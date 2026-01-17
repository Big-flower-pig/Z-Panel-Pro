#!/bin/bash
# ==============================================================================
# Z-Panel Pro V8.0 - 核心配置模块
# ==============================================================================
# @description    全局配置、常量定义和配置中心
# @version       8.0.0-Enterprise
# @author        Z-Panel Team
# @license       MIT License
# ==============================================================================

# ==============================================================================
# 版本信息
# ==============================================================================
readonly VERSION="8.0.0-Enterprise"
readonly BUILD_DATE="2026-01-17"
readonly CODENAME="Intelligent"

# ==============================================================================
# 目录结构
# ==============================================================================
readonly INSTALL_DIR="/opt/z-panel"
readonly CONF_DIR="${INSTALL_DIR}/conf"
readonly LOG_DIR="${INSTALL_DIR}/logs"
readonly BACKUP_DIR="${INSTALL_DIR}/backup"
readonly CACHE_DIR="${INSTALL_DIR}/cache"
readonly DATA_DIR="${INSTALL_DIR}/data"
readonly RUN_DIR="${INSTALL_DIR}/run"

# LIB_DIR: 如果未定义则使用脚本所在目录
if [[ -z "${LIB_DIR}" ]]; then
    readonly LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    readonly LIB_DIR="${LIB_DIR}"
fi

# ==============================================================================
# 配置文件路径
# ==============================================================================
readonly ZRAM_CONFIG_FILE="${CONF_DIR}/zram.conf"
readonly KERNEL_CONFIG_FILE="${CONF_DIR}/kernel.conf"
readonly STRATEGY_CONFIG_FILE="${CONF_DIR}/strategy.conf"
readonly LOG_CONFIG_FILE="${CONF_DIR}/log.conf"
readonly SWAP_CONFIG_FILE="${CONF_DIR}/swap.conf"

# V8.0 新增配置文件
readonly DECISION_ENGINE_CONFIG="${CONF_DIR}/decision_engine.conf"
readonly STREAM_PROCESSOR_CONFIG="${CONF_DIR}/stream_processor.conf"
readonly CACHE_CONFIG="${CONF_DIR}/cache.conf"
readonly FEEDBACK_CONFIG="${CONF_DIR}/feedback.conf"
readonly ADAPTIVE_TUNER_CONFIG="${CONF_DIR}/adaptive_tuner.conf"

# 轻量级模式配置文件
readonly LIGHTWEIGHT_CONFIG="${CONF_DIR}/lightweight.conf"

# ==============================================================================
# 锁文件
# ==============================================================================
readonly LOCK_FILE="/tmp/z-panel.lock"
readonly LOCK_FD=200

# V8.0 新增锁文件
readonly DECISION_ENGINE_LOCK="${RUN_DIR}/decision_engine.lock"
readonly STREAM_PROCESSOR_LOCK="${RUN_DIR}/stream_processor.lock"
readonly ADAPTIVE_TUNER_LOCK="${RUN_DIR}/adaptive_tuner.lock"

# ==============================================================================
# 颜色定义
# ==============================================================================
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_MAGENTA='\033[0;35m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_WHITE='\033[1;37m'
readonly COLOR_GRAY='\033[0;90m'
readonly COLOR_NC='\033[0m'

# ==============================================================================
# UI配置
# ==============================================================================
readonly UI_WIDTH=62
readonly UI_PADDING=2

# ==============================================================================
# 进度阈值
# ==============================================================================
readonly PROGRESS_THRESHOLD_CRITICAL=90
readonly PROGRESS_THRESHOLD_HIGH=70
readonly PROGRESS_THRESHOLD_MEDIUM=50

# V8.0 新增阈值
readonly MEMORY_PRESSURE_CRITICAL=90
readonly MEMORY_PRESSURE_HIGH=70
readonly MEMORY_PRESSURE_MEDIUM=50
readonly MEMORY_PRESSURE_LOW=30

# ==============================================================================
# 压缩比率标准
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
# 系统信息缓存
# ==============================================================================
declare -gA SYSTEM_INFO=(
    [distro]=""
    [version]=""
    [package_manager]=""
    [total_memory_mb]=0
    [cpu_cores]=0
    [architecture]=""
    [kernel_version]=""
    [uptime]=0
    [is_container]=false
    [is_virtual]=false
)

# ==============================================================================
# 运行时状态
# ==============================================================================
declare -g STRATEGY_MODE="balance"
declare -g ZRAM_ENABLED=false
declare -g SWAP_ENABLED=false

# V8.0 新增状态
declare -g DECISION_ENGINE_RUNNING=false
declare -g STREAM_PROCESSOR_RUNNING=false
declare -g ADAPTIVE_TUNER_RUNNING=false

# 轻量级模式状态
declare -g ZPANEL_MODE="${ZPANEL_MODE:-standard}"  # lightweight | standard | enterprise

# ==============================================================================
# 配置中心 - 统一配置管理
# ==============================================================================
declare -gA CONFIG_CENTER=(
    # 缓存配置
    [cache_ttl]=3
    [cache_enabled]=true
    [cache_max_size]=1000
    [refresh_interval]=1

    # 日志配置
    [log_level]=1
    [log_max_size_mb]=50
    [log_retention_days]=30
    [log_file_rotation]=true

    # Swap配置
    [zram_priority]=100
    [physical_swap_priority]=50
    [swap_file_path]="${SWAP_FILE_PATH}"

    # ZRAM配置
    [_zram_device_cache]=""
    [zram_compression]="lzo"
    [zram_max_streams]=4

    # 内核配置
    [swappiness]=60
    [vfs_cache_pressure]=100
    [dirty_ratio]=20
    [dirty_background_ratio]=10

    # V8.0 智能配置
    [decision_engine_enabled]=false
    [decision_engine_interval]=5
    [stream_processor_enabled]=false
    [adaptive_tuning_enabled]=false
    [adaptive_tuning_mode]=auto

    # 轻量级模式配置
    [mode]="standard"
    [web_ui_enabled]=true
    [api_enabled]=true
    [monitoring_enabled]=true
    [tui_enabled]=true
    [decision_engine_enabled_mode]=true
    [db_type]="timeseries"  # memory | timeseries | postgresql
    [max_memory]="2G"
    [zram_enabled_mode]=true
    [zram_size]="256M"

    # 性能配置
    [io_fuse_threshold]=80
    [memory_pressure_threshold]=70
    [swap_usage_threshold]=50
)

# ==============================================================================
# 获取配置
# ==============================================================================
get_config() {
    local key="$1"
    local default="${2:-}"
    echo "${CONFIG_CENTER[$key]:-$default}"
}

# ==============================================================================
# 设置配置
# ==============================================================================
set_config() {
    local key="$1"
    local value="$2"
    CONFIG_CENTER[$key]="${value}"
}

# ==============================================================================
# 批量设置配置
# ==============================================================================
set_config_batch() {
    local -n config_ref="$1"
    for key in "${!config_ref[@]}"; do
        CONFIG_CENTER["${key}"]="${config_ref[$key]}"
    done
}

# ==============================================================================
# 获取所有配置
# ==============================================================================
get_all_config() {
    local output=""
    for key in "${!CONFIG_CENTER[@]}"; do
        output+="${key}=${CONFIG_CENTER[$key]}"$'\n'
    done
    echo "${output}"
}

# ==============================================================================
# 保存配置到文件
# ==============================================================================
save_config() {
    local config_file="$1"
    local section="${2:-zpanel}"

    mkdir -p "$(dirname "${config_file}")" 2>/dev/null || return 1

    {
        echo "# Z-Panel Pro Configuration"
        echo "# Generated on $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# Version: ${VERSION}"
        echo ""
        echo "[${section}]"
        for key in "${!CONFIG_CENTER[@]}"; do
            echo "${key}=${CONFIG_CENTER[$key]}"
        done
    } > "${config_file}" 2>/dev/null || return 1

    chmod 600 "${config_file}" 2>/dev/null || true
    log_debug "配置已保存: ${config_file}"
    return 0
}

# ==============================================================================
# 从文件加载配置
# ==============================================================================
load_config() {
    local config_file="$1"

    [[ ! -f "${config_file}" ]] && return 1

    while IFS='=' read -r key value; do
        # 跳过注释和空行
        [[ "${key}" =~ ^#.*$ ]] && continue
        [[ -z "${key}" ]] && continue
        [[ "${key}" =~ ^\[.*\]$ ]] && continue

        # 移除值两端的引号
        value="${value#\"}"
        value="${value%\"}"

        CONFIG_CENTER["${key}"]="${value}"
    done < "${config_file}"

    log_debug "配置已加载: ${config_file}"
    return 0
}

# ==============================================================================
# 验证配置
# ==============================================================================
validate_config() {
    local errors=0

    # 验证数值范围
    local swappiness="${CONFIG_CENTER[swappiness]}"
    if [[ ${swappiness} -lt 0 ]] || [[ ${swappiness} -gt 100 ]]; then
        log_error "无效的swappiness值: ${swappiness} (范围: 0-100)"
        ((errors++))
    fi

    # 验证路径
    if [[ ! -d "$(dirname "${CONFIG_CENTER[swap_file_path]}")" ]]; then
        log_warn "Swap文件目录不存在: $(dirname "${CONFIG_CENTER[swap_file_path]}")"
    fi

    # 验证布尔值
    local bool_keys=("zram_enabled" "swap_enabled" "decision_engine_enabled")
    for key in "${bool_keys[@]}"; do
        local value="${CONFIG_CENTER[$key]}"
        if [[ "${value}" != "true" ]] && [[ "${value}" != "false" ]]; then
            log_warn "无效的布尔值配置: ${key}=${value}"
        fi
    done

    return ${errors}
}

# ==============================================================================
# 重置配置为默认值
# ==============================================================================
reset_config() {
    CONFIG_CENTER=(
        [cache_ttl]=3
        [cache_enabled]=true
        [cache_max_size]=1000
        [refresh_interval]=1
        [log_level]=1
        [log_max_size_mb]=50
        [log_retention_days]=30
        [log_file_rotation]=true
        [zram_priority]=100
        [physical_swap_priority]=50
        [swap_file_path]="${SWAP_FILE_PATH}"
        [_zram_device_cache]=""
        [zram_compression]="lzo"
        [zram_max_streams]=4
        [swappiness]=60
        [vfs_cache_pressure]=100
        [dirty_ratio]=20
        [dirty_background_ratio]=10
        [decision_engine_enabled]=false
        [decision_engine_interval]=5
        [stream_processor_enabled]=false
        [adaptive_tuning_enabled]=false
        [adaptive_tuning_mode]=auto
        [io_fuse_threshold]=80
        [memory_pressure_threshold]=70
        [swap_usage_threshold]=50
        [mode]="standard"
        [web_ui_enabled]=true
        [api_enabled]=true
        [monitoring_enabled]=true
        [tui_enabled]=true
        [decision_engine_enabled_mode]=true
        [db_type]="timeseries"
        [max_memory]="2G"
        [zram_enabled_mode]=true
        [zram_size]="256M"
    )

    log_info "配置已重置为默认值"
    return 0
}

# ==============================================================================
# 导出配置为环境变量
# ==============================================================================
export_config_env() {
    for key in "${!CONFIG_CENTER[@]}"; do
        # 转换为大写并替换点为下划线
        local env_key="ZPANEL_${key^^}"
        export "${env_key}=${CONFIG_CENTER[$key]}"
    done
}

# ==============================================================================
# 初始化核心模块
# ==============================================================================
init_core() {
    # 创建目录结构
    local dirs=(
        "${INSTALL_DIR}"
        "${CONF_DIR}"
        "${LOG_DIR}"
        "${BACKUP_DIR}"
        "${CACHE_DIR}"
        "${DATA_DIR}"
        "${RUN_DIR}"
    )

    for dir in "${dirs[@]}"; do
        mkdir -p "${dir}" 2>/dev/null || {
            log_error "无法创建目录: ${dir}"
            return 1
        }
    done

    # 设置目录权限
    chmod 750 "${INSTALL_DIR}" 2>/dev/null || true
    chmod 700 "${CONF_DIR}" 2>/dev/null || true
    chmod 750 "${LOG_DIR}" 2>/dev/null || true
    chmod 700 "${BACKUP_DIR}" 2>/dev/null || true
    chmod 750 "${CACHE_DIR}" 2>/dev/null || true
    chmod 750 "${DATA_DIR}" 2>/dev/null || true
    chmod 750 "${RUN_DIR}" 2>/dev/null || true

    # 验证配置
    validate_config

    log_debug "核心模块初始化完成"
    return 0
}

# ==============================================================================
# 获取版本信息
# ==============================================================================
get_version_info() {
    cat <<EOF
Z-Panel Pro ${VERSION} (${CODENAME})
Build Date: ${BUILD_DATE}
Enterprise Edition
EOF
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f get_config
export -f set_config
export -f set_config_batch
export -f get_all_config
export -f save_config
export -f load_config
export -f validate_config
export -f reset_config
export -f export_config_env
