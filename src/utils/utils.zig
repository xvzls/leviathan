const std = @import("std");
const builtin = @import("builtin");

const python_c = @import("python_c");
const jdz_allocator = @import("jdz_allocator");


pub var gpa = blk: {
    if (builtin.mode == .Debug) {
        break :blk std.heap.GeneralPurposeAllocator(.{}){};
    }else{
        break :blk jdz_allocator.JdzAllocator(.{}).init();
    }
};

pub inline fn put_python_runtime_error_message(msg: [:0]const u8) void {
    python_c.PyErr_SetString(
        python_c.PyExc_RuntimeError, @ptrCast(msg)
    );
}

pub inline fn get_data_ptr(comptime T: type, leviathan_pyobject: anytype) *T {
    const type_info = @typeInfo(@TypeOf(leviathan_pyobject));
    if (type_info != .pointer) {
        @compileError("leviathan_pyobject must be a pointer");
    }

    if (type_info.pointer.size != .One) {
        @compileError("leviathan_pyobject must be a single pointer");
    }

    if (!@hasField(type_info.pointer.child, "data")) {
        @compileError("T must have a data field");
    }

    return @as(*T, @ptrFromInt(@intFromPtr(leviathan_pyobject) + @offsetOf(type_info.pointer.child, "data")));
}

pub inline fn get_parent_ptr(comptime T: type, leviathan_object: anytype) *T {
    const type_info = @typeInfo(@TypeOf(leviathan_object));
    if (type_info != .pointer) {
        @compileError("leviathan_pyobject must be a pointer");
    }

    if (type_info.pointer.size != .One) {
        @compileError("leviathan_pyobject must be a single pointer");
    }
    
    return @as(*T, @ptrFromInt(@intFromPtr(leviathan_object) - @offsetOf(T, "data")));
}

pub inline fn print_error_traces(
    trace: ?*std.builtin.StackTrace, @"error": anyerror,
) void {
    const writer = std.io.getStdErr().writer();
    if (trace == null) {
        writer.print("No zig's traces available", .{}) catch unreachable;
        return;
    }

    var debug_info = std.debug.getSelfDebugInfo() catch {
        writer.print("No zig's traces available", .{}) catch unreachable;
        return;
    };
    defer debug_info.deinit();

    std.debug.writeStackTrace(
        trace.?.*, writer, debug_info,
        std.io.tty.detectConfig(std.io.getStdOut())
    ) catch {
        writer.print("No zig's traces available", .{}) catch unreachable;
        return;
    };
    writer.print("\nError name: {s}\n", .{@errorName(@"error")}) catch unreachable;
}

fn get_func_return_type(func: anytype) type {
    const ret_type = @typeInfo(@typeInfo(@TypeOf(func)).@"fn".return_type.?).error_union.payload;
    if (@typeInfo(ret_type) == .int) {
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
        if (@typeInfo(get_func_return_type(func)) == .int) {
            return -1;
        }
        return null;
    };
}
