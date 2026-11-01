#!/usr/bin/env bash
set -Eeuo pipefail

RAW_BASE="https://raw.githubusercontent.com/datout/common-scripts/main"

fetch_run() {
    local path="$1"
    shift || true

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "${RAW_BASE}/${path}" | bash -s -- "$@"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "${RAW_BASE}/${path}" | bash -s -- "$@"
    else
        printf '[FAIL] 需要 curl 或 wget。\n' >&2
        exit 1
    fi
}

printf '\n'
printf '==============================\n'
printf '          常用脚本\n'
printf '==============================\n'
printf '1) Linux 安全更新 / 内核更新\n'
printf '2) Debian 12 / 13 DD 重装\n'
printf 'q) 退出\n'
printf '\n'

ANSWER=""
if [ -r /dev/tty ] && [ -w /dev/tty ]; then
    printf '请选择: ' > /dev/tty
    IFS= read -r ANSWER < /dev/tty || ANSWER=""
else
    printf '[FAIL] 没有可用的交互终端。\n' >&2
    exit 1
fi

case "$ANSWER" in
    1) fetch_run "linux/linux-security-update.sh" ;;
    2) fetch_run "linux/debian-reinstall.sh" ;;
    q|Q) exit 0 ;;
    *) printf '[FAIL] 无效选择。\n' >&2; exit 1 ;;
esac
