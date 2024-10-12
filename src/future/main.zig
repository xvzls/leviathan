const std = @import("std");

const Loop = @import("../loop/main.zig");

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


pub fn init(allocator: std.mem.Allocator) !*Future {
    const fut = try allocator.create(Future);
    fut.* = .{
        .allocator = allocator,
        .mutex = std.Thread.Mutex{},
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
