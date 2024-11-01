const LinkedList = @import("../utils/linked_list.zig");

const Handle = @import("../handle/main.zig");
const Loop = @import("main.zig");

const utils = @import("../utils/utils.zig");

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

inline fn call_once(self: *Loop) bool {
    var queue_index: u8 = undefined;
    const queue = get_ready_events(self, &queue_index) orelse return true;

    var _node: ?LinkedList.Node = queue.first;
    if (_node == null) {
        self.stopping = true;
        return false;
    }

    var should_stop: bool = false;
    while (_node) |node| {
        const handle: *Handle = @alignCast(@ptrCast(node.data.?));
        if (should_stop) {
            const handle_mutex = &handle.mutex;
            handle_mutex.lock();
            handle.cancelled = true;
            handle_mutex.unlock();
        }

        if (handle.run_callback()) {
            should_stop = true;
        }

        _node = node.next;
    }

    const arena = &self.ready_tasks_arenas[queue_index];
    const not_deallocated = arena.reset(.{
        .retain_with_limit = self.ready_tasks_queue_min_bytes_capacity
    });
    if (not_deallocated) {
        _ = arena.reset(.free_all);
    }

    queue.first = null;
    queue.last = null;
    queue.len = 0;

    return true;
}

pub fn run_forever(self: *Loop) !void {
    const mutex = &self.mutex;
    {
        mutex.lock();
        defer mutex.unlock();

        if (self.closed) {
            utils.put_python_runtime_error_message("Loop is closed\x00");
            return error.PythonError;
        }

        if (self.stopping) {
            utils.put_python_runtime_error_message("Loop is stopping\x00");
            return error.PythonError;
        }

        if (self.running) {
            utils.put_python_runtime_error_message("Loop is already running\x00");
            return error.PythonError;
        }

        self.running = true;
        self.stopping = false;
    }

    while (call_once(self)) {}

    mutex.lock();
    self.running = false;
    self.stopping = false;
    mutex.unlock();
}
