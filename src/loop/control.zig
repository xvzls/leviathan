const LinkedList = @import("../utils/linked_list.zig");

const Handle = @import("../handle/main.zig");
const Loop = @import("main.zig");

const utils = @import("../utils/utils.zig");
const python_c = @import("../utils/python_c.zig");
const PyObject = *python_c.PyObject;

const std = @import("std");

inline fn get_ready_events(loop: *Loop, index: *u8) ?*LinkedList {
    // const mutex = &loop.mutex;
    // mutex.lock();
    // defer mutex.unlock();

    if (loop.stopping) {
        return null;
    }

    const ready_tasks_queue_to_use = loop.ready_tasks_queue_to_use;
    const ready_tasks_queue = &loop.ready_tasks_queues[ready_tasks_queue_to_use];
    index.* = ready_tasks_queue_to_use;
    loop.ready_tasks_queue_to_use = 1 - ready_tasks_queue_to_use;

    return ready_tasks_queue;
}

inline fn callback_for_python_methods(handle: *Handle, should_stop: bool) bool {
    const py_handle: *Handle.PythonHandleObject = handle.py_handle.?;
    defer python_c.py_decref(@ptrCast(py_handle));

    if (should_stop or handle.cancelled) {
        return false;
    }

    const ret: ?PyObject = python_c.PyObject_Call(py_handle.py_callback.?, py_handle.args.?, null);
    if (ret) |value| {
        python_c.py_decref(value);
    }else{
        if (
            python_c.PyErr_ExceptionMatches(python_c.PyExc_SystemExit) > 0 or
            python_c.PyErr_ExceptionMatches(python_c.PyExc_KeyboardInterrupt) > 0
        ) {
            return true;
        }

        const exception: PyObject = python_c.PyErr_GetRaisedException()
            orelse return true;
        defer python_c.py_decref(exception);

        const py_args: PyObject = python_c.Py_BuildValue("(O)\x00", exception)
            orelse return true;
        defer python_c.py_decref(py_args);

        const exc_handler_ret: PyObject = python_c.PyObject_CallObject(py_handle.exception_handler.?, py_args)
            orelse return true;
        python_c.py_decref(exc_handler_ret);
    }
    return false;
}

inline fn call_once(self: *Loop) bool {
    var queue_index: u8 = undefined;
    const queue = get_ready_events(self, &queue_index) orelse return false;

    var _node: ?LinkedList.Node = queue.first;
    if (_node == null) {
        self.stopping = true;
        return false;
    }

    var should_stop: bool = false;
    while (_node) |node| {
        _node = node.next;
        const events: *Loop.EventSet = @alignCast(@ptrCast(node.data.?));
        for (events.events[0..events.events_num]) |handle| {
            // if (should_stop) {
            //     const handle_mutex = &handle.mutex;
            //     handle_mutex.lock();
            //     handle.cancelled = true;
            //     handle_mutex.unlock();
            // }

            // if (handle.run_callback()) {
            if (callback_for_python_methods(handle, should_stop)) {
                should_stop = true;
            }
        }

    }

    const arena = &self.ready_tasks_arenas[queue_index];
    const not_deallocated = arena.reset(.{
        .retain_with_limit = Loop.MaxEvents * @sizeOf(*Handle),
    });
    if (not_deallocated) {
        _ = arena.reset(.free_all);
    }

    queue.first = null;
    queue.last = null;
    queue.len = 0;

    return true;
}

pub inline fn run_forever(self: *Loop) !void {
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

    while (call_once(self)) {}

    // mutex.lock();
    self.running = false;
    self.stopping = false;
    // mutex.unlock();
}
