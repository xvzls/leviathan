const python_c = @import("python_c");
const PyObject = *python_c.PyObject;

const utils = @import("../../utils/utils.zig");

const Loop = @import("../main.zig");
const LoopObject = Loop.Python.LoopObject;

const CallbackManager = @import("../../callback_manager.zig");

const std = @import("std");

inline fn z_loop_run_forever(self: *LoopObject) !PyObject {
    const loop_data = utils.get_data_ptr(Loop, self);

    try Loop.Python.Hooks.setup_asyncgen_hooks(self);
    defer Loop.Python.Hooks.cleanup_asyncgen_hooks(self);

    const set_running_loop = self.set_running_loop.?;
    if (python_c.PyObject_CallOneArg(set_running_loop, @ptrCast(self))) |v| {
        python_c.py_decref(v);
    }else{
        return error.PythonError;
    }

    defer {
        const exc = python_c.PyErr_GetRaisedException();
        if (python_c.PyObject_CallOneArg(set_running_loop, python_c.get_py_none())) |v| {
            python_c.py_decref(v);
            python_c.PyErr_SetRaisedException(exc);
        }
    }

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
    const instance = self.?;
    const clear_func: PyObject = python_c.PyObject_GetAttrString(instance.scheduled_tasks.?, "clear\x00")
        orelse return null;
    defer python_c.py_decref(clear_func);

    const ret: PyObject = python_c.PyObject_CallNoArgs(clear_func)
        orelse return null;
    python_c.py_decref(ret);

    const loop_data = utils.get_data_ptr(Loop, instance);

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
