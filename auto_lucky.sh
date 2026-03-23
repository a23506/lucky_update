#!/bin/bash

# ================= 基础配置 =================
BASE_URL="http://release.66666.host"
INSTALL_ROOT="/opt"
LUCKY_DIR="$INSTALL_ROOT/lucky.daji"
VER_RECORD="$LUCKY_DIR/.version"
CONF_FILE="$LUCKY_DIR/lucky.conf"
SERVICE_FILE="/lib/systemd/system/lucky.daji.service"
LOG_FILE="/var/log/lucky_update.log"
START_TIME=$(date +%s)

echo "============================================================"
echo "任务启动时间: $(date '+%Y-%m-%d %H:%M:%S')"

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

# 2. 获取本地存根版本
# 注意：我们不再信任二进制返回的模糊版本号，只信任存根文件
if [ -s "$VER_RECORD" ]; then
    LOCAL_TAG=$(cat "$VER_RECORD" | tr -d '[:space:]')
else
    LOCAL_TAG="Unknown/Empty"
fi

# 3. 抓取远程最新完整 Tag (例如 v3.0.0beta4)
REMOTE_TAG=$(curl -s "$BASE_URL/" | grep -oP '(?<=href="\.\/)[^"/]+' | grep '^v' | sort -V | tail -n 1)

if [ -z "$REMOTE_TAG" ]; then
    echo -e "${RED}❌ 无法获取远程版本信息，请检查网络${NC}"
    exit 1
fi

# 4. 【严谨对比】字符串完全匹配
if [ "$LOCAL_TAG" == "$REMOTE_TAG" ]; then
    echo -e "${GREEN}✅ 当前已是最新版本 ($LOCAL_TAG)${NC}"
    find /var/log -name "lucky_update.log" -mtime +7 -exec truncate -s 0 {} \;
    echo "============================================================"
    exit 0
fi

# 如果不匹配，无论是版本旧了，还是存根丢了，都执行更新
echo -e "${YELLOW}🔔 状态变更: 远程($REMOTE_TAG) vs 本地($LOCAL_TAG)${NC}"
echo -e "${YELLOW}🚀 开始部署/更新流程...${NC}"

# 5. 下载逻辑
REMOTE_VER=${REMOTE_TAG#v}
BASE_VER=$(echo "$REMOTE_VER" | grep -oP '^\d+\.\d+\.\d+')
TMP_FILE="/tmp/lucky_update.tar.gz"
URL1="$BASE_URL/$REMOTE_TAG/${BASE_VER}_wanji_docker/lucky_${BASE_VER}_Linux_${CPUTYPE}_wanji_docker.tar.gz"
URL2="$BASE_URL/$REMOTE_TAG/${REMOTE_VER}_wanji_docker/lucky_${REMOTE_VER}_Linux_${CPUTYPE}_wanji_docker.tar.gz"

if curl -fL -# -o "$TMP_FILE" "$URL1"; then
    echo -e "${GREEN}下载成功 (Path A)${NC}"
elif curl -fL -# -o "$TMP_FILE" "$URL2"; then
    echo -e "${GREEN}下载成功 (Path B)${NC}"
else
    echo -e "${RED}❌ 下载失败 (404)${NC}" && exit 1
fi

# 6. 安装与存根重建
[ ! -d "$LUCKY_DIR" ] && mkdir -p "$LUCKY_DIR"
tar -zxf "$TMP_FILE" -C "$LUCKY_DIR/" --strip-components=0
chmod +x "$LUCKY_DIR/lucky"
# 关键：更新成功后将完整的远程 Tag 写入存根，作为下次比对的唯一基准
echo "$REMOTE_TAG" > "$VER_RECORD"

# 7. Systemd 配置同步
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

# 8. 重启
echo -e "${YELLOW}🔄 重启 Lucky 服务...${NC}"
systemctl restart lucky.daji
sleep 2

# 9. 统计与通知
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MSG="Lucky 自动部署/更新成功\n----------------------\n主机: $(hostname)\n节点: ${DOMAIN:-AWS-Node}\n架构: $CPUTYPE\n版本: $LOCAL_TAG -> $REMOTE_TAG\n耗时: ${DURATION}s\n时间: $(date '+%Y-%m-%d %H:%M:%S')"

[ -n "$TG_TOKEN" ] && [ -n "$TG_ID" ] && curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" -d "chat_id=$TG_ID" -d "text=$(echo -e "$MSG")" > /dev/null
[ -n "$WX_URL" ] && curl -s -H "Content-Type: application/json" -X POST "$WX_URL" -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"$MSG\"}}" > /dev/null

# 10. 日志清理
find /var/log -name "lucky_update.log" -mtime +7 -exec truncate -s 0 {} \;

rm -f "$TMP_FILE"
echo -e "${GREEN}✨ 任务完成！耗时: ${DURATION}s${NC}"
echo "============================================================"
