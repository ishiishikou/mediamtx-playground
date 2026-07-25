#!/usr/bin/env python3
from __future__ import annotations

import csv
import json
import math
import statistics
import sys
from pathlib import Path
from typing import Iterable


def percentile(values: list[float], p: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    index = (len(ordered) - 1) * p
    low = math.floor(index)
    high = math.ceil(index)
    if low == high:
        return ordered[low]
    return ordered[low] + (ordered[high] - ordered[low]) * (index - low)


def numeric(value: str | None) -> float | None:
    if value in (None, ""):
        return None
    try:
        return float(value)
    except ValueError:
        return None


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def summarize_latency(rows: Iterable[dict[str, str]]) -> dict[str, float | int | None]:
    e2e: list[float] = []
    inference: list[float] = []
    result_return: list[float] = []
    for row in rows:
        source = numeric(row.get("source_ts_ms"))
        render = numeric(row.get("browser_render_ts_ms"))
        infer_start = numeric(row.get("inference_start_ts_ms"))
        infer_end = numeric(row.get("inference_end_ts_ms"))
        result_send = numeric(row.get("result_send_ts_ms"))
        receive = numeric(row.get("browser_receive_ts_ms"))
        if source is not None and render is not None and render >= source:
            e2e.append(render - source)
        if infer_start is not None and infer_end is not None and infer_end >= infer_start:
            inference.append(infer_end - infer_start)
        if result_send is not None and receive is not None and receive >= result_send:
            result_return.append(receive - result_send)

    return {
        "latency_samples": len(e2e),
        "e2e_latency_min_ms": min(e2e) if e2e else None,
        "e2e_latency_median_ms": statistics.median(e2e) if e2e else None,
        "e2e_latency_p95_ms": percentile(e2e, 0.95),
        "e2e_latency_max_ms": max(e2e) if e2e else None,
        "inference_median_ms": statistics.median(inference) if inference else None,
        "result_return_median_ms": statistics.median(result_return) if result_return else None,
    }


def summarize_case(case_dir: Path) -> dict[str, object]:
    case = json.loads((case_dir / "case.json").read_text(encoding="utf-8"))
    stats = read_csv(case_dir / "webrtc-stats.csv")
    results = read_csv(case_dir / "result-events.csv")
    publisher_events = read_csv(case_dir / "publisher-events.csv")
    fps_values = [value for row in stats if (value := numeric(row.get("frames_per_second"))) is not None]

    requested = int(case.get("clients", 0))
    successful = 0
    if case.get("protocol") == "webrtc":
        summary_path = case_dir / "webrtc-summary.json"
        if summary_path.exists():
            successful = int(json.loads(summary_path.read_text(encoding="utf-8")).get("connected_clients", 0))
    elif case.get("protocol") == "rtsp":
        successful = sum(1 for row in publisher_events if row.get("status") == "completed")

    row: dict[str, object] = {
        "case_id": case.get("case_id"),
        "scenario_id": case.get("scenario_id"),
        "protocol": case.get("protocol"),
        "clients": requested,
        "duration_seconds": case.get("duration_seconds"),
        "repeat": case.get("repeat"),
        "status": case.get("status"),
        "exit_code": case.get("exit_code"),
        "successful_clients": successful,
        "client_success_rate": successful / requested if requested else None,
        "stats_samples": len(stats),
        "result_events": len(results),
        "browser_fps_median": statistics.median(fps_values) if fps_values else None,
        "browser_fps_p95": percentile(fps_values, 0.95),
    }
    row.update(summarize_latency(results))
    return row


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def render_graphs(graph_dir: Path, rows: list[dict[str, object]]) -> None:
    try:
        import matplotlib.pyplot as plt
    except ImportError:
        return

    graph_dir.mkdir(parents=True, exist_ok=True)
    labels = [str(row["case_id"]) for row in rows]

    def bar(name: str, field: str, ylabel: str) -> None:
        values = [row.get(field) for row in rows]
        if not any(value is not None for value in values):
            return
        numeric_values = [float(value) if value is not None else 0.0 for value in values]
        fig = plt.figure(figsize=(max(8, len(rows) * 0.8), 5))
        plt.bar(labels, numeric_values)
        plt.ylabel(ylabel)
        plt.xticks(rotation=60, ha="right")
        plt.tight_layout()
        fig.savefig(graph_dir / name, dpi=150)
        plt.close(fig)

    bar("e2e_latency_p95_by_case.png", "e2e_latency_p95_ms", "E2E latency p95 (ms)")
    bar("browser_fps_median_by_case.png", "browser_fps_median", "Browser outbound FPS median")
    bar("client_success_rate_by_case.png", "client_success_rate", "Client success rate")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: summarize-results.py <run-dir>", file=sys.stderr)
        return 2
    run_dir = Path(sys.argv[1])
    case_dirs = sorted((run_dir / "cases").glob("*")) if (run_dir / "cases").exists() else []
    rows = [summarize_case(case_dir) for case_dir in case_dirs if (case_dir / "case.json").exists()]
    summary_dir = run_dir / "summary"
    summary_dir.mkdir(parents=True, exist_ok=True)
    write_csv(summary_dir / "summary.csv", rows)
    (summary_dir / "summary.json").write_text(json.dumps(rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    render_graphs(summary_dir / "graphs", rows)
    print(summary_dir / "summary.csv")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
