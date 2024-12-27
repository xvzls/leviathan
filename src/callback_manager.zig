const std = @import("std");

const python_c = @import("python_c");

const Future = @import("future/main.zig");
const Task = @import("task/main.zig");
const Handle = @import("handle.zig");

const LinkedList = @import("utils/linked_list.zig");

pub const ExecuteCallbacksReturn = enum {
    Stop,
    Exception,
    Continue
};

pub const CallbackType = enum {
    ZigGeneric, PythonGeneric, PythonFutureCallbacksSet, PythonFuture, PythonTask
};

pub const ZigGenericCallback = *const fn (?*anyopaque, status: ExecuteCallbacksReturn) ExecuteCallbacksReturn;
pub const ZigGenericCallbackData = struct {
    callback: ZigGenericCallback,
    data: ?*anyopaque,
    can_execute: bool = true,
};

pub const Callback = union(CallbackType) {
    ZigGeneric: ZigGenericCallbackData,
    PythonGeneric: Handle.GenericCallbackData,
    PythonFutureCallbacksSet: Future.FutureCallbacksSetData,
    PythonFuture: Future.FutureCallbackData,
    PythonTask: Task.TaskCallbackData
};

pub const CallbacksSet = struct {
    callbacks: []Callback,
    callbacks_num: usize = 0,
};

pub const CallbacksSetsQueue = struct {
    queue: LinkedList,
    last_set: ?LinkedList.Node = null,
};

pub inline fn get_max_callbacks_sets(rtq_min_capacity: usize, callbacks_set_length: usize) usize {
    return @max(
        @as(usize, @intFromFloat(
            @ceil(
                @log2(
                    @as(f64, @floatFromInt(rtq_min_capacity)) / @as(f64, @floatFromInt(callbacks_set_length * @sizeOf(Callback))) + 1.0
                )
            )
        )), 1
    );
}

pub inline fn create_new_set(allocator: std.mem.Allocator, size: usize) !*CallbacksSet {
    const callbacks = try allocator.create(CallbacksSet);
    errdefer allocator.destroy(callbacks);

    callbacks.callbacks = try allocator.alloc(Callback, size);
    callbacks.callbacks_num = 0;
    return callbacks;
}

pub fn release_set(allocator: std.mem.Allocator, set: *CallbacksSet) void {
    allocator.free(set.callbacks);
    allocator.destroy(set);
}

pub inline fn append_new_callback(
    allocator: std.mem.Allocator, sets_queue: *CallbacksSetsQueue, callback: Callback,
    max_callbacks: usize
) !*Callback {
    var callbacks: *CallbacksSet = undefined;
    var last_callbacks_set_len: usize = max_callbacks;
    var node = sets_queue.last_set;
    while (node) |n| {
        callbacks = @alignCast(@ptrCast(n.data.?));
        const callbacks_num = callbacks.callbacks_num;

        if (callbacks_num < callbacks.callbacks.len) {
            callbacks.callbacks[callbacks_num] = callback;
            callbacks.callbacks_num = callbacks_num + 1;

            sets_queue.last_set = n;
            return &callbacks.callbacks[callbacks_num];
        }
        last_callbacks_set_len = (callbacks_num * 2);
        node = n.next;
    }

    callbacks = try create_new_set(allocator, last_callbacks_set_len);
    errdefer allocator.free(callbacks.callbacks);

    callbacks.callbacks_num = 1;
    callbacks.callbacks[0] = callback;

    try sets_queue.queue.append(callbacks);
    sets_queue.last_set = sets_queue.queue.last;

    return &callbacks.callbacks[0];
}

pub inline fn run_callback(
    allocator: std.mem.Allocator, callback: Callback, status: ExecuteCallbacksReturn
) ExecuteCallbacksReturn {
    switch (status) {
        .Continue => {
            return switch (callback) {
                .ZigGeneric => |data| data.callback(data.data, if (data.can_execute) status else .Stop),
                .PythonGeneric => |data| Handle.callback_for_python_generic_callbacks(allocator, data),
                .PythonFutureCallbacksSet => |data| Future.callback_for_python_future_set_callbacks(
                    allocator, data, status
                ),
                .PythonFuture => |data| Future.callback_for_python_future_callbacks(data),
                .PythonTask => |data| Task.step_run_and_handle_result(data.task, data.exc_value),
            };
        },
        else => {
            switch (callback) {
                .ZigGeneric => |data| {
                    _  = data.callback(data.data, status);
                },
                .PythonGeneric => |data| Handle.release_python_generic_callback(allocator, data),
                .PythonFutureCallbacksSet => |data| {
                    _ = Future.callback_for_python_future_set_callbacks(
                        allocator, data, status
                    );
                },
                .PythonFuture => |data| Future.release_python_future_callback(data),
                .PythonTask => |data| {
                    data.task.must_cancel = true;
                    _ = Task.step_run_and_handle_result(data.task, data.exc_value);
                },
            }
            return .Continue;
        }
    }
}

pub fn execute_callbacks(
    allocator: std.mem.Allocator, sets_queue: *CallbacksSetsQueue, _exec_status: ExecuteCallbacksReturn,
    comptime can_restart: bool
) ExecuteCallbacksReturn {
    const queue = &sets_queue.queue;
    var _node: ?LinkedList.Node = queue.first orelse return .Stop;
    defer {
        if (can_restart) {
            sets_queue.last_set = queue.first;
        }
    }

    var status: ExecuteCallbacksReturn = _exec_status;
    var chunks_executed: usize = 0;
    while (_node) |node| : (chunks_executed += 1) {
        _node = node.next;
        const callbacks_set: *CallbacksSet = @alignCast(@ptrCast(node.data.?));
        const callbacks_num = callbacks_set.callbacks_num;
        if (callbacks_num == 0) {
            if (chunks_executed == 0) {
                return .Stop;
            }
            return status;
        }

        for (callbacks_set.callbacks[0..callbacks_num]) |callback| {
            switch (run_callback(allocator, callback, status)) {
                .Continue => {},
                .Stop => {
                    status = .Stop;
                },
                .Exception => {
                    status = .Exception;
                }
            }
        }
        callbacks_set.callbacks_num = 0;
    }

    return status;
}
