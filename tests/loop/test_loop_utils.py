
from leviathan import Loop, ThreadSafeLoop

from contextvars import Context, copy_context
from unittest.mock import AsyncMock
from time import monotonic
from typing import Type

import pytest, asyncio


@pytest.mark.parametrize("loop_obj", [Loop, ThreadSafeLoop])
def test_create_future(loop_obj: Type[asyncio.AbstractEventLoop]) -> None:
    loop = loop_obj()
    try:
        loop.create_future()
    finally:
        loop.close()


@pytest.mark.parametrize("loop_obj", [Loop, ThreadSafeLoop])
def test_create_task(loop_obj: Type[asyncio.AbstractEventLoop]) -> None:
    mock_func = AsyncMock(return_value=42)
    loop = loop_obj()
    try:
        task = loop.create_task(mock_func())
        loop.call_soon(loop.stop)
        loop.run_forever()
        mock_func.assert_called()
        mock_func.assert_awaited()
        assert task.result() == 42
    finally:
        loop.close()


@pytest.mark.parametrize("loop_obj", [Loop, ThreadSafeLoop])
def test_create_task_with_name(loop_obj: Type[asyncio.AbstractEventLoop]) -> None:
    mock_func = AsyncMock(return_value=42)
    loop = loop_obj()
    try:
        task = loop.create_task(mock_func(), name="test")
        loop.call_soon(loop.stop)
        loop.run_forever()

        mock_func.assert_called()
        mock_func.assert_awaited()
        assert task.result() == 42
    finally:
        loop.close()

@pytest.mark.parametrize("loop_obj", [Loop, ThreadSafeLoop])
def test_create_task_with_context(loop_obj: Type[asyncio.AbstractEventLoop]) -> None:
    async def test_func(context: Context) -> bool:
        return dict(context) == dict(copy_context())

    loop = loop_obj()
    try:
        context = copy_context()
        task = loop.create_task(test_func(context), context=context)
        loop.call_soon(loop.stop)
        loop.run_forever()
        assert task.result()
    finally:
        loop.close()

@pytest.mark.parametrize("loop_obj", [Loop, ThreadSafeLoop])
def test_create_task_with_context_and_name(loop_obj: Type[asyncio.AbstractEventLoop]) -> None:
    async def test_func(context: Context) -> bool:
        return dict(context) == dict(copy_context())

    loop = loop_obj()
    try:
        context = copy_context()
        task = loop.create_task(test_func(context), name="test", context=context)
        loop.call_soon(loop.stop)
        loop.run_forever()

        assert task.result()
        assert task.get_name() == "test"
    finally:
        loop.close()

@pytest.mark.parametrize("loop_obj", [Loop, ThreadSafeLoop])
def test_time(loop_obj: Type[asyncio.AbstractEventLoop]) -> None:
    loop = loop_obj()
    try:
        py_monotonic = monotonic()
        loop_monotonic = loop.time()
        assert abs(py_monotonic - loop_monotonic) < 0.1
    finally:
        loop.close()
