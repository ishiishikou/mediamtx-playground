#!/usr/bin/env bash
set -euo pipefail

TYPE="${1:-}"
SESSION_ID="${2:-}"
MTX_API_URL="${MTX_API_URL:-http://127.0.0.1:9997}"

usage() {
  cat >&2 <<'USAGE'
Usage:
  bash scripts/poc/kick-session.sh <type> <id>

Types:
  webrtc  -> /v3/webrtcsessions/kick/{id}
  rtsp    -> /v3/rtspsessions/kick/{id}
  rtmp    -> /v3/rtmpconns/kick/{id}
  srt     -> /v3/srtconns/kick/{id}
  hls     -> /v3/hlssessions/kick/{id}

List examples:
  bash scripts/poc/api.sh /v3/webrtcsessions/list
  bash scripts/poc/api.sh /v3/rtspsessions/list
  bash scripts/poc/api.sh /v3/rtmpconns/list
  bash scripts/poc/api.sh /v3/srtconns/list
  bash scripts/poc/api.sh /v3/hlssessions/list
USAGE
}

if [[ -z "${TYPE}" || -z "${SESSION_ID}" ]]; then
  usage
  exit 1
fi

case "${TYPE}" in
  webrtc) ENDPOINT="/v3/webrtcsessions/kick/${SESSION_ID}" ;;
  rtsp) ENDPOINT="/v3/rtspsessions/kick/${SESSION_ID}" ;;
  rtmp) ENDPOINT="/v3/rtmpconns/kick/${SESSION_ID}" ;;
  srt) ENDPOINT="/v3/srtconns/kick/${SESSION_ID}" ;;
  hls) ENDPOINT="/v3/hlssessions/kick/${SESSION_ID}" ;;
  *)
    echo "Unknown type: ${TYPE}" >&2
    usage
    exit 1
    ;;
esac

echo "Kicking ${TYPE} session/connection: ${SESSION_ID}" >&2
curl -fsS -X POST "${MTX_API_URL}${ENDPOINT}"
echo
