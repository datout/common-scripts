# 常用脚本

个人常用 Linux / VPS 运维脚本合集。

目前主要包括：

1. **Linux 安全更新 / 内核更新**
2. **Debian 12 / 13 VPS DD / 网络重装**

仓库：

```text
https://github.com/datout/common-scripts
```

---

## 一条命令打开菜单

以后最方便直接运行：

```bash
curl -fsSL https://raw.githubusercontent.com/datout/common-scripts/main/menu.sh | bash
```

菜单：

```text
==============================
          常用脚本
==============================
1) Linux 安全更新 / 内核更新
2) Debian 12 / 13 DD 重装
q) 退出
```

---

## 仓库结构

```text
common-scripts/
├── README.md
├── menu.sh
└── linux/
    ├── linux-security-update.sh
    └── debian-reinstall.sh
```

---

# 1. Linux 安全更新 / 内核更新

脚本：

```text
linux/linux-security-update.sh
```

用于常见 Linux VPS 的日常安全更新。

### 主要支持

- Debian / Ubuntu
- RHEL / Rocky Linux / AlmaLinux / CentOS / Oracle Linux
- Fedora / Amazon Linux
- openSUSE / SLES
- Arch Linux
- Alpine Linux

### 主要功能

- 自动识别 Linux 发行版
- 自动识别包管理器
- 升级已安装软件和内核
- Debian 12 / 13 检查 Security / Updates 软件源
- Debian 缺少官方安全源时自动补齐
- 检查 systemd failed units
- 检查 Nginx 配置
- 检查 Docker daemon / 容器
- 判断是否需要重启
- 检测到需要重启时由用户选择 `y/N`
- 默认不删除旧内核
- 默认不跨 Linux 大版本升级
- Debian 12 / 13 额外检查 CVE-2026-98432 修复状态

## 日常使用

```bash
curl -fsSL https://raw.githubusercontent.com/datout/common-scripts/main/linux/linux-security-update.sh | bash
```

如果更新后需要重启，会询问：

```text
是否现在立即重启？ [y/N]:
```

## 只检查，不升级

```bash
curl -fsSL https://raw.githubusercontent.com/datout/common-scripts/main/linux/linux-security-update.sh | bash -s -- --check
```

## APT 系 full-upgrade

```bash
curl -fsSL https://raw.githubusercontent.com/datout/common-scripts/main/linux/linux-security-update.sh | bash -s -- --full-upgrade
```

## 检测到需要重启时自动重启

```bash
curl -fsSL https://raw.githubusercontent.com/datout/common-scripts/main/linux/linux-security-update.sh | bash -s -- --reboot
```

---

# 2. Debian 12 / 13 VPS DD / 网络重装

脚本：

```text
linux/debian-reinstall.sh
```

这是本仓库维护的**交互式包装脚本**。

实际 DD / 网络重装由第三方项目完成：

```text
https://github.com/leitbogioro/Tools
```

实际调用：

```text
Linux_reinstall/InstallNET.sh
```

包装脚本不会在本仓库保存一份固定版本的 `InstallNET.sh`，而是在每次执行时直接从上游 GitHub 获取最新版。

这样可以：

- 避免自己维护第三方数千行 DD 脚本
- 避免本仓库保存过期版本
- 保持自己的入口命令长期不变
- 在执行前交互选择 Debian 12 / 13
- 自己输入 SSH 端口和 root 密码
- 最后必须输入 `YES` 二次确认才真正执行

上游目前支持 Debian 13，Debian 12 也可显式指定。

## 运行

```bash
curl -fsSL https://raw.githubusercontent.com/datout/common-scripts/main/linux/debian-reinstall.sh | bash
```

脚本会依次询问：

```text
选择目标 Debian 版本：
1) Debian 13（推荐）
2) Debian 12

新系统 SSH 端口 [22]:

设置新系统 root 密码:
再次输入 root 密码:

确认已经备份，并继续重装？请输入 YES:
```

只有最后明确输入：

```text
YES
```

才会进入重装流程。

## 重要警告

**DD / 网络重装可能清空系统盘。**

执行前请确认：

- 重要文件已经备份
- VPS 控制台 / VNC / Serial Console 可用
- VPS 支持网络重装
- IP、网关、网络方式没有特殊限制
- 已记录现有 Xray / 3x-ui / Docker / Nginx 等配置

第三方 `InstallNET.sh` 会以 root 权限运行，并修改磁盘、引导、网络和系统文件。

---

# 3. DD 完成后的推荐操作

重新 SSH 登录新系统后，先运行：

```bash
curl -fsSL https://raw.githubusercontent.com/datout/common-scripts/main/linux/linux-security-update.sh | bash
```

然后检查当前内核：

```bash
uname -r
```

检查 systemd：

```bash
systemctl --failed
```

如果安装了 Nginx：

```bash
nginx -t
```

如果安装了 Docker：

```bash
docker ps
```

---

# 4. 脚本来源和维护范围

本仓库自己维护：

```text
menu.sh
linux/linux-security-update.sh
linux/debian-reinstall.sh
```

其中 `debian-reinstall.sh` 只是第三方 `InstallNET.sh` 的交互包装和入口。

实际 DD 能力来自：

```text
leitbogioro/Tools
```

上游 `InstallNET.sh` 文件标明 GPL License，并保留原作者及历次修改者信息。本仓库不重新发布完整 `InstallNET.sh`，而是在用户确认后直接下载其 GitHub 上游版本。

---

# 5. 本地维护

本地建议目录：

```text
D:\git\common-scripts
```

以后修改完成后：

```bash
cd /d/git/common-scripts
git add -A
git commit -m "update scripts"
git push origin main
```

---

> 提醒：系统更新和 DD 重装都属于高权限操作。执行网络上的 root 脚本前，建议先查看源码，并确认下载地址仍然指向可信上游。
