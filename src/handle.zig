const python_c = @import("utils/python_c.zig");
const PyObject = *python_c.PyObject;

const utils = @import("utils/utils.zig");
const allocator = utils.allocator;

const py_handle_data = struct {
    contextvars: PyObject,
    py_callback: PyObject,
    args: PyObject
};

fn callback_for_python_methods(data: ?*anyopaque) void {
    const py_data: *py_handle_data = @alignCast(@ptrCast(data.?));
    _ = py_data;
}

pub const HandleType = enum {
    Python, Zig
};


cancelled: bool = false,
callback: *const fn (?*anyopaque) void,
data: ?*anyopaque,
@"type": HandleType,


pub const LEVIATHAN_HANDLE_MAGIC = 0x48414E444C450001;

pub const PythonHandleObject = extern struct {
    ob_base: python_c.PyObject,
    magic: u64,
    handle_obj: ?*Handle
};

inline fn z_handle_new(
    @"type": *python_c.PyTypeObject, _: ?PyObject,
    _: ?PyObject
) !*PythonHandleObject {
    var kwargs: [5][*c]u8 = undefined;
    kwargs[0] = @constCast("callback\x00");
    kwargs[1] = @constCast("args\x00");
    kwargs[2] = @constCast("loop\x00");
    kwargs[3] = @constCast("context\x00");
    kwargs[4] = null;

    const instance: *PythonHandleObject = @ptrCast(@"type".tp_alloc.?(@"type", 0) orelse return error.PythonError);
    errdefer @"type".tp_free.?(instance);


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


pub var PythonLoopType = python_c.PyTypeObject{
    .tp_name = "leviathan.Handle\x00",
    .tp_doc = "Leviathan's handle class\x00",
    .tp_basicsize = @sizeOf(PythonHandleObject),
    .tp_itemsize = 0,
    .tp_flags = python_c.Py_TPFLAGS_DEFAULT | python_c.Py_TPFLAGS_BASETYPE,
    .tp_new = &handle_new,
    // .tp_init = @ptrCast(&handle_init),
    // .tp_dealloc = @ptrCast(&handle_dealloc),
};


const Handle = @This();
