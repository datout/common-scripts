#!/usr/bin/env bash
# debian-reinstall.sh
#
# Interactive Debian 12 / 13 VPS network reinstall wrapper.
# The actual reinstall is performed by leitbogioro/Tools InstallNET.sh.
# Upstream: https://github.com/leitbogioro/Tools
#
# WARNING: Reinstalling can erase the target system disk. Back up first.

set -Eeuo pipefail

UPSTREAM_URL="https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh"
TMP_DIR=""
INSTALLNET=""

info() { printf '\n[INFO] %s\n' "$*"; }
ok()   { printf '[ OK ] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

cleanup() {
    if [ -n "${TMP_DIR:-}" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

[ "$(id -u)" -eq 0 ] || die "请使用 root 运行此脚本。"

if command -v systemd-detect-virt >/dev/null 2>&1; then
    if systemd-detect-virt --container >/dev/null 2>&1; then
        die "检测到容器环境。DD / 网络重装应在 VPS/VM/物理机宿主系统中执行。"
    fi
fi

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64|amd64|aarch64|arm64) ;;
    *)
        warn "当前架构：$ARCH"
        warn "上游可能支持，但本包装脚本未对该架构做专项验证。"
        ;;
esac

download_file() {
    local url="$1"
    local out="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 --connect-timeout 15 "$url" -o "$out"
    elif command -v wget >/dev/null 2>&1; then
        wget --no-check-certificate -O "$out" "$url"
    else
        die "系统缺少 curl/wget。请先安装其中一个后再运行。"
    fi
}

printf '\n'
printf '============================================\n'
printf '       Debian 12 / 13 VPS 网络重装\n'
printf '============================================\n'
printf '当前系统: '
if [ -r /etc/os-release ]; then
    . /etc/os-release
    printf '%s\n' "${PRETTY_NAME:-unknown}"
else
    printf 'unknown\n'
fi
printf '当前架构: %s\n' "$ARCH"
printf '\n'
printf '此操作会重新安装系统，并可能清空系统盘数据。\n'
printf '实际 DD / 网络重装由 leitbogioro/Tools 的 InstallNET.sh 执行。\n'
printf '\n'

printf '选择目标 Debian 版本：\n'
printf '  1) Debian 13（推荐）\n'
printf '  2) Debian 12\n'
printf '  q) 退出\n'
printf '\n'

CHOICE=""
if [ -r /dev/tty ] && [ -w /dev/tty ]; then
    printf '请选择 [1]: ' > /dev/tty
    IFS= read -r CHOICE < /dev/tty || CHOICE=""
else
    die "没有可用的交互终端。请在 SSH/终端中直接运行。"
fi

case "${CHOICE:-1}" in
    1|"") DEBIAN_VERSION="13" ;;
    2)    DEBIAN_VERSION="12" ;;
    q|Q)  exit 0 ;;
    *)    die "无效选择：$CHOICE" ;;
esac

SSH_PORT=""
printf '新系统 SSH 端口 [22]: ' > /dev/tty
IFS= read -r SSH_PORT < /dev/tty || SSH_PORT=""
SSH_PORT="${SSH_PORT:-22}"

case "$SSH_PORT" in
    ''|*[!0-9]*) die "SSH 端口必须是数字。" ;;
esac
if [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
    die "SSH 端口必须在 1-65535 之间。"
fi

ROOT_PASSWORD=""
ROOT_PASSWORD_2=""
while :; do
    printf '设置新系统 root 密码: ' > /dev/tty
    IFS= read -r -s ROOT_PASSWORD < /dev/tty || ROOT_PASSWORD=""
    printf '\n' > /dev/tty

    [ -n "$ROOT_PASSWORD" ] || {
        warn "密码不能为空。"
        continue
    }

    printf '再次输入 root 密码: ' > /dev/tty
    IFS= read -r -s ROOT_PASSWORD_2 < /dev/tty || ROOT_PASSWORD_2=""
    printf '\n' > /dev/tty

    if [ "$ROOT_PASSWORD" = "$ROOT_PASSWORD_2" ]; then
        break
    fi

    warn "两次密码不一致，请重新输入。"
done
unset ROOT_PASSWORD_2

printf '\n即将执行：\n'
printf '  目标系统: Debian %s\n' "$DEBIAN_VERSION"
printf '  SSH 端口: %s\n' "$SSH_PORT"
printf '  CPU 架构: %s\n' "$ARCH"
printf '  root 密码: ********\n'
printf '  上游脚本: %s\n' "$UPSTREAM_URL"
printf '\n'
warn "继续后将进入系统重装流程，现有系统和数据可能被清除。"

CONFIRM=""
printf '确认已经备份，并继续重装？请输入 YES: ' > /dev/tty
IFS= read -r CONFIRM < /dev/tty || CONFIRM=""

[ "$CONFIRM" = "YES" ] || {
    ok "已取消，没有执行重装。"
    unset ROOT_PASSWORD
    exit 0
}

TMP_DIR="$(mktemp -d)"
INSTALLNET="$TMP_DIR/InstallNET.sh"

info "下载上游 InstallNET.sh"
download_file "$UPSTREAM_URL" "$INSTALLNET"
chmod 700 "$INSTALLNET"

[ -s "$INSTALLNET" ] || die "下载到的 InstallNET.sh 为空。"
grep -q 'InstallNET' "$INSTALLNET" || \
grep -q 'License: GPL' "$INSTALLNET" || \
die "下载内容不像 InstallNET.sh，已停止执行。"

ok "上游脚本下载完成。"
info "开始 Debian $DEBIAN_VERSION 重装流程"

bash "$INSTALLNET" \
    -debian "$DEBIAN_VERSION" \
    -port "$SSH_PORT" \
    -pwd "$ROOT_PASSWORD"

unset ROOT_PASSWORD
