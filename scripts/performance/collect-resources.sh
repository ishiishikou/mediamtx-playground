#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${1:?output directory is required}"
DURATION="${2:-60}"
INTERVAL="${3:-5}"
MTX_METRICS_URL="${MTX_METRICS_URL:-http://127.0.0.1:9998/metrics}"
PROMETHEUS_URL="${PROMETHEUS_URL:-}"

mkdir -p "${OUTPUT_DIR}/metrics"
HOST_CSV="${OUTPUT_DIR}/resource-samples.csv"
printf 'timestamp_ms,load1,mem_available_kb,gpu_util_percent,gpu_memory_used_mb,gpu_memory_total_mb,mediamtx_cpu_cores,mediamtx_memory_bytes,mediamtx_network_receive_bps,mediamtx_network_transmit_bps\n' > "${HOST_CSV}"

prom_query() {
  local query="$1"
  [[ -n "${PROMETHEUS_URL}" ]] || return 0
  curl -fsSG --connect-timeout 1 --max-time 2 "${PROMETHEUS_URL}/api/v1/query" \
    --data-urlencode "query=${query}" 2>/dev/null \
    | jq -r '.data.result[0].value[1] // empty' 2>/dev/null \
    || true
}

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

  mediamtx_cpu=$(prom_query 'sum(rate(container_cpu_usage_seconds_total{container_label_com_docker_compose_service="mediamtx"}[1m]))')
  mediamtx_memory=$(prom_query 'sum(container_memory_working_set_bytes{container_label_com_docker_compose_service="mediamtx"})')
  mediamtx_rx=$(prom_query 'sum(rate(container_network_receive_bytes_total{container_label_com_docker_compose_service="mediamtx"}[1m]))')
  mediamtx_tx=$(prom_query 'sum(rate(container_network_transmit_bytes_total{container_label_com_docker_compose_service="mediamtx"}[1m]))')

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "${ts_ms}" "${load1}" "${mem_available}" \
    "${gpu_util}" "${gpu_mem_used}" "${gpu_mem_total}" \
    "${mediamtx_cpu}" "${mediamtx_memory}" "${mediamtx_rx}" "${mediamtx_tx}" >> "${HOST_CSV}"

  curl -fsS --connect-timeout 1 --max-time 2 "${MTX_METRICS_URL}" > "${OUTPUT_DIR}/metrics/${ts_ms}.prom" 2>/dev/null || true
  sleep "${INTERVAL}"
done
