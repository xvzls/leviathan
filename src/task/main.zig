const Future = @import("../future/main.zig");

const python_c = @import("python_c");

const constructors = @import("constructors.zig");
const task_utils = @import("utils.zig");
const cancel = @import("cancel.zig");

const PythonTaskMethods: []const python_c.PyMethodDef = &[_]python_c.PyMethodDef{
    python_c.PyMethodDef{
        .ml_name = "set_result\x00",
        .ml_meth = @ptrCast(&task_utils.task_not_implemented_method),
        .ml_doc = "Mark the Future as done and set its result.\x00",
        .ml_flags = python_c.METH_VARARGS
    },
    python_c.PyMethodDef{
        .ml_name = "set_exception\x00",
        .ml_meth = @ptrCast(&task_utils.task_not_implemented_method),
        .ml_doc = "Mark the Future as done and set its exception.\x00",
        .ml_flags = python_c.METH_VARARGS
    },
    python_c.PyMethodDef{
        .ml_name = "cancel\x00",
        .ml_meth = @ptrCast(&cancel.task_cancel),
        .ml_doc = "Cancel the Future and schedule callbacks.\x00",
        .ml_flags = python_c.METH_VARARGS | python_c.METH_KEYWORDS
    },
    python_c.PyMethodDef{
        .ml_name = "uncancel\x00",
        .ml_meth = @ptrCast(&cancel.task_uncancel),
        .ml_doc = "Decrement the number of pending cancellation requests to this Task\x00",
        .ml_flags = python_c.METH_NOARGS
    },
    python_c.PyMethodDef{
        .ml_name = "cancelling\x00",
        .ml_meth = @ptrCast(&cancel.task_cancelling),
        .ml_doc = "Return the number of pending cancellation requests to this Task.\x00",
        .ml_flags = python_c.METH_NOARGS
    },
    python_c.PyMethodDef{
        .ml_name = "get_coro\x00",
        .ml_meth = @ptrCast(&task_utils.task_get_coro),
        .ml_doc = "Return the coroutine object wrapped by the Task.\x00",
        .ml_flags = python_c.METH_NOARGS
    },
    python_c.PyMethodDef{
        .ml_name = "get_context\x00",
        .ml_meth = @ptrCast(&task_utils.task_get_context),
        .ml_doc = "Return the contextvars.Context object associated with the task.\x00",
        .ml_flags = python_c.METH_NOARGS
    },
    python_c.PyMethodDef{
        .ml_name = "get_name\x00",
        .ml_meth = @ptrCast(&task_utils.task_get_name),
        .ml_doc = "Return the name of the task.\x00",
        .ml_flags = python_c.METH_NOARGS
    },
    python_c.PyMethodDef{
        .ml_name = "set_name\x00",
        .ml_meth = @ptrCast(&task_utils.task_set_name),
        .ml_doc = "Set the name of the task\x00",
        .ml_flags = python_c.METH_VARARGS
    },
    python_c.PyMethodDef{
        .ml_name = "get_stack\x00",
        .ml_meth = @ptrCast(&task_utils.task_get_stack),
        .ml_doc = "Return the list of stack frames for this Task.\x00",
        .ml_flags = python_c.METH_VARARGS | python_c.METH_KEYWORDS
    },
    python_c.PyMethodDef{
        .ml_name = "print_stack\x00",
        .ml_meth = @ptrCast(&task_utils.task_print_stack),
        .ml_doc = "Print the stack or traceback for this Task.",
        .ml_flags = python_c.METH_VARARGS | python_c.METH_KEYWORDS
    },
    python_c.PyMethodDef{
        .ml_name = null, .ml_meth = null, .ml_doc = null, .ml_flags = 0
    }
};

const PythonTaskMembers: []const python_c.PyMemberDef = &[_]python_c.PyMemberDef{
    python_c.PyMemberDef{
        .name = "_coro\x00",
        .type = python_c.Py_T_OBJECT_EX,
        .offset = @offsetOf(constructors.PythonTaskObject, "coro"),
        .doc = null,
    },
    python_c.PyMemberDef{
        .name = "_exception\x00",
        .type = python_c.Py_T_OBJECT_EX,
        .offset = @offsetOf(constructors.PythonTaskObject, "coro"),
        .doc = null,
    },
    python_c.PyMemberDef{
        .name = null, .flags = 0, .offset = 0, .doc = null
    }
};

pub var PythonFutureType = python_c.PyTypeObject{
    .tp_name = "leviathan.Task\x00",
    .tp_doc = "Leviathan's task class\x00",
    .tp_base = &Future.constructors.PythonFutureType,
    .tp_basicsize = @sizeOf(constructors.PythonTaskObject),
    .tp_itemsize = 0,
    .tp_flags = python_c.Py_TPFLAGS_DEFAULT | python_c.Py_TPFLAGS_BASETYPE | python_c.Py_TPFLAGS_HAVE_GC,
    .tp_new = &constructors.task_new,
    .tp_init = @ptrCast(&constructors.task_init),
    .tp_traverse = @ptrCast(&constructors.task_traverse),
    .tp_clear = @ptrCast(&constructors.task_clear),
    .tp_dealloc = @ptrCast(&constructors.task_dealloc),
    .tp_methods = @constCast(PythonTaskMethods.ptr),
};
