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
(crontab -l 2>/dev/null | grep -v "lucky_update"; echo "30 2 * * * export $(grep -v '^#' /opt/lucky.daji/.env | xargs) && curl -sSL https://raw.githubusercontent.com/a23506/lucky_update/main/auto_lucky.sh | bash -s -- -t "${TG_TOKEN:-}" -i "${TG_ID:-}" -w "${WX_URL:-}" -d "${DOMAIN:-}" >> /var/log/lucky_update.log 2>&1") | crontab -
```


===================================================================================================
# Lucky 自动更新脚本

这是一个用于 **Lucky 自动部署 / 自动更新** 的 Shell 脚本，适合通过 `cron` 定时执行。
脚本会自动检测远程发布页上的最新版本，如果发现新版本，则下载、备份配置、覆盖安装、重启服务，并在失败时自动回滚主程序。

---

## 功能特性

* 自动检测远程最新版本
* 自动下载对应架构安装包
* 更新前自动备份 `.lkcf` 配置文件
* 备份目录固定为 `/opt/lucky.daji/backup`
* 备份为覆盖式保存，每次更新前会清空旧备份
* 自动生成 / 更新 `systemd` 服务
* 更新失败时自动回滚主程序
* 回滚时保留本次新生成的配置备份目录
* 支持 Telegram 通知
* 支持企业微信机器人通知
* 支持日志记录
* 支持并发锁，避免重复执行
* 仅在服务启动成功后才写入版本标记

---

## 目录结构

默认安装目录：

```text
/opt/lucky.daji
```

主要文件说明：

```text
/opt/lucky.daji/
├── lucky                 # 主程序
├── lucky.conf            # Lucky 配置文件
├── .version              # 本地版本标记文件
├── backup/               # 更新前自动备份的 .lkcf 配置目录
└── *.lkcf                # 需要备份的配置文件
```

systemd 服务文件：

```text
/etc/systemd/system/lucky.daji.service
```

日志文件：

```text
/var/log/lucky_update.log
```

锁文件：

```text
/var/run/lucky_update.lock
```

---

## 工作流程

脚本执行流程如下：

1. 检查运行环境和依赖命令
2. 检测当前机器架构
3. 读取本地 `.version`
4. 从发布页获取远程最新版本
5. 如果本地已是最新版本，则退出
6. 下载新版本安装包
7. 检查 tar.gz 包有效性
8. 检查磁盘空间是否足够
9. 备份 `/opt/lucky.daji` 下所有 `.lkcf` 文件到 `backup` 目录
10. 创建当前程序的回滚快照（不包含 `backup`）
11. 覆盖安装新版本
12. 重写 systemd 服务文件
13. 重启 Lucky 服务
14. 如果启动成功，则写入新的 `.version`
15. 如果失败，则自动回滚旧程序
16. 发送通知并记录日志

---

## 版本检测来源

脚本仅依赖以下发布页进行版本检测：

```text
https://release.66666.host/
```

脚本会解析发布页中的版本目录，并取排序后的最新版本作为目标版本。

---

## 配置备份说明

脚本会在每次实际更新前执行配置备份。

### 备份规则

* 备份目录为：

```text
/opt/lucky.daji/backup
```

* 备份对象为：

```text
/opt/lucky.daji 下所有 .lkcf 后缀文件
```

* 默认是 **递归查找子目录**
* 每次更新前会先删除旧的 `backup` 目录，再重新备份
* 因此备份始终只保留最近一次更新前的配置

### 示例

如果存在：

```text
/opt/lucky.daji/a.lkcf
/opt/lucky.daji/b.lkcf
/opt/lucky.daji/sub/c.lkcf
```

则备份后会得到：

```text
/opt/lucky.daji/backup/a.lkcf
/opt/lucky.daji/backup/b.lkcf
/opt/lucky.daji/backup/sub/c.lkcf
```

---

## 自动回滚说明

如果更新过程中发生错误，或者新版本启动失败，脚本会自动执行回滚。

### 回滚行为

* 删除当前安装目录中除 `backup` 外的内容
* 恢复更新前的旧程序文件
* 恢复旧的 systemd 服务配置
* 尝试重新启动旧版本服务
* 保留本次新生成的 `backup` 目录

### 注意

回滚保护的是 **主程序和服务文件**，而不是备份目录。
因此即使更新失败，新的配置备份仍会保留下来。

---

## 运行要求

建议在 Linux + systemd 环境下运行，并使用 `root` 执行。

### 必要依赖

脚本依赖以下命令：

* `bash`
* `curl`
* `grep`
* `sed`
* `sort`
* `tar`
* `systemctl`
* `mktemp`
* `stat`
* `python3`
* `find`
* `cp`
* `rm`
* `wc`
* `awk`
* `df`
* `dirname`

---

## 参数说明

脚本支持以下参数：

| 参数   | 说明                 | 是否必须 |
| ---- | ------------------ | ---- |
| `-t` | Telegram Bot Token | 否    |
| `-i` | Telegram Chat ID   | 否    |
| `-w` | 企业微信机器人 Webhook 地址 | 否    |
| `-d` | 节点标识 / 节点名称        | 否    |

---

## 使用方法

### 1. 保存脚本

例如保存为：

```bash
/usr/local/bin/lucky_update.sh
```

### 2. 赋予执行权限

```bash
chmod +x /usr/local/bin/lucky_update.sh
```

### 3. 手动执行

不带通知：

```bash
/usr/local/bin/lucky_update.sh
```

带 Telegram 通知：

```bash
/usr/local/bin/lucky_update.sh -t "你的TG_TOKEN" -i "你的TG_CHAT_ID"
```

带企业微信通知：

```bash
/usr/local/bin/lucky_update.sh -w "你的企业微信Webhook"
```

带节点名称：

```bash
/usr/local/bin/lucky_update.sh -d "东京-01"
```

混合使用：

```bash
/usr/local/bin/lucky_update.sh \
  -t "你的TG_TOKEN" \
  -i "你的TG_CHAT_ID" \
  -w "你的企业微信Webhook" \
  -d "东京-01"
```

---

## 定时执行示例

建议使用 `cron` 定时检查更新。

编辑 root 的计划任务：

```bash
crontab -e
```

示例：每 10 分钟执行一次

```cron
*/10 * * * * /usr/local/bin/lucky_update.sh
```

示例：每小时执行一次，并带通知参数

```cron
0 * * * * /usr/local/bin/lucky_update.sh -t "你的TG_TOKEN" -i "你的TG_CHAT_ID" -d "东京-01"
```

---

## 通知内容说明

### 成功通知示例

```text
Lucky 自动部署/更新成功
----------------------
主机: your-hostname
节点: 东京-01
架构: x86_64
版本: v2.27.1 -> v2.27.2
备份目录: /opt/lucky.daji/backup
耗时: 8s
时间: 2026-03-24 12:00:00
```

### 失败通知示例

```text
Lucky 自动部署/更新失败
----------------------
主机: your-hostname
节点: 东京-01
时间: 2026-03-24 12:00:00
耗时: 5s
出错行: 123
退出码: 1
日志: /var/log/lucky_update.log
回滚: 已执行自动回滚（已保留新的 backup 配置备份）
```

### 关于 `-d` 参数

* 如果传入 `-d`，通知中会显示“节点: xxx”
* 如果不传 `-d`，通知中不会显示“节点:”这一行

---

## 日志说明

脚本会将运行日志写入：

```text
/var/log/lucky_update.log
```

日志文件超过 10MB 时会自动清空。

查看日志：

```bash
tail -f /var/log/lucky_update.log
```

---

## systemd 服务说明

脚本会自动生成以下服务文件：

```text
/etc/systemd/system/lucky.daji.service
```

服务内容大致如下：

```ini
[Unit]
Description=lucky
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/lucky.daji
ExecStart=/opt/lucky.daji/lucky -c /opt/lucky.daji/lucky.conf
Restart=on-failure
RestartSec=3
LimitNOFILE=999999
KillMode=process
StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
```

常用命令：

```bash
systemctl status lucky.daji
systemctl restart lucky.daji
journalctl -u lucky.daji -n 50 --no-pager
```

---

## 版本标记说明

脚本使用以下文件记录当前已安装版本：

```text
/opt/lucky.daji/.version
```

这个文件中的内容会作为本地版本判断依据。
只有在新版本安装成功并且服务启动成功后，才会写入新的版本号。

---

## 锁文件说明

为避免 `cron` 重复执行导致并发更新，脚本会创建锁文件：

```text
/var/run/lucky_update.lock
```

如果检测到已有运行中的更新进程，则本次执行会直接退出。

---

## 常见问题

### 1. 为什么没有更新？

可能原因：

* 当前已经是最新版本
* 发布页网络异常
* 下载地址不可用
* 远程网页结构变化
* 本地 `.version` 已与远端版本一致

### 2. 为什么通知里没有“节点”？

因为没有传 `-d` 参数。
如果你想显示节点名称，请在执行脚本时加上：

```bash
-d "你的节点名"
```

### 3. 为什么失败后还是保留了 backup 目录？

这是脚本设计行为。
`backup` 目录用于保存本次更新前的配置备份，即使升级失败，也会保留，方便你手动核对和恢复配置。

### 4. 备份会不会越积越多？

不会。
每次更新前都会先删除旧的 `backup` 目录，再重新备份。

### 5. 回滚能恢复哪些内容？

会恢复：

* 旧版本主程序和文件
* 旧 systemd 服务文件

不会删除：

* 新生成的 `backup` 配置备份目录

### 6. 为什么日志文件会被清空？

脚本内置了简单的日志维护逻辑。
当 `/var/log/lucky_update.log` 超过 10MB 时，会自动清空，避免日志无限增长。

---

## 建议

建议首次上线前先手动执行一次，确认以下内容正常：

* 远程版本可以正确获取
* 下载地址有效
* Lucky 服务可以正常启动
* Telegram / 企业微信通知正常
* `.lkcf` 配置文件可以正确备份
* 回滚逻辑在异常场景下符合预期

---

## 故障排查

### 查看脚本日志

```bash
tail -n 200 /var/log/lucky_update.log
```

### 查看服务状态

```bash
systemctl status lucky.daji
```

### 查看服务最近日志

```bash
journalctl -u lucky.daji -n 50 --no-pager
```

### 手动测试脚本执行

```bash
bash -x /usr/local/bin/lucky_update.sh
```

---

## 免责声明

本脚本适用于自动化部署 / 更新场景。
在生产环境使用前，建议先在测试节点验证完整流程，包括：

* 正常更新
* 更新失败回滚
* 配置备份恢复
* 服务重启

请根据你的实际环境自行评估风险。

---

## License

按你自己的使用方式处理即可。
