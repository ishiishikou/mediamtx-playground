#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${1:?output directory is required}"
DURATION="${2:-60}"
INTERVAL="${3:-5}"
MTX_METRICS_URL="${MTX_METRICS_URL:-http://127.0.0.1:9998/metrics}"

mkdir -p "${OUTPUT_DIR}/metrics"
HOST_CSV="${OUTPUT_DIR}/resource-samples.csv"
printf 'timestamp_ms,load1,mem_available_kb,gpu_util_percent,gpu_memory_used_mb,gpu_memory_total_mb\n' > "${HOST_CSV}"

started=$(date +%s)
while (( $(date +%s) - started < DURATION )); do
  ts_ms=$(date +%s%3N)
  load1=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo '')
  mem_available=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo '')
  gpu_util=""
  gpu_mem_used=""
  gpu_mem_total=""

  if command -v nvidia-smi >/dev/null 2>&1; then
    IFS=',' read -r gpu_util gpu_mem_used gpu_mem_total < <(
      nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total \
        --format=csv,noheader,nounits 2>/dev/null | head -n 1 | tr -d ' '
    ) || true
  fi

  printf '%s,%s,%s,%s,%s,%s\n' \
    "${ts_ms}" "${load1}" "${mem_available}" \
    "${gpu_util}" "${gpu_mem_used}" "${gpu_mem_total}" >> "${HOST_CSV}"

  curl -fsS "${MTX_METRICS_URL}" > "${OUTPUT_DIR}/metrics/${ts_ms}.prom" 2>/dev/null || true
  sleep "${INTERVAL}"
done
