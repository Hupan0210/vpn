#!/usr/bin/env bash
# nlbwvpn Install Wrapper
# Author: nlbw
# GitHub: https://github.com/Hupan0210/vpn
set -euo pipefail

# ====== 彩色输出 ======
green(){ echo -e "\033[1;32m$1\033[0m"; }
red(){ echo -e "\033[1;31m$1\033[0m"; }
yellow(){ echo -e "\033[1;33m$1\033[0m"; }
blue(){ echo -e "\033[1;34m$1\033[0m"; }

# ====== 权限检测 ======
if [ "$EUID" -ne 0 ]; then
  red "❌ 请使用 root 用户运行此脚本"
  echo "执行：sudo -i"
  exit 1
fi

# ====== 网络检测 ======
if ! ping -c1 -W1 google.com >/dev/null 2>&1 && ! ping -c1 -W1 1.1.1.1 >/dev/null 2>&1; then
  red "❌ 网络连接异常，请检查 VPS 网络"
  exit 1
fi

# ====== 系统检测 ======
if [ -f /etc/debian_version ]; then
  OS="Debian"
elif [ -f /etc/lsb-release ] && grep -q "Ubuntu" /etc/lsb-release; then
  OS="Ubuntu"
else
  red "❌ 不支持的系统，请使用 Debian 或 Ubuntu"
  exit 1
fi

# ====== 环境准备 ======
green "🧩 检测系统：$OS"
yellow "更新系统并安装依赖..."

apt update -y && apt install -y curl || {
  red "❌ apt 安装失败，请检查软件源"
  exit 1
}

# ====== 下载安装主脚本 ======
URL="https://raw.githubusercontent.com/Hupan0210/vpn/main/nlbwvpn.sh"
DEST="/tmp/nlbwvpn.sh"

green "⬇️ 正在下载主安装脚本..."
if ! curl -fsSL "$URL" -o "$DEST"; then
  red "❌ 下载失败，请检查 GitHub 网络或仓库链接"
  exit 1
fi
chmod +x "$DEST"

# ====== 执行脚本 ======
green "🚀 启动 nlbwvpn 一键部署..."
sleep 1
bash "$DEST"

# ====== 成功提示 ======
green "✅ nlbwvpn 安装脚本执行完毕"
yellow "📄 详细日志：/root/deploy.log"
echo ""
blue "👉 部署完成后请到 Telegram 查看推送的 VLESS 链接与二维码"
