#!/bin/bash
# ==============================================================================
# Z-Panel Pro - 菜单管理模块
# ==============================================================================
# @description    菜单系统与交互处理
# @version       9.0.0-Lightweight
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 主菜单项
# ==============================================================================
declare -A MAIN_MENU_ITEMS=(
    ["1"]="一键智能优化"
    ["2"]="实时监控"
    ["3"]="ZRAM管理"
    ["4"]="Swap管理"
    ["5"]="内核参数"
    ["6"]="优化策略"
    ["7"]="性能报告"
    ["8"]="审计日志"
    ["9"]="系统信息"
    ["10"]="高级设置"
    ["0"]="退出程序"
)

# ==============================================================================
# ZRAM管理菜单项
# ==============================================================================
declare -A ZRAM_MENU_ITEMS=(
    ["1"]="启用ZRAM"
    ["2"]="停用ZRAM"
    ["3"]="调整ZRAM大小"
    ["4"]="更换压缩算法"
    ["5"]="查看ZRAM状态"
    ["0"]="返回主菜单"
)

# ==============================================================================
# Swap管理菜单项
# ==============================================================================
declare -A SWAP_MENU_ITEMS=(
    ["1"]="创建Swap"
    ["2"]="删除Swap"
    ["3"]="查看Swap状态"
    ["4"]="Swap性能优化"
    ["5"]="Swap监控报告"
    ["6"]="Swap使用分析"
    ["0"]="返回主菜单"
)

# ==============================================================================
# 优化策略菜单项
# ==============================================================================
declare -A STRATEGY_MENU_ITEMS=(
    ["1"]="保守模式"
    ["2"]="平衡模式"
    ["3"]="激进模式"
    ["4"]="查看策略详情"
    ["0"]="返回主菜单"
)

# ==============================================================================
# 性能报告菜单项
# ==============================================================================
declare -A PERFORMANCE_MENU_ITEMS=(
    ["1"]="查看性能报告"
    ["2"]="分析性能瓶颈"
    ["3"]="查看缓存统计"
    ["0"]="返回主菜单"
)

# ==============================================================================
# 审计日志菜单项
# ==============================================================================
declare -A AUDIT_MENU_ITEMS=(
    ["1"]="查看审计日志"
    ["2"]="审计统计"
    ["3"]="导出审计日志"
    ["4"]="清理过期日志"
    ["0"]="返回主菜单"
)

# ==============================================================================
# 显示主菜单
# ==============================================================================
show_main_menu() {
    ui_clear
    ui_draw_header "Z-Panel Pro v${VERSION} - 主菜单"
    ui_draw_row "  ${COLOR_WHITE}快捷键: ${COLOR_CYAN}[0]退出 ${COLOR_CYAN}[q]退出 ${COLOR_CYAN}[h]帮助"
    ui_draw_line

    # 按数字排序显示菜单项
    for key in $(printf '%s\n' "${!MAIN_MENU_ITEMS[@]}" | sort -n); do
        local item="${MAIN_MENU_ITEMS[$key]}"
        # 为常用菜单项添加快捷键提示
        case "${key}" in
            1) ui_draw_row "  ${COLOR_GREEN}${key}.${COLOR_NC} ${COLOR_WHITE}${item}${COLOR_NC} ${COLOR_GRAY}[推荐]${COLOR_NC}" ;;
            2) ui_draw_row "  ${COLOR_GREEN}${key}.${COLOR_NC} ${COLOR_WHITE}${item}${COLOR_NC} ${COLOR_GRAY}[实时]${COLOR_NC}" ;;
            *) ui_draw_menu_item "${key}" "${item}" ;;
        esac
    done

    ui_draw_bottom
    echo ""
}

# ==============================================================================
# 显示ZRAM管理菜单
# ==============================================================================
show_zram_menu() {
    ui_clear
    ui_draw_header "ZRAM管理"
    ui_draw_line

    for key in "${!ZRAM_MENU_ITEMS[@]}"; do
        ui_draw_menu_item "${key}" "${ZRAM_MENU_ITEMS[$key]}"
    done

    ui_draw_bottom
    echo ""
}

# ==============================================================================
# 显示Swap管理菜单
# ==============================================================================
show_swap_menu() {
    ui_clear
    ui_draw_header "Swap管理"
    ui_draw_line

    for key in "${!SWAP_MENU_ITEMS[@]}"; do
        ui_draw_menu_item "${key}" "${SWAP_MENU_ITEMS[$key]}"
    done

    ui_draw_bottom
    echo ""
}

# ==============================================================================
# 显示优化策略菜单
# ==============================================================================
show_strategy_menu() {
    ui_clear
    ui_draw_header "优化策略"
    ui_draw_line

    for key in "${!STRATEGY_MENU_ITEMS[@]}"; do
        ui_draw_menu_item "${key}" "${STRATEGY_MENU_ITEMS[$key]}"
    done

    ui_draw_bottom
    echo ""
}

# ==============================================================================
# 处理ZRAM管理
# ==============================================================================
handle_zram_management() {
    while true; do
        show_zram_menu
        echo -ne "${COLOR_WHITE}请选择 [0-5]: ${COLOR_NC}"
        read -r choice

        # 支持快捷键
        case "${choice}" in
            q|Q|0)
                return
                ;;
            1)
                log_info "正在启用ZRAM..."
                if configure_zram; then
                    log_info "ZRAM已成功启用"
                    ui_pause
                else
                    log_error "ZRAM启用失败"
                    ui_pause
                fi
                ;;
            2)
                log_info "正在停用ZRAM..."
                if ui_confirm "确定要停用ZRAM吗？"; then
                    if disable_zram; then
                        log_info "ZRAM已成功停用"
                    else
                        log_error "停用ZRAM失败"
                    fi
                fi
                ui_pause
                ;;
            3)
                log_info "正在调整ZRAM大小..."
                local current_size=$(get_config 'zram_size_mb' 256)
                echo -ne "${COLOR_WHITE}请输入ZRAM大小(MB) [当前: ${current_size}]: ${COLOR_NC}"
                read -r zram_size
                zram_size=${zram_size:-${current_size}}

                # 输入验证
                if [[ -z "${zram_size}" ]]; then
                    log_error "ZRAM大小不能为空"
                    ui_pause
                    continue
                fi

                if ! validate_positive_integer "${zram_size}"; then
                    log_error "ZRAM大小必须是正整数"
                    ui_pause
                    continue
                fi

                if [[ ${zram_size} -lt 64 ]]; then
                    log_error "ZRAM大小不能小于64MB"
                    ui_pause
                    continue
                fi

                if [[ ${zram_size} -gt $((SYSTEM_INFO[total_memory_mb] * 2)) ]]; then
                    log_error "ZRAM大小不能超过物理内存的2倍 (${COLOR_CYAN}$((SYSTEM_INFO[total_memory_mb] * 2))MB${COLOR_NC})"
                    ui_pause
                    continue
                fi

                set_config 'zram_size_mb' "${zram_size}"
                log_info "ZRAM大小已设置为${zram_size}MB，请重新启用ZRAM生效"
                ui_pause
                ;;
            4)
                log_info "正在更换压缩算法..."
                local current_algo=$(get_config 'zram_compression' 'lzo')
                local options=("lz4 [快速]" "lzo [默认]" "zstd [高效]")
                local selected
                selected=$(ui_select_menu "选择算法 (当前: ${current_algo})" "${options[@]}")
                if [[ -n "${selected}" ]]; then
                    local algo=$(echo "${selected}" | cut -d' ' -f1)
                    set_config 'zram_compression' "${algo}"
                    log_info "压缩算法已设置为${algo}，请重新启用ZRAM生效"
                fi
                ui_pause
                ;;
            5)
                show_status
                ui_pause
                ;;
            *)
                log_warn "无效选择: ${choice}"
                ui_pause
                ;;
        esac
    done
}

# ==============================================================================
# 处理Swap管理
# ==============================================================================
handle_swap_management() {
    while true; do
        show_swap_menu
        echo -ne "${COLOR_WHITE}请选择 [0-6]: ${COLOR_NC}"
        read -r choice

        # 支持快捷键
        case "${choice}" in
            q|Q|0)
                return
                ;;
            1)
                log_info "正在创建Swap..."
                local recommended=$(recommend_swap_size)
                if [[ "${recommended}" == "0" ]]; then
                    log_error "无法计算推荐Swap大小"
                    ui_pause
                    continue
                fi
                echo -ne "${COLOR_WHITE}请输入Swap大小(MB) [智能推荐: ${COLOR_GREEN}${recommended}MB${COLOR_NC}]: ${COLOR_NC}"
                read -r swap_size
                swap_size=${swap_size:-${recommended}}

                # 输入验证
                if [[ -z "${swap_size}" ]]; then
                    log_error "Swap大小不能为空"
                    ui_pause
                    continue
                fi

                if ! validate_positive_integer "${swap_size}"; then
                    log_error "Swap大小必须是正整数"
                    ui_pause
                    continue
                fi

                if [[ ${swap_size} -lt 128 ]]; then
                    log_error "Swap大小不能小于128MB"
                    ui_pause
                    continue
                fi

                local max_swap=$((SYSTEM_INFO[total_memory_mb] * 4))
                if [[ ${swap_size} -gt ${max_swap} ]]; then
                    log_error "Swap大小不能超过物理内存的4倍 (${COLOR_CYAN}${max_swap}MB${COLOR_NC})"
                    ui_pause
                    continue
                fi

                # 检查磁盘空间
                local disk_avail
                disk_avail=$(df -m / | awk 'NR==2 {print $4}')
                if [[ ${disk_avail} -lt $((swap_size + 512)) ]]; then
                    log_error "磁盘空间不足，需要至少${COLOR_CYAN}$((swap_size + 512))MB${COLOR_NC}，当前可用${COLOR_RED}${disk_avail}MB${COLOR_NC}"
                    ui_pause
                    continue
                fi

                if create_swap_file "${swap_size}"; then
                    log_info "Swap已成功创建 (${swap_size}MB)"
                    # 自动优化Swap性能
                    log_info "正在优化Swap性能..."
                    optimize_swap_performance "all"
                else
                    log_error "Swap创建失败"
                fi
                ui_pause
                ;;
            2)
                log_info "正在删除Swap..."
                if ui_confirm "确定要删除Swap文件吗？"; then
                    if disable_swap_file; then
                        log_info "Swap已成功删除"
                    else
                        log_error "删除Swap失败"
                    fi
                fi
                ui_pause
                ;;
            3)
                show_status
                ui_pause
                ;;
            4)
                log_info "正在优化Swap性能..."
                ui_clear
                ui_draw_header "Swap性能优化"
                ui_draw_line

                local options=("优化所有参数 [推荐]" "仅优化Swappiness" "仅优化VFS缓存" "返回")
                local selected
                selected=$(ui_select_menu "选择优化类型" "${options[@]}")

                case "${selected}" in
                    "优化所有参数 [推荐]"|1)
                        if optimize_swap_performance "all"; then
                            log_info "Swap性能优化完成"
                        else
                            log_error "Swap性能优化失败"
                        fi
                        ;;
                    "仅优化Swappiness"|2)
                        if optimize_swap_performance "swappiness"; then
                            log_info "Swappiness优化完成"
                        else
                            log_error "Swappiness优化失败"
                        fi
                        ;;
                    "仅优化VFS缓存"|3)
                        if optimize_swap_performance "vfs_cache_pressure"; then
                            log_info "VFS缓存优化完成"
                        else
                            log_error "VFS缓存优化失败"
                        fi
                        ;;
                    *)
                        ;;
                esac
                ui_pause
                ;;
            5)
                log_info "正在生成Swap监控报告..."
                ui_clear
                ui_draw_header "Swap监控报告"
                ui_draw_line

                local monitor_result
                monitor_result=$(monitor_swap_usage 80 90)

                local status swap_total swap_used swap_usage alert_level message
                status=$(echo "${monitor_result}" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
                swap_total=$(echo "${monitor_result}" | grep -o '"swap_total_mb": [0-9]*' | awk '{print $2}')
                swap_used=$(echo "${monitor_result}" | grep -o '"swap_used_mb": [0-9]*' | awk '{print $2}')
                swap_usage=$(echo "${monitor_result}" | grep -o '"swap_usage_percent": [0-9]*' | awk '{print $2}')
                alert_level=$(echo "${monitor_result}" | grep -o '"alert_level":"[^"]*"' | cut -d'"' -f4)
                message=$(echo "${monitor_result}" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)

                # 根据警报级别显示不同颜色
                local alert_color="${COLOR_GREEN}"
                [[ "${alert_level}" == "warning" ]] && alert_color="${COLOR_YELLOW}"
                [[ "${alert_level}" == "critical" ]] && alert_color="${COLOR_RED}"

                ui_draw_row "  状态: ${alert_color}${alert_level}${COLOR_NC}"
                if [[ "${status}" == "configured" ]]; then
                    ui_draw_row "  总大小: ${COLOR_CYAN}${swap_total}MB${COLOR_NC}"
                    ui_draw_row "  已使用: ${COLOR_CYAN}${swap_used}MB${COLOR_NC}"
                    ui_draw_row "  使用率: ${alert_color}${swap_usage}%${COLOR_NC}"
                    ui_draw_row "  消息: ${COLOR_WHITE}${message}${COLOR_NC}"
                else
                    ui_draw_row "  ${COLOR_WHITE}${message}${COLOR_NC}"
                fi

                ui_draw_bottom
                ui_pause
                ;;
            6)
                log_info "正在分析Swap使用情况..."
                ui_clear
                ui_draw_header "Swap使用分析"
                ui_draw_line

                get_swap_performance_report

                ui_pause
                ;;
            *)
                log_warn "无效选择: ${choice}"
                ui_pause
                ;;
        esac
    done
}

# ==============================================================================
# 处理一键优化
# ==============================================================================
handle_one_click_optimize() {
    log_info "正在执行一键智能优化..."
    if one_click_optimize; then
        log_info "一键优化完成！"
    else
        log_error "一键优化失败"
    fi
    ui_pause
}

# ==============================================================================
# 处理优化策略
# ==============================================================================

# ==============================================================================
# 显示性能报告菜单
# ==============================================================================
show_performance_menu() {
    ui_clear
    ui_draw_header "性能报告"
    ui_draw_line

    for key in "${!PERFORMANCE_MENU_ITEMS[@]}"; do
        ui_draw_menu_item "${key}" "${PERFORMANCE_MENU_ITEMS[$key]}"
    done

    ui_draw_bottom
    echo ""
}

# ==============================================================================
# 处理性能报告
# ==============================================================================
handle_performance_report() {
    while true; do
        show_performance_menu
        read -p "请选择 [0-3]: " choice

        case "${choice}" in
            1)
                log_info "正在生成性能报告..."
                get_performance_report
                ui_pause
                ;;
            2)
                log_info "正在分析性能瓶颈..."
                analyze_performance_bottlenecks
                ui_pause
                ;;
            3)
                log_info "正在查看缓存统计..."
                get_cache_stats
                ui_pause
                ;;
            0)
                return
                ;;
            *)
                log_warn "无效选择: ${choice}"
                ui_pause
                ;;
        esac
    done
}

# ==============================================================================
# 显示审计日志菜单
# ==============================================================================
show_audit_menu() {
    ui_clear
    ui_draw_header "审计日志"
    ui_draw_line

    for key in "${!AUDIT_MENU_ITEMS[@]}"; do
        ui_draw_menu_item "${key}" "${AUDIT_MENU_ITEMS[$key]}"
    done

    ui_draw_bottom
    echo ""
}

# ==============================================================================
# 处理审计日志
# ==============================================================================
handle_audit_log() {
    while true; do
        show_audit_menu
        read -p "请选择 [0-4]: " choice

        case "${choice}" in
            1)
                log_info "正在查看审计日志..."
                generate_audit_report
                ui_pause
                ;;
            2)
                log_info "正在生成审计统计..."
                get_audit_stats
                ui_pause
                ;;
            3)
                log_info "正在导出审计日志..."
                export_audit_log
                ui_pause
                ;;
            4)
                log_info "正在清理过期日志..."
                cleanup_audit_logs
                log_info "过期日志已清理"
                ui_pause
                ;;
            0)
                return
                ;;
            *)
                log_warn "无效选择: ${choice}"
                ui_pause
                ;;
        esac
    done
}
handle_strategy_management() {
    while true; do
        show_strategy_menu
        read -p "请选择 [0-4]: " choice

        case "${choice}" in
            1)
                set_strategy_mode "conservative"
                log_info "已切换到保守模式"
                ui_pause
                ;;
            2)
                set_strategy_mode "balance"
                log_info "已切换到平衡模式"
                ui_pause
                ;;
            3)
                set_strategy_mode "aggressive"
                log_info "已切换到激进模式"
                ui_pause
                ;;
            4)
                show_status
                ui_pause
                ;;
            0)
                return
                ;;
            *)
                log_warn "无效选择: ${choice}"
                ui_pause
                ;;
        esac
    done
}

# ==============================================================================
# 处理内核参数配置
# ==============================================================================
handle_kernel_management() {
    ui_clear
    ui_draw_header "内核参数配置"
    ui_draw_line

    log_info "正在配置内核参数..."
    if configure_virtual_memory; then
        log_info "内核参数配置完成"
    else
        log_error "内核参数配置失败"
    fi

    ui_pause
}

# ==============================================================================
# 处理系统信息
# ==============================================================================
handle_system_info() {
    show_status
    ui_pause
}

# ==============================================================================
# 处理高级设置
# ==============================================================================
handle_advanced_settings() {
    while true; do
        ui_clear
        ui_draw_header "高级设置"
        ui_draw_line

        local options=("刷新间隔" "日志级别" "启用/禁用自动启动" "返回主菜单")
        local choice
        choice=$(ui_select_menu "高级设置" "${options[@]}")

        case "${choice}" in
            "刷新间隔")
                read -p "请输入刷新间隔秒数 [默认: 1]: " interval
                interval=${interval:-1}
                if validate_positive_integer "${interval}"; then
                    set_config 'refresh_interval' "${interval}"
                    log_info "刷新间隔已设置为${interval}秒"
                else
                    log_error "无效的刷新间隔"
                fi
                ui_pause
                ;;
            "日志级别")
                local options=("DEBUG" "INFO" "WARN" "ERROR")
                local selected
                selected=$(ui_select_menu "选择级别" "${options[@]}")
                if [[ -n "${selected}" ]]; then
                    set_log_level "${selected}"
                    log_info "日志级别已设置为${selected}"
                fi
                ui_pause
                ;;
            "启用/禁用自动启动")
                local service_file="${SYSTEMD_SERVICE_FILE:-/etc/systemd/system/zpanel.service}"
                if [[ -f "${service_file}" ]] && systemctl is-enabled --quiet "zpanel" 2>/dev/null; then
                    if ui_confirm "确定要禁用自动启动吗？"; then
                        systemctl disable "zpanel" > /dev/null 2>&1
                        systemctl stop "zpanel" > /dev/null 2>&1
                        rm -f "${service_file}"
                        systemctl daemon-reload > /dev/null 2>&1
                        log_info "自动启动已禁用"
                    fi
                else
                    if ui_confirm "确定要启用自动启动吗？"; then
                        log_warn "请使用主脚本启用自动启动: ./Z-Panel.sh -e"
                    fi
                fi
                ui_pause
                ;;
            "返回主菜单")
                return
                ;;
        esac
    done
}

# ==============================================================================
# 主菜单循环
# ==============================================================================
main_menu() {
    while true; do
        show_main_menu
        echo -ne "${COLOR_WHITE}请选择 [0-10]: ${COLOR_NC}"
        read -r choice

        # 支持快捷键和命令
        case "${choice}" in
            q|Q|0)
                log_info "感谢使用 Z-Panel Pro，再见！"
                exit 0
                ;;
            1|o|O)
                handle_one_click_optimize
                ;;
            2|m|M)
                show_monitor
                ;;
            3|z|Z)
                handle_zram_management
                ;;
            4|s|S)
                handle_swap_management
                ;;
            5|k|K)
                handle_kernel_management
                ;;
            6|t|T)
                handle_strategy_management
                ;;
            7|p|P)
                handle_performance_report
                ;;
            8|a|A)
                handle_audit_log
                ;;
            9|i|I)
                handle_system_info
                ;;
            10)
                handle_advanced_settings
                ;;
            h|H|\?|help)
                show_help
                ui_pause
                ;;
            *)
                log_warn "无效选择: ${choice}，输入 h 查看帮助"
                ui_pause
                ;;
        esac
    done
}

# ==============================================================================
# 显示帮助信息
# ==============================================================================
show_help() {
    ui_clear
    ui_draw_header "Z-Panel Pro 帮助"
    ui_draw_section "快捷键"
    ui_draw_row "  ${COLOR_GREEN}q/Q${COLOR_NC} - 退出当前菜单"
    ui_draw_row "  ${COLOR_GREEN}h/H/?${COLOR_NC} - 显示帮助"
    ui_draw_row "  ${COLOR_GREEN}0${COLOR_NC} - 返回上级菜单/退出"
    ui_draw_line
    ui_draw_section "菜单快捷键"
    ui_draw_row "  ${COLOR_GREEN}1/o${COLOR_NC} - 一键智能优化"
    ui_draw_row "  ${COLOR_GREEN}2/m${COLOR_NC} - 实时监控"
    ui_draw_row "  ${COLOR_GREEN}3/z${COLOR_NC} - ZRAM管理"
    ui_draw_row "  ${COLOR_GREEN}4/s${COLOR_NC} - Swap管理"
    ui_draw_row "  ${COLOR_GREEN}5/k${COLOR_NC} - 内核参数"
    ui_draw_row "  ${COLOR_GREEN}6/t${COLOR_NC} - 优化策略"
    ui_draw_row "  ${COLOR_GREEN}7/p${COLOR_NC} - 性能报告"
    ui_draw_row "  ${COLOR_GREEN}8/a${COLOR_NC} - 审计日志"
    ui_draw_row "  ${COLOR_GREEN}9/i${COLOR_NC} - 系统信息"
    ui_draw_row "  ${COLOR_GREEN}10${COLOR_NC} - 高级设置"
    ui_draw_bottom
}


# ==============================================================================
# 导出函数
# ==============================================================================
export -f show_main_menu
export -f show_zram_menu
export -f show_swap_menu
export -f show_strategy_menu
export -f show_performance_menu
export -f show_audit_menu
export -f handle_zram_management
export -f handle_swap_management
export -f handle_one_click_optimize
export -f handle_performance_report
export -f handle_audit_log
export -f handle_strategy_management
export -f handle_kernel_management
export -f handle_system_info
export -f handle_advanced_settings
export -f main_menu
export -f show_help
