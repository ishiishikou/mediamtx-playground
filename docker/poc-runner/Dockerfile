FROM mcr.microsoft.com/playwright:v1.53.0-jammy

ENV DEBIAN_FRONTEND=noninteractive \
    NODE_ENV=development

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      ffmpeg \
      jq \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

COPY package.json ./
RUN npm install --no-audit --no-fund

COPY examples ./examples
COPY scripts ./scripts

CMD ["bash", "-lc", "bash scripts/poc/run-smoke.sh && npm run check:webrtc-publish"]
