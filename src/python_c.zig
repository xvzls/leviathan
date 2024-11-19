pub usingnamespace @cImport({
    @cDefine("PY_SSIZE_T_CLEAN", {});
    @cInclude("python3.12/Python.h");
});

pub inline fn get_py_true() *Python.PyObject {
    const py_true_struct: *Python.PyObject = @ptrCast(&Python._Py_TrueStruct);
    Python.py_incref(py_true_struct);
    return py_true_struct;
}

pub inline fn get_py_false() *Python.PyObject {
    const py_false_struct: *Python.PyObject = @ptrCast(&Python._Py_FalseStruct);
    Python.py_incref(py_false_struct);
    return py_false_struct;
}

pub inline fn get_py_none() *Python.PyObject {
    const py_none_struct: *Python.PyObject = @ptrCast(&Python._Py_NoneStruct);
    Python.py_incref(py_none_struct);
    return py_none_struct;
}

pub inline fn py_incref(op: *Python.PyObject) void {
    const new_refcnt = op.unnamed_0.ob_refcnt_split[0] +| 1;
    if (new_refcnt == 0) {
        return;
    }

    op.unnamed_0.ob_refcnt_split[0] = new_refcnt;
}

inline fn _Py_IsImmortal(arg_op: *Python.PyObject) bool {
    return @as(i32, @bitCast(@as(c_int, @truncate(arg_op.unnamed_0.ob_refcnt)))) < @as(c_int, 0);
}

pub inline fn py_decref(op: *Python.PyObject) void {
    var ref = op.unnamed_0.ob_refcnt;
    if (_Py_IsImmortal(op)) {
        return;
    }

    ref -= 1;
    op.unnamed_0.ob_refcnt = ref;
    if (ref == 0) {
        op.ob_type.*.tp_dealloc.?(op);
    }
}

pub inline fn py_xdecref(op: ?*Python.PyObject) void {
    if (op) |o| {
        py_decref(o);
    }
}

pub inline fn py_newref(op: anytype) @TypeOf(op) {
    Python.py_incref(@ptrCast(op));
    return op;
}

pub inline fn py_visit(objects: []const ?*Python.PyObject, visit: Python.visitproc, arg: ?*anyopaque) c_int {
    for (objects) |obj| {
        if (obj) |_obj| {
            const vret = visit.?(_obj, arg);
            if (vret != 0) {
                return vret;
            }
        }
    }

    return 0;
}

const Python = @This();
