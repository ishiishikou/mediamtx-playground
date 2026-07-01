#!/usr/bin/env bash
set -euo pipefail

PATH_NAME="${1:-live/poc-rtsp-001}"
MTX_HOST="${MTX_HOST:-127.0.0.1}"
HLS_PORT="${HLS_PORT:-8888}"
VIEW_USER="${VIEW_USER:-poc-viewer}"
VIEW_PASS="${VIEW_PASS:-poc-viewer-pass}"
MAX_WAIT_SECONDS="${MAX_WAIT_SECONDS:-15}"

URL="http://${MTX_HOST}:${HLS_PORT}/${PATH_NAME}/index.m3u8"
TMP_FILE="$(mktemp)"
trap 'rm -f "${TMP_FILE}"' EXIT

start_epoch="$(date +%s)"

echo "Checking HLS playlist: ${URL}" >&2

while true; do
  if curl -u "${VIEW_USER}:${VIEW_PASS}" -fsS -w "\ntime_total=%{time_total}\n" -o "${TMP_FILE}" "${URL}"; then
    echo "--- playlist ---"
    cat "${TMP_FILE}"
    echo "--- result ---"
    echo "HLS playlist is available."
    exit 0
  fi

  now_epoch="$(date +%s)"
  elapsed="$((now_epoch - start_epoch))"
  if (( elapsed >= MAX_WAIT_SECONDS )); then
    echo "HLS playlist was not available within ${MAX_WAIT_SECONDS}s." >&2
    exit 1
  fi

  sleep 1
done
