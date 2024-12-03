const builtin = @import("builtin");

const python_c = @import("python_c");
const PyObject = *python_c.PyObject;

const constructors = @import("constructors.zig");
const PythonFutureObject = constructors.PythonFutureObject;

const Future = @import("../main.zig");

const CallbackManager = @import("../../callback_manager.zig");

const utils = @import("../../utils/utils.zig");

inline fn z_future_add_done_callback(self: *PythonFutureObject, args: PyObject) !PyObject {
    var callback: ?PyObject = undefined;
    var context: ?PyObject = null;

    if (python_c.PyArg_ParseTuple(args, "O|O:context\x00", &callback, &context) < 0) {
        return error.PythonError;
    }


    const py_loop = self.py_loop.?;
    if (context) |py_ctx| {
        python_c.py_incref(py_ctx);
    }else {
        context = python_c.PyObject_CallNoArgs(py_loop.contextvars_copy.?) orelse return error.PythonError;
    }
    errdefer python_c.py_decref(context.?);

    const contextvars_run_func: PyObject = python_c.PyObject_GetAttrString(context.?, "run\x00")
        orelse return error.PythonError;
    errdefer python_c.py_decref(contextvars_run_func);

    const obj = self.future_obj.?;
    const mutex = &obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    const allocator = obj.callbacks_arena_allocator;
    const callback_args = try allocator.alloc(PyObject, 2);
    errdefer allocator.free(callback_args);

    callback_args[0] = python_c.py_newref(callback.?);
    errdefer python_c.py_decref(callback_args[0]);

    callback_args[1] = @ptrCast(self);

    var callback_data: CallbackManager.Callback = .{
        .PythonFuture = .{
            .args = callback_args,
            .exception_handler = py_loop.exception_handler.?,
            .contextvars = context.?,
            .py_callback = contextvars_run_func,
        }
    };

    switch (obj.status) {
        .PENDING => try obj.add_done_callback(callback_data),
        else => {
            python_c.py_incref(@ptrCast(self));
            errdefer python_c.py_decref(@ptrCast(self));

            callback_data.PythonFuture.dec_future = true;
            if (builtin.single_threaded) {
                try obj.loop.?.call_soon(callback_data);
            }else{
                try obj.loop.?.call_soon_threadsafe(callback_data);
            }
        }
    }

    return python_c.get_py_none();
}

pub fn future_add_done_callback(self: ?*PythonFutureObject, args: ?PyObject) callconv(.C) ?PyObject {
    return utils.execute_zig_function(z_future_add_done_callback, .{self.?, args.?});
}

pub fn future_remove_done_callback(self: ?*PythonFutureObject, args: ?PyObject) callconv(.C) ?PyObject {
    const instance = self.?;
    var callback: ?PyObject = null;
    if (python_c.PyArg_ParseTuple(args.?, "O\x00", &callback) < 0) {
        return null;
    }

    const obj = instance.future_obj.?;
    const mutex = &obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    const removed_count = obj.remove_done_callback(@intCast(@intFromPtr(callback.?))) catch |err| {
        const err_trace = @errorReturnTrace();
        utils.print_error_traces(err_trace, err);
        utils.put_python_runtime_error_message(@errorName(err));

        return null;
    };

    return python_c.PyLong_FromUnsignedLongLong(@intCast(removed_count));
}
