#!/bin/bash

# ================= 配置区域 =================
BASE_URL="http://release.66666.host"
LUCKY_DIR="/opt/lucky.daji"
DOMAIN="ai.com"

# 通知配置
TG_BOT_TOKEN="" 
TG_CHAT_ID=""
WECHAT_WEBHOOK=""
# ===========================================

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

# 3. 抓取远程最新版本标签 (例如 v3.0.0beta3)
REMOTE_TAG=$(curl -s "$BASE_URL/" | grep -oP '(?<=href="\.\/)[^"/]+' | grep '^v' | sort -V | tail -n 1)
# 纯版本号 (例如 3.0.0beta3)
REMOTE_VER=${REMOTE_TAG#v}
# 基础版本号 (去掉 beta 后缀，例如 3.0.0)
BASE_VER=$(echo "$REMOTE_VER" | grep -oP '^\d+\.\d+\.\d+')

if [ -z "$REMOTE_VER" ]; then
    echo "❌ 无法解析远程版本。"
    exit 1
fi

# 4. 版本比对
if [ "$LOCAL_VERSION" == "$REMOTE_VER" ] || [ "$LOCAL_VERSION" == "$BASE_VER" ]; then
    echo "当前版本 ($LOCAL_VERSION) 已是最新。"
    exit 0
fi

echo "发现新版本: $REMOTE_VER，正在为 $CPUTYPE 架构进行更新..."

# 5. 智能下载逻辑 (尝试多种可能的官方路径组合)
TMP_FILE="/tmp/lucky_update.tar.gz"
SUCCESS=0

# 组合 1: 完整版本号路径 (3.0.0beta3_wanji_docker)
URL1="$BASE_URL/$REMOTE_TAG/${REMOTE_VER}_wanji_docker/lucky_${REMOTE_VER}_Linux_${CPUTYPE}_wanji_docker.tar.gz"
# 组合 2: 基础版本号路径 (3.0.0_wanji_docker)
URL2="$BASE_URL/$REMOTE_TAG/${BASE_VER}_wanji_docker/lucky_${BASE_VER}_Linux_${CPUTYPE}_wanji_docker.tar.gz"

for DOWNLOAD_URL in "$URL1" "$URL2"; do
    echo "尝试下载: $DOWNLOAD_URL"
    # -f 参数确保 404 时返回错误码
    if curl -fL -o "$TMP_FILE" "$DOWNLOAD_URL"; then
        SUCCESS=1
        break
    fi
done

if [ $SUCCESS -ne 1 ]; then
    echo "❌ 所有下载路径均失效，请手动检查服务器目录结构。"
    exit 1
fi

# 6. 解压与安装
tar -zxf "$TMP_FILE" -C "$LUCKY_DIR/" --strip-components=0
chmod +x "$LUCKY_DIR/lucky" "$LUCKY_DIR/scripts/"*

# 7. 强制重启逻辑
echo "正在重启服务..."
netstat -tunlp | grep 16601 | awk '{print $7}' | cut -d'/' -f1 | xargs -r kill -9
systemctl restart lucky.daji

# 8. 通知模块
NEW_INFO=$("$LUCKY_DIR/lucky" -info)
NEW_VER=$(echo "$NEW_INFO" | grep -oP '(?<="Version":")[^"]+')
NEW_DATE=$(echo "$NEW_INFO" | grep -oP '(?<="Date":")[^"]+')

MSG="### Lucky 自动更新成功\n> **架构**: $CPUTYPE\n> **变更**: $LOCAL_VERSION -> $NEW_VER\n> **编译**: $NEW_DATE\n> **节点**: $DOMAIN"

[ -n "$TG_BOT_TOKEN" ] && curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" -d "chat_id=$TG_CHAT_ID" -d "parse_mode=Markdown" -d "text=$(echo -e $MSG)"
[ -n "$WECHAT_WEBHOOK" ] && curl -s -H "Content-Type: application/json" -X POST "$WECHAT_WEBHOOK" -d "{\"msgtype\":\"markdown\",\"markdown\":{\"content\":\"$MSG\"}}"

rm -f "$TMP_FILE"
echo "更新任务完成。"
