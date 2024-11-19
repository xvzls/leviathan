from leviathan import Future, ThreadSafeFuture, Loop, ThreadSafeLoop
from typing import Type, Any
import pytest, asyncio


@pytest.mark.parametrize("fut_obj, loop_obj", [
	(Future, Loop),
	(ThreadSafeFuture, ThreadSafeLoop),
])
def test_setting_value_and_done(
	fut_obj: Type[asyncio.Future[int]], loop_obj: Type[asyncio.AbstractEventLoop]
) -> None:
	loop = loop_obj()
	try:
		future = fut_obj(loop=loop)
		future.set_result(42)
		assert future.result() == 42
		assert future.done()
	finally:
		loop.close()


@pytest.mark.parametrize("fut_obj, loop_obj", [
	(Future, Loop),
	(ThreadSafeFuture, ThreadSafeLoop),
])
def test_cancelling_after_value(
	fut_obj: Type[asyncio.Future[int]], loop_obj: Type[asyncio.AbstractEventLoop]
) -> None:
	loop = loop_obj()
	try:
		future = fut_obj(loop=loop)
		future.set_result(42)
		future.cancel()
		assert future.result() == 42
		assert future.done()
	finally:
		loop.close()


@pytest.mark.parametrize("fut_obj, loop_obj", [
	(Future, Loop),
	(ThreadSafeFuture, ThreadSafeLoop),
])
def test_cancelling_before_value(
	fut_obj: Type[asyncio.Future[int]], loop_obj: Type[asyncio.AbstractEventLoop]
) -> None:
	loop = loop_obj()
	try:
		future = fut_obj(loop=loop)
		future.cancel()
		with pytest.raises(asyncio.InvalidStateError):
			future.set_result(42)
		assert future.done()
	finally:
		loop.close()

	
@pytest.mark.parametrize("fut_obj, loop_obj", [
	(Future, Loop),
	(ThreadSafeFuture, ThreadSafeLoop),
])
def test_cancelling(
	fut_obj: Type[asyncio.Future[int]], loop_obj: Type[asyncio.AbstractEventLoop]
) -> None:
	loop = loop_obj()
	try:
		future = fut_obj(loop=loop)
		future.cancel()
		assert future.cancelled()
		assert future.done()
	finally:
		loop.close()


@pytest.mark.parametrize("fut_obj, loop_obj", [
	(Future, Loop),
	(ThreadSafeFuture, ThreadSafeLoop),
])
def test_cancelling_with_message(
	fut_obj: Type[asyncio.Future[int]], loop_obj: Type[asyncio.AbstractEventLoop]
) -> None:
	loop = loop_obj()
	try:
		future = fut_obj(loop=loop)
		future.cancel(msg="test")
		assert future.cancelled()
		assert future.done()
		with pytest.raises(asyncio.CancelledError) as exc_info:
			future.result()
		assert exc_info.value.args[0] == "test"
	finally:
		loop.close()


@pytest.mark.parametrize("fut_obj, loop_obj", [
	(Future, ThreadSafeLoop),
	(ThreadSafeFuture, Loop),
])
def test_initializing_with_wrong_loop(
	fut_obj: Type[asyncio.Future[Any]], loop_obj: Type[asyncio.AbstractEventLoop]
) -> None:
	loop = loop_obj()
	try:
		with pytest.raises(ValueError):
			fut_obj(loop=loop)
	finally:
		loop.close()
