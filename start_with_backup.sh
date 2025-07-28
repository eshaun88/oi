#!/bin/bash

# Render平台专用启动脚本
# 集成数据恢复和OpenWebUI启动

set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "=== Render OpenWebUI 启动脚本 ==="

# 确保数据目录存在
mkdir -p /app/backend/data

# 设置权限
chmod -R 755 /app/backend/data

# 启动时尝试恢复数据
log "检查是否需要恢复数据..."
if [ ! -f "/app/backend/data/webui.db" ]; then
    log "数据库文件不存在，尝试从WebDAV恢复..."
    /app/sync_data.sh restore || log "数据恢复失败，将使用空数据库启动"
else
    log "发现现有数据库文件，跳过恢复"
fi

# 启动后台同步服务
log "启动数据同步服务..."
/app/sync_data.sh sync &
SYNC_PID=$!

log "同步服务已启动 (PID: $SYNC_PID)"

# 设置信号处理，确保优雅关闭
cleanup() {
    log "接收到关闭信号，正在清理..."
    if [ ! -z "$SYNC_PID" ]; then
        log "停止同步服务..."
        kill $SYNC_PID 2>/dev/null || true
        wait $SYNC_PID 2>/dev/null || true
    fi
    
    # 最后一次备份
    log "执行最后一次备份..."
    /app/sync_data.sh backup || log "最后备份失败"
    
    log "清理完成"
    exit 0
}

trap cleanup SIGTERM SIGINT

# 启动OpenWebUI
log "启动OpenWebUI服务..."
log "数据目录: /app/backend/data"
log "端口: ${PORT:-8080}"
log "WebDAV URL: ${WEBDAV_URL:-未配置}"

# 执行原始启动脚本
exec bash /app/backend/start.sh
