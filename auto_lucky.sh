#!/bin/bash

# ================= 配置区域 =================
# 基础下载域名及安装路径
BASE_URL="http://release.66666.host"
LUCKY_DIR="/opt/lucky.daji"
DOMAIN="ai.com" # 占位域名

# --- 通知配置 (请填写你的真实信息) ---
TG_BOT_TOKEN="" 
TG_CHAT_ID=""
WECHAT_WEBHOOK="" # 企业微信机器人 Webhook 地址
# ===========================================

# 1. 架构识别 (参考官方逻辑，确保兼容 x86 和 ARM)
get_arch() {
    local arch_raw=$(uname -m)
    case "$arch_raw" in
        x86_64) echo "x86_64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l) echo "armv7" ;;
        *) echo "x86_64" ;; # 默认回退到 x86_64
    esac
}
CPUTYPE=$(get_arch)

# 2. 获取本地版本
LOCAL_VERSION="0.0.0"
if [ -f "$LUCKY_DIR/lucky" ]; then
    LOCAL_INFO=$("$LUCKY_DIR/lucky" -info)
    LOCAL_VERSION=$(echo "$LOCAL_INFO" | grep -oP '(?<="Version":")[^"]+')
fi

# 3. 抓取远程最新版本 (模拟官方 get_versions 逻辑)
# 自动抓取以 'v' 开头的目录，通过版本号排序取最新一个
REMOTE_TAG=$(curl -s "$BASE_URL/" | grep -oP '(?<=href="\.\/)[^"/]+' | grep '^v' | sort -V | tail -n 1)
REMOTE_VER=${REMOTE_TAG#v}

if [ -z "$REMOTE_VER" ]; then
    echo "无法连接服务器或解析版本失败。"
    exit 1
fi

# 4. 版本比对
if [ "$LOCAL_VERSION" == "$REMOTE_VER" ]; then
    echo "当前版本 ($LOCAL_VERSION) 已是最新，无需更新。"
    exit 0
fi

echo "发现新版本: $REMOTE_VER，正在为 $CPUTYPE 架构进行更新..."

# 5. 动态拼接下载地址
SUBDIR="${REMOTE_VER}_wanji_docker"
PKG_NAME="lucky_${REMOTE_VER}_Linux_${CPUTYPE}_wanji_docker.tar.gz"
DOWNLOAD_URL="$BASE_URL/$REMOTE_TAG/$SUBDIR/$PKG_NAME"

# 6. 下载并替换 (静默安装)
TMP_FILE="/tmp/lucky_update.tar.gz"
curl -L -o "$TMP_FILE" "$DOWNLOAD_URL"
if [ $? -ne 0 ]; then
    echo "下载失败，请检查网络。"
    exit 1
fi

# 解压覆盖并清理
mkdir -p "$LUCKY_DIR"
tar -zxf "$TMP_FILE" -C "$LUCKY_DIR/" --strip-components=0
chmod +x "$LUCKY_DIR/lucky" "$LUCKY_DIR/scripts/"*
rm -f "$TMP_FILE"

# 7. 强制重启逻辑 (按照你的要求释放端口)
echo "正在重启服务..."
netstat -tunlp | grep 16601 | awk '{print $7}' | cut -d'/' -f1 | xargs -r kill -9
systemctl restart lucky.daji

# 8. 发送 Markdown 通知
NEW_INFO=$("$LUCKY_DIR/lucky" -info)
NEW_DATE=$(echo "$NEW_INFO" | grep -oP '(?<="Date":")[^"]+')
UPDATE_TIME=$(date '+%Y-%m-%d %H:%M:%S')

# 构建消息主体
TITLE="✅ Lucky 自动更新成功"
CONTENT="> **节点**: $DOMAIN ($CPUTYPE)\n> **变更**: $LOCAL_VERSION → $REMOTE_VER\n> **编译**: $NEW_DATE\n> **时间**: $UPDATE_TIME"

# Telegram 通知
if [ -n "$TG_BOT_TOKEN" ]; then
    curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
        -d "chat_id=$TG_CHAT_ID" -d "parse_mode=Markdown" -d "text=*$TITLE*\n$CONTENT" > /dev/null
fi

# 企业微信通知
if [ -n "$WECHAT_WEBHOOK" ]; then
    curl -s -H "Content-Type: application/json" -X POST "$WECHAT_WEBHOOK" \
        -d "{\"msgtype\":\"markdown\",\"markdown\":{\"content\":\"### $TITLE\n$CONTENT\"}}" > /dev/null
fi

echo "更新任务顺利结束。"
