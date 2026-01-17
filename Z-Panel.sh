#!/bin/bash
# ==============================================================================
# Z-Panel Pro V8.0 - 企业级 Linux 内存优化工具
# ==============================================================================
# @description    ZRAM、Swap、内核参数智能优化管理工具 V8.0 企业版
# @version       8.0.0-Enterprise
# @author        Z-Panel Team
# @license       MIT License
# @website       https://github.com/Z-Panel-Pro/Z-Panel-Pro
# ==============================================================================

set -euo pipefail

# ==============================================================================
# 路径定义
# ==============================================================================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/lib"

# 核心库加载
# 基础模块
source "${LIB_DIR}/core.sh"           # 核心配置和常量
source "${LIB_DIR}/error_handler.sh"  # 错误处理和日志
source "${LIB_DIR}/utils.sh"          # 工具函数
source "${LIB_DIR}/lock.sh"           # 文件锁
source "${LIB_DIR}/input_validator.sh" # 输入验证模块
source "${LIB_DIR}/transaction.sh"    # 事务管理模块
source "${LIB_DIR}/lock_secure.sh"    # 安全文件锁
# 功能模块
source "${LIB_DIR}/system.sh"         # 系统检测
source "${LIB_DIR}/data_collector.sh" # 数据采集
source "${LIB_DIR}/ui.sh"             # UI渲染
source "${LIB_DIR}/strategy.sh"       # 策略管理
source "${LIB_DIR}/zram.sh"           # ZRAM管理
source "${LIB_DIR}/swap.sh"           # Swap管理
source "${LIB_DIR}/kernel.sh"         # 内核参数
source "${LIB_DIR}/backup.sh"         # 备份还原
source "${LIB_DIR}/monitor.sh"        # 监控面板
source "${LIB_DIR}/menu.sh"           # 菜单系统
# V8.0 新增模块
source "${LIB_DIR}/decision_engine.sh" # 智能决策引擎
source "${LIB_DIR}/stream_processor.sh" # 流式数据处理
source "${LIB_DIR}/cache_manager.sh"  # 缓存管理器
source "${LIB_DIR}/feedback_loop.sh"   # 反馈循环
source "${LIB_DIR}/adaptive_tuner.sh"  # 自适应调优

# ==============================================================================
# 全局变量
# ==============================================================================
declare -g LOCK_FD=0
declare -g LOCK_FILE="${LOCK_DIR}/zpanel.lock"

# ==============================================================================
# 服务管理函数
# ==============================================================================

# 检查服务是否已安装
is_service_installed() {
    [[ -f "${SYSTEMD_SERVICE_FILE}" ]] && systemctl is-enabled --quiet "${SERVICE_NAME}" 2>/dev/null
}

# 启用开机自启
enable_autostart() {
    log_info "配置开机自启..."

    # 创建systemd服务文件
    cat > "${SYSTEMD_SERVICE_FILE}" << 'EOF'
[Unit]
Description=Z-Panel Pro Memory Optimizer
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'source /opt/Z-Panel-Pro/lib/core.sh && source /opt/Z-Panel-Pro/lib/error_handler.sh && source /opt/Z-Panel-Pro/lib/system.sh && source /opt/Z-Panel-Pro/lib/data_collector.sh && source /opt/Z-Panel-Pro/lib/strategy.sh && source /opt/Z-Panel-Pro/lib/zram.sh && source /opt/Z-Panel-Pro/lib/swap.sh && source /opt/Z-Panel-Pro/lib/kernel.sh && configure_zram && configure_physical_swap && configure_virtual_memory'
RemainAfterExit=true
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # 重载并启用systemd服务
    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}"

    log_info "开机自启已启用"
}

# 禁用开机自启
disable_autostart() {
    log_info "禁用开机自启..."

    if [[ -f "${SYSTEMD_SERVICE_FILE}" ]]; then
        systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
        systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
        rm -f "${SYSTEMD_SERVICE_FILE}"
        systemctl daemon-reload
    fi

    log_info "开机自启已禁用"
}

# ==============================================================================
# 系统初始化函数
# ==============================================================================

# 初始化日志系统
init_logging_system() {
    # 创建日志目录
    mkdir -p "${LOG_DIR}"

    # 设置文件权限
    ensure_file_permissions "${LOG_FILE}" 640
    ensure_dir_permissions "${LOG_DIR}" 750

    # 初始化日志
    init_logging "${LOG_FILE}"
    set_log_level "INFO"
}

# 初始化配置目录
init_config_dirs() {
    local dirs=(
        "${CONFIG_DIR}"
        "${LOCK_DIR}"
        "${BACKUP_DIR}"
        "${LOG_DIR}"
    )

    for dir in "${dirs[@]}"; do
        if [[ ! -d "${dir}" ]]; then
            mkdir -p "${dir}"
            ensure_dir_permissions "${dir}" 750
        fi
    done
}

# 检查运行环境
check_runtime_env() {
    log_info "检查运行环境..."

    # 检查root权限
    if [[ ${EUID} -ne 0 ]]; then
        handle_error "需要root权限运行此脚本" "exit" "check_runtime_env"
    fi

    # 检测系统
    detect_system

    # 检查内核版本
    if ! check_kernel_version; then
        handle_error "内核版本过低，需要${MIN_KERNEL_VERSION} 或更高版本" "exit" "check_runtime_env"
    fi

    # 检查必要命令
    check_commands awk grep sed free tr cut head tail sort uniq wc

    log_info "运行环境检查完成"
}

# 加载系统配置
load_system_config() {
    log_info "加载系统配置..."

    # 加载轻量级配置
    if [[ -f "${CONFIG_DIR}/lightweight.conf" ]]; then
        log_info "检测到轻量级模式配置..."
        safe_source "${CONFIG_DIR}/lightweight.conf"
        export ZPANEL_MODE="${ZPANEL_MODE:-standard}"
        log_info "当前运行模式: ${ZPANEL_MODE}"
    fi

    # 加载策略配置
    load_strategy_config

    # 加载ZRAM配置
    if [[ -f "${ZRAM_CONFIG_FILE}" ]]; then
        safe_source "${ZRAM_CONFIG_FILE}"
    fi

    # 加载内核配置
    if [[ -f "${KERNEL_CONFIG_FILE}" ]]; then
        safe_source "${KERNEL_CONFIG_FILE}"
    fi

    # 加载Swap配置
    if [[ -f "${SWAP_CONFIG_FILE}" ]]; then
        safe_source "${SWAP_CONFIG_FILE}"
    fi

    log_info "系统配置加载完成"
}

# 初始化系统
init_system() {
    log_info "初始化系统..."

    # 初始化配置目录
    init_config_dirs

    # 初始化日志系统
    init_logging_system

    # 检查运行环境
    check_runtime_env

    # 加载系统配置
    load_system_config

    # 设置策略模式
    local current_strategy
    current_strategy=$(get_strategy_mode)
    STRATEGY_MODE="${current_strategy:-${STRATEGY_BALANCE}}"

    log_info "系统初始化完成"
}

# ==============================================================================
# 帮助信息函数
# ==============================================================================

# 显示帮助信息
show_help() {
    cat << EOF
Z-Panel Pro v${VERSION} - 企业级 Linux 内存优化工具 (V8.0 企业版)

用法: $0 [选项]

基本选项:
  -h, --help              显示帮助信息
  -v, --version           显示版本信息
  -m, --monitor           显示实时监控面板
  -s, --status            显示系统状态
  -c, --configure         配置向导

管理选项:
  -e, --enable            启用开机自启
  -d, --disable           禁用开机自启
  -b, --backup            创建系统备份
  -r, --restore <ID>      还原系统备份

高级选项:
  --strategy <mode>       设置策略模式 (conservative|balance|aggressive)
  --log-level <level>     设置日志级别 (DEBUG|INFO|WARN|ERROR)

V8.0 新增选项:
  --start-decision-engine 启动智能决策引擎
  --stop-decision-engine  停止智能决策引擎
  --status-decision-engine 查看决策引擎状态
  --start-stream-processor 启动流式处理器
  --stop-stream-processor  停止流式处理器
  --run-adaptive-tuning   执行自适应调优
  --set-tuning-mode <mode> 设置调优模式 (auto|conservative|aggressive|emergency)
  --show-cache-stats      显示缓存统计
  --show-feedback-stats   显示反馈统计
  --show-adaptive-stats   显示自适应调优统计

示例:
  $0 -m                   显示实时监控面板
  $0 -s                   显示系统状态
  $0 -c                   运行配置向导
  $0 --strategy balance   设置平衡模式
  $0 --start-decision-engine  启动智能决策引擎
  $0 --run-adaptive-tuning   执行自适应调优
  $0 -b                   创建系统备份

官网: https://github.com/Z-Panel-Pro/Z-Panel-Pro
EOF
}

# 显示版本信息
show_version() {
    cat << EOF
Z-Panel Pro v${VERSION} - Enterprise Edition
Copyright (c) 2024 Z-Panel Team
License: MIT License
Website: https://github.com/Z-Panel-Pro/Z-Panel-Pro
EOF
}

# ==============================================================================
# 主函数
# ==============================================================================

main() {
    local action="menu"
    local strategy=""
    local backup_id=""
    local tuning_mode=""
    local mode=""

    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -m|--monitor)
                action="monitor"
                shift
                ;;
            -s|--status)
                action="status"
                shift
                ;;
            -c|--configure)
                action="configure"
                shift
                ;;
            -e|--enable)
                action="enable"
                shift
                ;;
            -d|--disable)
                action="disable"
                shift
                ;;
            -b|--backup)
                action="backup"
                shift
                ;;
            -r|--restore)
                action="restore"
                backup_id="$2"
                shift 2
                ;;
            --strategy)
                strategy="$2"
                shift 2
                ;;
            --log-level)
                set_log_level "$2"
                shift 2
                ;;
            # V8.0 新增选项
            --start-decision-engine)
                action="start_decision_engine"
                shift
                ;;
            --stop-decision-engine)
                action="stop_decision_engine"
                shift
                ;;
            --status-decision-engine)
                action="status_decision_engine"
                shift
                ;;
            --start-stream-processor)
                action="start_stream_processor"
                shift
                ;;
            --stop-stream-processor)
                action="stop_stream_processor"
                shift
                ;;
            --run-adaptive-tuning)
                action="run_adaptive_tuning"
                shift
                ;;
            --set-tuning-mode)
                tuning_mode="$2"
                action="set_tuning_mode"
                shift 2
                ;;
            --show-cache-stats)
                action="show_cache_stats"
                shift
                ;;
            --show-feedback-stats)
                action="show_feedback_stats"
                shift
                ;;
            --show-adaptive-stats)
                action="show_adaptive_stats"
                shift
                ;;
            --mode)
                mode="$2"
                shift 2
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # 获取文件锁
    if ! acquire_lock; then
        local lock_pid
        lock_pid=$(get_lock_pid)
        log_error "Z-Panel Pro 正在运行 (PID: ${lock_pid})"
        exit 1
    fi

    # 初始化系统
    init_system

    # 初始化V8.0高级模块 (轻量级模式跳过)
    if [[ "${ZPANEL_MODE:-standard}" != "lightweight" ]]; then
        log_info "初始化V8.0高级模块..."
        init_cache_manager
        init_feedback_loop
        init_stream_processor
        init_adaptive_tuner
        log_info "V8.0高级模块初始化完成"
    else
        log_info "轻量级模式，跳过高级功能初始化"
    fi

    # 设置策略模式
    if [[ -n "${strategy}" ]]; then
        if validate_strategy_mode "${strategy}"; then
            set_strategy_mode "${strategy}"
            log_info "策略模式已设置: ${strategy}"
        else
            log_error "无效的策略模式: ${strategy}"
            exit 1
        fi
    fi

    # 执行操作
    case "${action}" in
        monitor)
            show_monitor
            ;;
        status)
            show_status
            ;;
        configure)
            main_menu
            ;;
        enable)
            enable_autostart
            ;;
        disable)
            disable_autostart
            ;;
        backup)
            backup_id=$(create_backup)
            if [[ -n "${backup_id}" ]]; then
                log_info "备份创建成功: ${backup_id}"
            else
                log_error "备份创建失败"
                exit 1
            fi
            ;;
        restore)
            if [[ -z "${backup_id}" ]]; then
                log_error "请指定备份ID"
                exit 1
            fi
            if restore_backup "${backup_id}"; then
                log_info "备份还原成功，请重启系统使配置生效"
            else
                log_error "备份还原失败"
                exit 1
            fi
            ;;
        # V8.0 新增操作
        start_decision_engine)
            log_info "启动智能决策引擎..."
            if start_decision_engine; then
                log_info "智能决策引擎已启动"
            else
                log_error "智能决策引擎启动失败"
                exit 1
            fi
            ;;
        stop_decision_engine)
            log_info "停止智能决策引擎..."
            if stop_decision_engine; then
                log_info "智能决策引擎已停止"
            else
                log_error "智能决策引擎停止失败"
                exit 1
            fi
            ;;
        status_decision_engine)
            log_info "查询智能决策引擎状态..."
            local status=$(get_decision_engine_status)
            echo "${status}"
            ;;
        start_stream_processor)
            log_info "启动流式数据处理器..."
            if start_stream_processor; then
                log_info "流式数据处理器已启动"
            else
                log_error "流式数据处理器启动失败"
                exit 1
            fi
            ;;
        stop_stream_processor)
            log_info "停止流式数据处理器..."
            if stop_stream_processor; then
                log_info "流式数据处理器已停止"
            else
                log_error "流式数据处理器停止失败"
                exit 1
            fi
            ;;
        run_adaptive_tuning)
            log_info "执行自适应调优..."
            if run_adaptive_tuning; then
                log_info "自适应调优执行完成"
                local stats=$(get_adaptive_stats)
                echo "${stats}"
            else
                log_error "自适应调优执行失败"
                exit 1
            fi
            ;;
        set_tuning_mode)
            if [[ -n "${tuning_mode}" ]]; then
                if set_tuning_mode "${tuning_mode}"; then
                    log_info "调优模式已设置: ${tuning_mode}"
                else
                    log_error "无效的调优模式: ${tuning_mode}"
                    exit 1
                fi
            fi
            ;;
        show_cache_stats)
            local stats=$(get_cache_stats)
            echo "${stats}"
            ;;
        show_feedback_stats)
            local stats=$(get_feedback_stats)
            echo "${stats}"
            ;;
        show_adaptive_stats)
            local stats=$(get_adaptive_stats)
            echo "${stats}"
            ;;
        menu)
            main_menu
            ;;
    esac

    # 清理V8.0高级模块 (轻量级模式跳过)
    if [[ "${ZPANEL_MODE:-standard}" != "lightweight" ]]; then
        log_debug "清理V8.0高级模块..."
        cleanup_cache_manager
        cleanup_feedback_loop
        cleanup_stream_processor
        cleanup_adaptive_tuner
    fi

    # 释放文件锁
    release_lock
}

# 错误处理
trap 'release_lock' EXIT INT TERM QUIT

# 执行主函数
main "$@"
