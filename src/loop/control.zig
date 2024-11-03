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

// inline fn get_ready_events(loop: *Loop, index: *u8) ?*LinkedList {
//     // const mutex = &loop.mutex;
//     // mutex.lock();
//     // defer mutex.unlock();

//     if (loop.stopping) {
//         return null;
//     }

//     const ready_tasks_queue_to_use = loop.ready_tasks_queue_to_use;
//     const ready_tasks_queue = &loop.ready_tasks_queues[ready_tasks_queue_to_use];
//     index.* = ready_tasks_queue_to_use;
//     loop.ready_tasks_queue_to_use = 1 - ready_tasks_queue_to_use;

//     return ready_tasks_queue;
// }

inline fn call_once(_: usize, queue: *LinkedList, _: *std.heap.ArenaAllocator) CallOnceReturn {
    var _node: ?LinkedList.Node = queue.first;
    if (_node == null) {
        return .Stop;
    }

    var should_stop: bool = false;
    while (_node) |node| {
        _node = node.next;
        const events: *Loop.EventSet = @alignCast(@ptrCast(node.data.?));
        const events_num = events.events_num;
        if (events_num == 0) {
            return .Stop;
        }
        for (events.events[0..events_num]) |handle| {
            // if (should_stop) {
            //     const handle_mutex = &handle.mutex;
            //     handle_mutex.lock();
            //     handle.cancelled = true;
            //     handle_mutex.unlock();
            // }

            if (handle.run_callback()) {
                should_stop = true;
            }
        }
        events.events_num = 0;
    }

    // const deallocated = arena.reset(.{
    //     .retain_with_limit = ready_tasks_queue_min_bytes_capacity
    // });
    // if (!deallocated) {
    // _ = arena.reset(.free_all);
    // }

    // queue.first = null;
    // queue.last = null;
    // queue.len = 0;

    if (should_stop) {
        return .Exception;
    }

    return .Continue;
}

pub fn run_forever(self: *Loop) !void {
    // const mutex = &self.mutex;
    {
        // mutex.lock();
        // defer mutex.unlock();

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
        self.running = false;
        self.stopping = false;
    }

    var ready_tasks_queue_to_use = self.ready_tasks_queue_to_use;
    const ready_tasks_queues: []LinkedList = &self.ready_tasks_queues;
    const ready_tasks_arenas: []std.heap.ArenaAllocator = &self.ready_tasks_arenas;
    const ready_tasks_queue_min_bytes_capacity = self.ready_tasks_queue_min_bytes_capacity;
    while (!self.stopping) {
        defer {
            ready_tasks_queue_to_use = 1 - ready_tasks_queue_to_use;
            self.ready_tasks_queue_to_use = ready_tasks_queue_to_use;
        }

        switch (
            call_once(
                ready_tasks_queue_min_bytes_capacity, &ready_tasks_queues[ready_tasks_queue_to_use],
                &ready_tasks_arenas[ready_tasks_queue_to_use]
            )
        ) {
            .Continue => {},
            .Stop => break,
            .Exception => return error.PythonError,
        }
    }

    // mutex.lock();
    // mutex.unlock();
}
