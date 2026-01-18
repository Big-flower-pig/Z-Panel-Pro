#!/bin/bash
# ==============================================================================
# Z-Panel Pro V9.0 - Swap管理模块
# ==============================================================================
# @description    Swap文件管理与配置
# @version       9.0.0-Lightweight
# @author        Z-Panel Team
# @license       MIT License
# ==============================================================================

# ==============================================================================
# 获取Swap文件信息
# @return: "total_mb used_mb"
# ==============================================================================
get_swap_file_info() {
    if [[ ! -f "${SWAP_FILE_PATH}" ]]; then
        echo "0 0"
        return
    fi

    if ! swapon --show=NAME --noheadings 2>/dev/null | grep -q "${SWAP_FILE_PATH}"; then
        echo "0 0"
        return
    fi

    local swap_info
    swap_info=$(swapon --show=SIZE,USED --noheadings 2>/dev/null | grep "${SWAP_FILE_PATH}" | head -1)

    if [[ -z "${swap_info}" ]]; then
        echo "0 0"
        return
    fi

    # 转换单位为MB
    local swap_total swap_used
    swap_total=$(echo "${swap_info}" | awk '{print $1}')
    swap_used=$(echo "${swap_info}" | awk '{print $2}')

    swap_total=$(convert_size_to_mb "${swap_total}")
    swap_used=$(convert_size_to_mb "${swap_used}")

    [[ -z "${swap_total}" ]] || [[ "${swap_total}" == "0" ]] && swap_total=1
    [[ -z "${swap_used}" ]] && swap_used=0

    echo "${swap_total} ${swap_used}"
}

# ==============================================================================
# 检查Swap文件是否启用
# @return: 0表示启用，1表示未启用
# ==============================================================================
is_swap_file_enabled() {
    [[ -f "${SWAP_FILE_PATH}" ]] && swapon --show=NAME --noheadings 2>/dev/null | grep -q "${SWAP_FILE_PATH}"
}

# ==============================================================================
# 创建Swap文件
# @param size_mb: Swap文件大小（MB）
# @param priority: Swap优先级，默认使用PHYSICAL_SWAP_PRIORITY
# @return: 0成功，1失败
# ==============================================================================
create_swap_file() {
    local size_mb="$1"
    local priority="${2:-$(get_config 'physical_swap_priority')}"

    log_info "创建 Swap 文件 (${size_mb}MB)..."

    # 参数验证：大小
    if ! validate_positive_integer "${size_mb}"; then
        handle_error "SWAP_CREATE" "无效的 Swap 大小: ${size_mb}"
        return 1
    fi

    # 边界检查：最小128MB
    if [[ ${size_mb} -lt 128 ]]; then
        handle_error "SWAP_CREATE" "Swap 大小不能小于 128MB (当前: ${size_mb}MB)"
        return 1
    fi

    # 边界检查：最大4倍物理内存
    local max_size=$((SYSTEM_INFO[total_memory_mb] * 4))
    if [[ ${size_mb} -gt ${max_size} ]]; then
        handle_error "SWAP_CREATE" "Swap 大小超过最大限制 (最大: ${max_size}MB, 当前: ${size_mb}MB)"
        return 1
    fi

    # 参数验证：优先级
    if ! validate_positive_integer "${priority}"; then
        handle_error "SWAP_CREATE" "无效的 Swap 优先级: ${priority}"
        return 1
    fi

    # 边界检查：优先级范围 (1-32767)
    if [[ ${priority} -lt 1 ]] || [[ ${priority} -gt 32767 ]]; then
        handle_error "SWAP_CREATE" "Swap 优先级必须在 1-32767 之间 (当前: ${priority})"
        return 1
    fi

    # 磁盘空间检查
    local disk_avail
    disk_avail=$(df -m / | awk 'NR==2 {print $4}')
    local required_space=$((size_mb + 256))  # 额外256MB作为缓冲

    if [[ ${disk_avail} -lt ${required_space} ]]; then
        handle_error "SWAP_CREATE" "磁盘空间不足 (需要: ${required_space}MB, 可用: ${disk_avail}MB)"
        return 1
    fi

    # 创建目录
    mkdir -p "$(dirname "${SWAP_FILE_PATH}")"

    # 如果已存在Swap文件，先删除
    if [[ -f "${SWAP_FILE_PATH}" ]]; then
        log_warn "Swap 文件已存在，重新创建..."
        disable_swap_file
        rm -f "${SWAP_FILE_PATH}"
    fi

    # 创建Swap文件
    if ! fallocate -l "${size_mb}M" "${SWAP_FILE_PATH}" 2>/dev/null; then
        log_warn "fallocate 失败，尝试使用 dd..."
        dd if=/dev/zero of="${SWAP_FILE_PATH}" bs=1M count="${size_mb}" status=none || {
            handle_error "SWAP_CREATE" "创建 Swap 文件失败"
            return 1
        }
    fi

    # 设置权限
    chmod 600 "${SWAP_FILE_PATH}"

    # 创建Swap空间
    if ! mkswap "${SWAP_FILE_PATH}" > /dev/null 2>&1; then
        handle_error "SWAP_CREATE" "创建 Swap 空间失败"
        rm -f "${SWAP_FILE_PATH}"
        return 1
    fi

    # 启用Swap
    if ! swapon -p "${priority}" "${SWAP_FILE_PATH}" > /dev/null 2>&1; then
        handle_error "SWAP_CREATE" "启用 Swap 失败"
        rm -f "${SWAP_FILE_PATH}"
        return 1
    fi

    # 添加到fstab
    if [[ ! -f /etc/fstab ]] || ! grep -q "${SWAP_FILE_PATH}" /etc/fstab; then
        echo "${SWAP_FILE_PATH} none swap sw,pri=${priority} 0 0" >> /etc/fstab
        log_info "已添加到 /etc/fstab"
    fi

    # 清除缓存
    clear_cache

    SWAP_ENABLED=true
    log_info "Swap 文件创建成功: ${size_mb}MB, 优先级: ${priority}"
    return 0
}

# ==============================================================================
# 禁用Swap文件
# @return: 0成功
# ==============================================================================
disable_swap_file() {
    log_info "删除 Swap 文件..."

    # 停用Swap
    if [[ -f "${SWAP_FILE_PATH}" ]]; then
        swapoff "${SWAP_FILE_PATH}" 2>/dev/null || true
    fi

    # 从fstab删除
    if [[ -f /etc/fstab ]] && grep -q "${SWAP_FILE_PATH}" /etc/fstab; then
        # 备份fstab
        local backup_file="/etc/fstab.bak.$(date +%Y%m%d_%H%M%S)"
        cp /etc/fstab "${backup_file}" 2>/dev/null || true

        sed -i "\|${SWAP_FILE_PATH}|d" /etc/fstab
        log_info "已从 /etc/fstab 删除"
    fi

    # 删除文件
    if [[ -f "${SWAP_FILE_PATH}" ]]; then
        rm -f "${SWAP_FILE_PATH}"
        log_info "已删除 Swap 文件"
    fi

    # 清除缓存
    clear_cache

    SWAP_ENABLED=false
    return 0
}

# ==============================================================================
# 配置物理Swap
# @param mode: 策略模式
# @return: 0成功或1失败
# ==============================================================================
configure_physical_swap() {
    local mode="${1:-${STRATEGY_MODE}}"

    # 参数验证：策略模式
    if [[ -z "${mode}" ]]; then
        handle_error "SWAP_CONFIG" "策略模式不能为空"
        return 1
    fi

    # 验证策略模式是否有效（使用统一的验证函数）
    if ! validate_strategy_mode "${mode}"; then
        handle_error "SWAP_CONFIG" "无效的策略模式: ${mode}"
        return 1
    fi

    log_info "配置 Swap (模式: ${mode})..."

    local zram_ratio phys_limit swap_size swappiness dirty_ratio min_free
    read -r zram_ratio phys_limit swap_size swappiness dirty_ratio min_free <<< "$(calculate_strategy "${mode}")"

    # 边界检查：确保返回值有效
    if [[ -z "${swap_size}" ]] || ! validate_positive_integer "${swap_size}"; then
        handle_error "SWAP_CONFIG" "策略计算返回无效的 Swap 大小"
        return 1
    fi

    # 边界检查：最小128MB
    if [[ ${swap_size} -lt 128 ]]; then
        swap_size=128
        log_warn "Swap 大小调整至最小值: 128MB"
    fi

    # 边界检查：最大4倍物理内存
    local max_size=$((SYSTEM_INFO[total_memory_mb] * 4))
    if [[ ${swap_size} -gt ${max_size} ]]; then
        log_warn "Swap 大小超过最大限制，调整至: ${max_size}MB"
        swap_size=${max_size}
    fi

    # 检查是否已存在Swap
    if is_swap_file_enabled; then
        local swap_info
        swap_info=$(get_swap_file_info)
        local current_size
        current_size=$(echo "${swap_info}" | awk '{print $1}')

        local tolerance=100
        if [[ ${current_size} -ge $((swap_size - tolerance)) ]] && [[ ${current_size} -le $((swap_size + tolerance)) ]]; then
            log_info "Swap 大小符合要求 (${current_size}MB)"
            return 0
        fi

        log_info "调整 Swap 大小: ${current_size}MB -> ${swap_size}MB"
        disable_swap_file
    fi

    if ! create_swap_file "${swap_size}" "$(get_config 'physical_swap_priority')"; then
        handle_error "SWAP_CONFIG" "创建 Swap 文件失败"
        return 1
    fi

    return 0
}

# ==============================================================================
# 保存Swap配置
# @param swap_size: Swap文件大小（MB）
# @param enabled: 是否启用true/false
# @return: 0成功，1失败
# ==============================================================================
save_swap_config() {
    local swap_size="$1"
    local enabled="$2"

    # 获取配置值
    local zram_priority
    zram_priority=$(get_config 'zram_priority')
    local phys_swap_priority
    phys_swap_priority=$(get_config 'physical_swap_priority')

    local content
    cat <<EOF
# ============================================================================
# Z-Panel Pro 物理 Swap 配置
# ============================================================================
# 自动生成，请勿手动修改
#
# SWAP_SIZE: 物理 Swap 文件大小（MB）
# SWAP_ENABLED: 是否启用物理 Swap
# SWAP_PRIORITY: Swap 优先级 (ZRAM=${zram_priority}, 物理 Swap=${phys_swap_priority})
# ============================================================================

SWAP_SIZE=${swap_size}
SWAP_ENABLED=${enabled}
SWAP_PRIORITY=${phys_swap_priority}
EOF

    if save_config_file "${SWAP_CONFIG_FILE}" "${content}"; then
        log_info "Swap 配置已保存"
        return 0
    else
        log_error "Swap 配置保存失败"
        return 1
    fi
}

# ==============================================================================
# 获取所有Swap设备
# @return: 所有Swap设备信息
# ==============================================================================
get_all_swap_devices() {
    echo "=== 所有 Swap 设备 ==="
    echo ""

    if swapon --show=NAME,SIZE,USED,PRIO --noheadings 2>/dev/null | grep -q .; then
        printf "%-30s %10s %10s %10s\n" "设备" "大小" "已用" "优先级"
        printf "%-30s %10s %10s %10s\n" "----" "----" "----" "----"

        swapon --show=NAME,SIZE,USED,PRIO --noheadings 2>/dev/null | while read -r name size used prio; do
            # 转换单位
            local size_mb
            size_mb=$(convert_size_to_mb "${size}")
            local used_mb
            used_mb=$(convert_size_to_mb "${used}")

            printf "%-30s %10s %10s %10s\n" "${name}" "${size_mb}MB" "${used_mb}MB" "${prio}"
        done
    else
        echo "当前没有 Swap 设备"
    fi

    echo ""
    echo "=== 汇总 ==="
    local swap_total swap_used
    read -r swap_total swap_used <<< "$(get_swap_info false)"
    printf "总计: %sMB  已用: %sMB\n" "${swap_total}" "${swap_used}"
}

# ==============================================================================
# 智能Swap大小推荐（基于系统资源和地理位置）
# @return: 推荐的Swap大小（MB）
# ==============================================================================
recommend_swap_size() {
    # 参数验证：确保系统信息已加载
    if [[ -z "${SYSTEM_INFO[total_memory_mb]:-}" ]]; then
        handle_error "SWAP_RECOMMEND" "系统信息未加载，无法推荐 Swap 大小"
        echo "0"
        return 1
    fi

    local mem_total=${SYSTEM_INFO[total_memory_mb]}

    # 边界检查：物理内存必须有效
    if [[ ${mem_total} -lt 64 ]]; then
        handle_error "SWAP_RECOMMEND" "物理内存过小 (${mem_total}MB)，无法推荐 Swap 大小"
        echo "0"
        return 1
    fi

    local disk_avail
    disk_avail=$(df -m / | awk 'NR==2 {print $4}')

    # 边界检查：磁盘可用空间必须有效
    if [[ -z "${disk_avail}" ]] || [[ ${disk_avail} -lt 1 ]]; then
        handle_error "SWAP_RECOMMEND" "无法获取磁盘可用空间"
        echo "0"
        return 1
    fi

    local cpu_cores=${SYSTEM_INFO[cpu_cores]:-1}
    local region=${SYSTEM_INFO[region]:-"unknown"}
    local mem_usage
    mem_usage=$(get_memory_usage false)

    # 边界检查：内存使用率
    if [[ -z "${mem_usage}" ]] || [[ ${mem_usage} -lt 0 ]] || [[ ${mem_usage} -gt 100 ]]; then
        mem_usage=50  # 默认值
        log_warn "无法获取内存使用率，使用默认值: 50%"
    fi

    local recommended_size=0
    local reason=""

    # 基础计算：根据内存使用率和物理内存
    if [[ ${mem_usage} -gt 85 ]]; then
        # 内存紧张：Swap = 物理内存 * 1.5
        recommended_size=$((mem_total * 150 / 100))
        reason="内存使用率较高(${mem_usage}%)"
    elif [[ ${mem_usage} -gt 70 ]]; then
        # 中等使用：Swap = 物理内存 * 1.2
        recommended_size=$((mem_total * 120 / 100))
        reason="内存使用率中等(${mem_usage}%)"
    elif [[ ${mem_usage} -gt 50 ]]; then
        # 正常使用：Swap = 物理内存
        recommended_size=${mem_total}
        reason="内存使用率正常(${mem_usage}%)"
    else
        # 内存充足：Swap = 物理内存 * 0.8
        recommended_size=$((mem_total * 80 / 100))
        reason="内存使用率较低(${mem_usage}%)"
    fi

    # 根据地理位置调整（参考kejilion.sh的地理优化）
    case "${region}" in
        CN|HK|TW|SG|JP|KR)
            # 亚洲地区：网络延迟较低，可以适当增加Swap
            recommended_size=$((recommended_size * 110 / 100))
            reason="${reason}, 亚洲地区(增加10%)"
            ;;
        US|EU|AU)
            # 欧美地区：网络延迟较高，保持标准配置
            reason="${reason}, 欧美地区(标准配置)"
            ;;
        *)
            # 其他地区：使用标准配置
            reason="${reason}, 其他地区(标准配置)"
            ;;
    esac

    # 根据CPU核心数调整（多核系统可能需要更多Swap）
    if [[ ${cpu_cores} -ge 8 ]]; then
        recommended_size=$((recommended_size * 115 / 100))
        reason="${reason}, 多核系统(增加15%)"
    elif [[ ${cpu_cores} -ge 4 ]]; then
        recommended_size=$((recommended_size * 105 / 100))
        reason="${reason}, 中核系统(增加5%)"
    fi

    # 检查磁盘空间是否足够
    if [[ ${disk_avail} -lt $((recommended_size + 1024)) ]]; then
        local max_size=$((disk_avail - 1024))
        if [[ ${max_size} -ge 128 ]]; then
            log_warn "磁盘空间不足，调整推荐大小: ${recommended_size}MB -> ${max_size}MB"
            recommended_size=${max_size}
            reason="${reason}, 磁盘空间受限"
        else
            log_error "磁盘空间不足，无法创建Swap文件"
            echo "0"
            return 1
        fi
    fi

    # 边界检查
    [[ ${recommended_size} -lt 128 ]] && recommended_size=128
    [[ ${recommended_size} -gt $((mem_total * 4)) ]] && recommended_size=$((mem_total * 4))

    log_info "Swap大小推荐: ${recommended_size}MB (${reason})"
    echo "${recommended_size}"
}

# ==============================================================================
# Swap使用监控和警报
# @param alert_threshold: 警报阈值（百分比），默认80
# @param critical_threshold: 严重警报阈值（百分比），默认90
# @return: 监控结果JSON
# ==============================================================================
monitor_swap_usage() {
    local alert_threshold="${1:-80}"
    local critical_threshold="${2:-90}"

    # 参数验证：警报阈值
    if ! validate_positive_integer "${alert_threshold}"; then
        log_warn "无效的警报阈值: ${alert_threshold}，使用默认值 80"
        alert_threshold=80
    fi

    # 边界检查：警报阈值范围 (0-100)
    if [[ ${alert_threshold} -lt 0 ]] || [[ ${alert_threshold} -gt 100 ]]; then
        log_warn "警报阈值超出范围 (0-100)，调整为: 80"
        alert_threshold=80
    fi

    # 参数验证：严重警报阈值
    if ! validate_positive_integer "${critical_threshold}"; then
        log_warn "无效的严重警报阈值: ${critical_threshold}，使用默认值 90"
        critical_threshold=90
    fi

    # 边界检查：严重警报阈值范围 (0-100)
    if [[ ${critical_threshold} -lt 0 ]] || [[ ${critical_threshold} -gt 100 ]]; then
        log_warn "严重警报阈值超出范围 (0-100)，调整为: 90"
        critical_threshold=90
    fi

    # 逻辑检查：严重阈值必须大于等于警报阈值
    if [[ ${critical_threshold} -lt ${alert_threshold} ]]; then
        log_warn "严重警报阈值 (${critical_threshold}) 小于警报阈值 (${alert_threshold})，自动调整"
        critical_threshold=${alert_threshold}
    fi

    local swap_total swap_used swap_usage
    read -r swap_total swap_used <<< "$(get_swap_info false)"

    if [[ ${swap_total} -eq 0 ]]; then
        cat <<EOF
{
    "status": "not_configured",
    "swap_total_mb": 0,
    "swap_used_mb": 0,
    "swap_usage_percent": 0,
    "alert_level": "info",
    "message": "Swap未配置"
}
EOF
        return 0
    fi

    swap_usage=$(calculate_percentage "${swap_used}" "${swap_total}")
    local alert_level="info"
    local message="Swap使用正常"

    if [[ ${swap_usage} -ge ${critical_threshold} ]]; then
        alert_level="critical"
        message="Swap使用率严重过高(${swap_usage}%)，可能影响系统性能"
        log_error "Swap使用警报: ${message}"
    elif [[ ${swap_usage} -ge ${alert_threshold} ]]; then
        alert_level="warning"
        message="Swap使用率较高(${swap_usage}%)，建议关注"
        log_warn "Swap使用警告: ${message}"
    fi

    # 获取Swap I/O统计
    local swap_in swap_out
    swap_in=$(vmstat -s 2>/dev/null | grep "pages swapped in" | awk '{print $1}')
    swap_out=$(vmstat -s 2>/dev/null | grep "pages swapped out" | awk '{print $1}')

    cat <<EOF
{
    "status": "configured",
    "swap_total_mb": ${swap_total},
    "swap_used_mb": ${swap_used},
    "swap_usage_percent": ${swap_usage},
    "alert_level": "${alert_level}",
    "message": "${message}",
    "io_stats": {
        "pages_swapped_in": ${swap_in:-0},
        "pages_swapped_out": ${swap_out:-0}
    },
    "thresholds": {
        "alert": ${alert_threshold},
        "critical": ${critical_threshold}
    }
}
EOF
}

# ==============================================================================
# Swap性能优化
# @param optimize_type: 优化类型
#   - swappiness: 优化swappiness值
#   - vfs_cache_pressure: 优化vfs缓存压力
#   - all: 优化所有参数
# @return: 0成功，1失败
# ==============================================================================
optimize_swap_performance() {
    local optimize_type="${1:-all}"

    # 参数验证：优化类型
    if [[ -z "${optimize_type}" ]]; then
        handle_error "SWAP_OPTIMIZE" "优化类型不能为空"
        return 1
    fi

    # 验证优化类型是否有效
    local valid_types=("swappiness" "vfs_cache_pressure" "all")
    local is_valid=false
    for valid_type in "${valid_types[@]}"; do
        if [[ "${optimize_type}" == "${valid_type}" ]]; then
            is_valid=true
            break
        fi
    done

    if [[ "${is_valid}" == "false" ]]; then
        handle_error "SWAP_OPTIMIZE" "无效的优化类型: ${optimize_type} (有效值: swappiness, vfs_cache_pressure, all)"
        return 1
    fi

    log_info "开始Swap性能优化 (类型: ${optimize_type})..."

    local swappiness dirty_ratio dirty_background_ratio vfs_cache_pressure
    read -r _ _ _ swappiness dirty_ratio min_free <<< "$(calculate_strategy)"

    case "${optimize_type}" in
        swappiness)
            # 优化swappiness值
            if sysctl -w "vm.swappiness=${swappiness}" > /dev/null 2>&1; then
                # 持久化配置
                if ! grep -q "vm.swappiness" /etc/sysctl.conf 2>/dev/null; then
                    echo "vm.swappiness=${swappiness}" >> /etc/sysctl.conf
                else
                    sed -i "s/^vm.swappiness.*/vm.swappiness=${swappiness}/" /etc/sysctl.conf
                fi
                log_info "Swappiness已优化为: ${swappiness}"
                return 0
            else
                log_error "Swappiness优化失败"
                return 1
            fi
            ;;

        vfs_cache_pressure)
            # 优化VFS缓存压力（参考kejilion.sh的最佳实践）
            vfs_cache_pressure=50

            if sysctl -w "vm.vfs_cache_pressure=${vfs_cache_pressure}" > /dev/null 2>&1; then
                if ! grep -q "vm.vfs_cache_pressure" /etc/sysctl.conf 2>/dev/null; then
                    echo "vm.vfs_cache_pressure=${vfs_cache_pressure}" >> /etc/sysctl.conf
                else
                    sed -i "s/^vm.vfs_cache_pressure.*/vm.vfs_cache_pressure=${vfs_cache_pressure}/" /etc/sysctl.conf
                fi
                log_info "VFS缓存压力已优化为: ${vfs_cache_pressure}"
                return 0
            else
                log_error "VFS缓存压力优化失败"
                return 1
            fi
            ;;

        all)
            # 优化所有参数
            local success=true

            # 优化swappiness
            if ! sysctl -w "vm.swappiness=${swappiness}" > /dev/null 2>&1; then
                log_error "Swappiness优化失败"
                success=false
            else
                if ! grep -q "vm.swappiness" /etc/sysctl.conf 2>/dev/null; then
                    echo "vm.swappiness=${swappiness}" >> /etc/sysctl.conf
                else
                    sed -i "s/^vm.swappiness.*/vm.swappiness=${swappiness}/" /etc/sysctl.conf
                fi
                log_info "Swappiness已优化为: ${swappiness}"
            fi

            # 优化dirty_ratio
            if ! sysctl -w "vm.dirty_ratio=${dirty_ratio}" > /dev/null 2>&1; then
                log_error "Dirty Ratio优化失败"
                success=false
            else
                if ! grep -q "vm.dirty_ratio" /etc/sysctl.conf 2>/dev/null; then
                    echo "vm.dirty_ratio=${dirty_ratio}" >> /etc/sysctl.conf
                else
                    sed -i "s/^vm.dirty_ratio.*/vm.dirty_ratio=${dirty_ratio}/" /etc/sysctl.conf
                fi
                log_info "Dirty Ratio已优化为: ${dirty_ratio}"
            fi

            # 优化vfs_cache_pressure
            vfs_cache_pressure=50
            if ! sysctl -w "vm.vfs_cache_pressure=${vfs_cache_pressure}" > /dev/null 2>&1; then
                log_error "VFS缓存压力优化失败"
                success=false
            else
                if ! grep -q "vm.vfs_cache_pressure" /etc/sysctl.conf 2>/dev/null; then
                    echo "vm.vfs_cache_pressure=${vfs_cache_pressure}" >> /etc/sysctl.conf
                else
                    sed -i "s/^vm.vfs_cache_pressure.*/vm.vfs_cache_pressure=${vfs_cache_pressure}/" /etc/sysctl.conf
                fi
                log_info "VFS缓存压力已优化为: ${vfs_cache_pressure}"
            fi

            # 应用sysctl配置
            if command -v sysctl > /dev/null; then
                sysctl -p > /dev/null 2>&1 || true
            fi

            if [[ "${success}" == "true" ]]; then
                log_info "Swap性能优化完成"
                return 0
            else
                log_error "Swap性能优化部分失败"
                return 1
            fi
            ;;

        *)
            log_error "无效的优化类型: ${optimize_type}"
            return 1
            ;;
    esac
}

# ==============================================================================
# 获取Swap性能报告
# @return: 性能报告文本
# ==============================================================================
get_swap_performance_report() {
    local swap_total swap_used swap_usage
    read -r swap_total swap_used <<< "$(get_swap_info false)"

    local swappiness
    swappiness=$(get_swappiness)

    local dirty_ratio dirty_background_ratio vfs_cache_pressure
    dirty_ratio=$(get_kernel_param "vm.dirty_ratio")
    dirty_background_ratio=$(get_kernel_param "vm.dirty_background_ratio")
    vfs_cache_pressure=$(get_kernel_param "vm.vfs_cache_pressure")

    cat <<EOF
Swap性能报告
================================================================================

Swap状态:
  总大小: ${swap_total}MB
  已使用: ${swap_used}MB
  使用率: ${swap_usage}%

内核参数:
  Swappiness: ${swappiness}
    - 推荐值: 60-100 (值越大越积极使用Swap)
    - 说明: 控制内核使用Swap的激进程度

  Dirty Ratio: ${dirty_ratio}%
    - 推荐值: 5-15 (值越大延迟写入)
    - 说明: 脏数据占可用内存的百分比

  Dirty Background Ratio: ${dirty_background_ratio}%
    - 推荐值: 5-10
    - 说明: 后台写入的阈值

  VFS Cache Pressure: ${vfs_cache_pressure}
    - 推荐值: 50-100 (值越小越倾向于保留缓存)
    - 说明: 控制内核回收inode和dentry缓存的激进程度

性能建议:
  - Swappiness过高会导致频繁Swap，影响性能
  - Swappiness过低会导致内存不足时系统卡顿
  - 根据实际使用情况调整参数以获得最佳性能

================================================================================
EOF
}


# ==============================================================================
# 导出函数
# ==============================================================================
export -f get_swap_file_info
export -f is_swap_file_enabled
export -f create_swap_file
export -f disable_swap_file
export -f configure_physical_swap
export -f save_swap_config
export -f get_all_swap_devices
export -f recommend_swap_size
export -f monitor_swap_usage
export -f optimize_swap_performance
export -f get_swap_performance_report
