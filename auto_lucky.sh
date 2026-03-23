#!/bin/bash

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# ================= 默认配置区域 =================
BASE_URL="http://release.66666.host"
INSTALL_ROOT="/opt"
LUCKY_DIR="$INSTALL_ROOT/lucky.daji"
DOMAIN="ai.com"

# Webhook 默认值 (可通过参数 -t -i -w 覆盖)
TG_TOKEN=""
TG_ID=""
WX_URL=""

# ================= 参数解析逻辑 =================
# 用法: bash auto_lucky.sh -t <TOKEN> -i <ID> -w <URL> -d <NAME>
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

# 2. 版本检查
LOCAL_VER="0.0.0"
[ -f "$LUCKY_DIR/lucky" ] && LOCAL_VER=$("$LUCKY_DIR/lucky" -info | grep -oP '(?<="Version":")[^"]+')

# 获取远程最新版本
REMOTE_TAG=$(curl -s "$BASE_URL/" | grep -oP '(?<=href="\.\/)[^"/]+' | grep '^v' | sort -V | tail -n 1)
REMOTE_VER=${REMOTE_TAG#v}
BASE_VER=$(echo "$REMOTE_VER" | grep -oP '^\d+\.\d+\.\d+')

if [ -z "$REMOTE_VER" ]; then
    echo -e "${RED}❌ 无法连接远程服务器获取版本${NC}"
    exit 1
fi

if [ "$LOCAL_VER" == "$REMOTE_VER" ] || [ "$LOCAL_VER" == "$BASE_VER" ]; then
    echo -e "${GREEN}✅ 当前版本 ($LOCAL_VER) 已是最新，无需更新。${NC}"
    exit 0
fi

echo -e "${YELLOW}🔔 发现新版本: $REMOTE_VER (当前: $LOCAL_VER)，开始部署...${NC}"

# 3. 智能路径下载
TMP_FILE="/tmp/lucky_update.tar.gz"
# 优先尝试已确认成功的 BASE_VER 路径，备选 REMOTE_VER 路径
URL1="$BASE_URL/$REMOTE_TAG/${BASE_VER}_wanji_docker/lucky_${BASE_VER}_Linux_${CPUTYPE}_wanji_docker.tar.gz"
URL2="$BASE_URL/$REMOTE_TAG/${REMOTE_VER}_wanji_docker/lucky_${REMOTE_VER}_Linux_${CPUTYPE}_wanji_docker.tar.gz"

SUCCESS=0
for DOWNLOAD_URL in "$URL1" "$URL2"; do
    echo -e "${YELLOW}尝试下载: $DOWNLOAD_URL${NC}"
    if curl -fL -# -o "$TMP_FILE" "$DOWNLOAD_URL"; then
        SUCCESS=1 && break
    fi
done

if [ $SUCCESS -ne 1 ]; then
    echo -e "${RED}❌ 下载失败，请检查架构 $CPUTYPE 是否有对应包。${NC}"
    exit 1
fi

# 4. 初始化环境 (修复空环境报错)
if [ ! -d "$LUCKY_DIR" ]; then
    echo -e "${YELLOW}📂 创建安装目录: $LUCKY_DIR${NC}"
    mkdir -p "$LUCKY_DIR"
fi

# 5. 解压并授权
tar -zxf "$TMP_FILE" -C "$LUCKY_DIR/" --strip-components=0
chmod +x "$LUCKY_DIR/lucky"
[ -d "$LUCKY_DIR/scripts" ] && chmod +x "$LUCKY_DIR/scripts/"*

# 6. 注册 Systemd 服务 (融合官方逻辑)
SERVICE_FILE="/etc/systemd/system/lucky.daji.service"
if [ ! -f "$SERVICE_FILE" ]; then
    echo -e "${YELLOW}⚙️ 正在注册 Systemd 系统服务...${NC}"
    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Lucky Service
After=network.target

[Service]
Type=simple
WorkingDirectory=$LUCKY_DIR
ExecStart=$LUCKY_DIR/lucky
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable lucky.daji
fi

# 7. 重启服务与端口清理
echo -e "${YELLOW}🔄 正在重启 Lucky 服务...${NC}"
if command -v netstat >/dev/null 2>&1; then
    netstat -tunlp | grep 16601 | awk '{print $7}' | cut -d'/' -f1 | xargs -r kill -9
fi
systemctl restart lucky.daji

# 8. 发送通知 (增加非空校验)

# 只要 LOCAL_VER 和 NEW_VER 存在，就构建消息
MSG="Lucky 自动部署/更新成功\n----------------------\n主机: $(hostname)\n节点: $DOMAIN\nIP: $WAN_IP\n架构: $CPUTYPE\n版本: $LOCAL_VER -> $NEW_VER"

# Telegram: 只有当 TOKEN 和 ID 都不为空时才执行
if [ -n "$TG_TOKEN" ] && [ -n "$TG_ID" ]; then
    echo "检测到 Telegram 配置，正在发送通知..."
    curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
        -d "chat_id=$TG_ID" \
        -d "text=$(echo -e "$MSG")" > /dev/null
fi

# 企业微信: 只有当 WX_URL 不为空时才执行
if [ -n "$WX_URL" ]; then
    echo "检测到企业微信配置，正在发送通知..."
    curl -s -H "Content-Type: application/json" -X POST "$WX_URL" \
        -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"$MSG\"}}" > /dev/null
fi

echo -e "${GREEN}✨ 任务顺利结束！${NC}"
