const LinkedList = @import("../utils/linked_list.zig");

const Handle = @import("../handle/main.zig");
const Loop = @import("main.zig");

const utils = @import("../utils/utils.zig");
const allocator = utils.allocator;
const python_c = @import("../utils/python_c.zig");
const PyObject = *python_c.PyObject;

const std = @import("std");

const CallOnceReturn = enum {
    Continue, Stop, Exception
};

inline fn remove_exceded_events(loop: *Loop, index: usize, queue: *LinkedList, max_number_of_events_set: usize) void {
    var queue_len = queue.len;
    if (queue_len <= max_number_of_events_set) return;

    var node = queue.first.?;
    while (queue_len > max_number_of_events_set) : (queue_len -= 1) {
        const events_set: *Loop.EventsSet = @alignCast(@ptrCast(node.data.?));

        allocator.free(events_set.events);
        allocator.destroy(events_set);

        const next_node = node.next.?;
        allocator.destroy(node);
        node = next_node;
    }

    const events_set: *Loop.EventsSet = @alignCast(@ptrCast(node.data.?));
    node.prev = null;
    queue.first = node;
    queue.len = queue_len;

    loop.max_events_sets_per_queue[index] = Loop.get_max_events_sets(
        loop.ready_tasks_queue_min_bytes_capacity, events_set.events.len
    );
}


inline fn call_once(
    loop: *Loop, index: usize, max_number_of_events_set: usize,
    queue: *LinkedList, arena: *std.heap.ArenaAllocator
) CallOnceReturn {
    var _node: ?LinkedList.Node = queue.first orelse return .Stop;

    var can_execute: bool = true;
    while (_node) |node| {
        _node = node.next;
        const events_set: *Loop.EventsSet = @alignCast(@ptrCast(node.data.?));
        const events_num = events_set.events_num;
        if (events_num == 0) return .Stop;

        for (events_set.events[0..events_num]) |handle| {
            if (handle.run_callback(can_execute)) {
                can_execute = false;
            }
        }
        events_set.events_num = 0;
    }

    remove_exceded_events(loop, index, queue, max_number_of_events_set);
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

    var ready_tasks_queue_index = self.ready_tasks_queue_index;
    const ready_tasks_queues: []LinkedList = &self.ready_tasks_queues;
    const temporal_handles_arenas: []std.heap.ArenaAllocator = &self.temporal_handles_arenas;
    const max_events_set_per_queue: []usize = &self.max_events_sets_per_queue;
    while (!self.stopping) {
        const old_index = ready_tasks_queue_index;
        ready_tasks_queue_index = 1 - ready_tasks_queue_index;
        self.ready_tasks_queue_index = ready_tasks_queue_index;

        switch (
            call_once(
                self, old_index, max_events_set_per_queue[old_index], &ready_tasks_queues[old_index],
                &temporal_handles_arenas[old_index]
            )
        ) {
            .Continue => {},
            .Stop => break,
            .Exception => return error.PythonError,
        }
    }
}
