#!/bin/bash
# ==============================================================================
# Z-Panel Pro - 核心配置模块
# ==============================================================================
# @description    核心配置常量与全局状态管理
# @version       7.1.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 版本信息
# ==============================================================================
readonly VERSION="7.1.0-Enterprise"
readonly BUILD_DATE="2026-01-17"

# ==============================================================================
# 目录配置
# ==============================================================================
readonly INSTALL_DIR="/opt/z-panel"
readonly CONF_DIR="${INSTALL_DIR}/conf"
readonly LOG_DIR="${INSTALL_DIR}/logs"
readonly BACKUP_DIR="${INSTALL_DIR}/backup"
readonly LIB_DIR="${INSTALL_DIR}/lib"

# ==============================================================================
# 配置文件路径
# ==============================================================================
readonly ZRAM_CONFIG_FILE="${CONF_DIR}/zram.conf"
readonly KERNEL_CONFIG_FILE="${CONF_DIR}/kernel.conf"
readonly STRATEGY_CONFIG_FILE="${CONF_DIR}/strategy.conf"
readonly LOG_CONFIG_FILE="${CONF_DIR}/log.conf"
readonly SWAP_CONFIG_FILE="${CONF_DIR}/swap.conf"

# ==============================================================================
# 文件锁配置
# ==============================================================================
readonly LOCK_FILE="/tmp/z-panel.lock"
readonly LOCK_FD=200

# ==============================================================================
# 颜色配置
# ==============================================================================
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_WHITE='\033[1;37m'
readonly COLOR_NC='\033[0m'

# ==============================================================================
# UI配置
# ==============================================================================
readonly UI_WIDTH=62

# ==============================================================================
# 阈值配置
# ==============================================================================
readonly PROGRESS_THRESHOLD_CRITICAL=90
readonly PROGRESS_THRESHOLD_HIGH=70
readonly PROGRESS_THRESHOLD_MEDIUM=50

# ==============================================================================
# 压缩比阈值
# ==============================================================================
readonly COMPRESSION_RATIO_EXCELLENT=3.0
readonly COMPRESSION_RATIO_GOOD=2.0
readonly COMPRESSION_RATIO_FAIR=1.5

# ==============================================================================
# Swap配置
# ==============================================================================
readonly SWAP_FILE_PATH="/var/lib/z-panel/swapfile"
readonly ZRAM_PRIORITY=100
readonly PHYSICAL_SWAP_PRIORITY=50

# ==============================================================================
# 全局状态变量
# ==============================================================================
declare -gA SYSTEM_INFO=(
    [distro]=""
    [version]=""
    [package_manager]=""
    [total_memory_mb]=0
    [cpu_cores]=0
)

declare -g STRATEGY_MODE="balance"
declare -g ZRAM_ENABLED=false
declare -g SWAP_ENABLED=false

# ==============================================================================
# 配置中心 - 集中管理所有可配置参数
# ==============================================================================
declare -gA CONFIG_CENTER=(
    # 缓存配置
    [cache_ttl]=3
    [refresh_interval]=1

    # 日志配置
    [log_level]=1
    [log_max_size_mb]=50
    [log_retention_days]=30

    # Swap优先级
    [zram_priority]=100
    [physical_swap_priority]=50

    # ZRAM设备缓存
    [_zram_device_cache]=""
)

# ==============================================================================
# 获取配置值
# ==============================================================================
get_config() {
    local key="$1"
    local default="${2:-}"
    echo "${CONFIG_CENTER[$key]:-$default}"
}

# ==============================================================================
# 设置配置值
# ==============================================================================
set_config() {
    local key="$1"
    local value="$2"
    CONFIG_CENTER[$key]="$value"
}

# ==============================================================================
# 初始化核心模块
# ==============================================================================
init_core() {
    # 创建必要目录
    mkdir -p "${INSTALL_DIR}"/{conf,logs,backup} 2>/dev/null || return 1

    # 设置目录权限
    chmod 750 "${INSTALL_DIR}" 2>/dev/null || true
    chmod 700 "${INSTALL_DIR}/conf" 2>/dev/null || true
    chmod 750 "${INSTALL_DIR}/logs" 2>/dev/null || true
    chmod 700 "${INSTALL_DIR}/backup" 2>/dev/null || true

    return 0
}