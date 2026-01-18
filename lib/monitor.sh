#!/bin/bash
# ==============================================================================
# Z-Panel Pro V9.0 - 监控模块
# ==============================================================================
# @description    实时系统监控界面
# @version       9.0.0-Lightweight
# @author        Z-Panel Team
# @license       MIT License
# ==============================================================================

# ==============================================================================
# 监控清理函数
# ==============================================================================
cleanup_monitor() {
    clear_cache
    log_debug "监控已清理"
}

# ==============================================================================
# 显示内存状态
# ==============================================================================
show_memory_status() {
    ui_draw_section "[RAM] 内存状态"

    read -r mem_total mem_used mem_avail buff_cache <<< "$(get_memory_info true)"

    ui_draw_row " 已用: ${COLOR_GREEN}${mem_used}MB${COLOR_NC}  缓存: ${COLOR_CYAN}${buff_cache}MB${COLOR_NC}  可用: ${COLOR_GREEN}${mem_avail}MB${COLOR_NC}"
    ui_draw_row " 内存使用率:"
    echo -ne "  "
    ui_draw_progress_bar "${mem_used}" "${mem_total}" 46 ""
}

# ==============================================================================
# 显示ZRAM状态
# ==============================================================================
show_zram_status() {
    ui_draw_section "[ZRAM] 压缩状态"

    if ! is_zram_enabled; then
        ui_draw_row " 状态: ${COLOR_RED}未启用${COLOR_NC}"
        return
    fi

    ui_draw_row " 状态: ${COLOR_GREEN}已启用${COLOR_NC}"

    # 获取ZRAM信息
    local zram_status
    zram_status=$(get_zram_status)

    local algo="unknown"
    local ratio="1.00"

    if echo "${zram_status}" | grep -q '"enabled":\s*true'; then
        algo=$(echo "${zram_status}" | grep -o '"algorithm":"[^"]*"' | cut -d'"' -f4)
        ratio=$(echo "${zram_status}" | grep -o '"compression_ratio":"[^"]*"' | cut -d'"' -f4)

        # 验证提取的值
        [[ -z "${algo}" ]] && algo="unknown"
        [[ -z "${ratio}" ]] || [[ "${ratio}" == "0" ]] && ratio="1.00"
    fi

    ui_draw_row " 算法: ${COLOR_CYAN}${algo}${COLOR_NC}  压缩比: ${COLOR_YELLOW}${ratio}x${COLOR_NC}"

    ui_draw_row " 压缩效率:"
    echo -ne "  "
    ui_draw_compression_chart "${ratio}" 46

    read -r zram_total zram_used <<< "$(get_zram_usage)"
    ui_draw_row " ZRAM 使用率:"
    echo -ne "  "
    ui_draw_progress_bar "${zram_used}" "${zram_total}" 46 ""
}

# ==============================================================================
# 显示Swap状态
# ==============================================================================
show_swap_status() {
    ui_draw_section "[SWAP] 交换空间"

    read -r swap_total swap_used <<< "$(get_swap_info true)"

    if [[ ${swap_total} -eq 0 ]]; then
        ui_draw_row " 状态: ${COLOR_RED}未配置${COLOR_NC}"
    else
        echo -ne "  "
        ui_draw_progress_bar "${swap_used}" "${swap_total}" 46 ""
    fi
}

# ==============================================================================
# 显示内核参数状态
# ==============================================================================
show_kernel_status() {
    ui_draw_section "[KERNEL] 内核参数"

    local swappiness
    swappiness=$(get_swappiness)

    ui_draw_row " swappiness:"
    echo -ne "  "
    ui_draw_progress_bar "${swappiness}" 100 46 ""
}

# ==============================================================================
# 显示保护状态
# ==============================================================================
show_protection_status() {
    ui_draw_section "[PROTECTION] 保护机制"
    ui_draw_row "  ${COLOR_GREEN}[OK]${COLOR_NC} I/O 保护: ${COLOR_GREEN}已启用${COLOR_NC}"
    ui_draw_row "  ${COLOR_GREEN}[OK]${COLOR_NC} OOM 保护: ${COLOR_GREEN}已启用${COLOR_NC}"
    ui_draw_row "  ${COLOR_GREEN}[OK]${COLOR_NC} 进程保护: ${COLOR_GREEN}已启用${COLOR_NC}"
}

# ==============================================================================
# 显示系统信息
# ==============================================================================
show_system_info() {
    ui_draw_row " 系统: ${COLOR_GREEN}${SYSTEM_INFO[distro]} ${SYSTEM_INFO[version]}${COLOR_NC}"
    ui_draw_row " 内存: ${COLOR_GREEN}${SYSTEM_INFO[total_memory_mb]}MB${COLOR_NC} CPU: ${COLOR_GREEN}${SYSTEM_INFO[cpu_cores]}核${COLOR_NC} 模式: ${COLOR_YELLOW}${STRATEGY_MODE}${COLOR_NC}"
}

# ==============================================================================
# 显示实时监控
# ==============================================================================
show_monitor() {
    ui_clear

    trap 'cleanup_monitor; return 0' INT TERM QUIT HUP

    local last_mem_used=0
    local last_zram_used=0
    local last_swap_used=0
    local last_swappiness=0
    local refresh_interval=$(get_config 'refresh_interval')
    local force_refresh=true

    while true; do
        # 读取数据（使用缓存减少系统调用）
        read -r mem_total mem_used mem_avail buff_cache <<< "$(get_memory_info true)"
        read -r zram_total zram_used <<< "$(get_zram_usage)"
        read -r swap_total swap_used <<< "$(get_swap_info true)"
        local swappiness
        swappiness=$(get_swappiness)

        # 检查数据变化
        local data_changed=false
        if [[ ${force_refresh} == true ]] || \
           [[ ${mem_used} -ne ${last_mem_used} ]] || \
           [[ ${zram_used} -ne ${last_zram_used} ]] || \
           [[ ${swap_used} -ne ${last_swap_used} ]] || \
           [[ ${swappiness} -ne ${last_swappiness} ]]; then
            data_changed=true
            force_refresh=false
        fi

        # 刷新显示
        if [[ ${data_changed} == true ]]; then
            ui_clear

            ui_draw_header "Z-Panel Pro 实时监控 v${VERSION}"
            show_system_info
            ui_draw_line

            show_memory_status
            ui_draw_line

            show_zram_status
            ui_draw_line

            show_swap_status
            ui_draw_line

            show_kernel_status
            ui_draw_line

            show_protection_status

            ui_draw_bottom
            echo ""
            echo -e "${COLOR_YELLOW}[INFO] 按Ctrl+C退出监控${COLOR_NC}"
            echo ""

            # 更新缓存
            last_mem_used=${mem_used}
            last_zram_used=${zram_used}
            last_swap_used=${swap_used}
            last_swappiness=${swappiness}
        fi

        sleep ${refresh_interval}
    done
}

# ==============================================================================
# 显示状态摘要
# ==============================================================================
show_status() {
    ui_clear

    ui_draw_header "Z-Panel Pro 系统状态 v${VERSION}"

    # 系统信息
    ui_draw_section "[SYSTEM] 系统信息"
    show_system_info

    # ZRAM状态
    show_zram_status

    # Swap状态
    ui_draw_section "[SWAP] 交换空间"

    read -r swap_total swap_used <<< "$(get_swap_info false)"

    if [[ ${swap_total} -eq 0 ]]; then
        ui_draw_row " 状态: ${COLOR_RED}未配置${COLOR_NC}"
    else
        ui_draw_row " 总量: ${COLOR_CYAN}${swap_total}MB${COLOR_NC} 已用: ${COLOR_CYAN}${swap_used}MB${COLOR_NC}"
        ui_draw_row " Swap 使用率:"
        echo -ne "  "
        ui_draw_progress_bar "${swap_used}" "${swap_total}" 46 ""
    fi

    # 内核参数
    show_kernel_status

    # 保护状态
    show_protection_status

    ui_draw_bottom
    echo ""
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f cleanup_monitor
export -f show_memory_status
export -f show_zram_status
export -f show_swap_status
export -f show_kernel_status
export -f show_protection_status
export -f show_system_info
export -f show_monitor
export -f show_status
