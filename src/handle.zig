const std = @import("std");
const builtin = @import("builtin");

const python_c = @import("python_c");
const PyObject = *python_c.PyObject;

const CallbackManager = @import("callback_manager.zig");
const utils = @import("utils/utils.zig");

pub const PythonHandleObject = extern struct {
    ob_base: python_c.PyObject,
    contextvars: ?PyObject,
    cancelled: bool
};

pub const GenericCallbackData = struct {
    args: []PyObject,
    exception_handler: PyObject,
    py_callback: PyObject,
    py_handle: *PythonHandleObject,
    cancelled: *bool,
};

pub inline fn release_python_generic_callback(allocator: std.mem.Allocator, data: GenericCallbackData) void {
    for (data.args) |arg| python_c.py_decref(arg);
    allocator.free(data.args);

    python_c.py_decref(data.py_callback);
    python_c.py_decref(@ptrCast(data.py_handle));
}

pub inline fn callback_for_python_generic_callbacks(
    allocator: std.mem.Allocator, data: GenericCallbackData
) CallbackManager.ExecuteCallbacksReturn {
    defer release_python_generic_callback(allocator, data);

    if (builtin.single_threaded) {
        if (data.cancelled.*) {
            return .Continue;
        }
    }else{
        if (@atomicLoad(bool, data.cancelled, .monotonic)) {
            return .Continue;
        }
    }

    const result: ?PyObject = python_c.PyObject_Vectorcall(
        data.py_callback, data.args.ptr, @intCast(data.args.len), null
    );
    if (result) |value| {
        python_c.py_decref(value);
    }else{
        if (
            python_c.PyErr_ExceptionMatches(python_c.PyExc_SystemExit) > 0 or
            python_c.PyErr_ExceptionMatches(python_c.PyExc_KeyboardInterrupt) > 0
        ) {
            return .Exception;
        }

        const exception: PyObject = python_c.PyErr_GetRaisedException()
            orelse return .Exception;
        defer python_c.py_decref(exception);

        const exc_handler_ret: PyObject = python_c.PyObject_CallOneArg(data.exception_handler, exception)
            orelse return .Exception;
        python_c.py_decref(exc_handler_ret);
    }

    return .Continue;
}

pub inline fn fast_new_handle(contextvars: PyObject) !*PythonHandleObject {
    const instance: *PythonHandleObject = @ptrCast(
        PythonHandleType.tp_alloc.?(&PythonHandleType, 0) orelse return error.PythonError
    );
    instance.contextvars = contextvars;
    instance.cancelled = false;

    return instance;
}

fn handle_dealloc(self: ?*PythonHandleObject) void {
    const instance = self.?;
    python_c.py_xdecref(instance.contextvars);

    const @"type": *python_c.PyTypeObject = @ptrCast(python_c.Py_TYPE(@ptrCast(instance)) orelse unreachable);
    @"type".tp_free.?(@ptrCast(instance));
}

inline fn z_handle_init(
    self: *PythonHandleObject, args: ?PyObject, kwargs: ?PyObject
) !c_int {
    var kwlist: [2][*c]u8 = undefined;
    kwlist[0] = @constCast("context\x00");
    kwlist[1] = null;

    var py_context: ?PyObject = null;

    if (python_c.PyArg_ParseTupleAndKeywords(
            args, kwargs, "O\x00", @ptrCast(&kwlist), &py_context
    ) < 0) {
        return error.PythonError;
    }
    
    if (py_context) |ctx| {
        if (python_c.Py_IsNone(ctx) != 0) {
            utils.put_python_runtime_error_message("context cannot be None\x00");
            return error.PythonError;
        }
    }

    self.contextvars = python_c.py_newref(py_context.?);

    return 0;
}

fn handle_init(self: ?*PythonHandleObject, args: ?PyObject, kwargs: ?PyObject) callconv(.C) c_int {
    return utils.execute_zig_function(z_handle_init, .{self.?, args, kwargs});
}

fn handle_get_context(self: ?*PythonHandleObject, _: ?PyObject) callconv(.C) ?PyObject {
    return python_c.py_newref(self.?.contextvars.?);
}

fn handle_cancel(self: ?*PythonHandleObject, _: ?PyObject) callconv(.C) ?PyObject {
    @atomicStore(bool, &self.?.cancelled, true, .monotonic);
    return python_c.get_py_none();
}

fn handle_cancelled(self: ?*PythonHandleObject, _: ?PyObject) callconv(.C) ?PyObject {
    const cancelled = @atomicLoad(bool, &self.?.cancelled, .monotonic);
    return python_c.PyBool_FromLong(@intCast(@intFromBool(cancelled)));
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
    .tp_flags = python_c.Py_TPFLAGS_DEFAULT | python_c.Py_TPFLAGS_BASETYPE,
    .tp_new = &python_c.PyType_GenericNew,
    .tp_init = @ptrCast(&handle_init),
    .tp_dealloc = @ptrCast(&handle_dealloc),
    .tp_methods = @constCast(PythonhandleMethods.ptr),
};

