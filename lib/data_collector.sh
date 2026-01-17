#!/bin/bash
# ==============================================================================
# Z-Panel Pro - 数据采集模块
# ==============================================================================
# @description    系统数据采集与缓存管理
# @version       7.1.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 缓存配置
# ==============================================================================
declare -g CACHE_TTL=3
declare -g CACHE_LAST_UPDATE=0
declare -gA CACHE_DATA=()

# ==============================================================================
# 缓存管理函数
# ==============================================================================

# 更新缓存
update_cache() {
    local current_time
    current_time=$(get_timestamp)
    local cache_age=$((current_time - CACHE_LAST_UPDATE))

    if [[ ${cache_age} -lt ${CACHE_TTL} ]]; then
        log_debug "缓存未过期 (年龄: ${cache_age}s, TTL: ${CACHE_TTL}s)"
        return 0
    fi

    log_debug "更新缓存..."

    # 一次性获取内存信息（减少系统调用）
    local mem_info
    mem_info=$(free -m | awk '/^Mem:/ {print $2, $3, $7, $6}')
    read -r CACHE_DATA[mem_total] CACHE_DATA[mem_used] CACHE_DATA[mem_avail] CACHE_DATA[buff_cache] <<< "${mem_info}"

    # 一次性获取Swap信息
    local swap_info
    swap_info=$(free -m | awk '/Swap:/ {print $2, $3}')
    read -r CACHE_DATA[swap_total] CACHE_DATA[swap_used] <<< "${swap_info}"

    # 获取ZRAM状态缓存
    CACHE_DATA[zram_enabled]=$(is_zram_enabled && echo "1" || echo "0")

    CACHE_LAST_UPDATE=${current_time}
    log_debug "缓存已更新"
}

# 清除缓存
clear_cache() {
    CACHE_DATA=()
    CACHE_LAST_UPDATE=0
    log_debug "缓存已清除"
}

# 获取缓存值
get_cache_value() {
    local key="$1"
    echo "${CACHE_DATA[$key]:-}"
}

# ==============================================================================
# 内存信息采集
# ==============================================================================

# 获取内存信息
# @param use_cache: 是否使用缓存（true/false，默认true）
# @return: "total used avail buff_cache"
get_memory_info() {
    local use_cache="${1:-true}"

    if [[ "${use_cache}" == "true" ]]; then
        update_cache
        echo "${CACHE_DATA[mem_total]} ${CACHE_DATA[mem_used]} ${CACHE_DATA[mem_avail]} ${CACHE_DATA[buff_cache]}"
    else
        free -m | awk '/^Mem:/ {print $2, $3, $7, $6}'
    fi
}

# 获取内存使用率
# @param use_cache: 是否使用缓存（true/false，默认true）
# @return: 使用率百分比
get_memory_usage() {
    local use_cache="${1:-true}"
    local mem_total mem_used
    read -r mem_total mem_used _ _ <<< "$(get_memory_info "${use_cache}")"

    calculate_percentage "${mem_used}" "${mem_total}"
}

# ==============================================================================
# Swap信息采集
# ==============================================================================

# 获取Swap信息
# @param use_cache: 是否使用缓存（true/false，默认true）
# @return: "total used"
get_swap_info() {
    local use_cache="${1:-true}"

    if [[ "${use_cache}" == "true" ]]; then
        update_cache
        echo "${CACHE_DATA[swap_total]} ${CACHE_DATA[swap_used]}"
    else
        free -m | awk '/Swap:/ {print $2, $3}'
    fi
}

# 获取Swap使用率
# @param use_cache: 是否使用缓存（true/false，默认true）
# @return: 使用率百分比
get_swap_usage() {
    local use_cache="${1:-true}"
    local swap_total swap_used
    read -r swap_total swap_used <<< "$(get_swap_info "${use_cache}")"

    calculate_percentage "${swap_used}" "${swap_total}"
}

# ==============================================================================
# ZRAM信息采集
# ==============================================================================

# 检查ZRAM是否启用
# @return: 0为启用，1为未启用
is_zram_enabled() {
    swapon --show=NAME --noheadings 2>/dev/null | grep -q zram
}

# 获取ZRAM使用情况
# @return: "total_mb used_mb"
get_zram_usage() {
    if ! is_zram_enabled; then
        echo "0 0"
        return
    fi

    local zram_info
    zram_info=$(swapon --show=SIZE,USED --noheadings 2>/dev/null | grep zram | head -1)

    if [[ -z "${zram_info}" ]]; then
        echo "0 0"
        return
    fi

    # 使用统一的单位转换函数
    local zram_total zram_used
    zram_total=$(echo "${zram_info}" | awk '{print $1}')
    zram_used=$(echo "${zram_info}" | awk '{print $2}')

    zram_total=$(convert_size_to_mb "${zram_total}")
    zram_used=$(convert_size_to_mb "${zram_used}")

    [[ -z "${zram_total}" ]] || [[ "${zram_total}" == "0" ]] && zram_total=1
    [[ -z "${zram_used}" ]] && zram_used=0

    echo "${zram_total} ${zram_used}"
}

# 获取ZRAM使用率
# @return: 使用率百分比
get_zram_usage_percent() {
    local zram_total zram_used
    read -r zram_total zram_used <<< "$(get_zram_usage)"

    calculate_percentage "${zram_used}" "${zram_total}"
}

# 获取ZRAM状态（JSON格式）
# @return: JSON字符串
get_zram_status() {
    if ! check_command zramctl; then
        echo '{"enabled": false}'
        return
    fi

    local zram_info
    zram_info=$(zramctl 2>/dev/null | tail -n +2)

    if [[ -z "${zram_info}" ]]; then
        echo '{"enabled": false}'
        return
    fi

    local name disk_size data_size comp_size algo
    read -r name disk_size data_size comp_size algo <<< "${zram_info}"

    local compression_ratio="0"
    if [[ -n "${data_size}" ]] && [[ -n "${comp_size}" ]] && [[ "${comp_size}" != "0" ]]; then
        compression_ratio=$(echo "${data_size} ${comp_size}" | awk '{
            data_num = $1
            comp_num = $2
            gsub(/[KMGT]/, "", data_num)
            gsub(/[KMGT]/, "", comp_num)
            if (comp_num > 0 && data_num > 0) {
                printf "%.2f", data_num / comp_num
            }
        }')
    fi

    cat <<EOF
{
    "enabled": true,
    "device": "${name}",
    "disk_size": "${disk_size}",
    "data_size": "${data_size}",
    "comp_size": "${comp_size}",
    "algorithm": "${algo}",
    "compression_ratio": "${compression_ratio}"
}
EOF
}

# 获取ZRAM压缩算法
# @return: 算法名称
get_zram_algorithm() {
    local zram_status
    zram_status=$(get_zram_status)

    if echo "${zram_status}" | grep -q "enabled.*true"; then
        echo "${zram_status}" | grep -o '"algorithm":"[^"]*"' | cut -d'"' -f4
    else
        echo "unknown"
    fi
}

# 获取ZRAM压缩比
# @return: 压缩比（浮点数）
get_zram_compression_ratio() {
    local zram_status
    zram_status=$(get_zram_status)

    if echo "${zram_status}" | grep -q "enabled.*true"; then
        echo "${zram_status}" | grep -o '"compression_ratio":"[^"]*"' | cut -d'"' -f4
    else
        echo "1.00"
    fi
}

# ==============================================================================
# CPU信息采集
# ==============================================================================

# 获取CPU核心数
# @return: 核心数
get_cpu_cores() {
    nproc 2>/dev/null || echo "1"
}

# 获取CPU使用率
# @return: 使用率百分比
get_cpu_usage() {
    # 获取CPU使用率（简化版）
    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')

    echo "${cpu_usage:-0}"
}

# ==============================================================================
# 磁盘信息采集
# ==============================================================================

# 获取磁盘使用情况
# @param path: 路径（默认/）
# @return: "total_mb used_mb avail_mb usage_percent"
get_disk_info() {
    local path="${1:-/}"
    df -m "${path}" | awk 'NR==2 {print $2, $3, $4, $5}'
}

# ==============================================================================
# 内核参数采集
# ==============================================================================

# 获取内核参数
# @param param: 参数名
# @return: 参数值
get_kernel_param() {
    local param="$1"
    sysctl -n "${param}" 2>/dev/null || echo ""
}

# 获取swappiness值
# @return: swappiness值
get_swappiness() {
    get_kernel_param "vm.swappiness"
}

# ==============================================================================
# 系统负载采集
# ==============================================================================

# 获取系统负载
# @return: "1min 5min 15min"
get_load_average() {
    awk '{print $1, $2, $3}' /proc/loadavg
}