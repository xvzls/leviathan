const Loop = @import("../main.zig");

const LinkedList = @import("../../utils/linked_list.zig");
const CallbackManager = @import("../../callback_manager.zig");

const std = @import("std");
const builtin = @import("builtin");

pub inline fn _dispatch(self: *Loop, callback: CallbackManager.Callback) !void {
    const ready_queue = &self.ready_tasks_queues[self.ready_tasks_queue_index];
    _ = try CallbackManager.append_new_callback(self.allocator, ready_queue, callback, Loop.MaxCallbacks);
}

pub inline fn _dispatch_threadsafe(self: *Loop, callback: CallbackManager.Callback) !void {
    const mutex = &self.mutex;
    mutex.lock();
    defer mutex.unlock();
    try _dispatch(self, callback);
}

pub const dispatch = if (builtin.single_threaded) _dispatch else _dispatch_threadsafe;
