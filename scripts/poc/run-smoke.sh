#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="${POC_COMPOSE_FILE:-${ROOT_DIR}/examples/docker-compose.poc.yml}"
OUTPUT_DIR="${POC_OUTPUT_DIR:-${ROOT_DIR}/tmp/poc-output}"
PATH_NAME="live/smoke-$(date +%s)"
PUBLISH_DURATION="${PUBLISH_DURATION:-18}"
RECORD_DURATION="${RECORD_DURATION:-6}"
MAX_WAIT_SECONDS="${MAX_WAIT_SECONDS:-20}"
START_MEDIAMTX="${POC_START_MEDIAMTX:-1}"
STOP_MEDIAMTX="${POC_STOP_MEDIAMTX:-0}"

mkdir -p "${OUTPUT_DIR}"
cd "${ROOT_DIR}"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is required." >&2
  exit 1
fi

wait_for_api() {
  local start_epoch now_epoch elapsed
  start_epoch="$(date +%s)"

  echo "Waiting for MediaMTX Control API..." >&2
  while true; do
    if bash scripts/poc/api.sh /v3/paths/list >/dev/null 2>&1; then
      echo "MediaMTX Control API is ready." >&2
      return 0
    fi

    now_epoch="$(date +%s)"
    elapsed="$((now_epoch - start_epoch))"
    if (( elapsed >= MAX_WAIT_SECONDS )); then
      echo "MediaMTX Control API was not ready within ${MAX_WAIT_SECONDS}s." >&2
      return 1
    fi

    sleep 1
  done
}

if [[ "${START_MEDIAMTX}" == "1" ]]; then
  if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required when POC_START_MEDIAMTX=1." >&2
    exit 1
  fi

  if ! docker compose version >/dev/null 2>&1; then
    echo "docker compose is required when POC_START_MEDIAMTX=1." >&2
    exit 1
  fi

  echo "Starting MediaMTX PoC container..." >&2
  docker compose -f "${COMPOSE_FILE}" up -d
fi

cleanup() {
  if [[ -n "${PUBLISH_PID:-}" ]] && kill -0 "${PUBLISH_PID}" >/dev/null 2>&1; then
    kill "${PUBLISH_PID}" >/dev/null 2>&1 || true
  fi
  if [[ "${STOP_MEDIAMTX}" == "1" ]]; then
    if command -v docker >/dev/null 2>&1; then
      docker compose -f "${COMPOSE_FILE}" down -v >/dev/null 2>&1 || true
    fi
  fi
}
trap cleanup EXIT

wait_for_api

echo "Initial paths:" >&2
bash scripts/poc/api.sh /v3/paths/list | tee "${OUTPUT_DIR}/paths-initial.json"

echo "Publishing ${PATH_NAME}..." >&2
DURATION="${PUBLISH_DURATION}" bash scripts/poc/publish-rtsp-testsrc.sh "${PATH_NAME}" >"${OUTPUT_DIR}/publisher.log" 2>&1 &
PUBLISH_PID="$!"

sleep 5

echo "Paths while publishing:" >&2
bash scripts/poc/api.sh /v3/paths/list | tee "${OUTPUT_DIR}/paths-publishing.json"

echo "RTSP sessions while publishing:" >&2
bash scripts/poc/api.sh /v3/rtspsessions/list | tee "${OUTPUT_DIR}/rtsp-sessions-publishing.json"

echo "Recording a short reader sample..." >&2
OUTPUT_DIR="${OUTPUT_DIR}" bash scripts/poc/record-rtsp-head.sh "${PATH_NAME}" "${RECORD_DURATION}" | tee "${OUTPUT_DIR}/record.log"

echo "Checking HLS playlist..." >&2
bash scripts/poc/check-hls.sh "${PATH_NAME}" | tee "${OUTPUT_DIR}/hls.log"

wait "${PUBLISH_PID}" || true
PUBLISH_PID=""

sleep 2

echo "Paths after publisher stops:" >&2
bash scripts/poc/api.sh /v3/paths/list | tee "${OUTPUT_DIR}/paths-after-stop.json"

echo "Smoke test completed. Outputs are in ${OUTPUT_DIR}." >&2
