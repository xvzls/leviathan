const std = @import("std");

const leviathan = @import("leviathan");
const CallbackManager = leviathan.CallbackManager;

const allocator = std.testing.allocator;

test "Creating a new callback set" {
    const callback_set = try CallbackManager.create_new_set(allocator, 10);
    defer CallbackManager.release_set(allocator, callback_set);

    try std.testing.expectEqual(0, callback_set.callbacks_num);
    try std.testing.expectEqual(10, callback_set.callbacks.len);
}

fn test_callback(data: ?*anyopaque, status: CallbackManager.ExecuteCallbacksReturn) CallbackManager.ExecuteCallbacksReturn {
    if (status != .Continue) return status;

    const executed_ptr: *usize = @alignCast(@ptrCast(data.?));
    executed_ptr.* += 1;
    return status;
}

test "Run callback" {
    var executed: usize = 0;

    const ret = CallbackManager.run_callback(
        allocator, .{
            .ZigGeneric = .{
                .data = &executed,
                .callback = &test_callback
            }
        }, .Continue
    );
    try std.testing.expectEqual(.Continue, ret);
    try std.testing.expectEqual(1, executed);

    executed = 0;
    const ret2 = CallbackManager.run_callback(
        allocator, .{
            .ZigGeneric = .{
                .data = &executed,
                .callback = &test_callback,
                .can_execute = false
            }
        }, .Continue
    );
    try std.testing.expectEqual(.Continue, ret2);
    try std.testing.expectEqual(0, executed);
}

test "Append multiple sets" {
    var set_queue = CallbackManager.CallbacksSetsQueue{
        .queue = leviathan.utils.LinkedList.init(allocator)
    };
    defer {
        for (0..set_queue.queue.len) |_| {
            const callbacks_set: *CallbackManager.CallbacksSet = @alignCast(
                @ptrCast(set_queue.queue.pop() catch unreachable)
            );
            CallbackManager.release_set(allocator, callbacks_set);
        }
    }

    for (0..70) |_| {
        _ = try CallbackManager.append_new_callback(allocator, &set_queue, .{
            .ZigGeneric = .{
                .data = null,
                .callback = &test_callback
            }
        }, 10);
    }

    try std.testing.expectEqual(3, set_queue.queue.len);
    var node = set_queue.queue.first;
    var callbacks_len: usize = 10;
    while (node) |n| {
        const callbacks_set: *CallbackManager.CallbacksSet = @alignCast(@ptrCast(n.data.?));
        try std.testing.expectEqual(callbacks_len, callbacks_set.callbacks.len);
        try std.testing.expectEqual(callbacks_len, callbacks_set.callbacks_num);
        callbacks_len *= 2;
        node = n.next;
    }
}

test "Append new callback to set queue and execute it" {
    var set_queue = CallbackManager.CallbacksSetsQueue{
        .queue = leviathan.utils.LinkedList.init(allocator)
    };
    defer {
        for (0..set_queue.queue.len) |_| {
            const callbacks_set: *CallbackManager.CallbacksSet = @alignCast(
                @ptrCast(set_queue.queue.pop() catch unreachable)
            );
            CallbackManager.release_set(allocator, callbacks_set);
        }
    }

    var executed: usize = 0;

    const ret = try CallbackManager.append_new_callback(allocator, &set_queue, .{
        .ZigGeneric = .{
            .data = &executed,
            .callback = &test_callback
        }
    }, 10);

    try std.testing.expectEqual(&test_callback, ret.ZigGeneric.callback);
    try std.testing.expectEqual(@intFromPtr(&executed), @intFromPtr(ret.ZigGeneric.data));

    try std.testing.expect(set_queue.last_set != null);

    const callbacks_set: *CallbackManager.CallbacksSet = @alignCast(
        @ptrCast(set_queue.last_set.?.data.?)
    );

    try std.testing.expectEqual(1, callbacks_set.callbacks_num);
    try std.testing.expectEqual(ret, &callbacks_set.callbacks[0]);
    try std.testing.expectEqual(10, callbacks_set.callbacks.len);

    _ = CallbackManager.execute_callbacks(allocator, &set_queue, .Continue, false);
    try std.testing.expectEqual(1, executed);
    try std.testing.expectEqual(0, callbacks_set.callbacks_num);

    callbacks_set.callbacks_num = 1;
    executed = 0;
    _ = CallbackManager.execute_callbacks(allocator, &set_queue, .Continue, true);
    try std.testing.expectEqual(1, executed);
    try std.testing.expectEqual(0, callbacks_set.callbacks_num);
    try std.testing.expectEqual(set_queue.queue.first, set_queue.last_set);
}

test "Append multiple sets and cancelling callbacks" {
    var set_queue = CallbackManager.CallbacksSetsQueue{
        .queue = leviathan.utils.LinkedList.init(allocator)
    };
    defer {
        for (0..set_queue.queue.len) |_| {
            const callbacks_set: *CallbackManager.CallbacksSet = @alignCast(
                @ptrCast(set_queue.queue.pop() catch unreachable)
            );
            CallbackManager.release_set(allocator, callbacks_set);
        }
    }

    var executed: usize = 0;
    for (0..70) |i| {
        const callback = try CallbackManager.append_new_callback(allocator, &set_queue, .{
            .ZigGeneric = .{
                .data = &executed,
                .callback = &test_callback
            }
        }, 10);

        if (i % 2 == 0) {
            CallbackManager.cancel_callback(callback);
        }
    }

    try std.testing.expectEqual(3, set_queue.queue.len);
    var node = set_queue.queue.first;
    var callbacks_len: usize = 10;
    while (node) |n| {
        const callbacks_set: *CallbackManager.CallbacksSet = @alignCast(@ptrCast(n.data.?));
        try std.testing.expectEqual(callbacks_len, callbacks_set.callbacks.len);
        try std.testing.expectEqual(callbacks_len, callbacks_set.callbacks_num);
        callbacks_len *= 2;
        node = n.next;
    }

    _ = CallbackManager.execute_callbacks(allocator, &set_queue, .Continue, false);
    try std.testing.expectEqual(35, executed);
}
