const std = @import("std");

const python_c = @import("python_c");
const utils = @import("../utils/utils.zig");

const Loop = @import("main.zig");
const CallbackManager = @import("../callback_manager.zig");

callbacks: std.AutoHashMap(u6, CallbackManager.Callback),
fd: std.posix.fd_t,
mask: std.posix.sigset_t,
loop: *Loop,

signalfd_info: std.os.linux.signalfd_siginfo = undefined,

fn signal_handler(
    data: ?*anyopaque, status: CallbackManager.ExecuteCallbacksReturn
) CallbackManager.ExecuteCallbacksReturn {
    if (status != .Continue) return status;

    const loop: *Loop = @alignCast(@ptrCast(data.?));

    const sig = loop.unix_signals.signalfd_info.signo;
    const callback = loop.unix_signals.callbacks.get(@intCast(sig)).?;
    const ret = CallbackManager.run_callback(loop.allocator, callback, .Continue);

    if (ret != .Continue) {
        return ret;
    }

    const buffer_to_read: std.os.linux.IoUring.ReadBuffer = .{
        .buffer = @as([*]u8, @ptrCast(&loop.unix_signals.signalfd_info))[0..@sizeOf(std.os.linux.signalfd_siginfo)],
    };

    Loop.Scheduling.IO.queue(loop, Loop.Scheduling.IO.BlockingOperationData{
        .PerformRead = .{
            .fd = loop.unix_signals.fd,
            .data = buffer_to_read,
            .callback = CallbackManager.Callback{
                .ZigGeneric = .{
                    .data = loop,
                    .callback = &signal_handler
                }
            },
            .offset = 0
        }
    }) catch |err| {
        const err_trace = @errorReturnTrace();
        utils.print_error_traces(err_trace, err);

        utils.put_python_runtime_error_message(@errorName(err));
        return .Exception;
    };

    return .Continue;
}

fn default_sigterm_signal_callback(
    _: ?*anyopaque, _: CallbackManager.ExecuteCallbacksReturn
) CallbackManager.ExecuteCallbacksReturn {
    python_c.PyErr_SetString(python_c.PyExc_SystemExit, "SIGTERM received");
    return .Exception;
}

fn default_sigint_signal_callback(
    _: ?*anyopaque, _: CallbackManager.ExecuteCallbacksReturn
) CallbackManager.ExecuteCallbacksReturn {
    python_c.PyErr_SetString(python_c.PyExc_KeyboardInterrupt, "SIGINT received");
    return .Exception;
}

pub inline fn link(self: *UnixSignals, sig: u6, callback: CallbackManager.Callback) !void {
    try self.callbacks.put(sig, callback);
    self.callbacks.rehash();
}

pub fn unlink(self: *UnixSignals, sig: u6) !void {
    if (!self.callbacks.remove(sig)) return error.KeyNotFound;

    const callback: CallbackManager.Callback = switch (sig) {
        std.os.linux.SIG.INT => CallbackManager.Callback{
            .ZigGeneric = .{
                .data = self.loop,
                .callback = &default_sigint_signal_callback,
            }
        },
        std.os.linux.SIG.TERM => CallbackManager.Callback{
            .ZigGeneric = .{
                .data = self.loop,
                .callback = &default_sigterm_signal_callback,
            }
        },
        else => return
    };

    try self.callbacks.put(sig, callback);
}

pub fn init(loop: *Loop) !void {
    var mask: std.posix.sigset_t = std.posix.empty_sigset;
    std.c.sigfillset(&mask);
    const fd = try std.posix.signalfd(-1, &mask, 0);

    loop.unix_signals = .{
        .callbacks = std.AutoHashMap(u6, CallbackManager.Callback).init(loop.allocator),
        .fd = fd,
        .mask = mask,
        .loop = loop
    };
    errdefer loop.unix_signals.deinit();

    try loop.unix_signals.link(std.os.linux.SIG.INT, CallbackManager.Callback{
        .ZigGeneric = .{
            .data = loop,
            .callback = &default_sigint_signal_callback,
        }
    });

    try loop.unix_signals.link(std.os.linux.SIG.TERM, CallbackManager.Callback{
        .ZigGeneric = .{
            .data = loop,
            .callback = &default_sigterm_signal_callback,
        }
    });

    const buffer_to_read: std.os.linux.IoUring.ReadBuffer = .{
        .buffer = @as([*]u8, @ptrCast(&loop.unix_signals.signalfd_info))[0..@sizeOf(std.os.linux.signalfd_siginfo)],
    };

    try Loop.Scheduling.IO.queue(loop, Loop.Scheduling.IO.BlockingOperationData{
        .PerformRead = .{
            .fd = loop.unix_signals.fd,
            .data = buffer_to_read,
            .callback = CallbackManager.Callback{
                .ZigGeneric = .{
                    .data = loop,
                    .callback = &signal_handler
                }
            },
            .offset = 0
        }
    });
}

pub fn deinit(self: *UnixSignals) void {
    std.posix.close(self.fd);
    var iter = self.callbacks.keyIterator();
    while (iter.next()) |sig| {
        const removed = self.callbacks.remove(sig.*);
        if (!removed) @panic("Error removing signal");
    }

    self.callbacks.deinit();
}

const UnixSignals = @This();
