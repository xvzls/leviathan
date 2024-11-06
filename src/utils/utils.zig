const std = @import("std");
const builtin = @import("builtin");

const python_c = @import("python_c.zig");
const jdz_allocator = @import("jdz_allocator");


pub var gpa = blk: {
    if (builtin.mode == .Debug) {
        break :blk std.heap.GeneralPurposeAllocator(.{}){};
    }else{
        break :blk jdz_allocator.JdzAllocator(.{}).init();
    }
};

pub const allocator: std.mem.Allocator = gpa.allocator();

pub inline fn put_python_runtime_error_message(msg: [:0]const u8) void {
    python_c.PyErr_SetString(
        python_c.PyExc_RuntimeError, @ptrCast(msg)
    );
}

pub inline fn check_leviathan_python_object(object: anytype, magic: u64) bool {
    if (object.magic != magic) {
        python_c.PyErr_SetString(
            python_c.PyExc_TypeError, "Invalid Leviathan's object\x00"
        );
        return true;
    }

    return false;
}

pub inline fn print_error_traces(
    trace: ?*std.builtin.StackTrace, @"error": anyerror,
) void {
    const writer = std.io.getStdErr().writer();
    if (trace == null) {
        writer.print("No zig's traces available", .{}) catch unreachable;
        return;
    }

    var debug_info = std.debug.openSelfDebugInfo(allocator) catch {
        writer.print("No zig's traces available", .{}) catch unreachable;
        return;
    };
    defer debug_info.deinit();

    std.debug.writeStackTrace(
        trace.?.*, writer, allocator, &debug_info,
        std.io.tty.detectConfig(std.io.getStdOut())
    ) catch {
        writer.print("No zig's traces available", .{}) catch unreachable;
        return;
    };
    writer.print("\nError name: {s}\n", .{@errorName(@"error")}) catch unreachable;
}

fn get_func_return_type(func: anytype) type {
    const ret_type = @typeInfo(@typeInfo(@TypeOf(func)).Fn.return_type.?).ErrorUnion.payload;
    if (@typeInfo(ret_type) == .Int) {
        return ret_type;
    }
    return ?ret_type;
}

pub inline fn execute_zig_function(func: anytype, args: anytype) get_func_return_type(func) {
    return @call(.auto, func, args) catch |err| {
        if (err != error.PythonError) {
            const err_trace = @errorReturnTrace();
            print_error_traces(err_trace, err);

            put_python_runtime_error_message(@errorName(err));
        }
        if (@typeInfo(get_func_return_type(func)) == .Int) {
            return -1;
        }
        return null;
    };
}
