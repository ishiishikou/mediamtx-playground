#!/usr/bin/env bash
set -euo pipefail

MTX_API_URL="${MTX_API_URL:-http://127.0.0.1:9997}"
ENDPOINT="${1:-/v3/paths/list}"

if [[ "${ENDPOINT}" != /* ]]; then
  ENDPOINT="/${ENDPOINT}"
fi

if command -v jq >/dev/null 2>&1; then
  curl -fsS "${MTX_API_URL}${ENDPOINT}" | jq .
else
  curl -fsS "${MTX_API_URL}${ENDPOINT}"
  echo
fi
