
from .leviathan_zig import Handle as _Handle
from .leviathan_zig_single_thread import Handle as _HandleSingleThread

from contextvars import Context, copy_context
from typing import Any, Callable, Sequence
import asyncio


class Handle(asyncio.Handle):
	def __init__(self, callback: Callable[..., None], args: Sequence[Any], loop: asyncio.AbstractEventLoop,
			  thread_safe: bool, context: Context | None = None) -> None:
		if context is None:
			context = copy_context()

		leviathan_loop = getattr(loop, "_loop_leviathan_class", None)
		if leviathan_loop is None:
			raise ValueError("The given loop is not a leviathan event loop")

		exception_handler = getattr(loop, "_call_exception_handler", None)
		if exception_handler is None:
			raise ValueError("The given loop is not a leviathan event loop")

		callback_info = (callback, *args)
		if thread_safe:
			handle_leviathan_class = _Handle(
				callback_info, leviathan_loop, context, exception_handler
			)
		else:
			handle_leviathan_class = _HandleSingleThread(
				callback_info, leviathan_loop, context, exception_handler
			)
		self._handle_leviathan_class = handle_leviathan_class
		self._loop = loop

		# for x in dir(handle_leviathan_class):
		# 	if x.startswith("_"):
		# 		continue
		# 	obj = getattr(handle_leviathan_class, x)
		# 	if callable(obj):
		# 		setattr(self, x, obj)
