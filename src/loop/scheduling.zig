const Loop = @import("main.zig");

const LinkedList = @import("../utils/linked_list.zig");
const CallbackManager = @import("../callback_manager/main.zig");

const std = @import("std");

pub inline fn call_soon(self: *Loop, callback: CallbackManager.Callback) !void {
    const ready_queue = &self.ready_tasks_queues[self.ready_tasks_queue_index];
    _ = try CallbackManager.append_new_callback(self.allocator, ready_queue, callback, Loop.MaxCallbacks);
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

pub inline fn call_soon_threadsafe(self: *Loop, callback: CallbackManager.Callback) !void {
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
