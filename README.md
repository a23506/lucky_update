# Lucky 自动更新运维脚本 (Multi-Arch)

本项目提供了一个轻量级、非交互式的 Lucky 自动更新脚本。它旨在解决官方脚本在定时自动化任务中需要人工干预的问题，并针对特定运维需求进行了深度定制。

## 🌟 核心特性

* **多架构自适应**：自动识别 `x86_64`、`arm64` (aarch64) 或 `armv7` 架构，并动态拼接对应的官方下载链接。
* **静默安装**：模拟官方脚本 `install.sh` 的版本抓取逻辑，无需人工输入数字选择版本或目录。
* **精准进程释放**：在更新重启前，强制清理占用 `16601` 端口的旧进程，确保新版本服务顺利启动。
* **双平台通知**：集成 Telegram 和企业微信 Webhook 通知，支持 Markdown 格式，实时反馈更新状态、版本号及编译日期。

## 🚀 一键部署

在 **Root** 用户下执行以下命令，脚本将自动下载到 `/root` 目录，赋予执行权限，并添加每晚 23:00 执行的 Cron 定时任务：

```bash
curl -sSL [https://raw.githubusercontent.com/a23506/lucky_update/main/auto_lucky.sh](https://raw.githubusercontent.com/a23506/lucky_update/main/auto_lucky.sh) -o /root/auto_lucky.sh && \
chmod +x /root/auto_lucky.sh && \
(crontab -l 2>/dev/null | grep -v "auto_lucky.sh"; echo "0 23 * * * /bin/bash /root/auto_lucky.sh >> /var/log/lucky_update.log 2>&1") | crontab - && \
echo "Lucky 自动更新环境配置完成！"


```bash
curl -sSL https://raw.githubusercontent.com/a23506/lucky_update/main/auto_lucky.sh | bash
