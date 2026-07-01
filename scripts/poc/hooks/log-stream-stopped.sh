#!/usr/bin/env sh
set -eu

echo "$(date -Iseconds) stream_stopped path=${MTX_PATH:-} query=${MTX_QUERY:-} source_type=${MTX_SOURCE_TYPE:-} source_id=${MTX_SOURCE_ID:-}" >&2
