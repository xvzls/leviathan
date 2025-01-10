const python_c = @import("python_c");
const PyObject = *python_c.PyObject;

const utils = @import("../../utils/utils.zig");

const Loop = @import("../main.zig");
const LoopObject = Loop.Python.LoopObject;

const CallbackManager = @import("../../callback_manager.zig");

const std = @import("std");

// pub fn loop_run_until_complete(self: ?*LoopObject, _: ?PyObject) callconv(.C) ?PyObject {
    
// }
//

fn z_loop_run_forever(self: *LoopObject) !PyObject {
    const loop_data = utils.get_data_ptr(Loop, self);

    try Loop.Python.Hooks.setup_asyncgen_hooks(self);
    defer Loop.Python.Hooks.cleanup_asyncgen_hooks(self);

    try Loop.Runner.start(loop_data);
    return python_c.get_py_none();
}

pub fn loop_run_forever(self: ?*LoopObject, _: ?PyObject) callconv(.C) ?PyObject {
    return utils.execute_zig_function(z_loop_run_forever, .{self.?});
}

pub fn loop_stop(self: ?*LoopObject, _: ?PyObject) callconv(.C) ?PyObject {
    const loop_data = utils.get_data_ptr(Loop, self.?);

    const mutex = &loop_data.mutex;
    mutex.lock();
    defer mutex.unlock();

    loop_data.stopping = true;
    return python_c.get_py_none();
}

pub fn loop_is_running(self: ?*LoopObject, _: ?PyObject) callconv(.C) ?PyObject {
    const loop_data = utils.get_data_ptr(Loop, self.?);
    const mutex = &loop_data.mutex;
    mutex.lock();
    defer mutex.unlock();

    return python_c.PyBool_FromLong(@intCast(@intFromBool(loop_data.running)));
}

pub fn loop_is_closed(self: ?*LoopObject, _: ?PyObject) callconv(.C) ?PyObject {
    const loop_data = utils.get_data_ptr(Loop, self.?);

    const mutex = &loop_data.mutex;
    mutex.lock();
    defer mutex.unlock();

    return python_c.PyBool_FromLong(@intCast(@intFromBool(!loop_data.initialized)));
}

pub fn loop_close(self: ?*LoopObject, _: ?PyObject) callconv(.C) ?PyObject {
    const loop_data = utils.get_data_ptr(Loop, self.?);

    {
        const mutex = &loop_data.mutex;
        mutex.lock();
        defer mutex.unlock();

        if (loop_data.running) {
            utils.put_python_runtime_error_message("Loop is running\x00");
            return null;
        }
    }

    loop_data.release();
    return python_c.get_py_none();
}
