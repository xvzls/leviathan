const python_c = @import("python_c");
const PyObject = *python_c.PyObject;

const utils = @import("../utils/utils.zig");
const constructors = @import("constructors.zig");

pub fn task_not_implemented_method(
    _: ?*constructors.PythonTaskObject, _: ?PyObject, _: ?PyObject
) callconv(.C) ?PyObject {
    python_c.PyErr_SetString(python_c.PyExc_NotImplementedError, "This method is not supported for tasks\x00");
    return null;
}

pub fn task_get_coro(self: ?*constructors.PythonTaskObject) callconv(.C) ?PyObject {
    return python_c.py_newref(self.?.coro);
}

pub fn task_get_context(self: ?*constructors.PythonTaskObject) callconv(.C) ?PyObject {
    return python_c.py_newref(self.?.py_context);
}

pub fn task_get_name(self: ?*constructors.PythonTaskObject) callconv(.C) ?PyObject {
    return python_c.py_newref(self.?.name);
}

pub fn task_set_name(self: ?*constructors.PythonTaskObject, args: ?PyObject) callconv(.C) ?PyObject {
    const instance = self.?;

    var name: ?PyObject = null;
    if (python_c.PyArg_Parse(args, "O\x00", &name) < 0) {
        return null;
    }

    if (python_c.PyUnicode_Check(name.?) == 0) {
        python_c.PyErr_SetString(python_c.PyExc_TypeError, "name must be a string\x00");
        return;
    }

    const obj = instance.fut.future_obj.?;
    const mutex = &obj.mutex;
    mutex.lock();
    defer mutex.unlock();

    instance.name = python_c.py_newref(name.?);
    return python_c.get_py_none();
}

pub fn task_get_stack(self: ?*constructors.PythonTaskObject, args: ?PyObject, kwargs: ?PyObject) callconv(.C) ?PyObject {
    const instance = self.?;

    var kwlist: [2][*c]u8 = undefined;
    kwlist[0] = @constCast("limit\x00");
    kwlist[1] = null;

    var limit: ?PyObject = python_c.get_py_none();

    if (python_c.PyArg_ParseTupleAndKeywords(args, kwargs, "|$O\x00", @ptrCast(&kwlist), &limit) < 0) {
        return null;
    }

    const asyncio_module = instance.fut.asyncio_module.?;
    
    const base_tasks_module: PyObject = python_c.PyObject_GetAttrString(asyncio_module, "base_tasks\x00")
        orelse return null;
    defer python_c.Py_DecRef(base_tasks_module);

    const get_stack_func: PyObject = python_c.PyObject_GetAttrString(base_tasks_module, "_task_get_stack\x00")
        orelse return null;
    defer python_c.Py_DecRef(get_stack_func);

    const stack: PyObject = python_c.PyObject_CallFunctionObjArgs(get_stack_func, instance, limit, null)
        orelse return null;

    return python_c.py_newref(stack);
}

pub fn task_print_stack(self: ?*constructors.PythonTaskObject, args: ?PyObject, kwargs: ?PyObject) callconv(.C) ?PyObject {
    const instance = self.?;

    var kwlist: [3][*c]u8 = undefined;
    kwlist[0] = @constCast("limit\x00");
    kwlist[1] = @constCast("file\x00");
    kwlist[2] = null;

    var limit: ?PyObject = python_c.get_py_none();
    var file: ?PyObject = python_c.get_py_none();

    if (python_c.PyArg_ParseTupleAndKeywords(args, kwargs, "|$OO\x00", @ptrCast(&kwlist), &limit, &file) < 0) {
        return null;
    }

    const asyncio_module = instance.fut.asyncio_module.?;
    
    const base_tasks_module: PyObject = python_c.PyObject_GetAttrString(asyncio_module, "base_tasks\x00")
        orelse return null;
    defer python_c.py_decref(base_tasks_module);

    const print_stack_func: PyObject = python_c.PyObject_GetAttrString(base_tasks_module, "_task_print_stack\x00")
        orelse return null;
    defer python_c.py_decref(print_stack_func);

    const result: ?PyObject = python_c.PyObject_CallFunctionObjArgs(print_stack_func, instance, limit, file, null);
    return result;
}
