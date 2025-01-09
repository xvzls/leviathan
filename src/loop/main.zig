const std = @import("std");
const builtin = @import("builtin");

const CallbackManager = @import("../callback_manager.zig");
const python_c = @import("python_c");

const LinkedList = @import("../utils/linked_list.zig");

pub const MaxCallbacks = 128;

allocator: std.mem.Allocator,

ready_tasks_queue_index: u8 = 0,

ready_tasks_queues: [2]CallbackManager.CallbacksSetsQueue,

blocking_tasks_epoll_fd: std.posix.fd_t = -1,
blocking_ready_epoll_events: []std.os.linux.epoll_event,
blocking_tasks_queue: LinkedList,
blocking_ready_tasks: []std.os.linux.io_uring_cqe,

unlock_epoll_fd: std.posix.fd_t = -1,
epoll_locked: bool = false,

max_callbacks_sets_per_queue: [2]usize,
ready_tasks_queue_min_bytes_capacity: usize,

mutex: std.Thread.Mutex,

unix_signals: UnixSignals,

running: bool = false,
stopping: bool = false,
initialized: bool = false,


pub fn init(self: *Loop, allocator: std.mem.Allocator, rtq_min_capacity: usize) !void {
    if (self.initialized) {
        @panic("Loop is already initialized");
    }

    const max_callbacks_sets_per_queue = CallbackManager.get_max_callbacks_sets(
        rtq_min_capacity, MaxCallbacks
    );

    const blocking_ready_tasks = try allocator.alloc(std.os.linux.io_uring_cqe, Scheduling.IO.TotalItems);
    errdefer allocator.free(blocking_ready_tasks);

    const blocking_ready_epoll_events = try allocator.alloc(std.os.linux.epoll_event, 256);
    errdefer allocator.free(blocking_ready_epoll_events);

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
        .blocking_tasks_queue = LinkedList.init(allocator),
        .blocking_ready_tasks = blocking_ready_tasks,
        .blocking_tasks_epoll_fd = try std.posix.epoll_create1(0),
        .blocking_ready_epoll_events = blocking_ready_epoll_events,
        .unix_signals = undefined
    };
    errdefer {
        std.posix.close(self.blocking_tasks_epoll_fd);
    }

    try UnixSignals.init(self);

    self.initialized = true;
}

pub fn release(self: *Loop) void {
    if (self.running) {
        @panic("Loop is running, can't be deallocated");
    }

    const allocator = self.allocator;
    const blocking_tasks_queue = &self.blocking_tasks_queue;
    if (!blocking_tasks_queue.is_empty()) {
        for (0..blocking_tasks_queue.len) |_| {
            const node: LinkedList.Node = @alignCast(
                @ptrCast(blocking_tasks_queue.pop_node() catch unreachable)
            );
            const set: *Scheduling.IO.BlockingTasksSet = @alignCast(@ptrCast(node.data.?));
            set.cancel_all(self) catch unreachable;
            _ = set.deinit();
            blocking_tasks_queue.release_node(node);
        }
    }

    for (&self.ready_tasks_queues) |*ready_tasks_queue| {
        _  = CallbackManager.execute_callbacks(allocator, ready_tasks_queue, .Stop, false);
        const queue = &ready_tasks_queue.queue;
        for (0..queue.len) |_| {
             const set: *CallbackManager.CallbacksSet = @alignCast(@ptrCast(queue.pop() catch unreachable));
             CallbackManager.release_set(allocator, set);
        }
    }

    if (self.blocking_tasks_epoll_fd != -1) {
        std.posix.close(self.blocking_tasks_epoll_fd);
    }

    if (self.unlock_epoll_fd != -1) {
        std.posix.close(self.unlock_epoll_fd);
    }

    self.unix_signals.deinit();

    allocator.free(self.blocking_ready_epoll_events);
    allocator.free(self.blocking_ready_tasks);

    self.initialized = false;
}

pub const Runner = @import("runner.zig");
pub const Scheduling = @import("scheduling/main.zig");
pub const UnixSignals = @import("unix_signals.zig");
pub const Python = @import("python/main.zig");

const Loop = @This();
