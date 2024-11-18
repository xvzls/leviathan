from .leviathan_zig_single_thread import Loop as _LoopSingleThread
from .leviathan_zig import Loop as _Loop

from typing import Any


class _LoopHelpers:
	def __init__(self) -> None:
		self._exception_handler = self.default_exception_handler

	def _call_exception_handler(self, exc: Exception) -> None:
		context = {
			'exception': exc,
		}
		self._exception_handler(context)

	def default_exception_handler(self, context: dict[str, Any]) -> None:
		print(context)

	def call_exception_handler(self, context: dict[str, Any]) -> None:
		self._exception_handler(context)


class Loop(_LoopSingleThread, _LoopHelpers):
	_thread_safe = False

	def __init__(self, ready_tasks_queue_min_bytes_capacity: int = 10 ** 6) -> None:
		_LoopHelpers.__init__(self)
		_LoopSingleThread.__init__(self, ready_tasks_queue_min_bytes_capacity, self._call_exception_handler)


class ThreadSafeLoop(_Loop, _LoopHelpers):
	_thread_safe = True

	def __init__(self, ready_tasks_queue_min_bytes_capacity: int = 10 ** 6) -> None:
		_LoopHelpers.__init__(self)
		_Loop.__init__(self, ready_tasks_queue_min_bytes_capacity, self._call_exception_handler)
