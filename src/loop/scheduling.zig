const LinkedList = @import("../utils/linked_list.zig");

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

inline fn get_ready_events(loop: *Loop, index: *u8) ?*LinkedList {
    const mutex = &loop.mutex;
    mutex.lock();
    defer mutex.unlock();

    if (loop.stopping) {
        return null;
    }

    const ready_tasks_queue_to_use = loop.ready_tasks_queue_to_use;
    const ready_tasks_queue = &loop.ready_tasks_queues[ready_tasks_queue_to_use];
    index.* = ready_tasks_queue_to_use;
    loop.ready_tasks_queue_to_use = 1 - ready_tasks_queue_to_use;

    return ready_tasks_queue;
}

pub inline fn call_once(self: *Loop) bool {
    var queue_index: u8 = undefined;
    const queue = get_ready_events(self, &queue_index) orelse return true;

    var _node: ?LinkedList.Node = queue.first;
    if (_node == null) {
        self.stopping = true;
        return true;
    }

    while (_node) |node| {
        const handle: *Handle = @alignCast(@ptrCast(node.data.?));
        if (handle.run_callback()) {
            break;
        }

        _node = node.next;
    }

    self.ready_tasks_arenas[queue_index].reset(.{ .retain_with_limit = self.ready_tasks_queue_min_bytes_capacity });
    queue.first = null;
    queue.last = null;
    queue.len = 0;

    return false;
}
