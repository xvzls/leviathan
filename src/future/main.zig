const std = @import("std");
const builtin = @import("builtin");

const Loop = @import("../loop/main.zig");
const CallbackManager = @import("../callback_manager/main.zig");

const LinkedList = @import("../utils/linked_list.zig");
const BTree = @import("../utils/btree/btree.zig");

pub const FutureStatus = enum {
    PENDING, FINISHED, CANCELED
};

allocator: std.mem.Allocator,

result: ?*anyopaque = null,
status: FutureStatus = .PENDING,

mutex: std.Thread.Mutex,

callbacks_arena: std.heap.ArenaAllocator,
callbacks_arena_allocator: std.mem.Allocator = undefined,
callbacks_queue: CallbackManager.CallbacksSetsQueue = undefined,
python_callbacks: *BTree = undefined,
zig_callbacks: *BTree = undefined,
loop: ?*Loop,

py_future: ?*Future.constructors.PythonFutureObject = null,


pub fn init(allocator: std.mem.Allocator, loop: *Loop) !*Future {
    const fut = try allocator.create(Future);
    errdefer allocator.destroy(fut);

    const mutex = std.Thread.Mutex{};

    fut.* = .{
        .allocator = allocator,
        .loop = loop,
        .mutex = mutex,
        .callbacks_arena = std.heap.ArenaAllocator.init(allocator)
    };

    fut.callbacks_arena_allocator = fut.callbacks_arena.allocator();
    fut.zig_callbacks = try BTree.init(fut.callbacks_arena_allocator);
    errdefer fut.zig_callbacks.release() catch unreachable;

    fut.python_callbacks = try BTree.init(fut.callbacks_arena_allocator);
    errdefer fut.python_callbacks.release() catch unreachable;

    fut.callbacks_queue = .{
        .queue = LinkedList.init(fut.callbacks_arena_allocator),
        .last_set = null
    };

    return fut;
}

pub inline fn release(self: *Future) void {
    if (self.status == .PENDING) {
        _ = CallbackManager.execute_callbacks(&self.callbacks_queue, .Stop, false);
    }

    self.callbacks_arena.deinit();
    const allocator = self.allocator;

    allocator.destroy(self);
}

pub usingnamespace @import("callback.zig");
pub usingnamespace @import("python/main.zig");


const Future = @This();
