const std = @import("std");
const builtin = @import("builtin");

const Loop = @import("../loop/main.zig");
const NoOpMutex = @import("../utils/no_op_mutex.zig");

const LinkedList = @import("../utils/linked_list.zig");
const BTree = @import("../utils/btree/btree.zig");

pub const FutureStatus = enum {
    PENDING, FINISHED, CANCELED
};

allocator: std.mem.Allocator,

result: ?*anyopaque = null,
status: FutureStatus = .PENDING,

thread_safe: bool,
mutex: std.Thread.Mutex,

callbacks_arena: std.heap.ArenaAllocator,
callbacks_arena_allocator: std.mem.Allocator = undefined,
zig_callbacks: *BTree = undefined,
python_callbacks: *BTree = undefined,
callbacks_array: LinkedList = undefined,
loop: ?*Loop,

py_future: ?*Future.constructors.PythonFutureObject = null,


pub fn init(allocator: std.mem.Allocator, thread_safe: bool, loop: *Loop) !*Future {
    const fut = try allocator.create(Future);
    errdefer allocator.destroy(fut);

    const mutex = blk: {
        if (thread_safe or builtin.mode == .Debug) {
            break :blk std.Thread.Mutex{};
        } else {
            break :blk std.Thread.Mutex{
                .impl = NoOpMutex{},
            };
        }
    };

    fut.* = .{
        .allocator = allocator,
        .loop = loop,
        .thread_safe = thread_safe,
        .mutex = mutex,
        .callbacks_arena = std.heap.ArenaAllocator.init(allocator)
    };

    fut.callbacks_arena_allocator = fut.callbacks_arena.allocator();
    fut.zig_callbacks = try BTree.init(fut.callbacks_arena_allocator);
    errdefer fut.zig_callbacks.release() catch unreachable;

    fut.python_callbacks = try BTree.init(fut.callbacks_arena_allocator);
    errdefer fut.python_callbacks.release() catch unreachable;

    fut.callbacks_array = LinkedList.init(fut.callbacks_arena_allocator);

    return fut;
}

pub inline fn release(self: *Future) void {
    self.callbacks_arena.deinit();
    const allocator = self.allocator;

    allocator.destroy(self);
}

pub usingnamespace @import("callback.zig");
pub usingnamespace @import("python/main.zig");


const Future = @This();
