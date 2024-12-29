const std = @import("std");

const CallbackManager = @import("../../../callback_manager.zig");
const IO = @import("main.zig");

pub const WaitReadableOperationData = IO.WaitingOperationData;

pub fn wait_readable(set: *IO.BlockingTasksSet, data: WaitReadableOperationData) !void {
    const data_ptr = try set.push(data.callback);
    errdefer set.pop(data_ptr.id) catch unreachable;

    const ring: *std.os.linux.IoUring = &set.ring;
    _ = try ring.poll_add(@intCast(@intFromPtr(&data_ptr.data)), data.fd, std.c.POLL.IN);
    const ret = try ring.submit();
    if (ret != 1) {
        @panic("Unexpected number of submitted sqes");
    }
}
