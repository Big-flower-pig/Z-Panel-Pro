#!/bin/bash
# ==============================================================================
# Z-Panel Pro - Swap文件管理模块
# ==============================================================================
# @description    物理Swap文件管理
# @version       7.1.0-Enterprise
# @author        Z-Panel Team
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

    # 使用统一的单位转换函�?    local swap_total swap_used
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
# @return: 0为启用，1为未启用
# ==============================================================================
is_swap_file_enabled() {
    [[ -f "${SWAP_FILE_PATH}" ]] && swapon --show=NAME --noheadings 2>/dev/null | grep -q "${SWAP_FILE_PATH}"
}

# ==============================================================================
# 创建Swap文件
# @param size_mb: Swap文件大小（MB�?# @param priority: Swap优先级（默认为PHYSICAL_SWAP_PRIORITY�?# @return: 0为成功，1为失�?# ==============================================================================
create_swap_file() {
    local size_mb="$1"
    local priority="${2:-$(get_config 'physical_swap_priority')}"

    log_info "创建物理 Swap 文件 (${size_mb}MB)..."

    # 验证大小
    if ! validate_positive_integer "${size_mb}"; then
        handle_error "SWAP_CREATE" "无效�?Swap 大小: ${size_mb}"
        return 1
    fi

    if [[ ${size_mb} -lt 128 ]]; then
        handle_error "SWAP_CREATE" "Swap 文件大小不能小于 128MB"
        return 1
    fi

    if [[ ${size_mb} -gt $((SYSTEM_INFO[total_memory_mb] * 4)) ]]; then
        log_warn "Swap 文件大小超过物理内存�?4 倍，可能影响性能"
    fi

    # 创建目录
    mkdir -p "$(dirname "${SWAP_FILE_PATH}")"

    # 停用并删除现有Swap文件
    if [[ -f "${SWAP_FILE_PATH}" ]]; then
        log_warn "Swap 文件已存在，先停�?.."
        disable_swap_file
        rm -f "${SWAP_FILE_PATH}"
    fi

    # 创建Swap文件
    if ! fallocate -l "${size_mb}M" "${SWAP_FILE_PATH}" 2>/dev/null; then
        log_warn "fallocate 失败，尝试使�?dd..."
        dd if=/dev/zero of="${SWAP_FILE_PATH}" bs=1M count="${size_mb}" status=none || {
            handle_error "SWAP_CREATE" "创建 Swap 文件失败"
            return 1
        }
    fi

    # 设置安全权限
    chmod 600 "${SWAP_FILE_PATH}"

    # 格式化Swap文件
    if ! mkswap "${SWAP_FILE_PATH}" > /dev/null 2>&1; then
        handle_error "SWAP_CREATE" "格式�?Swap 文件失败"
        rm -f "${SWAP_FILE_PATH}"
        return 1
    fi

    # 启用Swap文件
    if ! swapon -p "${priority}" "${SWAP_FILE_PATH}" > /dev/null 2>&1; then
        handle_error "SWAP_CREATE" "启用 Swap 文件失败"
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
    log_info "物理 Swap 文件创建成功: ${size_mb}MB, 优先�?${priority}"
    return 0
}

# ==============================================================================
# 停用Swap文件
# @return: 0为成�?# ==============================================================================
disable_swap_file() {
    log_info "停用物理 Swap 文件..."

    # 停用Swap
    if [[ -f "${SWAP_FILE_PATH}" ]]; then
        swapoff "${SWAP_FILE_PATH}" 2>/dev/null || true
    fi

    # 从fstab移除
    if [[ -f /etc/fstab ]] && grep -q "${SWAP_FILE_PATH}" /etc/fstab; then
        # 备份fstab
        local backup_file="/etc/fstab.bak.$(date +%Y%m%d_%H%M%S)"
        cp /etc/fstab "${backup_file}" 2>/dev/null || true

        sed -i "\|${SWAP_FILE_PATH}|d" /etc/fstab
        log_info "已从 /etc/fstab 移除"
    fi

    # 删除文件
    if [[ -f "${SWAP_FILE_PATH}" ]]; then
        rm -f "${SWAP_FILE_PATH}"
        log_info "已删�?Swap 文件"
    fi

    # 清除缓存
    clear_cache

    SWAP_ENABLED=false
    return 0
}

# ==============================================================================
# 配置物理Swap
# @param mode: 策略模式
# @return: 0为成功，1为失�?# ==============================================================================
configure_physical_swap() {
    local mode="${1:-${STRATEGY_MODE}}"

    log_info "配置物理 Swap (策略: ${mode})..."

    local zram_ratio phys_limit swap_size swappiness dirty_ratio min_free
    read -r zram_ratio phys_limit swap_size swappiness dirty_ratio min_free <<< "$(calculate_strategy "${mode}")"

    if [[ ${swap_size} -lt 128 ]]; then
        swap_size=128
    fi

    # 检查是否需要重新配�?    if is_swap_file_enabled; then
        local swap_info
        swap_info=$(get_swap_file_info)
        local current_size
        current_size=$(echo "${swap_info}" | awk '{print $1}')

        local tolerance=100
        if [[ ${current_size} -ge $((swap_size - tolerance)) ]] && [[ ${current_size} -le $((swap_size + tolerance)) ]]; then
            log_info "物理 Swap 大小已符合要�?(${current_size}MB)"
            return 0
        fi

        log_info "重新调整 Swap 大小: ${current_size}MB -> ${swap_size}MB"
        disable_swap_file
    fi

    if ! create_swap_file "${swap_size}" "$(get_config 'physical_swap_priority')"; then
        handle_error "SWAP_CONFIG" "物理 Swap 配置失败"
        return 1
    fi

    return 0
}

# ==============================================================================
# 保存Swap配置
# @param swap_size: Swap大小（MB�?# @param enabled: 是否启用（true/false�?# @return: 0为成功，1为失�?# ==============================================================================
save_swap_config() {
    local swap_size="$1"
    local enabled="$2"

    local content
    cat <<EOF
# ============================================================================
# Z-Panel Pro 物理 Swap 配置
# ============================================================================
# 自动生成，请勿手动修�?#
# SWAP_SIZE: 物理 Swap 文件大小（MB�?# SWAP_ENABLED: 是否启用物理 Swap
# SWAP_PRIORITY: Swap 优先�?(ZRAM=$(get_config 'zram_priority'), 物理 Swap=$(get_config 'physical_swap_priority'))
# ============================================================================

SWAP_SIZE=${swap_size}
SWAP_ENABLED=${enabled}
SWAP_PRIORITY=$(get_config 'physical_swap_priority')
EOF

    if save_config_file "${SWAP_CONFIG_FILE}" "${content}"; then
        log_info "Swap 配置已保�?
        return 0
    else
        log_error "Swap 配置保存失败"
        return 1
    fi
}

# ==============================================================================
# 获取所有Swap设备信息
# @return: 格式化的Swap设备列表
# ==============================================================================
get_all_swap_devices() {
    echo "=== 系统 Swap 设备 ==="
    echo ""

    if swapon --show=NAME,SIZE,USED,PRIO --noheadings 2>/dev/null | grep -q .; then
        printf "%-30s %10s %10s %10s\n" "设备" "大小" "已用" "优先�?
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
        echo "未找到启用的 Swap 设备"
    fi

    echo ""
    echo "=== 总计 ==="
    local swap_total swap_used
    read -r swap_total swap_used <<< "$(get_swap_info false)"
    printf "总量: %sMB  已用: %sMB\n" "${swap_total}" "${swap_used}"
}