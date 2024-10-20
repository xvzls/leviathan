const std = @import("std");
const builtin = @import("builtin");

const NoOpMutex = @import("../utils/no_op_mutex.zig");
const Loop = @import("../loop/main.zig");

allocator: std.mem.Allocator,
mutex: std.Thread.Mutex,
cancelled: bool = false,
repeat: usize = 1,
callback: *const fn (?*anyopaque) bool,
data: ?*anyopaque,
loop: *Loop,

pub fn init(
    loop: *Loop, allocator: std.mem.Allocator, callback: *const fn (?*anyopaque) bool, data: ?*anyopaque,
    thread_safe: bool
) Handle {
    const mutex = blk: {
        if (thread_safe or builtin.mode == .Debug) {
            break :blk std.Thread.Mutex{};
        } else {
            break :blk std.Thread.Mutex{
                .impl = NoOpMutex{},
            };
        }
    };
    return .{
        .allocator = allocator,
        .mutex = mutex,
        .cancelled = false,
        .callback = callback,
        .data = data,
        .loop = loop,
    };
}

pub inline fn run_callback(self: *Handle) bool {
    var index: usize = 0;
    const limit = self.repeat;
    var should_stop: bool = false;

    const callback = self.callback;
    const data = self.data;
    while (!should_stop and index < limit) : (index += 1) {
        should_stop = callback(data);
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
