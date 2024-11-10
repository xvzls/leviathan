const python_c = @import("../../utils/python_c.zig");
const PyObject = *python_c.PyObject;

// const Future = @import("../../future/main.zig");
const Handle = @import("../../handle.zig");

const utils = @import("../../utils/utils.zig");
const allocator = utils.allocator;

pub const GenericCallbackData = struct {
    args: []PyObject,
    exception_handler: PyObject,
    py_callback: PyObject,
    py_handle: *Handle.PythonHandleObject,
    cancelled: *bool,
};

pub const FutureCallbackData = struct {
    exception_handler: PyObject,
    contextvars: PyObject,
    py_callback: PyObject,
    py_future: PyObject, // TODO
    repeat: usize
};

inline fn deal_with_result(result: ?PyObject, exception_handler: PyObject) bool {
    if (result) |value| {
        python_c.py_decref(value);
    }else{
        if (
            python_c.PyErr_ExceptionMatches(python_c.PyExc_SystemExit) > 0 or
            python_c.PyErr_ExceptionMatches(python_c.PyExc_KeyboardInterrupt) > 0
        ) {
            return true;
        }

        const exception: PyObject = python_c.PyErr_GetRaisedException()
            orelse return true;
        defer python_c.py_decref(exception);

        const exc_handler_ret: PyObject = python_c.PyObject_CallOneArg(exception_handler, exception)
            orelse return true;
        python_c.py_decref(exc_handler_ret);
    }

    return false;
}

pub inline fn release_python_generic_callback(data: GenericCallbackData) void {
    for (data.args) |arg| python_c.py_decref(arg);
    allocator.free(data.args);

    python_c.py_decref(data.py_callback);
    python_c.py_decref(@ptrCast(data.py_handle));
}

pub inline fn callback_for_python_generic_callbacks(data: GenericCallbackData) bool {
    defer release_python_generic_callback(data);

    if (@atomicLoad(bool, data.cancelled, .monotonic)) {
        return false;
    }

    const ret: ?PyObject = python_c.PyObject_Vectorcall(
        data.py_callback, data.args.ptr, @intCast(data.args.len), null
    );
    return deal_with_result(ret, data.exception_handler);
}

pub inline fn release_python_future_callback(data: FutureCallbackData) void {
    python_c.py_decref(data.contextvars);
    python_c.py_decref(data.py_callback);
}

pub inline fn callback_for_python_future_callbacks(data: FutureCallbackData) bool {
    defer release_python_future_callback(data);

    const py_callback = data.py_callback;
    const py_future = data.py_future;
    for (0..data.repeat) |_| {
        const ret: ?PyObject = python_c.PyObject_CallOneArg(py_callback, py_future);
        if (deal_with_result(ret, data.exception_handler)) return true;
    }

    return false;
}
