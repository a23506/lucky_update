#!/usr/bin/env bash
set -Eeuo pipefail

# ================= 基础配置 =================
BASE_URL="https://release.66666.host"
INSTALL_ROOT="/opt"
LUCKY_DIR="$INSTALL_ROOT/lucky.daji"
BACKUP_DIR="$LUCKY_DIR/backup"
VER_RECORD="$LUCKY_DIR/.version"
CONF_FILE="$LUCKY_DIR/lucky.conf"
SERVICE_FILE="/etc/systemd/system/lucky.daji.service"
LOG_FILE="/var/log/lucky_update.log"
LOCK_FILE="/var/run/lucky_update.lock"
START_TIME=$(date +%s)

# ================= 日志接管 =================
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"
exec >>"$LOG_FILE" 2>&1

# ================= 颜色定义 =================
if [ -t 1 ]; then
    YELLOW='\033[1;33m'
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    NC='\033[0m'
else
    YELLOW=''
    GREEN=''
    RED=''
    NC=''
fi

echo "============================================================"
echo "任务启动时间: $(date '+%Y-%m-%d %H:%M:%S')"

# ================= 参数解析 =================
TG_TOKEN=""
TG_ID=""
WX_URL=""
DOMAIN=""

while getopts "t:i:w:d:" opt; do
  case "$opt" in
    t) TG_TOKEN="$OPTARG" ;;
    i) TG_ID="$OPTARG" ;;
    w) WX_URL="$OPTARG" ;;
    d) DOMAIN="$OPTARG" ;;
  esac
done

# ================= 通用函数 =================
require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "❌ 缺少依赖命令: $1"
        exit 1
    }
}

notify_all() {
    local msg="$1"

    if [ -n "${TG_TOKEN:-}" ] && [ -n "${TG_ID:-}" ]; then
        curl -fsS -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
            --data-urlencode "chat_id=${TG_ID}" \
            --data-urlencode "text=${msg}" \
            >/dev/null 2>&1 || echo "Telegram 通知失败"
    fi

    if [ -n "${WX_URL:-}" ]; then
        local esc_msg
        esc_msg=$(printf '%s' "$msg" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || true)
        if [ -n "$esc_msg" ]; then
            curl -fsS -H "Content-Type: application/json" -X POST "$WX_URL" \
                -d "{\"msgtype\":\"text\",\"text\":{\"content\":${esc_msg}}}" \
                >/dev/null 2>&1 || echo "企业微信通知失败"
        else
            echo "企业微信通知失败：无法构造 JSON"
        fi
    fi
}

cleanup() {
    [ -n "${TMP_FILE:-}" ] && [ -f "${TMP_FILE:-}" ] && rm -f "$TMP_FILE"
    [ -n "${STAGE_DIR:-}" ] && [ -d "${STAGE_DIR:-}" ] && rm -rf "$STAGE_DIR"
    [ -f "$LOCK_FILE" ] && rm -f "$LOCK_FILE"
}
trap cleanup EXIT

on_error() {
    local line_no="$1"
    local exit_code="${2:-1}"
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - START_TIME))

    local msg="Lucky 自动部署/更新失败
----------------------
主机: $(hostname)
节点: ${DOMAIN:-AWS-Node}
时间: $(date '+%Y-%m-%d %H:%M:%S')
耗时: ${duration}s
出错行: ${line_no}
退出码: ${exit_code}
日志: ${LOG_FILE}"

    echo -e "${RED}${msg}${NC}"
    notify_all "$msg"
    exit "$exit_code"
}
trap 'on_error ${LINENO} $?' ERR

# ================= 前置检查 =================
[ "$(id -u)" -eq 0 ] || { echo "❌ 请以 root 身份运行"; exit 1; }
[ -d /run/systemd/system ] || { echo "❌ 当前系统不是 systemd 环境"; exit 1; }

for cmd in curl grep sed sort tar systemctl mktemp stat python3 find cp rm wc awk df dirname; do
    require_cmd "$cmd"
done

if [ -e "$LOCK_FILE" ]; then
    old_pid="$(cat "$LOCK_FILE" 2>/dev/null || true)"
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
        echo "⚠️ 已有运行中的更新进程 PID=$old_pid，退出"
        exit 0
    fi
fi
echo $$ > "$LOCK_FILE"

# ================= 架构识别 =================
get_arch() {
    case "$(uname -m)" in
        x86_64) echo "x86_64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l) echo "armv7" ;;
        *) echo "unsupported" ;;
    esac
}
CPUTYPE="$(get_arch)"
[ "$CPUTYPE" != "unsupported" ] || {
    echo "❌ 不支持的架构: $(uname -m)"
    exit 1
}

# ================= 本地版本 =================
if [ -s "$VER_RECORD" ]; then
    LOCAL_TAG="$(tr -d '[:space:]' < "$VER_RECORD")"
else
    LOCAL_TAG="Unknown/Empty"
fi

# ================= 远端最新版本 =================
REMOTE_TAG="$(
    curl -fsSL "$BASE_URL/" |
    grep -Eo 'href="\./v[^"/]+/?' |
    sed -E 's/^href="\.\/(v[^"/]+)\/?/\1/' |
    sort -V |
    tail -n 1
)"

if [ -z "$REMOTE_TAG" ]; then
    echo -e "${RED}❌ 无法获取远程版本信息，请检查网络或网页结构${NC}"
    exit 1
fi

if [ "$LOCAL_TAG" = "$REMOTE_TAG" ]; then
    echo -e "${GREEN}✅ 当前已是最新版本 ($LOCAL_TAG)${NC}"
    echo "============================================================"
    exit 0
fi

echo -e "${YELLOW}🔔 状态变更: 远程($REMOTE_TAG) vs 本地($LOCAL_TAG)${NC}"
echo -e "${YELLOW}🚀 开始部署/更新流程...${NC}"

# ================= 计算下载地址 =================
REMOTE_VER="${REMOTE_TAG#v}"
BASE_VER="$(printf '%s' "$REMOTE_VER" | grep -Eo '^[0-9]+\.[0-9]+\.[0-9]+')"

[ -n "$BASE_VER" ] || {
    echo "❌ 无法从远端版本解析 BASE_VER: $REMOTE_VER"
    exit 1
}

TMP_FILE="$(mktemp /tmp/lucky_update.XXXXXX.tar.gz)"
STAGE_DIR="$(mktemp -d /tmp/lucky_stage.XXXXXX)"

URL1="$BASE_URL/$REMOTE_TAG/${BASE_VER}_wanji_docker/lucky_${BASE_VER}_Linux_${CPUTYPE}_wanji_docker.tar.gz"
URL2="$BASE_URL/$REMOTE_TAG/${REMOTE_VER}_wanji_docker/lucky_${REMOTE_VER}_Linux_${CPUTYPE}_wanji_docker.tar.gz"

if curl -fL --retry 2 --connect-timeout 15 --max-time 300 -o "$TMP_FILE" "$URL1"; then
    echo -e "${GREEN}下载成功 (Path A)${NC}"
elif curl -fL --retry 2 --connect-timeout 15 --max-time 300 -o "$TMP_FILE" "$URL2"; then
    echo -e "${GREEN}下载成功 (Path B)${NC}"
else
    echo -e "${RED}❌ 下载失败 (Path A / Path B 均不可用)${NC}"
    exit 1
fi

# ================= 下载包基础检查 =================
[ -s "$TMP_FILE" ] || {
    echo "❌ 下载文件为空"
    exit 1
}

tar -tzf "$TMP_FILE" >/dev/null 2>&1 || {
    echo "❌ 下载包不是有效的 tar.gz 或已损坏"
    exit 1
}

# ================= 参考官方脚本：空间检查 =================
check_disk_space() {
    local tar_file_size luckydir_parent mount_point available_space_kb available_space estimated_size

    tar_file_size=$(stat -c %s "$TMP_FILE" 2>/dev/null || stat -f %z "$TMP_FILE" 2>/dev/null || ls -l "$TMP_FILE" | awk '{print $5}')

    if [ ! -d "$LUCKY_DIR" ]; then
        luckydir_parent="$(dirname "$LUCKY_DIR")"
    else
        luckydir_parent="$LUCKY_DIR"
    fi

    mount_point=$(df "$luckydir_parent" 2>/dev/null | awk 'NR==2 {print $NF}')

    if [ -z "$mount_point" ]; then
        echo "❌ 无法确定 $LUCKY_DIR 的挂载点"
        exit 1
    fi

    available_space_kb=$(df -k "$mount_point" 2>/dev/null | awk 'NR==2 {print $4}' | grep -oE '^[0-9]+' || true)

    if [ -z "${available_space_kb:-}" ] || [ "$available_space_kb" = "0" ]; then
        available_space_kb=$(df "$luckydir_parent" 2>/dev/null | tail -1 | awk '{print $4}' | grep -oE '^[0-9]+' || true)
    fi

    if [ -z "${available_space_kb:-}" ]; then
        echo "⚠️ 无法获取可用磁盘空间，跳过空间检查"
        return 0
    fi

    available_space=$(( available_space_kb * 1024 ))
    estimated_size=$(( tar_file_size * 3 / 2 ))

    echo "压缩包大小: $tar_file_size 字节"
    echo "可用空间: $available_space 字节"
    echo "预估解压后大小: $estimated_size 字节"

    if [ "$available_space" -lt "$estimated_size" ]; then
        echo "❌ 磁盘空间不足，至少需要 $estimated_size 字节，当前仅有 $available_space 字节"
        exit 1
    fi
}
check_disk_space

# ================= 解压到临时目录 =================
tar -zxf "$TMP_FILE" -C "$STAGE_DIR"

[ -f "$STAGE_DIR/lucky" ] || {
    echo "❌ 解压后未找到 lucky 主程序"
    exit 1
}

chmod +x "$STAGE_DIR/lucky"
[ -d "$STAGE_DIR/scripts" ] && chmod +x "$STAGE_DIR/scripts/"* 2>/dev/null || true

# ================= 更新前备份 .lkcf 配置 =================
backup_lkcf_configs() {
    mkdir -p "$LUCKY_DIR"

    # 覆盖式备份：每次先清空旧 backup
    rm -rf "$BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"

    # 仅备份 /opt/lucky.daji 目录下所有 .lkcf 文件（包含子目录）
    if find "$LUCKY_DIR" -type f -name '*.lkcf' | grep -q .; then
        while IFS= read -r file; do
            rel_path="${file#"$LUCKY_DIR"/}"
            target_dir="$BACKUP_DIR/$(dirname "$rel_path")"
            mkdir -p "$target_dir"
            cp -af "$file" "$target_dir/"
        done < <(find "$LUCKY_DIR" -type f -name '*.lkcf')
        echo "✅ 配置备份完成，备份目录: $BACKUP_DIR"
    else
        echo "ℹ️ 未发现 .lkcf 配置文件，跳过备份"
    fi
}
backup_lkcf_configs

# ================= 安装覆盖 =================
mkdir -p "$LUCKY_DIR"
cp -af "$STAGE_DIR/." "$LUCKY_DIR/"

[ -x "$LUCKY_DIR/lucky" ] || {
    echo "❌ 安装后 lucky 不可执行"
    exit 1
}

# ================= 写 systemd 服务 =================
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=lucky
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$LUCKY_DIR
ExecStart=$LUCKY_DIR/lucky -c $CONF_FILE
Restart=on-failure
RestartSec=3
LimitNOFILE=999999
KillMode=process
StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

[ -f "/lib/systemd/system/lucky.daji.service" ] && rm -f "/lib/systemd/system/lucky.daji.service"

systemctl daemon-reload
systemctl enable lucky.daji >/dev/null 2>&1 || true

# ================= 重启并检查 =================
echo -e "${YELLOW}🔄 重启 Lucky 服务...${NC}"
systemctl restart lucky.daji
sleep 2

if ! systemctl is-active --quiet lucky.daji; then
    echo "❌ lucky.daji 启动失败，最近日志如下："
    journalctl -u lucky.daji -n 50 --no-pager || true
    exit 1
fi

# ================= 成功后写入版本 =================
echo "$REMOTE_TAG" > "$VER_RECORD"

# ================= 通知 =================
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

MSG="Lucky 自动部署/更新成功
----------------------
主机: $(hostname)
节点: ${DOMAIN:-AWS-Node}
架构: $CPUTYPE
版本: $LOCAL_TAG -> $REMOTE_TAG
备份目录: $BACKUP_DIR
耗时: ${DURATION}s
时间: $(date '+%Y-%m-%d %H:%M:%S')"

notify_all "$MSG"

# ================= 日志维护 =================
if [ -f "$LOG_FILE" ]; then
    LOG_SIZE="$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)"
    if [ "$LOG_SIZE" -gt 10485760 ]; then
        : > "$LOG_FILE"
        echo "日志已超过 10MB，已清空"
    fi
fi

echo -e "${GREEN}✨ 任务完成！耗时: ${DURATION}s${NC}"
echo "============================================================"
