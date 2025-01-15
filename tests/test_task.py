from leviathan import Task, ThreadSafeTask, Loop, ThreadSafeLoop
from unittest.mock import AsyncMock

from contextvars import copy_context, Context
from typing import Type, Any
import pytest, asyncio, io


@pytest.mark.parametrize("task_obj, loop_obj", [
    (Task, Loop),
    (ThreadSafeTask, ThreadSafeLoop),
])
def test_checking_subclassing_and_arguments(
    task_obj: Type[asyncio.Task[Any]], loop_obj: Type[asyncio.AbstractEventLoop]
) -> None:
    another_loop = asyncio.new_event_loop()
    loop = loop_obj()
    try:
        coro = AsyncMock()()
        with pytest.raises(TypeError):
            task_obj(coro, loop=another_loop)

        assert asyncio.isfuture(task_obj(coro, loop=loop))
        with pytest.raises(TypeError):
            task_obj(None, loop=loop)  # type: ignore

        loop.call_soon(loop.stop)
        loop.run_forever()
    finally:
        loop.close()


@pytest.mark.parametrize("task_obj, loop_obj", [
    (Task, Loop),
    (ThreadSafeTask, ThreadSafeLoop),
])
def test_get_coro(
    task_obj: Type[asyncio.Task[Any]], loop_obj: Type[asyncio.AbstractEventLoop]
) -> None:
    loop = loop_obj()
    try:
        coro = AsyncMock()()
        task = task_obj(coro, loop=loop)
        assert task.get_coro() is coro
    finally:
        loop.close()


@pytest.mark.parametrize("task_obj, loop_obj", [
    (Task, Loop),
    (ThreadSafeTask, ThreadSafeLoop),
])
def test_get_context(
    task_obj: Type[asyncio.Task[Any]], loop_obj: Type[asyncio.AbstractEventLoop]
) -> None:
    loop = loop_obj()
    try:
        task = task_obj(AsyncMock()(), loop=loop)
        assert type(task.get_context()) is Context

        ctx = copy_context()
        task = task_obj(AsyncMock()(), loop=loop, context=ctx)
        assert task.get_context() is ctx
    finally:
        loop.close()


@pytest.mark.parametrize("task_obj, loop_obj", [
    (Task, Loop),
    (ThreadSafeTask, ThreadSafeLoop)
])
def test_get_loop(
    task_obj: Type[asyncio.Task[Any]], loop_obj: Type[asyncio.AbstractEventLoop]
) -> None:
    loop = loop_obj()
    try:
        task = task_obj(AsyncMock()(), loop=loop)
        assert task.get_loop() is loop
    finally:
        loop.close()


@pytest.mark.parametrize("task_obj, loop_obj", [
    (Task, Loop),
    (ThreadSafeTask, ThreadSafeLoop)
])
def test_name(
    task_obj: Type[asyncio.Task[Any]], loop_obj: Type[asyncio.AbstractEventLoop]
) -> None:
    loop = loop_obj()
    try:
        task = task_obj(AsyncMock()(), loop=loop)
        assert task.get_name()

        task = task_obj(AsyncMock()(), loop=loop, name="test")
        assert task.get_name() == "test"

        task.set_name("test2")
        assert task.get_name() == "test2"

        task.set_name(23)
        assert task.get_name() == "23"
    finally:
        loop.close()


@pytest.mark.parametrize("task_obj, loop_obj", [
    (Task, Loop),
    (ThreadSafeTask, ThreadSafeLoop)
])
def test_stack(
    task_obj: Type[asyncio.Task[Any]], loop_obj: Type[asyncio.AbstractEventLoop]
) -> None:
    loop = loop_obj()
    try:
        task = task_obj(AsyncMock()(), loop=loop)
        with io.StringIO() as buf:
            task.print_stack(file=buf)
            assert buf.getvalue()
    finally:
        loop.close()


@pytest.mark.parametrize("task_obj, loop_obj", [
    (Task, Loop),
    (ThreadSafeTask, ThreadSafeLoop)
])
def test_coro_running(
    task_obj: Type[asyncio.Task[Any]], loop_obj: Type[asyncio.AbstractEventLoop]
) -> None:
    loop = loop_obj()
    try:
        coro = AsyncMock(return_value=42)
        task = task_obj(coro(), loop=loop)
        loop.call_soon(loop.stop)
        loop.run_forever()

        coro.assert_called_once()
        assert task.result() == 42
    finally:
        loop.close()


@pytest.mark.parametrize("task_obj, loop_obj", [
    (Task, Loop),
    (ThreadSafeTask, ThreadSafeLoop)
])
def test_current_task(
    task_obj: Type[asyncio.Task[Any]], loop_obj: Type[asyncio.AbstractEventLoop]
) -> None:
    async def test_func(loop: asyncio.AbstractEventLoop) -> asyncio.Task[Any]|None:
        return asyncio.current_task(loop)

    loop = loop_obj()
    try:
        task = task_obj(test_func(loop), loop=loop)
        loop.call_soon(loop.stop)
        loop.run_forever()

        assert task.result() == task
    finally:
        loop.close()

@pytest.mark.parametrize("loop_obj", [Loop, ThreadSafeLoop])
def test_parent_task_cancels_child(loop_obj: Type[asyncio.AbstractEventLoop]) -> None:
    async def child_task() -> str|None:
        try:
            await asyncio.sleep(1)
            return None
        except asyncio.CancelledError:
            return "Child cancelled"

    async def parent_task() -> str|None:
        child = asyncio.create_task(child_task())
        await asyncio.sleep(0.1)
        child.cancel()
        result = await child
        return result

    loop = loop_obj()
    try:
        result = loop.run_until_complete(parent_task())
        assert result == "Child cancelled"
    finally:
        loop.close()

@pytest.mark.parametrize("loop_obj", [Loop, ThreadSafeLoop])
def test_parent_task_cancels_while_awaiting(loop_obj: Type[asyncio.AbstractEventLoop]) -> None:
    async def child_task() -> str|None:
        try:
            await asyncio.sleep(1)
            return None
        except asyncio.CancelledError:
            return "Child cancelled"

    async def parent_task(child: asyncio.Task[Any]) -> str|None:
        result = await child
        return result

    loop = loop_obj()
    try:
        task2 = loop.create_task(child_task())
        loop.call_later(0.1, task2.cancel)
        result = loop.run_until_complete(parent_task(task2))
        assert result == "Child cancelled"
    finally:
        loop.close()

@pytest.mark.parametrize("loop_obj", [Loop, ThreadSafeLoop])
def test_cancel_parent_not_child(loop_obj: Type[asyncio.AbstractEventLoop]) -> None:
    child_done = asyncio.Event()

    async def child_task() -> str:
        try:
            await asyncio.sleep(0.5)
            child_done.set()
            return "Child completed"
        except asyncio.CancelledError:
            return "Child cancelled"

    async def parent_task() -> tuple[str, str]|None:
        child = asyncio.create_task(child_task())
        try:
            await asyncio.sleep(1)
            return None
        except asyncio.CancelledError:
            await child
            return "Parent cancelled", await child

    loop = loop_obj()
    try:
        parent = asyncio.ensure_future(parent_task(), loop=loop)
        loop.call_later(0.1, parent.cancel)
        result = loop.run_until_complete(parent)
        assert result == ("Parent cancelled", "Child completed")
        assert child_done.is_set()
    finally:
        loop.close()

@pytest.mark.parametrize("loop_obj", [Loop, ThreadSafeLoop])
def test_cancel_parent_with_long_wait(loop_obj: Type[asyncio.AbstractEventLoop]) -> None:
    child_done = asyncio.Event()

    async def child_task() -> str:
        try:
            await asyncio.sleep(0.5)
            child_done.set()
            return "Child completed"
        except asyncio.CancelledError:
            return "Child cancelled"

    async def parent_task() -> tuple[str, str]|None:
        child = asyncio.create_task(child_task())
        try:
            await asyncio.sleep(3600)
            return None
        except asyncio.CancelledError:
            await child
            return "Parent cancelled", await child

    loop = loop_obj()
    try:
        parent = asyncio.ensure_future(parent_task(), loop=loop)
        loop.call_later(0.1, parent.cancel)
        result = loop.run_until_complete(parent)
        assert result == ("Parent cancelled", "Child completed")
        assert child_done.is_set()
    finally:
        loop.close()

@pytest.mark.parametrize("loop_obj", [Loop, ThreadSafeLoop])
def test_task_exception_propagation(loop_obj: Type[asyncio.AbstractEventLoop]) -> None:
    async def raise_exception() -> None:
        raise ValueError("Test exception")

    async def parent_task() -> None:
        await asyncio.create_task(raise_exception())

    loop = loop_obj()
    try:
        with pytest.raises(ValueError, match="Test exception"):
            loop.run_until_complete(parent_task())
    finally:
        loop.close()

@pytest.mark.parametrize("loop_obj", [Loop, ThreadSafeLoop])
def test_task_result_timing(loop_obj: Type[asyncio.AbstractEventLoop]) -> None:
    async def slow_task() -> str:
        await asyncio.sleep(0.1)
        return "Done"

    loop = loop_obj()
    try:
        task = asyncio.ensure_future(slow_task(), loop=loop)
        with pytest.raises(asyncio.InvalidStateError):
            task.result()  # Should raise because task is not done
        loop.run_until_complete(task)
        assert task.result() == "Done"  # Should not raise now
    finally:
        loop.close()

@pytest.mark.parametrize("loop_obj", [Loop, ThreadSafeLoop])
def test_task_cancel_callback(loop_obj: Type[asyncio.AbstractEventLoop]) -> None:
    cancel_called = False

    def on_cancel(_: asyncio.Task[None]) -> None:
        nonlocal cancel_called
        cancel_called = True

    async def cancelable_task() -> None:
        try:
            await asyncio.sleep(1)
        except asyncio.CancelledError:
            raise

    loop = loop_obj()
    try:
        task = asyncio.ensure_future(cancelable_task(), loop=loop)
        task.add_done_callback(on_cancel)
        loop.call_later(0.1, task.cancel)
        with pytest.raises(asyncio.CancelledError):
            loop.run_until_complete(task)
        assert cancel_called
    finally:
        loop.close()
