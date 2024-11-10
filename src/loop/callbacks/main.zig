const std = @import("std");

const python_callbacks = @import("python.zig");

pub const CallbackType = enum {
    PythonGeneric, PythonFuture
};

pub const Callback = union(CallbackType) {
    PythonGeneric: python_callbacks.GenericCallbackData,
    PythonFuture: python_callbacks.FutureCallbackData
};

pub const MaxCallbacks = 128;

pub const CallbacksSet = struct {
    callbacks_num: usize = 0,
    callbacks: []Callback,
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

pub inline fn run_callback(callback: Callback, can_execute: bool) bool {
    if (can_execute) {
        return switch (callback) {
            .PythonGeneric => |data| python_callbacks.callback_for_python_generic_callbacks(data),
            .PythonFuture => |data| python_callbacks.callback_for_python_future_callbacks(data),
        };
    }else{
        switch (callback) {
            .PythonGeneric => |data| python_callbacks.release_python_generic_callback(data),
            .PythonFuture => |data| python_callbacks.release_python_future_callback(data),
        }

        return false;
    }
}
