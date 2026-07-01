#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="${LOAD_COMPOSE_FILE:-${ROOT_DIR}/examples/docker-compose.poc.yml}"
FIXTURE_DIR="${LOAD_FIXTURE_DIR:-${ROOT_DIR}/tmp/load-fixtures}"
RUN_ID="${LOAD_RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
OUT_DIR="${LOAD_OUTPUT_DIR:-${ROOT_DIR}/tmp/load-test/${RUN_ID}}"

COUNTS="${LOAD_COUNTS:-1 5 10 20}"
PROFILES="${LOAD_PROFILES:-low medium high}"
MODES="${LOAD_MODES:-copy}"
PUBLISHERS="${LOAD_PUBLISHERS:-ffmpeg}"
REPEATS="${LOAD_REPEATS:-1}"
DURATION="${LOAD_DURATION:-60}"
SAMPLE_INTERVAL="${LOAD_SAMPLE_INTERVAL:-5}"
READERS_PER_STREAM="${LOAD_READERS_PER_STREAM:-0}"
START_SPACING="${LOAD_START_SPACING:-0.2}"
START_MEDIAMTX="${LOAD_START_MEDIAMTX:-1}"
STOP_MEDIAMTX="${LOAD_STOP_MEDIAMTX:-0}"

API_BASE="${MTX_API_URL:-http://127.0.0.1:9997}"
METRICS_BASE="${MTX_METRICS_URL:-http://127.0.0.1:9998}"
RTSP_HOST="${MTX_RTSP_HOST:-127.0.0.1}"
RTSP_PORT="${MTX_RTSP_PORT:-8554}"
PUBLISH_USER="${MTX_PUBLISH_USER:-poc-publisher}"
PUBLISH_PASS="${MTX_PUBLISH_PASS:-poc-publisher-pass}"
READ_USER="${MTX_READ_USER:-poc-viewer}"
READ_PASS="${MTX_READ_PASS:-poc-viewer-pass}"

mkdir -p "${OUT_DIR}/cases" "${OUT_DIR}/logs" "${OUT_DIR}/metrics"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing command: $1" >&2
    exit 1
  fi
}

need bash
need curl
need jq
need ffmpeg
need docker

profile_size() {
  case "$1" in
    low) echo "640x360" ;;
    medium) echo "1280x720" ;;
    high) echo "1920x1080" ;;
    *) echo "unknown profile: $1" >&2; exit 1 ;;
  esac
}

profile_fps() {
  case "$1" in
    low) echo "15" ;;
    medium|high) echo "30" ;;
    *) echo "unknown profile: $1" >&2; exit 1 ;;
  esac
}

profile_bitrate() {
  case "$1" in
    low) echo "500k" ;;
    medium) echo "1000k" ;;
    high) echo "3000k" ;;
    *) echo "unknown profile: $1" >&2; exit 1 ;;
  esac
}

profile_bitrate_kbps() {
  case "$1" in
    low) echo "500" ;;
    medium) echo "1000" ;;
    high) echo "3000" ;;
    *) echo "unknown profile: $1" >&2; exit 1 ;;
  esac
}

publish_url() {
  local path_name="$1"
  echo "rtsp://${PUBLISH_USER}:${PUBLISH_PASS}@${RTSP_HOST}:${RTSP_PORT}/${path_name}"
}

read_url() {
  local path_name="$1"
  echo "rtsp://${READ_USER}:${READ_PASS}@${RTSP_HOST}:${RTSP_PORT}/${path_name}"
}

api_count() {
  local endpoint="$1"
  curl -fsS "${API_BASE}${endpoint}" 2>/dev/null | jq -r '.itemCount // (.items | length) // 0' 2>/dev/null || echo 0
}

collect_loop() {
  local case_dir="$1"
  local sample_csv="$2"
  local started_at
  started_at="$(date +%s)"
  local index=0

  echo "timestamp_epoch,elapsed_sec,active_paths,rtsp_sessions,webrtc_sessions,docker_cpu_percent,docker_mem_usage,docker_net_io,metrics_file" > "${sample_csv}"

  while true; do
    local now elapsed paths rtsp_sessions webrtc_sessions docker_json cpu mem net metrics_file
    now="$(date +%s)"
    elapsed="$((now - started_at))"
    paths="$(api_count /v3/paths/list)"
    rtsp_sessions="$(api_count /v3/rtspsessions/list)"
    webrtc_sessions="$(api_count /v3/webrtcsessions/list)"
    docker_json="$(docker stats mediamtx-poc --no-stream --format '{{json .}}' 2>/dev/null || true)"
    cpu="$(printf '%s' "${docker_json}" | jq -r '.CPUPerc // ""' 2>/dev/null | tr -d '%' || true)"
    mem="$(printf '%s' "${docker_json}" | jq -r '.MemUsage // ""' 2>/dev/null || true)"
    net="$(printf '%s' "${docker_json}" | jq -r '.NetIO // ""' 2>/dev/null || true)"
    metrics_file="metrics-${index}.prom"
    curl -fsS "${METRICS_BASE}/metrics" > "${case_dir}/${metrics_file}" 2>/dev/null || true

    printf '%s,%s,%s,%s,%s,%s,"%s","%s",%s\n' \
      "${now}" "${elapsed}" "${paths}" "${rtsp_sessions}" "${webrtc_sessions}" "${cpu}" "${mem}" "${net}" "${metrics_file}" >> "${sample_csv}"

    index="$((index + 1))"
    sleep "${SAMPLE_INTERVAL}"
  done
}

start_ffmpeg_publisher() {
  local mode="$1" profile="$2" path_name="$3" log_file="$4"
  local size fps bitrate fixture
  size="$(profile_size "${profile}")"
  fps="$(profile_fps "${profile}")"
  bitrate="$(profile_bitrate "${profile}")"
  fixture="${FIXTURE_DIR}/${profile}.mp4"

  if [[ "${mode}" == "copy" ]]; then
    ffmpeg -hide_banner -loglevel warning -re -stream_loop -1 \
      -i "${fixture}" \
      -c copy \
      -f rtsp -rtsp_transport tcp \
      "$(publish_url "${path_name}")" > "${log_file}" 2>&1 &
  elif [[ "${mode}" == "encode" ]]; then
    ffmpeg -hide_banner -loglevel warning -re \
      -f lavfi -i "testsrc2=size=${size}:rate=${fps}" \
      -c:v libx264 \
      -preset ultrafast \
      -tune zerolatency \
      -pix_fmt yuv420p \
      -b:v "${bitrate}" \
      -g "$((fps * 2))" \
      -f rtsp -rtsp_transport tcp \
      "$(publish_url "${path_name}")" > "${log_file}" 2>&1 &
  else
    echo "unknown mode: ${mode}" >&2
    return 2
  fi
}

start_gstreamer_publisher() {
  local mode="$1" profile="$2" path_name="$3" log_file="$4"
  local size width height fps kbps
  size="$(profile_size "${profile}")"
  width="${size%x*}"
  height="${size#*x}"
  fps="$(profile_fps "${profile}")"
  kbps="$(profile_bitrate_kbps "${profile}")"

  if ! command -v gst-launch-1.0 >/dev/null 2>&1; then
    echo "missing command: gst-launch-1.0" > "${log_file}"
    return 127
  fi

  if [[ "${mode}" != "encode" ]]; then
    echo "gstreamer publisher currently supports mode=encode only" > "${log_file}"
    return 2
  fi

  gst-launch-1.0 -q \
    videotestsrc is-live=true pattern=smpte ! \
    "video/x-raw,width=${width},height=${height},framerate=${fps}/1" ! \
    x264enc bitrate="${kbps}" tune=zerolatency speed-preset=ultrafast key-int-max="$((fps * 2))" ! \
    h264parse ! \
    rtspclientsink protocols=tcp location="$(publish_url "${path_name}")" > "${log_file}" 2>&1 &
}

start_reader() {
  local path_name="$1" log_file="$2"
  ffmpeg -hide_banner -loglevel warning -rtsp_transport tcp \
    -i "$(read_url "${path_name}")" \
    -an -f null - > "${log_file}" 2>&1 &
}

stop_pids() {
  local pids=("$@")
  local pid
  for pid in "${pids[@]}"; do
    if kill -0 "${pid}" >/dev/null 2>&1; then
      kill "${pid}" >/dev/null 2>&1 || true
    fi
  done
  sleep 1
  for pid in "${pids[@]}"; do
    if kill -0 "${pid}" >/dev/null 2>&1; then
      kill -9 "${pid}" >/dev/null 2>&1 || true
    fi
  done
}

run_case() {
  local publisher="$1" profile="$2" mode="$3" stream_count="$4" repeat="$5"
  local case_id case_dir sample_csv meta_file collector_pid
  local -a publisher_pids=()
  local -a reader_pids=()
  local i r path_name

  case_id="${publisher}_${profile}_${mode}_${stream_count}s_${READERS_PER_STREAM}r_rep${repeat}"
  case_dir="${OUT_DIR}/cases/${case_id}"
  sample_csv="${case_dir}/samples.csv"
  meta_file="${case_dir}/case.json"
  mkdir -p "${case_dir}/publishers" "${case_dir}/readers"

  cat > "${meta_file}" <<JSON
{"case_id":"${case_id}","publisher":"${publisher}","profile":"${profile}","mode":"${mode}","streams":${stream_count},"readers_per_stream":${READERS_PER_STREAM},"repeat":${repeat},"duration_sec":${DURATION},"sample_interval_sec":${SAMPLE_INTERVAL}}
JSON

  echo "case start: ${case_id}"
  collect_loop "${case_dir}" "${sample_csv}" &
  collector_pid="$!"

  for i in $(seq 1 "${stream_count}"); do
    path_name="live/load-${case_id}-${i}"
    if [[ "${publisher}" == "ffmpeg" ]]; then
      start_ffmpeg_publisher "${mode}" "${profile}" "${path_name}" "${case_dir}/publishers/${i}.log" || true
    elif [[ "${publisher}" == "gstreamer" ]]; then
      start_gstreamer_publisher "${mode}" "${profile}" "${path_name}" "${case_dir}/publishers/${i}.log" || true
    else
      echo "unknown publisher: ${publisher}" >&2
      kill "${collector_pid}" >/dev/null 2>&1 || true
      return 2
    fi
    publisher_pids+=("$!")
    sleep "${START_SPACING}"
  done

  sleep 5

  if [[ "${READERS_PER_STREAM}" -gt 0 ]]; then
    for i in $(seq 1 "${stream_count}"); do
      path_name="live/load-${case_id}-${i}"
      for r in $(seq 1 "${READERS_PER_STREAM}"); do
        start_reader "${path_name}" "${case_dir}/readers/${i}-${r}.log"
        reader_pids+=("$!")
        sleep "${START_SPACING}"
      done
    done
  fi

  sleep "${DURATION}"

  stop_pids "${reader_pids[@]}" "${publisher_pids[@]}"
  kill "${collector_pid}" >/dev/null 2>&1 || true
  wait "${collector_pid}" 2>/dev/null || true

  local publisher_alive=0 reader_alive=0
  for i in "${publisher_pids[@]}"; do
    if kill -0 "${i}" >/dev/null 2>&1; then publisher_alive="$((publisher_alive + 1))"; fi
  done
  for i in "${reader_pids[@]}"; do
    if kill -0 "${i}" >/dev/null 2>&1; then reader_alive="$((reader_alive + 1))"; fi
  done

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "${case_id}" "${publisher}" "${profile}" "${mode}" "${stream_count}" "${READERS_PER_STREAM}" "${repeat}" "${publisher_alive}" "${reader_alive}" >> "${OUT_DIR}/case-results.csv"

  echo "case done: ${case_id}"
  sleep 3
}

if [[ "${START_MEDIAMTX}" == "1" ]]; then
  docker compose -f "${COMPOSE_FILE}" up -d
fi

"${ROOT_DIR}/scripts/load/generate-fixtures.sh"

echo "case_id,publisher,profile,mode,streams,readers_per_stream,repeat,publisher_alive_after_stop,reader_alive_after_stop" > "${OUT_DIR}/case-results.csv"
cat > "${OUT_DIR}/run-config.txt" <<EOF
LOAD_RUN_ID=${RUN_ID}
LOAD_COUNTS=${COUNTS}
LOAD_PROFILES=${PROFILES}
LOAD_MODES=${MODES}
LOAD_PUBLISHERS=${PUBLISHERS}
LOAD_REPEATS=${REPEATS}
LOAD_DURATION=${DURATION}
LOAD_SAMPLE_INTERVAL=${SAMPLE_INTERVAL}
LOAD_READERS_PER_STREAM=${READERS_PER_STREAM}
LOAD_START_SPACING=${START_SPACING}
EOF

for repeat in ${REPEATS}; do
  for publisher in ${PUBLISHERS}; do
    for profile in ${PROFILES}; do
      for mode in ${MODES}; do
        if [[ "${publisher}" == "gstreamer" && "${mode}" != "encode" ]]; then
          echo "skip: publisher=gstreamer mode=${mode} is unsupported"
          continue
        fi
        for stream_count in ${COUNTS}; do
          run_case "${publisher}" "${profile}" "${mode}" "${stream_count}" "${repeat}"
        done
      done
    done
  done
done

if [[ "${STOP_MEDIAMTX}" == "1" ]]; then
  docker compose -f "${COMPOSE_FILE}" down -v || true
fi

echo "load output: ${OUT_DIR}"
