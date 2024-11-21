const python_c = @import("python_c");
const PyObject = *python_c.PyObject;

const constructors = @import("constructors.zig");
const PythonFutureObject = constructors.PythonFutureObject;

const utils = @import("../../utils/utils.zig");


inline fn raise_cancel_exception(self: *PythonFutureObject) void {
    if (self.cancel_msg_py_object) |cancel_msg_py_object| {
        const msg = python_c.PyUnicode_AsUTF8(cancel_msg_py_object);
        python_c.PyErr_SetString(self.cancelled_error_exc.?, msg);
    }else{
        python_c.PyErr_SetRaisedException(self.cancelled_error_exc.?);
    }
}


pub fn future_result(self: ?*PythonFutureObject, _: ?PyObject) callconv(.C) ?PyObject {
    const instance = self.?;
    const obj = instance.future_obj.?;
    const mutex = &obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    const result: ?PyObject = switch (obj.status) {
        .PENDING => blk: {
            python_c.PyErr_SetString(instance.invalid_state_exc.?, "Result is not ready.\x00");
            break :blk null;
        },
        .FINISHED => blk: {
            if (instance.exception) |exc| {
                const new_exc = python_c.py_newref(exc);
                if (instance.exception_tb) |exception_tb| {
                    if (python_c.PyException_SetTraceback(new_exc, exception_tb) < 0) {
                        utils.put_python_runtime_error_message(
                            "An error ocurred setting traceback to python exception\x00"
                        );
                        break :blk null;
                    }
                }
                python_c.PyErr_SetRaisedException(new_exc);
                break :blk null;
            }
            break :blk @as(PyObject, @alignCast(@ptrCast(obj.result.?)));
        },
        .CANCELED => blk: {
            raise_cancel_exception(instance);
            break :blk null;
        }
    };

    return result;
}

pub fn future_exception(self: ?*PythonFutureObject, _: ?PyObject) callconv(.C) ?PyObject {
    const instance = self.?;
    const obj = instance.future_obj.?;
    const mutex = &obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    return switch (obj.status) {
        .PENDING => blk: {
            python_c.PyErr_SetString(instance.invalid_state_exc.?, "Exception is not set.\x00");
            break :blk null;
        },
        .FINISHED => blk: {
            if (instance.exception) |exc| {
                break :blk python_c.py_newref(exc);
            }
            break :blk python_c.get_py_none();
        },
        .CANCELED => blk: {
            raise_cancel_exception(instance);
            break :blk null;
        }
    };
}

inline fn z_future_set_exception(self: *PythonFutureObject, args: ?PyObject) !PyObject {
    const obj = self.future_obj.?;
    const mutex = &obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    switch (obj.status) {
        .FINISHED,.CANCELED => {
            python_c.PyErr_SetString(self.invalid_state_exc.?, "Exception already setted\x00");
            return error.PythonError;
        },
        else => {}
    }

    var exception: ?PyObject = null;
    if (python_c.PyArg_ParseTuple(args.?, "O:exception\x00", &exception) < 0) {
        return error.PythonError;
    }

    self.exception = python_c.py_newref(exception.?);
    errdefer python_c.py_decref_and_set_null(&self.exception);

    self.exception_tb = python_c.PyException_GetTraceback(exception.?);
    errdefer python_c.py_decref_and_set_null(&self.exception_tb);

    try obj.call_done_callbacks(.FINISHED);
    return python_c.get_py_none();
}

pub fn future_set_exception(self: ?*PythonFutureObject, args: ?PyObject) callconv(.C) ?PyObject {
    return utils.execute_zig_function(z_future_set_exception, .{self.?, args});
}

inline fn z_future_set_result(self: *PythonFutureObject, args: ?PyObject) !PyObject {
    const obj = self.future_obj.?;
    const mutex = &obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    switch (obj.status) {
        .FINISHED,.CANCELED => {
            python_c.PyErr_SetString(self.invalid_state_exc.?, "Result already setted\x00");
            return error.PythonError;
        },
        else => {}
    }

    var result: ?PyObject = undefined;
    if (python_c.PyArg_ParseTuple(args.?, "O:result\x00", &result) < 0) {
        return error.PythonError;
    }

    obj.result = python_c.py_newref(result.?);
    errdefer python_c.py_decref_and_set_null(@alignCast(@ptrCast(&obj.result)));

    try obj.call_done_callbacks(.FINISHED);
    return python_c.get_py_none();
}

pub fn future_set_result(self: ?*PythonFutureObject, args: ?PyObject) callconv(.C) ?PyObject {
    return utils.execute_zig_function(z_future_set_result, .{self.?, args});
}

pub fn future_done(self: ?*PythonFutureObject, _: ?PyObject) callconv(.C) ?PyObject {
    const instance = self.?;
    const obj = instance.future_obj.?;
    const mutex = &obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    return switch (obj.status) {
        .FINISHED,.CANCELED => python_c.get_py_true(),
        else => python_c.get_py_false()
    };
}
