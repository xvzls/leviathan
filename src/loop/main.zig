const std = @import("std");
const builtin = @import("builtin");

const python_c = @import("../utils/python_c.zig");

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

pub const MaxEvents = std.mem.page_size / @sizeOf(*Handle);

pub const EventSet = struct {
    events_num: usize = 0,
    events: []*Handle,
};

allocator: std.mem.Allocator,

ready_tasks_arenas: [2]std.heap.ArenaAllocator = undefined,
ready_tasks_arena_allocators: [2]std.mem.Allocator = undefined,
ready_tasks_queues: [2]LinkedList = undefined,
ready_tasks_queue_to_use: u8 = 0,
ready_tasks_queue_min_bytes_capacity: usize,
ready_tasks_queue_max_events_set: usize,

delayed_tasks: DeleyedQueue,
mutex: std.Thread.Mutex,

running: bool = false,
stopping: bool = false,
closed: bool = false,

py_loop: ?*Loop.constructors.PythonLoopObject = null,

pub fn init(allocator: std.mem.Allocator, rtq_min_capacity: usize) !*Loop {
    const loop = try allocator.create(Loop);
    errdefer allocator.destroy(loop);

    const max_numbers_of_events_set: usize = std.math.log2(rtq_min_capacity / MaxEvents + 1);

    loop.* = .{
        .allocator = allocator,
        .mutex = std.Thread.Mutex{},
        .ready_tasks_queue_min_bytes_capacity = rtq_min_capacity,
        .ready_tasks_queue_max_events_set = max_numbers_of_events_set,
        .delayed_tasks = .{
            .btree = try BTree.init(allocator),
        }
    };

    loop.ready_tasks_arenas[0] = std.heap.ArenaAllocator.init(allocator);
    loop.ready_tasks_arenas[1] = std.heap.ArenaAllocator.init(allocator);

    loop.ready_tasks_arena_allocators[0] = loop.ready_tasks_arenas[0].allocator();
    loop.ready_tasks_arena_allocators[1] = loop.ready_tasks_arenas[1].allocator();

    loop.ready_tasks_queues[0] = LinkedList.init(allocator);
    loop.ready_tasks_queues[1] = LinkedList.init(allocator);

    return loop;
}

pub fn release(self: *Loop) void {
    if (self.closed) @panic("Loop is already closed");

    inline for (&self.ready_tasks_arenas) |*ready_tasks_arena| {
        ready_tasks_arena.deinit();
    }

    const allocator = self.allocator;
    for (&self.ready_tasks_queues) |*ready_tasks_queue| {
        var node = ready_tasks_queue.first;
        while (node) |n| {
            const events_set: *EventSet = @alignCast(@ptrCast(n.data.?));
            allocator.free(events_set.events);
            allocator.destroy(events_set);
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
pub usingnamespace @import("python/main.zig");

const Loop = @This();
