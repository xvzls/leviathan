const python_c = @import("python_c");
const PyObject = *python_c.PyObject;

const constructors = @import("constructors.zig");
const PythonFutureObject = constructors.PythonFutureObject;

const Future = @import("../main.zig");

const CallbackManager = @import("../../callback_manager/main.zig");
const BTree = @import("../../utils/btree/btree.zig");

const utils = @import("../../utils/utils.zig");

inline fn z_future_add_done_callback(self: *PythonFutureObject, args: PyObject) !PyObject {
    var callback: ?PyObject = undefined;
    var context: ?PyObject = null;

    if (python_c.PyArg_ParseTuple(args, "O|O:context\x00", &callback, &context) < 0) {
        return error.PythonError;
    }

    const obj = self.future_obj.?;
    const mutex = &obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    const status = obj.status;

    var b_node: *BTree.Node = undefined;
    const callback_id: u64 = @intCast(@intFromPtr(callback.?));
    if (status != .PENDING) {
        const incremented = try @call(
            .always_inline, Future.check_done_callback_and_increment, .{obj, .PythonFuture, callback_id, &b_node}
        );
        if (incremented) {
            return python_c.get_py_none();
        }
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

    const allocator = obj.callbacks_arena_allocator;
    const callback_args = try allocator.alloc(PyObject, 2);
    errdefer allocator.free(callback_args);

    callback_args[0] = @ptrCast(self);
    callback_args[1] = python_c.py_newref(callback.?);
    errdefer python_c.py_decref(callback_args[1]);

    const callback_data: CallbackManager.Callback = .{
        .PythonFuture = .{
            .args = callback_args,
            .exception_handler = py_loop.exception_handler.?,
            .contextvars = context.?,
            .py_callback = contextvars_run_func,
        }
    };

    switch (status) {
        .PENDING => try @call(
            .always_inline, Future.add_done_callback, .{obj, callback_data, callback_id, b_node}
        ),
        else => try obj.loop.?.call_soon_threadsafe(callback_data)
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

    const removed_count = obj.remove_done_callback(@intCast(@intFromPtr(callback.?)), .PythonFuture) catch |err| {
        const err_trace = @errorReturnTrace();
        utils.print_error_traces(err_trace, err);
        utils.put_python_runtime_error_message(@errorName(err));

        return null;
    };

    return python_c.PyLong_FromUnsignedLongLong(@intCast(removed_count));
}
