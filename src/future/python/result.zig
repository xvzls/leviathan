const python_c = @import("../../utils/python_c.zig");
const PyObject = *python_c.PyObject;

const constructors = @import("constructors.zig");
const PythonFutureObject = constructors.PythonFutureObject;
const LEVIATHAN_FUTURE_MAGIC = constructors.LEVIATHAN_FUTURE_MAGIC;

const utils = @import("../../utils/utils.zig");


inline fn raise_cancel_exception(self: *PythonFutureObject) void {
    if (self.cancel_msg) |msg| {
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
                if (python_c.PyException_SetTraceback(exc, instance.exception_tb.?) < 0) {
                    utils.put_python_runtime_error_message(
                        "An error ocurred setting traceback to python exception\x00"
                    );
                }else{
                    python_c.PyErr_SetRaisedException(exc);
                }

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
                break :blk python_c.Py_NewRef(exc);
            }
            break :blk null;
        },
        .CANCELED => blk: {
            raise_cancel_exception(instance);
            break :blk null;
        }
    };
}

pub fn future_set_exception(self: ?*PythonFutureObject, args: ?PyObject) callconv(.C) ?PyObject {
    const instance = self.?;
    const obj = instance.future_obj.?;
    const mutex = &obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    switch (obj.status) {
        .FINISHED,.CANCELED => {
            python_c.PyErr_SetString(instance.invalid_state_exc.?, "Exception already setted\x00");
            return null;
        },
        else => {}
    }

    var exception: ?PyObject = null;
    if (python_c.PyArg_ParseTuple(args.?, "O:exception\x00", &exception) < 0) {
        return null;
    }

    instance.exception = python_c.Py_NewRef(exception.?) orelse return null;
    obj.call_done_callbacks(false) catch unreachable;

    return python_c.get_py_none();
}

pub fn future_set_result(self: ?*PythonFutureObject, args: ?PyObject) callconv(.C) ?PyObject {
    const instance = self.?;
    const obj = instance.future_obj.?;
    const mutex = &obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    switch (obj.status) {
        .FINISHED,.CANCELED => {
            python_c.PyErr_SetString(instance.invalid_state_exc.?, "Result already setted\x00");
            return null;
        },
        else => {}
    }

    var result: PyObject = undefined;
    if (python_c.PyArg_ParseTuple(args.?, "O:result\x00", &result) < 0) {
        return null;
    }

    obj.result = python_c.Py_NewRef(result) orelse return null;
    obj.call_done_callbacks(false) catch unreachable;

    return python_c.get_py_none();
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
