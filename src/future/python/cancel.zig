const std = @import("std");
const python_c = @import("../../utils/python_c.zig");
const PyObject = *python_c.PyObject;

const constructors = @import("constructors.zig");
const PythonFutureObject = constructors.PythonFutureObject;
const LEVIATHAN_FUTURE_MAGIC = constructors.LEVIATHAN_FUTURE_MAGIC;

const utils = @import("../../utils/utils.zig");

pub fn future_cancel(self: ?*PythonFutureObject, args: ?PyObject, kwargs: ?PyObject) callconv(.C) ?PyObject {
    const instance = self.?;

    const obj = instance.future_obj.?;
    const mutex = &obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    switch (obj.status) {
        .FINISHED,.CANCELED => return python_c.get_py_false(),
        else => {}
    }
    const cancel_msg_py_object = args.?;

    var kwlist: [2][*c]u8 = undefined;
    kwlist[0] = @constCast("msg\x00");
    kwlist[1] = null;

    var cancel_msg: ?[*:0]u8 = null;

    if (python_c.PyArg_ParseTupleAndKeywords(args, kwargs, "|s:msg\x00", @ptrCast(&kwlist), &cancel_msg) < 0) {
        return null;
    }

    instance.cancel_msg_py_object = cancel_msg_py_object;
    instance.cancel_msg = cancel_msg;
    obj.status = .CANCELED;
    return python_c.get_py_true();
}

pub fn future_cancelled(self: ?*PythonFutureObject, _: ?PyObject) callconv(.C) ?PyObject {
    const instance = self.?;

    const obj = instance.future_obj.?;
    const mutex = &obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    return switch (obj.status) {
        .CANCELED => python_c.get_py_true(),
        else => python_c.get_py_false()
    };
}

