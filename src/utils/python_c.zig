pub usingnamespace @cImport({
    @cDefine("PY_SSIZE_T_CLEAN", {});
    @cInclude("python3.12/Python.h");
});

pub inline fn get_py_true() *Python.PyObject {
    const py_true_struct: *Python.PyObject = @ptrCast(&Python._Py_TrueStruct);
    Python.Py_INCREF(py_true_struct);
    return py_true_struct;
}

pub inline fn get_py_false() *Python.PyObject {
    const py_false_struct: *Python.PyObject = @ptrCast(&Python._Py_FalseStruct);
    Python.Py_INCREF(py_false_struct);
    return py_false_struct;
}

pub inline fn get_py_none() *Python.PyObject {
    const py_none_struct: *Python.PyObject = @ptrCast(&Python._Py_NoneStruct);
    Python.Py_INCREF(py_none_struct);
    return py_none_struct;
}

const Python = @This();
