#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${1:?output directory is required}"
DURATION="${2:-60}"
INTERVAL="${3:-5}"
MTX_METRICS_URL="${MTX_METRICS_URL:-http://127.0.0.1:9998/metrics}"
PROMETHEUS_URL="${PROMETHEUS_URL:-}"
RESOURCE_BACKEND="${PERF_RESOURCE_BACKEND:-auto}"
DOCKER_SOCKET="${DOCKER_SOCKET:-/var/run/docker.sock}"
DOCKER_CONTAINER="${DOCKER_CONTAINER:-mediamtx-poc}"

mkdir -p "${OUTPUT_DIR}/metrics"
HOST_CSV="${OUTPUT_DIR}/resource-samples.csv"
printf 'timestamp_ms,load1,mem_available_kb,gpu_util_percent,gpu_memory_used_mb,gpu_memory_total_mb,mediamtx_cpu_cores,mediamtx_memory_bytes,mediamtx_network_receive_bps,mediamtx_network_transmit_bps\n' > "${HOST_CSV}"

case "${RESOURCE_BACKEND}" in
  auto|cadvisor|docker) ;;
  *)
    echo "unsupported PERF_RESOURCE_BACKEND: ${RESOURCE_BACKEND} (expected auto, cadvisor, or docker)" >&2
    exit 2
    ;;
esac

PROMETHEUS_READY=0
if [[ -n "${PROMETHEUS_URL}" ]] && curl -fsS --connect-timeout 1 --max-time 2 "${PROMETHEUS_URL}/-/ready" >/dev/null 2>&1; then
  PROMETHEUS_READY=1
fi

prom_query() {
  local query="$1"
  [[ "${PROMETHEUS_READY}" -eq 1 ]] || return 0
  curl -fsSG --connect-timeout 1 --max-time 2 "${PROMETHEUS_URL}/api/v1/query" \
    --data-urlencode "query=${query}" 2>/dev/null \
    | jq -r '.data.result[0].value[1] // empty' 2>/dev/null \
    || true
}

cadvisor_available() {
  local count
  count=$(prom_query 'count(container_memory_working_set_bytes{container_label_com_docker_compose_service="mediamtx"})')
  [[ -n "${count}" ]] && awk -v value="${count}" 'BEGIN { exit !(value > 0) }'
}

docker_available() {
  [[ -S "${DOCKER_SOCKET}" ]] || return 1
  curl -fsS --connect-timeout 1 --max-time 2 \
    --unix-socket "${DOCKER_SOCKET}" \
    "http://localhost/containers/${DOCKER_CONTAINER}/json" >/dev/null 2>&1
}

ACTIVE_BACKEND="none"
case "${RESOURCE_BACKEND}" in
  cadvisor)
    ACTIVE_BACKEND="cadvisor"
    if ! cadvisor_available; then
      echo "cAdvisor metrics are unavailable; MediaMTX container resource columns will remain empty" >&2
    fi
    ;;
  docker)
    ACTIVE_BACKEND="docker"
    if ! docker_available; then
      echo "Docker Engine stats are unavailable; MediaMTX container resource columns will remain empty" >&2
    fi
    ;;
  auto)
    if cadvisor_available; then
      ACTIVE_BACKEND="cadvisor"
    elif docker_available; then
      ACTIVE_BACKEND="docker"
    else
      echo "Neither cAdvisor metrics nor Docker Engine stats are available; MediaMTX container resource columns will remain empty" >&2
    fi
    ;;
esac

cat > "${OUTPUT_DIR}/resource-backend.txt" <<EOF_BACKEND
requested=${RESOURCE_BACKEND}
selected=${ACTIVE_BACKEND}
EOF_BACKEND

echo "resource backend: requested=${RESOURCE_BACKEND} selected=${ACTIVE_BACKEND}" >&2

prev_docker_ts_ms=""
prev_docker_rx=""
prev_docker_tx=""

sample_docker_resources() {
  local ts_ms="$1"
  local stats parsed cpu memory rx_total tx_total delta_ms

  mediamtx_cpu=""
  mediamtx_memory=""
  mediamtx_rx=""
  mediamtx_tx=""

  stats=$(curl -fsS --connect-timeout 1 --max-time 3 \
    --unix-socket "${DOCKER_SOCKET}" \
    "http://localhost/containers/${DOCKER_CONTAINER}/stats?stream=false" 2>/dev/null) || return 0

  parsed=$(jq -r '
    (.cpu_stats.cpu_usage.total_usage // 0) as $cpu_now
    | (.precpu_stats.cpu_usage.total_usage // 0) as $cpu_prev
    | (.cpu_stats.system_cpu_usage // 0) as $sys_now
    | (.precpu_stats.system_cpu_usage // 0) as $sys_prev
    | (.cpu_stats.online_cpus // ((.cpu_stats.cpu_usage.percpu_usage // []) | length)) as $online_raw
    | (if (($online_raw // 0) > 0) then $online_raw else 1 end) as $online
    | ($cpu_now - $cpu_prev) as $cpu_delta
    | ($sys_now - $sys_prev) as $sys_delta
    | (if ($cpu_delta >= 0 and $sys_delta > 0) then (($cpu_delta / $sys_delta) * $online) else null end) as $cpu_cores
    | (.memory_stats.usage // 0) as $memory_usage
    | (.memory_stats.stats.inactive_file // .memory_stats.stats.total_inactive_file // 0) as $inactive_file
    | (if ($memory_usage - $inactive_file) > 0 then ($memory_usage - $inactive_file) else 0 end) as $working_set
    | (([.networks[]?.rx_bytes // 0] | add) // 0) as $rx
    | (([.networks[]?.tx_bytes // 0] | add) // 0) as $tx
    | [$cpu_cores, $working_set, $rx, $tx]
    | @tsv
  ' <<<"${stats}" 2>/dev/null) || return 0

  IFS=$'\t' read -r cpu memory rx_total tx_total <<<"${parsed}"
  mediamtx_cpu="${cpu}"
  mediamtx_memory="${memory}"

  if [[ -n "${prev_docker_ts_ms}" && -n "${prev_docker_rx}" && -n "${prev_docker_tx}" ]]; then
    delta_ms=$(( ts_ms - prev_docker_ts_ms ))
    if (( delta_ms > 0 )) && (( rx_total >= prev_docker_rx )) && (( tx_total >= prev_docker_tx )); then
      mediamtx_rx=$(awk -v now="${rx_total}" -v prev="${prev_docker_rx}" -v ms="${delta_ms}" 'BEGIN { printf "%.6f", (now - prev) * 1000 / ms }')
      mediamtx_tx=$(awk -v now="${tx_total}" -v prev="${prev_docker_tx}" -v ms="${delta_ms}" 'BEGIN { printf "%.6f", (now - prev) * 1000 / ms }')
    fi
  fi

  prev_docker_ts_ms="${ts_ms}"
  prev_docker_rx="${rx_total}"
  prev_docker_tx="${tx_total}"
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

  mediamtx_cpu=""
  mediamtx_memory=""
  mediamtx_rx=""
  mediamtx_tx=""

  if [[ "${ACTIVE_BACKEND}" == "cadvisor" ]]; then
    mediamtx_cpu=$(prom_query 'sum(rate(container_cpu_usage_seconds_total{container_label_com_docker_compose_service="mediamtx"}[1m]))')
    mediamtx_memory=$(prom_query 'sum(container_memory_working_set_bytes{container_label_com_docker_compose_service="mediamtx"})')
    mediamtx_rx=$(prom_query 'sum(rate(container_network_receive_bytes_total{container_label_com_docker_compose_service="mediamtx"}[1m]))')
    mediamtx_tx=$(prom_query 'sum(rate(container_network_transmit_bytes_total{container_label_com_docker_compose_service="mediamtx"}[1m]))')
  elif [[ "${ACTIVE_BACKEND}" == "docker" ]]; then
    sample_docker_resources "${ts_ms}"
  fi

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "${ts_ms}" "${load1}" "${mem_available}" \
    "${gpu_util}" "${gpu_mem_used}" "${gpu_mem_total}" \
    "${mediamtx_cpu}" "${mediamtx_memory}" "${mediamtx_rx}" "${mediamtx_tx}" >> "${HOST_CSV}"

  curl -fsS --connect-timeout 1 --max-time 2 "${MTX_METRICS_URL}" > "${OUTPUT_DIR}/metrics/${ts_ms}.prom" 2>/dev/null || true
  sleep "${INTERVAL}"
done
