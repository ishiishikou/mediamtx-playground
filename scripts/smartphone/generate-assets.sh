#!/bin/sh
set -eu

: "${SMARTPHONE_LAN_IP:?SMARTPHONE_LAN_IP is required}"

if ! printf '%s\n' "${SMARTPHONE_LAN_IP}" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
  echo "SMARTPHONE_LAN_IP must be an IPv4 address: ${SMARTPHONE_LAN_IP}" >&2
  exit 1
fi

CERT_ROOT=/work/certs
PUBLIC_ROOT=/work/public
GENERATED_ROOT=/work/generated
TEMPLATE=/templates/mediamtx.smartphone.example.yml

mkdir -p "${CERT_ROOT}/ca" "${PUBLIC_ROOT}" "${GENERATED_ROOT}"
export CAROOT="${CERT_ROOT}/ca"

# mkcert は CAROOT にCAがなければ自動生成する。
# -install は実行しないため、Windows / WSL / コンテナの trust store は変更しない。
mkcert \
  -cert-file "${CERT_ROOT}/server.crt" \
  -key-file "${CERT_ROOT}/server.key" \
  "${SMARTPHONE_LAN_IP}" localhost 127.0.0.1

# CA は検証期間中に再利用する。HTTP配信側には公開情報であるCA証明書だけをコピーする。
# rootCA-key.pem は CERT_ROOT 配下に残し、cert-server からは参照できない。
cp "${CAROOT}/rootCA.pem" "${PUBLIC_ROOT}/rootCA.pem"
chmod 0600 "${CERT_ROOT}/server.key" "${CAROOT}/rootCA-key.pem"
chmod 0644 "${CERT_ROOT}/server.crt" "${CAROOT}/rootCA.pem" "${PUBLIC_ROOT}/rootCA.pem"

sed "s/__SMARTPHONE_LAN_IP__/${SMARTPHONE_LAN_IP}/g" \
  "${TEMPLATE}" > "${GENERATED_ROOT}/mediamtx.yml"

cat > "${GENERATED_ROOT}/environment.txt" <<EOF
SMARTPHONE_LAN_IP=${SMARTPHONE_LAN_IP}
CA_FILE=${PUBLIC_ROOT}/rootCA.pem
SERVER_CERT=${CERT_ROOT}/server.crt
SERVER_KEY=${CERT_ROOT}/server.key
EOF

echo "generated smartphone WebRTC assets for ${SMARTPHONE_LAN_IP}"
echo "CA certificate: ${PUBLIC_ROOT}/rootCA.pem"
echo "MediaMTX config: ${GENERATED_ROOT}/mediamtx.yml"
