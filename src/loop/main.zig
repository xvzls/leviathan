const std = @import("std");
const builtin = @import("builtin");

const CallbackManager = @import("../callback_manager.zig");
const python_c = @import("python_c");

const LinkedList = @import("../utils/linked_list.zig");

pub const MaxCallbacks = 128;

allocator: std.mem.Allocator,

ready_tasks_queue_index: u8 = 0,

ready_tasks_queues: [2]CallbackManager.CallbacksSetsQueue,
blocking_tasks_queue: LinkedList,

max_callbacks_sets_per_queue: [2]usize,
ready_tasks_queue_min_bytes_capacity: usize,

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
        .blocking_tasks_queue = LinkedList.init(allocator)
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

    if (!self.blocking_tasks_queue.is_empty()) {
        // TODO: Implement logic for releasing blocking tasks
        @panic("Loop has blocking tasks, can't be deallocated");
    }
    self.released = true;
}

pub const Runner = @import("runner.zig");
pub const Scheduling = @import("scheduling/main.zig");
pub const Python = @import("python/main.zig");

const Loop = @This();
