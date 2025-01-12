const std = @import("std");

const leviathan = @import("leviathan");

const CallbackManager = leviathan.CallbackManager;
const LinkedList = CallbackManager.LinkedList;
const Loop = leviathan.Loop;

fn callback_test(data: ?*anyopaque, status: CallbackManager.ExecuteCallbacksReturn) CallbackManager.ExecuteCallbacksReturn {
    std.testing.expectEqual(CallbackManager.ExecuteCallbacksReturn.Continue, status) catch unreachable;

    const number: *usize = @alignCast(@ptrCast(data.?));
    number.* += 1;

    return .Continue;
}

test "Prune sets when maximum is 1" {
    const allocator = std.testing.allocator;

    var ready_tasks = CallbackManager.CallbacksSetsQueue{
        .queue = LinkedList.init(allocator),
    };
    defer {
        for (0..ready_tasks.queue.len) |_| {
            const set: CallbackManager.CallbacksSet = ready_tasks.queue.pop() catch unreachable;
            CallbackManager.release_set(allocator, set);
        }
    }

    var number: usize = 0;
    for (0..3) |_| {
        _ = try CallbackManager.append_new_callback(allocator, &ready_tasks, .{
            .ZigGeneric = .{
                .data = &number,
                .callback = &callback_test
            }
        }, 1);
    }

    try std.testing.expect(ready_tasks.queue.len > 1);

    var max_number_of_callbacks_set_ptr: usize = 1;
    Loop.Runner.prune_callbacks_sets(allocator, &ready_tasks, &max_number_of_callbacks_set_ptr, 0);

    try std.testing.expectEqual(ready_tasks.queue.len, 1);
}

test "Prune sets when maximum is more than 1" {
    const allocator = std.testing.allocator;

    var ready_tasks = CallbackManager.CallbacksSetsQueue{
        .queue = LinkedList.init(allocator),
    };
    defer {
        for (0..ready_tasks.queue.len) |_| {
            const set: CallbackManager.CallbacksSet = ready_tasks.queue.pop() catch unreachable;
            CallbackManager.release_set(allocator, set);
        }
    }

    var number: usize = 0;
    for (0..20) |_| {
        _ = try CallbackManager.append_new_callback(allocator, &ready_tasks, .{
            .ZigGeneric = .{
                .data = &number,
                .callback = &callback_test
            }
        }, 2);
    }

    try std.testing.expect(ready_tasks.queue.len > 1);

    var max_number_of_callbacks_set: usize = CallbackManager.get_max_callbacks_sets(
        14*@sizeOf(CallbackManager.Callback), 2
    );

    Loop.Runner.prune_callbacks_sets(
        allocator, &ready_tasks, &max_number_of_callbacks_set, 14*@sizeOf(CallbackManager.Callback)
    );

    try std.testing.expectEqual(ready_tasks.queue.len, max_number_of_callbacks_set);
}


test "Prune sets with high limit" {
    const allocator = std.testing.allocator;

    var ready_tasks = CallbackManager.CallbacksSetsQueue{
        .queue = LinkedList.init(allocator),
    };
    defer {
        for (0..ready_tasks.queue.len) |_| {
            const set: CallbackManager.CallbacksSet = ready_tasks.queue.pop() catch unreachable;
            CallbackManager.release_set(allocator, set);
        }
    }

    var number: usize = 0;
    for (0..20) |_| {
        _ = try CallbackManager.append_new_callback(allocator, &ready_tasks, .{
            .ZigGeneric = .{
                .data = &number,
                .callback = &callback_test
            }
        }, 2);
    }

    try std.testing.expect(ready_tasks.queue.len > 1);

    var max_number_of_callbacks_set: usize = CallbackManager.get_max_callbacks_sets(
        40*@sizeOf(CallbackManager.Callback), 2
    );

    Loop.Runner.prune_callbacks_sets(
        allocator, &ready_tasks, &max_number_of_callbacks_set, 30*@sizeOf(CallbackManager.Callback)
    );

    try std.testing.expect(ready_tasks.queue.len < max_number_of_callbacks_set);
}

test "Running callbaks and prune" {
    const allocator = std.testing.allocator;

    var ready_tasks = CallbackManager.CallbacksSetsQueue{
        .queue = LinkedList.init(allocator),
    };
    defer {
        for (0..ready_tasks.queue.len) |_| {
            const set: CallbackManager.CallbacksSet = ready_tasks.queue.pop() catch unreachable;
            CallbackManager.release_set(allocator, set);
        }
    }

    var number: usize = 0;
    for (0..20) |_| {
        _ = try CallbackManager.append_new_callback(allocator, &ready_tasks, .{
            .ZigGeneric = .{
                .data = &number,
                .callback = &callback_test
            }
        }, 2);
    }

    try std.testing.expect(ready_tasks.queue.len > 1);

    var max_number_of_callbacks_set: usize = CallbackManager.get_max_callbacks_sets(
        14*@sizeOf(CallbackManager.Callback), 2
    );

    const ret = Loop.Runner.call_once(
        allocator, &ready_tasks, &max_number_of_callbacks_set, 14*@sizeOf(CallbackManager.Callback)
    );
    Loop.Runner.prune_callbacks_sets(
        allocator, &ready_tasks, &max_number_of_callbacks_set, 14*@sizeOf(CallbackManager.Callback)
    );

    try std.testing.expectEqual(ret, CallbackManager.ExecuteCallbacksReturn.Continue);
    try std.testing.expect(ready_tasks.queue.len <= max_number_of_callbacks_set);
}
