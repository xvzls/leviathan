from leviathan import Loop, ThreadSafeLoop

from contextvars import copy_context
from unittest.mock import MagicMock
from typing import Type

import pytest, asyncio, random

DELAY_TIME = 0.01


@pytest.mark.parametrize("loop_obj", [Loop, ThreadSafeLoop])
def test_call_soon(loop_obj: Type[asyncio.AbstractEventLoop]) -> None:
    loop = loop_obj()
    try:
        calls_num = random.randint(1, 20)
        mock_func = MagicMock()
        for i in range(calls_num):
            loop.call_soon(mock_func, i)
        loop.call_soon(loop.stop)
        loop.run_forever()
        assert mock_func.call_count == calls_num

        expected_calls = [((i,),) for i in range(calls_num)]
        assert mock_func.call_args_list == expected_calls
    finally:
        loop.close()


@pytest.mark.parametrize("loop_obj", [Loop, ThreadSafeLoop])
def test_call_soon_with_cancel(loop_obj: Type[asyncio.AbstractEventLoop]) -> None:
    loop = loop_obj()
    try:
        calls_num = random.randint(1, 20)
        mock_func = MagicMock()
        for x in range(calls_num):
            h = loop.call_soon(mock_func, x)
            if x % 2 == 0:
                h.cancel()
        loop.call_soon(loop.stop)
        loop.run_forever()
        assert mock_func.call_count == (calls_num // 2)

        expected_calls = [((i,),) for i in range(calls_num) if i % 2 == 1]
        assert mock_func.call_args_list == expected_calls
    finally:
        loop.close()


@pytest.mark.parametrize("loop_obj", [Loop, ThreadSafeLoop])
def test_call_soon_with_context(loop_obj: Type[asyncio.AbstractEventLoop]) -> None:
    loop = loop_obj()
    try:
        calls_num = random.randint(1, 20)
        mock_func = MagicMock()
        for i in range(calls_num):
            loop.call_soon(mock_func, i, context=copy_context())
        loop.call_soon(loop.stop)
        loop.run_forever()
        assert mock_func.call_count == calls_num

        expected_calls = [((i,),) for i in range(calls_num)]
        assert mock_func.call_args_list == expected_calls
    finally:
        loop.close()


@pytest.mark.parametrize("loop_obj", [Loop, ThreadSafeLoop])
def test_call_later(loop_obj: Type[asyncio.AbstractEventLoop]) -> None:
    loop = loop_obj()
    try:
        calls_num = random.randint(1, 20)
        mock_func = MagicMock()
        start_time = loop.time()
        for i in range(calls_num):
            loop.call_later(DELAY_TIME * (i + 1), mock_func, i)

        loop.call_later(DELAY_TIME * (calls_num + 1), loop.stop)
        loop.run_forever()
        end_time = loop.time()

        assert mock_func.call_count == calls_num
        assert DELAY_TIME * (calls_num + 1) <= (end_time - start_time) <= DELAY_TIME * (calls_num + 2)

        expected_calls = [((i,),) for i in range(calls_num)]
        assert mock_func.call_args_list == expected_calls
    finally:
        loop.close()


@pytest.mark.parametrize("loop_obj", [Loop, ThreadSafeLoop])
def test_call_later_with_cancel(loop_obj: Type[asyncio.AbstractEventLoop]) -> None:
    loop = loop_obj()
    try:
        calls_num = random.randint(1, 20)
        mock_func = MagicMock()
        start_time = loop.time()
        for x in range(calls_num):
            h = loop.call_later(DELAY_TIME * (x + 1), mock_func, x)
            if x % 2 == 0:
                h.cancel()

        loop.call_later(DELAY_TIME * (calls_num + 1), loop.stop)
        loop.run_forever()
        end_time = loop.time()

        assert mock_func.call_count == (calls_num // 2)
        assert DELAY_TIME * (calls_num + 1) <= (end_time - start_time) <= DELAY_TIME * (calls_num + 2)

        expected_calls = [((i,),) for i in range(calls_num) if i % 2 == 1]
        assert mock_func.call_args_list == expected_calls
    finally:
        loop.close()


@pytest.mark.parametrize("loop_obj", [Loop, ThreadSafeLoop])
def test_call_later_with_context(loop_obj: Type[asyncio.AbstractEventLoop]) -> None:
    loop = loop_obj()
    try:
        calls_num = random.randint(1, 20)
        mock_func = MagicMock()
        start_time = loop.time()

        for i in range(calls_num):
            loop.call_later(DELAY_TIME * (i + 1), mock_func, i, context=copy_context())

        loop.call_later(DELAY_TIME * (calls_num + 1), loop.stop)
        loop.run_forever()
        end_time = loop.time()

        assert mock_func.call_count == calls_num
        assert DELAY_TIME * (calls_num + 1) <= (end_time - start_time) <= DELAY_TIME * (calls_num + 2)

        expected_calls = [((i,),) for i in range(calls_num)]
        assert mock_func.call_args_list == expected_calls
    finally:
        loop.close()
