const python_c = @import("../../utils/python_c.zig");
pub const constructors = @import("constructors.zig");


pub var PythonLoopType = python_c.PyTypeObject{
    .tp_name = "leviathan.Loop\x00",
    .tp_doc = "Leviathan's loop class\x00",
    .tp_basicsize = @sizeOf(constructors.PythonLoopObject),
    .tp_itemsize = 0,
    .tp_flags = python_c.Py_TPFLAGS_DEFAULT | python_c.Py_TPFLAGS_BASETYPE,
    .tp_new = &constructors.loop_new,
    .tp_init = @ptrCast(&constructors.loop_init),
    .tp_dealloc = @ptrCast(&constructors.loop_dealloc),
};

