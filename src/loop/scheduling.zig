const Loop = @import("main.zig");

const LinkedList = @import("../utils/linked_list.zig");


const std = @import("std");

pub inline fn call_soon(self: *Loop, callback: Loop.Callback) !void {
    const ready_queue = &self.ready_tasks_queues[self.ready_tasks_queue_index];

    var callbacks: *Loop.CallbacksSet = undefined;
    var last_callbacks_set_len: usize = Loop.MaxCallbacks;
    var node = ready_queue.last_node;
    while (node) |n| {
        callbacks = @alignCast(@ptrCast(n.data.?));
        const callbacks_num = callbacks.callbacks_num;

        if (callbacks_num < callbacks.callbacks.len) {
            callbacks.callbacks[callbacks_num] = callback;
            callbacks.callbacks_num = callbacks_num + 1;

            ready_queue.last_node = n;
            return;
        }
        last_callbacks_set_len = callbacks_num;
        node = n.next;
    }

    const allocator = self.allocator;
    callbacks = try allocator.create(Loop.CallbacksSet);
    errdefer allocator.destroy(callbacks);

    const callbacks_arr = try allocator.alloc(Loop.Callback, last_callbacks_set_len * 2);
    errdefer allocator.free(callbacks_arr);

    callbacks.callbacks_num = 1;
    callbacks_arr[0] = callback;
    callbacks.callbacks = callbacks_arr;

    try ready_queue.queue.append(callbacks);
    ready_queue.last_node = ready_queue.queue.last;
}

pub inline fn extend_ready_tasks(self: *Loop, new_tasks: *LinkedList) void {
    if (new_tasks.len == 0) return;

    const queue = &self.ready_tasks_queues[self.ready_tasks_queue_index];
    if (queue.last) |last| {
        last.next = new_tasks.first;
    }else{
        queue.first = new_tasks.first;
    }
    queue.last = new_tasks.last;

    new_tasks.first = null;
    new_tasks.last = null;
    new_tasks.len = 0;
}

pub inline fn call_soon_threadsafe(self: *Loop, callback: Loop.Callback) !void {
    const mutex = &self.mutex;
    mutex.lock();
    defer mutex.unlock();
    try self.call_soon(callback);
}

pub inline fn extend_ready_tasks_threadsafe(self: *Loop, new_tasks: *LinkedList) void {
    const mutex = &self.mutex;
    mutex.lock();
    defer mutex.unlock();
    self.extend_ready_tasks(new_tasks);
}
