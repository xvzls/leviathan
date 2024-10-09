const python_c = @import("../utils/python_c.zig");
const PyObject = *python_c.PyObject;

const utils = @import("../utils/utils.zig");
const allocator = utils.allocator;

const Loop = @import("main.zig");

const std = @import("std");

pub const LEVIATHAN_LOOP_MAGIC = 0x4C4F4F5000000001;

pub const PythonLoopObject = extern struct {
    ob_base: python_c.PyObject,
    magic: u64,
    loop_obj: *Loop
};

pub var PythonLoopType = python_c.PyTypeObject{
    .tp_name = "leviathan.Future\x00",
    .tp_doc = "Leviathan's future class\x00",
    .tp_basicsize = @sizeOf(PythonLoopObject),
    .tp_itemsize = 0,
    .tp_flags = python_c.Py_TPFLAGS_DEFAULT,
    // .tp_new = &future_new,
    // .tp_init = @ptrCast(&future_init),
    // .tp_dealloc = @ptrCast(&future_dealloc)
};

