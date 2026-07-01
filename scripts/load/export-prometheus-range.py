#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

import matplotlib.pyplot as plt


def http_json(url: str, params: dict[str, str]) -> dict[str, Any]:
    full_url = f"{url}?{urllib.parse.urlencode(params)}"
    with urllib.request.urlopen(full_url, timeout=15) as response:
        return json.loads(response.read().decode("utf-8"))


def load_queries(path: Path) -> list[dict[str, str]]:
    with path.open() as f:
        data = json.load(f)
    if not isinstance(data, list):
        raise ValueError("query file must contain a list")
    return data


def query_range(prometheus_url: str, query: str, start: int, end: int, step: str) -> list[tuple[float, float]]:
    payload = http_json(
        f"{prometheus_url.rstrip('/')}/api/v1/query_range",
        {
            "query": query,
            "start": str(start),
            "end": str(end),
            "step": step,
        },
    )
    if payload.get("status") != "success":
        raise RuntimeError(json.dumps(payload, ensure_ascii=False))

    points: list[tuple[float, float]] = []
    for result in payload.get("data", {}).get("result", []):
        for ts, value in result.get("values", []):
            try:
                points.append((float(ts), float(value)))
            except (TypeError, ValueError):
                continue
    points.sort(key=lambda item: item[0])
    return points


def write_csv(path: Path, points: list[tuple[float, float]]) -> None:
    with path.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp_epoch", "elapsed_sec", "value"])
        if not points:
            return
        first_ts = points[0][0]
        for ts, value in points:
            writer.writerow([int(ts), round(ts - first_ts, 3), value])


def scale_values(unit: str, values: list[float]) -> tuple[str, list[float]]:
    if unit == "bytes":
        return "MiB", [value / 1024 / 1024 for value in values]
    if unit == "bytes_per_second":
        return "MiB/s", [value / 1024 / 1024 for value in values]
    return unit or "value", values


def write_graph(path: Path, name: str, unit: str, points: list[tuple[float, float]]) -> None:
    if not points:
        return
    first_ts = points[0][0]
    x_values = [(ts - first_ts) for ts, _ in points]
    raw_values = [value for _, value in points]
    y_label, y_values = scale_values(unit, raw_values)

    plt.figure(figsize=(12, 6))
    plt.plot(x_values, y_values)
    plt.title(name)
    plt.xlabel("Elapsed seconds")
    plt.ylabel(y_label)
    plt.tight_layout()
    plt.savefig(path)
    plt.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Export Prometheus query_range results to CSV and PNG")
    parser.add_argument("--prometheus-url", default="http://prometheus:9090")
    parser.add_argument("--queries-file", type=Path, default=Path("monitoring/prometheus/load-test-queries.json"))
    parser.add_argument("--out", type=Path, default=Path("tmp/load-test/prometheus"))
    parser.add_argument("--lookback-seconds", type=int, default=3600)
    parser.add_argument("--step", default="5")
    parser.add_argument("--start", type=int, default=None)
    parser.add_argument("--end", type=int, default=None)
    args = parser.parse_args()

    end = args.end or int(time.time())
    start = args.start or (end - args.lookback_seconds)

    queries = load_queries(args.queries_file)
    csv_dir = args.out / "csv"
    graph_dir = args.out / "graphs"
    csv_dir.mkdir(parents=True, exist_ok=True)
    graph_dir.mkdir(parents=True, exist_ok=True)

    summary_rows: list[dict[str, Any]] = []
    for item in queries:
        name = item["name"]
        query = item["query"]
        unit = item.get("unit", "")
        print(f"query: {name}")
        try:
            points = query_range(args.prometheus_url, query, start, end, args.step)
        except Exception as exc:  # noqa: BLE001
            print(f"skip {name}: {exc}")
            points = []

        write_csv(csv_dir / f"{name}.csv", points)
        write_graph(graph_dir / f"{name}.png", name, unit, points)
        summary_rows.append({
            "name": name,
            "query": query,
            "unit": unit,
            "points": len(points),
            "min": min((value for _, value in points), default=""),
            "max": max((value for _, value in points), default=""),
        })

    with (args.out / "summary.csv").open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["name", "query", "unit", "points", "min", "max"])
        writer.writeheader()
        writer.writerows(summary_rows)

    print(f"prometheus export written to: {args.out}")


if __name__ == "__main__":
    main()
