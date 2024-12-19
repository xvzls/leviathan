const std = @import("std");
const builtin = @import("builtin");

const CallbackManager = @import("../callback_manager.zig");
const python_c = @import("python_c");

const LinkedList = @import("../utils/linked_list.zig");
const BTree = @import("../utils/btree/btree.zig");

pub const DeleyedQueue = struct {
    btree: *BTree,
    min_delay: ?u64 = null,
    min_node: ?*BTree.Node = null,
};

pub const MaxCallbacks = 128;

allocator: std.mem.Allocator,

ready_tasks_queue_index: u8 = 0,

ready_tasks_queues: [2]CallbackManager.CallbacksSetsQueue,

max_callbacks_sets_per_queue: [2]usize,
ready_tasks_queue_min_bytes_capacity: usize,

delayed_tasks: DeleyedQueue,
mutex: std.Thread.Mutex,

running: bool = false,
stopping: bool = false,
closed: bool = false,
released: bool = false,

pub fn init(self: *Loop, allocator: std.mem.Allocator, rtq_min_capacity: usize) !void {
    const max_callbacks_sets_per_queue = CallbackManager.get_max_callbacks_sets(
        rtq_min_capacity, MaxCallbacks
    );

    self.* = .{
        .allocator = allocator,
        .mutex = std.Thread.Mutex{},
        .ready_tasks_queues = .{
            .{
                .queue = LinkedList.init(allocator),
            },
            .{
                .queue = LinkedList.init(allocator),
            },
        },
        .max_callbacks_sets_per_queue = .{
            max_callbacks_sets_per_queue,
            max_callbacks_sets_per_queue,
        },
        .ready_tasks_queue_min_bytes_capacity = rtq_min_capacity,
        .delayed_tasks = .{
            .btree = try BTree.init(allocator),
        }
    };
}

pub fn release(self: *Loop) void {
    if (!self.closed) {
        @panic("Loop is not closed, can't be deallocated");
    }

    if (self.running) {
        @panic("Loop is running, can't be deallocated");
    }

    const allocator = self.allocator;
    for (&self.ready_tasks_queues) |*ready_tasks_queue| {
        const queue = &ready_tasks_queue.queue;
        for (0..queue.len) |_| {
             const set: *CallbackManager.CallbacksSet = @alignCast(@ptrCast(queue.pop() catch unreachable));
             CallbackManager.release_set(allocator, set);
        }
    }

    const delayed_tasks_btree = self.delayed_tasks.btree;
    while (delayed_tasks_btree.pop(null) != null) {}
    delayed_tasks_btree.release() catch unreachable;

    self.released = true;
}

pub usingnamespace @import("control.zig");
pub usingnamespace @import("scheduling.zig");
pub usingnamespace @import("python/main.zig");

const Loop = @This();
