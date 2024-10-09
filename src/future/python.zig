const python_c = @import("../utils/python_c.zig");
const PyObject = *python_c.PyObject;

const utils = @import("../utils/utils.zig");
const allocator = utils.allocator;

const Future = @import("main.zig");
const Loop = @import("../loop/main.zig");

const std = @import("std");

pub const LEVIATHAN_FUTURE_MAGIC = 0x4655545552554552;

pub const PythonFutureObject = extern struct {
    ob_base: python_c.PyObject,
    magic: u64,
    future_obj: *Future,
    asyncio_module: PyObject,

    invalid_state_exc: PyObject,
    cancelled_error_exc: PyObject,

    exception: ?PyObject,
    exception_tb: ?PyObject,
};

fn z_future_new(
    @"type": ?*python_c.PyTypeObject, _: ?PyObject,
    _: ?PyObject
) !*PythonFutureObject {
    const instance: *PythonFutureObject = @ptrCast(@"type".?.tp_alloc.?(@"type", 0) orelse return error.PythonError);
    errdefer @"type".?.tp_free.?(instance);

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
    return instance;
}

fn future_new(
    @"type": ?*python_c.PyTypeObject, args: ?PyObject,
    kwargs: ?PyObject
) callconv(.C) ?PyObject {
    const self = utils.execute_zig_function(
        z_future_new, .{@"type", args, kwargs}
    );
    return @ptrCast(self);
}

fn future_dealloc(self: ?*PythonFutureObject) callconv(.C) void {
    if (utils.check_leviathan_python_object(self.?, LEVIATHAN_FUTURE_MAGIC)) {
        @panic("Invalid Leviathan's object");
    }
    const py_future = self.?;
    if (py_future.future_obj.result) |v| {
        python_c.Py_DECREF(@alignCast(@ptrCast(v)));
    }
    py_future.future_obj.release();

    python_c.Py_DECREF(py_future.invalid_state_exc);
    python_c.Py_DECREF(py_future.cancelled_error_exc);
    python_c.Py_DECREF(py_future.asyncio_module);


    const @"type": *python_c.PyTypeObject = @ptrCast(python_c.Py_TYPE(@ptrCast(self.?)) orelse unreachable);
    @"type".tp_free.?(@ptrCast(self.?));
}

fn z_future_init(
    self: *PythonFutureObject, args: ?PyObject, kwargs: ?PyObject
) !c_int {
    var py_loop: PyObject = python_c.Py_None();
    python_c.Py_INCREF(py_loop);
    defer python_c.Py_DECREF(py_loop);

    var loop_args_name: [5]u8 = undefined;
    @memcpy(&loop_args_name, "loop\x00");
    var kwlist: [2][*c]u8 = undefined;
    kwlist[0] = @ptrCast(&loop_args_name[0]);
    kwlist[1] = null;

    if (python_c.PyArg_ParseTupleAndKeywords(args, kwargs, "|O", @ptrCast(&kwlist), &py_loop) < 0) {
        return error.PythonError;
    }

    if (py_loop == python_c.Py_None()) {
        python_c.Py_DECREF(py_loop);
        const get_running_loop_func: PyObject = python_c.PyObject_GetAttrString(
            self.asyncio_module, "get_running_loop\x00"
        ) orelse return error.PythonError;
        defer python_c.Py_DECREF(get_running_loop_func);

        if (python_c.PyCallable_Check(get_running_loop_func) < 0) {
            utils.put_python_runtime_error_message("Error getting 'get_running_loop' function");
            return error.PythonError;
        }

        py_loop = python_c.PyObject_CallNoArgs(get_running_loop_func)
            orelse return error.PythonError;
    }

    if (python_c.PyObject_GetAttrString(py_loop, "_leviathan_asyncio_loop\x00")) |attr| {
        defer python_c.Py_DECREF(attr);
        const leviathan_loop: *Loop.PythonLoopObject = @ptrCast(attr);
        // if (utils.check_leviathan_python_object(leviathan_loop, Loop.LEVIATHAN_LOOP_MAGIC)) {
        //     return -1;
        // }

        self.future_obj.loop = leviathan_loop.loop_obj;
    }else{
        utils.put_python_runtime_error_message(
            "Invalid asyncio event loop. Only Leviathan's event loops are allowed\x00"
        );
        return -1;
    }

    return 0;
}

fn future_init(
    self: ?*PythonFutureObject, args: ?PyObject, kwargs: ?PyObject
) callconv(.C) c_int {
    if (utils.check_leviathan_python_object(self.?, LEVIATHAN_FUTURE_MAGIC)) {
        return -1;
    }
    const ret = utils.execute_zig_function(z_future_init, .{self.?, args, kwargs});
    return ret;
}

fn future_result(self: ?*PythonFutureObject, _: ?PyObject) callconv(.C) ?PyObject {
    if (utils.check_leviathan_python_object(self.?, LEVIATHAN_FUTURE_MAGIC)) {
        return null;
    }

    const instance = self.?;
    const obj = instance.future_obj;
    const mutex = &obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    const result: ?PyObject = switch (obj.status) {
        .PENDING => blk: {
            python_c.PyErr_SetString(instance.invalid_state_exc, "Result is not ready.\x00");
            break :blk null;
        },
        .FINISHED => blk: {
            if (instance.exception) |exc| {
                if (python_c.PyException_SetTraceback(exc, instance.exception_tb.?) < 0) {
                    utils.put_python_runtime_error_message(
                        "An error ocurred setting traceback to python exception\x00"
                    );
                }else{
                    python_c.PyErr_SetRaisedException(exc);
                }

                break :blk null;
            }
            break :blk @as(?PyObject, @alignCast(@ptrCast(obj.result)));
        },
        .CANCELED => blk: {
            python_c.PyErr_SetRaisedException(instance.cancelled_error_exc);
            break :blk null;
        }
    };

    return result;
}

fn future_set_result(self: ?*PythonFutureObject, args: ?PyObject) callconv(.C) ?PyObject {
    const instance = self.?;
    if (utils.check_leviathan_python_object(instance, LEVIATHAN_FUTURE_MAGIC)) {
        return null;
    }

    const obj = instance.future_obj;
    const mutex = &obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    switch (obj.status) {
        .FINISHED,.CANCELED => {
            python_c.PyErr_SetString(instance.invalid_state_exc, "Result already setted");
            return null;
        },
        else => {}
    }

    var result: PyObject = undefined;
    if (python_c.PyArg_ParseTuple(args.?, "O:result\x00", &result) < 0) {
        return null;
    }
    python_c.Py_INCREF(result);

    obj.result = result;
    obj.status = .FINISHED;

    return python_c.get_py_none();
}

fn future_done(self: ?*PythonFutureObject, _: ?PyObject) callconv(.C) ?PyObject {
    const instance = self.?;
    if (utils.check_leviathan_python_object(instance, LEVIATHAN_FUTURE_MAGIC)) {
        return null;
    }

    const obj = instance.future_obj;
    const mutex = &obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    return switch (obj.status) {
        .FINISHED,.CANCELED => python_c.get_py_true(),
        else => python_c.get_py_false()
    };
}

fn future_cancelled(self: ?*PythonFutureObject, _: ?PyObject) callconv(.C) ?PyObject {
    const instance = self.?;
    if (utils.check_leviathan_python_object(instance, LEVIATHAN_FUTURE_MAGIC)) {
        return null;
    }

    const obj = instance.future_obj;
    const mutex = &obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    return switch (obj.status) {
        .CANCELED => python_c.get_py_true(),
        else => python_c.get_py_false()
    };
}

const PythonFutureMethods: []const python_c.PyMethodDef = &[_]python_c.PyMethodDef{
    python_c.PyMethodDef{
        .ml_name = "result\x00",
        .ml_meth = @ptrCast(&future_result),
        .ml_doc = "Return the result of the Future\x00",
        .ml_flags = python_c.METH_NOARGS
    },

    python_c.PyMethodDef{
        .ml_name = "set_result\x00",
        .ml_meth = @ptrCast(&future_set_result),
        .ml_doc = "Mark the Future as done and set its result.\x00",
        .ml_flags = python_c.METH_VARARGS
    },
    python_c.PyMethodDef{
        .ml_name = "cancelled\x00",
        .ml_meth = @ptrCast(&future_cancelled),
        .ml_doc = "Return True if the Future was cancelled.\x00",
        .ml_flags = python_c.METH_NOARGS
    },
    python_c.PyMethodDef{
        .ml_name = "done\x00",
        .ml_meth = @ptrCast(&future_done),
        .ml_doc = "Return True if the Future is done.\x00",
        .ml_flags = python_c.METH_NOARGS
    },
    python_c.PyMethodDef{
        .ml_name = null, .ml_meth = null, .ml_doc = null, .ml_flags = 0
    }
};

pub var PythonFutureType = python_c.PyTypeObject{
    .tp_name = "leviathan.Future\x00",
    .tp_doc = "Leviathan's future class\x00",
    .tp_basicsize = @sizeOf(PythonFutureObject),
    .tp_itemsize = 0,
    .tp_flags = python_c.Py_TPFLAGS_DEFAULT,
    .tp_new = &future_new,
    .tp_init = @ptrCast(&future_init),
    .tp_dealloc = @ptrCast(&future_dealloc),
    .tp_methods = @constCast(PythonFutureMethods.ptr)
};

