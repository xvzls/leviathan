const std = @import("std");
const LinkedList = @import("../utils/linked_list.zig");
const BTree = @import("../utils/btree/btree.zig");


pub const delayed_queue = struct {
    btree: *BTree,
    min_delay: ?u64,
    min_node: ?*BTree.Node,
};


allocator: std.mem.Allocator,
ready_tasks: LinkedList,
delayed_tasks: delayed_queue,
mutex: std.Thread.Mutex = .{},

pending_io_tasks: LinkedList,
ready_io_tasks: LinkedList,
io_mutex: std.Thread.Mutex = .{},

io_proessing_workers: ?[]std.Thread = null,

pub fn init(allocator: std.mem.Allocator, io_workers: usize) !*Loop {
    const loop = try allocator.create(Loop);
    loop.* = .{
        .allocator = allocator,
        .ready_tasks = LinkedList.init(allocator),
        .ready_io_tasks = LinkedList.init(allocator),
        .pending_io_tasks = LinkedList.init(allocator),
        .delayed_tasks = .{
            .btree = try BTree.init(allocator),
            .min_delay = null,
            .min_node = null
        }
    };

    _ = io_workers; // TODO
    return loop;
}

pub fn release(loop: *Loop) void {
    const allocator = loop.allocator;
    const leak: bool = (
        loop.ready_io_tasks.len > 0 or
        loop.pending_io_tasks.len > 0 or
        loop.ready_tasks.len > 0 or
        loop.delayed_tasks.min_delay != null
    );

    if (leak) {
        @panic("Loop leak");
    }

    loop.delayed_tasks.btree.release() catch unreachable;
    allocator.destroy(loop);
}


pub usingnamespace @import("python/main.zig");

const Loop = @This();
