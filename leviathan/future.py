from .leviathan_zig_single_thread import Future as _FutureSingleThread
from .leviathan_zig import Future as _Future

from typing import TypeVar
import asyncio

T = TypeVar('T')


class Future(_FutureSingleThread):
	_thread_safe = False

	def __init__(self, *, loop: asyncio.AbstractEventLoop | None = None) -> None:
		if loop is None:
			loop = asyncio.get_running_loop()

		thread_safe = getattr(loop, "_thread_safe")
		if thread_safe != False:
			raise ValueError("The given loop is not a leviathan event loop")

		_FutureSingleThread.__init__(self, loop)


class ThreadSafeFuture(_Future):
	_thread_safe = True

	def __init__(self, *, loop: asyncio.AbstractEventLoop | None = None) -> None:
		if loop is None:
			loop = asyncio.get_running_loop()

		thread_safe = getattr(loop, "_thread_safe")
		if thread_safe != True:
			raise ValueError("The given loop is not a leviathan event loop")

		_Future.__init__(self, loop)
