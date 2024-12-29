const std = @import("std");

const LinkedList = @import("../../../utils/linked_list.zig");

const CallbackManger = @import("../../../callback_manager.zig");
const Loop = @import("../../main.zig");

pub const Read = @import("read.zig");
pub const Write = @import("write.zig");

pub const BlockingTaskData = struct {
    id: usize,
    data: CallbackManger.Callback
};

const TotalItems = 1024;

pub const BlockingTasksSet = struct {
    ring: std.os.linux.IoUring,
    tasks_data: [TotalItems]BlockingTaskData,
    free_items: [TotalItems]usize,
    free_items_count: usize = TotalItems,
    free_item_index: usize = 0,
    busy_item_index: usize = 0,

    node: LinkedList.Node,

    pub fn init(allocator: std.mem.Allocator, node: LinkedList.Node) !*BlockingTasksSet {
        const set = allocator.create(BlockingTasksSet) catch unreachable;
        errdefer allocator.destroy(set);

        set.* = .{
            .ring = try std.os.linux.IoUring.init(TotalItems),
            .tasks_data = undefined,
            .free_items = undefined,
            .node = node
        };

        for (set.free_items, 0..) |*item, i| {
            item.* = i;
        }

        node.data = set;
        return set;
    }

    pub fn deinit(self: *BlockingTasksSet, allocator: std.mem.Allocator) LinkedList.Node {
        if (self.free_items_count != TotalItems) {
            @panic("Free items count is not equal to total items");
        }
        const node = self.node;

        self.ring.deinit();
        allocator.destroy(self);
        return node;
    }

    pub fn get_from_task_data(data: *BlockingTaskData) *BlockingTaskData {
        const ptr = @intFromPtr(data) - data.id * @sizeOf(BlockingTaskData) - @offsetOf(BlockingTaskData, "tasks_data"); 
        return @ptrFromInt(ptr);
    }

    pub fn push(self: *BlockingTasksSet, data: CallbackManger.Callback) !*BlockingTaskData {
        if (self.free_items_count == 0) {
            return error.NoFreeItems;
        }

        const free_item_index = self.free_item_index;
        const index = self.free_items[free_item_index];
        self.free_item_index = (free_item_index + 1) % TotalItems;
        self.free_items_count -= 1;

        const task_data: *BlockingTaskData = &self.tasks_data[index];
        task_data.* = .{
            .id = index,
            .data = data,
        };

        return task_data;
    }

    pub fn pop(self: *BlockingTasksSet, id: usize) !void {
        if (self.free_items_count == TotalItems) {
            return error.NoBusyItems;
        }else if (id >= TotalItems) {
            return error.InvalidID;
        }

        const busy_item_index = self.busy_item_index;
        self.free_items[busy_item_index] = id;
        self.busy_item_index = (busy_item_index + 1) % TotalItems;
        self.free_items_count += 1;
    }
};

pub const BlockingOperation = enum {
    WaitReadable,
    WaitWritable,
    PerformRead,
    PerformWrite,
    WaitTimer
};

pub const WaitingOperationData = struct {
    callback: CallbackManger.Callback,
    fd: std.os.linux.fd_t
};

pub const BlockingOperationData = union(BlockingOperation) {
    WaitReadable: WaitingOperationData,
    WaitWritable: WaitingOperationData,
    WaitTimer: CallbackManger.Callback
};

inline fn get_blocking_tasks_set(allocator: std.mem.Allocator, blocking_tasks_queue: *LinkedList) !*BlockingTasksSet {
    if (blocking_tasks_queue.last) |node| {
        const set: *BlockingTasksSet = @alignCast(@ptrCast(node.data.?));
        if (set.free_items_count > 0) {
            return set;
        }
    }

    const new_node = try blocking_tasks_queue.create_new_node(null);
    errdefer blocking_tasks_queue.release_node(new_node);

    const new_set = try BlockingTasksSet.init(allocator, new_node);
    errdefer {
        _ = new_set.deinit(allocator);
        blocking_tasks_queue.unlink_node(new_node);
    }

    try blocking_tasks_queue.append(new_set);
    return new_set;
}

pub fn remove_last_tasks_set(blocking_tasks_queue: *LinkedList, blocking_tasks_set: *BlockingTasksSet) void {
    const node = blocking_tasks_set.deinit();
    blocking_tasks_queue.unlink_node(node);
}

pub fn queue(self: *Loop, event: BlockingOperation, data: BlockingOperationData) !void {
    const blocking_tasks_queue = &self.blocking_tasks_queue;
    const blocking_tasks_set = try get_blocking_tasks_set(self.allocator, blocking_tasks_queue);
    errdefer {
        if (blocking_tasks_set.free_items_count == TotalItems) {
            remove_last_tasks_set(blocking_tasks_queue, blocking_tasks_set);
        }
    }

    switch (event) {
        .WaitReadable => Read.wait_readable(blocking_tasks_set, data.WaitReadable),
        .WaitWritable => Write.wait_writable(blocking_tasks_set, data.WaitWritable),
        .WaitTimer => 
    }

}
