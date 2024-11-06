const LinkedList = @import("../utils/linked_list.zig");

const Handle = @import("../handle/main.zig");
const Loop = @import("main.zig");

const utils = @import("../utils/utils.zig");
const python_c = @import("../utils/python_c.zig");
const PyObject = *python_c.PyObject;

const std = @import("std");

const CallOnceReturn = enum {
    Continue, Stop, Exception
};


inline fn call_once(
    max_number_of_events_set: usize, queue: *LinkedList,
    arena: *std.heap.ArenaAllocator
) CallOnceReturn {
    var _node: ?LinkedList.Node = queue.first orelse return .Stop;

    var can_execute: bool = true;
    while (_node) |node| {
        _node = node.next;
        const events_set: *Loop.EventSet = @alignCast(@ptrCast(node.data.?));
        const events_num = events_set.events_num;
        if (events_num == 0) return .Stop;

        for (events_set.events[0..events_num]) |handle| {
            if (handle.run_callback(can_execute)) {
                can_execute = false;
            }
        }
        events_set.events_num = 0;
    }

    var queue_len = queue.len;
    if (queue_len > max_number_of_events_set) {
        while (queue_len > max_number_of_events_set) |queue_len -= 1| {
            const node = queue.pop_node();
            const events_set = queue.pop().?
        }
    }

    // TODO: Clear queue to ready_tasks_queue_min_bytes_capacity
    _ = arena.reset(.free_all);

    if (!can_execute) {
        return .Exception;
    }

    return .Continue;
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

    defer {
        mutex.lock();
        self.running = false;
        self.stopping = false;
        mutex.unlock();
    }

    var ready_tasks_queue_to_use = self.ready_tasks_queue_to_use;
    const ready_tasks_queues: []LinkedList = &self.ready_tasks_queues;
    const ready_tasks_arenas: []std.heap.ArenaAllocator = &self.ready_tasks_arenas;
    const ready_tasks_queue_min_bytes_capacity = self.ready_tasks_queue_min_bytes_capacity;
    while (!self.stopping) {
        const old_index = ready_tasks_queue_to_use;
        ready_tasks_queue_to_use = 1 - ready_tasks_queue_to_use;
        self.ready_tasks_queue_to_use = ready_tasks_queue_to_use;

        switch (
            call_once(
                ready_tasks_queue_min_bytes_capacity, &ready_tasks_queues[old_index],
                &ready_tasks_arenas[old_index]
            )
        ) {
            .Continue => {},
            .Stop => break,
            .Exception => return error.PythonError,
        }
    }
}
