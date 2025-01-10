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
        assert asyncio.isfuture(task_obj(AsyncMock()(), loop=loop))

        coro = AsyncMock()()
        with pytest.raises(TypeError):
            task_obj(coro, loop=another_loop)

        with pytest.raises(TypeError):
            task_obj(None, loop=loop)  # type: ignore
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
