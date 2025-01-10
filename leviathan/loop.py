from .leviathan_zig_single_thread import Loop as _LoopSingleThread
from .leviathan_zig import Loop as _Loop

from typing import Any, Callable, TypedDict, NotRequired, AsyncGenerator
from logging import getLogger
import asyncio, socket

logger = getLogger(__package__)


class ExceptionContext(TypedDict):
    message: NotRequired[str]
    exception: Exception
    callback: NotRequired[object]
    future: NotRequired[asyncio.Future[Any]]
    task: NotRequired[asyncio.Task[Any]]
    handle: NotRequired[asyncio.Handle]
    protocol: NotRequired[asyncio.Protocol]
    socket: NotRequired[socket.socket]
    asyncgenerator: NotRequired[AsyncGenerator[Any]]


class _LoopHelpers:
    def __init__(self) -> None:
        self._exception_handler: Callable[[ExceptionContext], None] = (
            self.default_exception_handler
        )

    def _call_exception_handler(
        self,
        exception: Exception,
        *,
        message: str | None = None,
        callback: object | None = None,
        future: asyncio.Future[Any] | None = None,
        task: asyncio.Task[Any] | None = None,
        handle: asyncio.Handle | None = None,
        protocol: asyncio.Protocol | None = None,
        socket: socket.socket | None = None,
        asyncgenerator: AsyncGenerator[Any] | None = None,
    ) -> None:
        context: ExceptionContext = {"exception": exception}
        if message is not None:
            context["message"] = message
        if callback is not None:
            context["callback"] = callback
        if future is not None:
            context["future"] = future
        if task is not None:
            context["task"] = task
        if handle is not None:
            context["handle"] = handle
        if protocol is not None:
            context["protocol"] = protocol
        if socket is not None:
            context["socket"] = socket
        if asyncgenerator is not None:
            context["asyncgenerator"] = asyncgenerator

        self._exception_handler(context)

    def default_exception_handler(self, context: ExceptionContext) -> None:
        message = context.get("message")
        if not message:
            message = "Unhandled exception in event loop"

        log_lines = [message]
        for key, value in context.items():
            if key in {"message", "exception"}:
                continue
            log_lines.append(f"{key}: {value!r}")

        exception = context.get("exception")
        logger.error("\n".join(log_lines), exc_info=exception)

    def call_exception_handler(self, context: ExceptionContext) -> None:
        self._exception_handler(context)

    # --------------------------------------------------------------------------------------------------------
    # If you're interested in using debug mode, use the CPython event loop implementation instead of Leviathan.
    def get_debug(self) -> bool:
        return False

    def set_debug(self, enabled: bool) -> None:
        _ = enabled
        return

    # --------------------------------------------------------------------------------------------------------


class Loop(_LoopSingleThread, _LoopHelpers):
    def __init__(self, ready_tasks_queue_min_bytes_capacity: int = 10**6) -> None:
        _LoopHelpers.__init__(self)
        _LoopSingleThread.__init__(
            self, ready_tasks_queue_min_bytes_capacity, self._call_exception_handler
        )


class ThreadSafeLoop(_Loop, _LoopHelpers):
    def __init__(self, ready_tasks_queue_min_bytes_capacity: int = 10**6) -> None:
        _LoopHelpers.__init__(self)
        _Loop.__init__(
            self, ready_tasks_queue_min_bytes_capacity, self._call_exception_handler
        )
