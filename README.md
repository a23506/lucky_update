Lucky 自动更新运维脚本 (Multi-Arch)
本项目提供了一个轻量级的、非交互式的 Lucky 自动更新脚本，支持 x86_64 和 ARM64/armv7 架构。专门为已安装 Lucky 的 Linux 环境设计，支持定时检测、静默升级及双平台通知。

🚀 一键部署与定时任务
在 Root 用户下执行以下命令，即可完成脚本下载、权限设置并自动添加每晚 23:00 的定时任务：

curl -sSL https://raw.githubusercontent.com/a23506/lucky_update/main/auto_lucky.sh -o /root/auto_lucky.sh && \
chmod +x /root/auto_lucky.sh && \
(crontab -l 2>/dev/null | grep -v "auto_lucky.sh"; echo "0 23 * * * /bin/bash /root/auto_lucky.sh >> /var/log/lucky_update.log 2>&1") | crontab - && \
echo "Lucky 自动更新环境配置完成！"
