from leviathan import Task, ThreadSafeTask, Loop, ThreadSafeLoop
from unittest.mock import MagicMock

from contextvars import copy_context, Context
from typing import Type, Any
import pytest, asyncio

async def coro_test(*opt: Any, **kwargs: Any) -> tuple[Any, dict[str, Any]]:
    return opt, kwargs


@pytest.mark.parametrize("task_obj, loop_obj", [
    (Task, Loop),
    (ThreadSafeTask, ThreadSafeLoop),
])
def test_checking_subclassing(
    task_obj: Type[asyncio.Task[Any]], loop_obj: Type[asyncio.AbstractEventLoop]
) -> None:
    loop = loop_obj()
    try:
        coro = coro_test()
        assert asyncio.isfuture(task_obj(coro, loop=loop))
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
        coro = coro_test()
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
        coro = coro_test()
        task = task_obj(coro, loop=loop)
        assert type(task.get_context()) is Context

        ctx = copy_context()
        task = task_obj(coro, loop=loop, context=ctx)
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
        coro = coro_test()
        task = task_obj(coro, loop=loop)
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
        coro = coro_test()
        task = task_obj(coro, loop=loop, name="test")
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
        coro = coro_test()
        task = task_obj(coro, loop=loop)
        task.print_stack()
    finally:
        loop.close()
