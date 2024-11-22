const std = @import("std");

const CallbackManager = @import("../callback_manager/main.zig");
const Future = @import("main.zig");

const BTree = @import("../utils/btree/btree.zig");
const LinkedList = @import("../utils/linked_list.zig");
const python_c = @import("python_c");
const PyObject = *python_c.PyObject;

const MaxCallbacks = 8;

pub fn create_python_handle(self: *Future, callback_data: PyObject) !CallbackManager.Callback {
    var py_callback: ?PyObject = null;
    var py_context: ?PyObject = null;
    const ret = python_c.PyArg_ParseTuple(callback_data, "(OO)\x00", &py_callback, &py_context);
    if (ret < 0) {
        return error.PythonError;
    }

    return .{
        .PythonFuture = .{
            .exception_handler = self.loop.?.py_loop.?.exception_handler.?,
            .contextvars = python_c.py_newref(py_context.?),
            .py_callback = python_c.py_newref(py_callback.?),
            .py_future = @ptrCast(self.py_future.?),
        }
    };
}

pub inline fn add_done_callback(
    self: *Future, callback: CallbackManager.Callback
) !void {
    if (self.status != .PENDING) return error.FutureAlreadyFinished;

    const allocator = self.callbacks_arena_allocator;
    _ = try CallbackManager.append_new_callback(
        allocator, &self.callbacks_queue, callback, MaxCallbacks
    );
}

pub fn remove_done_callback(self: *Future, callback_id: u64) !usize {
    if (self.status != .PENDING) return error.FutureAlreadyFinished;

    const callbacks_queue = &self.callbacks_queue.queue;
    var node = callbacks_queue.first;
    var removed_count: usize = 0;
    while (node) |n| {
        node = n.next;
        const queue: *CallbackManager.CallbacksSet = @alignCast(@ptrCast(n.data.?));
        for (queue.callbacks[0..queue.callbacks_num]) |*callback| {
            switch (@as(CallbackManager.CallbackType, callback.*)) {
                .ZigGeneric => {
                    if (@as(u64, @intFromPtr(callback.ZigGeneric.callback)) == callback_id) {
                        callback.ZigGeneric.can_execute = false;
                        removed_count += 1;
                    }
                },
                .PythonFuture => {
                    if (@as(u64, @intFromPtr(callback.PythonFuture.args[0])) == callback_id) {
                        callback.PythonFuture.can_execute = false;
                        removed_count += 1;
                    }
                },
                else => unreachable
            }
        }
    }

    return removed_count;
}

pub inline fn call_done_callbacks(self: *Future, new_status: Future.FutureStatus) !void {
    if (self.status != .PENDING) return error.FutureAlreadyFinished;

    if (self.callbacks_queue.last_set == null) {
        self.status = new_status;
        return;
    }

    const pyfut: PyObject = @ptrCast(python_c.py_newref(self.py_future.?));
    errdefer python_c.py_decref(pyfut);

    try self.loop.?.call_soon_threadsafe(.{
        .PythonFutureCallbacksSet = .{
            .sets_queue = &self.callbacks_queue,
            .future = pyfut
        }
    });

    self.status = new_status;
}
