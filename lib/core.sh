#!/bin/bash
# ==============================================================================
# Z-Panel Pro - ??????
# ==============================================================================
# @description    ?????????????
# @version       7.1.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# ????
# ==============================================================================
readonly VERSION="7.1.0-Enterprise"
readonly BUILD_DATE="2026-01-17"

# ==============================================================================
# ????
# ==============================================================================
readonly INSTALL_DIR="/opt/z-panel"
readonly CONF_DIR="${INSTALL_DIR}/conf"
readonly LOG_DIR="${INSTALL_DIR}/logs"
readonly BACKUP_DIR="${INSTALL_DIR}/backup"
# LIB_DIR is defined in main script (Z-Panel.sh)

# ==============================================================================
# ??????
# ==============================================================================
readonly ZRAM_CONFIG_FILE="${CONF_DIR}/zram.conf"
readonly KERNEL_CONFIG_FILE="${CONF_DIR}/kernel.conf"
readonly STRATEGY_CONFIG_FILE="${CONF_DIR}/strategy.conf"
readonly LOG_CONFIG_FILE="${CONF_DIR}/log.conf"
readonly SWAP_CONFIG_FILE="${CONF_DIR}/swap.conf"

# ==============================================================================
# ?????
# ==============================================================================
readonly LOCK_FILE="/tmp/z-panel.lock"
readonly LOCK_FD=200

# ==============================================================================
# ????
# ==============================================================================
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_WHITE='\033[1;37m'
readonly COLOR_NC='\033[0m'

# ==============================================================================
# UI??
# ==============================================================================
readonly UI_WIDTH=62

# ==============================================================================
# ????
# ==============================================================================
readonly PROGRESS_THRESHOLD_CRITICAL=90
readonly PROGRESS_THRESHOLD_HIGH=70
readonly PROGRESS_THRESHOLD_MEDIUM=50

# ==============================================================================
# ?????
# ==============================================================================
readonly COMPRESSION_RATIO_EXCELLENT=3.0
readonly COMPRESSION_RATIO_GOOD=2.0
readonly COMPRESSION_RATIO_FAIR=1.5

# ==============================================================================
# Swap??
# ==============================================================================
readonly SWAP_FILE_PATH="/var/lib/z-panel/swapfile"
readonly ZRAM_PRIORITY=100
readonly PHYSICAL_SWAP_PRIORITY=50

# ==============================================================================
# ??????
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
# ???? - ???????????
# ==============================================================================
declare -gA CONFIG_CENTER=(
    # ????
    [cache_ttl]=3
    [refresh_interval]=1

    # ????
    [log_level]=1
    [log_max_size_mb]=50
    [log_retention_days]=30

    # Swap???
    [zram_priority]=100
    [physical_swap_priority]=50

    # ZRAM????
    [_zram_device_cache]=""
)

# ==============================================================================
# ?????
# ==============================================================================
get_config() {
    local key="$1"
    local default="${2:-}"
    echo "${CONFIG_CENTER[$key]:-$default}"
}

# ==============================================================================
# ?????
# ==============================================================================
set_config() {
    local key="$1"
    local value="$2"
    CONFIG_CENTER[$key]="$value"
}

# ==============================================================================
# ???????
# ==============================================================================
init_core() {
    # ??????
    mkdir -p "${INSTALL_DIR}"/{conf,logs,backup} 2>/dev/null || return 1

    # ??????
    chmod 750 "${INSTALL_DIR}" 2>/dev/null || true
    chmod 700 "${INSTALL_DIR}/conf" 2>/dev/null || true
    chmod 750 "${INSTALL_DIR}/logs" 2>/dev/null || true
    chmod 700 "${INSTALL_DIR}/backup" 2>/dev/null || true

    return 0
}
