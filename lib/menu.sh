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

)

# ==============================================================================
# 显示主菜单
# ==============================================================================
show_main_menu() {
    ui_clear
    ui_draw_header "Z-Panel Pro v${VERSION} - 主菜单"
    ui_draw_line

    for key in "${!MAIN_MENU_ITEMS[@]}"; do
        ui_draw_menu_item "${key}" "${MAIN_MENU_ITEMS[$key]}"
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
        read -p "请选择 [0-5]: " choice

        case "${choice}" in
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
                read -p "请输入ZRAM大小(MB): " zram_size
                if validate_positive_integer "${zram_size}"; then
                    set_config 'zram_size_mb' "${zram_size}"
                    log_info "ZRAM大小已设置为${zram_size}MB，请重新启用ZRAM生效"
                else
                    log_error "无效的ZRAM大小"
                fi
                ui_pause
                ;;
            4)
                log_info "正在更换压缩算法..."
                local options=("lz4" "lzo" "zstd")
                local selected
                selected=$(ui_select_menu "选择算法" "${options[@]}")
                if [[ -n "${selected}" ]]; then
                    set_config 'compression_algorithm' "${selected}"
                    log_info "压缩算法已设置为${selected}，请重新启用ZRAM生效"
                fi
                ui_pause
                ;;
            5)
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
# 处理Swap管理
# ==============================================================================
handle_swap_management() {
    while true; do
        show_swap_menu
        read -p "请选择 [0-3]: " choice

        case "${choice}" in
            1)
                log_info "正在创建Swap..."
                read -p "请输入Swap大小(MB): " swap_size
                if validate_positive_integer "${swap_size}"; then
                    if create_swap_file "${swap_size}"; then
                        log_info "Swap已成功创建"
                    else
                        log_error "Swap创建失败"
                    fi
                else
                    log_error "无效的Swap大小"
                fi
                ui_pause
                ;;
            2)
                log_info "正在删除Swap..."
                if ui_confirm "确定要删除Swap文件吗？"; then
                    if disable_swap_file; then
                        log_info "Swap已成功删除"
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
        read -p "请选择 [0-5]: " choice

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
                if is_service_installed; then
                    if ui_confirm "确定要禁用自动启动吗？"; then
                        disable_autostart
                        log_info "自动启动已禁用"
                    fi
                else
                    if ui_confirm "确定要启用自动启动吗？"; then
                        enable_autostart
                        log_info "自动启动已启用"
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
        read -p "请选择 [0-10]: " choice

        case "${choice}" in
            1)
                handle_one_click_optimize
                ;;
            2)
                show_monitor
                ;;
            3)
                handle_zram_management
                ;;
            4)
                handle_swap_management
                ;;
            5)
                handle_kernel_management
                ;;
            6)
                handle_strategy_management
                ;;
            7)
                handle_performance_report
                ;;
            8)
                handle_audit_log
                ;;
            9)
                handle_system_info
                ;;
            10)
                handle_advanced_settings
                ;;
            0)
                log_info "感谢使用 Z-Panel Pro，再见！"
                exit 0
                ;;
            *)
                log_warn "无效选择: ${choice}"
                ui_pause
                ;;
        esac
    done
}
