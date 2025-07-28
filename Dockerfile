# Render平台专用Dockerfile
# 基于官方OpenWebUI镜像，支持自动备份功能

FROM ghcr.io/open-webui/open-webui:main

# 安装必要的工具
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    git \
    jq \
    cron \
    && rm -rf /var/lib/apt/lists/*

# 复制备份脚本
COPY sync_data.sh /app/sync_data.sh
COPY start_with_backup.sh /app/start_with_backup.sh

# 设置权限
RUN chmod +x /app/sync_data.sh && \
    chmod +x /app/start_with_backup.sh && \
    chmod -R 777 /app/backend/data

# 切换回原用户
USER $UID:$GID

# 使用自定义启动脚本
CMD ["/app/start_with_backup.sh"]
