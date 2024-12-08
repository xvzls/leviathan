from leviathan import Future, ThreadSafeFuture, Loop, ThreadSafeLoop
from unittest.mock import MagicMock
from typing import Type, Any
import pytest, asyncio


@pytest.mark.parametrize("fut_obj, loop_obj", [
	(Future, Loop),
	(ThreadSafeFuture, ThreadSafeLoop),
])
def test_checking_subclassing(
	fut_obj: Type[asyncio.Future[Any]], loop_obj: Type[asyncio.AbstractEventLoop]
) -> None:
	loop = loop_obj()
	try:
		assert asyncio.isfuture(fut_obj(loop=loop))
	finally:
		loop.close()


@pytest.mark.parametrize("fut_obj, loop_obj", [
	(Future, Loop),
	(ThreadSafeFuture, ThreadSafeLoop),
])
def test_getting_loop(
	fut_obj: Type[asyncio.Future[Any]], loop_obj: Type[asyncio.AbstractEventLoop]
) -> None:
	loop = loop_obj()
	try:
		future = fut_obj(loop=loop)
		assert future.get_loop() is loop
	finally:
		loop.close()


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
		assert not(future.cancelled())
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
		assert not(future.cancel())
		assert not(future.cancelled())
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
		assert future.cancel()
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
		assert future.cancel()
		assert future.cancelled()
		assert future.done()
	finally:
		loop.close()


@pytest.mark.parametrize("fut_obj, loop_obj", [
	(Future, Loop),
	(ThreadSafeFuture, ThreadSafeLoop),
])
def test_setting_exception(
	fut_obj: Type[asyncio.Future[int]], loop_obj: Type[asyncio.AbstractEventLoop]
) -> None:
	loop = loop_obj()
	try:
		future = fut_obj(loop=loop)
		exc = RuntimeError("test")
		future.set_exception(exc)
		assert future.exception() is exc
		assert not(future.cancelled())
		assert future.done()
		with pytest.raises(RuntimeError) as exc_info:
			future.result()
		assert exc_info.value.args[0] == "test"
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
		with pytest.raises(TypeError):
			fut_obj(loop=loop)
	finally:
		loop.close()

@pytest.mark.parametrize("fut_obj, loop_obj", [
	(Future, Loop),
	(ThreadSafeFuture, ThreadSafeLoop),
])
def test_adding_callback(
	fut_obj: Type[asyncio.Future[Any]], loop_obj: Type[asyncio.AbstractEventLoop]
) -> None:
	loop = loop_obj()
	try:
		future = fut_obj(loop=loop)
		mock_func = MagicMock()
		future.add_done_callback(mock_func)
		future.set_result(42)
		assert future.done()

		loop.run_forever()
		assert mock_func.call_count == 1
	finally:
		loop.close()


@pytest.mark.parametrize("fut_obj, loop_obj", [
	(Future, Loop),
	(ThreadSafeFuture, ThreadSafeLoop),
])
def test_adding_several_callbacks(
	fut_obj: Type[asyncio.Future[Any]], loop_obj: Type[asyncio.AbstractEventLoop]
) -> None:
	loop = loop_obj()
	try:
		future = fut_obj(loop=loop)
		mock_func = MagicMock()
		mock_func2 = MagicMock()
		mock_func3 = MagicMock()

		future.add_done_callback(mock_func)
		for _ in range(3):
			future.add_done_callback(mock_func2)
			future.add_done_callback(mock_func3)

		for _ in range(10):
			future.add_done_callback(mock_func3)

		future.set_result(42)
		assert future.done()

		loop.run_forever()
		assert mock_func.call_count == 1
		assert mock_func2.call_count == 3
		assert mock_func3.call_count == 13
	finally:
		loop.close()


@pytest.mark.parametrize("fut_obj, loop_obj", [
	(Future, Loop),
	(ThreadSafeFuture, ThreadSafeLoop),
])
def test_adding_several_callbacks_and_removing(
	fut_obj: Type[asyncio.Future[Any]], loop_obj: Type[asyncio.AbstractEventLoop]
) -> None:
	loop = loop_obj()
	try:
		future = fut_obj(loop=loop)
		mock_func = MagicMock()
		mock_func2 = MagicMock()
		mock_func3 = MagicMock()

		future.add_done_callback(mock_func)
		for _ in range(3):
			future.add_done_callback(mock_func2)
			future.add_done_callback(mock_func3)

		for _ in range(10):
			future.add_done_callback(mock_func3)

		assert future.remove_done_callback(mock_func2) == 3
		assert future.remove_done_callback(mock_func3) == 13

		future.set_result(42)
		assert future.done()

		loop.run_forever()
		assert mock_func.call_count == 1
		assert mock_func2.call_count == 0
		assert mock_func3.call_count == 0
	finally:
		loop.close()


@pytest.mark.parametrize("fut_obj, loop_obj", [
	(Future, Loop),
	(ThreadSafeFuture, ThreadSafeLoop),
])
def test_adding_callbacks_after_setting_result(
	fut_obj: Type[asyncio.Future[Any]], loop_obj: Type[asyncio.AbstractEventLoop]
) -> None:
	loop = loop_obj()
	try:
		future = fut_obj(loop=loop)
		mock_func = MagicMock()
		mock_func2 = MagicMock()
		mock_func3 = MagicMock()

		future.add_done_callback(mock_func)
		for _ in range(3):
			future.add_done_callback(mock_func2)
			future.add_done_callback(mock_func3)

		future.set_result(42)

		for _ in range(10):
			future.add_done_callback(mock_func3)

		assert future.done()

		loop.run_forever()
		assert mock_func.call_count == 1
		assert mock_func2.call_count == 3
		assert mock_func3.call_count == 13
	finally:
		loop.close()

@pytest.mark.parametrize("fut_obj, loop_obj", [
	(Future, Loop),
	(ThreadSafeFuture, ThreadSafeLoop),
])
def test_future_await(
	fut_obj: Type[asyncio.Future[Any]], loop_obj: Type[asyncio.AbstractEventLoop]
) -> None:
	async def test_func(fut: asyncio.Future[int]) -> int:
		loop = asyncio.get_running_loop()
		loop.call_soon(fut.set_result, 42)
		result = await fut
		return result

	# TODO: Replace asyncio loop by leviathan
	a_loop = asyncio.new_event_loop()
	loop = loop_obj()
	try:
		future = fut_obj(loop=loop)
		result = a_loop.run_until_complete(test_func(future))
		assert future.done()
		assert future.result() == 42
		assert result == 42
	finally:
		loop.close()
