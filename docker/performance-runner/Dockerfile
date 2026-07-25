FROM mcr.microsoft.com/playwright:v1.53.0-jammy

ENV DEBIAN_FRONTEND=noninteractive \
    NODE_ENV=development \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      ffmpeg \
      fonts-dejavu-core \
      jq \
      procps \
      python3 \
      python3-pip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

COPY package.json ./
RUN npm install --no-audit --no-fund --no-save playwright@1.53.0 \
    && python3 -m pip install matplotlib

COPY configs ./configs
COPY scripts ./scripts

CMD ["bash", "scripts/performance/run-scenarios.sh"]
