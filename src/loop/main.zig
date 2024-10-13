const std = @import("std");
const builtin = @import("builtin");

const LinkedList = @import("../utils/linked_list.zig");
const BTree = @import("../utils/btree/btree.zig");
const NoOpMutex = @import("../utils/no_op_mutex.zig");

const Handle = @import("../handle/main.zig");


pub const DeleyedQueue = struct {
    btree: *BTree,
    min_delay: ?u64,
    min_node: ?*BTree.Node,
};

pub const EventType = enum (u8) {
    INMEDIATE,
    DELAYED
};

pub const HandlesArenaAllocatorConfig = struct {
    arena_allocator: std.heap.ArenaAllocator = undefined,
    allocator: std.mem.Allocator = undefined,
    bytes_allocated: usize = 0,
    max_bytes_allocated: usize = 0,
    must_be_freed: bool = false,
};

allocator: std.mem.Allocator,

handles_arena_allocators: [2]HandlesArenaAllocatorConfig,
handles_arena_allocator_to_use: u8,
max_bytes_capacity_for_handles: usize,
min_bytes_capacity_for_handles: usize,

ready_tasks_arena_allocators: [2]std.heap.ArenaAllocator,
ready_tasks_queues: [2]LinkedList,
ready_tasks_queue_to_use: u8,
ready_tasks_queue_min_bytes_capacity: usize,

delayed_tasks: DeleyedQueue,
mutex: std.Thread.Mutex,


pub fn init(
    allocator: std.mem.Allocator, thread_safe: bool, h_max_capacity: usize,
    h_min_capacity: usize, rtq_min_capacity: usize
) !*Loop {
    const loop = try allocator.create(Loop);
    errdefer allocator.destroy(loop);

    loop.allocator = allocator;
    loop.mutex =  blk: {
        if (thread_safe or builtin.mode == .Debug) {
            break :blk std.Thread.Mutex{};
        } else {
            break :blk std.Thread.Mutex{
                .impl = NoOpMutex{},
            };
        }
    };

    loop.handles_arena_allocators[0] = .{};
    loop.handles_arena_allocators[0].arena_allocator = std.heap.ArenaAllocator.init(allocator);
    loop.handles_arena_allocators[0].allocator = loop.handles_arena_allocators[0].arena_allocator.allocator();

    loop.handles_arena_allocators[1] = .{};
    loop.handles_arena_allocators[1].arena_allocator = std.heap.ArenaAllocator.init(allocator);
    loop.handles_arena_allocators[1].allocator = loop.handles_arena_allocators[1].arena_allocator.allocator();

    loop.handles_arena_allocator_to_use = 0;
    loop.max_bytes_capacity_for_handles = h_max_capacity;
    loop.min_bytes_capacity_for_handles = h_min_capacity;

    loop.ready_tasks_arena_allocators[0] = std.heap.ArenaAllocator.init(allocator);
    loop.ready_tasks_arena_allocators[1] = std.heap.ArenaAllocator.init(allocator);
    loop.ready_tasks_queues[0] = LinkedList.init(loop.ready_tasks_arena_allocators[0].allocator());
    loop.ready_tasks_queues[1] = LinkedList.init(loop.ready_tasks_arena_allocators[1].allocator());
    loop.ready_tasks_queue_min_bytes_capacity = rtq_min_capacity;
    loop.ready_tasks_queue_to_use = 0;

    loop.delayed_tasks = .{
        .btree = try BTree.init(allocator),
        .min_delay = null,
        .min_node = null
    };

    return loop;
}

pub inline fn alloc_handle_data(
    self: *Loop, comptime item_size: usize, index: ?*u8
) std.mem.Allocator {
    var handles_arena_allocator_to_use = self.handles_arena_allocator_to_use;

    var handles_arena_allocator: *HandlesArenaAllocatorConfig = &self.handles_arena_allocators[handles_arena_allocator_to_use];
    if (handles_arena_allocator.max_bytes_allocated > self.max_bytes_capacity_for_handles) {
        handles_arena_allocator.must_be_freed = true;
        handles_arena_allocator_to_use = (handles_arena_allocator_to_use + 1) % 2;
        handles_arena_allocator = &self.handles_arena_allocators[handles_arena_allocator_to_use];
        self.handles_arena_allocator_to_use = handles_arena_allocator_to_use;
    }

    const handles_allocated = handles_arena_allocator.bytes_allocated + item_size;
    handles_arena_allocator.max_bytes_allocated = @max(handles_arena_allocator.max_bytes_allocated, handles_allocated);
    handles_arena_allocator.bytes_allocated = handles_allocated;

    if (index) |ptr| {
        ptr.* = handles_arena_allocator_to_use;
    }

    return handles_arena_allocator.allocator;
}

pub inline fn free_handle_data(self: *Loop, item_size: usize, index: u8) void {
    const handles_arena_allocator: *HandlesArenaAllocatorConfig = &self.handles_arena_allocators[index];
    handles_arena_allocator.bytes_allocated -= item_size;
    if (handles_arena_allocator.must_be_freed and handles_arena_allocator.bytes_allocated == 0) {
        const preheated = handles_arena_allocator.arena_allocator.reset(
            .{ .retain_with_limit = self.min_bytes_capacity_for_handles }
        );
        if (!preheated) {
            _ = handles_arena_allocator.arena_allocator.reset(.free_all);
        }
        handles_arena_allocator.must_be_freed = false;
    }
}

pub fn release(loop: *Loop) void {
    const allocator = loop.allocator;

    inline for (&loop.handles_arena_allocators) |*handles_arena_allocator| {
        handles_arena_allocator.arena_allocator.deinit();
    }

    inline for (&loop.ready_tasks_arena_allocators) |*ready_tasks_arena_allocator| {
        ready_tasks_arena_allocator.deinit();
    }

    const delayed_tasks_btree = loop.delayed_tasks.btree;
    while (delayed_tasks_btree.pop(null) != null) {}

    allocator.destroy(loop);
}


pub usingnamespace @import("python/main.zig");

const Loop = @This();
