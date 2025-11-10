<p align="center">
  <a href="https://raw.githubusercontent.com/Hupan0210/vpn/main/install.sh" target="_blank">
    <img src="https://img.shields.io/badge/🟢%20一键安装-nlbwvpn-success?style=for-the-badge&logo=gnubash&logoColor=white" alt="一键安装 nlbwvpn">
  </a>
</p>

<h1 align="center">🚀 nlbwvpn — 一键部署 VLESS + WS + TLS + Telegram</h1>

<p align="center">
  <img src="https://img.shields.io/badge/Author-nlbw-blueviolet?style=for-the-badge">
  <img src="https://img.shields.io/badge/Built%20With-Bash-green?style=for-the-badge&logo=gnu-bash">
  <img src="https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge">
  <img src="https://img.shields.io/badge/Platform-Debian%20%7C%20Ubuntu-orange?style=for-the-badge&logo=linux">
</p>

<p align="center">
  <a href="https://raw.githubusercontent.com/Hupan0210/vpn/main/nlbwvpn.sh">
    <img src="https://img.shields.io/badge/💾%20立即安装-nlbwvpn.sh-red?style=for-the-badge">
  </a>
</p>

---

## ✨ 项目简介

**`nlbwvpn`** 是一个全自动化的 VPN 部署脚本，专为个人 VPS 打造。  
支持 **VLESS + WebSocket + TLS**，并通过 Telegram 自动发送配置链接与二维码。  
一键安装，无需手动配置 Xray / Nginx / Certbot / BBR。

---

## 🧠 功能亮点

- ✅ 自动安装 Xray (VLESS + WS + TLS)  
- ✅ 自动申请 Let’s Encrypt 证书（Certbot）  
- ✅ 自动配置 Nginx 伪装站点与反向代理  
- ✅ 自动启用 BBR TCP 加速  
- ✅ 自动生成 VLESS 链接与二维码（`/root/vless-qrcode.png`）  
- ✅ 自动推送到 Telegram（文本 + 二维码）  
- ✅ 健康检测与 Telegram 告警（systemd 服务）  
- ✅ 每周 Telegram 周报（BBR 速率 / 证书到期提醒）  
- ✅ 支持一键卸载（`uninstall` 参数）  
- ✅ 随机化或自定义 WebSocket 路径

---

## 🚀 快速使用（Usage）

> **注意**：在执行前，请先把你的域名的 **A 记录** 指向 VPS 公网 IP 并等待 DNS 生效。

### 一键安装（推荐）
在任何支持 `bash` 的终端以 root 身份运行：

```bash
# 切换到 root 用户（必要）
sudo -i

# 执行一键安装（interactive）
bash <(curl -Ls https://raw.githubusercontent.com/Hupan0210/vpn/main/install.sh)

脚本会以交互方式询问：

域名（例如 vpn.example.com）

证书邮箱（例如 admin@example.com）

Telegram Bot Token（从 @BotFather 获得）

Telegram Chat ID（纯数字，使用 @userinfobot 可查询）

健康检测间隔（秒）（默认 300）

卸载

若想卸载（删除 systemd 服务、配置与生成文件），请运行：

sudo -i
bash <(curl -Ls https://raw.githubusercontent.com/Hupan0210/vpn/main/nlbwvpn.sh) uninstall


卸载命令由脚本内 uninstall 分支执行，请确保使用相同仓库和脚本版本以匹配路径与服务名。

📦 部署产物（部署完成后你将得到）

VLESS 配置文本（Telegram 私聊）

二维码文件：/root/vless-qrcode.png

部署日志：/root/deploy.log

Xray 配置：/usr/local/etc/xray/config.json

Nginx 配置：/etc/nginx/sites-available/[DOMAIN].conf

BBR 测速日志：/var/log/bbr-check.log

核心脚本配置：/etc/nlbwvpn/config.conf（脚本保存的用户输入）

示例（脚本发送的示例输出）：

🎉 部署完成！ (by nlbw)
主机: debian-vps

VLESS 链接:
vless://[UUID]@[DOMAIN]:443?encryption=none&security=tls&type=ws&host=[DOMAIN]&path=%2F[RANDOM_PATH]#[DOMAIN]-nlbw

📊 自动化系统（systemd / timers）
功能	Systemd 名称	触发周期 / 描述
实时健康检测	tg-control.service	常驻服务，按 CHECK_INTERVAL 秒检测 nginx/xray 状态并通过 Telegram 报警
BBR 状态检查	bbr-status.timer / .service	每周运行一次，记录 BBR & 测速日志
Telegram 周报	bbr-weekly-report.timer / .service	每周一 03:10 发送 BBR 平均速率与证书到期提醒
🗂️ 关键路径（Key Paths）

/root/deploy.log —— 部署日志（标准输出重定向）

/root/vless-qrcode.png —— 生成的二维码文件

/usr/local/etc/xray/config.json —— Xray 配置文件

/etc/nginx/sites-available/[DOMAIN].conf —— Nginx 虚拟主机配置

/etc/nlbwvpn/config.conf —— 保存的安装参数（域名、邮箱、TG token 等）

/var/log/bbr-check.log —— BBR/测速日志

💡 常见问题（FAQ）

Q1：Certbot 申请失败？

A：最常见原因是域名未解析或解析未生效。确认域名 A 记录正确指向 VPS，并等待 DNS 缓存刷新（通常几分钟到 1 小时）。

Q2：Telegram 没收到消息？

A：确认 Bot Token 与 Chat ID 无误，并且你已主动在 Telegram 上向 Bot 发送 /start 或任意消息以开启会话。Chat ID 必须是纯数字（私聊或群聊均可，群聊需确保 Bot 已被添加并开启权限）。

Q3：脚本可重复运行吗？

A：可以。脚本设计为可重复运行（幂等性），再次运行会用新输入覆盖配置，适用于更新证书、修改 TG 设置或改变 WS 路径。

Q4：如何修改 WebSocket 路径或端口？

A：重运行脚本并在交互中输入你希望的 WS 路径；脚本会替换 Xray 与 Nginx 中的路径。如果只想修改配置，也可以手动编辑 /usr/local/etc/xray/config.json 与 Nginx 对应站点文件，然后 systemctl restart xray nginx。

Q5：如何查看部署日志？

A：sudo tail -n 200 /root/deploy.log 或 less /root/deploy.log。

🧰 系统兼容性（Requirements）

操作系统：Debian 10/11/12 或 Ubuntu 20.04/22.04/24.04

权限：必须以 root 用户执行或使用 sudo -i 切换到 root

网络：能访问 GitHub、apt 仓库、Let’s Encrypt 及 Telegram API

DNS：域名已解析到 VPS 公网 IP

🧑‍💻 作者与支持

作者：nlbw

Email：hupan0210@gmail.com

项目地址：https://github.com/Hupan0210/vpn

⚖️ License

本项目基于 MIT License
 开源。欢迎 Fork、提交 PR 或开 Issue。
