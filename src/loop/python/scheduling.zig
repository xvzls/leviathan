const python_c = @import("python_c");
const PyObject = *python_c.PyObject;

const utils = @import("../../utils/utils.zig");

const Loop = @import("../main.zig");
const Handle = @import("../../handle.zig");

const PythonLoopObject = Loop.PythonLoopObject;

const std = @import("std");

inline fn get_py_context(knames: ?PyObject, args: []?PyObject, loop: *PythonLoopObject) !PyObject {
    var context: ?PyObject = null;
    if (knames) |kwargs| {
        const kwargs_len = python_c.PyTuple_Size(kwargs);
        if (kwargs_len < 0) {
            return error.PythonError;
        }else if (kwargs_len == 1) {
            const key = python_c.PyTuple_GetItem(kwargs, @intCast(0)) orelse return error.PythonError;
            if (python_c.PyUnicode_CompareWithASCIIString(key, "context\x00") == 0) {
                context = args[args.len].?;
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
    self: *PythonLoopObject, args: []?PyObject,
    knames: ?PyObject
) !*Handle.PythonHandleObject {
    const context = try get_py_context(knames, args, self);
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

    try loop_data.call_soon(.{
        .PythonGeneric = .{
            .args = callback_info,
            .exception_handler = self.exception_handler.?,
            .py_callback = contextvars_run_func,
            .py_handle = py_handle,
            .cancelled = &py_handle.cancelled
        }
    });
    return python_c.py_newref(py_handle);
}

pub fn loop_call_soon(
    self: ?*PythonLoopObject, args: ?[*]?PyObject, nargs: isize, knames: ?PyObject
) callconv(.C) ?*Handle.PythonHandleObject {
    return utils.execute_zig_function(z_loop_call_soon, .{
        self.?, args.?[0..@as(usize, @intCast(nargs))], knames
    });
}
