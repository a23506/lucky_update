# Lucky 自动更新运维脚本 (Multi-Arch)

本项目提供了一个轻量级、非交互式的 Lucky 自动更新脚本。它旨在解决官方脚本在定时自动化任务中需要人工干预的问题，并针对特定运维需求进行了深度定制。

## 🌟 核心特性

* **多架构自适应**：自动识别 `x86_64`、`arm64` (aarch64) 或 `armv7` 架构，并动态拼接对应的官方下载链接。
* **静默安装**：模拟官方脚本 `install.sh` 的版本抓取逻辑，无需人工输入数字选择版本或目录。
* **精准进程释放**：在更新重启前，强制清理占用 `16601` 端口的旧进程，确保新版本服务顺利启动。
* **双平台通知**：集成 Telegram 和企业微信 Webhook 通知，支持 Markdown 格式，实时反馈更新状态、版本号及编译日期。

## 🚀 一键部署
## 创建日志文件
``` bash
touch /var/log/lucky_update.log && chmod 666 /var/log/lucky_update.log
```

## 配置env
```bash
cat <<EOF > /opt/lucky.daji/.env
# Lucky 更新webhook自动化配置
TG_TOKEN="你的TG_TOKEN"
TG_ID="你的TG_ID"
WX_URL="你的微信Webhook地址"
DOMAIN="$(hostname)"
EOF

# 修改权限，仅 root 可读写
chmod 600 /opt/lucky.daji/.env
```

## 带webhook通知的命令
``` bash
export $(grep -v '^#' /opt/lucky.daji/.env | xargs) && curl -sSL https://raw.githubusercontent.com/a23506/lucky_update/main/auto_lucky.sh | bash -s -- -t "${TG_TOKEN:-}" -i "${TG_ID:-}" -w "${WX_URL:-}" -d "${DOMAIN:-}"
```

# 配置定时任务
``` bash
# 复制这一整段到终端执行，它会自动帮你把带参数的远程定时任务写进 crontab
# 每天凌晨 02:30 远程拉取脚本并带参数执行
(crontab -l 2>/dev/null | grep -v "lucky_update"; echo "30 2 * * * export $(grep -v '^#' /opt/lucky.daji/.env | xargs) && curl -sSL https://raw.githubusercontent.com/a23506/lucky_update/main/auto_lucky.sh | bash -s -- -t "${TG_TOKEN:-}" -i "${TG_ID:-}" -w "${WX_URL:-}" -d "${DOMAIN:-AWS-Node}" >> /var/log/lucky_update.log 2>&1") | crontab -
```
