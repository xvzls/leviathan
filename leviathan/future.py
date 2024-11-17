from .leviathan_zig_single_thread import Future as _FutureSingleThread
from .leviathan_zig import Future as _Future

from typing import TypeVar
import asyncio

T = TypeVar('T')


class Future(asyncio.Future[T]):
	def __init__(self, *, loop: asyncio.AbstractEventLoop | None = None) -> None:
		if loop is None:
			loop = asyncio.get_running_loop()

		leviathan_loop = getattr(loop, "_loop_leviathan_class", None)
		if leviathan_loop is None:
			raise ValueError("The given loop is not a leviathan event loop")

		thread_safe = getattr(loop, "_thread_safe")
		if thread_safe is None:
			raise ValueError("The given loop is not a leviathan event loop")

		if thread_safe:
			future_leviathan_class = _Future(leviathan_loop)
		else:
			future_leviathan_class = _FutureSingleThread(leviathan_loop)
	
		self._future_leviathan_class = future_leviathan_class
		for x in dir(future_leviathan_class):
			if x.startswith("_"):
				continue
			obj = getattr(future_leviathan_class, x)
			if callable(obj):
				setattr(self, x, obj)

		self._thread_safe = thread_safe
