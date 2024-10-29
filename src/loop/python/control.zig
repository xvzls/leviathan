const python_c = @import("../../utils/python_c.zig");
const PyObject = *python_c.PyObject;

const utils = @import("../../utils/utils.zig");
const allocator = utils.allocator;

const Loop = @import("../main.zig");

const constructors = @import("constructors.zig");
const PythonLoopObject = constructors.PythonLoopObject;
const LEVIATHAN_LOOP_MAGIC = constructors.LEVIATHAN_LOOP_MAGIC;


pub fn loop_run_forever(self: ?*PythonLoopObject, _: ?PyObject) callconv(.C) ?PyObject {
    const instance = self.?;
    if (utils.check_leviathan_python_object(instance, LEVIATHAN_LOOP_MAGIC)) {
        return null;
    }

    const loop_obj = instance.loop_obj.?;
    const mutex = &loop_obj.mutex;
    {
        mutex.lock();
        defer mutex.unlock();

        if (loop_obj.closed) {
            utils.put_python_runtime_error_message("Loop is closed\x00");
            return null;
        }

        if (loop_obj.stopping) {
            utils.put_python_runtime_error_message("Loop is stopping\x00");
            return null;
        }

        if (loop_obj.running) {
            utils.put_python_runtime_error_message("Loop is already running\x00");
            return null;
        }

        loop_obj.running = true;
        loop_obj.stopping = false;
    }

    while (loop_obj.call_once()) {}

    mutex.lock();
    loop_obj.running = false;
    loop_obj.stopping = false;
    mutex.unlock();
}


pub fn loop_stop(self: ?*PythonLoopObject, _: ?PyObject) callconv(.C) ?PyObject {
    const instance = self.?;
    if (utils.check_leviathan_python_object(instance, LEVIATHAN_LOOP_MAGIC)) {
        return null;
    }

    const loop_obj = instance.loop_obj.?;

    const mutex = &loop_obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    loop_obj.stopping = true;
    return python_c.get_py_none();
}

pub fn loop_is_running(self: ?*PythonLoopObject, _: ?PyObject) callconv(.C) ?PyObject {
    const instance = self.?;
    if (utils.check_leviathan_python_object(instance, LEVIATHAN_LOOP_MAGIC)) {
        return null;
    }

    const loop_obj = instance.loop_obj.?;
    const mutex = &loop_obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    return python_c.PyBool_FromLong(@intCast(@intFromBool(loop_obj.running)));
}

pub fn loop_is_closed(self: ?*PythonLoopObject, _: ?PyObject) callconv(.C) ?PyObject {
    const instance = self.?;
    if (utils.check_leviathan_python_object(instance, LEVIATHAN_LOOP_MAGIC)) {
        return null;
    }

    const loop_obj = instance.loop_obj.?;

    const mutex = &loop_obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    return python_c.PyBool_FromLong(@intCast(@intFromBool(loop_obj.closed)));
}

pub fn loop_close(self: ?*PythonLoopObject, _: ?PyObject) callconv(.C) ?PyObject {
    const instance = self.?;
    if (utils.check_leviathan_python_object(instance, LEVIATHAN_LOOP_MAGIC)) {
        return null;
    }

    const loop_obj = instance.loop_obj.?;

    const mutex = &loop_obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    if (loop_obj.running) {
        utils.put_python_runtime_error_message("Loop is running\x00");
        return null;
    }

    loop_obj.closed = true;
    return python_c.get_py_none();
}
