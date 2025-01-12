const std = @import("std");

const LinkedList = @import("../../../utils/linked_list.zig");

const CallbackManger = @import("../../../callback_manager.zig");
const Loop = @import("../../main.zig");

pub const Read = @import("read.zig");
pub const Write = @import("write.zig");
pub const Timer = @import("timer.zig");

pub const BlockingTaskData = struct {
    id: usize,
    data: CallbackManger.Callback,
    released: bool = true
};

pub const TotalItems = 1024;

pub const BlockingTasksSet = struct {
    allocator: std.mem.Allocator,
    ring: std.os.linux.IoUring,
    tasks_data: [TotalItems]BlockingTaskData,
    free_items: [TotalItems]usize,
    free_items_count: usize = TotalItems,
    free_item_index: usize = 0,
    busy_item_index: usize = 0,

    eventfd: std.posix.fd_t,

    node: LinkedList.Node,

    pub fn init(allocator: std.mem.Allocator, node: LinkedList.Node) !*BlockingTasksSet {
        const set = allocator.create(BlockingTasksSet) catch unreachable;
        errdefer allocator.destroy(set);

        const eventfd = try std.posix.eventfd(1, std.os.linux.EFD.NONBLOCK|std.os.linux.EFD.CLOEXEC);
        errdefer std.posix.close(eventfd);

        set.* = .{
            .allocator = allocator,
            .ring = try std.os.linux.IoUring.init(TotalItems, 0),
            .tasks_data = undefined,
            .free_items = undefined,
            .node = node,
            .eventfd = eventfd
        };
        errdefer set.ring.deinit();

        try set.ring.register_eventfd(eventfd);

        for (&set.free_items, 0..) |*item, i| {
            item.* = i;
        }

        for (&set.tasks_data) |*task_data| {
            task_data.* = .{
                .id = undefined,
                .data = undefined,
                .released = true
            };
        }

        node.data = set;
        return set;
    }

    pub fn deinit(self: *BlockingTasksSet) LinkedList.Node {
        if (self.free_items_count != TotalItems) {
            @panic("Free items count is not equal to total items");
        }
        const node = self.node;

        self.ring.unregister_eventfd() catch unreachable;
        std.posix.close(self.eventfd);

        self.ring.deinit();
        self.allocator.destroy(self);
        return node;
    }

    pub fn push(self: *BlockingTasksSet, data: CallbackManger.Callback) !*BlockingTaskData {
        @setRuntimeSafety(false);
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
            .released = false
        };

        return task_data;
    }

    pub inline fn pop(self: *BlockingTasksSet, data: *BlockingTaskData) !void {
        @setRuntimeSafety(false);
        const id = data.id;
        if (self.free_items_count == TotalItems) {
            return error.NoBusyItems;
        }else if (id >= TotalItems) {
            return error.InvalidID;
        }

        data.released = true;

        const busy_item_index = self.busy_item_index;
        self.free_items[busy_item_index] = id;
        self.busy_item_index = (busy_item_index + 1) % TotalItems;
        self.free_items_count += 1;
    }

    pub fn cancel_all(self: *BlockingTasksSet, loop: *Loop) !void {
        for (&self.tasks_data) |*task_data| {
            if (!task_data.released) {
                self.pop(task_data) catch unreachable;
                try Loop.Scheduling.Soon.dispatch(loop, task_data.data);
            }
        }
    }
};

pub const BlockingOperation = enum {
    WaitReadable,
    WaitWritable,
    PerformRead,
    PerformWrite,
    WaitTimer
};

pub const WaitData = struct {
    callback: CallbackManger.Callback,
    fd: std.os.linux.fd_t
};

pub const BlockingOperationData = union(BlockingOperation) {
    WaitReadable: WaitData,
    WaitWritable: WaitData,
    PerformRead: Read.PerformData,
    PerformWrite: Write.PerformData,
    WaitTimer: Timer.WaitData
};

inline fn get_blocking_tasks_set(
    allocator: std.mem.Allocator, epoll_fd: std.posix.fd_t,
    blocking_tasks_queue: *LinkedList
) !*BlockingTasksSet {
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
        _ = new_set.deinit();
        blocking_tasks_queue.unlink_node(new_node) catch unreachable;
    }

    var epoll_event: std.os.linux.epoll_event = .{
        .events = std.os.linux.EPOLL.IN | std.os.linux.EPOLL.ET,
        .data = std.os.linux.epoll_data{
            .ptr = @intFromPtr(new_set)
        }
    };

    blocking_tasks_queue.append_node(new_node);
    errdefer _ = blocking_tasks_queue.pop_node() catch unreachable;

    try std.posix.epoll_ctl(epoll_fd, std.os.linux.EPOLL.CTL_ADD, new_set.eventfd, &epoll_event);
    return new_set;
}

pub inline fn remove_tasks_set(
    epoll_fd: std.posix.fd_t, blocking_tasks_queue: *LinkedList,
    blocking_tasks_set: *BlockingTasksSet
) void {
    std.posix.epoll_ctl(epoll_fd, std.os.linux.EPOLL.CTL_DEL, blocking_tasks_set.eventfd, null) catch unreachable;
    const node = blocking_tasks_set.deinit();
    blocking_tasks_queue.unlink_node(node) catch unreachable;
}

pub fn queue(self: *Loop, event: BlockingOperationData) !void {
    const blocking_tasks_queue = &self.blocking_tasks_queue;
    const epoll_fd = self.blocking_tasks_epoll_fd;
    const blocking_tasks_set = try get_blocking_tasks_set(
        self.allocator, epoll_fd, blocking_tasks_queue
    );
    errdefer {
        if (blocking_tasks_set.free_items_count == TotalItems) {
            remove_tasks_set(epoll_fd, blocking_tasks_queue, blocking_tasks_set);
        }
    }

    switch (event) {
        .WaitReadable => |data| try Read.wait_ready(blocking_tasks_set, data),
        .WaitWritable => |data| try Write.wait_ready(blocking_tasks_set, data),
        .PerformRead => |data| try Read.perform(blocking_tasks_set, data),
        .PerformWrite => |data| try Write.perform(blocking_tasks_set, data),
        .WaitTimer => |data| try Timer.wait(blocking_tasks_set, data),
    }
}
