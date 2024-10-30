const Handle = @import("../handle/main.zig");
const Loop = @import("main.zig");


pub inline fn call_soon(self: *Loop, handle: *Handle) !void {
    const queue = &self.ready_tasks_queues[self.ready_tasks_queue_to_use];
    try queue.append(handle);
}

pub inline fn call_soon_without_handle(
    self: *Loop, callback: *const fn (?*anyopaque) bool, data: ?*anyopaque
) !void {
    const allocator = self.ready_tasks_arena_allocators[self.ready_tasks_queue_to_use];

    const handle = try allocator.create(Handle);
    errdefer allocator.destroy(handle);

    handle.init(self, allocator, callback, data, false);

    try self.call_soon(handle);
}

pub inline fn call_soon_threadsafe(self: *Loop, handle: *Handle) !void {
    const mutex = &self.mutex;
    mutex.lock();
    defer mutex.unlock();
    try self.call_soon(handle);
}

pub inline fn call_soon_without_handle_threadsafe(
    self: *Loop, callback: *const fn (?*anyopaque) bool, data: ?*anyopaque
) !void {
    const mutex = &self.mutex;
    mutex.lock();
    defer mutex.unlock();
    try self.call_soon_without_handle(callback, data);
}

