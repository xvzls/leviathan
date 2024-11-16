from .leviathan_zig_single_thread import Loop as _LoopSingleThread
from .leviathan_zig import Loop as _Loop

from typing import Any
import asyncio


# _Ts = TypeVarTuple('_Ts')


class Loop(asyncio.AbstractEventLoop):
	def __init__(self, ready_tasks_queue_min_bytes_capacity: int = 10 ** 6, thread_safe: bool = False) -> None:
		if thread_safe:
			loop_leviathan_class = _Loop(
				ready_tasks_queue_min_bytes_capacity, self._call_exception_handler
			)
		else:
			loop_leviathan_class = _LoopSingleThread(
				ready_tasks_queue_min_bytes_capacity, self._call_exception_handler
			)
		self._loop_leviathan_class = loop_leviathan_class

		for x in dir(loop_leviathan_class):
			if x.startswith("_"):
				continue
			obj = getattr(loop_leviathan_class, x)
			if callable(obj):
				setattr(self, x, obj)

		self._exception_handler = self.default_exception_handler
		self._thread_safe = thread_safe

	def _call_exception_handler(self, exc: Exception) -> None:
		context = {
			'exception': exc,
		}
		self._exception_handler(context)

	def default_exception_handler(self, context: dict[str, Any]) -> None:
		print(context)
		return

	def call_exception_handler(self, context: dict[str, Any]) -> None:
		self._exception_handler(context)
