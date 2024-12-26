
from leviathan import Loop, ThreadSafeLoop

from contextvars import copy_context
from unittest.mock import MagicMock, AsyncMock
from typing import Type

import pytest, asyncio, random


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
        loop.run_forever()
        assert task.result() == 42
        mock_func.assert_called()
    finally:
        loop.close()


@pytest.mark.parametrize("loop_obj", [Loop, ThreadSafeLoop])
def test_create_task_with_context(loop_obj: Type[asyncio.AbstractEventLoop]) -> None:
    mock_func = AsyncMock(return_value=42)
    loop = loop_obj()
    try:
        task = loop.create_task(mock_func())
        loop.run_forever()
        assert task.result() == 42
        mock_func.assert_called()
    finally:
        loop.close()
