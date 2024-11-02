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

inline fn z_loop_call_soon(self: *PythonLoopObject, args: PyObject) !PyObject {
    var kwlist: [2][*c]u8 = undefined;
    kwlist[0] = @constCast("handle\x00");
    kwlist[1] = null;

    var py_handle: ?*Handle.PythonHandleObject = null;

    if (python_c.PyArg_ParseTupleAndKeywords(
            args, null, "O\x00", @ptrCast(&kwlist), &py_handle
        ) < 0) {
        return error.PythonError;
    }

    if (utils.check_leviathan_python_object(py_handle.?, Handle.LEVIATHAN_HANDLE_MAGIC)) {
        return error.PythonError;
    }

    python_c.Py_INCREF(@ptrCast(py_handle.?));
    errdefer python_c.Py_DECREF(@ptrCast(py_handle.?));

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

    try loop_obj.call_soon(py_handle.?.handle_obj.?);

    return python_c.get_py_none();
}

pub fn loop_call_soon(self: ?*PythonLoopObject, args: ?PyObject) callconv(.C) ?PyObject {
    const instance = self.?;
    if (utils.check_leviathan_python_object(instance, LEVIATHAN_LOOP_MAGIC)) {
        return null;
    }

    return utils.execute_zig_function(z_loop_call_soon, .{instance, args.?});
}
