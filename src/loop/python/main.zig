const Loop = @import("../main.zig");

const python_c = @import("python_c");
const PyObject = *python_c.PyObject;

const constructors = @import("constructors.zig");
const scheduling = @import("scheduling.zig");
const control = @import("control.zig");
const utils = @import("utils/main.zig");

const PythonLoopMethods: []const python_c.PyMethodDef = &[_]python_c.PyMethodDef{
    // --------------------- Control ---------------------
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

    // --------------------- Sheduling ---------------------
    python_c.PyMethodDef{
        .ml_name = "call_soon\x00",
        .ml_meth = @ptrCast(&scheduling.loop_call_soon),
        .ml_doc = "Schedule callback to be called with args arguments at the next iteration of the event loop.\x00",
        .ml_flags = python_c.METH_FASTCALL | python_c.METH_KEYWORDS
    },

    // --------------------- Utils ---------------------
    python_c.PyMethodDef{
        .ml_name = "create_future\x00",
        .ml_meth = @ptrCast(&utils.future.loop_create_future),
        .ml_doc = "Schedule callback to be called with args arguments at the next iteration of the event loop.\x00",
        .ml_flags = python_c.METH_NOARGS
    },
    python_c.PyMethodDef{
        .ml_name = "create_task\x00",
        .ml_meth = @ptrCast(&utils.task.loop_create_task),
        .ml_doc = "Schedule callback to be called with args arguments at the next iteration of the event loop.\x00",
        .ml_flags = python_c.METH_FASTCALL | python_c.METH_KEYWORDS
    },

    // --------------------- Sentinel ---------------------
    python_c.PyMethodDef{
        .ml_name = null, .ml_meth = null, .ml_doc = null, .ml_flags = 0
    }
};

pub const PythonLoopObject = extern struct {
    ob_base: python_c.PyObject,
    data: [@sizeOf(Loop)]u8,

    asyncio_module: ?PyObject,
    invalid_state_exc: ?PyObject,
    cancelled_error_exc: ?PyObject,
    
    enter_task_func: ?PyObject,
    leave_task_func: ?PyObject,

    contextvars_module: ?PyObject,
    contextvars_copy: ?PyObject,
    exception_handler: ?PyObject,
};

pub var PythonLoopType = python_c.PyTypeObject{
    .tp_name = "leviathan.Loop\x00",
    .tp_doc = "Leviathan's loop class\x00",
    .tp_basicsize = @sizeOf(PythonLoopObject),
    .tp_itemsize = 0,
    .tp_flags = python_c.Py_TPFLAGS_DEFAULT | python_c.Py_TPFLAGS_BASETYPE | python_c.Py_TPFLAGS_HAVE_GC,
    .tp_new = &constructors.loop_new,
    .tp_traverse = @ptrCast(&constructors.loop_traverse),
    .tp_clear = @ptrCast(&constructors.loop_clear),
    .tp_init = @ptrCast(&constructors.loop_init),
    .tp_dealloc = @ptrCast(&constructors.loop_dealloc),
    .tp_methods = @constCast(PythonLoopMethods.ptr)
};

