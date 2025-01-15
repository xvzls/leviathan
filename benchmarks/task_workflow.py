import asyncio

BENCHMARK_NAME = "Async Task Workflow"

async def subtask(_: str) -> None:
    await asyncio.sleep(0.1)

def future_callback(fut: asyncio.Future[str]) -> None:
    result = fut.result()
    loop = asyncio.get_event_loop()

    for i in range(3):
        sub_task_id = f"{result}_sub_{i}"
        loop.create_task(subtask(sub_task_id))

async def consumer(fut: asyncio.Future[str], cid: int) -> None:
    await asyncio.sleep(0.1)
    fut.set_result(f"Consumer_{cid}")

async def main_task(tid: int) -> None:
    loop = asyncio.get_event_loop()

    fut = loop.create_future()
    fut.add_done_callback(future_callback)

    asyncio.create_task(consumer(fut, tid))

    immediate_subtask = asyncio.create_task(subtask(f"main_{tid}"))
    await immediate_subtask

async def main(num_tasks: int) -> None:
    tasks = [asyncio.create_task(main_task(i)) for i in range(num_tasks)]
    
    await asyncio.gather(*tasks)


def run(loop: asyncio.AbstractEventLoop, num_producers: int) -> None:
    loop.run_until_complete(main(num_producers))
