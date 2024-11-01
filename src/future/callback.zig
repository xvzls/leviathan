const std = @import("std");

const Future = @import("main.zig");
const Handle = @import("../handle/main.zig");

const BTree = @import("../utils/btree/btree.zig");
const LinkedList = @import("../utils/linked_list.zig");
const python_c = @import("../utils/python_c.zig");
const PyObject = *python_c.PyObject;


pub const CallbackType = enum { Python, Zig };
pub const FutureCallback = Handle.HandleCallback;

pub fn create_python_handle(self: *Future, callback_data: PyObject) !*Handle {
    var py_callback: ?PyObject = null;
    var py_context: ?PyObject = null;
    const ret = python_c.PyArg_ParseTuple(callback_data, "(OO)\x00", &py_callback, &py_context);
    if (ret < 0) {
        return error.PythonError;
    }

    const py_callback_info = python_c.Py_BuildValue("(OO)\x00", py_callback, self.py_future.?)
        orelse return error.PythonError;
    errdefer python_c.Py_DECREF(py_callback_info);

    const py_loop = self.loop.?.py_loop.?;

    const args: PyObject = python_c.Py_BuildValue(
        "(OOOOp)\x00", py_callback_info, py_loop, py_context.?,
        py_loop.exception_handler.?, @as(c_int, 0)
    ) orelse return error.PythonError;
    defer python_c.Py_DECREF(args);

    const py_handle: *Handle.PythonHandleObject = @ptrCast(
        python_c.PyObject_CallObject(@ptrCast(&Handle.PythonHandleType), args)
            orelse return error.PythonError
    );

    return py_handle.handle_obj.?;
}

pub fn add_done_callback(
    self: *Future, callback: ?FutureCallback, data: ?*anyopaque, callback_id: u64, callback_type: CallbackType
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
        if (existing_handle.cancelled) {
            existing_handle.repeat = 1;
            existing_handle.cancelled = false;
        }else{
            existing_handle.repeat +|= 1;
        }
    }else{
        const allocator = self.callbacks_arena_allocator;
        const handle = switch (callback_type) {
            .Python => try self.create_python_handle(@alignCast(@ptrCast(data.?))),
            .Zig => try Handle.init(allocator, null, self.loop.?, callback.?, self, false)
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

    const callbacks_btree = switch (callback_type) {
        .Python => self.python_callbacks,
        .Zig => self.zig_callbacks
    };

    const callback_node: LinkedList.Node = @alignCast(
        @ptrCast(callbacks_btree.search(callback_id, null) orelse return error.CallbackNotFound)
    );
    const handle: *Handle = @alignCast(@ptrCast(callback_node.data.?));
    if (handle.cancelled) {
        return 0;
    }

    const removed_count = handle.repeat;
    handle.cancelled = true;

    return removed_count;
}

fn release_future_callback(_: *Handle, data: ?*anyopaque) bool {
    const future: *Future = @alignCast(@ptrCast(data.?));
    if (future.py_future) |py_future| {
        python_c.Py_DECREF(py_future);
    }else{
        future.release();
    }
    return false;
}

pub inline fn call_done_callbacks(self: *Future, release: bool) !void {
    if (self.status != .PENDING) return error.FutureAlreadyFinished;

    const loop = self.loop.?;
    const loop_mutex = &loop.mutex;
    loop_mutex.lock();
    defer loop_mutex.unlock();

    loop.extend_ready_tasks(&self.callbacks_array);

    if (release) {
        loop.call_soon_without_handle(&release_future_callback, self);
    }

    self.status = .FINISHED;
}

pub inline fn call_done_callbacks_thread_safe(self: *Future, release: bool) !void {
    const mutex = &self.mutex;
    mutex.lock();
    defer mutex.unlock();

    try self.call_done_callbacks(release);
}
