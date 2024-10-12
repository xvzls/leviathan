const std = @import("std");
const python_c = @import("../../utils/python_c.zig");
const PyObject = *python_c.PyObject;

const constructors = @import("constructors.zig");
const PythonFutureObject = constructors.PythonFutureObject;
const LEVIATHAN_FUTURE_MAGIC = constructors.LEVIATHAN_FUTURE_MAGIC;

const utils = @import("../../utils/utils.zig");

pub fn future_cancel(self: ?*PythonFutureObject, args: ?PyObject) callconv(.C) ?PyObject {
    const instance = self.?;
    if (utils.check_leviathan_python_object(instance, LEVIATHAN_FUTURE_MAGIC)) {
        return null;
    }

    const obj = instance.future_obj;
    const mutex = &obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    return switch (obj.status) {
        .FINISHED,.CANCELED => python_c.get_py_false(),
        else => blk: {
            const cancel_msg_py_object = args.?;
            var cancel_msg: ?[*:0]u8 = null;
            if (python_c.PyArg_ParseTuple(cancel_msg_py_object, "|s:msg\x00", &cancel_msg) < 0) {
                break :blk null;
            }
            instance.cancel_msg_py_object = cancel_msg_py_object;
            instance.cancel_msg = cancel_msg;
            obj.status = .CANCELED;
            break :blk python_c.get_py_true();
        }
    };
}

pub fn future_cancelled(self: ?*PythonFutureObject, _: ?PyObject) callconv(.C) ?PyObject {
    const instance = self.?;
    if (utils.check_leviathan_python_object(instance, LEVIATHAN_FUTURE_MAGIC)) {
        return null;
    }

    const obj = instance.future_obj;
    const mutex = &obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    return switch (obj.status) {
        .CANCELED => python_c.get_py_true(),
        else => python_c.get_py_false()
    };
}

