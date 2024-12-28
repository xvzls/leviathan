const std = @import("std");

const python_c = @import("python_c");
const PyObject = *python_c.PyObject;

const Future = @import("../main.zig");
const PythonFutureObject = Future.FutureObject;

const utils = @import("../../utils/utils.zig");

pub inline fn future_fast_cancel(instance: *PythonFutureObject, cancel_msg_py_object: ?PyObject) bool {
    if (cancel_msg_py_object) |pyobj| {
        if (python_c.PyUnicode_Check(pyobj) == 0) {
            python_c.PyErr_SetString(python_c.PyExc_TypeError.?, "Cancel message must be a string\x00");
            return false;
        }

        instance.cancel_msg_py_object = python_c.py_newref(pyobj);
    }

    const future_data = utils.get_data_ptr(Future, instance);
    future_data.call_done_callbacks(.CANCELED) catch |err| {
        const err_trace = @errorReturnTrace();
        utils.print_error_traces(err_trace, err);
        utils.put_python_runtime_error_message(@errorName(err));
        return false;
    };

    return true;
}

pub fn future_cancel(self: ?*PythonFutureObject, args: ?PyObject, kwargs: ?PyObject) callconv(.C) ?PyObject {
    const instance = self.?;

    const future_data = utils.get_data_ptr(Future, instance);
    const mutex = &future_data.mutex;
    mutex.lock();
    defer mutex.unlock();

    switch (future_data.status) {
        .FINISHED,.CANCELED => return python_c.get_py_false(),
        else => {}
    }

    var kwlist: [2][*c]u8 = undefined;
    kwlist[0] = @constCast("msg\x00");
    kwlist[1] = null;

    var cancel_msg_py_object: ?PyObject = null;

    if (
        python_c.PyArg_ParseTupleAndKeywords(
            args, kwargs, "|O:msg\x00", @ptrCast(&kwlist), &cancel_msg_py_object
        ) < 0
    ) {
        return null;
    }

    if (!future_fast_cancel(instance, cancel_msg_py_object)) {
        return null;
    }

    return python_c.get_py_true();
}

pub fn future_cancelled(self: ?*PythonFutureObject, _: ?PyObject) callconv(.C) ?PyObject {
    const future_data = utils.get_data_ptr(Future, self.?);
    const mutex = &future_data.mutex;
    mutex.lock();
    defer mutex.unlock();

    return switch (future_data.status) {
        .CANCELED => python_c.get_py_true(),
        else => python_c.get_py_false()
    };
}
