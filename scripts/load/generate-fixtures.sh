#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${LOAD_FIXTURE_DIR:-${ROOT_DIR}/tmp/load-fixtures}"
DURATION="${LOAD_FIXTURE_DURATION:-60}"

mkdir -p "${OUT_DIR}"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing command: $1" >&2
    exit 1
  fi
}

need ffmpeg

make_fixture() {
  local name="$1"
  local size="$2"
  local fps="$3"
  local bitrate="$4"
  local out="${OUT_DIR}/${name}.mp4"

  if [[ -s "${out}" && "${LOAD_REGENERATE_FIXTURES:-0}" != "1" ]]; then
    echo "exists: ${out}"
    return
  fi

  echo "generate: profile=${name} size=${size} fps=${fps} bitrate=${bitrate} duration=${DURATION}s"
  ffmpeg -hide_banner -loglevel warning -y \
    -f lavfi -i "testsrc2=size=${size}:rate=${fps}" \
    -t "${DURATION}" \
    -c:v libx264 \
    -preset veryfast \
    -pix_fmt yuv420p \
    -b:v "${bitrate}" \
    -g "$((fps * 2))" \
    -movflags +faststart \
    "${out}"
}

make_fixture low 640x360 15 500k
make_fixture medium 1280x720 30 1000k
make_fixture high 1920x1080 30 3000k

echo "fixtures written to: ${OUT_DIR}"
