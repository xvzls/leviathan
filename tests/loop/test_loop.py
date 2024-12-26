from leviathan import Loop, ThreadSafeLoop

from contextvars import copy_context
from unittest.mock import MagicMock
from typing import Type

import pytest, asyncio, random


@pytest.mark.parametrize("loop_obj", [Loop, ThreadSafeLoop])
def test_call_soon(loop_obj: Type[asyncio.AbstractEventLoop]) -> None:
	loop = loop_obj()
	try:
		calls_num = random.randint(1, 20)
		mock_func = MagicMock()
		for _ in range(calls_num):
			loop.call_soon(mock_func)
		loop.run_forever()
		assert mock_func.call_count == calls_num
	finally:
		loop.close()


@pytest.mark.parametrize("loop_obj", [Loop, ThreadSafeLoop])
def test_call_soon_with_cancel(loop_obj: Type[asyncio.AbstractEventLoop]) -> None:
	loop = loop_obj()
	try:
		calls_num = random.randint(1, 20)
		mock_func = MagicMock()
		for x in range(calls_num):
			h = loop.call_soon(mock_func)
			if x % 2 == 0:
				h.cancel()
		loop.run_forever()
		assert mock_func.call_count == (calls_num // 2)
	finally:
		loop.close()


@pytest.mark.parametrize("loop_obj", [Loop, ThreadSafeLoop])
def test_call_soon_with_context(loop_obj: Type[asyncio.AbstractEventLoop]) -> None:
    loop = loop_obj()
    try:
        calls_num = random.randint(1, 20)
        mock_func = MagicMock()
        for _ in range(calls_num):
            loop.call_soon(mock_func, context=copy_context())
        loop.run_forever()
        assert mock_func.call_count == calls_num
    finally:
        loop.close()
