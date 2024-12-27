const python_c = @import("python_c");
const PyObject = *python_c.PyObject;

const utils = @import("../../utils/utils.zig");

const Loop = @import("../main.zig");
const PythonLoopObject = Loop.PythonLoopObject;

const CallbackManager = @import("../../callback_manager.zig");

const std = @import("std");

// pub fn loop_run_until_complete(self: ?*PythonLoopObject, _: ?PyObject) callconv(.C) ?PyObject {
    
// }

pub fn loop_run_forever(self: ?*PythonLoopObject, _: ?PyObject) callconv(.C) ?PyObject {
    const loop_data = utils.get_data_ptr(Loop, self.?);
    loop_data.run_forever() catch return null;

    return python_c.get_py_none();
}

pub fn loop_stop(self: ?*PythonLoopObject, _: ?PyObject) callconv(.C) ?PyObject {
    const loop_data = utils.get_data_ptr(Loop, self.?);

    const mutex = &loop_data.mutex;
    mutex.lock();
    defer mutex.unlock();

    loop_data.stopping = true;
    return python_c.get_py_none();
}

pub fn loop_is_running(self: ?*PythonLoopObject, _: ?PyObject) callconv(.C) ?PyObject {
    const loop_data = utils.get_data_ptr(Loop, self.?);
    const mutex = &loop_data.mutex;
    mutex.lock();
    defer mutex.unlock();

    return python_c.PyBool_FromLong(@intCast(@intFromBool(loop_data.running)));
}

pub fn loop_is_closed(self: ?*PythonLoopObject, _: ?PyObject) callconv(.C) ?PyObject {
    const loop_data = utils.get_data_ptr(Loop, self.?);

    const mutex = &loop_data.mutex;
    mutex.lock();
    defer mutex.unlock();

    return python_c.PyBool_FromLong(@intCast(@intFromBool(loop_data.closed)));
}

pub fn loop_close(self: ?*PythonLoopObject, _: ?PyObject) callconv(.C) ?PyObject {
    const loop_data = utils.get_data_ptr(Loop, self.?);

    const mutex = &loop_data.mutex;
    mutex.lock();
    defer mutex.unlock();

    if (loop_data.running) {
        utils.put_python_runtime_error_message("Loop is running\x00");
        return null;
    }

    const allocator = loop_data.allocator;
    for (&loop_data.ready_tasks_queues) |*ready_tasks_queue| {
        _  = CallbackManager.execute_callbacks(allocator, ready_tasks_queue, .Stop, false);
    }

    loop_data.closed = true;
    return python_c.get_py_none();
}
