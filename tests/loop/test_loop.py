from leviathan import Loop

from unittest.mock import MagicMock
from typing import Any
import pytest, asyncio, random


def test_call_soon() -> None:
	loop = Loop()
	try:
		calls_num = random.randint(1, 20)
		mock_func = MagicMock()
		for _ in range(calls_num):
			loop.call_soon(mock_func)
		loop.run_forever()
		assert mock_func.call_count == calls_num
	finally:
		loop.close()


def test_call_soon_with_cancel() -> None:
	loop = Loop()
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
