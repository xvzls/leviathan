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

pub fn check_done_callback_and_increment(
    self: *Future, callback_type: CallbackManager.CallbackType,
    callback_id: u64, b_node: **BTree.Node
) !bool {
    const callbacks_btree = switch (callback_type) {
        .PythonFuture => self.python_callbacks,
        .ZigGeneric => self.zig_callbacks,
        else => return error.CallbackTypeNotSupported
    };

    const existing_handle: ?*CallbackManager.Callback = @alignCast(
        @ptrCast(callbacks_btree.search(callback_id, b_node))
    );
    if (existing_handle) |handle| {
        switch (callback_type) {
            .PythonFuture => {
                handle.ZigGeneric.repeat +|= 1;
            },
            .ZigGeneric => {
                handle.PythonFuture.repeat +|= 1;
            },
            else => return error.CallbackTypeNotSupported
        }

        return true;
    }

    return false;
}

pub fn add_done_callback(
    self: *Future, callback: CallbackManager.Callback,
    callback_id: u64, b_node: *BTree.Node
) !void {
    if (self.status != .PENDING) return error.FutureAlreadyFinished;

    const callback_type = @as(CallbackManager.CallbackType, callback);
    const callbacks_btree = switch (callback_type) {
        .PythonFuture => self.python_callbacks,
        .ZigGeneric => self.zig_callbacks,
        else => return error.CallbackTypeNotSupported
    };

    const allocator = self.callbacks_arena_allocator;
    const handle: *CallbackManager.Callback = try CallbackManager.append_new_callback(
        allocator, &self.callbacks_queue, callback, MaxCallbacks
    );

    BTree.insert_in_node(callbacks_btree.allocator, b_node, callback_id, handle);
}

pub fn remove_done_callback(self: *Future, callback_id: u64, callback_type: CallbackManager.CallbackType) !usize {
    const mutex = &self.mutex;
    mutex.lock();
    defer mutex.unlock();

    if (self.status != .PENDING) return error.FutureAlreadyFinished;

    const callbacks_btree = switch (callback_type) {
        .PythonFuture => self.python_callbacks,
        .ZigGeneric => self.zig_callbacks,
        else => return error.CallbackTypeNotSupported
    };

    const handle: *CallbackManager.Callback = @alignCast(
        @ptrCast(callbacks_btree.search(callback_id, null) orelse return error.CallbackNotFound)
    );

    return switch (callback_type) {
        .ZigGeneric => blk: {
            const repeat = handle.ZigGeneric.repeat;
            handle.ZigGeneric.repeat = 0;
            break :blk repeat;
        },
        .PythonFuture => blk: {
            const repeat = handle.PythonFuture.repeat;
            handle.PythonFuture.repeat = 0;
            break :blk repeat;
        },
        else => return error.CallbackTypeNotSupported
    };
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
