#!/bin/bash

# ================= 基础配置 =================
BASE_URL="http://release.66666.host"
INSTALL_ROOT="/opt"
LUCKY_DIR="$INSTALL_ROOT/lucky.daji"
DOMAIN="ai.com"

# 通过参数解析 Webhook
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

# 1. 环境准备与架构识别
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

REMOTE_TAG=$(curl -s "$BASE_URL/" | grep -oP '(?<=href="\.\/)[^"/]+' | grep '^v' | sort -V | tail -n 1)
REMOTE_VER=${REMOTE_TAG#v}
BASE_VER=$(echo "$REMOTE_VER" | grep -oP '^\d+\.\d+\.\d+')

if [ -z "$REMOTE_VER" ]; then
    echo -e "${RED}❌ 无法获取远程版本${NC}"
    exit 1
fi

if [ "$LOCAL_VER" == "$REMOTE_VER" ] || [ "$LOCAL_VER" == "$BASE_VER" ]; then
    echo -e "${GREEN}✅ 当前已是最新版本 ($LOCAL_VER)${NC}"
    exit 0
fi

# 3. 智能下载
echo -e "${YELLOW}🔔 正在下载 Lucky $REMOTE_VER ($CPUTYPE)...${NC}"
TMP_FILE="/tmp/lucky_update.tar.gz"
URLS=(
    "$BASE_URL/$REMOTE_TAG/${REMOTE_VER}_wanji_docker/lucky_${REMOTE_VER}_Linux_${CPUTYPE}_wanji_docker.tar.gz"
    "$BASE_URL/$REMOTE_TAG/${BASE_VER}_wanji_docker/lucky_${BASE_VER}_Linux_${CPUTYPE}_wanji_docker.tar.gz"
)

SUCCESS=0
for URL in "${URLS[@]}"; do
    if curl -fL -# -o "$TMP_FILE" "$URL"; then
        SUCCESS=1 && break
    fi
done

[ $SUCCESS -ne 1 ] && echo -e "${RED}❌ 下载失败${NC}" && exit 1

# 4. 目录处理 (融合官方逻辑：确保目录存在)
if [ ! -d "$LUCKY_DIR" ]; then
    echo -e "${YELLOW}📂 创建安装目录: $LUCKY_DIR${NC}"
    mkdir -p "$LUCKY_DIR"
fi

# 5. 解压替换
tar -zxf "$TMP_FILE" -C "$LUCKY_DIR/" --strip-components=0
chmod +x "$LUCKY_DIR/lucky"
[ -d "$LUCKY_DIR/scripts" ] && chmod +x "$LUCKY_DIR/scripts/"*

# 6. 写入 Systemd 服务 (融合官方关键逻辑：解决 Unit not found 问题)
SERVICE_FILE="/etc/systemd/system/lucky.daji.service"
if [ ! -f "$SERVICE_FILE" ]; then
    echo -e "${YELLOW}⚙️ 正在生成 Systemd 服务文件...${NC}"
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

# 7. 重启与进程清理
echo -e "${YELLOW}🔄 正在启动/重启服务...${NC}"
netstat -tunlp | grep 16601 | awk '{print $7}' | cut -d'/' -f1 | xargs -r kill -9
systemctl restart lucky.daji

# 8. 发送通知
WAN_IP=$(curl -s --connect-timeout 5 https://api.ipify.org || echo "Internal")
MSG="### Lucky 部署/更新成功\n> **主机**: $(hostname) ($WAN_IP)\n> **架构**: $CPUTYPE\n> **版本**: $LOCAL_VER -> $REMOTE_VER\n> **节点**: $DOMAIN"

[ -n "$TG_TOKEN" ] && curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" -d "chat_id=$TG_ID" -d "parse_mode=Markdown" -d "text=$(echo -e "$MSG")" > /dev/null
[ -n "$WX_URL" ] && curl -s -H "Content-Type: application/json" -X POST "$WX_URL" -d "{\"msgtype\":\"markdown\",\"markdown\":{\"content\":\"$MSG\"}}" > /dev/null

rm -f "$TMP_FILE"
echo -e "${GREEN}✨ 部署/更新任务已完成！${NC}"
