const python_c = @import("python_c");
const PyObject = *python_c.PyObject;

const utils = @import("../utils/utils.zig");

const CallbackManager = @import("../callback_manager.zig");

const Task = @import("main.zig");
const Future = @import("../future/main.zig");
const Loop = @import("../loop/main.zig");

const std = @import("std");
const builtin = @import("builtin");

pub const TaskCallbackData = struct {
    task: *Task.constructors.PythonTaskObject,
    exc_value: ?PyObject = null
};


fn create_new_runtime_error_message_and_add_event(
    loop: *Loop, allocator: std.mem.Allocator, comptime fmt: []const u8,
    task: *Task.constructors.PythonTaskObject,
    result: PyObject
) !void {
    const task_repr: ?PyObject = python_c.PyObject_Repr(task) orelse return error.PythonError;
    defer python_c.py_decref(task_repr);

    const result_repr: ?PyObject = python_c.PyObject_Repr(result) orelse return error.PythonError;
    defer python_c.py_decref(result_repr);

    const task_repr_unicode: [*c]u8 = python_c.PyUnicode_AsUTF8(task_repr) orelse return error.PythonError;
    const result_repr_unicode: [*c]u8 = python_c.PyUnicode_AsUTF8(result_repr) orelse return error.PythonError;

    const task_repr_unicode_len = std.mem.len(task_repr_unicode);
    const result_repr_unicode_len = std.mem.len(result_repr_unicode);

    const message = try std.fmt.allocPrint(
        allocator, fmt, .{
            task_repr_unicode[0..task_repr_unicode_len],
            result_repr_unicode[0..result_repr_unicode_len]
        }
    );
    defer allocator.free(message);

    const py_message: ?PyObject = python_c.PyUnicode_FromString(message.ptr) orelse return error.PythonError;
    defer python_c.py_decref(py_message);

    const exception = python_c.PyObject_CallOneArg(python_c.PyExc_RuntimeError, task_repr)
        orelse return error.PythonError;
    errdefer python_c.py_decref(exception);

    const callback = .{
        .PythonTask = .{
            .task = task,
            .exc_value = exception
        }
    };

    if (builtin.single_threaded) {
        try loop.call_soon(callback);
    }else{
        try loop.call_soon_threadsafe(callback);
    }
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

inline fn handle_legacy_future_object(
    task: *Task.constructors.PythonTaskObject, future: PyObject
) CallbackManager.ExecuteCallbacksReturn {
    const loop = task.fut.py_loop.?.loop_obj.?;
    const allocator = loop.allocator;

    const asyncio_future_blocking: ?PyObject = python_c.PyObject_GetAttrString(
        future, "_asyncio_future_blocking\x00"
    ) orelse return .Exception;

    if (python_c.PyBool_Check(asyncio_future_blocking) == 0) {
        return execute_zig_function(
            create_new_runtime_error_message_and_add_event, .{
                loop, allocator, "Task {s} got bad yield: {s}\x00",
                task, future
            }
        );
    }

    if (python_c.Py_IsTrue(asyncio_future_blocking)) {
        const add_done_callback_func: PyObject = python_c.PyObject_GetAttrString(
            future, "add_done_callback\x00"
        ) orelse return .Exception;

        const callback: CallbackManager.Callback = .{
            .ZigGeneric = .{
                .callback = &wakeup_task,
                .data = task
            }
        };

        const ret = execute_zig_function(
            future.future_obj.?.add_done_callback, .{callback}
        );
        if (ret == .Continue) {
            python_c.py_incref(@ptrCast(task));

            python_c.py_decref(task.fut_waiter.?);
            task.fut_waiter = python_c.py_newref(future);
        }

        return ret;
    }

    return execute_zig_function(
        create_new_runtime_error_message_and_add_event, .{
            loop, allocator, "Yield was used instead of yield from in Task {s} with Future {s}\x00",
            task, future
        }
    );
}

inline fn handle_leviathan_future_object(
    task: *Task.constructors.PythonTaskObject,
    future: *Future.constructors.PythonFutureObject
) CallbackManager.ExecuteCallbacksReturn {
    const loop = task.fut.py_loop.?.loop_obj.?;
    const allocator = loop.allocator;

    if (loop != future.py_loop.?.loop_obj.?) {
        return execute_zig_function(
            create_new_runtime_error_message_and_add_event, .{
                loop, allocator, "Task {s} and Future {s} are not in the same loop\x00",
                task, future
            }
        );
    }

    if (task.fut.blocking > 0) {
        if (future == task) {
            return execute_zig_function(
                create_new_runtime_error_message_and_add_event, .{
                    loop, allocator, "Task {s} and Future {s} are the same object. Task cannot await on itself\x00",
                    task, future
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
            future.future_obj.?.add_done_callback, .{callback}
        );
        if (ret == .Continue) {
            python_c.py_incref(@ptrCast(task));

            python_c.py_decref(task.fut_waiter.?);
            task.fut_waiter = python_c.py_newref(future);
        }

        return ret;
    }

    return execute_zig_function(
        create_new_runtime_error_message_and_add_event, .{
            loop, allocator, "Yield was used instead of yield from in Task {s} with Future {s}\x00",
            task, future
        }
    );
}

inline fn successfully_execution(
    task: *Task.constructors.PythonTaskObject, result: PyObject
) CallbackManager.ExecuteCallbacksReturn {
    if (python_c.PyObject_TypeCheck(result, &Future.PythonFutureType) != 0) {
        return handle_leviathan_future_object(task, @ptrCast(result));
    }else if (python_c.Py_IsNone(result) != 0) {
        const loop = task.fut.py_loop.?.loop_obj.?;

        const callback: CallbackManager.Callback = .{
            .PythonTask = .{
                .task = task
            }
        };
        if (builtin.single_threaded) {
            loop.call_soon(callback) catch |err| {
                utils.put_python_runtime_error_message(@errorName(err));
                return .Exception;
            };
        }else{
            loop.call_soon_threadsafe(callback) catch |err| {
                utils.put_python_runtime_error_message(@errorName(err));
                return .Exception;
            };
        }
        return .Continue;
    }

    return handle_legacy_future_object(task, result);
}

inline fn failed_execution(task: *Task.constructors.PythonTaskObject) CallbackManager.ExecuteCallbacksReturn {
    const exc_match = python_c.PyErr_ExceptionMatches;

    const fut: *Future.constructors.PythonFutureObject = &task.fut;
    const exception = python_c.PyErr_GetRaisedException() orelse return .Exception;
    defer python_c.py_decref(exception);

    if (exc_match(python_c.PyExc_StopIteration) > 0) {
        if (task.must_cancel) {
            if (!Future.cancel.future_fast_cancel(fut, fut.future_obj.?, fut.cancel_msg_py_object)) {
                return .Exception;
            }
        }else{
            const value: PyObject = python_c.PyObject_GetAttrString(exception, "value\x00")
                orelse return .Exception;
            if (
                utils.execute_zig_function(
                    Future.result.future_fast_set_result, .{@ptrCast(&task.fut), value}
                ) < 0
            ) {
                return .Exception;
            }
        }

        return .Continue;
    }

    const cancelled_error = task.fut.py_loop.?.cancelled_error_exc.?;
    if (exc_match(cancelled_error) > 0) {
        if (!Future.cancel.future_fast_cancel(fut, fut.future_obj.?, null)) {
            return .Exception;
        }
        return .Continue;
    }

    if (
        Future.result.future_fast_set_exception(fut, fut.future_obj.?, exception) < 0 or
        exc_match(python_c.PyExc_SystemExit) > 0 or
        exc_match(python_c.PyExc_KeyboardInterrupt) > 0
    ) {
        return .Exception;
    }

    return .Continue;
}

pub fn step_run_and_handle_result_task(task: *Task.constructors.PythonTaskObject, exc_value: ?PyObject) CallbackManager.ExecuteCallbacksReturn {
    const ret: ?PyObject = blk: {
        if (exc_value) |value| {
            defer python_c.py_decref(value);
            break :blk python_c.PyObject_CallOneArg(task.coro_throw.?, value);
        }else{
            break :blk python_c.PyObject_CallOneArg(task.coro_send.?, python_c.get_py_none());
        }
    };

    if (ret) |result| {

    }

    return failed_execution(task);
}

fn wakeup_task(
    data: ?*anyopaque, status: CallbackManager.ExecuteCallbacksReturn
) CallbackManager.ExecuteCallbacksReturn {
    const task: *Task.constructors.PythonTaskObject = @alignCast(@ptrCast(data.?));
    defer python_c.py_decref(task);

    if (status != .Continue) return status;

    var exc_value: ?PyObject = null;
    const py_future = task.fut_waiter.?;
    defer {
        python_c.py_decref(py_future);
        task.fut_waiter = python_c.get_py_none();
    }

    if (python_c.PyObject_TypeCheck(py_future, &Future.PythonFutureType) != 0) {
        const leviathan_fut: *Future.constructors.PythonFutureObject = @alignCast(@ptrCast(py_future));
        const fut = leviathan_fut.future_obj.?;
        if (fut.exception) |exception| {
            if (python_c.Py_IsNone(exception) == 0) {
                exc_value = python_c.py_newref(exception);
            }
        }
    }else{
        // Third party future
        const get_result_func: PyObject = python_c.PyObject_GetAttrString(py_future, "result\x00")
            orelse return .Exception;
        defer python_c.py_decref(get_result_func);

        const ret = python_c.PyObject_CallNoArgs(get_result_func);
        if (ret) |result| {
            python_c.py_decref(result);
        }else{
            exc_value = python_c.PyErr_GetRaisedException() orelse return .Exception;
        }
    }

    return step_run_and_handle_result_task(task, exc_value);
}
