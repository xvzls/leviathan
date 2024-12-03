const LinkedList = @import("../utils/linked_list.zig");

const Loop = @import("main.zig");
const CallbackManager = @import("../callback_manager.zig");

const utils = @import("../utils/utils.zig");
const python_c = @import("python_c");
const PyObject = *python_c.PyObject;

const std = @import("std");

inline fn free_callbacks_set(allocator: std.mem.Allocator, node: LinkedList.Node, comptime field_name: []const u8) LinkedList.Node {
    const callbacks_set: *CallbackManager.CallbacksSet = @alignCast(@ptrCast(node.data.?));
    allocator.free(callbacks_set.callbacks);
    allocator.destroy(callbacks_set);

    const next_node = @field(node, field_name).?;
    allocator.destroy(node);

    return next_node;
}

inline fn remove_exceded_callbacks(
    loop: *Loop, index: usize, ready_tasks: *CallbackManager.CallbacksSetsQueue,
    max_number_of_callbacks_set: usize
) void {
    const queue = &ready_tasks.queue;
    var queue_len = queue.len;
    if (queue_len <= max_number_of_callbacks_set) return;

    const allocator = loop.allocator;
    if (max_number_of_callbacks_set == 1) {
        var node = queue.last.?;
        while (queue_len > max_number_of_callbacks_set) : (queue_len -= 1) {
            node = free_callbacks_set(allocator, node, "prev");
        }
        node.next = null;
        queue.last = node;
        queue.len = queue_len;
    }else{
        var node = queue.first.?;
        while (queue_len > max_number_of_callbacks_set) : (queue_len -= 1) {
            node = free_callbacks_set(allocator, node, "next");
        }

        const callbacks_set: *CallbackManager.CallbacksSet = @alignCast(@ptrCast(node.data.?));
        node.prev = null;
        queue.first = node;
        ready_tasks.last_set = node;
        queue.len = queue_len;

        loop.max_callbacks_sets_per_queue[index] = CallbackManager.get_max_callbacks_sets(
            loop.ready_tasks_queue_min_bytes_capacity, callbacks_set.callbacks.len
        );
    }
}

fn call_once(
    loop: *Loop, index: usize, max_number_of_callbacks_set: usize,
    ready_queue: *CallbackManager.CallbacksSetsQueue
) CallbackManager.ExecuteCallbacksReturn {
    const ret = CallbackManager.execute_callbacks(loop.allocator, ready_queue, .Continue, true);
    remove_exceded_callbacks(loop, index, ready_queue, max_number_of_callbacks_set);

    return ret;
}

pub fn run_forever(self: *Loop) !void {
    const mutex = &self.mutex;
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

    defer {
        self.running = false;
        self.stopping = false;
    }

    const ready_tasks_queues: []CallbackManager.CallbacksSetsQueue = &self.ready_tasks_queues;
    const max_callbacks_set_per_queue: []usize = &self.max_callbacks_sets_per_queue;
    var ready_tasks_queue_index = self.ready_tasks_queue_index;
    while (!self.stopping) {
        const old_index = ready_tasks_queue_index;
        ready_tasks_queue_index = 1 - ready_tasks_queue_index;
        self.ready_tasks_queue_index = ready_tasks_queue_index;

        mutex.unlock();
        defer mutex.lock();

        switch (
            call_once(
                self, old_index, max_callbacks_set_per_queue[old_index], &ready_tasks_queues[old_index]
            )
        ) {
            .Continue => {},
            .Stop => break,
            .Exception => return error.PythonError,
        }
    }
}
