const python_c = @import("python_c");
const PyObject = *python_c.PyObject;

const utils = @import("../../utils/utils.zig");

const CallbackManager = @import("../../callback_manager.zig");
const Loop = @import("../main.zig");
const Handle = @import("../../handle.zig");

const LoopObject = Loop.Python.LoopObject;

const std = @import("std");
const builtin = @import("builtin");

inline fn get_py_context(knames: ?PyObject, args_ptr: [*]?PyObject, loop: *LoopObject) !PyObject {
    var context: ?PyObject = null;
    if (knames) |kwargs| {
        const kwargs_len = python_c.PyTuple_Size(kwargs);
        const args = args_ptr[0..@as(usize, @intCast(kwargs_len))];
        if (kwargs_len < 0) {
            return error.PythonError;
        }else if (kwargs_len == 1) {
            const key = python_c.PyTuple_GetItem(kwargs, @intCast(0)) orelse return error.PythonError;
            if (python_c.PyUnicode_CompareWithASCIIString(key, "context\x00") == 0) {
                context = args[0].?;
            }else{
                utils.put_python_runtime_error_message("Invalid keyword argument\x00");
                return error.PythonError;
            }
        }else if (kwargs_len > 1) {
            utils.put_python_runtime_error_message("Too many keyword arguments\x00");
            return error.PythonError;
        }
    }

    if (context) |v| {
        if (python_c.Py_IsNone(v) == 0) {
            return python_c.py_newref(v);
        }
    }

    return python_c.PyObject_CallNoArgs(loop.contextvars_copy.?) orelse error.PythonError;
}

inline fn get_callback_info(allocator: std.mem.Allocator, args: []?PyObject) ![]PyObject {
    const callback_info = try allocator.alloc(PyObject, args.len);
    errdefer allocator.free(callback_info);

    for (args, callback_info) |arg, *ci| {
        ci.* = python_c.py_newref(arg.?);
    }
    errdefer {
        for (callback_info) |arg| {
            python_c.py_decref(@ptrCast(arg));
        }
    }

    if (python_c.PyCallable_Check(callback_info[0]) < 0) {
        utils.put_python_runtime_error_message("Invalid callback\x00");
        return error.PythonError;
    }

    return callback_info;
}

inline fn z_loop_call_soon(
    self: *LoopObject, args: []?PyObject,
    knames: ?PyObject
) !*Handle.PythonHandleObject {
    const context = try get_py_context(knames, args.ptr + args.len, self);
    errdefer python_c.py_decref(context);

    const loop_data = utils.get_data_ptr(Loop, self);
    const allocator = loop_data.allocator;

    const callback_info = try get_callback_info(allocator, args);
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

    if (loop_data.closed) {
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
            .cancelled = &py_handle.cancelled
        }
    };
    try Loop.Scheduling.Soon._dispatch(loop_data, callback);
    return python_c.py_newref(py_handle);
}

pub fn loop_call_soon(
    self: ?*LoopObject, args: ?[*]?PyObject, nargs: isize, knames: ?PyObject
) callconv(.C) ?*Handle.PythonHandleObject {
    return utils.execute_zig_function(z_loop_call_soon, .{
        self.?, args.?[0..@as(usize, @intCast(nargs))], knames
    });
}

pub fn loop_call_soon_threadsafe(
    self: ?*LoopObject, args: ?[*]?PyObject, nargs: isize, knames: ?PyObject
) callconv(.C) ?*Handle.PythonHandleObject {
    if (builtin.single_threaded) {
        utils.put_python_runtime_error_message("Loop.call_soon_threadsafe is not supported\x00");
        return null;
    }

    return utils.execute_zig_function(z_loop_call_soon, .{
        self.?, args.?[0..@as(usize, @intCast(nargs))], knames
    });
}
