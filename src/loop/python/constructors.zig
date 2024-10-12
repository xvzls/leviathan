const python_c = @import("../../utils/python_c.zig");
const PyObject = *python_c.PyObject;

const utils = @import("../../utils/utils.zig");
const allocator = utils.allocator;

const Loop = @import("../main.zig");

pub const LEVIATHAN_LOOP_MAGIC = 0x4C4F4F5000000001;

pub const PythonLoopObject = extern struct {
    ob_base: python_c.PyObject,
    magic: u64,
    loop_obj: ?*Loop
};

inline fn z_loop_new(
    @"type": *python_c.PyTypeObject, _: ?PyObject,
    _: ?PyObject
) !*PythonLoopObject {
    const instance: *PythonLoopObject = @ptrCast(@"type".tp_alloc.?(@"type", 0) orelse return error.PythonError);
    errdefer @"type".tp_free.?(instance);

    instance.magic = LEVIATHAN_LOOP_MAGIC;
    instance.loop_obj = null;

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

pub fn loop_dealloc(self: ?*PythonLoopObject) callconv(.C) void {
    if (utils.check_leviathan_python_object(self.?, LEVIATHAN_LOOP_MAGIC)) {
        @panic("Invalid Leviathan's object");
    }
    const py_loop = self.?;

    if (py_loop.loop_obj) |loop| {
        loop.release();
    }

    const @"type": *python_c.PyTypeObject = @ptrCast(python_c.Py_TYPE(@ptrCast(self.?)) orelse unreachable);
    @"type".tp_free.?(@ptrCast(self.?));
}

inline fn z_loop_init(
    self: *PythonLoopObject, args: ?PyObject, kwargs: ?PyObject
) !c_int {
    var loop_args_name: [11]u8 = undefined;
    @memcpy(&loop_args_name, "io_workers\x00");
    var kwlist: [2][*c]u8 = undefined;
    kwlist[0] = @ptrCast(&loop_args_name[0]);
    kwlist[1] = null;

    var io_workers: u64 = 0;

    if (python_c.PyArg_ParseTupleAndKeywords(args, kwargs, "|l", @ptrCast(&kwlist), &io_workers) < 0) {
        return error.PythonError;
    }

    self.loop_obj = try Loop.init(allocator, io_workers);

    return 0;
}

pub fn loop_init(
    self: ?*PythonLoopObject, args: ?PyObject, kwargs: ?PyObject
) callconv(.C) c_int {
    if (utils.check_leviathan_python_object(self.?, LEVIATHAN_LOOP_MAGIC)) {
        return -1;
    }
    const ret = utils.execute_zig_function(z_loop_init, .{self.?, args, kwargs});
    return ret;
}
