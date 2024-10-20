const std = @import("std");

const Future = @import("main.zig");
const Handle = @import("../handle/main.zig");

const BTree = @import("../utils/btree/btree.zig");
const LinkedList = @import("../utils/linked_list.zig");
const python_c = @import("../utils/python_c.zig");


pub const CallbackType = enum { Python, Zig };
pub const FutureCallback = *const fn (?*anyopaque) bool;

inline fn create_handle_for_zig_callback(
    allocator: std.mem.allocator, future: *Future, callback: FutureCallback, args: ?*anyopaque
) !*Handle {
    const handle = try allocator.create(Handle);
    handle.* = Handle.init(allocator, callback, args orelse future, false);
    return handle;
}

fn create_handle_for_python_callback(args: *python_c.PyObject) !*Handle {
    const py_handle: *Handle.PythonHandleObject = python_c.PyObject_CallObject(
        @ptrCast(&Handle.PythonHandleType), @ptrCast(args)
    ) orelse return error.PythonError;

    return &py_handle.handle_obj.?;
}

pub fn add_done_callback(
    self: *Future, callback: ?FutureCallback, args: ?*anyopaque, callback_id: u64, callback_type: CallbackType
) !void {
    const mutex = &self.mutex;
    mutex.lock();
    defer mutex.unlock();

    if (self.status != .PENDING) return error.FutureAlreadyFinished;

    const callbacks_array = &self.callbacks_array;
    const callbacks_btree = switch (callback_type) {
        .Python => self.python_callbacks,
        .Zig => self.zig_callbacks
    };

    var b_node: *BTree.Node = undefined;
    const existing_handle_node: ?LinkedList.Node = @ptrCast(callbacks_btree.search(callback_id, &b_node));
    if (existing_handle_node) |node| {
        const existing_handle: *Handle = @ptrCast(node.data.?);
        existing_handle.repeat +|= 1;
    }else{
        const allocator = self.callbacks_arena_allocator;
        const handle = switch (callback_type) {
            .Python => try create_handle_for_python_callback(args.?),
            .Zig => try create_handle_for_zig_callback(allocator, self, callback.?, args)
        };
        errdefer {
            switch (callback_type) {
                .Python => {
                    const py_handle: *Handle.PythonHandleObject = @fieldParentPtr("handle_obj", handle);
                    python_c.Py_DECREF(@ptrCast(py_handle));
                },
                .Zig => allocator.destroy(handle)
            }
        }

        const callback_node = try callbacks_array.create_new_node(handle);
        callbacks_btree.insert_in_node(callbacks_btree.allocator, b_node, callback_id, callback_node);
        callbacks_array.append_node(callbacks_array);
    }
}

pub fn remove_done_callback(self: *Future, callback_id: u64, callback_type: CallbackType) !usize {
    const mutex = &self.mutex;
    mutex.lock();
    defer mutex.unlock();

    if (self.status != .PENDING) return error.FutureAlreadyFinished;

    const callbacks_array = &self.callbacks_array;
    const callbacks_btree = switch (callback_type) {
        .Python => self.python_callbacks,
        .Zig => self.zig_callbacks
    };

    const callback_node: LinkedList.Node = @ptrCast(
        callbacks_btree.delete(callback_id) orelse return error.CallbackNotFound
    );
    const handle: *Handle = @ptrCast(callback_node.data.?);
    const callbacks_removed = handle.repeat;

    const n_prev = callback_node.prev;
    const n_next = callback_node.next;

    if (n_prev) |prev| {
        prev.next = n_next;
    }else{
        callbacks_array.first = n_next;
    }

    if (n_next) |next| {
        next.prev = n_prev;
    }else{
        callbacks_array.last = n_prev;
    }

    const allocator = self.callbacks_arena_allocator;
    switch (callback_type) {
        .Python => {
            const py_handle: *Handle.PythonHandleObject = @fieldParentPtr("handle_obj", handle);
            python_c.Py_DECREF(@ptrCast(py_handle));
        },
        .Zig => allocator.destroy(handle)
    }
    allocator.destroy(callback_node);
    return callbacks_removed;
}
