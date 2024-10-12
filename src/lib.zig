const std = @import("std");
const builtin = @import("builtin");

const python_c = @import("utils/python_c.zig");
const utils = @import("utils/utils.zig");

const future = @import("future/main.zig");
const loop = @import("loop/main.zig");


// fn testing_function(self: ?*python_c.PyObject, args: ?*python_c.PyObject) callconv(.C) ?*python_c.PyObject {
//     std.debug.print("HOLA!!!", .{});
//     _ = self;
//     _ = args;

//     python_c.Py_INCREF(python_c.Py_None());
//     return python_c.Py_None();
// }

// const leviathan_methods: []const python_c.PyMethodDef = &[_]python_c.PyMethodDef{
//     python_c.PyMethodDef{
//         .ml_name = "testing_function\x00", .ml_meth = &testing_function,
//         .ml_doc = null, .ml_flags = python_c.METH_NOARGS
//     },

//     python_c.PyMethodDef{
//         .ml_name = null, .ml_meth = null, .ml_doc = null, .ml_flags = 0
//     }
// };


fn on_module_exit() callconv(.C) void {
    _ = utils.gpa.detectLeaks();
    _ = utils.gpa.deinit();
}


var leviathan_module = python_c.PyModuleDef{
    .m_name = "leviathan_zig\x00",
    .m_doc = "Leviathan: A lightning-fast Zig-powered event loop for Python's asyncio.\x00",
    .m_size = -1,
    // .m_methods = @constCast(leviathan_methods.ptr),
};

inline fn initialize_leviathan_types() !void {
    if (python_c.PyType_Ready(&future.PythonFutureType) < 0) {
        return error.PythonError;
    }

    python_c.Py_INCREF(@ptrCast(&future.PythonFutureType));
    errdefer python_c.Py_DECREF(@ptrCast(&future.PythonFutureType));

    if (python_c.PyType_Ready(&loop.PythonLoopType) < 0) {
        return error.PythonError;
    }

    python_c.Py_INCREF(@ptrCast(&loop.PythonLoopType));
}

inline fn deinitialize_leviathan_types() void {
    python_c.Py_DECREF(@ptrCast(&future.PythonFutureType));
    python_c.Py_DECREF(@ptrCast(&loop.PythonLoopType));
}

inline fn initialize_python_module() !*python_c.PyObject {
    errdefer deinitialize_leviathan_types();

    const module: *python_c.PyObject = python_c.PyModule_Create(&leviathan_module) orelse return error.PythonError;
    errdefer python_c.Py_DECREF(module);

    const leviathan_modules = .{
        .{"Future\x00", &future.PythonFutureType},
        .{"Loop\x00", &loop.PythonLoopType},
    };

    inline for (leviathan_modules) |v| {
        const leviathan_module_name = v[0];
        const leviathan_module_obj = v[1];
        if (
            python_c.PyModule_AddObject(
                module, leviathan_module_name, @as(*python_c.PyObject, @ptrCast(leviathan_module_obj))
            ) < 0
        ) {
            return error.PythonError;
        }
    }


    if (builtin.mode == .Debug) {
        if (python_c.Py_AtExit(&on_module_exit) < 0) {
            return error.PythonError;
        }
    }

    return module;
}

export fn PyInit_leviathan_zig() ?*python_c.PyObject {
    initialize_leviathan_types() catch return null;
    const module = initialize_python_module() catch return null;
    return module;
}
