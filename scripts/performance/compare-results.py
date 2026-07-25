#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import statistics
from collections import Counter
from pathlib import Path
from typing import Any


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            if not line.strip():
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError as exc:
                raise ValueError(f"{path}:{line_number}: invalid JSON: {exc}") from exc
    return rows


def timestamp(row: dict[str, Any]) -> float | None:
    for key in ("source_ts_ms", "frame_ts_ms", "timestamp_ms"):
        value = row.get(key)
        if value is not None:
            return float(value)
    return None


def detections(row: dict[str, Any]) -> list[dict[str, Any]]:
    value = row.get("detections", [])
    return value if isinstance(value, list) else []


def class_name(item: dict[str, Any]) -> str:
    return str(item.get("class", item.get("class_name", item.get("label", "unknown"))))


def confidence(item: dict[str, Any]) -> float | None:
    value = item.get("confidence", item.get("score"))
    return float(value) if value is not None else None


def signature(row: dict[str, Any]) -> Counter[str]:
    return Counter(class_name(item) for item in detections(row))


def pair_rows(
    webrtc: list[dict[str, Any]], rtsp: list[dict[str, Any]], tolerance_ms: float
) -> tuple[list[tuple[dict[str, Any], dict[str, Any]]], list[dict[str, Any]], list[dict[str, Any]]]:
    rtsp_by_id = {str(row["frame_id"]): row for row in rtsp if row.get("frame_id") is not None}
    paired: list[tuple[dict[str, Any], dict[str, Any]]] = []
    unmatched_webrtc: list[dict[str, Any]] = []
    used_rtsp: set[int] = set()

    for web_row in webrtc:
        match: dict[str, Any] | None = None
        if web_row.get("frame_id") is not None:
            candidate = rtsp_by_id.get(str(web_row["frame_id"]))
            if candidate is not None:
                candidate_index = next((index for index, row in enumerate(rtsp) if row is candidate), None)
                if candidate_index is not None and candidate_index not in used_rtsp:
                    match = candidate
                    used_rtsp.add(candidate_index)
        if match is None:
            web_ts = timestamp(web_row)
            candidates = []
            if web_ts is not None:
                for index, rtsp_row in enumerate(rtsp):
                    if index in used_rtsp:
                        continue
                    rtsp_ts = timestamp(rtsp_row)
                    if rtsp_ts is not None and abs(rtsp_ts - web_ts) <= tolerance_ms:
                        candidates.append((abs(rtsp_ts - web_ts), index, rtsp_row))
            if candidates:
                _, index, match = min(candidates, key=lambda item: item[0])
                used_rtsp.add(index)

        if match is None:
            unmatched_webrtc.append(web_row)
        else:
            paired.append((web_row, match))

    unmatched_rtsp = [row for index, row in enumerate(rtsp) if index not in used_rtsp]
    return paired, unmatched_webrtc, unmatched_rtsp


def aggregate(rows: list[dict[str, Any]]) -> dict[str, Any]:
    all_detections = [item for row in rows for item in detections(row)]
    confidences = [value for item in all_detections if (value := confidence(item)) is not None]
    classes = Counter(class_name(item) for item in all_detections)
    return {
        "frames": len(rows),
        "detections": len(all_detections),
        "average_confidence": statistics.fmean(confidences) if confidences else None,
        "class_counts": dict(sorted(classes.items())),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="WebRTCとRTSPの推論結果JSONLを相対比較する")
    parser.add_argument("--webrtc", required=True, type=Path)
    parser.add_argument("--rtsp", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--tolerance-ms", type=float, default=50.0)
    args = parser.parse_args()

    web_rows = load_jsonl(args.webrtc)
    rtsp_rows = load_jsonl(args.rtsp)
    paired, web_only, rtsp_only = pair_rows(web_rows, rtsp_rows, args.tolerance_ms)
    exact = sum(1 for web_row, rtsp_row in paired if signature(web_row) == signature(rtsp_row))

    args.out.mkdir(parents=True, exist_ok=True)
    frame_rows = []
    for web_row, rtsp_row in paired:
        web_ts = timestamp(web_row)
        rtsp_ts = timestamp(rtsp_row)
        frame_rows.append({
            "frame_id": web_row.get("frame_id", rtsp_row.get("frame_id")),
            "webrtc_source_ts_ms": web_ts,
            "rtsp_source_ts_ms": rtsp_ts,
            "timestamp_delta_ms": abs(web_ts - rtsp_ts) if web_ts is not None and rtsp_ts is not None else None,
            "webrtc_detection_count": len(detections(web_row)),
            "rtsp_detection_count": len(detections(rtsp_row)),
            "class_count_match": signature(web_row) == signature(rtsp_row),
            "webrtc_classes": dict(signature(web_row)),
            "rtsp_classes": dict(signature(rtsp_row)),
        })

    with (args.out / "frame-comparison.csv").open("w", newline="", encoding="utf-8") as handle:
        fieldnames = list(frame_rows[0].keys()) if frame_rows else [
            "frame_id", "webrtc_source_ts_ms", "rtsp_source_ts_ms", "timestamp_delta_ms",
            "webrtc_detection_count", "rtsp_detection_count", "class_count_match",
            "webrtc_classes", "rtsp_classes",
        ]
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in frame_rows:
            writer.writerow({
                **row,
                "webrtc_classes": json.dumps(row["webrtc_classes"], ensure_ascii=False),
                "rtsp_classes": json.dumps(row["rtsp_classes"], ensure_ascii=False),
            })

    summary = {
        "matching": {
            "tolerance_ms": args.tolerance_ms,
            "paired_frames": len(paired),
            "class_count_matched_frames": exact,
            "class_count_match_ratio": exact / len(paired) if paired else None,
            "webrtc_only_frames": len(web_only),
            "rtsp_only_frames": len(rtsp_only),
        },
        "webrtc": aggregate(web_rows),
        "rtsp": aggregate(rtsp_rows),
        "interpretation": "正解率ではなく、同一入力に対する配信方式間の相対差を示す。",
    }
    (args.out / "comparison-summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    classes = sorted(set(summary["webrtc"]["class_counts"]) | set(summary["rtsp"]["class_counts"]))
    with (args.out / "class-counts.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["class", "webrtc_count", "rtsp_count", "difference"])
        for name in classes:
            web_count = summary["webrtc"]["class_counts"].get(name, 0)
            rtsp_count = summary["rtsp"]["class_counts"].get(name, 0)
            writer.writerow([name, web_count, rtsp_count, web_count - rtsp_count])

    print(args.out / "comparison-summary.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
