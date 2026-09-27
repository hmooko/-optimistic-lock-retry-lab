#!/usr/bin/env python3
"""Aggregate structured k6 benchmark outputs into paper-ready CSV files."""

from __future__ import annotations

import argparse
import csv
import glob
import json
import statistics
from collections import defaultdict
from pathlib import Path
from typing import Iterable

STRATEGY_ORDER = {
    "PESSIMISTIC": 0,
    "OPT_IMMEDIATE": 1,
    "OPT_FIXED": 2,
    "OPT_FIXED_JITTER": 3,
    "OPT_EXPONENTIAL": 4,
    "OPT_EXPONENTIAL_JITTER": 5,
}

HOT_SET_ORDER = {100: 0, 20: 1, 5: 2, 1: 3}

CONTENTION_LABEL = {
    100: "Low",
    20: "Medium",
    5: "High",
    1: "Extreme",
}

METRICS = (
    "throughputPerSecond",
    "p99LatencyMs",
    "retryAmplification",
    "failureRate",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--input-glob",
        default="results/*_run*.json",
        help="Glob for structured benchmark JSON files.",
    )
    parser.add_argument(
        "--runs-output",
        default="results/runs.csv",
        help="Per-run CSV output path.",
    )
    parser.add_argument(
        "--summary-output",
        default="results/summary.csv",
        help="Grouped summary CSV output path.",
    )
    return parser.parse_args()


def load_runs(pattern: str) -> list[dict]:
    files = [Path(path) for path in glob.glob(pattern)]
    if not files:
        raise SystemExit(f"no benchmark files matched: {pattern}")

    rows = []
    for path in files:
        with path.open(encoding="utf-8") as handle:
            payload = json.load(handle)

        metadata = payload.get("metadata", {})
        metrics = payload.get("metrics", {})

        required_metadata = (
            "strategy",
            "hotSet",
            "rate",
            "durationSeconds",
            "repetition",
        )
        required_metrics = (
            "successCount",
            "failureCount",
            "retryCount",
            "throughputPerSecond",
            "p99LatencyMs",
            "retryAmplification",
            "failureRate",
            "droppedIterations",
        )

        missing = [
            key
            for key in required_metadata
            if metadata.get(key) is None
        ] + [
            key
            for key in required_metrics
            if metrics.get(key) is None
        ]

        if missing:
            raise SystemExit(f"{path}: missing values: {', '.join(missing)}")

        hot_set = int(metadata["hotSet"])
        row = {
            "source": str(path),
            "strategy": metadata["strategy"],
            "hotSet": hot_set,
            "contention": CONTENTION_LABEL.get(hot_set, f"hot-{hot_set}"),
            "rate": float(metadata["rate"]),
            "warmup": metadata.get("warmup", ""),
            "duration": metadata.get("duration", ""),
            "durationSeconds": float(metadata["durationSeconds"]),
            "repetition": int(metadata["repetition"]),
            "successCount": float(metrics["successCount"]),
            "failureCount": float(metrics["failureCount"]),
            "retryCount": float(metrics["retryCount"]),
            "throughputPerSecond": float(metrics["throughputPerSecond"]),
            "p99LatencyMs": float(metrics["p99LatencyMs"]),
            "retryAmplification": float(metrics["retryAmplification"]),
            "failureRate": float(metrics["failureRate"]),
            "droppedIterations": float(metrics["droppedIterations"]),
        }
        rows.append(row)

    return sorted(rows, key=run_sort_key)


def run_sort_key(row: dict) -> tuple:
    return (
        STRATEGY_ORDER.get(row["strategy"], 999),
        HOT_SET_ORDER.get(row["hotSet"], 999),
        row["hotSet"],
        row["repetition"],
    )


def write_runs(rows: list[dict], output_path: str) -> None:
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)

    fieldnames = list(rows[0].keys())
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def five_number_stats(values: Iterable[float]) -> dict[str, float]:
    values = list(values)
    if not values:
        raise ValueError("values must not be empty")

    if len(values) == 1:
        q1 = q3 = values[0]
        stdev = 0.0
    else:
        q1, _, q3 = statistics.quantiles(values, n=4, method="inclusive")
        stdev = statistics.stdev(values)

    return {
        "median": statistics.median(values),
        "mean": statistics.mean(values),
        "stdev": stdev,
        "q1": q1,
        "q3": q3,
    }


def summarize(rows: list[dict]) -> list[dict]:
    grouped: dict[tuple, list[dict]] = defaultdict(list)

    for row in rows:
        key = (
            row["strategy"],
            row["hotSet"],
            row["rate"],
            row["durationSeconds"],
        )
        grouped[key].append(row)

    summaries = []

    for (strategy, hot_set, rate, duration_seconds), group in grouped.items():
        summary = {
            "strategy": strategy,
            "hotSet": hot_set,
            "contention": CONTENTION_LABEL.get(hot_set, f"hot-{hot_set}"),
            "rate": rate,
            "durationSeconds": duration_seconds,
            "n": len(group),
            "droppedIterationsTotal": sum(
                row["droppedIterations"] for row in group
            ),
        }

        for metric in METRICS:
            stats = five_number_stats(row[metric] for row in group)
            for stat_name, value in stats.items():
                summary[f"{metric}_{stat_name}"] = value

        summaries.append(summary)

    return sorted(
        summaries,
        key=lambda row: (
            STRATEGY_ORDER.get(row["strategy"], 999),
            HOT_SET_ORDER.get(row["hotSet"], 999),
            row["hotSet"],
        ),
    )


def write_summary(rows: list[dict], output_path: str) -> None:
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)

    fieldnames = list(rows[0].keys())
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    args = parse_args()
    runs = load_runs(args.input_glob)
    summary = summarize(runs)

    write_runs(runs, args.runs_output)
    write_summary(summary, args.summary_output)

    print(
        f"aggregated {len(runs)} runs into {len(summary)} groups: "
        f"{args.runs_output}, {args.summary_output}"
    )


if __name__ == "__main__":
    main()
