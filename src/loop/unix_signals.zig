const std = @import("std");

const Loop = @import("main.zig");
const CallbackManager = @import("../callback_manager.zig");

callbacks: std.AutoHashMap(i32, CallbackManager.Callback),
fd: std.posix.fd_t,
mask: std.posix.sigset_t,

fn signal_handler(data: ?*anyopaque, status: CallbackManager.ExecuteCallbacksReturn) void {

}

pub fn link(self: *Loop, sig: u6, callback: CallbackManager.Callback) !void {
    const mask = &self.unix_signals.mask;
    std.os.linux.sigaddset(mask, sig);
    std.posix.sigprocmask(std.os.linux.SIG.BLOCK, mask, null);
}

pub fn unlink(self: *Loop, sig: u6) !void {
    var mask: std.posix.sigset_t = std.posix.empty_sigset;
    std.os.linux.sigaddset(&mask, sig);

    std.os.linux.sigdelset(&self.unix_signals.mask, sig);

    std.posix.sigprocmask(std.os.linux.SIG.UNBLOCK, &mask, null);

}

pub fn init(loop: *Loop) !void {
    var mask: std.posix.sigset_t = std.posix.empty_sigset;
    const fd = try std.posix.signalfd(-1, &mask, 0);

    loop.unix_signals = .{
        .callbacks = std.AutoHashMap(i32, CallbackManager.Callback).init(loop.allocator),
        .fd = fd,
        .mask = mask,
    };
}

const UnixSignals = @This();
