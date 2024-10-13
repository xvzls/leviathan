const std = @import("std");
const builtin = @import("builtin");

const NoOpMutex = @import("../utils/no_op_mutex.zig");
const Loop = @import("../loop/main.zig");

arena_allocator_id: u8,
allocator: std.mem.Allocator,
mutex: std.Thread.Mutex,
cancelled: bool = false,
callback: *const fn (?*anyopaque) bool,
data: ?*anyopaque,
loop: *Loop,
bytes_allocated: usize,

pub fn init(
    loop: *Loop, callback: *const fn (?*anyopaque) bool, comptime data_type: type,
    thread_safe: bool
) !*Handle {
    const loop_mutex = &loop.mutex;

    loop_mutex.lock();
    defer loop_mutex.unlock();

    var arena_allocator_id: u8 = undefined;
    comptime var size_to_allocate: usize = @sizeOf(Handle);

    const data_type_info = @typeInfo(data_type);
    if (data_type_info != .Null) {
        if (data_type_info != .Pointer) {
            @compileError("Data type must be a pointer or null");
        }else if (data_type_info.Pointer.size != .One) {
            @compileError("Data type must be a single item pointer");
        }

        size_to_allocate += @sizeOf(data_type_info.Pointer.child);
    }

    const allocator = loop.alloc_handle_data(size_to_allocate, &arena_allocator_id);
    errdefer loop.free_handle_data(size_to_allocate, arena_allocator_id);

    const handle = try allocator.create(Handle);
    errdefer allocator.destroy(handle);

    const data_ptr: ?*anyopaque = blk: {
        if (data_type_info != .Null) {
            break :blk try allocator.create(data_type);
        }
        break :blk null;
    };

    const mutex = blk: {
        if (thread_safe or builtin.mode == .Debug) {
            break :blk std.Thread.Mutex{};
        } else {
            break :blk std.Thread.Mutex{
                .impl = NoOpMutex{},
            };
        }
    };
    handle.* = .{
        .arena_allocator_id = arena_allocator_id,
        .allocator = allocator,
        .mutex = mutex,
        .cancelled = false,
        .callback = callback,
        .data = data_ptr,
        .loop = loop,
        .bytes_allocated = size_to_allocate
    };

    return handle;
}

pub inline fn run_callback(self: *Handle) bool {
    return self.callback(self.data);
}

pub inline fn is_cancelled(self: *Handle) bool {
    const mutex = &self.mutex;

    mutex.lock();
    defer mutex.unlock();

    return self.cancelled;
}

pub fn release(self: *Handle, can_free_data: bool) void {
    const mutex = &self.loop.mutex;

    mutex.lock();
    defer mutex.unlock();

    self.loop.free_handle_data(self.bytes_allocated, self.arena_allocator_id);
    const allocator = self.allocator;

    if (can_free_data) {
        if (self.data) |v| {
            allocator.destroy(v);
        }
    }

    allocator.destroy(self);
}

pub usingnamespace @import("python.zig");

const Handle = @This();
