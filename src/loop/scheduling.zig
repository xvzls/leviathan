const Handle = @import("../handle/main.zig");
const Loop = @import("main.zig");

const LinkedList = @import("../utils/linked_list.zig");


pub inline fn call_soon(self: *Loop, handle: *Handle) !void {
    const queue = &self.ready_tasks_queues[self.ready_tasks_queue_to_use];
    try queue.append(handle);
}

pub inline fn call_soon_without_handle(
    self: *Loop, callback: Handle.HandleCallback, data: ?*anyopaque
) !void {
    const allocator = self.ready_tasks_arena_allocators[self.ready_tasks_queue_to_use];

    const handle = try allocator.create(Handle);
    errdefer allocator.destroy(handle);

    handle.init(self, allocator, callback, data, false);

    try self.call_soon(handle);
}

pub inline fn extend_ready_tasks(self: *Loop, new_tasks: *LinkedList) void {
    if (new_tasks.len == 0) return;

    const queue = &self.ready_tasks_queues[self.ready_tasks_queue_to_use];
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

pub inline fn call_soon_threadsafe(self: *Loop, handle: *Handle) !void {
    const mutex = &self.mutex;
    mutex.lock();
    defer mutex.unlock();
    try self.call_soon(handle);
}

pub inline fn call_soon_without_handle_threadsafe(
    self: *Loop, callback: Handle.HandleCallback, data: ?*anyopaque
) !void {
    const mutex = &self.mutex;
    mutex.lock();
    defer mutex.unlock();
    try self.call_soon_without_handle(callback, data);
}

pub inline fn extend_ready_tasks_threadsafe(self: *Loop, new_tasks: *LinkedList) void {
    const mutex = &self.mutex;
    mutex.lock();
    defer mutex.unlock();
    self.extend_ready_tasks(new_tasks);
}
