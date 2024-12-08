from .leviathan_zig_single_thread import Future as _FutureSingleThread
from .leviathan_zig import Future as _Future
import asyncio


class Future(_FutureSingleThread):
    def __init__(self, *, loop: asyncio.AbstractEventLoop | None = None) -> None:
        if loop is None:
            loop = asyncio.get_running_loop()

        _FutureSingleThread.__init__(self, loop)


class ThreadSafeFuture(_Future):
    def __init__(self, *, loop: asyncio.AbstractEventLoop | None = None) -> None:
        if loop is None:
            loop = asyncio.get_running_loop()

        _Future.__init__(self, loop)
