const std = @import("std");
const builtin = @import("builtin");

const LinkedList = @import("../utils/linked_list.zig");
const BTree = @import("../utils/btree/btree.zig");
const NoOpMutex = @import("../utils/no_op_mutex.zig");

const Handle = @import("../handle/main.zig");


pub const DeleyedQueue = struct {
    btree: *BTree,
    min_delay: ?u64 = null,
    min_node: ?*BTree.Node = null,
};

pub const EventType = enum {
    INMEDIATE,
    DELAYED
};

allocator: std.mem.Allocator,

ready_tasks_arenas: [2]std.heap.ArenaAllocator = undefined,
ready_tasks_arena_allocators: [2]std.mem.Allocator = undefined,
ready_tasks_queues: [2]LinkedList = undefined,
ready_tasks_queue_to_use: u8 = 0,
ready_tasks_queue_min_bytes_capacity: usize,

delayed_tasks: DeleyedQueue,
mutex: std.Thread.Mutex,
thread_safe: bool,

running: bool = false,
stopping: bool = false,
closed: bool = false,

pub fn init(self: *Loop, allocator: std.mem.Allocator, thread_safe: bool, rtq_min_capacity: usize) !void {
    self.* = .{
        .allocator = allocator,
        .thread_safe = thread_safe,
        .mutex = blk: {
            if (thread_safe or builtin.mode == .Debug) {
                break :blk std.Thread.Mutex{};
            } else {
                break :blk std.Thread.Mutex{
                    .impl = NoOpMutex{},
                };
            }
        },
        .ready_tasks_queue_min_bytes_capacity = rtq_min_capacity,
        .delayed_tasks = .{
            .btree = try BTree.init(allocator),
        }
    };

    self.ready_tasks_arenas[0] = std.heap.ArenaAllocator.init(allocator);
    self.ready_tasks_arenas[1] = std.heap.ArenaAllocator.init(allocator);

    self.ready_tasks_arena_allocators[0] = self.ready_tasks_arenas[0].allocator();
    self.ready_tasks_arena_allocators[1] = self.ready_tasks_arenas[1].allocator();

    self.ready_tasks_queues[0] = LinkedList.init(self.ready_tasks_arena_allocators[0]);
    self.ready_tasks_queues[1] = LinkedList.init(self.ready_tasks_arena_allocators[1]);
}

pub fn release(loop: *Loop) void {
    inline for (&loop.handles_arena_allocators) |*handles_arena_allocator| {
        handles_arena_allocator.arena_allocator.deinit();
    }

    inline for (&loop.ready_tasks_arena_allocators) |*ready_tasks_arena_allocator| {
        ready_tasks_arena_allocator.deinit();
    }

    const delayed_tasks_btree = loop.delayed_tasks.btree;
    while (delayed_tasks_btree.pop(null) != null) {}
}


pub usingnamespace @import("scheduling.zig");
pub usingnamespace @import("python/main.zig");

const Loop = @This();
