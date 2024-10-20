const std = @import("std");
const builtin = @import("builtin");

const Loop = @import("../loop/main.zig");
const NoOpMutex = @import("../utils/no_op_mutex.zig");

const LinkedList = @import("../utils/linked_list.zig");
const BTree = @import("../utils/btree/btree.zig");

pub const FutureStatus = enum {
    PENDING, FINISHED, CANCELED
};

result: ?*anyopaque = null,
status: FutureStatus = .PENDING,

mutex: std.Thread.Mutex,

callbacks_arena: std.heap.ArenaAllocator,
callbacks_arena_allocator: std.mem.Allocator,
zig_callbacks: *BTree = undefined,
python_callbacks: *BTree = undefined,
callbacks_array: LinkedList = undefined,

loop: ?*Loop,


pub fn init(self: *Future, allocator: std.mem.Allocator, thread_safe: bool, loop: *Loop) !void {
    const mutex = blk: {
        if (thread_safe or builtin.mode == .Debug) {
            break :blk std.Thread.Mutex{};
        } else {
            break :blk std.Thread.Mutex{
                .impl = NoOpMutex{},
            };
        }
    };

    self.* = .{
        .loop = loop,
        .mutex = mutex,
        .callbacks_arena = std.heap.ArenaAllocator.init(allocator)
    };

    self.callbacks_arena_allocator = self.callbacks_arena.allocator();
    self.zig_callbacks = try BTree.init(self.callbacks_arena_allocator);
    errdefer self.zig_callbacks.release() catch unreachable;

    self.python_callbacks = try BTree.init(self.callbacks_arena_allocator);
    errdefer self.python_callbacks.release() catch unreachable;

    self.callbacks_array = LinkedList.init(self.callbacks_arena_allocator);
}

pub inline fn release(self: *Future) void {
    self.callbacks_arena.deinit();
}

pub usingnamespace @import("callback.zig");
pub usingnamespace @import("python/main.zig");


const Future = @This();
