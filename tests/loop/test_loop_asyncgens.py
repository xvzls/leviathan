import asyncio
import pytest
from leviathan import Loop, ThreadSafeLoop
from typing import Type, AsyncGenerator


@pytest.mark.parametrize("loop_obj", [Loop, ThreadSafeLoop])
def test_normal_async_generator(loop_obj: Type[asyncio.AbstractEventLoop]) -> None:
    async def async_gen() -> AsyncGenerator[int, None]:
        for i in range(3):
            await asyncio.sleep(0.1)
            yield i

    async def run_gen() -> list[int]:
        results = []
        async for item in async_gen():
            results.append(item)
        return results

    loop = loop_obj()
    try:
        results = loop.run_until_complete(run_gen())
        assert results == [0, 1, 2]
    finally:
        loop.close()


@pytest.mark.parametrize("loop_obj", [Loop, ThreadSafeLoop])
def test_unfinished_async_generator(loop_obj: Type[asyncio.AbstractEventLoop]) -> None:
    cleanup_called = False

    async def async_gen() -> AsyncGenerator[int, None]:
        try:
            for i in range(3):
                await asyncio.sleep(0.1)
                yield i
            await asyncio.sleep(1)  # This sleep will be interrupted
        finally:
            nonlocal cleanup_called
            cleanup_called = True

    async def run_gen() -> tuple[list[int], AsyncGenerator[int, None]]:
        ag = async_gen()
        results = []
        try:
            results.append(await anext(ag))
            results.append(await anext(ag))
            # We don't call anext() a third time, leaving the generator unfinished
        except StopAsyncIteration:
            pass
        return results, ag

    loop = loop_obj()
    try:
        results, _ = loop.run_until_complete(run_gen())
        assert results == [0, 1]
        assert not cleanup_called, "Cleanup shouldn't be called yet"

        # Run shutdown_asyncgens
        loop.run_until_complete(loop.shutdown_asyncgens())

        # Check if the cleanup was called
        assert cleanup_called, "Async generator cleanup was not called"
    finally:
        loop.close()
