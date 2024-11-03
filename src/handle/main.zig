const std = @import("std");
const builtin = @import("builtin");

const python_c = @import("../utils/python_c.zig");

const NoOpMutex = @import("../utils/no_op_mutex.zig");
const Loop = @import("../loop/main.zig");

pub const HandleCallback = *const fn (*Handle, bool, ?*anyopaque) bool;

allocator: std.mem.Allocator,
mutex: std.Thread.Mutex,
cancelled: bool = false,
repeat: usize = 1,
callback: ?HandleCallback,
data: ?*anyopaque,
loop: *Loop,

py_handle: ?*Handle.PythonHandleObject,

pub fn init(
    allocator: std.mem.Allocator, py_handle: ?*Handle.PythonHandleObject, loop: *Loop,
    callback: ?HandleCallback, data: ?*anyopaque
) !*Handle {
    const handle = try allocator.create(Handle);

    handle.* = .{
        .allocator = allocator,
        .mutex = std.Thread.Mutex{},
        .cancelled = false,
        .callback = callback,
        .data = data,
        .loop = loop,
        .py_handle = py_handle
    };

    return handle;
}

pub inline fn run_callback(self: *Handle, can_execute: bool) bool {
    var index: usize = 0;
    const limit = self.repeat;
    var should_stop: bool = false;

    const can_execute_logic: bool = can_execute and !self.is_cancelled();

    if (self.py_handle) |py_handle| {
        if (can_execute_logic) {
            while (!should_stop and index < limit) : (index += 1) {
                should_stop = Handle.callback_for_python_methods(py_handle);
            }
        }
        python_c.py_decref(@ptrCast(py_handle));
    }else{
        const callback = self.callback.?;
        const data = self.data.?;
        while (!should_stop and index < limit) : (index += 1) {
            should_stop = callback(self, can_execute_logic, data);
        }
    }

    return should_stop;
}

pub inline fn is_cancelled(self: *Handle) bool {
    const mutex = &self.mutex;

    mutex.lock();
    defer mutex.unlock();

    return self.cancelled;
}

pub inline fn cancel(self: *Handle) void {
    const mutex = &self.mutex;

    mutex.lock();
    self.cancelled = true;
    mutex.unlock();
}

pub usingnamespace @import("python.zig");

const Handle = @This();
