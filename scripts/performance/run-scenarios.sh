#!/usr/bin/env bash
set -euo pipefail

CONFIG="${PERF_CONFIG:-${1:-configs/performance/scenarios.example.json}}"
OUTPUT_ROOT="${PERF_OUTPUT_ROOT:-tmp/performance-results}"
FIXTURE_DIR="${PERF_FIXTURE_DIR:-tmp/performance-fixtures}"
ONLY_SCENARIOS="${PERF_ONLY_SCENARIOS:-}"
RUN_ID="${PERF_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
RUN_DIR="${OUTPUT_ROOT}/${RUN_ID}"

for command in jq node python3 ffmpeg curl; do
  command -v "${command}" >/dev/null 2>&1 || { echo "required command not found: ${command}" >&2; exit 1; }
done
[[ -f "${CONFIG}" ]] || { echo "scenario config not found: ${CONFIG}" >&2; exit 1; }

mkdir -p "${RUN_DIR}"
cp "${CONFIG}" "${RUN_DIR}/scenarios.json"

export PERF_FIXTURE_DIR="${FIXTURE_DIR}"
if [[ ! -f "${FIXTURE_DIR}/sample.mp4" || ! -f "${FIXTURE_DIR}/sample.y4m" ]]; then
  bash scripts/performance/prepare-fixture.sh "${FIXTURE_DIR}"
fi

cat > "${RUN_DIR}/run.json" <<JSON
{
  "run_id": "${RUN_ID}",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "config": "${CONFIG}",
  "fixture_dir": "${FIXTURE_DIR}",
  "only_scenarios": "${ONLY_SCENARIOS}"
}
JSON

scenario_selected() {
  local id="$1"
  [[ -z "${ONLY_SCENARIOS}" ]] && return 0
  local candidate
  for candidate in ${ONLY_SCENARIOS}; do
    [[ "${candidate}" == "${id}" ]] && return 0
  done
  return 1
}

scenario_count=$(jq '.scenarios | length' "${CONFIG}")
for ((scenario_index=0; scenario_index<scenario_count; scenario_index++)); do
  scenario=$(jq -c ".scenarios[${scenario_index}]" "${CONFIG}")
  id=$(jq -r '.id' <<<"${scenario}")
  automated=$(jq -r 'if has("automated") then .automated else true end' <<<"${scenario}")
  protocol=$(jq -r '.protocol' <<<"${scenario}")
  priority=$(jq -r '.priority // "must"' <<<"${scenario}")

  if [[ "${automated}" != "true" ]]; then
    echo "skip manual scenario: ${id}"
    continue
  fi
  if ! scenario_selected "${id}"; then
    echo "skip unselected scenario: ${id}"
    continue
  fi

  clients=$(jq -r '.clients // empty' <<<"${scenario}")
  duration=$(jq -r '.durationSeconds // empty' <<<"${scenario}")
  repeats=$(jq -r '.repeats // empty' <<<"${scenario}")
  stats_interval=$(jq -r '.statsIntervalSeconds // empty' <<<"${scenario}")
  path_prefix=$(jq -r '.pathPrefix // empty' <<<"${scenario}")
  result_event_name=$(jq -r '.resultEventName // empty' <<<"${scenario}")

  [[ -n "${clients}" ]] || clients=$(jq -r '.defaults.clients // 1' "${CONFIG}")
  [[ -n "${duration}" ]] || duration=$(jq -r '.defaults.durationSeconds // 300' "${CONFIG}")
  [[ -n "${repeats}" ]] || repeats=$(jq -r '.defaults.repeats // 3' "${CONFIG}")
  [[ -n "${stats_interval}" ]] || stats_interval=$(jq -r '.defaults.statsIntervalSeconds // 5' "${CONFIG}")
  [[ -n "${path_prefix}" ]] || path_prefix=$(jq -r '.defaults.pathPrefix // "live/perf"' "${CONFIG}")
  [[ -n "${result_event_name}" ]] || result_event_name=$(jq -r '.defaults.resultEventName // "perf:inference-result"' "${CONFIG}")

  for ((repeat=1; repeat<=repeats; repeat++)); do
    case_id="${id}_rep${repeat}"
    case_dir="${RUN_DIR}/cases/${case_id}"
    mkdir -p "${case_dir}"
    echo "run ${case_id}: protocol=${protocol} clients=${clients} duration=${duration}s priority=${priority}"

    cat > "${case_dir}/case.json" <<JSON
{
  "run_id": "${RUN_ID}",
  "case_id": "${case_id}",
  "scenario_id": "${id}",
  "protocol": "${protocol}",
  "clients": ${clients},
  "duration_seconds": ${duration},
  "repeat": ${repeat},
  "priority": "${priority}",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON

    PERF_CASE_DIR="${case_dir}" \
      bash scripts/performance/collect-resources.sh "${case_dir}" "${duration}" "${stats_interval}" &
    collector_pid=$!

    set +e
    if [[ "${protocol}" == "webrtc" ]]; then
      PERF_SCENARIO_ID="${id}" \
      PERF_CLIENTS="${clients}" \
      PERF_DURATION_SECONDS="${duration}" \
      PERF_STATS_INTERVAL_SECONDS="${stats_interval}" \
      PERF_INPUT_Y4M="${FIXTURE_DIR}/sample.y4m" \
      PERF_CASE_DIR="${case_dir}" \
      PERF_PATH_PREFIX="${path_prefix}" \
      PERF_RESULT_EVENT_NAME="${result_event_name}" \
        node scripts/performance/webrtc-publisher.mjs
      case_exit=$?
    elif [[ "${protocol}" == "rtsp" ]]; then
      PERF_SCENARIO_ID="${id}" \
      PERF_CLIENTS="${clients}" \
      PERF_DURATION_SECONDS="${duration}" \
      PERF_INPUT_FILE="${FIXTURE_DIR}/sample.mp4" \
      PERF_CASE_DIR="${case_dir}" \
      PERF_PATH_PREFIX="${path_prefix}" \
        bash scripts/performance/run-rtsp-publishers.sh
      case_exit=$?
    else
      echo "unsupported automated protocol: ${protocol}" >&2
      case_exit=2
    fi
    set -e

    if [[ "${case_exit}" -ne 0 ]] && kill -0 "${collector_pid}" 2>/dev/null; then
      kill -TERM "${collector_pid}" 2>/dev/null || true
    fi
    wait "${collector_pid}" 2>/dev/null || true
    jq --arg status "$([[ "${case_exit}" -eq 0 ]] && echo completed || echo failed)" \
       --argjson exit_code "${case_exit}" \
       --arg completed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '. + {status: $status, exit_code: $exit_code, completed_at: $completed_at}' \
       "${case_dir}/case.json" > "${case_dir}/case.json.tmp"
    mv "${case_dir}/case.json.tmp" "${case_dir}/case.json"
  done
done

python3 scripts/performance/summarize-results.py "${RUN_DIR}"
echo "performance results: ${RUN_DIR}"
