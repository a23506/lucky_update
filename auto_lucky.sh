#!/bin/bash

# ================= 基础配置 =================
BASE_URL="http://release.66666.host"
INSTALL_ROOT="/opt"
LUCKY_DIR="$INSTALL_ROOT/lucky.daji"
START_TIME=$(date +%s) # 记录开始时间

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

# 2. 获取本地旧版本
OLD_VER="未知"
[ -f "$LUCKY_DIR/lucky" ] && OLD_VER=$("$LUCKY_DIR/lucky" -info | grep -oP '(?<="Version":")[^"]+')

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
    exit 0
fi

# 4. 智能路径下载
TMP_FILE="/tmp/lucky_update.tar.gz"
URL_SUCCESS="$BASE_URL/$REMOTE_TAG/${BASE_VER}_wanji_docker/lucky_${BASE_VER}_Linux_${CPUTYPE}_wanji_docker.tar.gz"
URL_BETA="$BASE_URL/$REMOTE_TAG/${REMOTE_VER}_wanji_docker/lucky_${REMOTE_VER}_Linux_${CPUTYPE}_wanji_docker.tar.gz"

DOWNLOAD_URL=""
if curl -fL -# -o "$TMP_FILE" "$URL_SUCCESS"; then
    DOWNLOAD_URL=$URL_SUCCESS
elif curl -fL -# -o "$TMP_FILE" "$URL_BETA"; then
    DOWNLOAD_URL=$URL_BETA
else
    echo -e "${RED}❌ 下载失败 (404)${NC}" && exit 1
fi

# 5. 安装逻辑
[ ! -d "$LUCKY_DIR" ] && mkdir -p "$LUCKY_DIR"
tar -zxf "$TMP_FILE" -C "$LUCKY_DIR/" --strip-components=0
chmod +x "$LUCKY_DIR/lucky"
[ -d "$LUCKY_DIR/scripts" ] && chmod +x "$LUCKY_DIR/scripts/"*

# 6. 系统服务注册
SERVICE_FILE="/etc/systemd/system/lucky.daji.service"
if [ ! -f "$SERVICE_FILE" ]; then
    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Lucky Service
After=network.target
[Service]
Type=simple
WorkingDirectory=$LUCKY_DIR
ExecStart=$LUCKY_DIR/lucky
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable lucky.daji
fi

# 7. 重启
systemctl restart lucky.daji
sleep 2 # 等待服务启动以获取最新版本号

# 8. 获取新版本与统计耗时
NEW_VER=$("$LUCKY_DIR/lucky" -info | grep -oP '(?<="Version":")[^"]+')
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# 9. 发送通知 (根据你的需求优化格式)
MSG="Lucky 自动部署/更新成功\n----------------------\n主机: $(hostname)\n节点: ${DOMAIN:-未命名}\n架构: $CPUTYPE\n版本: $OLD_VER -> $NEW_VER\n路径: $DOWNLOAD_URL\n耗时: ${DURATION}s\n时间: $(date '+%Y-%m-%d %H:%M:%S')"

# Telegram
if [ -n "$TG_TOKEN" ] && [ -n "$TG_ID" ]; then
    curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" -d "chat_id=$TG_ID" -d "text=$(echo -e "$MSG")" > /dev/null
fi

# 企业微信
if [ -n "$WX_URL" ]; then
    curl -s -H "Content-Type: application/json" -X POST "$WX_URL" -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"$MSG\"}}" > /dev/null
fi

rm -f "$TMP_FILE"
echo -e "${GREEN}✨ 更新流程结束，耗时 ${DURATION}s${NC}"
