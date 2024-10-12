const python_c = @import("../utils/python_c.zig");
const PyObject = *python_c.PyObject;

pub const LoopCallback = struct {
    callback: fn (?*anyopaque) void,
    data: ?*anyopaque,
};

pub const PythonCallbackData = struct {
    callback: PyObject,

};

pub fn call_python_event(data: ?*anyopaque) void {
    _ = data;
}

