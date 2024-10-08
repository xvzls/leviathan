const std = @import("std");

pub const callback_data = struct {
    id: usize,
    data: ?*anyopaque
};

pub const future_callbacks_array = std.ArrayList(*fn (allocator: std.mem.Allocator, data: ?*callback_data) void);
const future_callbacks_data_array = std.ArrayList(?*callback_data);

allocator: std.mem.Allocator,
must_cancel: bool = false,
result: ?*anyopaque = null,
exception: ?*anyopaque = null,
is_done: bool = false,
cancelled: bool = false,

pending_futures_to_be_executed: usize = 0,
callbacks: future_callbacks_array,
callbacks_data: future_callbacks_data_array,


pub fn init(allocator: std.mem.Allocator) !*Future {
    const fut = try allocator.create(Future);
    fut.* = .{
        .allocator = allocator,
        .callbacks = future_callbacks_array.init(allocator),
        .callbacks_data = future_callbacks_data_array.init(allocator)
    };
    return fut;
}

pub fn release(self: *const Future) void {
    self.allocator.destroy(self);
}

pub usingnamespace @import("python.zig");


const Future = @This();
