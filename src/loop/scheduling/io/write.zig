const std = @import("std");

const CallbackManager = @import("../../../callback_manager.zig");
const IO = @import("main.zig");

pub const WaitWritableOperationData = IO.WaitingOperationData;

pub fn wait_writable(set: *IO.BlockingTasksSet, data: WaitWritableOperationData) !void {
    const data_ptr = try set.push(data.callback);
    errdefer set.pop(data_ptr.id) catch unreachable;

    const ring: *std.os.linux.IoUring = &set.ring;
    _ = try ring.poll_add(@intCast(@intFromPtr(&data_ptr.data)), data.fd, std.c.POLL.OUT);
    const ret = try ring.submit();
    if (ret != 1) {
        @panic("Unexpected number of submitted sqes");
    }
}
