#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${MTX_API_BASE_URL:-http://localhost:9997}"

echo "Checking MediaMTX Control API: ${BASE_URL}"
curl -fsS "${BASE_URL}/v3/config/global/get" | sed 's/,/,&\n/g' | head -n 40

echo
echo "OK"
