#!/bin/bash

# Render平台优化的数据同步脚本
# 适配Render的环境变量和文件系统特性

set -e

# 创建数据目录
mkdir -p /app/backend/data

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 生成校验和文件
generate_sum() {
    local file=$1
    local sum_file=$2
    if [ -f "$file" ]; then
        sha256sum "$file" > "$sum_file"
    fi
}

# 验证环境变量
check_env() {
    if [ -z "$WEBDAV_URL" ] || [ -z "$WEBDAV_USERNAME" ] || [ -z "$WEBDAV_PASSWORD" ]; then
        log "警告: WebDAV环境变量未完全配置，跳过备份功能"
        return 1
    fi
    return 0
}

# 从WebDAV恢复数据
restore_from_webdav() {
    log "尝试从WebDAV恢复数据..."
    
    if ! check_env; then
        return 1
    fi
    
    # 尝试下载数据库文件
    if curl -L --fail --connect-timeout 30 --max-time 300 \
        --user "$WEBDAV_USERNAME:$WEBDAV_PASSWORD" \
        "$WEBDAV_URL/webui.db" -o "/app/backend/data/webui.db.tmp"; then
        
        # 验证下载的文件
        if [ -s "/app/backend/data/webui.db.tmp" ]; then
            mv "/app/backend/data/webui.db.tmp" "/app/backend/data/webui.db"
            log "从WebDAV恢复数据成功"
            return 0
        else
            log "下载的数据库文件为空"
            rm -f "/app/backend/data/webui.db.tmp"
        fi
    else
        log "从WebDAV恢复失败"
        rm -f "/app/backend/data/webui.db.tmp"
    fi
    
    return 1
}

# 备份到WebDAV
backup_to_webdav() {
    local db_file="/app/backend/data/webui.db"
    
    if [ ! -f "$db_file" ]; then
        log "数据库文件不存在，跳过备份"
        return 1
    fi
    
    if ! check_env; then
        return 1
    fi
    
    log "开始备份到WebDAV..."
    
    # 上传数据库文件
    if curl -L -T "$db_file" --connect-timeout 30 --max-time 300 \
        --user "$WEBDAV_USERNAME:$WEBDAV_PASSWORD" \
        "$WEBDAV_URL/webui.db"; then
        log "WebDAV备份成功"
        return 0
    else
        log "WebDAV备份失败，重试一次..."
        sleep 5
        if curl -L -T "$db_file" --connect-timeout 30 --max-time 300 \
            --user "$WEBDAV_USERNAME:$WEBDAV_PASSWORD" \
            "$WEBDAV_URL/webui.db"; then
            log "WebDAV备份重试成功"
            return 0
        else
            log "WebDAV备份重试失败"
            return 1
        fi
    fi
}

# 每日备份（带日期标记）
daily_backup() {
    local db_file="/app/backend/data/webui.db"
    
    if [ ! -f "$db_file" ]; then
        log "数据库文件不存在，跳过每日备份"
        return 1
    fi
    
    if ! check_env; then
        return 1
    fi
    
    local date_str=$(date '+%Y%m%d')
    local backup_filename="webui_${date_str}.db"
    
    log "开始每日备份: $backup_filename"
    
    if curl -L -T "$db_file" --connect-timeout 30 --max-time 300 \
        --user "$WEBDAV_USERNAME:$WEBDAV_PASSWORD" \
        "$WEBDAV_URL/$backup_filename"; then
        log "每日备份成功: $backup_filename"
        return 0
    else
        log "每日备份失败: $backup_filename"
        return 1
    fi
}

# 主同步循环
sync_loop() {
    local db_file="/app/backend/data/webui.db"
    local sum_file="/app/backend/data/webui.db.sha256"
    local new_sum_file="/app/backend/data/webui.db.sha256.new"
    local last_daily_backup=""
    
    while true; do
        # 检查文件是否存在并且有变化
        if [ -f "$db_file" ]; then
            generate_sum "$db_file" "$new_sum_file"
            
            # 检查文件是否变化
            if [ ! -f "$sum_file" ] || ! cmp -s "$new_sum_file" "$sum_file"; then
                log "检测到数据库变化，开始同步..."
                mv "$new_sum_file" "$sum_file"
                
                # 备份到WebDAV
                backup_to_webdav
            else
                log "数据库无变化，跳过同步"
                rm -f "$new_sum_file"
            fi
        else
            log "数据库文件不存在"
        fi
        
        # 检查是否需要每日备份（每天执行一次）
        current_date=$(date '+%Y%m%d')
        if [ "$current_date" != "$last_daily_backup" ]; then
            current_hour=$(date '+%H')
            # 在凌晨0-1点之间执行每日备份
            if [ "$current_hour" = "00" ] || [ "$current_hour" = "01" ]; then
                daily_backup
                last_daily_backup="$current_date"
            fi
        fi
        
        log "下次检查时间: $(date -d '+30 minutes' '+%Y-%m-%d %H:%M:%S')"
        # Render平台优化：减少检查频率以节省资源
        sleep 1800  # 30分钟检查一次
    done
}

# 根据参数执行不同操作
case "${1:-sync}" in
    "restore")
        restore_from_webdav
        ;;
    "backup")
        backup_to_webdav
        ;;
    "daily")
        daily_backup
        ;;
    "sync")
        log "启动数据同步服务..."
        sync_loop
        ;;
    *)
        log "用法: $0 {restore|backup|daily|sync}"
        exit 1
        ;;
esac
