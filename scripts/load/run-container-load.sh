#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${LOAD_OUTPUT_DIR:-/workspace/tmp/load-test/container}"
PROMETHEUS_URL="${PROMETHEUS_URL:-}"
PROMETHEUS_QUERIES_FILE="${PROMETHEUS_QUERIES_FILE:-/workspace/monitoring/prometheus/load-test-queries.json}"
PROMETHEUS_LOOKBACK_SECONDS="${PROMETHEUS_LOOKBACK_SECONDS:-3600}"
PROMETHEUS_STEP="${PROMETHEUS_STEP:-5}"

bash scripts/load/run-load-matrix.sh
python3 scripts/load/render-load-graphs.py "${OUTPUT_DIR}"

if [[ -n "${PROMETHEUS_URL}" ]]; then
  python3 scripts/load/export-prometheus-range.py \
    --prometheus-url "${PROMETHEUS_URL}" \
    --queries-file "${PROMETHEUS_QUERIES_FILE}" \
    --out "${OUTPUT_DIR}/prometheus" \
    --lookback-seconds "${PROMETHEUS_LOOKBACK_SECONDS}" \
    --step "${PROMETHEUS_STEP}"
else
  echo "PROMETHEUS_URL is not set. Skipping Prometheus range export." >&2
fi
