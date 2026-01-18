#!/bin/bash
# ==============================================================================
# Z-Panel Pro V9.0 - 轻量级 Linux 内存优化工具
# ==============================================================================
# @description    ZRAM、Swap、内核参数优化管理工具 V9.0 轻量版
# @version       9.0.0-Lightweight
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
source "${LIB_DIR}/core.sh"           # 核心配置和常量
source "${LIB_DIR}/error_handler.sh"  # 错误处理和日志
source "${LIB_DIR}/utils.sh"          # 工具函数
source "${LIB_DIR}/lock.sh"           # 文件锁
source "${LIB_DIR}/system.sh"         # 系统检测
source "${LIB_DIR}/data_collector.sh" # 数据采集
source "${LIB_DIR}/ui.sh"             # UI渲染
source "${LIB_DIR}/strategy.sh"       # 策略管理
source "${LIB_DIR}/zram.sh"           # ZRAM管理
source "${LIB_DIR}/swap.sh"           # Swap管理
source "${LIB_DIR}/kernel.sh"         # 内核参数
source "${LIB_DIR}/monitor.sh"        # 监控面板
source "${LIB_DIR}/menu.sh"           # 菜单系统
source "${LIB_DIR}/performance_monitor.sh"  # 性能监控
source "${LIB_DIR}/audit_log.sh"      # 审计日志

# ==============================================================================
# 服务管理函数
# ==============================================================================

# ==============================================================================
# 检查服务是否已安装
# @return: 0已安装，1未安装
# ==============================================================================
is_service_installed() {
    [[ -f "${SYSTEMD_SERVICE_FILE}" ]] && systemctl is-enabled --quiet "${SERVICE_NAME}" 2>/dev/null
}

# ==============================================================================
# 启用开机自启
# @return: 0成功，1失败
# ==============================================================================
enable_autostart() {
    log_info "配置开机自启..."

    # 验证安装目录存在
    if [[ ! -d "${INSTALL_DIR}" ]]; then
        log_error "安装目录不存在: ${INSTALL_DIR}"
        return 1
    fi

    # 验证LIB_DIR存在
    if [[ ! -d "${LIB_DIR}" ]]; then
        log_error "库目录不存在: ${LIB_DIR}"
        return 1
    fi

    # 创建启动脚本
    local autostart_script="${INSTALL_DIR}/autostart.sh"
    cat > "${autostart_script}" << EOF
#!/bin/bash
# Z-Panel Pro 自动启动脚本
set -euo pipefail

# 加载核心模块
source "${LIB_DIR}/core.sh"
source "${LIB_DIR}/error_handler.sh"
source "${LIB_DIR}/system.sh"
source "${LIB_DIR}/data_collector.sh"
source "${LIB_DIR}/strategy.sh"
source "${LIB_DIR}/zram.sh"
source "${LIB_DIR}/swap.sh"
source "${LIB_DIR}/kernel.sh"

# 初始化日志
mkdir -p "${LOG_DIR}"
init_logging "\${LOG_FILE}"
set_log_level "INFO"

# 检测系统
detect_system

# 加载配置
load_strategy_config

# 配置ZRAM、Swap和内核参数
if configure_zram; then
    log_info "ZRAM自动配置完成"
fi

if configure_physical_swap; then
    log_info "Swap自动配置完成"
fi

if configure_virtual_memory; then
    log_info "内核参数优化完成"
fi

log_info "Z-Panel Pro 自动启动完成"
EOF

    chmod 700 "${autostart_script}"

    # 创建systemd服务文件
    cat > "${SYSTEMD_SERVICE_FILE}" << EOF
[Unit]
Description=Z-Panel Pro Memory Optimizer
After=network.target

[Service]
Type=oneshot
ExecStart=${autostart_script}
RemainAfterExit=true
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # 重载并启用systemd服务
    if ! systemctl daemon-reload > /dev/null 2>&1; then
        log_error "systemd重载失败"
        return 1
    fi

    if ! systemctl enable "${SERVICE_NAME}" > /dev/null 2>&1; then
        log_error "启用服务失败"
        return 1
    fi

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

# ==============================================================================
# 初始化日志系统
# @return: 0成功，1失败
# ==============================================================================
init_logging_system() {
    # 创建日志目录（忽略错误）
    mkdir -p "${LOG_DIR}" 2>/dev/null || {
        echo "警告: 无法创建日志目录: ${LOG_DIR}" >&2
        # 继续运行，不退出
    }

    # 设置文件权限（忽略错误）
    ensure_file_permissions "${LOG_FILE}" 640 2>/dev/null || true
    ensure_dir_permissions "${LOG_DIR}" 750 2>/dev/null || true

    # 初始化日志（忽略错误）
    init_logging "${LOG_FILE}" 2>/dev/null || {
        echo "警告: 初始化日志失败，继续运行..." >&2
        # 继续运行，不退出
    }

    set_log_level "INFO" 2>/dev/null || true
    return 0
}

# ==============================================================================
# 初始化配置目录
# @return: 0成功，1失败
# ==============================================================================
init_config_dirs() {
    local dirs=(
        "${CONF_DIR}"
        "${LOCK_DIR}"
        "${BACKUP_DIR}"
        "${LOG_DIR}"
    )

    for dir in "${dirs[@]}"; do
        if [[ ! -d "${dir}" ]]; then
            if ! mkdir -p "${dir}" 2>/dev/null; then
                log_error "无法创建目录: ${dir}"
                return 1
            fi
        fi
        ensure_dir_permissions "${dir}" 750 2>/dev/null || true
    done

    return 0
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
    if ! check_kernel_version "${MIN_KERNEL_VERSION}"; then
        handle_error "内核版本过低，需要${MIN_KERNEL_VERSION} 或更高版本" "exit" "check_runtime_env"
    fi

    # 检查必要命令
    check_commands awk grep sed free tr cut head tail sort uniq wc

    log_info "运行环境检查完成"
}

# 加载系统配置
load_system_config() {
    log_info "加载系统配置..."

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

    # 初始化配置目录（忽略错误）
    init_config_dirs || {
        log_warn "配置目录初始化失败，使用默认值..."
    }

    # 初始化日志系统（忽略错误）
    init_logging_system || {
        log_warn "日志系统初始化失败，继续运行..."
    }

    # 初始化审计日志（忽略错误）
    init_audit_log || {
        log_warn "审计日志初始化失败，继续运行..."
    }

    # 检查运行环境（必须成功）
    check_runtime_env || {
        log_error "运行环境检查失败"
        return 1
    }

    # 加载系统配置（忽略错误）
    load_system_config || {
        log_warn "系统配置加载失败，使用默认值..."
    }

    # 设置策略模式
    local current_strategy
    current_strategy=$(get_strategy_mode 2>/dev/null || echo "")
    STRATEGY_MODE="${current_strategy:-${STRATEGY_BALANCE}}"

    # 记录系统启动审计（忽略错误）
    audit_system_start || {
        log_warn "系统启动审计记录失败..."
    }

    log_info "系统初始化完成"
    return 0
}

# ==============================================================================
# 一键优化功能 (世界顶级标准)
# ==============================================================================

# ==============================================================================
# 智能策略选择器
# @return: 策略名称 (conservative/balance/aggressive)
# ==============================================================================
auto_select_strategy() {
    local mem_total="${SYSTEM_INFO[total_memory_mb]}"
    local is_vm="${SYSTEM_INFO[is_virtual]}"
    local is_container="${SYSTEM_INFO[is_container]}"

    # 验证内存信息
    if [[ ! "${mem_total}" =~ ^[0-9]+$ ]]; then
        log_warn "无效的内存信息，使用默认策略"
        mem_total=2048
    fi

    # 验证内存范围 (64MB-1TB)
    if [[ ${mem_total} -lt 64 ]]; then
        log_warn "内存大小过小，已自动调整为64MB"
        mem_total=64
    elif [[ ${mem_total} -gt 1048576 ]]; then
        log_warn "内存大小过大，已自动调整为1TB"
        mem_total=1048576
    fi

    # 容器环境使用保守策略
    if [[ "${is_container}" == "true" ]]; then
        echo "conservative"
        return 0
    fi

    # 虚拟机使用平衡策略
    if [[ "${is_vm}" == "true" ]]; then
        echo "balance"
        return 0
    fi

    # 物理机根据内存大小选择
    if [[ ${mem_total} -lt 1024 ]]; then
        # 小内存机器使用激进策略
        echo "aggressive"
    elif [[ ${mem_total} -lt 4096 ]]; then
        # 中等内存使用平衡策略
        echo "balance"
    else
        # 大内存机器使用保守策略
        echo "conservative"
    fi
}

# 优化前状态快照
capture_optimization_snapshot() {
    local snapshot_file="${BACKUP_DIR}/optimization_snapshot_$(date +%Y%m%d_%H%M%S).json"

    log_info "捕获优化前状态快照..."

    # 采集系统状态
    local mem_info=$(get_memory_info false)
    local swap_info=$(get_swap_info false)
    local zram_info=$(get_zram_usage)
    local swappiness=$(get_swappiness)
    local strategy=$(get_strategy_mode)

    # 保存快照
    cat > "${snapshot_file}" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "memory_info": "${mem_info}",
  "swap_info": "${swap_info}",
  "zram_info": "${zram_info}",
  "swappiness": "${swappiness}",
  "strategy": "${strategy}"
}
EOF

    echo "${snapshot_file}"
}

# ==============================================================================
# 显示优化进度
# @param step: 当前步骤 (>=1)
# @param total: 总步骤数 (>0)
# @param message: 进度消息
# ==============================================================================
show_optimization_progress() {
    # 参数验证
    if [[ ${#} -lt 3 ]]; then
        log_error "show_optimization_progress: 缺少必需参数 (step, total, message)"
        return 1
    fi

    local step="$1"
    local total="$2"
    local message="$3"

    # 验证step和total为正数
    if ! validate_positive_integer "${step}" || ! validate_positive_integer "${total}"; then
        log_error "无效的步骤参数"
        return 1
    fi

    # 边界检查
    if [[ ${step} -lt 1 ]]; then
        step=1
    fi
    if [[ ${total} -lt 1 ]]; then
        total=1
    fi
    if [[ ${step} -gt ${total} ]]; then
        step=${total}
    fi

    # 限制message长度 (最大50字符)
    if [[ ${#message} -gt 50 ]]; then
        message="${message:0:50}"
    fi

    local percent=$((step * 100 / total)) || true
    local filled=$((percent / 2)) || true
    local empty=$((50 - filled)) || true

    printf "\r${COLOR_CYAN}[${COLOR_NC}"
    printf "${COLOR_GREEN}%*s${COLOR_NC}" ${filled} '' | tr ' ' '='
    printf "${COLOR_WHITE}%*s${COLOR_NC}" ${empty} '' | tr ' ' '-'
    printf "${COLOR_CYAN}]${COLOR_NC} ${COLOR_WHITE}%3d%%${COLOR_NC} ${COLOR_YELLOW}%s${COLOR_NC}" "${percent}" "${message}"
}

# 一键优化主函数
one_click_optimize() {
    log_info "开始一键优化..."
    ui_clear

    # 步骤1: 系统检测
    show_optimization_progress 1 6 "检测系统环境..."
    sleep 0.3

    # 确保系统信息已正确加载
    detect_system 2>/dev/null || {
        log_warn "系统检测失败，使用默认值"
        SYSTEM_INFO[total_memory_mb]=1024
        SYSTEM_INFO[cpu_cores]=2
    }

    # 验证系统信息
    if [[ -z "${SYSTEM_INFO[total_memory_mb]:-}" ]] || [[ ! "${SYSTEM_INFO[total_memory_mb]}" =~ ^[0-9]+$ ]]; then
        log_warn "内存信息无效，使用默认值 1024MB"
        SYSTEM_INFO[total_memory_mb]=1024
    fi

    if [[ -z "${SYSTEM_INFO[cpu_cores]:-}" ]] || [[ ! "${SYSTEM_INFO[cpu_cores]}" =~ ^[0-9]+$ ]]; then
        log_warn "CPU核心数无效，使用默认值 2"
        SYSTEM_INFO[cpu_cores]=2
    fi

    log_info "系统信息: 内存 ${SYSTEM_INFO[total_memory_mb]}MB, CPU核心 ${SYSTEM_INFO[cpu_cores]}"

    local optimal_strategy
    optimal_strategy=$(auto_select_strategy)
    log_info "推荐策略: ${optimal_strategy}"

    # 步骤2: 捕获快照
    show_optimization_progress 2 6 "捕获优化前快照..."
    sleep 0.3

    local snapshot_file
    snapshot_file=$(capture_optimization_snapshot)

    # 步骤3: 配置策略
    show_optimization_progress 3 6 "应用优化策略 (${optimal_strategy})..."
    sleep 0.3

    set_strategy_mode "${optimal_strategy}"

    # 读取策略参数
    local strategy_params
    strategy_params=$(calculate_strategy "${optimal_strategy}")

    # 验证返回值不为空
    if [[ -z "${strategy_params}" ]]; then
        log_error "策略参数计算失败，使用默认值"
        zram_ratio=120
        phys_limit=256
        swap_size=512
        swappiness=85
        dirty_ratio=10
        min_free=32768
    else
        read -r zram_ratio phys_limit swap_size swappiness dirty_ratio min_free <<< "${strategy_params}"
    fi

    # 验证参数不为空
    [[ -z "${zram_ratio}" ]] && zram_ratio=120
    [[ -z "${phys_limit}" ]] && phys_limit=256
    [[ -z "${swap_size}" ]] && swap_size=512
    [[ -z "${swappiness}" ]] && swappiness=85
    [[ -z "${dirty_ratio}" ]] && dirty_ratio=10
    [[ -z "${min_free}" ]] && min_free=32768

    # 步骤4: 配置ZRAM
    show_optimization_progress 4 6 "配置ZRAM压缩内存..."
    sleep 0.3

    set_config "zram_enabled" "true"
    set_config "zram_ratio" "${zram_ratio}"
    set_config "compression_algorithm" "lz4"

    if configure_zram; then
        log_info "ZRAM配置成功"
    else
        log_warn "ZRAM配置失败，继续其他优化..."
    fi

    # 步骤5: 配置Swap
    show_optimization_progress 5 6 "配置物理Swap..."
    sleep 0.3

    set_config "swap_enabled" "true"
    set_config "swap_size" "${swap_size}"

    if create_swap_file "${swap_size}"; then
        log_info "Swap配置成功"
    else
        log_warn "Swap配置失败，继续其他优化..."
    fi

    # 步骤6: 配置内核参数
    show_optimization_progress 6 6 "优化内核参数..."
    sleep 0.3

    set_config "swappiness" "${swappiness}"
    set_config "dirty_ratio" "${dirty_ratio}"
    set_config "min_free_kbytes" "${min_free}"

    if configure_virtual_memory; then
        log_info "内核参数优化成功"
    else
        log_warn "内核参数优化失败..."
    fi

    # 保存配置
    save_config "${CONF_DIR}/zpanel.conf" "zpanel"
    save_strategy_config

    # 显示优化结果
    echo ""
    echo ""
    ui_draw_header "优化完成"
    ui_draw_line

    echo -e "${COLOR_GREEN}✓${COLOR_NC} 策略模式: ${COLOR_CYAN}${optimal_strategy}${COLOR_NC}"
    echo -e "${COLOR_GREEN}✓${COLOR_NC} ZRAM配置: ${COLOR_CYAN}${zram_ratio}%${COLOR_NC}"
    echo -e "${COLOR_GREEN}✓${COLOR_NC} Swap大小: ${COLOR_CYAN}${swap_size}MB${COLOR_NC}"
    echo -e "${COLOR_GREEN}✓${COLOR_NC} Swappiness: ${COLOR_CYAN}${swappiness}${COLOR_NC}"
    echo -e "${COLOR_GREEN}✓${COLOR_NC} Dirty Ratio: ${COLOR_CYAN}${dirty_ratio}%${COLOR_NC}"
    echo ""
    echo -e "${COLOR_YELLOW}快照已保存: ${COLOR_NC}${snapshot_file}"

    ui_draw_bottom
    echo ""
    echo -e "${COLOR_YELLOW}[提示] 运行 $0 -m 查看实时监控${COLOR_NC}"
    echo -e "${COLOR_YELLOW}[提示] 运行 $0 -s 查看系统状态${COLOR_NC}"
    echo ""

    ui_pause
}

# ==============================================================================
# 帮助信息函数
# ==============================================================================

# 显示帮助信息
show_help() {
    cat << EOF
${COLOR_CYAN}Z-Panel Pro v${VERSION} - 轻量级 Linux 内存优化工具 (V9.0 轻量版)${COLOR_NC}

${COLOR_WHITE}用法:${COLOR_NC} $0 [选项]

${COLOR_YELLOW}基本选项:${COLOR_NC}
  -h, --help              显示帮助信息
  -v, --version           显示版本信息
  -m, --monitor           显示实时监控面板
  -s, --status            显示系统状态
  -c, --configure         配置向导

${COLOR_YELLOW}优化选项:${COLOR_NC}
  -o, --optimize          ${COLOR_GREEN}一键智能优化 (推荐)${COLOR_NC}
  --strategy <mode>       设置策略模式 (conservative|balance|aggressive)

${COLOR_YELLOW}管理选项:${COLOR_NC}
  -e, --enable            启用开机自启
  -d, --disable           禁用开机自启

${COLOR_YELLOW}高级选项:${COLOR_NC}
  --log-level <level>     设置日志级别 (DEBUG|INFO|WARN|ERROR)

${COLOR_WHITE}示例:${COLOR_NC}
  $0 -o                   ${COLOR_GREEN}一键智能优化 (推荐)${COLOR_NC}
  $0 -m                   显示实时监控面板
  $0 -s                   显示系统状态
  $0 -c                   运行配置向导
  $0 --strategy balance   设置平衡模式

${COLOR_CYAN}官网:${COLOR_NC} https://github.com/Z-Panel-Pro/Z-Panel-Pro
EOF
}

# 显示版本信息
show_version() {
    cat << EOF
Z-Panel Pro v${VERSION} - Lightweight Edition
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
            -o|--optimize)
                action="optimize"
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
            --strategy)
                strategy="$2"
                shift 2
                ;;
            --log-level)
                set_log_level "$2"
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

    # 初始化系统（忽略错误，继续执行）
    init_system || {
        log_warn "系统初始化部分失败，但继续运行..."
    }

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
        optimize)
            one_click_optimize
            ;;
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
        menu)
            main_menu
            ;;
    esac

    # 释放文件锁
    release_lock
}

# 错误处理
trap 'release_lock' EXIT INT TERM QUIT

# 执行主函数
main "$@"
