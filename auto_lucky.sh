#!/bin/bash

# ================= 基础配置 =================
BASE_URL="http://release.66666.host"
INSTALL_ROOT="/opt"
LUCKY_DIR="$INSTALL_ROOT/lucky.daji"
CONF_FILE="$LUCKY_DIR/lucky.conf"
SERVICE_FILE="/lib/systemd/system/lucky.daji.service"
LOG_FILE="/var/log/lucky_update.log"
START_TIME=$(date +%s)
# 打印当前执行任务的时间戳（用于日志审计）
echo "------------------------------------------------------------"
echo "任务开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "------------------------------------------------------------"

# 参数解析
while getopts "t:i:w:d:" opt; do
  case $opt in
    t) TG_TOKEN=$OPTARG ;;
    i) TG_ID=$OPTARG ;;
    w) WX_URL=$OPTARG ;;
    d) DOMAIN=$OPTARG ;;
  esac
done

# 颜色定义
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 1. 架构识别
get_arch() {
    case "$(uname -m)" in
        x86_64) echo "x86_64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l) echo "armv7" ;;
        *) echo "x86_64" ;;
    esac
}
CPUTYPE=$(get_arch)

# 2. 获取本地版本
OLD_VER="0.0.0"
[ -f "$LUCKY_DIR/lucky" ] && OLD_VER=$("$LUCKY_DIR/lucky" -info | grep -oP '(?<="Version":")[^"]+' || echo "0.0.0")

# 3. 抓取远程版本
REMOTE_TAG=$(curl -s "$BASE_URL/" | grep -oP '(?<=href="\.\/)[^"/]+' | grep '^v' | sort -V | tail -n 1)
REMOTE_VER=${REMOTE_TAG#v}
BASE_VER=$(echo "$REMOTE_VER" | grep -oP '^\d+\.\d+\.\d+')

if [ -z "$REMOTE_VER" ]; then
    echo -e "${RED}❌ 无法获取远程版本${NC}"
    exit 1
fi

# 版本比对
if [ "$OLD_VER" == "$REMOTE_VER" ] || [ "$OLD_VER" == "$BASE_VER" ]; then
    echo -e "${GREEN}✅ 当前已是最新版本 ($OLD_VER)${NC}"
    # 即使不更新也执行一次清理逻辑
    [ -f "$LOG_FILE" ] && find $(dirname "$LOG_FILE") -name "$(basename "$LOG_FILE")" -mtime +7 -exec truncate -s 0 {} \;
    exit 0
fi

echo -e "${YELLOW}🔔 发现新版本: $REMOTE_VER (当前: $OLD_VER)，开始部署...${NC}"

# 4. 下载逻辑
TMP_FILE="/tmp/lucky_update.tar.gz"
URL_SUCCESS="$BASE_URL/$REMOTE_TAG/${BASE_VER}_wanji_docker/lucky_${BASE_VER}_Linux_${CPUTYPE}_wanji_docker.tar.gz"
URL_BETA="$BASE_URL/$REMOTE_TAG/${REMOTE_VER}_wanji_docker/lucky_${REMOTE_VER}_Linux_${CPUTYPE}_wanji_docker.tar.gz"

if curl -fL -# -o "$TMP_FILE" "$URL_SUCCESS"; then
    echo -e "${GREEN}下载成功！${NC}"
elif curl -fL -# -o "$TMP_FILE" "$URL_BETA"; then
    echo -e "${GREEN}下载成功！${NC}"
else
    echo -e "${RED}❌ 下载失败 (404)${NC}" && exit 1
fi

# 5. 安装与授权
[ ! -d "$LUCKY_DIR" ] && mkdir -p "$LUCKY_DIR"
[ ! -f "$CONF_FILE" ] && touch "$CONF_FILE"

tar -zxf "$TMP_FILE" -C "$LUCKY_DIR/" --strip-components=0
chmod +x "$LUCKY_DIR/lucky"
[ -d "$LUCKY_DIR/scripts" ] && chmod +x "$LUCKY_DIR/scripts/"*

# 6. 同步官方 Systemd 配置
echo -e "${YELLOW}⚙️ 同步官方 Systemd 配置...${NC}"
cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=lucky
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$LUCKY_DIR
ExecStart=$LUCKY_DIR/lucky -c $CONF_FILE >/dev/null
Restart=on-failure
RestartSec=3s
LimitNOFILE=999999
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

[ -f "/etc/systemd/system/lucky.daji.service" ] && rm -f "/etc/systemd/system/lucky.daji.service"
systemctl daemon-reload
systemctl enable lucky.daji

# 7. 重启服务
echo -e "${YELLOW}🔄 正在重启 Lucky 服务...${NC}"
if command -v netstat >/dev/null 2>&1; then
    netstat -tunlp | grep 16601 | awk '{print $7}' | cut -d'/' -f1 | xargs -r kill -9 2>/dev/null
fi
systemctl restart lucky.daji
sleep 2

# 8. 获取新版本信息与统计
NEW_VER=$("$LUCKY_DIR/lucky" -info | grep -oP '(?<="Version":")[^"]+' || echo "升级失败")
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# 9. 构建 Webhook 消息
MSG="Lucky 自动部署/更新成功\n----------------------\n主机: $(hostname)\n节点: ${DOMAIN:-AWS-Node}\n架构: $CPUTYPE\n版本: $OLD_VER -> $NEW_VER\n耗时: ${DURATION}s\n时间: $(date '+%Y-%m-%d %H:%M:%S')"

# 发送 Telegram
if [ -n "$TG_TOKEN" ] && [ -n "$TG_ID" ]; then
    echo -e "${YELLOW}检测到 Telegram 配置，正在发送通知...${NC}"
    curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" -d "chat_id=$TG_ID" -d "text=$(echo -e "$MSG")" > /dev/null
fi

# 发送企业微信
if [ -n "$WX_URL" ]; then
    echo -e "${YELLOW}检测到企业微信配置，正在发送通知...${NC}"
    curl -s -H "Content-Type: application/json" -X POST "$WX_URL" -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"$MSG\"}}" > /dev/null
fi

# 10. 清理旧日志 (保留最近7天，由于是单文件追加，此处逻辑为超过7天则清空或截断)
# 这里的逻辑是查找 7 天前修改过的日志文件并清空，防止磁盘占用过大
if [ -f "$LOG_FILE" ]; then
    find /var/log -name "lucky_update.log" -mtime +7 -exec truncate -s 0 {} \;
    echo -e "${YELLOW}已完成旧日志检查与清理${NC}"
fi

rm -f "$TMP_FILE"
echo -e "${GREEN}✨ 任务顺利结束！耗时 ${DURATION}s${NC}"
echo "------------------------------------------------------------"
