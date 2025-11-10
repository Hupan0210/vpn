#!/usr/bin/env bash
# nlbwvpn — 一键部署 (final) + 自动通过 Telegram 发送 VLESS 链接与二维码
# Author: nlbw
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
exec > >(tee -a /root/deploy.log) 2>&1

# 彩色输出
say(){ echo -e "\033[1;32m$1\033[0m"; }

say "🚀 nlbwvpn Ultimate — 一键部署（交互式）"

# 交互输入
read -r -p "域名 (例 090110.xyz): " DOMAIN
[ -z "$DOMAIN" ] && { echo "域名不能为空"; exit 1; }
read -r -p "证书邮箱 (例 admin@gmail.com): " EMAIL
[ -z "$EMAIL" ] && { echo "邮箱不能为空"; exit 1; }
read -r -p "Telegram Bot Token (格式: 123:ABC...): " BOT_TOKEN
[ -z "$BOT_TOKEN" ] && { echo "Bot Token 不能为空"; exit 1; }
read -r -p "Telegram Chat ID (数字): " CHAT_ID
[ -z "$CHAT_ID" ] && { echo "Chat ID 不能为空"; exit 1; }
read -r -p "健康检测间隔秒 (默认300): " INTERVAL
CHECK_INTERVAL=${INTERVAL:-300}

UUID="$(cat /proc/sys/kernel/random/uuid)"
WS_PATH="/ws"

say "开始部署：DOMAIN=${DOMAIN}, UUID=${UUID}"

# 1) 系统依赖
say "安装系统依赖..."
apt update -y
apt install -y curl jq bc nginx certbot python3-certbot-nginx unzip openssl qrencode git || true

# 2) 安装 Xray（官方安装脚本）
if ! command -v xray >/dev/null 2>&1; then
  say "安装 Xray..."
  bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh)
fi

# 3) 伪装站点
say "配置伪装站点..."
mkdir -p /var/www/${DOMAIN}/html
cat > /var/www/${DOMAIN}/html/index.html <<HTML
<!doctype html><meta charset=utf-8><title>nlbwvpn</title>
<h1 style="text-align:center">Welcome to nlbwvpn 🚀</h1>
<p style="text-align:center">VLESS + WS + TLS 已部署成功。</p>
HTML
chmod -R 755 /var/www/${DOMAIN}/html

# 4) 临时 nginx 配置（用于 certbot webroot）
NG_CONF="/etc/nginx/sites-available/${DOMAIN}.conf"
ln -sf "$NG_CONF" "/etc/nginx/sites-enabled/${DOMAIN}.conf"
cat > "$NG_CONF" <<NG
server {
    listen 80;
    server_name ${DOMAIN};
    root /var/www/${DOMAIN}/html;
    location / { try_files \$uri \$uri/ =404; }
    location /.well-known/acme-challenge/ { root /var/www/${DOMAIN}/html; }
}
NG
nginx -t && systemctl restart nginx

# 5) 申请证书（webroot，避免修改 nginx 配置）
say "申请 Let's Encrypt 证书..."
certbot certonly --webroot -w /var/www/${DOMAIN}/html -d "${DOMAIN}" --email "${EMAIL}" --agree-tos --noninteractive || { echo "Certbot 失败，请确认 DNS A 记录已指向本 VPS"; exit 1; }
systemctl enable certbot.timer || true
systemctl start certbot.timer || true

# 6) 写 Xray 配置 (VLESS + WS)
say "写入 Xray 配置..."
mkdir -p /usr/local/etc/xray
cat > /usr/local/etc/xray/config.json <<JSON
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": 10000,
    "listen": "127.0.0.1",
    "protocol": "vless",
    "settings": { "clients": [{ "id": "${UUID}" }], "decryption": "none" },
    "streamSettings": { "network": "ws", "wsSettings": { "path": "${WS_PATH}" } }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
JSON

# Ensure xray auto-restart on crash
mkdir -p /etc/systemd/system/xray.service.d
cat > /etc/systemd/system/xray.service.d/restart.conf <<EOF
[Service]
Restart=always
RestartSec=3
EOF

systemctl daemon-reload || true
systemctl enable --now xray || true
systemctl restart xray || true

# 7) 最终 nginx (80->443, 443 -> ws proxy)
say "写入最终 nginx 配置..."
cat > "$NG_CONF" <<NG
server {
    listen 80;
    server_name ${DOMAIN};
    location /.well-known/acme-challenge/ { root /var/www/${DOMAIN}/html; }
    location / { return 301 https://\$host\$request_uri; }
}
server {
    listen 443 ssl http2;
    server_name ${DOMAIN};
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        root /var/www/${DOMAIN}/html;
        index index.html;
        try_files \$uri \$uri/ =404;
    }

    location ${WS_PATH} {
        proxy_redirect off;
        proxy_buffering off;
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NG
nginx -t && systemctl restart nginx

# 8) BBR 打开
say "启用 BBR..."
grep -q "net.ipv4.tcp_congestion_control" /etc/sysctl.conf || cat >> /etc/sysctl.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
EOF
sysctl -p || true

# 9) bbr-status.sh
say "写入 bbr-status.sh..."
cat > /usr/local/bin/bbr-status.sh <<'BBR'
#!/bin/bash
set -euo pipefail
LOG="/var/log/bbr-check.log"
DATE=$(date '+%F %T')
CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)
SPEED_BPS=$(curl -s "https://speed.cloudflare.com/__down?bytes=5000000" -o /dev/null -w '%{speed_download}' 2>/dev/null || echo 0)
MBPS=$(awk "BEGIN{printf \"%.2f\", ($SPEED_BPS*8)/1000000}")
echo "[$DATE] BBR=${CC} SPEED=${MBPS}Mbps (${SPEED_BPS} B/s)" | tee -a "$LOG"
# auto truncate if > 5MB
find /var/log -name "bbr-check.log" -size +5M -exec truncate -s 0 {} \; 2>/dev/null || true
BBR
chmod +x /usr/local/bin/bbr-status.sh

cat > /etc/systemd/system/bbr-status.service <<'SVCB'
[Unit]
Description=BBR status check
[Service]
Type=oneshot
ExecStart=/usr/local/bin/bbr-status.sh
SVCB
cat > /etc/systemd/system/bbr-status.timer <<'TM1'
[Unit]
Description=Run bbr-status weekly
[Timer]
OnCalendar=Mon *-*-* 03:00:00
Persistent=true
[Install]
WantedBy=timers.target
TM1
systemctl daemon-reload
systemctl enable --now bbr-status.timer

# 10) bbr-weekly-report.sh (friendly, MarkdownV2)
say "写入 bbr-weekly-report.sh..."
cat > /usr/local/bin/bbr-weekly-report.sh <<'WEEK'
#!/bin/bash
set -euo pipefail
LOG="/var/log/bbr-check.log"
API="https://api.telegram.org/bot${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
EXPIRY_DATE="2026-11-10"
if [ ! -f "$LOG" ]; then
  curl -s "${API}/sendMessage" -d chat_id="${CHAT_ID}" -d parse_mode="MarkdownV2" -d text="📊 每周BBR报告：暂无数据" >/dev/null
  exit 0
fi
AVG=$(awk -F' ' '/SPEED/ {sum+=substr($3,7); count++} END{ if(count>0) printf "%.2f", sum/count; else print "0" }' "$LOG")
MSG="📊 *每周BBR报告*\n主机: $(hostname)\n平均速度: ${AVG} Mbps\n\n到期提醒: ${EXPIRY_DATE}"
curl -s "${API}/sendMessage" -d chat_id="${CHAT_ID}" -d parse_mode="MarkdownV2" -d text="$MSG" >/dev/null || true
WEEK
chmod +x /usr/local/bin/bbr-weekly-report.sh

cat > /etc/systemd/system/bbr-weekly-report.service <<'SVCW'
[Unit]
Description=Weekly BBR report service
[Service]
Type=oneshot
ExecStart=/usr/local/bin/bbr-weekly-report.sh
SVCW
cat > /etc/systemd/system/bbr-weekly-report.timer <<'TMRW'
[Unit]
Description=Weekly BBR report timer
[Timer]
OnCalendar=Mon *-*-* 03:10:00
Persistent=true
[Install]
WantedBy=timers.target
TMRW
systemctl daemon-reload
systemctl enable --now bbr-weekly-report.timer

# 11) tg-control minimal (health + friendly)
say "写入 tg-control.sh..."
cat > /usr/local/bin/tg-control.sh <<'TG'
#!/usr/bin/env bash
set -euo pipefail
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
API="https://api.telegram.org/bot${BOT_TOKEN}"
CHECK_INTERVAL=${CHECK_INTERVAL}

send_msg() {
  txt="$1"
  # escape for MarkdownV2
  esc=$(echo "$txt" | sed 's/[][_*`~()<>#+=\-|{}.!]/\\&/g')
  curl -s "${API}/sendMessage" -d chat_id="${CHAT_ID}" -d parse_mode="MarkdownV2" -d text="$esc" >/dev/null || true
}

while true; do
  for svc in xray nginx; do
    if ! systemctl is-active "$svc" >/dev/null; then
      send_msg "⚠️ 服务 ${svc} 异常! 主机: $(hostname)"
    fi
  done
  sleep $CHECK_INTERVAL
done
TG
sed -i "s|\${BOT_TOKEN}|${BOT_TOKEN}|g" /usr/local/bin/tg-control.sh
sed -i "s|\${CHAT_ID}|${CHAT_ID}|g" /usr/local/bin/tg-control.sh
sed -i "s|\${CHECK_INTERVAL}|${CHECK_INTERVAL}|g" /usr/local/bin/tg-control.sh
chmod +x /usr/local/bin/tg-control.sh
cat > /etc/systemd/system/tg-control.service <<'SRV'
[Unit]
Description=Telegram health monitor
After=network.target
[Service]
ExecStart=/usr/local/bin/tg-control.sh
Restart=always
RestartSec=10
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
SRV
systemctl daemon-reload && systemctl enable --now tg-control.service

# 12) 生成 VLESS 链接与二维码，并用 Bot 发送到 Chat
say "生成 VLESS 链接与二维码..."
VLESS="vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "${WS_PATH}")#${DOMAIN}-ws"
echo "VLESS 链接: $VLESS"
qrencode -o /root/vless-qrcode.png "$VLESS" || true

# 发送文本和文件给 Telegram（两次重试机制）
say "把 VLESS 链接和二维码发到 Telegram 私聊..."
TELE_API="https://api.telegram.org/bot${BOT_TOKEN}"
# 发送文本（MarkdownV2）
TEXT_MSG="🎉 部署完成！\nVLESS 链接:\n\`${VLESS}\`"
curl -s -m 10 "${TELE_API}/sendMessage" -d chat_id="${CHAT_ID}" -d parse_mode="MarkdownV2" -d text="$TEXT_MSG" || true
# 发送二维码文件（如果存在）
if [ -f /root/vless-qrcode.png ]; then
  curl -s -F chat_id="${CHAT_ID}" -F caption="二维码（扫码导入）" -F document=@/root/vless-qrcode.png "${TELE_API}/sendDocument" >/dev/null 2>&1 || true
fi

say "部署与通知完成。登录 Telegram 查看消息（私聊）"
say "证书到期: $(openssl x509 -enddate -noout -in /etc/letsencrypt/live/${DOMAIN}/fullchain.pem | cut -d= -f2 || true)"
say "二维码路径: /root/vless-qrcode.png"
say "部署日志: /root/deploy.log"