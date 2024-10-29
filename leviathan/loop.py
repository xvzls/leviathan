from .leviathan_zig import Loop as _Loop # type: ignore

from typing import Any
import asyncio


class Loop(asyncio.AbstractEventLoop):
	def __init__(self, ready_tasks_queue_min_bytes_capacity: int = 10 ** 6, thread_safe: bool = False) -> None:
		self._loop_leviathan_class = _Loop(ready_tasks_queue_min_bytes_capacity, thread_safe)

	def __getattribute__(self, name: str, /) -> Any:
		if name == '_loop_leviathan_class':
			return super().__getattribute__(name)
		leviathan_class = self._loop_leviathan_class
		if hasattr(leviathan_class, name):
			return getattr(leviathan_class, name)
		return super().__getattribute__(name)

	def __setattr__(self, name: str, value: Any, /) -> None:
		if name == '_loop_leviathan_class':
			return super().__setattr__(name, value)
		leviathan_class = self._loop_leviathan_class
		if hasattr(leviathan_class, name):
			setattr(leviathan_class, name, value)
		else:
			super().__setattr__(name, value)
