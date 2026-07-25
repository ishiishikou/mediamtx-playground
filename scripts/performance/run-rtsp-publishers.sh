#!/usr/bin/env bash
set -euo pipefail

SCENARIO_ID="${PERF_SCENARIO_ID:?PERF_SCENARIO_ID is required}"
CLIENTS="${PERF_CLIENTS:-1}"
DURATION="${PERF_DURATION_SECONDS:-60}"
INPUT_FILE="${PERF_INPUT_FILE:?PERF_INPUT_FILE is required}"
OUTPUT_DIR="${PERF_CASE_DIR:?PERF_CASE_DIR is required}"
PATH_PREFIX="${PERF_PATH_PREFIX:-live/perf}"
RTSP_BASE_URL="${RTSP_BASE_URL:-rtsp://poc-publisher:poc-publisher-pass@127.0.0.1:8554}"
START_STAGGER_MS="${PERF_CLIENT_START_STAGGER_MS:-250}"

mkdir -p "${OUTPUT_DIR}/publishers"
EVENTS="${OUTPUT_DIR}/publisher-events.csv"
printf 'scenario_id,client_id,path,start_ts_ms,end_ts_ms,exit_code,status\n' > "${EVENTS}"

pids=()
client_ids=()
paths=()
starts=()

cleanup() {
  local pid
  for pid in "${pids[@]:-}"; do
    kill -TERM "${pid}" 2>/dev/null || true
  done
  sleep 1
  for pid in "${pids[@]:-}"; do
    kill -KILL "${pid}" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

for ((i=1; i<=CLIENTS; i++)); do
  client_id=$(printf 'rtsp-%03d' "${i}")
  path="${PATH_PREFIX}/${SCENARIO_ID,,}/${client_id}"
  url="${RTSP_BASE_URL}/${path}"
  log_file="${OUTPUT_DIR}/publishers/${client_id}.log"
  start_ts_ms=$(date +%s%3N)

  ffmpeg -hide_banner -loglevel info -re -stream_loop -1 \
    -i "${INPUT_FILE}" \
    -t "${DURATION}" \
    -an \
    -c:v copy \
    -rtsp_transport tcp \
    -f rtsp \
    "${url}" >"${log_file}" 2>&1 &

  pids+=("$!")
  client_ids+=("${client_id}")
  paths+=("${path}")
  starts+=("${start_ts_ms}")
  python3 - <<PY
import time
time.sleep(${START_STAGGER_MS} / 1000)
PY
done

failed=0
for idx in "${!pids[@]}"; do
  pid="${pids[$idx]}"
  set +e
  wait "${pid}"
  exit_code=$?
  set -e
  if [[ "${exit_code}" -ne 0 ]]; then
    failed=$((failed + 1))
  fi
  end_ts_ms=$(date +%s%3N)
  status="completed"
  if [[ "${exit_code}" -ne 0 ]]; then
    status="failed"
  fi
  printf '%s,%s,%s,%s,%s,%s,%s\n' \
    "${SCENARIO_ID}" "${client_ids[$idx]}" "${paths[$idx]}" \
    "${starts[$idx]}" "${end_ts_ms}" "${exit_code}" "${status}" >> "${EVENTS}"
done

trap - EXIT INT TERM

cat > "${OUTPUT_DIR}/rtsp-summary.json" <<JSON
{
  "scenario_id": "${SCENARIO_ID}",
  "protocol": "rtsp",
  "requested_clients": ${CLIENTS},
  "completed_clients": $((CLIENTS - failed)),
  "failed_clients": ${failed},
  "duration_seconds": ${DURATION}
}
JSON

[[ "${failed}" -eq 0 ]]
