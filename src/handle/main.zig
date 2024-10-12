const std = @import("std");

allocator: std.mem.Allocator,
cancelled: bool = false,
callback: *const fn (?*anyopaque) void,
data: ?*anyopaque,

pub fn init(allocator: std.mem.Allocator, callback: *const fn (?*anyopaque) void, data: ?*anyopaque) !*Handle {
    const handle = try allocator.create(Handle);
    handle.* = .{
        .allocator = allocator,
        .cancelled = false,
        .callback = callback,
        .data = data
    };
    return handle;
}

pub inline fn run_callback(self: *Handle) void {
    self.callback(self.data);
}

pub fn release(self: *Handle, comptime free_data: bool) void {
    const allocator = self.allocator;

    if (free_data) {
        if (self.data) |v| {
            allocator.destroy(v);
        }
    }

    allocator.destroy(self);
}

const Handle = @This();
