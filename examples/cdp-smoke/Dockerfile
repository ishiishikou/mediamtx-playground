FROM mcr.microsoft.com/playwright:v1.53.0-noble

WORKDIR /app

RUN npm init -y \
    && npm install --save-exact playwright@1.53.0

COPY cdp-smoke.mjs ./cdp-smoke.mjs

CMD ["node", "cdp-smoke.mjs"]
