const python_c = @import("../../utils/python_c.zig");
const PyObject = *python_c.PyObject;

const constructors = @import("constructors.zig");
const PythonFutureObject = constructors.PythonFutureObject;
const LEVIATHAN_FUTURE_MAGIC = constructors.LEVIATHAN_FUTURE_MAGIC;

const utils = @import("../../utils/utils.zig");

pub fn future_add_done_callback(self: ?*PythonFutureObject, args: ?PyObject) callconv(.C) ?PyObject {
    const instance = self.?;
    if (utils.check_leviathan_python_object(instance, LEVIATHAN_FUTURE_MAGIC)) {
        return null;
    }

    var callback_id: u64 = undefined;
    var callback_data: ?PyObject = null;

    if (python_c.PyArg_ParseTuple(args.?, "KO\x00", &callback_id, &callback_data) < 0) {
        return null;
    }

    const obj = instance.future_obj.?;
    const mutex = &obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    switch (obj.status) {
        .PENDING => {
             obj.add_done_callback(null, args.?, callback_id, .Python) catch |err| switch (err) {
                error.PythonError => return null,
                else => {
                    const err_trace = @errorReturnTrace();
                    utils.print_error_traces(err_trace, err);
                    utils.put_python_runtime_error_message(@errorName(err));
                }
            };
        },
        else => {
            // TODO
        }
    }

    return python_c.get_py_none();
}

pub fn future_remove_done_callback(self: ?*PythonFutureObject, args: ?PyObject) callconv(.C) ?PyObject {
    const instance = self.?;
    if (utils.check_leviathan_python_object(instance, LEVIATHAN_FUTURE_MAGIC)) {
        return null;
    }

    var callback_id: u64 = undefined;
    if (python_c.PyArg_ParseTuple(args.?, "K\x00", &callback_id) < 0) {
        return null;
    }

    const obj = instance.future_obj.?;
    const mutex = &obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    const removed_count = obj.remove_done_callback(callback_id, .Python) catch |err| {
        const err_trace = @errorReturnTrace();
        utils.print_error_traces(err_trace, err);
        utils.put_python_runtime_error_message(@errorName(err));

        return null;
    };

    return python_c.PyLong_FromUnsignedLongLong(@intCast(removed_count));
}
