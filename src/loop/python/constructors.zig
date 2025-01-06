const python_c = @import("python_c");
const PyObject = *python_c.PyObject;

const utils = @import("../../utils/utils.zig");

const Loop = @import("../main.zig");
const LoopObject = Loop.Python.LoopObject;

inline fn z_loop_new(
    @"type": *python_c.PyTypeObject, _: ?PyObject,
    _: ?PyObject
) !*LoopObject {
    const instance: *LoopObject = @ptrCast(@"type".tp_alloc.?(@"type", 0) orelse return error.PythonError);
    errdefer @"type".tp_free.?(instance);

    const contextvars_module: PyObject = python_c.PyImport_ImportModule("contextvars\x00")
        orelse return error.PythonError;
    errdefer python_c.py_decref(contextvars_module);

    const contextvars_copy: PyObject = python_c.PyObject_GetAttrString(contextvars_module, "copy_context\x00")
        orelse return error.PythonError;
    errdefer python_c.py_decref(contextvars_copy);

    const asyncio_module: PyObject = python_c.PyImport_ImportModule("asyncio\x00")
        orelse return error.PythonError;
    errdefer python_c.py_decref(asyncio_module);

    const invalid_state_exc: PyObject = python_c.PyObject_GetAttrString(asyncio_module, "InvalidStateError\x00")
        orelse return error.PythonError;
    errdefer python_c.py_decref(invalid_state_exc);

    const cancelled_error_exc: PyObject = python_c.PyObject_GetAttrString(asyncio_module, "CancelledError\x00")
        orelse return error.PythonError;
    errdefer python_c.py_decref(cancelled_error_exc);

    const enter_task_func: PyObject = python_c.PyObject_GetAttrString(asyncio_module, "_enter_task\x00")
        orelse return error.PythonError;
    errdefer python_c.py_decref(enter_task_func);

    const leave_task_func: PyObject = python_c.PyObject_GetAttrString(asyncio_module, "_leave_task\x00")
        orelse return error.PythonError;
    errdefer python_c.py_decref(leave_task_func);

    @memset(&instance.data, 0);

    instance.asyncio_module = asyncio_module;
    instance.cancelled_error_exc = cancelled_error_exc;
    instance.invalid_state_exc = invalid_state_exc;

    instance.enter_task_func = enter_task_func;
    instance.leave_task_func = leave_task_func;

    instance.contextvars_module = contextvars_module;
    instance.contextvars_copy = contextvars_copy;

    return instance;
}

pub fn loop_new(
    @"type": ?*python_c.PyTypeObject, args: ?PyObject,
    kwargs: ?PyObject
) callconv(.C) ?PyObject {
    const self = utils.execute_zig_function(
        z_loop_new, .{@"type".?, args, kwargs}
    );
    return @ptrCast(self);
}

pub fn loop_clear(self: ?*LoopObject) callconv(.C) c_int {
    const py_loop = self.?;
    const loop_data = utils.get_data_ptr(Loop, py_loop);
    if (loop_data.initialized) {
        loop_data.release();
    }

    python_c.py_decref_and_set_null(&py_loop.asyncio_module);
    python_c.py_decref_and_set_null(&py_loop.invalid_state_exc);
    python_c.py_decref_and_set_null(&py_loop.cancelled_error_exc);

    python_c.py_decref_and_set_null(&py_loop.exception_handler);
    python_c.py_decref_and_set_null(&py_loop.contextvars_module);
    python_c.py_decref_and_set_null(&py_loop.contextvars_copy);

    return 0;
}

pub fn loop_traverse(self: ?*LoopObject, visit: python_c.visitproc, arg: ?*anyopaque) callconv(.C) c_int {
    const instance = self.?;
    return python_c.py_visit(
        &[_]?*python_c.PyObject{
            instance.asyncio_module,
            instance.invalid_state_exc,
            instance.cancelled_error_exc,
            instance.exception_handler,
            instance.contextvars_module,
            instance.contextvars_copy,
        }, visit, arg
    );
}

pub fn loop_dealloc(self: ?*LoopObject) callconv(.C) void {
    const instance = self.?;

    python_c.PyObject_GC_UnTrack(instance);
    _ = loop_clear(instance);

    const @"type": *python_c.PyTypeObject = @ptrCast(python_c.Py_TYPE(@ptrCast(instance)) orelse unreachable);
    @"type".tp_free.?(@ptrCast(instance));
}

inline fn z_loop_init(
    self: *LoopObject, args: ?PyObject, kwargs: ?PyObject
) !c_int {
    var kwlist: [4][*c]u8 = undefined;
    kwlist[0] = @constCast("ready_tasks_queue_min_bytes_capacity\x00");
    kwlist[1] = @constCast("exception_handler\x00");
    kwlist[2] = null;

    var ready_tasks_queue_min_bytes_capacity: u64 = 0;
    var exception_handler: ?PyObject = null;

    if (python_c.PyArg_ParseTupleAndKeywords(
            args, kwargs, "KO\x00", @ptrCast(&kwlist), &ready_tasks_queue_min_bytes_capacity,
            &exception_handler
    ) < 0) {
        return error.PythonError;
    }

    if (python_c.PyCallable_Check(exception_handler.?) < 0) {
        utils.put_python_runtime_error_message("Invalid exception handler\x00");
        return error.PythonError;
    }

    self.exception_handler = python_c.py_newref(exception_handler.?);
    errdefer python_c.py_decref(exception_handler.?);

    const allocator = utils.gpa.allocator();
    const loop_data = utils.get_data_ptr(Loop, self);
    try loop_data.init(allocator, @intCast(ready_tasks_queue_min_bytes_capacity));

    return 0;
}

pub fn loop_init(
    self: ?*LoopObject, args: ?PyObject, kwargs: ?PyObject
) callconv(.C) c_int {
    return utils.execute_zig_function(z_loop_init, .{self.?, args, kwargs});
}

