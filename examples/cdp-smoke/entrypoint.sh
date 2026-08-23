#!/bin/sh
set -eu

node cdp-smoke.mjs &
app_pid=$!

cleanup() {
  kill "$app_pid" 2>/dev/null || true
  kill "$relay_pid" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

# Headless Chromium binds CDP to 127.0.0.1:9222 inside the container.
# Relay it to 0.0.0.0:9223 so Docker port publishing can reach it.
socat TCP-LISTEN:9223,fork,reuseaddr TCP:127.0.0.1:9222 &
relay_pid=$!

wait "$app_pid"
