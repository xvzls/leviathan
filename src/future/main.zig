const std = @import("std");
const builtin = @import("builtin");

const Loop = @import("../loop/main.zig");
const CallbackManager = @import("../callback_manager.zig");

const lock = @import("../utils/lock.zig");

pub const FutureStatus = enum {
    PENDING, FINISHED, CANCELED
};

result: ?*anyopaque = null,
status: FutureStatus = .PENDING,

mutex: lock.Mutex = lock.init(),

callbacks_arena: std.heap.ArenaAllocator,
callbacks_arena_allocator: std.mem.Allocator = undefined,
callbacks_queue: CallbackManager.CallbacksSetsQueue = undefined,
loop: *Loop,

released: bool = false,


pub fn init(self: *Future, loop: *Loop) void {
    self.* = .{
        .loop = loop,
        .callbacks_arena = std.heap.ArenaAllocator.init(loop.allocator)
    };

    self.callbacks_arena_allocator = self.callbacks_arena.allocator();
    self.callbacks_queue = .{
        .queue = CallbackManager.LinkedList.init(self.callbacks_arena_allocator),
        .last_set = null
    };
}

pub inline fn release(self: *Future) void {
    if (self.status == .PENDING) {
        _ = CallbackManager.execute_callbacks(self.loop.allocator, &self.callbacks_queue, .Stop, false);
    }

    self.callbacks_arena.deinit();
    self.released = true;
}

pub const Callback = @import("callback.zig");
pub const Python = @import("python/main.zig");


const Future = @This();
