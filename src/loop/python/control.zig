const python_c = @import("python_c");
const PyObject = *python_c.PyObject;

const utils = @import("../../utils/utils.zig");

const Loop = @import("../main.zig");

const constructors = @import("constructors.zig");
const PythonLoopObject = constructors.PythonLoopObject;

const CallbackManager = @import("../../callback_manager.zig");

const std = @import("std");


pub fn loop_run_forever(self: ?*PythonLoopObject, _: ?PyObject) callconv(.C) ?PyObject {
    const loop_obj = self.?.loop_obj.?;
    loop_obj.run_forever() catch return null;

    return python_c.get_py_none();
}


pub fn loop_stop(self: ?*PythonLoopObject, _: ?PyObject) callconv(.C) ?PyObject {
    const loop_obj = self.?.loop_obj.?;

    const mutex = &loop_obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    loop_obj.stopping = true;
    return python_c.get_py_none();
}

pub fn loop_is_running(self: ?*PythonLoopObject, _: ?PyObject) callconv(.C) ?PyObject {
    const loop_obj = self.?.loop_obj.?;
    const mutex = &loop_obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    return python_c.PyBool_FromLong(@intCast(@intFromBool(loop_obj.running)));
}

pub fn loop_is_closed(self: ?*PythonLoopObject, _: ?PyObject) callconv(.C) ?PyObject {
    const loop_obj = self.?.loop_obj.?;

    const mutex = &loop_obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    return python_c.PyBool_FromLong(@intCast(@intFromBool(loop_obj.closed)));
}

pub fn loop_close(self: ?*PythonLoopObject, _: ?PyObject) callconv(.C) ?PyObject {
    const loop_obj = self.?.loop_obj.?;

    const mutex = &loop_obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    if (loop_obj.running) {
        utils.put_python_runtime_error_message("Loop is running\x00");
        return null;
    }

    const allocator = loop_obj.allocator;
    for (&loop_obj.ready_tasks_queues) |*ready_tasks_queue| {
        _  = CallbackManager.execute_callbacks(allocator, ready_tasks_queue, .Stop, false);
    }

    loop_obj.closed = true;
    return python_c.get_py_none();
}
