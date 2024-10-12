from .leviathan_zig import Future as _Future # type: ignore

from typing import TypeVar, Any
import asyncio

T = TypeVar('T')


class Future(asyncio.Future[T]):
	def __init__(self, *, loop: asyncio.AbstractEventLoop | None = None) -> None:
		if loop is None:
			loop = asyncio.get_running_loop()
		leviathan_loop = getattr(loop, "_loop_leviathan_class", None)
		if leviathan_loop is None:
			raise ValueError("The given loop is not a leviathan event loop")
	
		self._future_leviathan_class = _Future(leviathan_loop)

	def __getattribute__(self, name: str, /) -> Any:
		if name == '_future_leviathan_class':
			return super().__getattribute__(name)
		leviathan_class = self._future_leviathan_class
		if hasattr(leviathan_class, name):
			return getattr(leviathan_class, name)
		return super().__getattribute__(name)

	def __setattr__(self, name: str, value: Any, /) -> None:
		if name == '_future_leviathan_class':
			return super().__setattr__(name, value)
		leviathan_class = self._future_leviathan_class
		if hasattr(leviathan_class, name):
			setattr(leviathan_class, name, value)
		else:
			super().__setattr__(name, value)
