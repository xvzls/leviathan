const python_c = @import("../../utils/python_c.zig");
const PyObject = *python_c.PyObject;

const utils = @import("../../utils/utils.zig");
const allocator = utils.allocator;

const Future = @import("../main.zig");
const Loop = @import("../../loop/main.zig");

const std = @import("std");

pub const PythonFutureObject = extern struct {
    ob_base: python_c.PyObject,
    future_obj: ?*Future,

    asyncio_module: ?PyObject,
    invalid_state_exc: ?PyObject,
    cancelled_error_exc: ?PyObject,

    py_loop: ?*Loop.constructors.PythonLoopObject,
    exception: ?PyObject,
    exception_tb: ?PyObject,

    cancel_msg_py_object: ?PyObject,
    cancel_msg: ?[*:0]u8
};

inline fn z_future_new(
    @"type": *python_c.PyTypeObject, _: ?PyObject,
    _: ?PyObject
) !*PythonFutureObject {
    const instance: *PythonFutureObject = @ptrCast(@"type".tp_alloc.?(@"type", 0) orelse return error.PythonError);
    errdefer @"type".tp_free.?(instance);

    instance.future_obj = null;

    const asyncio_module: PyObject = python_c.PyImport_ImportModule("asyncio\x00")
        orelse return error.PythonError;
    errdefer python_c.py_decref(asyncio_module);

    instance.asyncio_module = asyncio_module;

    const invalid_state_exc: PyObject = python_c.PyObject_GetAttrString(asyncio_module, "InvalidStateError\x00")
        orelse return error.PythonError;
    errdefer python_c.py_decref(invalid_state_exc);

    const cancelled_error_exc: PyObject = python_c.PyObject_GetAttrString(asyncio_module, "CancelledError\x00")
        orelse return error.PythonError;
    errdefer python_c.py_decref(cancelled_error_exc);

    instance.cancelled_error_exc = cancelled_error_exc;
    instance.invalid_state_exc = invalid_state_exc;

    instance.exception_tb = null;
    instance.exception = null;
    instance.cancel_msg_py_object = null;
    instance.cancel_msg = null;
    return instance;
}

pub fn future_new(
    @"type": ?*python_c.PyTypeObject, args: ?PyObject,
    kwargs: ?PyObject
) callconv(.C) ?PyObject {
    const self = utils.execute_zig_function(
        z_future_new, .{@"type".?, args, kwargs}
    );
    return @ptrCast(self);
}

inline fn future_clear(py_future: *PythonFutureObject) void {
    if (py_future.future_obj) |future_obj| {
        future_obj.release();
    }

    python_c.py_xdecref(@ptrCast(py_future.py_loop));
    python_c.py_xdecref(py_future.exception);
    python_c.py_xdecref(py_future.exception_tb);
    python_c.py_xdecref(py_future.cancel_msg_py_object);
    python_c.py_xdecref(py_future.invalid_state_exc);
    python_c.py_xdecref(py_future.cancelled_error_exc);
    python_c.py_xdecref(py_future.asyncio_module);
}

pub fn future_dealloc(self: ?*PythonFutureObject) callconv(.C) void {
    const instance = self.?;
    future_clear(instance);

    const @"type": *python_c.PyTypeObject = @ptrCast(python_c.Py_TYPE(@ptrCast(instance)) orelse unreachable);
    @"type".tp_free.?(@ptrCast(instance));
}

inline fn z_future_init(
    self: *PythonFutureObject, args: ?PyObject, kwargs: ?PyObject
) !c_int {
    var kwlist: [3][*c]u8 = undefined;
    kwlist[0] = @constCast("loop\x00");
    kwlist[1] = null;

    var py_loop: ?PyObject = null;

    if (python_c.PyArg_ParseTupleAndKeywords(args, kwargs, "O\x00", @ptrCast(&kwlist), &py_loop) < 0) {
        return error.PythonError;
    }

    const leviathan_loop: *Loop.constructors.PythonLoopObject = @ptrCast(py_loop.?);
    if (python_c.PyObject_TypeCheck(@ptrCast(leviathan_loop), &Loop.PythonLoopType) == 0) {
        utils.put_python_runtime_error_message("Invalid asyncio event loop. Only Leviathan's event loops are allowed\x00");
        return error.PythonError;
    }

    self.future_obj = try Future.init(allocator, leviathan_loop.loop_obj.?);
    self.future_obj.?.py_future = self;
    self.py_loop = python_c.py_newref(leviathan_loop);

    return 0;
}

pub fn future_init(
    self: ?*PythonFutureObject, args: ?PyObject, kwargs: ?PyObject
) callconv(.C) c_int {
    return utils.execute_zig_function(z_future_init, .{self.?, args, kwargs});
}
