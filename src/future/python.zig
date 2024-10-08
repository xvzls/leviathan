const python_c = @import("../utils/python_c.zig");
const PyObject = *python_c.PyObject;

const utils = @import("../utils/utils.zig");
const allocator = utils.allocator;

const Future = @import("main.zig");

const std = @import("std");

pub const PythonFutureObject = extern struct {
    ob_base: python_c.PyObject,
    future_obj: *Future
};

fn z_future_new(
    @"type": ?*python_c.PyTypeObject, _: ?PyObject,
    _: ?PyObject
) !*PythonFutureObject {
    const instance: *PythonFutureObject = @ptrCast(@"type".?.tp_alloc.?(@"type", 0) orelse return error.PythonError);
    errdefer @"type".?.tp_free.?(instance);

    const zig_future_obj = try Future.init(allocator);
    instance.future_obj = zig_future_obj;

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
    self.?.future_obj.release();

    const @"type": *python_c.PyTypeObject = @ptrCast(python_c.Py_TYPE(@ptrCast(self.?)) orelse unreachable);
    @"type".tp_free.?(@ptrCast(self.?));
}

fn z_future_init(
    _: ?*PythonFutureObject, args: ?PyObject, kwargs: ?PyObject
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
        const asyncio_module: PyObject = python_c.PyImport_ImportModule("asyncio\x00")
            orelse return error.PythonError;
        defer python_c.Py_DECREF(asyncio_module);

        const get_running_loop_func: PyObject = python_c.PyObject_GetAttrString(
            asyncio_module, "get_running_loop\x00"
        ) orelse return error.PythonError;

        if (python_c.PyCallable_Check(get_running_loop_func) < 0) {
            utils.put_python_runtime_error_message("Error getting 'get_running_loop' function");
            return error.PythonError;
        }

        py_loop = python_c.PyObject_CallNoArgs(get_running_loop_func)
            orelse return error.PythonError;
    }

    if (python_c.PyObject_GetAttrString(py_loop, "_leviathan_asyncio_loop\x00")) |attr| {
        python_c.Py_DECREF(attr);
    }else{
        utils.put_python_runtime_error_message("Invalid asyncio event loop. Only Leviathan's event loops are allowed\x00");
        return -1;
    }

    return 0;
}

fn future_init(
    self: ?*PythonFutureObject, args: ?PyObject, kwargs: ?PyObject
) callconv(.C) c_int {
    const ret = utils.execute_zig_function(z_future_init, .{self, args, kwargs});
    return ret;
}

pub var PythonFutureType = python_c.PyTypeObject{
    .tp_name = "leviathan.Future\x00",
    .tp_doc = "Leviathan's future class\x00",
    .tp_basicsize = @sizeOf(PythonFutureObject),
    .tp_itemsize = 0,
    .tp_flags = python_c.Py_TPFLAGS_DEFAULT,
    .tp_new = &future_new,
    .tp_init = @ptrCast(&future_init),
    .tp_dealloc = @ptrCast(&future_dealloc)
};

