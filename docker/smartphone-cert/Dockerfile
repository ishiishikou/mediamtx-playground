FROM alpine:3.20

ARG MKCERT_VERSION=1.4.4
ARG TARGETARCH

RUN apk add --no-cache ca-certificates curl qrencode \
    && case "${TARGETARCH}" in \
         amd64|arm64) mkcert_arch="${TARGETARCH}" ;; \
         *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
       esac \
    && curl -fsSL \
       "https://github.com/FiloSottile/mkcert/releases/download/v${MKCERT_VERSION}/mkcert-v${MKCERT_VERSION}-linux-${mkcert_arch}" \
       -o /usr/local/bin/mkcert \
    && chmod 0755 /usr/local/bin/mkcert

WORKDIR /work

COPY scripts/smartphone/generate-assets.sh /usr/local/share/smartphone/generate-assets.sh

ENTRYPOINT ["sh", "/usr/local/share/smartphone/generate-assets.sh"]
