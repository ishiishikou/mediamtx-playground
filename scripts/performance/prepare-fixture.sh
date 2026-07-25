#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${PERF_FIXTURE_DIR:-${1:-tmp/performance-fixtures}}"
SOURCE_FILE="${PERF_SOURCE_VIDEO:-${2:-}}"
DURATION="${PERF_FIXTURE_DURATION:-30}"
FPS="${PERF_FIXTURE_FPS:-15}"
WIDTH="${PERF_FIXTURE_WIDTH:-640}"
HEIGHT="${PERF_FIXTURE_HEIGHT:-360}"
MP4_OUT="${OUTPUT_DIR}/sample.mp4"
Y4M_OUT="${OUTPUT_DIR}/sample.y4m"
META_OUT="${OUTPUT_DIR}/fixture.json"

mkdir -p "${OUTPUT_DIR}"

COMMON_FILTER="fps=${FPS},scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=decrease,pad=${WIDTH}:${HEIGHT}:(ow-iw)/2:(oh-ih)/2,format=yuv420p,drawbox=x=20:y=20:w=80:h=80:color=white@1:t=fill:enable='lt(mod(t,2),0.5)'"
DRAW_FILTER="${COMMON_FILTER},drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='frame %{n}  pts %{pts\\:hms}':x=20:y=h-42:fontsize=22:fontcolor=white:box=1:boxcolor=black@0.6"

if [[ -n "${SOURCE_FILE}" ]]; then
  if [[ ! -f "${SOURCE_FILE}" ]]; then
    echo "source video not found: ${SOURCE_FILE}" >&2
    exit 1
  fi
  INPUT_ARGS=(-stream_loop -1 -i "${SOURCE_FILE}")
  SOURCE_KIND="file"
else
  INPUT_ARGS=(-f lavfi -i "testsrc2=size=${WIDTH}x${HEIGHT}:rate=${FPS}")
  SOURCE_KIND="generated"
fi

encode_fixture() {
  local filter="$1"
  ffmpeg -hide_banner -loglevel warning -y \
    "${INPUT_ARGS[@]}" \
    -t "${DURATION}" \
    -an \
    -vf "${filter}" \
    -c:v libx264 \
    -preset veryfast \
    -tune zerolatency \
    -profile:v baseline \
    -g "${FPS}" \
    -keyint_min "${FPS}" \
    -sc_threshold 0 \
    -bf 0 \
    -pix_fmt yuv420p \
    -movflags +faststart \
    "${MP4_OUT}"
}

if ! encode_fixture "${DRAW_FILTER}"; then
  echo "drawtext filter failed; generating fixture without frame text" >&2
  encode_fixture "${COMMON_FILTER}"
fi

ffmpeg -hide_banner -loglevel warning -y \
  -i "${MP4_OUT}" \
  -an \
  -pix_fmt yuv420p \
  -f yuv4mpegpipe \
  "${Y4M_OUT}"

cat > "${META_OUT}" <<JSON
{
  "source_kind": "${SOURCE_KIND}",
  "source_file": "${SOURCE_FILE}",
  "duration_seconds": ${DURATION},
  "fps": ${FPS},
  "width": ${WIDTH},
  "height": ${HEIGHT},
  "mp4": "${MP4_OUT}",
  "y4m": "${Y4M_OUT}"
}
JSON

echo "fixture mp4: ${MP4_OUT}"
echo "fixture y4m: ${Y4M_OUT}"
echo "fixture metadata: ${META_OUT}"
