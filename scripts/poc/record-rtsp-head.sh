#!/usr/bin/env bash
set -euo pipefail

PATH_NAME="${1:-live/poc-rtsp-001}"
DURATION="${2:-8}"
MTX_HOST="${MTX_HOST:-127.0.0.1}"
RTSP_PORT="${RTSP_PORT:-8554}"
VIEW_USER="${VIEW_USER:-poc-viewer}"
VIEW_PASS="${VIEW_PASS:-poc-viewer-pass}"
OUTPUT_DIR="${OUTPUT_DIR:-tmp/poc-output}"
SAFE_NAME="$(echo "${PATH_NAME}" | tr '/:' '__')"
OUTPUT_FILE="${OUTPUT_DIR}/${SAFE_NAME}_head.mp4"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is required." >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"
URL="rtsp://${VIEW_USER}:${VIEW_PASS}@${MTX_HOST}:${RTSP_PORT}/${PATH_NAME}"

echo "Recording first ${DURATION}s from ${PATH_NAME} to ${OUTPUT_FILE}" >&2

ffmpeg \
  -hide_banner \
  -loglevel info \
  -rtsp_transport tcp \
  -i "${URL}" \
  -t "${DURATION}" \
  -c copy \
  -y \
  "${OUTPUT_FILE}"

echo "Saved: ${OUTPUT_FILE}"
