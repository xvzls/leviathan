const python_c = @import("python_c");
pub const constructors = @import("constructors.zig");
const result = @import("result.zig");
const cancel = @import("cancel.zig");
const callbacks = @import("callbacks.zig");

const PythonFutureMethods: []const python_c.PyMethodDef = &[_]python_c.PyMethodDef{
    python_c.PyMethodDef{
        .ml_name = "result\x00",
        .ml_meth = @ptrCast(&result.future_result),
        .ml_doc = "Return the result of the Future\x00",
        .ml_flags = python_c.METH_NOARGS
    },
    python_c.PyMethodDef{
        .ml_name = "set_result\x00",
        .ml_meth = @ptrCast(&result.future_set_result),
        .ml_doc = "Mark the Future as done and set its result.\x00",
        .ml_flags = python_c.METH_VARARGS
    },
    python_c.PyMethodDef{
        .ml_name = "exception\x00",
        .ml_meth = @ptrCast(&result.future_exception),
        .ml_doc = "Return the exception raised by the Future\x00",
        .ml_flags = python_c.METH_NOARGS
    },
    python_c.PyMethodDef{
        .ml_name = "set_exception\x00",
        .ml_meth = @ptrCast(&result.future_set_exception),
        .ml_doc = "Mark the Future as done and set its exception.\x00",
        .ml_flags = python_c.METH_VARARGS
    },
    python_c.PyMethodDef{
        .ml_name = "cancel\x00",
        .ml_meth = @ptrCast(&cancel.future_cancel),
        .ml_doc = "Cancel the Future and schedule callbacks.\x00",
        .ml_flags = python_c.METH_VARARGS | python_c.METH_KEYWORDS
    },
    python_c.PyMethodDef{
        .ml_name = "cancelled\x00",
        .ml_meth = @ptrCast(&cancel.future_cancelled),
        .ml_doc = "Return True if the Future was cancelled.\x00",
        .ml_flags = python_c.METH_NOARGS
    },
    python_c.PyMethodDef{
        .ml_name = "done\x00",
        .ml_meth = @ptrCast(&result.future_done),
        .ml_doc = "Return True if the Future is done.\x00",
        .ml_flags = python_c.METH_NOARGS
    },
    python_c.PyMethodDef{
        .ml_name = "add_done_callback\x00",
        .ml_meth = @ptrCast(&callbacks.future_add_done_callback),
        .ml_doc = "Add a callback to be run when the Future is done.\x00",
        .ml_flags = python_c.METH_VARARGS
    },
    python_c.PyMethodDef{
        .ml_name = "remove_done_callback\x00",
        .ml_meth = @ptrCast(&callbacks.future_remove_done_callback),
        .ml_doc = "Remove callback from the callbacks list.\x00",
        .ml_flags = python_c.METH_VARARGS
    },
    python_c.PyMethodDef{
        .ml_name = "get_loop\x00",
        .ml_meth = @ptrCast(&constructors.future_get_loop),
        .ml_doc = "Return the event loop.\x00",
        .ml_flags = python_c.METH_NOARGS
    },
    python_c.PyMethodDef{
        .ml_name = null, .ml_meth = null, .ml_doc = null, .ml_flags = 0
    }
};

const PythonFutureAsyncMethods = python_c.PyAsyncMethods{
    .am_await = @ptrCast(&constructors.future_iter),
};

pub var PythonFutureType = python_c.PyTypeObject{
    .tp_name = "leviathan.Future\x00",
    .tp_doc = "Leviathan's future class\x00",
    .tp_basicsize = @sizeOf(constructors.PythonFutureObject),
    .tp_itemsize = 0,
    .tp_flags = python_c.Py_TPFLAGS_DEFAULT | python_c.Py_TPFLAGS_BASETYPE | python_c.Py_TPFLAGS_HAVE_GC,
    .tp_new = &constructors.future_new,
    .tp_init = @ptrCast(&constructors.future_init),
    .tp_traverse = @ptrCast(&constructors.future_traverse),
    .tp_clear = @ptrCast(&constructors.future_clear),
    .tp_dealloc = @ptrCast(&constructors.future_dealloc),
    .tp_iter = @ptrCast(&constructors.future_iter),
    .tp_iternext = @ptrCast(&constructors.future_iternext),
    .tp_as_async = @constCast(&PythonFutureAsyncMethods),
    .tp_methods = @constCast(PythonFutureMethods.ptr)
};
