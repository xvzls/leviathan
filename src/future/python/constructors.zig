const python_c = @import("python_c");
const PyObject = *python_c.PyObject;

const utils = @import("../../utils/utils.zig");
const result = @import("result.zig");

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
    blocking: u64
};

inline fn z_future_new(
    @"type": *python_c.PyTypeObject, _: ?PyObject,
    _: ?PyObject
) !*PythonFutureObject {
    const instance: *PythonFutureObject = @ptrCast(@"type".tp_alloc.?(@"type", 0) orelse return error.PythonError);
    errdefer @"type".tp_free.?(instance);

    instance.asyncio_module = null;
    instance.invalid_state_exc = null;
    instance.cancelled_error_exc = null;

    instance.future_obj = null;
    instance.exception_tb = null;
    instance.exception = null;

    instance.cancel_msg_py_object = null;
    instance.blocking = 0;
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

pub fn future_clear(self: ?*PythonFutureObject) callconv(.C) c_int {
    const py_future = self.?;
    if (py_future.future_obj) |future_obj| {
        future_obj.release();
        py_future.future_obj = null;
    }

    python_c.py_decref_and_set_null(@ptrCast(&py_future.py_loop));
    python_c.py_decref_and_set_null(&py_future.exception);
    python_c.py_decref_and_set_null(&py_future.exception_tb);
    python_c.py_decref_and_set_null(&py_future.cancel_msg_py_object);

    return 0;
}

pub fn future_traverse(self: ?*PythonFutureObject, visit: python_c.visitproc, arg: ?*anyopaque) callconv(.C) c_int {
    const instance = self.?;
    return python_c.py_visit(
        &[_]?*python_c.PyObject{
            @ptrCast(instance.py_loop),
            instance.exception,
            instance.exception_tb,
            instance.cancel_msg_py_object,
            instance.invalid_state_exc,
            instance.cancelled_error_exc,
            instance.asyncio_module,
        }, visit, arg
    );
}

pub fn future_dealloc(self: ?*PythonFutureObject) callconv(.C) void {
    const instance = self.?;

    python_c.PyObject_GC_UnTrack(instance);
    _ = future_clear(instance);

    const @"type": *python_c.PyTypeObject = @ptrCast(python_c.Py_TYPE(@ptrCast(instance)) orelse unreachable);
    @"type".tp_free.?(@ptrCast(instance));
}

inline fn z_future_init(
    self: *PythonFutureObject, args: ?PyObject, kwargs: ?PyObject
) !c_int {
    var kwlist: [2][*c]u8 = undefined;
    kwlist[0] = @constCast("loop\x00");
    kwlist[1] = null;

    var py_loop: ?PyObject = null;

    if (python_c.PyArg_ParseTupleAndKeywords(args, kwargs, "O\x00", @ptrCast(&kwlist), &py_loop) < 0) {
        return error.PythonError;
    }

    const leviathan_loop: *Loop.constructors.PythonLoopObject = @ptrCast(py_loop.?);
    if (python_c.PyObject_TypeCheck(@ptrCast(leviathan_loop), &Loop.PythonLoopType) == 0) {
        utils.put_python_runtime_error_message(
            "Invalid asyncio event loop. Only Leviathan's event loops are allowed\x00"
        );
        return error.PythonError;
    }

    self.future_obj = try Future.init(leviathan_loop.loop_obj.?.allocator, leviathan_loop.loop_obj.?);
    self.future_obj.?.py_future = self;
    self.py_loop = python_c.py_newref(leviathan_loop);

    self.asyncio_module = leviathan_loop.asyncio_module.?;
    self.invalid_state_exc = leviathan_loop.invalid_state_exc.?;
    self.cancelled_error_exc = leviathan_loop.cancelled_error_exc.?;

    return 0;
}

pub fn future_init(
    self: ?*PythonFutureObject, args: ?PyObject, kwargs: ?PyObject
) callconv(.C) c_int {
    return utils.execute_zig_function(z_future_init, .{self.?, args, kwargs});
}

pub fn future_get_loop(self: ?*PythonFutureObject) callconv(.C) ?*Loop.constructors.PythonLoopObject {
    return python_c.py_newref(self.?.py_loop);
}

pub fn future_iter(self: ?*PythonFutureObject) callconv(.C) ?*python_c.PyObject {
    return @ptrCast(python_c.py_newref(self.?));
}

pub fn future_iternext(self: ?*PythonFutureObject) callconv(.C) ?*python_c.PyObject {
    const instance = self.?;

    const obj = instance.future_obj.?;
    const mutex = &obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    if (obj.status != .PENDING) {
        const res = result.get_result(obj.py_future.?);
        if (res) |py_res| {
            python_c.PyErr_SetObject(python_c.PyExc_StopIteration, py_res);
        }
        return null;
    }

    // TODO: Return future object instead of None
    return python_c.get_py_none();
}
