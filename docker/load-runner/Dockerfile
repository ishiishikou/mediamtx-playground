FROM python:3.12-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      ffmpeg \
      jq \
      procps \
      gstreamer1.0-tools \
      gstreamer1.0-plugins-base \
      gstreamer1.0-plugins-good \
      gstreamer1.0-plugins-bad \
      gstreamer1.0-plugins-ugly \
      gstreamer1.0-libav \
    && rm -rf /var/lib/apt/lists/*

RUN python -m pip install matplotlib

WORKDIR /workspace

COPY scripts ./scripts

CMD ["bash", "-lc", "bash scripts/load/run-load-matrix.sh && python3 scripts/load/render-load-graphs.py ${LOAD_OUTPUT_DIR:-/workspace/tmp/load-test/container}"]
