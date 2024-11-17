const std = @import("std");

const CallbackManager = @import("main.zig");

const python_c = @import("python_c");
const PyObject = *python_c.PyObject;

// const Future = @import("../../future/main.zig");
const Handle = @import("../handle.zig");

const utils = @import("../utils/utils.zig");

pub const GenericCallbackData = struct {
    args: []PyObject,
    exception_handler: PyObject,
    py_callback: PyObject,
    py_handle: *Handle.PythonHandleObject,
    cancelled: *bool,
};

pub const FutureCallbacksSetData = struct {
    sets_queue: *CallbackManager.CallbacksSetsQueue,
    future: PyObject,
};

pub const FutureCallbackData = struct {
    exception_handler: PyObject,
    contextvars: PyObject,
    py_callback: PyObject,
    py_future: PyObject,
    repeat: usize = 1,
    dec_future: bool = false
};

inline fn deal_with_result(result: ?PyObject, exception_handler: PyObject) CallbackManager.ExecuteCallbacksReturn {
    if (result) |value| {
        python_c.py_decref(value);
    }else{
        if (
            python_c.PyErr_ExceptionMatches(python_c.PyExc_SystemExit) > 0 or
            python_c.PyErr_ExceptionMatches(python_c.PyExc_KeyboardInterrupt) > 0
        ) {
            return .Exception;
        }

        const exception: PyObject = python_c.PyErr_GetRaisedException()
            orelse return .Exception;
        defer python_c.py_decref(exception);

        const exc_handler_ret: PyObject = python_c.PyObject_CallOneArg(exception_handler, exception)
            orelse return .Exception;
        python_c.py_decref(exc_handler_ret);
    }

    return .Continue;
}

pub inline fn release_python_generic_callback(allocator: std.mem.Allocator, data: GenericCallbackData) void {
    for (data.args) |arg| python_c.py_decref(arg);
    allocator.free(data.args);

    python_c.py_decref(data.py_callback);
    python_c.py_decref(@ptrCast(data.py_handle));
}

pub inline fn callback_for_python_generic_callbacks(
    allocator: std.mem.Allocator, data: GenericCallbackData
) CallbackManager.ExecuteCallbacksReturn {
    defer release_python_generic_callback(allocator, data);

    if (@atomicLoad(bool, data.cancelled, .monotonic)) {
        return .Continue;
    }

    const ret: ?PyObject = python_c.PyObject_Vectorcall(
        data.py_callback, data.args.ptr, @intCast(data.args.len), null
    );
    return deal_with_result(ret, data.exception_handler);
}

pub inline fn release_python_future_callback(data: FutureCallbackData) void {
    python_c.py_decref(data.contextvars);
    python_c.py_decref(data.py_callback);
    if (data.dec_future) python_c.py_decref(data.py_future);
}

pub inline fn callback_for_python_future_callbacks(data: FutureCallbackData) CallbackManager.ExecuteCallbacksReturn {
    defer release_python_future_callback(data);

    const py_callback = data.py_callback;
    const py_future = data.py_future;
    for (0..data.repeat) |_| {
        const ret: ?PyObject = python_c.PyObject_CallOneArg(py_callback, py_future);
        switch (deal_with_result(ret, data.exception_handler)) {
            .Continue => {},
            .Stop => return .Stop,
            .Exception => return .Exception
        }
    }

    return .Continue;
}

pub inline fn callback_for_python_future_set_callbacks(
    allocator: std.mem.Allocator, data: FutureCallbacksSetData, status: CallbackManager.ExecuteCallbacksReturn
) CallbackManager.ExecuteCallbacksReturn {
    defer python_c.py_decref(data.future);
    return CallbackManager.execute_callbacks(allocator, data.sets_queue, status, false);
}
