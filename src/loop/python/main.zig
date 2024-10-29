const python_c = @import("../../utils/python_c.zig");
pub const constructors = @import("constructors.zig");

const control = @import("control.zig");
const scheduling = @import("scheduling.zig");

const PythonFutureMethods: []const python_c.PyMethodDef = &[_]python_c.PyMethodDef{
    python_c.PyMethodDef{
        .ml_name = "run_forever\x00",
        .ml_meth = @ptrCast(&control.loop_run_forever),
        .ml_doc = "Run the event loop forever.\x00",
        .ml_flags = python_c.METH_NOARGS
    },
    python_c.PyMethodDef{
        .ml_name = "stop\x00",
        .ml_meth = @ptrCast(&control.loop_stop),
        .ml_doc = "Stop the event loop.\x00",
        .ml_flags = python_c.METH_NOARGS
    },
    python_c.PyMethodDef{
        .ml_name = "is_running\x00",
        .ml_meth = @ptrCast(&control.loop_is_running),
        .ml_doc = "Return True if the event loop is currently running.\x00",
        .ml_flags = python_c.METH_NOARGS
    },
    python_c.PyMethodDef{
        .ml_name = "is_closed\x00",
        .ml_meth = @ptrCast(&control.loop_is_closed),
        .ml_doc = "Return True if the event loop was closed.\x00",
        .ml_flags = python_c.METH_NOARGS
    },
    python_c.PyMethodDef{
        .ml_name = "close\x00",
        .ml_meth = @ptrCast(&control.loop_close),
        .ml_doc = "Close the event loop\x00",
        .ml_flags = python_c.METH_NOARGS
    },
    python_c.PyMethodDef{
        .ml_name = "call_soon\x00",
        .ml_meth = @ptrCast(&scheduling.loop_call_soon),
        .ml_doc = "Schedule callback to be called with args arguments at the next iteration of the event loop.\x00",
        .ml_flags = python_c.METH_VARARGS
    },
    python_c.PyMethodDef{
        .ml_name = "call_soon_threadsafe\x00",
        .ml_meth = @ptrCast(&scheduling.loop_call_soon),
        .ml_doc = "A thread-safe variant of call_soon\x00",
        .ml_flags = python_c.METH_VARARGS
    },
    python_c.PyMethodDef{
        .ml_name = null, .ml_meth = null, .ml_doc = null, .ml_flags = 0
    }
};

pub var PythonLoopType = python_c.PyTypeObject{
    .tp_name = "leviathan.Loop\x00",
    .tp_doc = "Leviathan's loop class\x00",
    .tp_basicsize = @sizeOf(constructors.PythonLoopObject),
    .tp_itemsize = 0,
    .tp_flags = python_c.Py_TPFLAGS_DEFAULT | python_c.Py_TPFLAGS_BASETYPE,
    .tp_new = &constructors.loop_new,
    .tp_init = @ptrCast(&constructors.loop_init),
    .tp_dealloc = @ptrCast(&constructors.loop_dealloc),
};

