const python_c = @import("python_c");
const PyObject = *python_c.PyObject;

const utils = @import("../../../utils/utils.zig");

const Loop = @import("../../main.zig");
const Future = @import("../../../future/main.zig");

const LoopObject = Loop.Python.LoopObject;
const PythonFutureObject = Future.FutureObject;

pub fn loop_create_future(
    self: ?*LoopObject, args: ?PyObject
) callconv(.C) ?*PythonFutureObject {
    _ = args;
    return utils.execute_zig_function(Future.constructors.fast_new_future, .{self.?});
}
