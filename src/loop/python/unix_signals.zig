const python_c = @import("python_c");
const PyObject = *python_c.PyObject;

const utils = @import("../../utils/utils.zig");

const CallbackManager = @import("../../callback_manager.zig");
const Handle = @import("../../handle.zig");
const Loop = @import("../main.zig");
const LoopObject = Loop.Python.LoopObject;

const Scheduling = @import("scheduling.zig");

const std = @import("std");

inline fn z_loop_add_signal_handler(
    self: *LoopObject, args: []?PyObject
) !PyObject {
    if (args.len < 2) {
        utils.put_python_runtime_error_message("Invalid number of arguments\x00");
        return error.PythonError;
    }
    const loop_data = utils.get_data_ptr(Loop, self);

    const py_sig: PyObject = args[0].?;
    if (python_c.PyLong_Check(py_sig) == 0) {
        utils.put_python_runtime_error_message("Invalid signal\x00");
        return error.PythonError;
    }

    const sig = python_c.PyLong_AsLong(py_sig);
    if (sig < 0) {
        python_c.PyErr_SetString(
            python_c.PyExc_ValueError,
            "Invalid signal\x00",
        );
        return error.PythonError;
    }

    const context: PyObject = python_c.PyObject_CallNoArgs(self.contextvars_copy.?)
        orelse return error.PythonError;
    errdefer python_c.py_decref(context);

    const allocator = loop_data.allocator;

    const callback_info = try Scheduling.get_callback_info(allocator, args[1..]);
    errdefer {
        for (callback_info) |arg| {
            python_c.py_decref(@ptrCast(arg));
        }
        allocator.free(callback_info);
    }

    const contextvars_run_func: PyObject = python_c.PyObject_GetAttrString(context, "run\x00")
        orelse return error.PythonError;
    errdefer python_c.py_decref(contextvars_run_func);

    const py_handle: *Handle.PythonHandleObject = try Handle.fast_new_handle(context);
    errdefer python_c.py_decref(@ptrCast(py_handle));

    const mutex = &loop_data.mutex;
    mutex.lock();
    defer mutex.unlock();
    if (!loop_data.initialized) {
        utils.put_python_runtime_error_message("Loop is closed\x00");
        return error.PythonError;
    }

    if (loop_data.stopping) {
        utils.put_python_runtime_error_message("Loop is stopping\x00");
        return error.PythonError;
    }

    const callback: CallbackManager.Callback = .{
        .PythonGeneric = .{
            .args = callback_info,
            .exception_handler = self.exception_handler.?,
            .py_callback = contextvars_run_func,
            .py_handle = py_handle,
            .cancelled = &py_handle.cancelled,
            .can_release = false
        }
    };

    try loop_data.unix_signals.link(@intCast(sig), callback);

    return python_c.get_py_none();
}

pub fn loop_add_signal_handler(
    self: ?*LoopObject, args: ?[*]?PyObject, nargs: isize
) callconv(.C) ?PyObject {
    return utils.execute_zig_function(z_loop_add_signal_handler, .{
        self.?, args.?[0..@as(usize, @intCast(nargs))]
    });
}

pub fn loop_remove_signal_handler(
    self: ?*LoopObject, py_sig: ?PyObject
) callconv(.C) ?PyObject {
    if (python_c.PyLong_Check(py_sig.?) == 0) {
        utils.put_python_runtime_error_message("Invalid signal\x00");
        return null;
    }

    const sig = python_c.PyLong_AsUnsignedLong(py_sig.?);

    const loop_data = utils.get_data_ptr(Loop, self.?);
    const mutex = &loop_data.mutex;
    mutex.lock();
    defer mutex.unlock();

    loop_data.unix_signals.unlink(@intCast(sig)) catch |err| {
        if (err == error.KeyNotFound) {
            return python_c.get_py_false();
        }
        utils.put_python_runtime_error_message(@errorName(err));
        return null;
    };

    return python_c.get_py_true();
}
