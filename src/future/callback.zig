const std = @import("std");
const builtin = @import("builtin");

const CallbackManager = @import("../callback_manager.zig");
const Future = @import("main.zig");

const BTree = @import("../utils/btree/btree.zig");
const LinkedList = @import("../utils/linked_list.zig");
const utils = @import("../utils/utils.zig");

const python_c = @import("python_c");
const PyObject = *python_c.PyObject;

const MaxCallbacks = 8;

pub const FutureCallbacksSetData = struct {
    sets_queue: *CallbackManager.CallbacksSetsQueue,
    future: *Future.PythonFutureObject,
};

pub const FutureCallbackData = struct {
    args: []PyObject,
    exception_handler: PyObject,
    py_callback: PyObject,
    can_execute: bool = true,
    dec_future: bool = false
};

pub inline fn release_python_future_callback(data: FutureCallbackData) void {
    python_c.py_decref(data.py_callback);
    python_c.py_decref(data.args[0]);
    if (data.dec_future) python_c.py_decref(data.args[1]);
}

pub fn callback_for_python_future_callbacks(data: FutureCallbackData) CallbackManager.ExecuteCallbacksReturn {
    defer release_python_future_callback(data);
    if (!data.can_execute) return .Continue;

    const args = data.args;
    const py_callback = data.py_callback;

    const result: ?PyObject = python_c.PyObject_Vectorcall(py_callback, args.ptr, args.len, null);
    if (result) |value| {
        python_c.py_decref(value);
    }else{
        if (
            python_c.PyErr_ExceptionMatches(python_c.PyExc_SystemExit) > 0 or
            python_c.PyErr_ExceptionMatches(python_c.PyExc_KeyboardInterrupt) > 0
        ) {
            return .Exception;
        }

        const exception: PyObject = python_c.PyErr_GetRaisedException()
            orelse return .Exception;
        defer python_c.py_decref(exception);

        const exc_handler_ret: PyObject = python_c.PyObject_CallOneArg(data.exception_handler, exception)
            orelse return .Exception;
        python_c.py_decref(exc_handler_ret);
    }

    return .Continue;
}

pub inline fn callback_for_python_future_set_callbacks(
    allocator: std.mem.Allocator, data: FutureCallbacksSetData, status: CallbackManager.ExecuteCallbacksReturn
) CallbackManager.ExecuteCallbacksReturn {
    defer python_c.py_decref(@ptrCast(data.future));
    return CallbackManager.execute_callbacks(allocator, data.sets_queue, status, false);
}

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

    const pyfut = utils.get_parent_ptr(Future.PythonFutureObject, self);
    python_c.py_incref(@ptrCast(pyfut));
    errdefer python_c.py_decref(@ptrCast(pyfut));

    const callback: CallbackManager.Callback = .{
        .PythonFutureCallbacksSet = .{
            .sets_queue = &self.callbacks_queue,
            .future = pyfut
        }
    };

    if (builtin.single_threaded) {
        try self.loop.call_soon(callback);
    }else{
        try self.loop.call_soon_threadsafe(callback);
    }

    self.status = new_status;
}
