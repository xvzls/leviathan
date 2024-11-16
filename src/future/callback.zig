const std = @import("std");

const CallbackManager = @import("../callback_manager/main.zig");
const Future = @import("main.zig");

const BTree = @import("../utils/btree/btree.zig");
const LinkedList = @import("../utils/linked_list.zig");
const python_c = @import("../utils/python_c.zig");
const PyObject = *python_c.PyObject;


const MaxCallbacks = 8;
pub const CallbackType = enum { Python, Zig };

pub fn create_python_handle(self: *Future, callback_data: PyObject) !*CallbackManager.Callback {
    var py_callback: ?PyObject = null;
    var py_context: ?PyObject = null;
    const ret = python_c.PyArg_ParseTuple(callback_data, "(OO)\x00", &py_callback, &py_context);
    if (ret < 0) {
        return error.PythonError;
    }

    try CallbackManager.append_new_callback(self.callbacks_arena_allocator, &self.callbacks_queue, .{
        .PythonFuture = .{
            .exception_handler = self.loop.?.py_loop.?.exception_handler,
            .contextvars = python_c.py_newref(py_context.?),
            .py_callback = python_c.py_newref(py_callback.?),
            .py_future = self.py_future.?,
        }
    }, MaxCallbacks);
}

pub fn add_done_callback(
    self: *Future, callback: ?CallbackManager.ZigGenericCallback, data: ?*anyopaque,
    callback_id: u64, callback_type: CallbackType
) !void {
    const mutex = &self.mutex;
    mutex.lock();
    defer mutex.unlock();

    if (self.status != .PENDING) return error.FutureAlreadyFinished;

    const callbacks_btree = switch (callback_type) {
        .Python => self.python_callbacks,
        .Zig => self.zig_callbacks
    };

    var b_node: *BTree.Node = undefined;
    const existing_handle_node: ?LinkedList.Node = @alignCast(
        @ptrCast(callbacks_btree.search(callback_id, &b_node))
    );
    if (existing_handle_node) |node| {
        const existing_handle: *CallbackManager.Callback = @alignCast(@ptrCast(node.data.?));
        switch (existing_handle) {
            .ZigGeneric => |handle| {
                handle.repeat +|= 1;
            },
            .PythonFuture => |handle| {
                handle.repeat +|= 1;
            },
            else => unreachable
        }
    }else{
        const allocator = self.callbacks_arena_allocator;
        const handle = switch (callback_type) {
            .Python => try self.create_python_handle(@alignCast(@ptrCast(data.?))),
            .Zig => {
                try CallbackManager.append_new_callback(allocator, &self.callbacks_queue, .{
                    .ZigGeneric = .{
                        .callback = callback.?,
                        .data = data,
                    }
                }, MaxCallbacks);
            }
        };
        errdefer {
            switch (handle) {
                .PythonFuture => |d| {
                    d.repeat = 0;
                },
                .ZigGeneric => |d| {
                    d.repeat = 0;
                },
                else => unreachable
            }
        }

        BTree.insert_in_node(callbacks_btree.allocator, b_node, callback_id, handle);
    }
}

pub fn remove_done_callback(self: *Future, callback_id: u64, callback_type: CallbackType) !usize {
    const mutex = &self.mutex;
    mutex.lock();
    defer mutex.unlock();

    if (self.status != .PENDING) return error.FutureAlreadyFinished;

    const callbacks_btree = switch (callback_type) {
        .Python => self.python_callbacks,
        .Zig => self.zig_callbacks
    };

    const handle: *CallbackManager.Callback = @alignCast(
        @ptrCast(callbacks_btree.search(callback_id, null) orelse return error.CallbackNotFound)
    );

    return switch (handle) {
        .ZigGeneric => |d| blk: {
            const repeat = d.repeat;
            d.repeat = 0;
            break :blk repeat;
        },
        .PythonFuture => |d| blk: {
            const repeat = d.repeat;
            d.repeat = 0;
            break :blk repeat;
        },
        else => unreachable
    };
}

pub inline fn call_done_callbacks(self: *Future) !void {
    if (self.status != .PENDING) return error.FutureAlreadyFinished;

    try self.loop.?.call_soon_threadsafe(.{
        .PythonFutureCallbacksSet = .{
            .sets_queue = &self.callbacks_queue,
            .future = @ptrCast(python_c.py_newref(self.py_future.?))
        }
    });

    self.status = .FINISHED;
}
