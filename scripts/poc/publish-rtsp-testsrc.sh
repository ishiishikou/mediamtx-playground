#!/usr/bin/env bash
set -euo pipefail

PATH_NAME="${1:-live/poc-rtsp-$(date +%s)}"
DURATION="${DURATION:-30}"
MTX_HOST="${MTX_HOST:-127.0.0.1}"
RTSP_PORT="${RTSP_PORT:-8554}"
PUBLISH_USER="${PUBLISH_USER:-poc-publisher}"
PUBLISH_PASS="${PUBLISH_PASS:-poc-publisher-pass}"
FPS="${FPS:-30}"
WIDTH="${WIDTH:-1280}"
HEIGHT="${HEIGHT:-720}"
GOP="${GOP:-30}"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is required." >&2
  exit 1
fi

URL="rtsp://${PUBLISH_USER}:${PUBLISH_PASS}@${MTX_HOST}:${RTSP_PORT}/${PATH_NAME}"

echo "Publishing test pattern to ${PATH_NAME} for ${DURATION}s" >&2

ffmpeg \
  -hide_banner \
  -loglevel info \
  -re \
  -f lavfi \
  -i "testsrc2=size=${WIDTH}x${HEIGHT}:rate=${FPS}" \
  -f lavfi \
  -i "sine=frequency=1000:sample_rate=48000" \
  -t "${DURATION}" \
  -c:v libx264 \
  -preset veryfast \
  -tune zerolatency \
  -pix_fmt yuv420p \
  -g "${GOP}" \
  -keyint_min "${GOP}" \
  -sc_threshold 0 \
  -c:a aac \
  -f rtsp \
  -rtsp_transport tcp \
  "${URL}"
