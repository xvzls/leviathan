const python_c = @import("python_c");
const PyObject = *python_c.PyObject;

const Future = @import("../main.zig");
const constructors = @import("constructors.zig");
const result = @import("result.zig");


pub const PythonFutureIterObject = extern struct {
    ob_base: python_c.PyObject,
    py_future: ?*constructors.PythonFutureObject,
    result_returned: bool
};

pub inline fn create_new_future_iter(py_future: *constructors.PythonFutureObject) !*PythonFutureIterObject {
    const new_iter: *PythonFutureIterObject = @ptrCast(
        Future.PythonFutureIterType.tp_alloc.?(&Future.PythonFutureIterType, 0)
        orelse return error.PythonError
    );
    new_iter.py_future = python_c.py_newref(py_future);
    return new_iter;
}

pub fn future_iter_new(
    _: ?*python_c.PyTypeObject, _: ?PyObject,
    _: ?PyObject
) callconv(.C) ?PyObject {
    python_c.PyErr_SetString(python_c.PyExc_RuntimeError, "Calling this method is not allowed. Only internal use\x00");
    return null;
}

pub fn future_iter_clear(self: ?*PythonFutureIterObject) callconv(.C) c_int {
    python_c.py_decref_and_set_null(@ptrCast(&self.?.py_future));
    return 0;
}

pub fn future_iter_traverse(self: ?*PythonFutureIterObject, visit: python_c.visitproc, arg: ?*anyopaque) callconv(.C) c_int {
    return python_c.py_visit(&[_]?*python_c.PyObject{
        @ptrCast(self.?.py_future)
    }, visit, arg);
}

pub fn future_iter_dealloc(self: ?*PythonFutureIterObject) callconv(.C) void {
    const instance = self.?;
    python_c.PyObject_GC_UnTrack(instance);
    _ = future_iter_clear(instance);

    const @"type": *python_c.PyTypeObject = @ptrCast(python_c.Py_TYPE(@ptrCast(instance)) orelse unreachable);
    @"type".tp_free.?(@ptrCast(instance));
}

pub fn future_iter_init(_: ?*PythonFutureIterObject, _: ?PyObject, _: ?PyObject) callconv(.C) c_int {
    python_c.PyErr_SetString(python_c.PyExc_RuntimeError, "Calling this method is not allowed. Only internal use\x00");
    return -1;
}


pub fn future_iter_iternext(self: ?*PythonFutureIterObject) callconv(.C) ?*python_c.PyObject {
    const instance = self.?;

    const py_future = instance.py_future.?;
    const obj = py_future.future_obj.?;
    const mutex = &obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    if (instance.result_returned) {
        python_c.PyErr_SetNone(python_c.PyExc_StopIteration);
        return null;
    }

    if (obj.status != .PENDING) {
        instance.result_returned = true;
        return result.get_result(obj.py_future.?);
    }

    return python_c.get_py_none();
}
