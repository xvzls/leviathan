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

pub const EventsSet = struct {
    events_num: usize = 0,
    events: []*Handle,
};

allocator: std.mem.Allocator,

ready_tasks_queue_index: u8 = 0,

temporal_handles_arenas: [2]std.heap.ArenaAllocator,
temporal_handles_arena_allocators: [2]std.mem.Allocator = undefined,

ready_tasks_queues: [2]LinkedList,

max_events_sets_per_queue: [2]usize,
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

    const max_events_sets_per_queue = get_max_events_sets(rtq_min_capacity, MaxEvents);

    loop.* = .{
        .allocator = allocator,
        .mutex = std.Thread.Mutex{},
        .temporal_handles_arenas = .{
            std.heap.ArenaAllocator.init(allocator),
            std.heap.ArenaAllocator.init(allocator),
        },
        .ready_tasks_queues = .{
            LinkedList.init(allocator),
            LinkedList.init(allocator),
        },
        .max_events_sets_per_queue = .{
            max_events_sets_per_queue,
            max_events_sets_per_queue,
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

pub inline fn get_max_events_sets(rtq_min_capacity: usize, events_set_length: usize) usize {
    return @max(
        @as(usize, @intFromFloat(
            @ceil(
                @log2(
                    @as(f64, @floatFromInt(rtq_min_capacity)) / @as(f64, @floatFromInt(events_set_length * @sizeOf(*Handle))) + 1.0
                )
            )
        )), 2
    );
}

pub fn release(self: *Loop) void {
    if (self.closed) @panic("Loop is already closed");

    inline for (&self.temporal_handles_arenas) |*temporal_handles_arena| {
        temporal_handles_arena.deinit();
    }

    const allocator = self.allocator;
    for (&self.ready_tasks_queues) |*ready_tasks_queue| {
        var node = ready_tasks_queue.first;
        while (node) |n| {
            const events_set: *EventsSet = @alignCast(@ptrCast(n.data.?));
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
