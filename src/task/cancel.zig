const python_c = @import("python_c");
const PyObject = *python_c.PyObject;

const utils = @import("../utils/utils.zig");

const Future = @import("../future/main.zig");
const Task = @import("main.zig");
const PythonTaskObject = Task.PythonTaskObject;

pub fn task_cancel(self: ?*PythonTaskObject, args: ?PyObject, kwargs: ?PyObject) callconv(.C) ?PyObject {
    const instance = self.?;

    const future_data = utils.get_data_ptr(Future, &instance.fut);
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

    if (cancel_msg_py_object) |pyobj| {
        if (python_c.PyUnicode_Check(pyobj) == 0) {
            python_c.PyErr_SetString(python_c.PyExc_TypeError.?, "Cancel message must be a string\x00");
            return null;
        }

        python_c.py_xdecref(instance.fut.cancel_msg_py_object);
        instance.fut.cancel_msg_py_object = python_c.py_newref(pyobj);
    }

    instance.cancel_requests +|= 1;
    instance.must_cancel = true;
    return python_c.get_py_true();
}

pub fn task_uncancel(self: ?*PythonTaskObject) callconv(.C) ?PyObject {
    const instance = self.?;
    const future_data = utils.get_data_ptr(Future, &instance.fut);

    const mutex = &future_data.mutex;
    mutex.lock();
    defer mutex.unlock();

    const new_cancel_requests = instance.cancel_requests -| 1;
    instance.cancel_requests = new_cancel_requests;
    instance.must_cancel = (new_cancel_requests > 0);
    return python_c.PyLong_FromUnsignedLongLong(@intCast(new_cancel_requests));
}

pub fn task_cancelling(self: ?*PythonTaskObject) callconv(.C) ?PyObject {
    const instance = self.?;

    const future_data = utils.get_data_ptr(Future, &instance.fut);
    const mutex = &future_data.mutex;
    mutex.lock();
    defer mutex.unlock();

    return switch (future_data.status) {
        .CANCELED,.FINISHED => python_c.PyLong_FromUnsignedLongLong(0),
        else => python_c.PyLong_FromUnsignedLongLong(@intCast(instance.cancel_requests))
    };
}
