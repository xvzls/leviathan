const python_c = @import("../utils/python_c.zig");
const PyObject = *python_c.PyObject;

const utils = @import("../utils/utils.zig");
const allocator = utils.allocator;

const Handle = @import("main.zig");
const Loop = @import("../loop/main.zig");

pub const LEVIATHAN_HANDLE_MAGIC = 0x48414E444C450001;

pub const PythonHandleObject = extern struct {
    ob_base: python_c.PyObject,
    magic: u64,
    handle_obj: *Handle,

    contextvars: ?PyObject,
    py_callback: ?PyObject,
    py_loop: ?*Loop.constructors.PythonLoopObject,
    args: ?PyObject
};

fn callback_for_python_methods(data: ?*anyopaque) bool {
    const py_handle: *PythonHandleObject = @alignCast(@ptrCast(data.?));

    const ret: ?PyObject = python_c.PyObject_CallObject(py_handle.py_callback.?, py_handle.args.?);
    if (ret) |value| {
        python_c.Py_DECREF(value);
    }else{
        if (
            python_c.PyErr_ExceptionMatches(python_c.PyExc_SystemExit) > 0 or
            python_c.PyErr_ExceptionMatches(python_c.PyExc_KeyboardInterrupt) > 0
        ) {
            return true;
        }

        const exception: PyObject = python_c.PyErr_GetRaisedException()
            orelse return true;
        // TODO: Create context's error dictionary
    }
}

inline fn z_handle_new(
    @"type": *python_c.PyTypeObject, _: ?PyObject,
    _: ?PyObject
) !*PythonHandleObject {
    const instance: *PythonHandleObject = @ptrCast(@"type".tp_alloc.?(@"type", 0) orelse return error.PythonError);
    errdefer @"type".tp_free.?(instance);

    instance.magic = LEVIATHAN_HANDLE_MAGIC;
    instance.handle_obj = try Handle.init(allocator, &callback_for_python_methods, instance);

    return instance;
}

fn handle_new(
    @"type": *python_c.PyTypeObject, args: ?PyObject,
    kwargs: ?PyObject
) void {
    const self = utils.execute_zig_function(
        z_handle_new, .{@"type".?, args, kwargs}
    );
    return @ptrCast(self);
}

fn handle_dealloc(self: ?*PythonHandleObject) void {
    if (utils.check_leviathan_python_object(self.?, LEVIATHAN_HANDLE_MAGIC)) {
        @panic("Invalid Leviathan's object");
    }
    const py_handle = self.?;
    py_handle.handle_obj.release(false);

    python_c.Py_XDECREF(py_handle.contextvars);
    python_c.Py_XDECREF(py_handle.py_callback);
    python_c.Py_XDECREF(py_handle.py_loop);
    python_c.Py_XDECREF(py_handle.args);

    const @"type": *python_c.PyTypeObject = @ptrCast(python_c.Py_TYPE(@ptrCast(self.?)) orelse unreachable);
    @"type".tp_free.?(@ptrCast(self.?));
}

inline fn z_handle_init(
    self: *PythonHandleObject, args: ?PyObject, kwargs: ?PyObject
) !c_int {
    var kwlist: [5][*c]u8 = undefined;
    kwlist[0] = @constCast("callback\x00");
    kwlist[1] = @constCast("args\x00");
    kwlist[2] = @constCast("loop\x00");
    kwlist[3] = @constCast("context\x00");
    kwlist[4] = null;

    var py_callback: ?PyObject = null;
    var py_callback_args: ?PyObject = null;
    var py_loop: ?*Loop.constructors.PythonLoopObject = null;
    var py_context: ?PyObject = null;

    if (python_c.PyArg_ParseTupleAndKeywords(
            self, args, kwargs, "OOOO\x00", &py_callback, &py_callback_args, &py_loop, &py_context
    ) < 0) {
        return error.PythonError;
    }

    const leviathan_loop: *Loop.constructors.PythonLoopObject = @ptrCast(py_loop.?);
    if (utils.check_leviathan_python_object(leviathan_loop, Loop.constructors.LEVIATHAN_LOOP_MAGIC)) {
        utils.put_python_runtime_error_message("Invalid asyncio event loop. Only Leviathan's event loops are allowed\x00");
        return error.PythonError;
    }

    const contextvars_run_func: PyObject = python_c.PyObject_GetAttrString(py_callback.?, "run\x00")
        orelse return error.PythonError;
    errdefer python_c.Py_DECREF(contextvars_run_func);

    if (python_c.PyCallable_Check(contextvars_run_func) < 0) {
        utils.put_python_runtime_error_message("Invalid contextvars run function\x00");
        return error.PythonError;
    }

    const py_args: PyObject = python_c.Py_BuildValue("OO\x00", py_callback.?, py_callback_args.?)
        orelse return error.PythonError;
    
    self.py_callback = python_c.Py_NewRef(contextvars_run_func.?).?;
    self.py_loop = python_c.Py_NewRef(py_loop.?).?;
    self.contextvars = python_c.Py_NewRef(py_context.?).?;
    self.args = python_c.Py_NewRef(py_args.?).?;

    return 0;
}

fn handle_init(self: ?*PythonHandleObject, args: ?PyObject, kwargs: ?PyObject) callconv(.C) c_int {
    if (utils.check_leviathan_python_object(self.?, LEVIATHAN_HANDLE_MAGIC)) {
        return -1;
    }
    const ret = utils.execute_zig_function(z_handle_init, .{self.?, args, kwargs});
    return ret;
}

pub var PythonLoopType = python_c.PyTypeObject{
    .tp_name = "leviathan.Handle\x00",
    .tp_doc = "Leviathan's handle class\x00",
    .tp_basicsize = @sizeOf(PythonHandleObject),
    .tp_itemsize = 0,
    .tp_flags = python_c.Py_TPFLAGS_DEFAULT | python_c.Py_TPFLAGS_BASETYPE,
    .tp_new = &handle_new,
    .tp_init = @ptrCast(&handle_init),
    .tp_dealloc = @ptrCast(&handle_dealloc),
};

