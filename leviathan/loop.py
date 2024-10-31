from .leviathan_zig import Loop as _Loop
from .leviathan_zig import Handle as _Handle
from .handle import Handle

from typing import Callable, Unpack, TypeVarTuple, Any
from contextvars import Context
import asyncio


_Ts = TypeVarTuple('_Ts')


class Loop(asyncio.AbstractEventLoop):
	def __init__(self, ready_tasks_queue_min_bytes_capacity: int = 10 ** 6, thread_safe: bool = False) -> None:
		loop_leviathan_class = _Loop(ready_tasks_queue_min_bytes_capacity, thread_safe)
		self._loop_leviathan_class = loop_leviathan_class

		for x in dir(loop_leviathan_class):
			if x.startswith("_"):
				continue
			obj = getattr(loop_leviathan_class, x)
			if callable(obj):
				setattr(self, x, obj)

		self._call_soon = loop_leviathan_class._call_soon
	
		self._exception_handler = self.default_exception_handler

	def call_soon(self, callback: Callable[[Unpack[_Ts]], object], *args: Unpack[_Ts],
			   context: Context | None = None) -> Handle:
		handle = Handle(callback, args, self, context)
		self._call_soon(handle._handle_leviathan_class)
		return handle

	def default_exception_handler(self, context: dict[str, Any]) -> None:
		print(context)
		return

	def call_exception_handler(self, context: dict[str, Any]) -> None:
		self._exception_handler(context)
