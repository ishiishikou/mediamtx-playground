#!/usr/bin/env bash
set -euo pipefail

PATH_NAME="${MTX_TEST_PATH:-test}"
RTSP_URL="${MTX_RTSP_URL:-rtsp://localhost:8554/${PATH_NAME}}"

echo "Publishing ffmpeg test source to ${RTSP_URL}"
echo "Stop with Ctrl+C."

ffmpeg \
  -re \
  -f lavfi -i testsrc=size=1280x720:rate=30 \
  -f lavfi -i sine=frequency=1000:sample_rate=48000 \
  -c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p \
  -c:a aac -ar 48000 -ac 2 \
  -f rtsp -rtsp_transport tcp \
  "${RTSP_URL}"
