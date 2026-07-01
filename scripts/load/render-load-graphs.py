#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path

import matplotlib.pyplot as plt

UNITS = {"B": 1, "kB": 1000, "KB": 1000, "KiB": 1024, "MB": 1000**2, "MiB": 1024**2, "GB": 1000**3, "GiB": 1024**3}
PROM_RE = re.compile(r"^([a-zA-Z_:][a-zA-Z0-9_:]*)(?:\{[^}]*\})?\s+([-+0-9.eE]+)$")


def number(value: str | None) -> float:
    if not value:
        return 0.0
    try:
        return float(value.strip().replace("%", ""))
    except ValueError:
        return 0.0


def mem_bytes(value: str) -> float:
    first = (value or "").split("/")[0].strip()
    match = re.match(r"^([0-9.]+)\s*([A-Za-z]+)$", first)
    if not match:
        return 0.0
    return float(match.group(1)) * UNITS.get(match.group(2), 1)


def read_meta(case_dir: Path) -> dict:
    path = case_dir / "case.json"
    if not path.exists():
        return {"case_id": case_dir.name}
    return json.loads(path.read_text())


def label(meta: dict) -> str:
    return f"{meta.get('publisher','?')}/{meta.get('profile','?')}/{meta.get('mode','?')}/{meta.get('streams','?')}s/{meta.get('readers_per_stream','?')}r/r{meta.get('repeat','?')}"


def read_samples(case_dir: Path) -> list[dict]:
    path = case_dir / "samples.csv"
    if not path.exists():
        return []
    rows = []
    with path.open(newline="") as f:
        for row in csv.DictReader(f):
            row["elapsed_sec"] = number(row.get("elapsed_sec"))
            row["active_paths"] = number(row.get("active_paths"))
            row["rtsp_sessions"] = number(row.get("rtsp_sessions"))
            row["webrtc_sessions"] = number(row.get("webrtc_sessions"))
            row["docker_cpu_percent"] = number(row.get("docker_cpu_percent"))
            row["docker_mem_bytes"] = mem_bytes(row.get("docker_mem_usage", ""))
            rows.append(row)
    return rows


def parse_prom(path: Path) -> dict[str, float]:
    values: dict[str, float] = {}
    for line in path.read_text(errors="replace").splitlines():
        if not line or line.startswith("#"):
            continue
        match = PROM_RE.match(line)
        if not match:
            continue
        name, raw = match.groups()
        try:
            values[name] = values.get(name, 0.0) + float(raw)
        except ValueError:
            pass
    return values


def prom_delta(case_dir: Path) -> tuple[str, float, float]:
    files = sorted(case_dir.glob("metrics-*.prom"))
    if len(files) < 2:
        return "", 0.0, 0.0
    first = parse_prom(files[0])
    last = parse_prom(files[-1])
    deltas = {name: value - first.get(name, 0.0) for name, value in last.items()}
    deltas = {name: value for name, value in deltas.items() if value > 0}
    if not deltas:
        return "", 0.0, 0.0
    top_name, top_value = max(deltas.items(), key=lambda item: item[1])
    selected = sum(value for name, value in deltas.items() if any(token in name.lower() for token in ["byte", "packet", "frame", "session", "path"]))
    return top_name, top_value, selected


def summarize(input_dir: Path) -> list[dict]:
    out = []
    for case_dir in sorted((input_dir / "cases").glob("*")):
        if not case_dir.is_dir():
            continue
        meta = read_meta(case_dir)
        samples = read_samples(case_dir)
        if not samples:
            continue
        top_metric, top_delta, selected_delta = prom_delta(case_dir)
        out.append({
            **meta,
            "label": label(meta),
            "sample_count": len(samples),
            "max_cpu_percent": max(row["docker_cpu_percent"] for row in samples),
            "max_mem_bytes": max(row["docker_mem_bytes"] for row in samples),
            "max_active_paths": max(row["active_paths"] for row in samples),
            "max_rtsp_sessions": max(row["rtsp_sessions"] for row in samples),
            "max_webrtc_sessions": max(row["webrtc_sessions"] for row in samples),
            "top_prometheus_metric": top_metric,
            "top_prometheus_delta": top_delta,
            "selected_prometheus_delta": selected_delta,
        })
    return out


def write_csv(rows: list[dict], path: Path) -> None:
    keys = ["case_id", "publisher", "profile", "mode", "streams", "readers_per_stream", "repeat", "sample_count", "max_cpu_percent", "max_mem_bytes", "max_active_paths", "max_rtsp_sessions", "max_webrtc_sessions", "top_prometheus_metric", "top_prometheus_delta", "selected_prometheus_delta"]
    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=keys)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row.get(key, "") for key in keys})


def bar(rows: list[dict], key: str, title: str, xlabel: str, path: Path, scale: float = 1.0) -> None:
    labels = [row["label"] for row in rows]
    values = [float(row.get(key, 0.0)) / scale for row in rows]
    plt.figure(figsize=(12, max(5, 0.35 * len(rows) + 2)))
    plt.barh(labels, values)
    plt.title(title)
    plt.xlabel(xlabel)
    plt.tight_layout()
    plt.savefig(path)
    plt.close()


def cpu_time(input_dir: Path, path: Path) -> None:
    plt.figure(figsize=(12, 7))
    plotted = False
    for case_dir in sorted((input_dir / "cases").glob("*")):
        meta = read_meta(case_dir)
        samples = read_samples(case_dir)
        if not samples:
            continue
        plt.plot([r["elapsed_sec"] for r in samples], [r["docker_cpu_percent"] for r in samples], label=label(meta))
        plotted = True
    if plotted:
        plt.title("MediaMTX CPU over time")
        plt.xlabel("Elapsed seconds")
        plt.ylabel("CPU percent")
        plt.legend(fontsize="small")
        plt.tight_layout()
        plt.savefig(path)
    plt.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_dir", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    out_dir = args.out or args.input_dir / "graphs"
    out_dir.mkdir(parents=True, exist_ok=True)
    rows = summarize(args.input_dir)
    if not rows:
        raise SystemExit(f"no samples found: {args.input_dir}")
    rows.sort(key=lambda row: (str(row.get("profile")), str(row.get("mode")), int(row.get("streams", 0))))
    write_csv(rows, out_dir / "summary.csv")
    bar(rows, "max_cpu_percent", "Peak MediaMTX CPU by case", "CPU percent", out_dir / "peak_cpu_by_case.png")
    bar(rows, "max_mem_bytes", "Peak MediaMTX memory by case", "MiB", out_dir / "peak_memory_by_case.png", 1024 * 1024)
    bar(rows, "max_active_paths", "Peak active paths by case", "Active paths", out_dir / "peak_active_paths_by_case.png")
    bar(rows, "max_rtsp_sessions", "Peak RTSP sessions by case", "RTSP sessions", out_dir / "peak_rtsp_sessions_by_case.png")
    bar(rows, "selected_prometheus_delta", "Selected Prometheus metric deltas by case", "Delta sum", out_dir / "prometheus_selected_deltas_by_case.png")
    cpu_time(args.input_dir, out_dir / "cpu_over_time.png")
    print(f"graphs written to: {out_dir}")


if __name__ == "__main__":
    main()
