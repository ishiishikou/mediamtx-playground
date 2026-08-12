#!/bin/sh
set -eu

WORKSPACE_ROOT="${1:-tmp/smartphone}"

print_repair_hint() {
  cat >&2 <<EOF
スマートフォン検証用ワークスペースにroot所有または書き込み不可のパスがあります:
  ${WORKSPACE_ROOT}

正規のstart.ps1経路ではWSLの現在ユーザーでこのディレクトリを作成します。
過去にdocker composeを直接実行した場合などに、Dockerがbind元をrootで作成した可能性があります。

所有者を現在のWSLユーザーへ戻してから再実行してください:
  sudo chown -R \"\$(id -u):\$(id -g)\" "${WORKSPACE_ROOT}"
EOF
}

if [ -e "${WORKSPACE_ROOT}" ]; then
  if [ "$(stat -c '%u' "${WORKSPACE_ROOT}")" = "0" ]; then
    print_repair_hint
    exit 73
  fi

  root_owned_path="$(find "${WORKSPACE_ROOT}" -xdev -uid 0 -print -quit 2>/dev/null || true)"
  if [ -n "${root_owned_path}" ]; then
    echo "root所有のパスを検出しました: ${root_owned_path}" >&2
    print_repair_hint
    exit 73
  fi
fi

mkdir -p \
  "${WORKSPACE_ROOT}/certs/ca" \
  "${WORKSPACE_ROOT}/public" \
  "${WORKSPACE_ROOT}/generated"

for path in \
  "${WORKSPACE_ROOT}" \
  "${WORKSPACE_ROOT}/certs" \
  "${WORKSPACE_ROOT}/certs/ca" \
  "${WORKSPACE_ROOT}/public" \
  "${WORKSPACE_ROOT}/generated"
do
  if [ ! -w "${path}" ]; then
    owner="$(stat -c '%U:%G (%u:%g)' "${path}" 2>/dev/null || echo unknown)"
    echo "書き込みできないパスを検出しました: ${path} owner=${owner}" >&2
    print_repair_hint
    exit 73
  fi
done

printf 'smartphone workspace ready: %s (uid=%s gid=%s)\n' \
  "${WORKSPACE_ROOT}" "$(id -u)" "$(id -g)"
