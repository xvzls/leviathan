const std = @import("std");

const Future = @import("main.zig");
const Handle = @import("../handle/main.zig");

const BTree = @import("../utils/btree/btree.zig");
const LinkedList = @import("../utils/linked_list.zig");
const python_c = @import("../utils/python_c.zig");


pub const CallbackType = enum { Python, Zig };
pub const FutureCallback = Handle.HandleCallback;

inline fn create_handle_for_zig_callback(
    allocator: std.mem.Allocator, future: *Future, callback: FutureCallback, args: ?*anyopaque
) !*Handle {
    const handle = try Handle.init(allocator, null, future.loop.?, callback, args orelse future, false);
    return handle;
}

fn create_handle_for_python_callback(args: *python_c.PyObject) !*Handle {
    const py_handle: *Handle.PythonHandleObject = @ptrCast(
        python_c.PyObject_CallObject(@ptrCast(&Handle.PythonHandleType), @ptrCast(args))
            orelse return error.PythonError
    );

    return py_handle.handle_obj.?;
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
    const existing_handle_node: ?LinkedList.Node = @alignCast(
        @ptrCast(callbacks_btree.search(callback_id, &b_node))
    );
    if (existing_handle_node) |node| {
        const existing_handle: *Handle = @alignCast(@ptrCast(node.data.?));
        existing_handle.repeat +|= 1;
    }else{
        const allocator = self.callbacks_arena_allocator;
        const handle = switch (callback_type) {
            .Python => try create_handle_for_python_callback(@alignCast(@ptrCast(args.?))),
            .Zig => try create_handle_for_zig_callback(allocator, self, callback.?, args)
        };
        errdefer {
            switch (callback_type) {
                .Python => python_c.Py_DECREF(@ptrCast(handle.py_handle.?)),
                .Zig => allocator.destroy(handle)
            }
        }

        const callback_node = try callbacks_array.create_new_node(handle);
        BTree.insert_in_node(callbacks_btree.allocator, b_node, callback_id, callback_node);
        callbacks_array.append_node(callback_node);
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

    const callback_node: LinkedList.Node = @alignCast(
        @ptrCast(callbacks_btree.delete(callback_id) orelse return error.CallbackNotFound)
    );
    const handle: *Handle = @alignCast(@ptrCast(callback_node.data.?));
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
        .Python => python_c.Py_DECREF(@ptrCast(handle.py_handle.?)),
        .Zig => allocator.destroy(handle)
    }
    allocator.destroy(callback_node);
    return callbacks_removed;
}
