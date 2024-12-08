const python_c = @import("python_c");
const PyObject = *python_c.PyObject;

const utils = @import("../utils/utils.zig");

const Future = @import("../future/main.zig");
const Loop = @import("../loop/main.zig");

const std = @import("std");

pub const PythonTaskObject = extern struct {
    fut: Future.constructors.PythonFutureObject,

    py_context: ?PyObject,
    name: ?PyObject,

    coro: ?PyObject,
    coro_send: ?PyObject,
    coro_throw: ?PyObject,

    cancel_requests: usize,
    must_cancel: bool
};

inline fn z_task_new(
    @"type": *python_c.PyTypeObject, _: ?PyObject,
    _: ?PyObject
) !*PythonTaskObject {
    const instance: *PythonTaskObject = @ptrCast(@"type".tp_alloc.?(@"type", 0) orelse return error.PythonError);
    errdefer @"type".tp_free.?(instance);

    instance.fut.asyncio_module = null;
    instance.fut.invalid_state_exc = null;
    instance.fut.cancelled_error_exc = null;

    instance.fut.future_obj = null;
    instance.fut.exception_tb = null;
    instance.fut.exception = python_c.get_py_none();

    instance.fut.cancel_msg_py_object = null;
    instance.fut.blocking = 0;

    instance.py_context = null;
    instance.coro = null;
    instance.name = null;

    return instance;
}

pub fn task_new(
    @"type": ?*python_c.PyTypeObject, args: ?PyObject,
    kwargs: ?PyObject
) callconv(.C) ?PyObject {
    const self = utils.execute_zig_function(
        z_task_new, .{@"type".?, args, kwargs}
    );
    return @ptrCast(self);
}

pub fn task_clear(self: ?*PythonTaskObject) callconv(.C) c_int {
    const py_task = self.?;
    if (py_task.fut.future_obj) |future_obj| {
        future_obj.release();
        py_task.fut.future_obj = null;
    }

    python_c.py_decref_and_set_null(@ptrCast(&py_task.fut.py_loop));
    python_c.py_decref_and_set_null(&py_task.fut.exception);
    python_c.py_decref_and_set_null(&py_task.fut.exception_tb);
    python_c.py_decref_and_set_null(&py_task.fut.cancel_msg_py_object);

    python_c.py_decref_and_set_null(&py_task.py_context);
    python_c.py_decref_and_set_null(&py_task.name);

    python_c.py_decref_and_set_null(&py_task.coro);
    python_c.py_decref_and_set_null(&py_task.coro_send);
    python_c.py_decref_and_set_null(&py_task.coro_throw);

    return 0;
}

pub fn task_traverse(self: ?*PythonTaskObject, visit: python_c.visitproc, arg: ?*anyopaque) callconv(.C) c_int {
    const instance = self.?;
    return python_c.py_visit(
        &[_]?*python_c.PyObject{
            @ptrCast(instance.fut.py_loop),
            instance.fut.exception,
            instance.fut.exception_tb,
            instance.fut.cancel_msg_py_object,
            instance.fut.invalid_state_exc,
            instance.fut.cancelled_error_exc,
            instance.fut.asyncio_module,

            instance.py_context,
            instance.name,
            instance.coro,
            instance.coro_send,
            instance.coro_throw
        }, visit, arg
    );
}

pub fn task_dealloc(self: ?*PythonTaskObject) callconv(.C) void {
    const instance = self.?;

    python_c.PyObject_GC_UnTrack(instance);
    _ = task_clear(instance);

    const @"type": *python_c.PyTypeObject = @ptrCast(python_c.Py_TYPE(@ptrCast(instance)) orelse unreachable);
    @"type".tp_free.?(@ptrCast(instance));
}

inline fn z_task_init(
    self: *PythonTaskObject, args: ?PyObject, kwargs: ?PyObject
) !c_int {
    var kwlist: [5][*c]u8 = undefined;
    kwlist[0] = @constCast("coro\x00");
    kwlist[1] = @constCast("loop\x00");
    kwlist[2] = @constCast("name\x00");
    kwlist[3] = @constCast("context\x00");
    kwlist[4] = null;

    var coro: ?PyObject = null;
    var py_loop: ?PyObject = null;
    var name: ?PyObject = null;
    var context: ?PyObject = null;

    if (python_c.PyArg_ParseTupleAndKeywords(
            args, kwargs, "OOO|O\x00", @ptrCast(&kwlist), &coro, &py_loop,
            &name, &context
        ) < 0) {
        return error.PythonError;
    }

    const leviathan_loop: *Loop.constructors.PythonLoopObject = @ptrCast(py_loop.?);
    if (python_c.PyObject_TypeCheck(@ptrCast(leviathan_loop), &Loop.PythonLoopType) == 0) {
        utils.put_python_runtime_error_message(
            "Invalid asyncio event loop. Only Leviathan's event loops are allowed\x00"
        );
        return error.PythonError;
    }

    if (python_c.PyCoro_CheckExact(coro.?) == 0) {
        utils.put_python_runtime_error_message("Task coro must be a coroutine\x00");
        return error.PythonError;
    }

    const coro_send: PyObject = python_c.PyObject_GetAttrString(coro.?, "send\x00") orelse return error.PythonError;
    errdefer python_c.py_decref(coro_send);

    const coro_throw: PyObject = python_c.PyObject_GetAttrString(coro.?, "throw\x00") orelse return error.PythonError;
    errdefer python_c.py_decref(coro_throw);

    if (python_c.PyUnicode_Check(name.?) == 0) {
        utils.put_python_runtime_error_message("Task name must be a string\x00");
        return error.PythonError;
    }

    if (context) |py_ctx| {
        if (python_c.Py_IsNone(py_ctx) != 0) {
            self.py_context = python_c.PyObject_CallNoArgs(leviathan_loop.contextvars_copy.?)
                orelse return error.PythonError;
        }else{
            self.py_context = python_c.py_newref(py_ctx);
        }
    }else{
        self.py_context = python_c.PyObject_CallNoArgs(leviathan_loop.contextvars_copy.?) orelse return error.PythonError;
    }

    self.fut.future_obj = try Future.init(leviathan_loop.loop_obj.?.allocator, leviathan_loop.loop_obj.?);
    self.fut.future_obj.?.py_future = @ptrCast(self);
    self.fut.py_loop = python_c.py_newref(leviathan_loop);

    self.fut.asyncio_module = leviathan_loop.asyncio_module.?;
    self.fut.invalid_state_exc = leviathan_loop.invalid_state_exc.?;
    self.fut.cancelled_error_exc = leviathan_loop.cancelled_error_exc.?;

    self.coro = python_c.py_newref(coro.?);
    self.coro_send = coro_send;
    self.coro_throw = coro_throw;
    self.name = python_c.py_newref(name.?);

    return 0;
}

pub fn task_init(
    self: ?*PythonTaskObject, args: ?PyObject, kwargs: ?PyObject
) callconv(.C) c_int {
    return utils.execute_zig_function(z_task_init, .{self.?, args, kwargs});
}
