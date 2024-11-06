const std = @import("std");
const builtin = @import("builtin");

const python_c = @import("utils/python_c.zig");
const utils = @import("utils/utils.zig");

const future = @import("future/main.zig");
const loop = @import("loop/main.zig");
const handle = @import("handle/main.zig");

const leviathan_types = .{
    &future.PythonFutureType,
    &loop.PythonLoopType,
    &handle.PythonHandleType
};

fn on_module_exit() callconv(.C) void {
    _ = utils.gpa.deinit();
}

var leviathan_module = python_c.PyModuleDef{
    .m_name = "leviathan_zig\x00",
    .m_doc = "Leviathan: A lightning-fast Zig-powered event loop for Python's asyncio.\x00",
    .m_size = -1,
};

inline fn initialize_leviathan_types() !void {
    inline for (leviathan_types) |v| {
        if (python_c.PyType_Ready(v) < 0) {
            return error.PythonError;
        }
    }
}

inline fn deinitialize_leviathan_types() void {
    inline for (leviathan_types) |v| {
        python_c.py_decref(@ptrCast(v));
    }
}

inline fn initialize_python_module() !*python_c.PyObject {
    const module: *python_c.PyObject = python_c.PyModule_Create(&leviathan_module) orelse return error.PythonError;
    errdefer python_c.py_decref(module);

    const leviathan_modules_name = .{
        "Future\x00", "Loop\x00", "Handle\x00"
    };

    inline for (leviathan_modules_name, leviathan_types) |leviathan_module_name, leviathan_module_obj| {
        if (
            python_c.PyModule_AddObject(
                module, leviathan_module_name, @as(*python_c.PyObject, @ptrCast(leviathan_module_obj))
            ) < 0
        ) {
            return error.PythonError;
        }
    }

    if (python_c.Py_AtExit(&on_module_exit) < 0) {
        return error.PythonError;
    }

    return module;
}

export fn PyInit_leviathan_zig() ?*python_c.PyObject {
    if (builtin.single_threaded) {
        utils.put_python_runtime_error_message("leviathan_zig is not supported in single-threaded mode\x00");
        return null;
    }else{
        initialize_leviathan_types() catch return null;
        const module = initialize_python_module() catch return null;
        return module;
    }
}

export fn PyInit_leviathan_zig_single_thread() ?*python_c.PyObject {
    if (builtin.single_threaded) {
        initialize_leviathan_types() catch return null;
        const module = initialize_python_module() catch return null;
        return module;
    }else{
        utils.put_python_runtime_error_message("leviathan_zig_single_thread is not supported in multi-threaded mode\x00");
        return null;
    }
}
