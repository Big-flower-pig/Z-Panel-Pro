#!/bin/bash
# ==============================================================================
# Z-Panel Pro V8.0 - 自适应调优模块
# ==============================================================================
# @description    根据系统状态动态调整swappiness、ZRAM大小和压缩算法
# @version       8.0.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 自适应调优配置
# ==============================================================================
declare -gA ADAPTIVE_TUNER=(
    # 调优模式
    [mode]="auto"                   # auto/conservative/aggressive/emergency

    # Swappiness配置
    [swappiness_min]="1"             # 最小swappiness值
    [swappiness_max]="100"           # 最大swappiness值
    [swappiness_default]="60"        # 默认swappiness值
    [swappiness_adjust_step]="5"     # 调整步长

    # ZRAM配置
    [zram_min_mb]="256"              # 最小ZRAM大小（MB）
    [zram_max_mb]="8192"             # 最大ZRAM大小（MB）
    [zram_default_mb]="2048"         # 默认ZRAM大小（MB）
    [zram_adjust_step]="256"         # 调整步长（MB）

    # 压缩算法配置
    [compression_algorithms]="lzo,lzo-rle,lz4,zstd"  # 支持的压缩算法
    [compression_default]="lzo"     # 默认压缩算法

    # 调优间隔
    [tuning_interval]="60"           # 调优间隔（秒）
    [min_adjustment_interval]="300" # 最小调整间隔（秒）

    # 阈值
    [memory_pressure_high]="80"     # 内存压力高阈值
    [memory_pressure_low]="30"       # 内存压力低阈值
    [swap_usage_high]="50"          # Swap使用率高阈值
    [swap_usage_low]="10"            # Swap使用率低阈值
)

# ==============================================================================
# 调优历史记录
# ==============================================================================
declare -gA ADAPTIVE_HISTORY=(
    [count]="0"
    [last_adjustment_time]="0"
)

# 调优记录数组
declare -ga ADAPTIVE_ADJUSTMENTS=()

# ==============================================================================
# 当前状态快照
# ==============================================================================
declare -gA ADAPTIVE_CURRENT_STATE=(
    [swappiness]=""
    [zram_size]=""
    [compression_algo]=""
    [memory_percent]=""
    [swap_percent]=""
    [timestamp]=""
)

# ==============================================================================
# 压缩算法性能数据
# ==============================================================================
declare -gA COMPRESSION_PERFORMANCE=(
    [lzo_speed]="1.0"
    [lzo_ratio]="2.0"
    [lzo-rle_speed]="1.1"
    [lzo-rle_ratio]="2.1"
    [lz4_speed]="2.0"
    [lz4_ratio]="1.8"
    [zstd_speed]="0.8"
    [zstd_ratio]="3.0"
)

# ==============================================================================
# 状态获取函数
# ==============================================================================

# 获取当前系统状态
get_adaptive_state() {
    # 获取内存使用率
    local mem_info=$(free | awk '/^Mem:/ {printf "%.1f", $3/$2*100}')
    ADAPTIVE_CURRENT_STATE[memory_percent]="${mem_info}"

    # 获取Swap使用率
    local swap_total=$(free | awk '/^Swap:/ {print $2}')
    local swap_used=$(free | awk '/^Swap:/ {print $3}')
    local swap_percent="0"
    [[ ${swap_total} -gt 0 ]] && {
        swap_percent=$(awk "BEGIN {printf \"%.1f\", ${swap_used}/${swap_total}*100}")
    }
    ADAPTIVE_CURRENT_STATE[swap_percent]="${swap_percent}"

    # 获取当前swappiness
    ADAPTIVE_CURRENT_STATE[swappiness]=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "60")

    # 获取ZRAM信息
    if [[ -d /sys/block/zram0 ]]; then
        local zram_size_kb=$(cat /sys/block/zram0/disksize 2>/dev/null || echo "0")
        ADAPTIVE_CURRENT_STATE[zram_size]=$(awk "BEGIN {printf \"%.0f\", ${zram_size_kb}/1024}")
    else
        ADAPTIVE_CURRENT_STATE[zram_size]="0"
    fi

    # 获取压缩算法
    ADAPTIVE_CURRENT_STATE[compression_algo]="${CONFIG[zram_compression]:-lzo}"

    # 更新时间戳
    ADAPTIVE_CURRENT_STATE[timestamp]=$(date +%s)

    log_debug "获取自适应调优状态: 内存=${mem_info}%, Swap=${swap_percent}%"
    return 0
}

# ==============================================================================
# Swappiness自适应调优
# ==============================================================================

# 计算推荐的swappiness值
# @return: 推荐的swappiness值
calculate_swappiness() {
    local mem_percent="${ADAPTIVE_CURRENT_STATE[memory_percent]}"
    local swap_percent="${ADAPTIVE_CURRENT_STATE[swap_percent]}"
    local current_swappiness="${ADAPTIVE_CURRENT_STATE[swappiness]}"
    local mode="${ADAPTIVE_TUNER[mode]}"

    local recommended_swappiness="${current_swappiness}"

    # 根据模式和系统状态计算
    case "${mode}" in
        emergency)
            # 紧急模式：尽量减少swap使用
            recommended_swappiness="1"
            ;;
        aggressive)
            # 激进模式：根据内存压力动态调整
            if (( $(echo "${mem_percent} > ${ADAPTIVE_TUNER[memory_pressure_high]}" | bc -l 2>/dev/null || echo "0") )); then
                # 内存压力大，增加swappiness以主动swap
                recommended_swappiness="80"
            elif (( $(echo "${mem_percent} < ${ADAPTIVE_TUNER[memory_pressure_low]}" | bc -l 2>/dev/null || echo "0") )); then
                # 内存压力小，减少swappiness
                recommended_swappiness="10"
            else
                # 中等压力，使用中等值
                recommended_swappiness="40"
            fi
            ;;
        conservative)
            # 保守模式：小幅调整
            if (( $(echo "${swap_percent} > ${ADAPTIVE_TUNER[swap_usage_high]}" | bc -l 2>/dev/null || echo "0") )); then
                # Swap使用率高，减少swappiness
                recommended_swappiness=$((current_swappiness - ADAPTIVE_TUNER[swappiness_adjust_step]))
            elif (( $(echo "${swap_percent} < ${ADAPTIVE_TUNER[swap_usage_low]}" | bc -l 2>/dev/null || echo "0") )); then
                # Swap使用率低，增加swappiness
                recommended_swappiness=$((current_swappiness + ADAPTIVE_TUNER[swappiness_adjust_step]))
            fi
            ;;
        auto|*)
            # 自动模式：综合考虑内存和swap使用
            local mem_factor=$(echo "${mem_percent} / 100" | bc -l 2>/dev/null || echo "0")
            local swap_factor=$(echo "${swap_percent} / 100" | bc -l 2>/dev/null || echo "0")
            local combined=$(echo "(${mem_factor} + ${swap_factor}) / 2 * 100" | bc -l 2>/dev/null || echo "60")
            recommended_swappiness=$(awk "BEGIN {printf \"%.0f\", ${combined}}")
            ;;
    esac

    # 限制范围
    local min_swappiness="${ADAPTIVE_TUNER[swappiness_min]}"
    local max_swappiness="${ADAPTIVE_TUNER[swappiness_max]}"
    recommended_swappiness=$(echo "if (${recommended_swappiness} < ${min_swappiness}) ${min_swappiness}; if (${recommended_swappiness} > ${max_swappiness}) ${max_swappiness}; ${recommended_swappiness}" | bc -l 2>/dev/null || echo "${current_swappiness}")

    echo "${recommended_swappiness}"
    return 0
}

# 应用swappiness调整
# @param new_swappiness: 新的swappiness值
# @return: 0=成功, 1=失败
apply_swappiness() {
    local new_swappiness="$1"
    local current_swappiness="${ADAPTIVE_CURRENT_STATE[swappiness]}"

    # 检查是否需要调整
    [[ "${new_swappiness}" == "${current_swappiness}" ]] && return 0

    # 检查调整间隔
    local current_time=$(date +%s)
    local last_time="${ADAPTIVE_HISTORY[last_adjustment_time]}"
    local min_interval="${ADAPTIVE_TUNER[min_adjustment_interval]}"

    if [[ ${last_time} -gt 0 ]] && [[ $((current_time - last_time)) -lt ${min_interval} ]]; then
        log_debug "跳过swappiness调整: 距离上次调整时间不足"
        return 0
    fi

    # 验证值
    [[ "${new_swappiness}" -lt 0 ]] || [[ "${new_swappiness}" -gt 100 ]] && {
        log_warn "无效的swappiness值: ${new_swappiness}"
        return 1
    }

    # 应用调整
    if echo "${new_swappiness}" > /proc/sys/vm/swappiness 2>/dev/null; then
        # 记录调整
        local timestamp=$(date +%s)
        local record="${timestamp}|swappiness|${current_swappiness}|${new_swappiness}"
        ADAPTIVE_ADJUSTMENTS+=("${record}")
        ((ADAPTIVE_HISTORY[count]++))
        ADAPTIVE_HISTORY[last_adjustment_time]="${timestamp}"

        log_info "Swappiness调整: ${current_swappiness} -> ${new_swappiness}"
        return 0
    else
        log_error "Swappiness调整失败: ${new_swappiness}"
        return 1
    fi
}

# ==============================================================================
# ZRAM大小自适应调优
# ==============================================================================

# 计算推荐的ZRAM大小
# @return: 推荐的ZRAM大小（MB）
calculate_zram_size() {
    local mem_percent="${ADAPTIVE_CURRENT_STATE[memory_percent]}"
    local current_zram="${ADAPTIVE_CURRENT_STATE[zram_size]}"
    local mode="${ADAPTIVE_TUNER[mode]}"

    # 获取系统总内存（MB）
    local total_mem_mb=$(free -m | awk '/^Mem:/ {print $2}')

    local recommended_size="${current_zram}"

    # 根据模式计算
    case "${mode}" in
        emergency)
            # 紧急模式：最大化ZRAM
            recommended_size=$((total_mem_mb / 2))
            ;;
        aggressive)
            # 激进模式：根据内存压力调整
            if (( $(echo "${mem_percent} > ${ADAPTIVE_TUNER[memory_pressure_high]}" | bc -l 2>/dev/null || echo "0") )); then
                # 内存压力大，增加ZRAM
                recommended_size=$((current_zram + ADAPTIVE_TUNER[zram_adjust_step]))
            elif (( $(echo "${mem_percent} < ${ADAPTIVE_TUNER[memory_pressure_low]}" | bc -l 2>/dev/null || echo "0") )); then
                # 内存压力小，减少ZRAM
                recommended_size=$((current_zram - ADAPTIVE_TUNER[zram_adjust_step]))
            fi
            ;;
        conservative)
            # 保守模式：使用总内存的固定比例
            recommended_size=$((total_mem_mb / 4))
            ;;
        auto|*)
            # 自动模式：根据内存使用率动态调整
            local mem_factor=$(echo "${mem_percent} / 100" | bc -l 2>/dev/null || echo "0")
            recommended_size=$(awk "BEGIN {printf \"%.0f\", ${total_mem_mb} * ${mem_factor} * 0.5}")
            ;;
    esac

    # 限制范围
    local min_zram="${ADAPTIVE_TUNER[zram_min_mb]}"
    local max_zram="${ADAPTIVE_TUNER[zram_max_mb]}"
    recommended_size=$(echo "if (${recommended_size} < ${min_zram}) ${min_zram}; if (${recommended_size} > ${max_zram}) ${max_zram}; ${recommended_size}" | bc -l 2>/dev/null || echo "${current_zram}")

    # 对齐到步长
    local step="${ADAPTIVE_TUNER[zram_adjust_step]}"
    recommended_size=$(( (recommended_size / step) * step ))

    echo "${recommended_size}"
    return 0
}

# 应用ZRAM大小调整
# @param new_size_mb: 新的ZRAM大小（MB）
# @return: 0=成功, 1=失败
apply_zram_size() {
    local new_size_mb="$1"
    local current_zram="${ADAPTIVE_CURRENT_STATE[zram_size]}"

    # 检查是否需要调整
    [[ "${new_size_mb}" == "${current_zram}" ]] && return 0

    # 检查ZRAM是否存在
    [[ ! -d /sys/block/zram0 ]] && {
        log_warn "ZRAM设备不存在，跳过大小调整"
        return 1
    }

    # 检查调整间隔
    local current_time=$(date +%s)
    local last_time="${ADAPTIVE_HISTORY[last_adjustment_time]}"
    local min_interval="${ADAPTIVE_TUNER[min_adjustment_interval]}"

    if [[ ${last_time} -gt 0 ]] && [[ $((current_time - last_time)) -lt ${min_interval} ]]; then
        log_debug "跳过ZRAM大小调整: 距离上次调整时间不足"
        return 0
    fi

    # 需要先卸载再调整大小
    local zram_mounted=0
    if grep -q "^/dev/zram0" /proc/mounts 2>/dev/null; then
        zram_mounted=1
        swapoff /dev/zram0 2>/dev/null || true
    fi

    # 设置新大小
    local new_size_kb=$((new_size_mb * 1024))
    if echo "${new_size_kb}" > /sys/block/zram0/disksize 2>/dev/null; then
        # 重新挂载
        if [[ ${zram_mounted} -eq 1 ]]; then
            mkswap /dev/zram0 >/dev/null 2>&1
            swapon /dev/zram0 2>/dev/null
        fi

        # 记录调整
        local timestamp=$(date +%s)
        local record="${timestamp}|zram_size|${current_zram}|${new_size_mb}"
        ADAPTIVE_ADJUSTMENTS+=("${record}")
        ((ADAPTIVE_HISTORY[count]++))
        ADAPTIVE_HISTORY[last_adjustment_time]="${timestamp}"

        log_info "ZRAM大小调整: ${current_zram}MB -> ${new_size_mb}MB"
        return 0
    else
        log_error "ZRAM大小调整失败: ${new_size_mb}MB"
        return 1
    fi
}

# ==============================================================================
# 压缩算法自适应选择
# ==============================================================================

# 计算推荐的压缩算法
# @return: 推荐的压缩算法
calculate_compression_algorithm() {
    local mem_percent="${ADAPTIVE_CURRENT_STATE[memory_percent]}"
    local swap_percent="${ADAPTIVE_CURRENT_STATE[swap_percent]}"
    local current_algo="${ADAPTIVE_CURRENT_STATE[compression_algo]}"
    local mode="${ADAPTIVE_TUNER[mode]}"

    local recommended_algo="${current_algo}"

    # 根据模式选择算法
    case "${mode}" in
        emergency)
            # 紧急模式：最高压缩率
            recommended_algo="zstd"
            ;;
        aggressive)
            # 激进模式：根据系统负载选择
            local cpu_load=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
            if (( $(echo "${cpu_load} > 80" | bc -l 2>/dev/null || echo "0") )); then
                # CPU负载高，使用快速算法
                recommended_algo="lz4"
            else
                # CPU负载低，使用高压缩率算法
                recommended_algo="zstd"
            fi
            ;;
        conservative)
            # 保守模式：平衡速度和压缩率
            recommended_algo="lzo-rle"
            ;;
        auto|*)
            # 自动模式：根据内存压力选择
            if (( $(echo "${mem_percent} > ${ADAPTIVE_TUNER[memory_pressure_high]}" | bc -l 2>/dev/null || echo "0") )); then
                # 内存压力大，使用高压缩率
                recommended_algo="zstd"
            elif (( $(echo "${mem_percent} < ${ADAPTIVE_TUNER[memory_pressure_low]}" | bc -l 2>/dev/null || echo "0") )); then
                # 内存压力小，使用快速算法
                recommended_algo="lz4"
            else
                # 中等压力，使用平衡算法
                recommended_algo="lzo-rle"
            fi
            ;;
    esac

    echo "${recommended_algo}"
    return 0
}

# 应用压缩算法调整
# @param new_algo: 新的压缩算法
# @return: 0=成功, 1=失败
apply_compression_algorithm() {
    local new_algo="$1"
    local current_algo="${ADAPTIVE_CURRENT_STATE[compression_algo]}"

    # 检查是否需要调整
    [[ "${new_algo}" == "${current_algo}" ]] && return 0

    # 验证算法
    local valid_algorithms="${ADAPTIVE_TUNER[compression_algorithms]}"
    if [[ ",${valid_algorithms}," != *",${new_algo},"* ]]; then
        log_warn "无效的压缩算法: ${new_algo}"
        return 1
    fi

    # 检查ZRAM是否存在
    [[ ! -d /sys/block/zram0 ]] && {
        log_warn "ZRAM设备不存在，跳过压缩算法调整"
        return 1
    }

    # 需要先卸载
    local zram_mounted=0
    if grep -q "^/dev/zram0" /proc/mounts 2>/dev/null; then
        zram_mounted=1
        swapoff /dev/zram0 2>/dev/null || true
    fi

    # 设置新算法
    if echo "${new_algo}" > /sys/block/zram0/comp_algorithm 2>/dev/null; then
        # 更新配置
        CONFIG[zram_compression]="${new_algo}"

        # 重新挂载
        if [[ ${zram_mounted} -eq 1 ]]; then
            mkswap /dev/zram0 >/dev/null 2>&1
            swapon /dev/zram0 2>/dev/null
        fi

        # 记录调整
        local timestamp=$(date +%s)
        local record="${timestamp}|compression|${current_algo}|${new_algo}"
        ADAPTIVE_ADJUSTMENTS+=("${record}")
        ((ADAPTIVE_HISTORY[count]++))
        ADAPTIVE_HISTORY[last_adjustment_time]="${timestamp}"

        log_info "压缩算法调整: ${current_algo} -> ${new_algo}"
        return 0
    else
        log_error "压缩算法调整失败: ${new_algo}"
        return 1
    fi
}

# ==============================================================================
# 综合调优
# ==============================================================================

# 执行一次完整的自适应调优
# @return: 0=成功, 1=失败
run_adaptive_tuning() {
    log_debug "执行自适应调优..."

    # 获取当前状态
    get_adaptive_state

    # 计算并应用swappiness调整
    local new_swappiness=$(calculate_swappiness)
    apply_swappiness "${new_swappiness}"

    # 计算并应用ZRAM大小调整
    local new_zram_size=$(calculate_zram_size)
    apply_zram_size "${new_zram_size}"

    # 计算并应用压缩算法调整
    local new_compression=$(calculate_compression_algorithm)
    apply_compression_algorithm "${new_compression}"

    log_debug "自适应调优完成"
    return 0
}

# ==============================================================================
# 模式管理
# ==============================================================================

# 设置调优模式
# @param mode: 调优模式（auto/conservative/aggressive/emergency）
set_tuning_mode() {
    local mode="$1"

    case "${mode}" in
        auto|conservative|aggressive|emergency)
            ADAPTIVE_TUNER[mode]="${mode}"
            log_info "调优模式设置为: ${mode}"
            return 0
            ;;
        *)
            log_error "无效的调优模式: ${mode}"
            return 1
            ;;
    esac
}

# 获取当前模式
get_tuning_mode() {
    echo "${ADAPTIVE_TUNER[mode]}"
    return 0
}

# ==============================================================================
# 统计和报告
# ==============================================================================

# 获取自适应调优统计
get_adaptive_stats() {
    cat <<EOF
{
    "config": {
        "mode": "${ADAPTIVE_TUNER[mode]}",
        "swappiness": {
            "min": ${ADAPTIVE_TUNER[swappiness_min]},
            "max": ${ADAPTIVE_TUNER[swappiness_max]},
            "default": ${ADAPTIVE_TUNER[swappiness_default]},
            "current": ${ADAPTIVE_CURRENT_STATE[swappiness]}
        },
        "zram": {
            "min_mb": ${ADAPTIVE_TUNER[zram_min_mb]},
            "max_mb": ${ADAPTIVE_TUNER[zram_max_mb]},
            "default_mb": ${ADAPTIVE_TUNER[zram_default_mb]},
            "current_mb": ${ADAPTIVE_CURRENT_STATE[zram_size]}
        },
        "compression": {
            "algorithms": "${ADAPTIVE_TUNER[compression_algorithms]}",
            "default": "${ADAPTIVE_TUNER[compression_default]}",
            "current": "${ADAPTIVE_CURRENT_STATE[compression_algo]}"
        }
    },
    "current_state": {
        "memory_percent": ${ADAPTIVE_CURRENT_STATE[memory_percent]},
        "swap_percent": ${ADAPTIVE_CURRENT_STATE[swap_percent]},
        "timestamp": ${ADAPTIVE_CURRENT_STATE[timestamp]}
    },
    "history": {
        "adjustment_count": ${ADAPTIVE_HISTORY[count]},
        "last_adjustment": ${ADAPTIVE_HISTORY[last_adjustment_time]}
    },
    "compression_performance": {
        "lzo": {
            "speed": ${COMPRESSION_PERFORMANCE[lzo_speed]},
            "ratio": ${COMPRESSION_PERFORMANCE[lzo_ratio]}
        },
        "lzo-rle": {
            "speed": ${COMPRESSION_PERFORMANCE[lzo-rle_speed]},
            "ratio": ${COMPRESSION_PERFORMANCE[lzo-rle_ratio]}
        },
        "lz4": {
            "speed": ${COMPRESSION_PERFORMANCE[lz4_speed]},
            "ratio": ${COMPRESSION_PERFORMANCE[lz4_ratio]}
        },
        "zstd": {
            "speed": ${COMPRESSION_PERFORMANCE[zstd_speed]},
            "ratio": ${COMPRESSION_PERFORMANCE[zstd_ratio]}
        }
    }
}
EOF
}

# 导出调优历史
export_adaptive_history() {
    local output_file="$1"

    {
        echo "# Adaptive Tuning History"
        for record in "${ADAPTIVE_ADJUSTMENTS[@]}"; do
            echo "${record}"
        done

        echo -e "\n# Current Configuration"
        for key in "${!ADAPTIVE_TUNER[@]}"; do
            echo "${key}=${ADAPTIVE_TUNER[${key}]}"
        done
    } > "${output_file}" 2>/dev/null || return 1

    log_info "自适应调优历史已导出: ${output_file}"
    return 0
}

# ==============================================================================
# 初始化和清理
# ==============================================================================

# 初始化自适应调优模块
init_adaptive_tuner() {
    log_debug "初始化自适应调优模块..."

    # 创建数据目录
    mkdir -p "${CONF_DIR}/adaptive" 2>/dev/null || true

    # 加载历史数据
    local history_file="${CONF_DIR}/adaptive/history"
    if [[ -f "${history_file}" ]]; then
        # 简单加载（实际实现需要更复杂的解析）
        while IFS='|' read -r timestamp param old new; do
            [[ "${timestamp}" == "#" ]] && continue
            [[ -z "${timestamp}" ]] && continue
            ADAPTIVE_ADJUSTMENTS+=("${timestamp}|${param}|${old}|${new}")
        done < "${history_file}"
    fi

    # 获取初始状态
    get_adaptive_state

    log_debug "自适应调优模块初始化完成"
    return 0
}

# 清理自适应调优模块
cleanup_adaptive_tuner() {
    log_debug "清理自适应调优模块..."

    # 保存历史数据
    local history_file="${CONF_DIR}/adaptive/history"
    export_adaptive_history "${history_file}"

    log_debug "自适应调优模块清理完成"
    return 0
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f get_adaptive_state
export -f calculate_swappiness
export -f apply_swappiness
export -f calculate_zram_size
export -f apply_zram_size
export -f calculate_compression_algorithm
export -f apply_compression_algorithm
export -f run_adaptive_tuning
export -f set_tuning_mode
export -f get_tuning_mode
export -f get_adaptive_stats
export -f export_adaptive_history
