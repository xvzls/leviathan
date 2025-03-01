const python_c = @import("python_c");
const PyObject = *python_c.PyObject;

const utils = @import("../utils/utils.zig");

const CallbackManager = @import("../callback_manager.zig");

const Task = @import("main.zig");
const Future = @import("../future/main.zig");
const Loop = @import("../loop/main.zig");

const std = @import("std");

pub const Data = struct {
    task: *Task.PythonTaskObject,
    exc_value: ?PyObject = null
};


const LeviathanPyTaskWakeupMethod = python_c.PyMethodDef{
    .ml_name = "wake_up_task\x00",
    .ml_meth = @ptrCast(&py_wake_up),
    .ml_doc = "Wakeup the task.\x00",
    .ml_flags = python_c.METH_O
};

inline fn set_fut_waiter(
    task: *Task.PythonTaskObject, future: PyObject
) void {
    if (task.fut_waiter) |_| {
        @panic("task.fut_waiter is not null");
    }else{
        task.fut_waiter = python_c.py_newref(future);
    }
}

fn create_new_py_exception_and_add_event(
    loop: *Loop, allocator: std.mem.Allocator, comptime fmt: []const u8,
    task: *Task.PythonTaskObject,
    result: PyObject
) !void {
    const task_repr: PyObject = python_c.PyObject_Repr(@ptrCast(task)) orelse return error.PythonError;
    defer python_c.py_decref(task_repr);

    const result_repr: PyObject = python_c.PyObject_Repr(result) orelse return error.PythonError;
    defer python_c.py_decref(result_repr);

    const task_repr_unicode: [*c]const u8 = python_c.PyUnicode_AsUTF8(task_repr) orelse return error.PythonError;
    const result_repr_unicode: [*c]const u8 = python_c.PyUnicode_AsUTF8(result_repr) orelse return error.PythonError;

    const task_repr_unicode_len = std.mem.len(task_repr_unicode);
    const result_repr_unicode_len = std.mem.len(result_repr_unicode);

    const message = try std.fmt.allocPrint(
        allocator, fmt, .{
            task_repr_unicode[0..task_repr_unicode_len],
            result_repr_unicode[0..result_repr_unicode_len]
        }
    );
    defer allocator.free(message);

    const py_message: PyObject = python_c.PyUnicode_FromString(message.ptr) orelse return error.PythonError;
    defer python_c.py_decref(py_message);

    const exception = python_c.PyObject_CallOneArg(python_c.PyExc_RuntimeError, py_message)
        orelse return error.PythonError;
    errdefer python_c.py_decref(exception);

    const callback: CallbackManager.Callback = .{
        .PythonTask = .{
            .task = task,
            .exc_value = exception
        }
    };

    try Loop.Scheduling.Soon.dispatch(loop, callback);
    python_c.py_incref(@ptrCast(task));
} 

inline fn execute_zig_function(
    comptime function: anytype, args: anytype
) CallbackManager.ExecuteCallbacksReturn {
    @call(.auto, function, args) catch |err| {
        if (err != error.PythonError) {
            utils.put_python_runtime_error_message(@errorName(err));
        }
        return .Exception;
    };

    return .Continue;
}

inline fn cancel_future_object(
    task: *Task.PythonTaskObject, future: anytype
) CallbackManager.ExecuteCallbacksReturn {
    if (@TypeOf(future) == *Future.Python.FutureObject) {
        if (!Future.Python.Cancel.future_fast_cancel(future, task.fut.cancel_msg_py_object)) {
            return .Exception;
        }
    }else{
        const cancel_function: PyObject = python_c.PyObject_GetAttrString(
            future, "cancel\x00"
        );
        defer python_c.py_decref(cancel_function);

        const ret: PyObject = blk: {
            if (task.fut.cancel_msg_py_object) |msg| {
                break :blk python_c.PyObject_CallOneArg(cancel_function, msg) orelse {
                    return .Exception;
                };
            }else{
                break :blk python_c.PyObject_CallNoArgs(cancel_function) orelse {
                    return .Exception;
                };
            }
        };
        python_c.py_decref(ret);
    }

    return .Continue;
}

inline fn handle_legacy_future_object(
    task: *Task.PythonTaskObject, future: PyObject
) CallbackManager.ExecuteCallbacksReturn {
    const loop_data = utils.get_data_ptr(Loop, task.fut.py_loop.?);
    const allocator = loop_data.allocator;

    const asyncio_future_blocking: PyObject = python_c.PyObject_GetAttrString(
        future, "_asyncio_future_blocking\x00"
    ) orelse return .Exception;

    if (!python_c.type_check(asyncio_future_blocking, &python_c.PyBool_Type)) {
        return execute_zig_function(
            create_new_py_exception_and_add_event, .{
                loop_data, allocator, "Task {s} got bad yield: {s}\x00",
                task, asyncio_future_blocking
            }
        );
    }

    if (python_c.Py_IsTrue(asyncio_future_blocking) != 0) {
        const add_done_callback_func: PyObject = python_c.PyObject_GetAttrString(
            future, "add_done_callback\x00"
        ) orelse return .Exception;
        defer python_c.py_decref(add_done_callback_func);
        
        const wrapper: PyObject = python_c.PyCFunction_New(
            @constCast(&LeviathanPyTaskWakeupMethod), @ptrCast(task)
        ) orelse return .Exception;
        defer python_c.py_decref(wrapper);

        const ret: PyObject = python_c.PyObject_CallOneArg(add_done_callback_func, wrapper) orelse {
            return .Exception;
        };
        python_c.py_decref(ret);
        python_c.py_incref(@ptrCast(task));

        if (python_c.PyObject_SetAttrString(future, "_asyncio_future_blocking", python_c.get_py_false()) < 0) {
            return .Exception;
        }

        set_fut_waiter(task, future);
        if (task.must_cancel) {
            return cancel_future_object(task, future);
        }

        return .Continue;
    }

    return execute_zig_function(
        create_new_py_exception_and_add_event, .{
            loop_data, allocator, "Yield was used instead of yield from in Task {s} with Future {s}\x00",
            task, future
        }
    );
}

inline fn handle_leviathan_future_object(
    task: *Task.PythonTaskObject,
    future: *Future.Python.FutureObject,
    loop_data: *Loop
) CallbackManager.ExecuteCallbacksReturn {
    const allocator = loop_data.allocator;

    const future_data = utils.get_data_ptr(Future, future);
    const mutex = &future_data.mutex;

    mutex.lock();
    defer mutex.unlock();

    if (loop_data != utils.get_data_ptr(Loop, future.py_loop.?)) {
        return execute_zig_function(
            create_new_py_exception_and_add_event, .{
                loop_data, allocator, "Task {s} and Future {s} are not in the same loop\x00",
                task, @as(PyObject, @ptrCast(future))
            }
        );
    }

    if (future.blocking > 0) {
        if (@intFromPtr(future) == @intFromPtr(task)) {
            return execute_zig_function(
                create_new_py_exception_and_add_event, .{
                    loop_data, allocator, "Task {s} and Future {s} are the same object. Task cannot await on itself\x00",
                    task, @as(PyObject, @ptrCast(future))
                }
            );
        }

        const callback: CallbackManager.Callback = .{
            .ZigGeneric = .{
                .callback = &wakeup_task,
                .data = task
            }
        };

        const ret = execute_zig_function(
            Future.Callback.add_done_callback, .{future_data, callback}
        );
        if (ret == .Continue) {
            python_c.py_incref(@ptrCast(task));

            set_fut_waiter(task, @ptrCast(future));
            future.blocking = 0;

            if (task.must_cancel) {
                return cancel_future_object(task, future);
            }
        }

        return ret;
    }

    return execute_zig_function(
        create_new_py_exception_and_add_event, .{
            loop_data, allocator, "Yield was used instead of yield from in Task {s} with Future {s}\x00",
            task, @as(PyObject, @ptrCast(future))
        }
    );
}

inline fn successfully_execution(
    task: *Task.PythonTaskObject, loop_data: *Loop, result: PyObject
) CallbackManager.ExecuteCallbacksReturn {
    if (python_c.type_check(result, &Future.Python.FutureType)) {
        return handle_leviathan_future_object(task, @ptrCast(result), loop_data);
    }else if (python_c.is_none(result)) {
        const callback: CallbackManager.Callback = .{
            .PythonTask = .{
                .task = task
            }
        };

        Loop.Scheduling.Soon.dispatch(loop_data, callback) catch |err| {
            utils.put_python_runtime_error_message(@errorName(err));
            return .Exception;
        };

        python_c.py_incref(@ptrCast(task));
        return .Continue;
    }

    return handle_legacy_future_object(task, result);
}

inline fn failed_execution(
    task: *Task.PythonTaskObject,
    py_loop: *Loop.Python.LoopObject
) CallbackManager.ExecuteCallbacksReturn {
    const exc_match = python_c.PyErr_GivenExceptionMatches;

    const fut: *Future.Python.FutureObject = &task.fut;
    const future_data = utils.get_data_ptr(Future, fut);
    const exception: PyObject = python_c.PyErr_GetRaisedException() orelse return .Exception;
    defer python_c.py_decref(exception);

    const cancelled_error = py_loop.cancelled_error_exc.?;
    if (exc_match(exception, cancelled_error) > 0) {
        if (!Future.Python.Cancel.future_fast_cancel(fut, null)) {
            return .Exception;
        }
        return .Continue;
    }

    if (
        utils.execute_zig_function(
            Future.Python.Result.future_fast_set_exception, .{fut, future_data, exception}
        ) < 0 or
        exc_match(exception, python_c.PyExc_SystemExit) > 0 or
        exc_match(exception, python_c.PyExc_KeyboardInterrupt) > 0
    ) {
        python_c.PyErr_SetRaisedException(exception);
        return .Exception;
    }

    const exc_message: PyObject = python_c.PyUnicode_FromString("Exception ocurred executing Task\x00")
        orelse return .Exception;
    defer python_c.py_decref(exc_message);

    var args: [4]?PyObject = undefined;
    args[0] = exception;
    args[1] = exc_message;
    args[2] = task.coro.?;
    args[3] = @ptrCast(task);

    const message_kname: PyObject = python_c.PyUnicode_FromString("message\x00")
        orelse return .Exception;
    defer python_c.py_decref(message_kname);

    const callback_kname: PyObject = python_c.PyUnicode_FromString("callback\x00")
        orelse return .Exception;
    defer python_c.py_decref(callback_kname);

    const task_kname: PyObject = python_c.PyUnicode_FromString("task\x00")
        orelse return .Exception;
    defer python_c.py_decref(task_kname);

    const knames: PyObject = python_c.PyTuple_Pack(3, message_kname, callback_kname, task_kname)
        orelse return .Exception;
    defer python_c.py_decref(knames);

    const exception_handler = py_loop.exception_handler.?;
    const exc_handler_ret: PyObject = python_c.PyObject_Vectorcall(exception_handler, &args, 1, knames)
        orelse return .Exception;
    python_c.py_decref(exc_handler_ret);

    return .Continue;
}

inline fn release_python_task_callback(task: *Task.PythonTaskObject, exc_value: ?PyObject) void {
    python_c.py_decref(@ptrCast(task));
    python_c.py_xdecref(exc_value);
}

pub fn step_run_and_handle_result(
    task: *Task.PythonTaskObject, exc_value: ?PyObject
) CallbackManager.ExecuteCallbacksReturn {
    var exception_value: ?PyObject = exc_value;
    defer release_python_task_callback(task, exception_value);

    const py_fut = &task.fut;
    const py_loop = py_fut.py_loop.?;

    const loop_data = utils.get_data_ptr(Loop, py_loop);
    const future_data = utils.get_data_ptr(Future, py_fut);

    const mutex = &future_data.mutex;
    mutex.lock();
    defer mutex.unlock();

    if (future_data.status != .PENDING) {
        utils.put_python_runtime_error_message(
            "Task already finished\x00"
        );
        return failed_execution(task, py_loop);
    }

    if (task.must_cancel) {
        if (
            exception_value == null or
            python_c.type_check(exception_value.?, python_c.get_type(task.fut.cancelled_error_exc.?))
        ) {
            python_c.py_xdecref(exception_value);
            exception_value = blk: {
                if (task.fut.cancel_msg_py_object) |value| {
                    break :blk python_c.PyObject_CallOneArg(
                               task.fut.cancelled_error_exc.?, value
                           ) orelse return .Exception;
                }else{
                    break :blk python_c.PyObject_CallNoArgs(task.fut.cancelled_error_exc.?) orelse return .Exception;
                }
            };
        }
        task.must_cancel = false;
    }

    const enter_task_args: [2]?PyObject = .{
        @ptrCast(py_loop), @ptrCast(task)
    };

    const py_none = python_c.get_py_none();
    defer python_c.py_decref(py_none);

    var ret: PyObject = python_c.PyObject_Vectorcall(py_loop.enter_task_func.?, &enter_task_args, enter_task_args.len, null)
        orelse return .Exception;
    python_c.py_decref(ret);

    const new_status = blk: {
        mutex.unlock();
        defer mutex.lock();

        const context = task.py_context.?;
        if (python_c.PyContext_Enter(context) < 0) {
            return .Exception;
        }

        var coro_ret: ?PyObject = null;
        const gen_ret: python_c.PySendResult = blk2: {
            if (exception_value) |value| {
                if (python_c.PyObject_CallOneArg(task.coro_throw.?, value)) |v| {
                    coro_ret = v;
                    break :blk2 python_c.PYGEN_RETURN;
                }
                break :blk2 python_c.PYGEN_ERROR;
            }else{
                break :blk2 python_c.PyIter_Send(task.coro.?, py_none, &coro_ret);
            }
        };

        if (python_c.PyContext_Exit(context) < 0) {
            python_c.py_xdecref(coro_ret);
            return .Exception;
        }

        switch (gen_ret) {
            python_c.PYGEN_RETURN => {
                if (task.must_cancel) {
                    if (!Future.Python.Cancel.future_fast_cancel(&task.fut, task.fut.cancel_msg_py_object)) {
                        break :blk .Exception;
                    }
                    break :blk .Continue;
                }else{
                    break :blk execute_zig_function(
                               Future.Python.Result.future_fast_set_result, .{future_data, coro_ret.?}
                           );
                }
            },
            python_c.PYGEN_ERROR => break :blk failed_execution(task, py_loop),
            else => {
                if (coro_ret) |result| {
                    defer python_c.py_decref(result);
                    break :blk successfully_execution(task, loop_data, result);
                }
                break :blk failed_execution(task, py_loop);
            }
        }
    };

    ret = python_c.PyObject_Vectorcall(py_loop.leave_task_func.?, &enter_task_args, enter_task_args.len, null)
        orelse return .Exception;
    python_c.py_decref(ret);

    return new_status;
}

fn wakeup_task(
    data: ?*anyopaque, status: CallbackManager.ExecuteCallbacksReturn
) CallbackManager.ExecuteCallbacksReturn {
    const task: *Task.PythonTaskObject = @alignCast(@ptrCast(data.?));

    if (status != .Continue) {
        python_c.py_decref(@ptrCast(task));
        return status;
    }

    python_c.py_incref(@ptrCast(task));
    defer python_c.py_decref(@ptrCast(task));

    var exc_value: ?PyObject = null;
    const py_future = task.fut_waiter.?;
    task.fut_waiter = null;

    defer python_c.py_decref(py_future);

    if (python_c.type_check(py_future, &Future.Python.FutureType)) {
        const leviathan_fut: *Future.Python.FutureObject = @alignCast(@ptrCast(py_future));
        if (leviathan_fut.exception) |exception| {
            exc_value = python_c.py_newref(exception);
        }
    }else{
        // Third party future
        const get_result_func: PyObject = python_c.PyObject_GetAttrString(py_future, "result\x00")
            orelse return .Exception;
        defer python_c.py_decref(get_result_func);

        const ret: ?PyObject = python_c.PyObject_CallNoArgs(get_result_func);
        if (ret) |result| {
            python_c.py_decref(result);
        }else{
            exc_value = python_c.PyErr_GetRaisedException() orelse return .Exception;
        }
    }

    return step_run_and_handle_result(task, exc_value);
}

fn py_wake_up(
    self: ?*Task.PythonTaskObject, fut: ?PyObject
) ?PyObject {
    _ = fut.?;
    const ret: CallbackManager.ExecuteCallbacksReturn = @call(.always_inline, wakeup_task, .{self, .Continue});
    return switch (ret) {
        .Continue => python_c.get_py_none(),
        .Stop => blk: {
            utils.put_python_runtime_error_message("Stop signal received\x00");
            break :blk null;
        },
        .Exception => null,
        else => unreachable
    };
}
