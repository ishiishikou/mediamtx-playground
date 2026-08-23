FROM mcr.microsoft.com/playwright:v1.53.0-noble

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends socat \
    && rm -rf /var/lib/apt/lists/* \
    && npm init -y \
    && npm install --save-exact playwright@1.53.0

COPY cdp-smoke.mjs ./cdp-smoke.mjs
COPY entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh

CMD ["./entrypoint.sh"]
