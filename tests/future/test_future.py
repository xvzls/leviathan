from leviathan import Future, Loop

from typing import Any
import pytest, asyncio


def test_setting_value_and_done() -> None:
	loop = Loop()
	try:
		future = Future[Any](loop=loop)
		future.set_result(42)
		assert future.result() == 42
		assert future.done()
	finally:
		loop.close()


def test_cancelling_after_value() -> None:
	loop = Loop()
	try:
		future = Future[Any](loop=loop)
		future.set_result(42)
		future.cancel()
		assert future.result() == 42
		assert future.done()
	finally:
		loop.close()


def test_cancelling_before_value() -> None:
	loop = Loop()
	try:
		future = Future[Any](loop=loop)
		future.cancel()
		with pytest.raises(asyncio.InvalidStateError):
			future.set_result(42)
		assert future.done()
	finally:
		loop.close()

	
def test_cancelling() -> None:
	loop = Loop()
	try:
		future = Future[Any](loop=loop)
		future.cancel()
		assert future.cancelled()
		assert future.done()
	finally:
		loop.close()


def test_cancelling_with_message() -> None:
	loop = Loop()
	try:
		future = Future[Any](loop=loop)
		future.cancel(msg="test")
		assert future.cancelled()
		assert future.done()
		with pytest.raises(asyncio.CancelledError) as exc_info:
			future.result()
		assert exc_info.value.args[0] == "test"
	finally:
		loop.close()
