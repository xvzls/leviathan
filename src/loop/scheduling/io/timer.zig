const std = @import("std");

const CallbackManager = @import("../../../callback_manager.zig");
const IO = @import("main.zig");

pub const DelayType = enum(u32) {
    Relative = 0,
    Absolute = std.os.linux.IORING_TIMEOUT_ABS
};

pub const WaitData = struct {
    callback: CallbackManager.Callback,
    duration: std.os.linux.kernel_timespec,
    delay_type: DelayType
};

pub fn wait(set: *IO.BlockingTasksSet, data: WaitData) !void {
    const data_ptr = try set.push(data.callback);
    errdefer set.pop(data_ptr.id) catch unreachable;

    const ring: *std.os.linux.IoUring = &set.ring;
    _ = try ring.timeout(@intCast(@intFromPtr(data_ptr)), &data.duration, 0, @intFromEnum(data.delay_type));
    const ret = try ring.submit();
    if (ret != 1) {
        @panic("Unexpected number of submitted sqes");
    }
}
