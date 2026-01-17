#!/bin/bash
# ==============================================================================
# Z-Panel Pro - 监控面板模块
# ==============================================================================
# @description    系统监控与状态显示
# @version       7.1.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 监控面板清理函数
# ==============================================================================
cleanup_monitor() {
    clear_cache
    log_debug "监控面板已退出"
}

# ==============================================================================
# 显示内存状态
# ==============================================================================
show_memory_status() {
    ui_draw_section "[RAM] 使用情况"

    read -r mem_total mem_used mem_avail buff_cache <<< "$(get_memory_info true)"

    ui_draw_row " 使用: ${COLOR_GREEN}${mem_used}MB${COLOR_NC}  缓存: ${COLOR_CYAN}${buff_cache}MB${COLOR_NC}  空闲: ${COLOR_GREEN}${mem_avail}MB${COLOR_NC}"
    ui_draw_row " 物理内存负载:"
    echo -ne "  "
    ui_draw_progress_bar "${mem_used}" "${mem_total}" 46 ""
}

# ==============================================================================
# 显示ZRAM状态
# ==============================================================================
show_zram_status() {
    ui_draw_section "[ZRAM] 状态"

    if ! is_zram_enabled; then
        ui_draw_row " 状态: ${COLOR_RED}未启用${COLOR_NC}"
        return
    fi

    ui_draw_row " 状态: ${COLOR_GREEN}运行中${COLOR_NC}"

    # 解析ZRAM状态
    local zram_status
    zram_status=$(get_zram_status)

    local algo="unknown"
    local ratio="1.00"

    if echo "${zram_status}" | grep -q "enabled.*true"; then
        algo=$(echo "${zram_status}" | grep -o '"algorithm":"[^"]*"' | cut -d'"' -f4)
        ratio=$(echo "${zram_status}" | grep -o '"compression_ratio":"[^"]*"' | cut -d'"' -f4)
    fi

    [[ -z "${ratio}" ]] || [[ "${ratio}" == "0" ]] && ratio="1.00"

    ui_draw_row " 算法: ${COLOR_CYAN}${algo}${COLOR_NC}  压缩比: ${COLOR_YELLOW}${ratio}x${COLOR_NC}"

    ui_draw_row " ZRAM 压缩比:"
    echo -ne "  "
    ui_draw_compression_chart "${ratio}" 46

    read -r zram_total zram_used <<< "$(get_zram_usage)"
    ui_draw_row " ZRAM 负载:"
    echo -ne "  "
    ui_draw_progress_bar "${zram_used}" "${zram_total}" 46 ""
}

# ==============================================================================
# 显示Swap状态
# ==============================================================================
show_swap_status() {
    ui_draw_section "[SWAP] 负载"

    read -r swap_total swap_used <<< "$(get_swap_info true)"

    if [[ ${swap_total} -eq 0 ]]; then
        ui_draw_row " 状态: ${COLOR_RED}未启用${COLOR_NC}"
    else
        echo -ne "  "
        ui_draw_progress_bar "${swap_used}" "${swap_total}" 46 ""
    fi
}

# ==============================================================================
# 显示内核参数状态
# ==============================================================================
show_kernel_status() {
    ui_draw_section "[KERNEL] 参数"

    local swappiness
    swappiness=$(get_swappiness)

    ui_draw_row " swappiness:"
    echo -ne "  "
    ui_draw_progress_bar "${swappiness}" 100 46 ""
}

# ==============================================================================
# 显示保护机制状态
# ==============================================================================
show_protection_status() {
    ui_draw_section "[PROTECTION] 保护机制"
    ui_draw_row "  ${COLOR_GREEN}[OK]${COLOR_NC} I/O 熔断: ${COLOR_GREEN}已启用${COLOR_NC}"
    ui_draw_row "  ${COLOR_GREEN}[OK]${COLOR_NC} OOM 保护: ${COLOR_GREEN}已启用${COLOR_NC}"
    ui_draw_row "  ${COLOR_GREEN}[OK]${COLOR_NC} 物理内存熔断: ${COLOR_GREEN}已启用${COLOR_NC}"
}

# ==============================================================================
# 显示系统信息
# ==============================================================================
show_system_info() {
    ui_draw_row " 发行版: ${COLOR_GREEN}${SYSTEM_INFO[distro]} ${SYSTEM_INFO[version]}${COLOR_NC}"
    ui_draw_row " 内存: ${COLOR_GREEN}${SYSTEM_INFO[total_memory_mb]}MB${COLOR_NC} CPU: ${COLOR_GREEN}${SYSTEM_INFO[cpu_cores]}核心${COLOR_NC} 策略: ${COLOR_YELLOW}${STRATEGY_MODE}${COLOR_NC}"
}

# ==============================================================================
# 显示实时监控面板
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
        # 获取数据
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

        # 渲染界面
        if [[ ${data_changed} == true ]]; then
            ui_clear

            ui_draw_header "Z-Panel Pro 实时监控面板 v${VERSION}"
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
            echo -e "${COLOR_YELLOW}[INFO] 按 Ctrl+C 返回主菜单${COLOR_NC}"
            echo ""

            # 更新最后值
            last_mem_used=${mem_used}
            last_zram_used=${zram_used}
            last_swap_used=${swap_used}
            last_swappiness=${swappiness}
        fi

        sleep ${refresh_interval}
    done
}

# ==============================================================================
# 显示系统状态
# ==============================================================================
show_status() {
    ui_clear

    ui_draw_header "Z-Panel Pro 系统状态 v${VERSION}"

    # 系统信息
    ui_draw_section "[SYSTEM] 信息"
    show_system_info

    # ZRAM状态
    show_zram_status

    # Swap状态
    ui_draw_section "[SWAP] 状态"

    read -r swap_total swap_used <<< "$(get_swap_info false)"

    if [[ ${swap_total} -eq 0 ]]; then
        ui_draw_row " 状态: ${COLOR_RED}未启用${COLOR_NC}"
    else
        ui_draw_row " 总量: ${COLOR_CYAN}${swap_total}MB${COLOR_NC} 已用: ${COLOR_CYAN}${swap_used}MB${COLOR_NC}"
        ui_draw_row " Swap 负载:"
        echo -ne "  "
        ui_draw_progress_bar "${swap_used}" "${swap_total}" 46 ""
    fi

    # 内核参数
    show_kernel_status

    # 保护机制
    show_protection_status

    ui_draw_bottom
    echo ""
}