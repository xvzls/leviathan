const std = @import("std");
const builtin = @import("builtin");

const NoOpMutex = @import("../utils/no_op_mutex.zig");
const Loop = @import("../loop/main.zig");

pub const HandleCallback = *const fn (*Handle, ?*anyopaque) bool;

allocator: std.mem.Allocator,
mutex: std.Thread.Mutex,
cancelled: bool = false,
repeat: usize = 1,
callback: HandleCallback,
data: ?*anyopaque,
loop: *Loop,

py_handle: ?*Handle.PythonHandleObject,

pub fn init(
    allocator: std.mem.Allocator, py_handle: ?*Handle.PythonHandleObject, loop: *Loop,
    callback: HandleCallback, data: ?*anyopaque, thread_safe: bool
) !*Handle {
    const handle = try allocator.create(Handle);

    const mutex = blk: {
        _ = thread_safe;
        // if (thread_safe or builtin.mode == .Debug) {
            break :blk std.Thread.Mutex{};
        // } else {
        //     break :blk std.Thread.Mutex{
        //         .impl = NoOpMutex{},
        //     };
        // }
    };
    handle.* = .{
        .allocator = allocator,
        .mutex = mutex,
        .cancelled = false,
        .callback = callback,
        .data = data,
        .loop = loop,
        .py_handle = py_handle
    };

    return handle;
}

pub inline fn run_callback(self: *Handle) bool {
    var index: usize = 0;
    const limit = self.repeat;
    var should_stop: bool = false;

    const callback = self.callback;
    const data = self.data;
    while (!should_stop and index < limit) : (index += 1) {
        should_stop = callback(self, data);
    }
    return should_stop;
}

pub inline fn is_cancelled(self: *Handle) bool {
    const mutex = &self.mutex;

    mutex.lock();
    defer mutex.unlock();

    return self.cancelled;
}

pub usingnamespace @import("python.zig");

const Handle = @This();
