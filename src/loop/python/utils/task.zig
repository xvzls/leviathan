const python_c = @import("python_c");
const PyObject = *python_c.PyObject;

const utils = @import("../../../utils/utils.zig");

const Loop = @import("../../main.zig");
const Task = @import("../../../task/main.zig");

const PythonLoopObject = Loop.Python.LoopObject;
const PythonTaskObject = Task.PythonTaskObject;


inline fn get_py_context_and_name(
    knames: ?PyObject, args_ptr: [*]?PyObject, loop: *PythonLoopObject,
    context: *?PyObject, name: *?PyObject
) !void {
    var _context: ?PyObject = null;
    var _name: ?PyObject = null;
    if (knames) |kwargs| {
        const kwargs_len = python_c.PyTuple_Size(kwargs);
        const args = args_ptr[0..@as(usize, @intCast(kwargs_len))];
        if (kwargs_len < 0) {
            return error.PythonError;
        }else if (kwargs_len <= 2) {
            for (args, 0..) |arg, i| {
                const key = python_c.PyTuple_GetItem(kwargs, @intCast(i)) orelse return error.PythonError;
                if (python_c.PyUnicode_CompareWithASCIIString(key, "context\x00") == 0) {
                    _context = arg.?;
                }else if (python_c.PyUnicode_CompareWithASCIIString(key, "name\x00") == 0) {
                    _name = arg.?;
                }else{
                    utils.put_python_runtime_error_message("Invalid keyword argument\x00");
                    return error.PythonError;
                }
            }
        }else if (kwargs_len > 2) {
            utils.put_python_runtime_error_message("Too many keyword arguments\x00");
            return error.PythonError;
        }
    }

    if (_context) |v| {
        if (python_c.Py_IsNone(v) == 0) {
            context.* = python_c.py_newref(v);
        }
    }else{
        context.* = python_c.PyObject_CallNoArgs(loop.contextvars_copy.?) orelse return error.PythonError;
    }
    errdefer python_c.py_decref(context.*.?);

    if (_name) |v| {
        if (python_c.Py_IsNone(v) != 0) {
            return;
        }

        if (python_c.PyUnicode_Check(v) == 0) {
            name.* = python_c.PyObject_Str(v) orelse return error.PythonError;
        }else{
            name.* = python_c.py_newref(v);
        }
    }
}

inline fn z_loop_create_task(
    self: *PythonLoopObject, args: []?PyObject,
    knames: ?PyObject
) !*PythonTaskObject {
    if (args.len != 1) {
        utils.put_python_runtime_error_message("Invalid number of arguments\x00");
        return error.PythonError;
    }

    var context: ?PyObject = null;
    var name: ?PyObject = null;
    try get_py_context_and_name(knames, args.ptr + 1, self, &context, &name);
    errdefer {
        python_c.py_decref(context.?);
        python_c.py_xdecref(name);
    }

    const coro: PyObject = python_c.py_newref(args[0].?);
    errdefer python_c.py_decref(coro);

    const task = try Task.constructors.fast_new_task(self, coro, context.?, name);
    return task;
}

pub fn loop_create_task(
    self: ?*PythonLoopObject, args: ?[*]?PyObject, nargs: isize, knames: ?PyObject
) callconv(.C) ?*PythonTaskObject {
    return utils.execute_zig_function(z_loop_create_task, .{
        self.?, args.?[0..@as(usize, @intCast(nargs))], knames
    });
}
