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

// inline fn z_loop_call_soon(self: *PythonLoopObject, args: PyObject) !PyObject {
inline fn z_loop_call_soon(self: *PythonLoopObject, args: []?PyObject) !*Handle.PythonHandleObject {
    // var py_handle: ?*Handle.PythonHandleObject = null;

    // if (python_c.PyArg_ParseTuple(args, "O\x00", &py_handle) < 0) {
    //     return error.PythonError;
    // }
    //
    const callback_info = args[0].?;
    const context = args[1].?;
    const py_handle: *Handle.PythonHandleObject = @ptrCast(python_c.PyObject_CallFunctionObjArgs(
        @ptrCast(&Handle.PythonHandleType), callback_info, self, context, @as(?PyObject, null)
    ) orelse return error.PythonError);
    errdefer python_c.py_decref(@ptrCast(py_handle));

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

pub fn loop_call_soon(self: ?*PythonLoopObject, args: [*]?PyObject, nargs: isize) callconv(.C) ?*Handle.PythonHandleObject {
    return utils.execute_zig_function(z_loop_call_soon, .{
        self.?, args[0..@as(usize, @intCast(nargs))]
    });
}
