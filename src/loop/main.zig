const std = @import("std");
const builtin = @import("builtin");

const python_c = @import("../utils/python_c.zig");

const LinkedList = @import("../utils/linked_list.zig");
const BTree = @import("../utils/btree/btree.zig");
const NoOpMutex = @import("../utils/no_op_mutex.zig");

pub const DeleyedQueue = struct {
    btree: *BTree,
    min_delay: ?u64 = null,
    min_node: ?*BTree.Node = null,
};

pub const ReadyQueue = struct {
    queue: LinkedList,
    last_node: ?LinkedList.Node
};

allocator: std.mem.Allocator,

ready_tasks_queue_index: u8 = 0,

temporal_handles_arenas: [2]std.heap.ArenaAllocator,
temporal_handles_arena_allocators: [2]std.mem.Allocator = undefined,

ready_tasks_queues: [2]ReadyQueue,

max_callbacks_sets_per_queue: [2]usize,
ready_tasks_queue_min_bytes_capacity: usize,

delayed_tasks: DeleyedQueue,
mutex: std.Thread.Mutex,

running: bool = false,
stopping: bool = false,
closed: bool = false,

py_loop: ?*Loop.constructors.PythonLoopObject = null,

pub fn init(allocator: std.mem.Allocator, rtq_min_capacity: usize) !*Loop {
    const loop = try allocator.create(Loop);
    errdefer allocator.destroy(loop);

    const max_callbacks_sets_per_queue = Loop.get_max_callbacks_sets(rtq_min_capacity, Loop.MaxCallbacks);

    loop.* = .{
        .allocator = allocator,
        .mutex = std.Thread.Mutex{},
        .temporal_handles_arenas = .{
            std.heap.ArenaAllocator.init(allocator),
            std.heap.ArenaAllocator.init(allocator),
        },
        .ready_tasks_queues = .{
            .{
                .queue = LinkedList.init(allocator),
                .last_node = null,
            },
            .{
                .queue = LinkedList.init(allocator),
                .last_node = null,
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

    loop.temporal_handles_arena_allocators[0] = loop.temporal_handles_arenas[0].allocator();
    loop.temporal_handles_arena_allocators[1] = loop.temporal_handles_arenas[1].allocator();

    return loop;
}

pub fn release(self: *Loop) void {
    if (self.closed) @panic("Loop is already closed");

    inline for (&self.temporal_handles_arenas) |*temporal_handles_arena| {
        temporal_handles_arena.deinit();
    }

    const allocator = self.allocator;
    for (&self.ready_tasks_queues) |*ready_tasks_queue| {
        var node = ready_tasks_queue.queue.first;
        while (node) |n| {
            const callbacks_set: *Loop.CallbacksSet = @alignCast(@ptrCast(n.data.?));
            for (callbacks_set.callbacks[0..callbacks_set.callbacks_num]) |callback| {
                _ = Loop.run_callback(callback, false);
            }
            allocator.free(callbacks_set.callbacks);
            allocator.destroy(callbacks_set);
            node = n.next;
            allocator.destroy(n);
        }
    }

    const delayed_tasks_btree = self.delayed_tasks.btree;
    while (delayed_tasks_btree.pop(null) != null) {}
    delayed_tasks_btree.release() catch unreachable;
    self.closed = true;
}


pub usingnamespace @import("control.zig");
pub usingnamespace @import("scheduling.zig");
pub usingnamespace @import("callbacks/main.zig");
pub usingnamespace @import("python/main.zig");

const Loop = @This();
