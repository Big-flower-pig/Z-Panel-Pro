#!/bin/bash
# ==============================================================================
# Z-Panel Pro - 菜单管理模块
# ==============================================================================
# @description    菜单系统与交互处理
# @version       7.1.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 主菜单项
# ==============================================================================
declare -A MAIN_MENU_ITEMS=(
    ["1"]="实时监控"
    ["2"]="ZRAM管理"
    ["3"]="Swap管理"
    ["4"]="内核参数"
    ["5"]="优化策略"
    ["6"]="智能优化"    # V8.0 新增
    ["7"]="系统信息"
    ["8"]="备份恢复"
    ["9"]="日志查看"
    ["A"]="高级设置"
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
    ["4"]="自定义策略"
    ["5"]="查看策略详情"
    ["0"]="返回主菜单"
)

# ==============================================================================
# 智能优化菜单项 (V8.0)
# ==============================================================================
declare -A INTELLIGENT_MENU_ITEMS=(
    ["1"]="启动决策引擎"
    ["2"]="停止决策引擎"
    ["3"]="查看引擎状态"
    ["4"]="启动流处理器"
    ["5"]="停止流处理器"
    ["6"]="运行自适应调优"
    ["7"]="设置调优模式"
    ["8"]="查看缓存统计"
    ["9"]="查看反馈统计"
    ["A"]="查看自适应统计"
    ["0"]="返回主菜单"
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
# 显示智能优化菜单 (V8.0)
# ==============================================================================
show_intelligent_menu() {
    ui_clear
    ui_draw_header "智能优化 (V8.0)"
    ui_draw_line

    for key in "${!INTELLIGENT_MENU_ITEMS[@]}"; do
        ui_draw_menu_item "${key}" "${INTELLIGENT_MENU_ITEMS[$key]}"
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
                    if configure_physical_swap "${swap_size}"; then
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
handle_strategy_management() {
    while true; do
        show_strategy_menu
        read -p "请选择 [0-5]: " choice

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
                log_info "正在自定义策略..."
                read -p "请输入ZRAM大小(MB): " zram_size
                read -p "请输入Swap大小(MB): " swap_size
                read -p "请输入swappiness值(0-100): " swappiness
                read -p "请输入I/O熔断阈值(0-100): " io_fuse

                if validate_positive_integer "${zram_size}" && \
                   validate_positive_integer "${swap_size}" && \
                   validate_number "${swappiness}" && \
                   validate_number "${io_fuse}"; then
                    set_config 'zram_size_mb' "${zram_size}"
                    set_config 'swap_size_mb' "${swap_size}"
                    set_config 'swappiness' "${swappiness}"
                    set_config 'io_fuse_threshold' "${io_fuse}"
                    log_info "自定义策略已保存"
                else
                    log_error "无效的参数"
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
# 处理智能优化 (V8.0)
# ==============================================================================
handle_intelligent_optimization() {
    while true; do
        show_intelligent_menu
        read -p "请选择 [0-9,A]: " choice

        case "${choice}" in
            1)
                log_info "正在启动决策引擎..."
                if start_decision_engine; then
                    log_info "决策引擎已成功启动"
                else
                    log_error "决策引擎启动失败"
                fi
                ui_pause
                ;;
            2)
                log_info "正在停止决策引擎..."
                if ui_confirm "确定要停止决策引擎吗？"; then
                    if stop_decision_engine; then
                        log_info "决策引擎已成功停止"
                    else
                        log_error "决策引擎停止失败"
                    fi
                fi
                ui_pause
                ;;
            3)
                log_info "正在查看决策引擎状态..."
                local status=$(get_decision_engine_status)
                echo "${status}"
                ui_pause
                ;;
            4)
                log_info "正在启动流处理器..."
                if start_stream_processor "metrics" "json_stream_processor"; then
                    log_info "流处理器已成功启动"
                else
                    log_error "流处理器启动失败"
                fi
                ui_pause
                ;;
            5)
                log_info "正在停止流处理器..."
                if ui_confirm "确定要停止流处理器吗？"; then
                    if stop_stream_processor "metrics"; then
                        log_info "流处理器已成功停止"
                    else
                        log_error "流处理器停止失败"
                    fi
                fi
                ui_pause
                ;;
            6)
                log_info "正在运行自适应调优..."
                if run_adaptive_tuning; then
                    log_info "自适应调优已完成"
                    local stats=$(get_adaptive_stats)
                    echo "${stats}"
                else
                    log_error "自适应调优失败"
                fi
                ui_pause
                ;;
            7)
                log_info "正在设置调优模式..."
                local options=("auto" "conservative" "aggressive" "emergency")
                local selected
                selected=$(ui_select_menu "选择模式" "${options[@]}")
                if [[ -n "${selected}" ]]; then
                    if set_tuning_mode "${selected}"; then
                        log_info "调优模式已设置为: ${selected}"
                    else
                        log_error "设置调优模式失败"
                    fi
                fi
                ui_pause
                ;;
            8)
                log_info "正在查看缓存统计..."
                local stats=$(get_cache_stats)
                echo "${stats}"
                ui_pause
                ;;
            9)
                log_info "正在查看反馈统计..."
                local stats=$(get_feedback_stats)
                echo "${stats}"
                ui_pause
                ;;
            A|a)
                log_info "正在查看自适应统计..."
                local stats=$(get_adaptive_stats)
                echo "${stats}"
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
# 处理备份恢复
# ==============================================================================
handle_backup_restore() {
    while true; do
        ui_clear
        ui_draw_header "备份与恢复"
        ui_draw_line

        local options=("创建备份" "恢复备份" "列出备份" "删除备份" "清理旧备份" "返回主菜单")
        local choice
        choice=$(ui_select_menu "备份管理" "${options[@]}")

        case "${choice}" in
            "创建备份")
                log_info "正在创建备份..."
                local backup_id
                backup_id=$(create_backup)
                if [[ -n "${backup_id}" ]]; then
                    log_info "备份创建成功: ${backup_id}"
                else
                    log_error "备份创建失败"
                fi
                ui_pause
                ;;
            "恢复备份")
                local backups
                readarray -t backups < <(list_backups)
                if [[ ${#backups[@]} -eq 0 ]]; then
                    log_warn "没有可用的备份"
                    ui_pause
                    continue
                fi
                local selected
                selected=$(ui_select_menu "选择备份" "${backups[@]}")
                if [[ -n "${selected}" ]]; then
                    local backup_id
                    backup_id=$(echo "${selected}" | cut -d'|' -f1)
                    if ui_confirm "确定要恢复备份 ${backup_id} 吗？"; then
                        if restore_backup "${backup_id}"; then
                            log_info "备份已恢复，请重启系统以应用更改"
                        else
                            log_error "备份恢复失败"
                        fi
                    fi
                fi
                ui_pause
                ;;
            "列出备份")
                list_backups
                ui_pause
                ;;
            "删除备份")
                local backups
                readarray -t backups < <(list_backups)
                if [[ ${#backups[@]} -eq 0 ]]; then
                    log_warn "没有可用的备份"
                    ui_pause
                    continue
                fi
                local selected
                selected=$(ui_select_menu "选择备份" "${backups[@]}")
                if [[ -n "${selected}" ]]; then
                    local backup_id
                    backup_id=$(echo "${selected}" | cut -d'|' -f1)
                    if ui_confirm "确定要删除备份 ${backup_id} 吗？"; then
                        if delete_backup "${backup_id}"; then
                            log_info "备份已删除"
                        else
                            log_error "备份删除失败"
                        fi
                    fi
                fi
                ui_pause
                ;;
            "清理旧备份")
                read -p "清理多少天前的备份 [默认: 7]: " days
                days=${days:-7}
                if validate_positive_integer "${days}"; then
                    if clean_old_backups "${days}"; then
                        log_info "旧备份已清理"
                    else
                        log_error "清理失败"
                    fi
                else
                    log_error "无效的天数"
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
# 处理日志查看
# ==============================================================================
handle_log_viewing() {
    while true; do
        ui_clear
        ui_draw_header "日志查看"
        ui_draw_line

        local options=("主日志" "ZRAM日志" "Swap日志" "清空日志" "返回主菜单")
        local choice
        choice=$(ui_select_menu "日志管理" "${options[@]}")

        case "${choice}" in
            "主日志")
                if [[ -f "${LOG_FILE}" ]]; then
                    less "${LOG_FILE}"
                else
                    log_warn "日志文件不存在"
                    ui_pause
                fi
                ;;
            "ZRAM日志")
                local zram_log="${LOG_DIR}/zram.log"
                if [[ -f "${zram_log}" ]]; then
                    less "${zram_log}"
                else
                    log_warn "ZRAM日志文件不存在"
                    ui_pause
                fi
                ;;
            "Swap日志")
                local swap_log="${LOG_DIR}/swap.log"
                if [[ -f "${swap_log}" ]]; then
                    less "${swap_log}"
                else
                    log_warn "Swap日志文件不存在"
                    ui_pause
                fi
                ;;
            "清空日志")
                if ui_confirm "确定要清空所有日志吗？"; then
                    > "${LOG_FILE}"
                    > "${LOG_DIR}/zram.log" 2>/dev/null
                    > "${LOG_DIR}/swap.log" 2>/dev/null
                    log_info "日志已清空"
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
                read -p "请输入刷新间隔秒数 [默认: $(get_config 'refresh_interval')]: " interval
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
        read -p "请选择 [0-9,A]: " choice

        case "${choice}" in
            1)
                show_monitor
                ;;
            2)
                handle_zram_management
                ;;
            3)
                handle_swap_management
                ;;
            4)
                handle_kernel_management
                ;;
            5)
                handle_strategy_management
                ;;
            6)
                handle_intelligent_optimization
                ;;
            7)
                handle_system_info
                ;;
            8)
                handle_backup_restore
                ;;
            9)
                handle_log_viewing
                ;;
            A|a)
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
