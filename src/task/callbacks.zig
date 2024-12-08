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

pub fn handle_legacy_future_object(future: PyObject) CallbackManager.ExecuteCallbacksReturn {

}

pub fn handle_leviathan_future_object(
    task: *Task.constructors.PythonTaskObject,
    future: *Future.constructors.PythonFutureObject
) CallbackManager.ExecuteCallbacksReturn {
    
}

pub inline fn successfully_execution(task: *Task.constructors.PythonTaskObject, result: PyObject) CallbackManager.ExecuteCallbacksReturn {
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

pub inline fn failed_execution(task: *Task.constructors.PythonTaskObject) CallbackManager.ExecuteCallbacksReturn {
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
            const value: PyObject = python_c.PyObject_GetAttrString(exception, "value\x00") orelse return .Exception;
            if (utils.execute_zig_function(Future.result.future_fast_set_result, .{@ptrCast(&task.fut), value}) < 0) {
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


pub inline fn step_run_and_handle_result_task(task: *Task.constructors.PythonTaskObject, exc_value: ?PyObject) CallbackManager.ExecuteCallbacksReturn {
    const ret: ?PyObject = blk: {
        if (exc_value) |value| {
            defer python_c.py_decref(value);
            break :blk python_c.PyObject_CallOneArg(task.coro_throw.?, value);
        }else{
            break :blk python_c.PyObject_CallOneArg(task.coro_send.?, python_c.get_py_none());
        }
    };

    
    return .Continue;
}
