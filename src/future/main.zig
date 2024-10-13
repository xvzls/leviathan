const std = @import("std");
const builtin = @import("builtin");

const Loop = @import("../loop/main.zig");
const NoOpMutex = @import("../utils/no_op_mutex.zig");

pub const FutureStatus = enum {
    PENDING, FINISHED, CANCELED
};

pub const callback_data = struct {
    id: usize,
    data: ?*anyopaque
};

pub const future_callbacks_array = std.ArrayList(*fn (allocator: std.mem.Allocator, data: ?*callback_data) void);
const future_callbacks_data_array = std.ArrayList(?*callback_data);

allocator: std.mem.Allocator,
result: ?*anyopaque = null,
status: FutureStatus = .PENDING,

mutex: std.Thread.Mutex,

callbacks: future_callbacks_array,
callbacks_data: future_callbacks_data_array,

loop: ?*Loop = null,


pub fn init(allocator: std.mem.Allocator, thread_safe: bool) !*Future {
    const mutex = blk: {
        if (thread_safe or builtin.mode == .Debug) {
            break :blk std.Thread.Mutex{};
        } else {
            break :blk std.Thread.Mutex{
                .impl = NoOpMutex{},
            };
        }
    };

    const fut = try allocator.create(Future);
    fut.* = .{
        .allocator = allocator,
        .mutex = mutex,
        .callbacks = future_callbacks_array.init(allocator),
        .callbacks_data = future_callbacks_data_array.init(allocator)
    };
    return fut;
}

pub fn release(self: *const Future) void {
    self.allocator.destroy(self);
}

pub usingnamespace @import("python/main.zig");


const Future = @This();
