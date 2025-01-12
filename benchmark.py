from typing import Callable, List, Tuple, Dict, TypedDict
from prettytable import PrettyTable

import uvloop, asyncio, time, leviathan
import matplotlib.pyplot as plt

from benchmarks.producer_consumer import (
    run as benchmark1_run,
    BENCHMARK_NAME as benchmark1_name,
)
# from benchmark2 import run as benchmark2_run, BENCHMARK_NAME as benchmark2_name
# from benchmark3 import run as benchmark3_run, BENCHMARK_NAME as benchmark3_name

BENCHMARK_FUNCTIONS: List[
    Tuple[Callable[[asyncio.AbstractEventLoop, int], None], str]
] = [
    (benchmark1_run, benchmark1_name),
    # (benchmark2_run, benchmark2_name),
    # (benchmark3_run, benchmark3_name)
]

N: int = 1
ITERATIONS = 10

M_INITIAL: int = 64 * 2 ** 10
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
    functions: List[Tuple[Callable[[asyncio.AbstractEventLoop, int], None], str]],
) -> Dict[str, Dict[str, List[Tuple[int, float]]]]:
    results: Dict[str, Dict[str, List[Tuple[int, float]]]] = {}

    for loop_name, loop_creator in loops:
        results[loop_name] = {name: [] for _, name in functions}
        m: int = M_INITIAL

        print("Starting benchmark with loop:", loop_name)
        loop = loop_creator()
        try:
            while m <= M_INITIAL * (2 ** (N - 1)):
                for func, name in functions:
                    total_time = 0.0
                    for _ in range(ITERATIONS):
                        start_time: float = time.perf_counter()
                        func(loop, m)
                        end_time: float = time.perf_counter()
                        print((end_time - start_time))
                        total_time += (end_time - start_time)

                    # average_time: float = (end_time - start_time) / ITERATIONS
                    average_time: float = (total_time) / ITERATIONS
                    print(f"{loop_name} - {name} - {m} - {average_time:.6f} s")
                    results[loop_name][name].append((m, average_time))

                m *= M_MULTIPLIER
        finally:
            loop.close()

        print("-" * 50)

    return results


def create_comparison_table(
    results: Dict[str, Dict[str, List[Tuple[int, float]]]],
) -> None:
    table: PrettyTable = PrettyTable()
    table.field_names = [
        "Loop",
        "Test",
        "M",
        "Avg Time (s)",
        "Diff (s)",
        "Relative Speed",
    ]

    base_loop_results = results["asyncio"]

    for loop_name, loop_results in results.items():
        for func_name, times in loop_results.items():
            base_times = base_loop_results[func_name]
            for i, (m, avg_time) in enumerate(times):
                base_time: float = base_times[i][1]
                relative_time: float = (
                    base_time / avg_time
                )
                table.add_row(
                    [
                        loop_name,
                        func_name,
                        m,
                        f"{avg_time:.6f}",
                        f"{(avg_time - base_time):.6f}",
                        f"{relative_time:.2f}",
                    ]
                )

    print(table)


def plot_results(results: Dict[str, Dict[str, List[Tuple[int, float]]]]) -> None:
    plt.figure(figsize=(10, 6))

    for loop_name, loop_results in results.items():
        for func_name, times in loop_results.items():
            x: List[int] = [m for m, _ in times]
            y: List[float] = [avg_time for _, avg_time in times]
            plt.plot(x, y, marker="o", label=f"{loop_name} - {func_name}")

    plt.xscale("log", base=2)
    plt.yscale("log")
    plt.xlabel("M (log scale)")
    plt.ylabel("Time (s, log scale)")
    plt.title("Benchmark Comparison Across Event Loops")
    plt.legend()
    plt.grid(True, which="both", linestyle="--", linewidth=0.5)
    plt.tight_layout()
    plt.show()


if __name__ == "__main__":
    benchmark_results = benchmark_with_event_loops(LOOPS, BENCHMARK_FUNCTIONS)
    create_comparison_table(benchmark_results)
    plot_results(benchmark_results)
