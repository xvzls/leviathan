const python_c = @import("../utils/python_c.zig");
const PyObject = *python_c.PyObject;

const utils = @import("../utils/utils.zig");
const allocator = utils.allocator;

const Handle = @import("main.zig");
const Loop = @import("../loop/main.zig");

const std = @import("std");

pub const PythonHandleObject = extern struct {
    ob_base: python_c.PyObject,
    handle_obj: ?*Handle,

    exception_handler: ?PyObject,
    contextvars: ?PyObject,
    py_callback: ?PyObject,
    py_loop: ?*Loop.constructors.PythonLoopObject,
    args: ?[*]PyObject,
    nargs: usize
};

pub inline fn callback_for_python_methods(py_handle: *PythonHandleObject) bool {
    const ret: ?PyObject = python_c.PyObject_Vectorcall(
        py_handle.py_callback.?, py_handle.args, @intCast(py_handle.nargs), null
    );
    if (ret) |value| {
        python_c.py_decref(value);
    }else{
        if (
            python_c.PyErr_ExceptionMatches(python_c.PyExc_SystemExit) > 0 or
            python_c.PyErr_ExceptionMatches(python_c.PyExc_KeyboardInterrupt) > 0
        ) {
            return true;
        }

        const exception: PyObject = python_c.PyErr_GetRaisedException()
            orelse return true;
        defer python_c.py_decref(exception);

        const exc_handler_ret: PyObject = python_c.PyObject_CallOneArg(py_handle.exception_handler.?, exception)
            orelse return true;
        python_c.py_decref(exc_handler_ret);
    }
    return false;
}

pub inline fn fast_new_handle(
    loop: *Loop.constructors.PythonLoopObject, contextvars: PyObject,
    callback_info: []PyObject
) !*PythonHandleObject {
    const instance: *PythonHandleObject = @ptrCast(
        PythonHandleType.tp_alloc.?(&PythonHandleType, 0) orelse return error.PythonError
    );
    errdefer PythonHandleType.tp_free.?(instance);

    const contextvars_run_func: PyObject = python_c.PyObject_GetAttrString(contextvars, "run\x00")
        orelse return error.PythonError;
    errdefer python_c.py_decref(contextvars_run_func);

    instance.handle_obj = try Handle.init(
        allocator, instance, loop.loop_obj.?, null, null
    );

    instance.exception_handler = python_c.py_newref(loop.exception_handler.?);
    instance.contextvars = contextvars;
    instance.py_callback = contextvars_run_func;
    instance.py_loop = python_c.py_newref(loop);
    instance.args = callback_info.ptr;
    instance.nargs = callback_info.len;

    return instance;
}

inline fn z_handle_new(
    @"type": *python_c.PyTypeObject, _: ?PyObject,
    _: ?PyObject
) !*PythonHandleObject {
    const instance: *PythonHandleObject = @ptrCast(@"type".tp_alloc.?(@"type", 0) orelse return error.PythonError);
    errdefer @"type".tp_free.?(instance);
    instance.handle_obj = null;

    return instance;
}

fn handle_new(
    @"type": ?*python_c.PyTypeObject, args: ?PyObject,
    kwargs: ?PyObject
) callconv(.C) ?PyObject {
    const self = utils.execute_zig_function(
        z_handle_new, .{@"type".?, args, kwargs}
    );
    return @ptrCast(self);
}

inline fn handle_clear(py_handle: *PythonHandleObject) void {
    if (py_handle.handle_obj) |handle| {
        allocator.destroy(handle);
    }

    if (py_handle.args) |args| {
        const args_slice = args[0..py_handle.nargs];
        for (args_slice) |arg| {
            python_c.py_decref(arg);
        }
        allocator.free(args_slice);
    }

    python_c.py_xdecref(py_handle.contextvars);
    python_c.py_xdecref(py_handle.py_callback);
    python_c.py_xdecref(@ptrCast(py_handle.py_loop));
    python_c.py_xdecref(py_handle.exception_handler);
}

fn handle_dealloc(self: ?*PythonHandleObject) void {
    const instance = self.?;
    handle_clear(instance);

    const @"type": *python_c.PyTypeObject = @ptrCast(python_c.Py_TYPE(@ptrCast(instance)) orelse unreachable);
    @"type".tp_free.?(@ptrCast(instance));
}

inline fn z_handle_init(
    self: *PythonHandleObject, args: ?PyObject, kwargs: ?PyObject
) !c_int {
    var kwlist: [4][*c]u8 = undefined;
    kwlist[0] = @constCast("callback_info\x00");
    kwlist[1] = @constCast("loop\x00");
    kwlist[2] = @constCast("context\x00");
    kwlist[3] = null;

    var py_callback_args: ?PyObject = null;
    var py_loop: ?PyObject = null;
    var py_context: ?PyObject = null;

    if (python_c.PyArg_ParseTupleAndKeywords(
            args, kwargs, "OOO\x00", @ptrCast(&kwlist), &py_callback_args, &py_loop, &py_context
    ) < 0) {
        return error.PythonError;
    }

    if (python_c.PyObject_TypeCheck(py_loop.?, &Loop.PythonLoopType) == 0) {
        utils.put_python_runtime_error_message(
            "Invalid asyncio event loop. Only Leviathan's event loops are allowed\x00"
        );
        return error.PythonError;
    }
    const leviathan_loop: *Loop.constructors.PythonLoopObject = @ptrCast(py_loop.?);
    python_c.py_incref(@ptrCast(leviathan_loop));
    errdefer python_c.py_decref(@ptrCast(leviathan_loop));

    const contextvars_run_func: PyObject = python_c.PyObject_GetAttrString(py_context.?, "run\x00")
        orelse return error.PythonError;
    errdefer python_c.py_decref(contextvars_run_func);

    if (python_c.PyCallable_Check(contextvars_run_func) < 0) {
        utils.put_python_runtime_error_message("Invalid contextvars run function\x00");
        return error.PythonError;
    }

    const args_num = python_c.PyTuple_Size(py_callback_args.?);
    if (args_num < 0) {
        return error.PythonError;
    }

    const callback_info = try allocator.alloc(PyObject, @intCast(args_num));
    errdefer allocator.free(callback_info);

    for (0..@intCast(args_num)) |i| {
        callback_info[i] = python_c.py_newref(
            @as(PyObject, @ptrCast(
                python_c.PyTuple_GetItem(py_callback_args.?, @intCast(i)) orelse return error.PythonError
            ))
        );
    }
    errdefer {
        for (callback_info[0..@intCast(args_num)]) |arg| {
            python_c.py_decref(arg);
        }
    }

    self.handle_obj = try Handle.init(
        allocator, self, leviathan_loop.loop_obj.?, null, null
    );
    
    self.exception_handler = python_c.py_newref(leviathan_loop.exception_handler.?);
    self.py_callback = contextvars_run_func;
    self.py_loop = leviathan_loop;
    self.contextvars = python_c.py_newref(py_context.?);
    self.args = callback_info.ptr;
    self.nargs = callback_info.len;

    return 0;
}

fn handle_init(self: ?*PythonHandleObject, args: ?PyObject, kwargs: ?PyObject) callconv(.C) c_int {
    return utils.execute_zig_function(z_handle_init, .{self.?, args, kwargs});
}

fn handle_get_context(self: ?*PythonHandleObject, _: ?PyObject) callconv(.C) ?PyObject {
    return python_c.py_newref(self.?.contextvars.?);
}

fn handle_cancel(self: ?*PythonHandleObject, _: ?PyObject) callconv(.C) ?PyObject {
    const handle_obj = self.?.handle_obj.?;
    const mutex = &handle_obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    handle_obj.cancelled = true;

    return python_c.get_py_none();
}

fn handle_cancelled(self: ?*PythonHandleObject, _: ?PyObject) callconv(.C) ?PyObject {
    const handle_obj = self.?.handle_obj.?;
    const mutex = &handle_obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    return python_c.PyBool_FromLong(@intCast(@intFromBool(handle_obj.cancelled)));
}

const PythonhandleMethods: []const python_c.PyMethodDef = &[_]python_c.PyMethodDef{
    python_c.PyMethodDef{
        .ml_name = "cancel\x00",
        .ml_meth = @ptrCast(&handle_cancel),
        .ml_doc = "Cancel the callback. If the callback has already been canceled or executed, this method has no effect.\x00",
        .ml_flags = python_c.METH_NOARGS
    },
    python_c.PyMethodDef{
        .ml_name = "cancelled\x00",
        .ml_meth = @ptrCast(&handle_cancelled),
        .ml_doc = "Return True if the callback was cancelled.\x00",
        .ml_flags = python_c.METH_NOARGS
    },
    python_c.PyMethodDef{
        .ml_name = "get_context\x00",
        .ml_meth = @ptrCast(&handle_get_context),
        .ml_doc = "Return the contextvars.Context object associated with the handle.\x00",
        .ml_flags = python_c.METH_NOARGS
    },
    python_c.PyMethodDef{
        .ml_name = null, .ml_meth = null, .ml_doc = null, .ml_flags = 0
    }
};

pub var PythonHandleType = python_c.PyTypeObject{
    .tp_name = "leviathan.Handle\x00",
    .tp_doc = "Leviathan's handle class\x00",
    .tp_basicsize = @sizeOf(PythonHandleObject),
    .tp_itemsize = 0,
    .tp_flags = python_c.Py_TPFLAGS_DEFAULT | python_c.Py_TPFLAGS_BASETYPE,// | python_c.Py_TPFLAGS_HAVE_GC,
    .tp_new = &handle_new,
    .tp_init = @ptrCast(&handle_init),
    // .tp_traverse = @ptrCast(&handle_traverse),
    // .tp_clear = @ptrCast(&handle_clear),
    .tp_dealloc = @ptrCast(&handle_dealloc),
    .tp_methods = @constCast(PythonhandleMethods.ptr),
};

