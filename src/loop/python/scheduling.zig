const python_c = @import("../../utils/python_c.zig");
const PyObject = *python_c.PyObject;

const utils = @import("../../utils/utils.zig");
const allocator = utils.allocator;

const Loop = @import("../main.zig");
const Handle = @import("../../handle/main.zig");

const constructors = @import("constructors.zig");
const PythonLoopObject = constructors.PythonLoopObject;
const LEVIATHAN_LOOP_MAGIC = constructors.LEVIATHAN_LOOP_MAGIC;

const std = @import("std");

inline fn z_loop_call_soon(
    self: *PythonLoopObject, args: []?PyObject,
    knames: ?PyObject
) !*Handle.PythonHandleObject {
    var context: ?PyObject = null;
    if (knames) |kwargs| {
        const kwargs_len = python_c.PyTuple_Size(kwargs);
        if (kwargs_len < 0) {
            return error.PythonError;
        }else if (kwargs_len == 1) {
            const key = python_c.PyTuple_GetItem(kwargs, @intCast(0)) orelse return error.PythonError;
            if (python_c.PyUnicode_CompareWithASCIIString(key, "context\x00") == 0) {
                context = python_c.py_newref(args[args.len].?);
            }else{
                utils.put_python_runtime_error_message("Invalid keyword argument\x00");
                return error.PythonError;
            }
        }else if (kwargs_len > 1) {
            utils.put_python_runtime_error_message("Too many keyword arguments\x00");
            return error.PythonError;
        }
    }

    if (context == null) {
        context = python_c.PyObject_CallNoArgs(self.contextvars_copy.?) orelse return error.PythonError;
    }

    errdefer python_c.py_decref(@ptrCast(context.?));

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

    const py_handle: *Handle.PythonHandleObject = try Handle.fast_new_handle(self, context.?, callback_info);
    const loop_obj = self.loop_obj.?;

    const mutex = &loop_obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    if (loop_obj.closed) {
        utils.put_python_runtime_error_message("Loop is closed\x00");
        return error.PythonError;
    }

    if (loop_obj.stopping) {
        utils.put_python_runtime_error_message("Loop is stopping\x00");
        return error.PythonError;
    }

    try loop_obj.call_soon(py_handle.handle_obj.?);
    return python_c.py_newref(py_handle);
}

pub fn loop_call_soon(
    self: ?*PythonLoopObject, args: ?[*]?PyObject, nargs: isize, knames: ?PyObject
) callconv(.C) ?*Handle.PythonHandleObject {
    return utils.execute_zig_function(z_loop_call_soon, .{
        self.?, args.?[0..@as(usize, @intCast(nargs))], knames
    });
}
