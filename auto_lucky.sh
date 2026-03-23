#!/bin/bash

# ================= 配置区域 =================
BASE_URL="http://release.66666.host"
LUCKY_DIR="/opt/lucky.daji"
DOMAIN="ai.com" # 占位域名，可改为你的机器别名

# 通知配置 (留空则跳过)
TG_BOT_TOKEN="" 
TG_CHAT_ID=""
WECHAT_WEBHOOK=""
# ===========================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

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
LOCAL_VERSION="0.0.0"
[ -f "$LUCKY_DIR/lucky" ] && LOCAL_VERSION=$("$LUCKY_DIR/lucky" -info | grep -oP '(?<="Version":")[^"]+')

# 3. 抓取远程最新标签
REMOTE_TAG=$(curl -s "$BASE_URL/" | grep -oP '(?<=href="\.\/)[^"/]+' | grep '^v' | sort -V | tail -n 1)
REMOTE_VER=${REMOTE_TAG#v}
BASE_VER=$(echo "$REMOTE_VER" | grep -oP '^\d+\.\d+\.\d+')

if [ -z "$REMOTE_VER" ]; then
    echo -e "${RED}❌ 无法解析远程版本，请检查网络。${NC}"
    exit 1
fi

# 4. 版本比对 (只有远程版本高于或不等于本地时才更新)
if [ "$LOCAL_VERSION" == "$REMOTE_VER" ] || [ "$LOCAL_VERSION" == "$BASE_VER" ]; then
    echo -e "${GREEN}✅ 当前已是最新版本 ($LOCAL_VERSION)，跳过更新。${NC}"
    exit 0
fi

echo -e "${YELLOW}🔔 发现新版本: $REMOTE_VER (本地: $LOCAL_VERSION)，正在更新...${NC}"

# 5. 智能下载逻辑
TMP_FILE="/tmp/lucky_update.tar.gz"
SUCCESS=0

# 定义可能的路径组合 (针对 Lucky 官方服务器的命名习惯)
URLS=(
    "$BASE_URL/$REMOTE_TAG/${REMOTE_VER}_wanji_docker/lucky_${REMOTE_VER}_Linux_${CPUTYPE}_wanji_docker.tar.gz"
    "$BASE_URL/$REMOTE_TAG/${BASE_VER}_wanji_docker/lucky_${BASE_VER}_Linux_${CPUTYPE}_wanji_docker.tar.gz"
    "$BASE_URL/$REMOTE_TAG/wanji_docker/lucky_${BASE_VER}_Linux_${CPUTYPE}_wanji_docker.tar.gz"
)

for URL in "${URLS[@]}"; do
    echo -e "${YELLOW}正在尝试下载: $URL${NC}"
    if curl -fL -# -o "$TMP_FILE" "$URL"; then
        SUCCESS=1
        break
    fi
done

if [ $SUCCESS -ne 1 ]; then
    echo -e "${RED}❌ 所有路径下载失败，可能是官方更改了目录结构。${NC}"
    exit 1
fi

# 6. 解压与覆盖
tar -zxf "$TMP_FILE" -C "$LUCKY_DIR/" --strip-components=0
chmod +x "$LUCKY_DIR/lucky" "$LUCKY_DIR/scripts/"*

# 7. 强制重启逻辑
echo -e "${YELLOW}🔄 正在清理旧进程并重启服务...${NC}"
netstat -tunlp | grep 16601 | awk '{print $7}' | cut -d'/' -f1 | xargs -r kill -9
systemctl restart lucky.daji

# 8. 获取新信息并发送通知
NEW_INFO=$("$LUCKY_DIR/lucky" -info)
NEW_VER=$(echo "$NEW_INFO" | grep -oP '(?<="Version":")[^"]+')
NEW_DATE=$(echo "$NEW_INFO" | grep -oP '(?<="Date":")[^"]+')
WAN_IP=$(curl -s https://api.ipify.org || echo "Unknown")

MSG="### Lucky 自动更新成功\n> **主机**: $(hostname) ($WAN_IP)\n> **架构**: $CPUTYPE\n> **变更**: $LOCAL_VERSION -> $NEW_VER\n> **编译**: $NEW_DATE\n> **节点**: $DOMAIN"

# Telegram
[ -n "$TG_BOT_TOKEN" ] && curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" -d "chat_id=$TG_CHAT_ID" -d "parse_mode=Markdown" -d "text=$(echo -e $MSG)" > /dev/null
# 企业微信
[ -n "$WECHAT_WEBHOOK" ] && curl -s -H "Content-Type: application/json" -X POST "$WECHAT_WEBHOOK" -d "{\"msgtype\":\"markdown\",\"markdown\":{\"content\":\"$MSG\"}}" > /dev/null

rm -f "$TMP_FILE"
echo -e "${GREEN}✨ 更新流程顺利结束！${NC}"
