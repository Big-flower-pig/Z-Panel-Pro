#!/bin/bash
# ==============================================================================
# Z-Panel Pro - 菜单模块
# ==============================================================================
# @description    用户交互菜单系统
# @version       7.1.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 主菜单项定义
# ==============================================================================
declare -A MAIN_MENU_ITEMS=(
    ["1"]="监控面板"
    ["2"]="ZRAM管理"
    ["3"]="Swap管理"
    ["4"]="内核参数"
    ["5"]="策略管理"
    ["6"]="系统信息"
    ["7"]="备份还原"
    ["8"]="日志查看"
    ["9"]="高级设置"
    ["0"]="退出程�?
)

# ==============================================================================
# ZRAM管理菜单项定�?# ==============================================================================
declare -A ZRAM_MENU_ITEMS=(
    ["1"]="启用ZRAM"
    ["2"]="禁用ZRAM"
    ["3"]="调整ZRAM大小"
    ["4"]="更换压缩算法"
    ["5"]="查看ZRAM状�?
    ["0"]="返回主菜�?
)

# ==============================================================================
# Swap管理菜单项定�?# ==============================================================================
declare -A SWAP_MENU_ITEMS=(
    ["1"]="创建物理Swap"
    ["2"]="删除物理Swap"
    ["3"]="查看Swap状�?
    ["0"]="返回主菜�?
)

# ==============================================================================
# 策略管理菜单项定�?# ==============================================================================
declare -A STRATEGY_MENU_ITEMS=(
    ["1"]="保守模式"
    ["2"]="平衡模式"
    ["3"]="激进模�?
    ["4"]="自定义模�?
    ["5"]="查看当前策略"
    ["0"]="返回主菜�?
)

# ==============================================================================
# 显示主菜�?# ==============================================================================
show_main_menu() {
    ui_clear
    ui_draw_header "Z-Panel Pro v${VERSION} - 主菜�?
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
# 显示策略管理菜单
# ==============================================================================
show_strategy_menu() {
    ui_clear
    ui_draw_header "策略管理"
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
                log_info "启用ZRAM..."
                if configure_zram; then
                    log_info "ZRAM配置成功"
                    ui_pause
                else
                    log_error "ZRAM配置失败"
                    ui_pause
                fi
                ;;
            2)
                log_info "禁用ZRAM..."
                if ui_confirm "确定要禁用ZRAM吗？"; then
                    if disable_zram; then
                        log_info "ZRAM已禁�?
                    else
                        log_error "禁用ZRAM失败"
                    fi
                fi
                ui_pause
                ;;
            3)
                log_info "调整ZRAM大小..."
                read -p "请输入ZRAM大小(MB): " zram_size
                if validate_positive_integer "${zram_size}"; then
                    set_config 'zram_size_mb' "${zram_size}"
                    log_info "ZRAM大小已设置为${zram_size}MB，请重新启用ZRAM以生�?
                else
                    log_error "无效的ZRAM大小"
                fi
                ui_pause
                ;;
            4)
                log_info "更换压缩算法..."
                local options=("lz4" "lzo" "zstd")
                local selected
                selected=$(ui_select_menu "选择压缩算法" "${options[@]}")
                if [[ -n "${selected}" ]]; then
                    set_config 'compression_algorithm' "${selected}"
                    log_info "压缩算法已设置为${selected}，请重新启用ZRAM以生�?
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
                log_info "创建物理Swap..."
                read -p "请输入Swap大小(MB): " swap_size
                if validate_positive_integer "${swap_size}"; then
                    if configure_physical_swap "${swap_size}"; then
                        log_info "物理Swap创建成功"
                    else
                        log_error "物理Swap创建失败"
                    fi
                else
                    log_error "无效的Swap大小"
                fi
                ui_pause
                ;;
            2)
                log_info "删除物理Swap..."
                if ui_confirm "确定要删除物理Swap吗？"; then
                    if disable_swap_file; then
                        log_info "物理Swap已删�?
                    else
                        log_error "删除物理Swap失败"
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
# 处理策略管理
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
                log_info "已切换到激进模�?
                ui_pause
                ;;
            4)
                log_info "自定义模�?.."
                read -p "请输入ZRAM大小(MB): " zram_size
                read -p "请输入Swap大小(MB): " swap_size
                read -p "请输入swappiness�?0-100): " swappiness
                read -p "请输入I/O熔断阈�?0-100): " io_fuse

                if validate_positive_integer "${zram_size}" && \
                   validate_positive_integer "${swap_size}" && \
                   validate_number "${swappiness}" && \
                   validate_number "${io_fuse}"; then
                    set_config 'zram_size_mb' "${zram_size}"
                    set_config 'swap_size_mb' "${swap_size}"
                    set_config 'swappiness' "${swappiness}"
                    set_config 'io_fuse_threshold' "${io_fuse}"
                    log_info "自定义策略已设置"
                else
                    log_error "无效的参�?
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
# 处理内核参数管理
# ==============================================================================
handle_kernel_management() {
    ui_clear
    ui_draw_header "内核参数管理"
    ui_draw_line

    log_info "配置内核参数..."
    if configure_virtual_memory; then
        log_info "内核参数配置成功"
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
# 处理备份还原
# ==============================================================================
handle_backup_restore() {
    while true; do
        ui_clear
        ui_draw_header "备份与还�?
        ui_draw_line

        local options=("创建备份" "还原备份" "查看备份" "删除备份" "清理旧备�? "返回主菜�?)
        local choice
        choice=$(ui_select_menu "选择操作" "${options[@]}")

        case "${choice}" in
            "创建备份")
                log_info "创建系统备份..."
                local backup_id
                backup_id=$(create_backup)
                if [[ -n "${backup_id}" ]]; then
                    log_info "备份创建成功: ${backup_id}"
                else
                    log_error "备份创建失败"
                fi
                ui_pause
                ;;
            "还原备份")
                local backups
                readarray -t backups < <(list_backups)
                if [[ ${#backups[@]} -eq 0 ]]; then
                    log_warn "没有可用的备�?
                    ui_pause
                    continue
                fi
                local selected
                selected=$(ui_select_menu "选择要还原的备份" "${backups[@]}")
                if [[ -n "${selected}" ]]; then
                    local backup_id
                    backup_id=$(echo "${selected}" | cut -d'|' -f1)
                    if ui_confirm "确定要还原备�?${backup_id} 吗？"; then
                        if restore_backup "${backup_id}"; then
                            log_info "备份还原成功，请重启系统使更改生�?
                        else
                            log_error "备份还原失败"
                        fi
                    fi
                fi
                ui_pause
                ;;
            "查看备份")
                list_backups
                ui_pause
                ;;
            "删除备份")
                local backups
                readarray -t backups < <(list_backups)
                if [[ ${#backups[@]} -eq 0 ]]; then
                    log_warn "没有可用的备�?
                    ui_pause
                    continue
                fi
                local selected
                selected=$(ui_select_menu "选择要删除的备份" "${backups[@]}")
                if [[ -n "${selected}" ]]; then
                    local backup_id
                    backup_id=$(echo "${selected}" | cut -d'|' -f1)
                    if ui_confirm "确定要删除备�?${backup_id} 吗？"; then
                        if delete_backup "${backup_id}"; then
                            log_info "备份已删�?
                        else
                            log_error "删除备份失败"
                        fi
                    fi
                fi
                ui_pause
                ;;
            "清理旧备�?)
                read -p "保留最近几天的备份 [默认: 7]: " days
                days=${days:-7}
                if validate_positive_integer "${days}"; then
                    if clean_old_backups "${days}"; then
                        log_info "旧备份已清理"
                    else
                        log_error "清理备份失败"
                    fi
                else
                    log_error "无效的天�?
                fi
                ui_pause
                ;;
            "返回主菜�?)
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

        local options=("查看主日�? "查看ZRAM日志" "查看Swap日志" "清空日志" "返回主菜�?)
        local choice
        choice=$(ui_select_menu "选择操作" "${options[@]}")

        case "${choice}" in
            "查看主日�?)
                if [[ -f "${LOG_FILE}" ]]; then
                    less "${LOG_FILE}"
                else
                    log_warn "主日志文件不存在"
                    ui_pause
                fi
                ;;
            "查看ZRAM日志")
                local zram_log="${LOG_DIR}/zram.log"
                if [[ -f "${zram_log}" ]]; then
                    less "${zram_log}"
                else
                    log_warn "ZRAM日志文件不存�?
                    ui_pause
                fi
                ;;
            "查看Swap日志")
                local swap_log="${LOG_DIR}/swap.log"
                if [[ -f "${swap_log}" ]]; then
                    less "${swap_log}"
                else
                    log_warn "Swap日志文件不存�?
                    ui_pause
                fi
                ;;
            "清空日志")
                if ui_confirm "确定要清空所有日志吗�?; then
                    > "${LOG_FILE}"
                    > "${LOG_DIR}/zram.log" 2>/dev/null
                    > "${LOG_DIR}/swap.log" 2>/dev/null
                    log_info "日志已清�?
                fi
                ui_pause
                ;;
            "返回主菜�?)
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

        local options=("刷新间隔" "日志级别" "启用/禁用开机自�? "返回主菜�?)
        local choice
        choice=$(ui_select_menu "选择操作" "${options[@]}")

        case "${choice}" in
            "刷新间隔")
                read -p "请输入刷新间�?�? [当前: $(get_config 'refresh_interval')]: " interval
                if validate_positive_integer "${interval}"; then
                    set_config 'refresh_interval' "${interval}"
                    log_info "刷新间隔已设置为${interval}�?
                else
                    log_error "无效的刷新间�?
                fi
                ui_pause
                ;;
            "日志级别")
                local options=("DEBUG" "INFO" "WARN" "ERROR")
                local selected
                selected=$(ui_select_menu "选择日志级别" "${options[@]}")
                if [[ -n "${selected}" ]]; then
                    set_log_level "${selected}"
                    log_info "日志级别已设置为${selected}"
                fi
                ui_pause
                ;;
            "启用/禁用开机自�?)
                if is_service_installed; then
                    if ui_confirm "确定要禁用开机自启吗�?; then
                        disable_autostart
                        log_info "开机自启已禁用"
                    fi
                else
                    if ui_confirm "确定要启用开机自启吗�?; then
                        enable_autostart
                        log_info "开机自启已启用"
                    fi
                fi
                ui_pause
                ;;
            "返回主菜�?)
                return
                ;;
        esac
    done
}

# ==============================================================================
# 主程序入�?# ==============================================================================
main_menu() {
    while true; do
        show_main_menu
        read -p "请选择 [0-9]: " choice

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
                handle_system_info
                ;;
            7)
                handle_backup_restore
                ;;
            8)
                handle_log_viewing
                ;;
            9)
                handle_advanced_settings
                ;;
            0)
                log_info "感谢使用 Z-Panel Pro�?
                exit 0
                ;;
            *)
                log_warn "无效选择: ${choice}"
                ui_pause
                ;;
        esac
    done
}