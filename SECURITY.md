# Security Policy

## Public repository policy

This repository is public. Do not commit real credentials, private keys, certificates, tokens, camera URLs, recording files, screenshots that contain private information, or environment-specific logs.

## Do not commit

- `.env` or local override files
- real RTSP / RTMP / WebRTC / TURN credentials
- private IP addresses or global IP addresses tied to a personal environment
- TLS private keys or certificates
- recorded video, captured images, or raw logs

## Safe examples

Use `*.example.yml` and `.env.example` for public examples. Use placeholders such as `example-user`, `example-password`, and `example.local`.

## Local-only files

Use these files for real values. They are ignored by Git.

- `.env`
- `mediamtx.local.yml`
- `docker-compose.override.yml`
