const python_c = @import("../../utils/python_c.zig");
const PyObject = *python_c.PyObject;

const utils = @import("../../utils/utils.zig");
const allocator = utils.allocator;

const Future = @import("../main.zig");
const Loop = @import("../../loop/main.zig");

const std = @import("std");

pub const LEVIATHAN_FUTURE_MAGIC = 0x4655545552554552;

pub const PythonFutureObject = extern struct {
    ob_base: python_c.PyObject,
    magic: u64,
    future_obj: *Future,

    py_loop: PyObject,
    asyncio_module: PyObject,
    invalid_state_exc: PyObject,
    cancelled_error_exc: PyObject,

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

    instance.magic = LEVIATHAN_FUTURE_MAGIC;

    const zig_future_obj = try Future.init(allocator);
    instance.future_obj = zig_future_obj;
    errdefer zig_future_obj.release();

    const asyncio_module: PyObject = python_c.PyImport_ImportModule("asyncio\x00")
        orelse return error.PythonError;
    errdefer python_c.Py_DECREF(asyncio_module);

    instance.asyncio_module = asyncio_module;

    const invalid_state_exc: PyObject = python_c.PyObject_GetAttrString(asyncio_module, "InvalidStateError\x00")
        orelse return error.PythonError;
    errdefer python_c.Py_DECREF(invalid_state_exc);

    const cancelled_error_exc: PyObject = python_c.PyObject_GetAttrString(asyncio_module, "CancelledError\x00")
        orelse return error.PythonError;
    errdefer python_c.Py_DECREF(cancelled_error_exc);

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

pub fn future_dealloc(self: ?*PythonFutureObject) callconv(.C) void {
    if (utils.check_leviathan_python_object(self.?, LEVIATHAN_FUTURE_MAGIC)) {
        @panic("Invalid Leviathan's object");
    }
    const py_future = self.?;
    if (py_future.future_obj.result) |v| {
        python_c.Py_DECREF(@alignCast(@ptrCast(v)));
    }
    py_future.future_obj.release();

    python_c.Py_XDECREF(py_future.exception);
    python_c.Py_XDECREF(py_future.exception_tb);
    python_c.Py_XDECREF(py_future.cancel_msg_py_object);

    python_c.Py_DECREF(py_future.invalid_state_exc);
    python_c.Py_DECREF(py_future.cancelled_error_exc);
    python_c.Py_DECREF(py_future.asyncio_module);
    python_c.Py_DECREF(py_future.py_loop);


    const @"type": *python_c.PyTypeObject = @ptrCast(python_c.Py_TYPE(@ptrCast(self.?)) orelse unreachable);
    @"type".tp_free.?(@ptrCast(self.?));
}

inline fn z_future_init(
    self: *PythonFutureObject, args: ?PyObject, kwargs: ?PyObject
) !c_int {
    var py_loop: ?PyObject = null;
    errdefer python_c.Py_XDECREF(py_loop);

    var loop_args_name: [5]u8 = undefined;
    @memcpy(&loop_args_name, "loop\x00");
    var kwlist: [2][*c]u8 = undefined;
    kwlist[0] = @ptrCast(&loop_args_name[0]);
    kwlist[1] = null;

    if (python_c.PyArg_ParseTupleAndKeywords(args, kwargs, "|O", @ptrCast(&kwlist), &py_loop) < 0) {
        return error.PythonError;
    }

    if (py_loop) |_py_loop| {
        python_c.Py_INCREF(_py_loop);
    }

    const leviathan_loop: *Loop.constructors.PythonLoopObject = @ptrCast(py_loop.?);
    if (utils.check_leviathan_python_object(leviathan_loop, Loop.constructors.LEVIATHAN_LOOP_MAGIC)) {
        utils.put_python_runtime_error_message("Invalid asyncio event loop. Only Leviathan's event loops are allowed\x00");
        return error.PythonError;
    }
    self.future_obj.loop = leviathan_loop.loop_obj;
    self.py_loop = py_loop.?;

    return 0;
}

pub fn future_init(
    self: ?*PythonFutureObject, args: ?PyObject, kwargs: ?PyObject
) callconv(.C) c_int {
    if (utils.check_leviathan_python_object(self.?, LEVIATHAN_FUTURE_MAGIC)) {
        return -1;
    }
    const ret = utils.execute_zig_function(z_future_init, .{self.?, args, kwargs});
    return ret;
}
