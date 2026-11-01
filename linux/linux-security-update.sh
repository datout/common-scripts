#!/usr/bin/env bash
# linux-security-update.sh
#
# 通用 Linux 安全更新 / 内核更新脚本
#
# 支持的主要发行版：
#   - Debian / Ubuntu 及常见 Debian 系衍生版
#   - RHEL / Rocky Linux / AlmaLinux / CentOS / Oracle Linux / Fedora / Amazon Linux
#   - openSUSE / SLES
#   - Arch Linux
#   - Alpine Linux
#
# 设计原则：
#   - 自动识别系统、架构和包管理器
#   - 不跨发行版大版本升级
#   - 不强制安装某个固定内核 flavor
#   - 不自动删除旧内核
#   - 默认不自动重启
#   - Debian 12/13 缺少官方 security/updates 源时可自动补齐
#   - Ubuntu/其他发行版只检查软件源，不擅自重写发行版配置
#
# 用法：
#   bash linux-security-update.sh
#   bash linux-security-update.sh --check
#   bash linux-security-update.sh --full-upgrade
#   bash linux-security-update.sh --reboot
#   bash linux-security-update.sh --no-repo-repair
#
# 重启行为：
#   默认：如检测到需要重启，会在终端中询问是否立即重启。
#   --reboot：无需询问，检测到需要重启时自动重启。
#
# CVE-2026-98432：
#   Debian 12/13 可额外进行本地版本判断。
#   其他发行版不硬编码固定版本，避免把 Debian 的版本号错误套用到其他系统。
#
# 最后更新：2026-11-01

set -Eeuo pipefail

SCRIPT_NAME="${0##*/}"
CHECK_ONLY=0
DO_REBOOT=0
FULL_UPGRADE=0
REPO_REPAIR=1

info() { printf '\n[INFO] %s\n' "$*"; }
ok()   { printf '[ OK ] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage:
  $SCRIPT_NAME
  $SCRIPT_NAME --check
  $SCRIPT_NAME --full-upgrade
  $SCRIPT_NAME --reboot
  $SCRIPT_NAME --no-repo-repair

Options:
  --check             仅检查可更新内容和当前状态，不安装软件包
  --full-upgrade      APT 系使用 full-upgrade；其他系统仍使用其标准完整更新方式
  --reboot            如检测到需要重启则自动重启，不再交互询问
  --no-repo-repair    不自动补 Debian 缺失的 security / updates 官方源
  -h, --help          显示帮助

默认行为：
  1. 自动识别 Linux 发行版
  2. 刷新软件仓库元数据
  3. 使用发行版自己的包管理器升级已安装软件和内核
  4. 检查 systemd / Nginx / Docker
  5. 判断是否需要重启；需要时由你在脚本中选择是否立即重启
  6. 不删除旧内核、不自动跨大版本升级
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --check) CHECK_ONLY=1 ;;
        --full-upgrade) FULL_UPGRADE=1 ;;
        --reboot) DO_REBOOT=1 ;;
        --no-repo-repair) REPO_REPAIR=0 ;;
        -h|--help) usage; exit 0 ;;
        *) die "未知参数: $1" ;;
    esac
    shift
done

trap 'warn "脚本在第 $LINENO 行停止。未执行自动清理或回滚。"' ERR

[ "$(id -u)" -eq 0 ] || die "请使用 root 运行：sudo bash $SCRIPT_NAME"
[ -r /etc/os-release ] || die "找不到 /etc/os-release，无法安全识别系统。"

# shellcheck disable=SC1091
. /etc/os-release

OS_ID="${ID:-unknown}"
OS_NAME="${PRETTY_NAME:-Linux}"
OS_VERSION="${VERSION_ID:-unknown}"
OS_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
OS_LIKE="${ID_LIKE:-}"
ARCH="$(uname -m)"
RUNNING_KERNEL="$(uname -r)"
PKG_FAMILY="unknown"
PKG_MANAGER="unknown"
IS_CONTAINER=0

if [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then
    IS_CONTAINER=1
elif command -v systemd-detect-virt >/dev/null 2>&1; then
    if systemd-detect-virt --container >/dev/null 2>&1; then
        IS_CONTAINER=1
    fi
fi

contains_word() {
    case " $1 " in
        *" $2 "*) return 0 ;;
        *) return 1 ;;
    esac
}

detect_family() {
    if [ "$OS_ID" = "debian" ] || [ "$OS_ID" = "ubuntu" ] || \
       contains_word "$OS_LIKE" "debian" || command -v apt-get >/dev/null 2>&1; then
        PKG_FAMILY="apt"
        PKG_MANAGER="apt"
        return
    fi

    if [ "$OS_ID" = "alpine" ] || command -v apk >/dev/null 2>&1; then
        PKG_FAMILY="apk"
        PKG_MANAGER="apk"
        return
    fi

    if [ "$OS_ID" = "arch" ] || contains_word "$OS_LIKE" "arch" || \
       command -v pacman >/dev/null 2>&1; then
        PKG_FAMILY="pacman"
        PKG_MANAGER="pacman"
        return
    fi

    if [ "$OS_ID" = "opensuse-tumbleweed" ] || [ "$OS_ID" = "opensuse-leap" ] || \
       [ "$OS_ID" = "sles" ] || [ "$OS_ID" = "sled" ] || \
       contains_word "$OS_LIKE" "suse" || command -v zypper >/dev/null 2>&1; then
        PKG_FAMILY="zypper"
        PKG_MANAGER="zypper"
        return
    fi

    if command -v dnf >/dev/null 2>&1; then
        PKG_FAMILY="dnf"
        PKG_MANAGER="dnf"
        return
    fi

    if command -v yum >/dev/null 2>&1; then
        PKG_FAMILY="yum"
        PKG_MANAGER="yum"
        return
    fi
}

detect_family
[ "$PKG_FAMILY" != "unknown" ] || die "暂不支持此系统或未找到受支持的包管理器。"

info "系统信息"
printf '  系统:           %s\n' "$OS_NAME"
printf '  ID:             %s\n' "$OS_ID"
printf '  版本:           %s\n' "$OS_VERSION"
printf '  Codename:       %s\n' "${OS_CODENAME:-N/A}"
printf '  架构:           %s\n' "$ARCH"
printf '  包管理器:       %s\n' "$PKG_MANAGER"
printf '  当前内核:       %s\n' "$RUNNING_KERNEL"
if [ "$IS_CONTAINER" -eq 1 ]; then
    printf '  环境:           Container\n'
    warn "检测到容器环境；容器自身通常不能更新宿主机内核。"
else
    printf '  环境:           Host / VM / VPS\n'
fi

# --------------------------
# APT / Debian / Ubuntu
# --------------------------

apt_source_text() {
    {
        [ -f /etc/apt/sources.list ] && cat /etc/apt/sources.list
        if [ -d /etc/apt/sources.list.d ]; then
            find /etc/apt/sources.list.d -maxdepth 1 -type f \
                \( -name '*.list' -o -name '*.sources' \) \
                -exec cat {} + 2>/dev/null || true
        fi
    } | sed -E '/^[[:space:]]*#/d;/^[[:space:]]*$/d'
}

apt_has_suite() {
    apt_source_text | grep -Eq "(^|[[:space:]])${1}([[:space:]]|$)"
}

repair_debian_repositories() {
    [ "$OS_ID" = "debian" ] || return 0

    local codename security_suite updates_suite auto_file
    codename="$OS_CODENAME"

    case "${OS_VERSION%%.*}" in
        12)
            codename="${codename:-bookworm}"
            ;;
        13)
            codename="${codename:-trixie}"
            ;;
        *)
            warn "Debian $OS_VERSION 不在自动补源白名单中；不会修改软件源。"
            return 0
            ;;
    esac

    security_suite="${codename}-security"
    updates_suite="${codename}-updates"
    auto_file="/etc/apt/sources.list.d/99-linux-security-update.list"

    info "Debian 官方更新源检查"

    if apt_has_suite "$security_suite"; then
        ok "$security_suite 已配置。"
    else
        warn "缺少 $security_suite。"
        if [ "$CHECK_ONLY" -eq 0 ] && [ "$REPO_REPAIR" -eq 1 ]; then
            mkdir -p /etc/apt/sources.list.d
            printf 'deb https://security.debian.org/debian-security %s main\n' \
                "$security_suite" >> "$auto_file"
            ok "已补充 $security_suite。"
        fi
    fi

    if apt_has_suite "$updates_suite"; then
        ok "$updates_suite 已配置。"
    else
        warn "缺少 $updates_suite。"
        if [ "$CHECK_ONLY" -eq 0 ] && [ "$REPO_REPAIR" -eq 1 ]; then
            mkdir -p /etc/apt/sources.list.d
            printf 'deb https://deb.debian.org/debian %s main\n' \
                "$updates_suite" >> "$auto_file"
            ok "已补充 $updates_suite。"
        fi
    fi
}

check_ubuntu_security_repository() {
    [ "$OS_ID" = "ubuntu" ] || return 0
    [ -n "$OS_CODENAME" ] || return 0

    local security_suite="${OS_CODENAME}-security"

    info "Ubuntu Security 源检查"
    if apt_has_suite "$security_suite"; then
        ok "$security_suite 已配置。"
    else
        warn "没有检测到 $security_suite。"
        warn "为避免破坏云镜像、区域镜像、Ubuntu Pro/ESM 配置，脚本不会自动重写 Ubuntu 软件源。"
    fi
}

apt_refresh() {
    repair_debian_repositories
    check_ubuntu_security_repository
    info "刷新 APT 软件包索引"
    apt-get update
}

apt_show_updates() {
    info "可升级软件包"
    local output
    output="$(apt list --upgradable 2>/dev/null | sed '1d' || true)"
    if [ -n "$output" ]; then
        printf '%s\n' "$output"
    else
        ok "没有检测到可升级软件包。"
    fi
}

apt_upgrade_system() {
    if [ "$FULL_UPGRADE" -eq 1 ]; then
        info "执行 APT full-upgrade"
        DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y
    else
        info "执行 APT upgrade（允许安装新依赖，不主动删除软件包）"
        DEBIAN_FRONTEND=noninteractive apt-get upgrade --with-new-pkgs -y
    fi
}

# --------------------------
# DNF / YUM
# --------------------------

dnf_refresh_and_show() {
    info "检查 DNF 更新"
    set +e
    dnf -q check-update --refresh
    local rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
        ok "没有检测到可升级软件包。"
    elif [ "$rc" -eq 100 ]; then
        ok "检测到可升级软件包。"
    else
        die "dnf check-update 失败，退出码：$rc"
    fi
}

dnf_upgrade_system() {
    info "执行 DNF 系统更新"
    dnf -y upgrade --refresh
}

yum_refresh_and_show() {
    info "检查 YUM 更新"
    set +e
    yum -q check-update
    local rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
        ok "没有检测到可升级软件包。"
    elif [ "$rc" -eq 100 ]; then
        ok "检测到可升级软件包。"
    else
        die "yum check-update 失败，退出码：$rc"
    fi
}

yum_upgrade_system() {
    info "执行 YUM 系统更新"
    yum -y update
}

# --------------------------
# Zypper
# --------------------------

zypper_refresh_and_show() {
    info "刷新 Zypper 仓库"
    zypper --non-interactive refresh

    info "可升级软件包"
    set +e
    zypper --non-interactive list-updates
    local rc=$?
    set -e
    [ "$rc" -eq 0 ] || warn "zypper list-updates 返回退出码 $rc。"
}

zypper_upgrade_system() {
    if [ "$OS_ID" = "opensuse-tumbleweed" ]; then
        info "检测到 openSUSE Tumbleweed，执行官方滚动升级方式 zypper dup"
        zypper --non-interactive dup --no-allow-vendor-change
    else
        info "执行 Zypper 系统更新"
        zypper --non-interactive update
    fi
}

# --------------------------
# Pacman / Arch
# --------------------------

pacman_show_updates() {
    info "检查 Pacman 更新"

    if command -v checkupdates >/dev/null 2>&1; then
        local output
        output="$(checkupdates 2>/dev/null || true)"
        if [ -n "$output" ]; then
            printf '%s\n' "$output"
        else
            ok "没有检测到可升级软件包。"
        fi
    else
        warn "未安装 checkupdates（pacman-contrib）。"
        warn "为了避免 Arch 的 partial upgrade 风险，--check 模式不会单独执行 pacman -Sy。"
        local output
        output="$(pacman -Qu 2>/dev/null || true)"
        if [ -n "$output" ]; then
            printf '%s\n' "$output"
            warn "以上结果基于当前本地软件包数据库，可能不是最新仓库状态。"
        else
            ok "当前本地数据库未显示可升级软件包。"
        fi
    fi
}

pacman_upgrade_system() {
    info "执行 Pacman 完整系统更新"
    pacman -Syu --noconfirm
}

# --------------------------
# APK / Alpine
# --------------------------

apk_refresh_and_show() {
    info "刷新 APK 索引"
    apk update

    info "可升级软件包"
    local output
    output="$(apk version -l '<' 2>/dev/null || true)"
    if [ -n "$output" ]; then
        printf '%s\n' "$output"
    else
        ok "没有检测到可升级软件包。"
    fi
}

apk_upgrade_system() {
    info "执行 APK 系统更新"
    apk upgrade
}

# --------------------------
# CVE-2026-98432 Debian check
# --------------------------

debian_running_kernel_pkg_version() {
    local pkg="linux-image-$(uname -r)"
    dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || true
}

debian_cve_fixed_threshold() {
    local version_major="${OS_VERSION%%.*}"
    local kernel
    kernel="$(uname -r)"

    case "$version_major:$kernel" in
        12:6.1.*)  printf '%s\n' "6.1.190-1" ;;
        12:6.12.*) printf '%s\n' "6.12.113-1~deb12u1" ;;
        13:6.12.*) printf '%s\n' "6.12.113-1" ;;
        *)          printf '%s\n' "" ;;
    esac
}

check_cve_2026_98432() {
    [ "$OS_ID" = "debian" ] || return 0

    local run_ver threshold
    run_ver="$(debian_running_kernel_pkg_version)"
    threshold="$(debian_cve_fixed_threshold)"

    info "CVE-2026-98432（Debian 本地版本检查）"

    if [ -z "$threshold" ]; then
        warn "当前 Debian/内核分支没有内置固定版本阈值；不做武断判断。"
        return 0
    fi

    if [ -z "$run_ver" ]; then
        warn "当前运行内核无法映射到 Debian linux-image 包；可能是自定义/宿主机内核。"
        return 0
    fi

    printf '  当前运行内核包版本: %s\n' "$run_ver"
    printf '  Debian 修复阈值:     %s\n' "$threshold"

    if dpkg --compare-versions "$run_ver" ge "$threshold"; then
        ok "当前正在运行的 Debian 内核已达到该 CVE 的修复版本。"
    else
        warn "当前正在运行的 Debian 内核低于该 CVE 的修复版本。"
        warn "如果新内核已经安装，通常需要重启后才会真正生效。"
    fi
}

# --------------------------
# Generic reboot detection
# --------------------------

latest_modules_kernel() {
    [ -d /usr/lib/modules ] || return 0
    find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d \
        -printf '%f\n' 2>/dev/null | sort -V | tail -n 1
}

version_gt() {
    local a="$1" b="$2"
    [ "$a" != "$b" ] || return 1
    [ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -n 1)" = "$a" ]
}

detect_reboot_required() {
    REBOOT_REQUIRED=0
    REBOOT_REASONS=()

    if [ -f /var/run/reboot-required ] || [ -f /run/reboot-required ]; then
        REBOOT_REQUIRED=1
        REBOOT_REASONS+=("系统创建了 reboot-required 标记")
    fi

    if [ "$PKG_FAMILY" = "dnf" ] || [ "$PKG_FAMILY" = "yum" ]; then
        if command -v needs-restarting >/dev/null 2>&1; then
            set +e
            needs-restarting -r >/dev/null 2>&1
            local rc=$?
            set -e
            if [ "$rc" -ne 0 ]; then
                REBOOT_REQUIRED=1
                REBOOT_REASONS+=("needs-restarting 检测到需要重启")
            fi
        elif command -v dnf >/dev/null 2>&1; then
            set +e
            dnf needs-restarting -r >/dev/null 2>&1
            local rc=$?
            set -e
            if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
                :
            elif [ "$rc" -ne 0 ]; then
                REBOOT_REQUIRED=1
                REBOOT_REASONS+=("dnf needs-restarting 检测到需要重启")
            fi
        fi
    fi

    local latest
    latest="$(latest_modules_kernel || true)"

    if [ -n "$latest" ] && [ "$latest" != "$RUNNING_KERNEL" ]; then
        if version_gt "$latest" "$RUNNING_KERNEL"; then
            REBOOT_REQUIRED=1
            REBOOT_REASONS+=("已安装较新的内核模块：$latest；当前运行：$RUNNING_KERNEL")
        fi
    fi
}

# --------------------------
# Service checks
# --------------------------

post_checks() {
    info "更新后检查"

    if command -v systemctl >/dev/null 2>&1 && [ "$IS_CONTAINER" -eq 0 ]; then
        local failed
        failed="$(systemctl --failed --no-legend 2>/dev/null || true)"
        if [ -n "$failed" ]; then
            warn "存在 failed systemd units："
            printf '%s\n' "$failed"
        else
            ok "没有 failed systemd units。"
        fi
    fi

    if command -v nginx >/dev/null 2>&1; then
        if nginx -t; then
            ok "Nginx 配置检查通过。"
        else
            warn "Nginx 配置检查失败。"
        fi
    fi

    if command -v docker >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then
            ok "Docker daemon 正常响应。"
            docker ps --format 'table {{.Names}}\t{{.Status}}' || true
        else
            warn "检测到 Docker 命令，但 Docker daemon 没有正常响应。"
        fi
    fi
}

# --------------------------
# Main
# --------------------------

case "$PKG_FAMILY" in
    apt)
        apt_refresh
        apt_show_updates
        if [ "$CHECK_ONLY" -eq 0 ]; then
            apt_upgrade_system
        fi
        ;;
    dnf)
        dnf_refresh_and_show
        if [ "$CHECK_ONLY" -eq 0 ]; then
            dnf_upgrade_system
        fi
        ;;
    yum)
        yum_refresh_and_show
        if [ "$CHECK_ONLY" -eq 0 ]; then
            yum_upgrade_system
        fi
        ;;
    zypper)
        zypper_refresh_and_show
        if [ "$CHECK_ONLY" -eq 0 ]; then
            zypper_upgrade_system
        fi
        ;;
    pacman)
        if [ "$CHECK_ONLY" -eq 1 ]; then
            pacman_show_updates
        else
            pacman_upgrade_system
        fi
        ;;
    apk)
        apk_refresh_and_show
        if [ "$CHECK_ONLY" -eq 0 ]; then
            apk_upgrade_system
        fi
        ;;
    *)
        die "内部错误：未知包管理器类型 $PKG_FAMILY"
        ;;
esac

check_cve_2026_98432

if [ "$CHECK_ONLY" -eq 1 ]; then
    printf '\n[INFO] 检查模式完成：没有安装或升级软件包。\n'
    exit 0
fi

# 刷新一次运行状态变量；当前内核在 reboot 前通常不会改变。
RUNNING_KERNEL="$(uname -r)"

post_checks
detect_reboot_required

info "重启判断"
printf '  当前运行内核: %s\n' "$RUNNING_KERNEL"

if [ "$REBOOT_REQUIRED" -eq 1 ]; then
    warn "检测到系统需要或建议重启。"
    for reason in "${REBOOT_REASONS[@]}"; do
        printf '  - %s\n' "$reason"
    done

    if [ "$IS_CONTAINER" -eq 1 ]; then
        warn "当前为容器环境，不会从容器内部重启宿主机。"
    elif [ "$DO_REBOOT" -eq 1 ]; then
        info "正在重启系统..."
        sync
        reboot
    else
        printf '\n'
        REBOOT_ANSWER=""

        # 使用 /dev/tty 读取，避免 curl ... | bash 时 stdin 被管道占用。
        if [ -r /dev/tty ] && [ -w /dev/tty ]; then
            printf '是否现在立即重启？ [y/N]: ' > /dev/tty
            IFS= read -r REBOOT_ANSWER < /dev/tty || REBOOT_ANSWER=""
        else
            warn "当前没有可用的交互终端，默认不自动重启。"
        fi

        case "$REBOOT_ANSWER" in
            y|Y|yes|YES|Yes)
                info "正在重启系统..."
                sync
                reboot
                ;;
            *)
                ok "已选择暂不重启。"
                printf '稍后准备好时执行：\n  reboot\n'
                printf '\n重启后可再次检查：\n  bash %s --check\n' "$SCRIPT_NAME"
                ;;
        esac
    fi
else
    ok "没有检测到明确的重启需求。"
fi

printf '\n[ OK ] Linux 更新流程完成。\n'
