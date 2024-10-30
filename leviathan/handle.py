
from .leviathan_zig import Handle as _Handle # type: ignore

from contextvars import Context, copy_context
from typing import Any, Callable, Sequence
import asyncio


class Handle(asyncio.Handle):
	def __init__(self, callback: Callable[..., object], args: Sequence[Any], loop: asyncio.AbstractEventLoop,
			  context: Context | None = None, thread_safe: bool = False) -> None:
		if context is None:
			context = copy_context()

		leviathan_loop = getattr(loop, "_loop_leviathan_class", None)
		if leviathan_loop is None:
			raise ValueError("The given loop is not a leviathan event loop")

		callback_info = (callback, *args)
		handle_leviathan_class = _Handle(
			callback_info, leviathan_loop, context, loop.call_exception_handler, thread_safe
		)
		self._handle_leviathan_class = handle_leviathan_class

		for x in dir(handle_leviathan_class):
			if x.startswith("__"):
				continue
			obj = getattr(handle_leviathan_class, x)
			if callable(obj):
				setattr(self, x, obj)
