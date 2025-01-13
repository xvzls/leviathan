from typing import Callable, List, Tuple, Dict, TypedDict
from prettytable import PrettyTable

import uvloop, asyncio, time, leviathan
import matplotlib.pyplot as plt
import matplotlib

matplotlib.use("QtAgg")

from benchmarks.producer_consumer import (
    run as benchmark1_run,
    BENCHMARK_NAME as benchmark1_name,
)
from benchmarks.task_workflow import (
    run as benchmark2_run,
    BENCHMARK_NAME as benchmark2_name,
)
from benchmarks.event_fiesta_factory import (
    run as benchmark3_run,
    BENCHMARK_NAME as benchmark3_name,
)
from benchmarks.chat import run as benchmark4_run, BENCHMARK_NAME as benchmark4_name
from benchmarks.food_delivery import (
    run as benchmark5_run,
    BENCHMARK_NAME as benchmark5_name,
)

BENCHMARK_FUNCTIONS: List[
    Tuple[Callable[[asyncio.AbstractEventLoop, int], None], str]
] = [
    (benchmark1_run, benchmark1_name),
    (benchmark2_run, benchmark2_name),
    (benchmark3_run, benchmark3_name),
    (benchmark4_run, benchmark4_name),
    (benchmark5_run, benchmark5_name),
]

N: int = 11
ITERATIONS = 10

M_INITIAL: int = 1024
M_MULTIPLIER: int = 2


class ComparisonData(TypedDict):
    Function: str
    M: int
    Avg_Time_s: float
    Diff_s: float
    Relative_Speed: float


LOOPS: List[Tuple[str, Callable[[], asyncio.AbstractEventLoop]]] = [
    ("asyncio", asyncio.new_event_loop),
    ("uvloop", uvloop.new_event_loop),
    ("leviathan", leviathan.Loop),
    ("leviathan (Thread-safe)", leviathan.ThreadSafeLoop),
]


def benchmark_with_event_loops(
    loops: List[Tuple[str, Callable[[], asyncio.AbstractEventLoop]]],
    function: Callable[[asyncio.AbstractEventLoop, int], None],
) -> Dict[str, List[Tuple[int, float]]]:
    results: Dict[str, List[Tuple[int, float]]] = {}

    for loop_name, loop_creator in loops:
        results[loop_name] = []
        m: int = M_INITIAL

        print("Starting benchmark with loop:", loop_name)
        loop = loop_creator()
        try:
            while m <= M_INITIAL * (2 ** (N - 1)):
                total_time = 0.0
                for _ in range(ITERATIONS):
                    start_time: float = time.perf_counter()
                    function(loop, m)
                    end_time: float = time.perf_counter()
                    total_time += end_time - start_time

                # average_time: float = (end_time - start_time) / ITERATIONS
                average_time: float = (total_time) / ITERATIONS
                print(f"{loop_name} - {m} - {average_time:.6f} s")
                results[loop_name].append((m, average_time))

                m *= M_MULTIPLIER
        finally:
            loop.close()

        print("-" * 50)

    return results


def create_comparison_table(
    results: Dict[str, List[Tuple[int, float]]],
) -> None:
    table: PrettyTable = PrettyTable()
    table.field_names = [
        "Loop",
        "M",
        "Avg Time (s)",
        "Diff (s)",
        "Relative Speed",
    ]

    base_loop_results = results["asyncio"]
    for loop_name, loop_results in results.items():
        for i, (m, avg_time) in enumerate(loop_results):
            base_time: float = base_loop_results[i][1]
            relative_time: float = base_time / avg_time
            table.add_row(
                [
                    loop_name,
                    m,
                    f"{avg_time:.6f}",
                    f"{(avg_time - base_time):.6f}",
                    f"{relative_time:.2f}",
                ]
            )

    print(table)


def plot_results(results: Dict[str, List[Tuple[int, float]]], name: str) -> None:
    plt.figure(figsize=(10, 6))

    for loop_name, loop_results in results.items():
        x: List[int] = [m for m, _ in loop_results]
        y: List[float] = [avg_time for _, avg_time in loop_results]
        plt.plot(x, y, marker="o", label=loop_name)

    plt.xscale("log", base=2)
    plt.yscale("log")
    plt.xlabel("M (log scale)")
    plt.ylabel("Time (s, log scale)")
    plt.title(f"Benchmark Comparison Across Event Loops ({name})")
    plt.legend()
    plt.grid(True, which="both", linestyle="--", linewidth=0.5)
    plt.tight_layout()
    plt.show()


if __name__ == "__main__":
    for function, name in BENCHMARK_FUNCTIONS:
        print("Starting test for function:", name)
        benchmark_results = benchmark_with_event_loops(LOOPS, function)
        create_comparison_table(benchmark_results)
        plot_results(benchmark_results, name)
        print("-" * 50)
        print()
