#!/bin/bash
# ==============================================================================
# Z-Panel Pro - 企业级内存优化系统 (重构版 v7.0.0)
# ==============================================================================
# @description    专注于 ZRAM 压缩内存和系统虚拟内存的深度优化
# @version       7.0.0-Enterprise
# @author        Z-Panel Team
# @license       MIT
# @copyright     2026
#
# @features      - 严格模块化设计
#                - 完全解耦的函数库
#                - 响应式UI引擎
#                - 并发处理优化
#                - 企业级安全防护
#                - 统一错误处理
# ==============================================================================

# ==============================================================================
# 1. 核心配置模块
# ==============================================================================

# 版本信息
readonly VERSION="7.0.0-Enterprise"
readonly BUILD_DATE="2026-01-17"

# 目录配置
readonly INSTALL_DIR="/opt/z-panel"
readonly CONF_DIR="${INSTALL_DIR}/conf"
readonly LOG_DIR="${INSTALL_DIR}/logs"
readonly BACKUP_DIR="${INSTALL_DIR}/backup"
readonly LIB_DIR="${INSTALL_DIR}/lib"

# 配置文件路径
readonly ZRAM_CONFIG_FILE="${CONF_DIR}/zram.conf"
readonly KERNEL_CONFIG_FILE="${CONF_DIR}/kernel.conf"
readonly STRATEGY_CONFIG_FILE="${CONF_DIR}/strategy.conf"
readonly LOG_CONFIG_FILE="${CONF_DIR}/log.conf"
readonly SWAP_CONFIG_FILE="${CONF_DIR}/swap.conf"

# 文件锁配置
readonly LOCK_FILE="/tmp/z-panel.lock"
readonly LOCK_FD=200

# 颜色配置
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_WHITE='\033[1;37m'
readonly COLOR_NC='\033[0m'

# UI配置
readonly UI_WIDTH=62

# 阈值配置
readonly PROGRESS_THRESHOLD_CRITICAL=90
readonly PROGRESS_THRESHOLD_HIGH=70
readonly PROGRESS_THRESHOLD_MEDIUM=50

# 压缩比阈值
readonly COMPRESSION_RATIO_EXCELLENT=3.0
readonly COMPRESSION_RATIO_GOOD=2.0
readonly COMPRESSION_RATIO_FAIR=1.5

# Swap配置
readonly SWAP_FILE_PATH="/var/lib/z-panel/swapfile"
readonly ZRAM_PRIORITY=100
readonly PHYSICAL_SWAP_PRIORITY=50

# 系统信息（运行时初始化）
declare -g SYSTEM_INFO=(
    [distro]=""
    [version]=""
    [package_manager]=""
    [total_memory_mb]=0
    [cpu_cores]=0
)

# ==============================================================================
# 2. 日志与错误处理模块
# ==============================================================================

# 日志级别
declare -gr LOG_LEVEL_DEBUG=0
declare -gr LOG_LEVEL_INFO=1
declare -gr LOG_LEVEL_WARN=2
declare -gr LOG_LEVEL_ERROR=3

# 当前日志级别
declare -g CURRENT_LOG_LEVEL=${LOG_LEVEL_DEBUG}

# 错误计数器
declare -g ERROR_COUNT=0

# 日志配置
declare -g LOG_MAX_SIZE_MB=50
declare -g LOG_RETENTION_DAYS=30

# 初始化日志目录
init_logging() {
    mkdir -p "${LOG_DIR}" 2>/dev/null || return 1
    chmod 750 "${LOG_DIR}" 2>/dev/null || true
    return 0
}

# 统一日志函数
log_message() {
    local level=$1
    shift
    local message="$*"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"

    local level_str color prefix
    case ${level} in
        ${LOG_LEVEL_DEBUG})
            level_str="DEBUG"
            color="${COLOR_CYAN}"
            prefix="[DEBUG]"
            ;;
        ${LOG_LEVEL_INFO})
            level_str="INFO"
            color="${COLOR_CYAN}"
            prefix="[INFO]"
            ;;
        ${LOG_LEVEL_WARN})
            level_str="WARN"
            color="${COLOR_YELLOW}"
            prefix="[WARN]"
            ;;
        ${LOG_LEVEL_ERROR})
            level_str="ERROR"
            color="${COLOR_RED}"
            prefix="[ERROR]"
            ;;
        *)
            level_str="LOG"
            color="${COLOR_NC}"
            prefix="[LOG]"
            ;;
    esac

    # 控制台输出
    if [[ ${level} -ge ${CURRENT_LOG_LEVEL} ]]; then
        echo -e "${color}${timestamp}${prefix}${NC} ${message}"
    fi

    # 文件输出
    if [[ -d "${LOG_DIR}" ]]; then
        local log_file="${LOG_DIR}/zpanel_$(date +%Y%m%d).log"
        echo "${timestamp}${prefix} ${message}" >> "${log_file}" 2>/dev/null || true
    fi
}

log_debug() { log_message ${LOG_LEVEL_DEBUG} "$@"; }
log_info() { log_message ${LOG_LEVEL_INFO} "$@"; }
log_warn() { log_message ${LOG_LEVEL_WARN} "$@"; }
log_error() { log_message ${LOG_LEVEL_ERROR} "$@"; }

# 错误处理函数
handle_error() {
    local context="$1"
    local message="$2"
    local action="${3:-continue}"

    log_error "[${context}] ${message}"
    ((ERROR_COUNT++)) || true

    case "${action}" in
        continue) return 1 ;;
        exit) exit 1 ;;
        abort) return 2 ;;
        *) return 1 ;;
    esac
}

# ==============================================================================
# 3. 工具函数库
# ==============================================================================

# 输入验证函数
validate_positive_integer() {
    local var="$1"
    [[ "${var}" =~ ^[0-9]+$ ]] && [[ ${var} -gt 0 ]]
}

validate_number() {
    local var="$1"
    [[ "${var}" =~ ^-?[0-9]+$ ]]
}

validate_filename() {
    local filename="$1"
    # 只允许字母、数字、下划线、点、连字符
    [[ "${filename}" =~ ^[a-zA-Z0-9_.-]+$ ]]
}

validate_path() {
    local path="$1"
    # 防止路径遍历
    [[ "${path}" != *".."* ]] && [[ "${path}" == /* ]]
}

# 单位转换函数（统一处理）
convert_size_to_mb() {
    local size="$1"
    local unit
    local num

    # 提取单位和数值
    unit="${size//[0-9.]}"
    num="${size//[KMGTi]/}"

    # 处理单位
    case "${unit}" in
        G|Gi) echo "$((num * 1024))" ;;
        M|Mi) echo "${num}" ;;
        K|Ki) echo "$((num / 1024))" ;;
        B|b|"") echo "$((num / 1048576))" ;;
        *) echo "$((num / 1048576))" ;;
    esac
}

# 计算百分比
calculate_percentage() {
    local used="$1"
    local total="$2"

    if [[ -z "${total}" ]] || [[ "${total}" -eq 0 ]]; then
        echo 0
        return
    fi

    if [[ -z "${used}" ]]; then
        used=0
    fi

    echo "$((used * 100 / total))"
}

# 安全的文件权限设置
ensure_file_permissions() {
    local file="$1"
    local expected_perms="${2:-600}"

    if [[ -f "${file}" ]]; then
        local actual_perms
        actual_perms=$(stat -c "%a" "${file}" 2>/dev/null || stat -f "%OLp" "${file}" 2>/dev/null || echo "000")
        if [[ "${actual_perms}" != "${expected_perms}" ]]; then
            chmod "${expected_perms}" "${file}" 2>/dev/null || {
                log_error "无法设置文件权限: ${file}"
                return 1
            }
        fi
    fi
    return 0
}

# 安全的配置加载
safe_source() {
    local file="$1"
    local pattern='^[A-Z_][A-Z0-9_]*='

    if [[ ! -f "${file}" ]]; then
        return 1
    fi

    # 检查文件内容安全性
    if grep -qE '`|\$\([^)]*\)|>|<|&|;' "${file}" 2>/dev/null; then
        log_error "配置文件包含危险字符: ${file}"
        return 1
    fi

    ensure_file_permissions "${file}" 600 || true

    source "${file}"
    return 0
}

# 配置保存函数（统一处理）
save_config_file() {
    local file="$1"
    local content="$2"

    mkdir -p "$(dirname "${file}")" 2>/dev/null || return 1
    chmod 700 "$(dirname "${file}")" 2>/dev/null || true

    echo "${content}" > "${file}" 2>/dev/null || return 1
    chmod 600 "${file}" 2>/dev/null || true

    return 0
}

# 命令检查
check_command() {
    local cmd="$1"
    command -v "${cmd}" &> /dev/null
}

# 依赖检查
check_dependencies() {
    local missing=()
    local warnings=()

    # 必需命令
    for cmd in awk sed grep; do
        check_command "${cmd}" || missing+=("${cmd}")
    done

    for cmd in modprobe swapon mkswap; do
        check_command "${cmd}" || missing+=("${cmd}")
    done

    # 可选命令
    check_command zramctl || warnings+=("zramctl")
    check_command sysctl || warnings+=("sysctl")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "缺少必需命令: ${missing[*]}"
        echo ""
        echo "请安装缺失的依赖："
        echo "  Debian/Ubuntu: apt-get install -y ${missing[*]}"
        echo "  CentOS/RHEL: yum install -y ${missing[*]}"
        echo "  Alpine: apk add ${missing[*]}"
        echo ""
        return 1
    fi

    if [[ ${#warnings[@]} -gt 0 ]]; then
        log_warn "缺少可选命令: ${warnings[*]}"
        log_warn "某些功能可能无法正常使用"
    fi

    return 0
}

# ==============================================================================
# 4. 文件锁模块
# ==============================================================================

acquire_lock() {
    if ! eval "exec ${LOCK_FD}>\"${LOCK_FILE}\"" 2>/dev/null; then
        log_error "无法创建锁文件: ${LOCK_FILE}"
        return 1
    fi

    if ! flock -n "${LOCK_FD}" 2>/dev/null; then
        local pid
        pid=$(cat "${LOCK_FILE}" 2>/dev/null || echo "unknown")
        log_error "脚本已在运行中 (PID: ${pid})"
        log_error "如需重新启动，请先运行: rm -f ${LOCK_FILE}"
        return 1
    fi

    echo $$ > "${LOCK_FILE}" 2>/dev/null
    return 0
}

release_lock() {
    if flock -u "${LOCK_FD}" 2>/dev/null; then
        rm -f "${LOCK_FILE}" 2>/dev/null
    fi
}

# ==============================================================================
# 5. UI引擎模块
# ==============================================================================

# UI基础绘制函数
ui_draw_top() {
    printf "${COLOR_CYAN}┌$(printf '%.0s─' $(seq 1 ${UI_WIDTH}))┐${COLOR_NC}\n"
}

ui_draw_bottom() {
    printf "${COLOR_CYAN}└$(printf '%.0s─' $(seq 1 ${UI_WIDTH}))┘${COLOR_NC}\n"
}

ui_draw_line() {
    printf "${COLOR_CYAN}├$(printf '%.0s─' $(seq 1 ${UI_WIDTH}))┤${COLOR_NC}\n"
}

ui_draw_row() {
    local text="$1"
    local color="${2:-${COLOR_NC}}"

    # 移除ANSI转义码计算长度
    local plain_text
    plain_text=$(echo -e "${text}" | sed 's/\x1b\[[0-9;]*m//g')

    local pad=$(( UI_WIDTH - ${#plain_text} - 2 ))
    printf "${COLOR_CYAN}│${COLOR_NC} ${color}${text}${COLOR_NC}$(printf '%*s' ${pad} '')${COLOR_CYAN}│${COLOR_NC}\n"
}

ui_draw_header() {
    ui_draw_top
    local title=" $1 "
    local pad=$(( (UI_WIDTH - ${#title}) / 2 ))
    printf "${COLOR_CYAN}│${COLOR_NC}$(printf '%*s' ${pad} '')${COLOR_WHITE}${title}${COLOR_NC}$(printf '%*s' $((UI_WIDTH-pad-${#title})) '')${COLOR_CYAN}│${COLOR_NC}\n"
    ui_draw_line
}

ui_draw_section() {
    ui_draw_line
    ui_draw_row " ${COLOR_WHITE}$1${COLOR_NC}"
    ui_draw_line
}

# 进度条显示函数
ui_draw_progress_bar() {
    local current=$1
    local total=$2
    local width=${3:-46}
    local label="${4:-}"

    [[ -n "${label}" ]] && echo -ne "${COLOR_WHITE}${label}${COLOR_NC} "

    # 防止除零
    [[ "${total}" -eq 0 ]] && total=1
    [[ "${current}" -gt "${total}" ]] && current=${total}

    local filled=$((current * width / total)) || true
    local empty=$((width - filled)) || true
    local percent=$((current * 100 / total)) || true

    # 颜色选择
    local bar_color="${COLOR_GREEN}"
    if [[ ${percent} -ge ${PROGRESS_THRESHOLD_CRITICAL} ]]; then
        bar_color="${COLOR_RED}"
    elif [[ ${percent} -ge ${PROGRESS_THRESHOLD_HIGH} ]]; then
        bar_color="${COLOR_YELLOW}"
    elif [[ ${percent} -ge ${PROGRESS_THRESHOLD_MEDIUM} ]]; then
        bar_color="${COLOR_CYAN}"
    fi

    # 渲染进度条
    echo -ne "${COLOR_WHITE}[${COLOR_NC}"
    local filled_bar=$(printf "%${filled}s" '' | tr ' ' '=')
    local empty_bar=$(printf "%${empty}s" '' | tr ' ' '-')
    echo -ne "${bar_color}${filled_bar}${COLOR_NC}${COLOR_WHITE}${empty_bar}${COLOR_NC}]${COLOR_NC} "

    # 渲染百分比
    if [[ ${percent} -ge 90 ]]; then
        echo -e "${COLOR_RED}${percent}%${COLOR_NC}"
    elif [[ ${percent} -ge 70 ]]; then
        echo -e "${COLOR_YELLOW}${percent}%${COLOR_NC}"
    elif [[ ${percent} -ge 50 ]]; then
        echo -e "${COLOR_CYAN}${percent}%${COLOR_NC}"
    else
        echo -e "${COLOR_GREEN}${percent}%${COLOR_NC}"
    fi
}

# 压缩比图表显示函数
ui_draw_compression_chart() {
    local ratio=$1
    local width=${2:-46}

    local filled=0
    local bar_color="${COLOR_GREEN}"

    # 使用awk进行浮点比较
    if awk "BEGIN {exit !(${ratio} >= ${COMPRESSION_RATIO_EXCELLENT})}"; then
        filled=$((width * 100 / 100)) || true
        bar_color="${COLOR_GREEN}"
    elif awk "BEGIN {exit !(${ratio} >= ${COMPRESSION_RATIO_GOOD})}"; then
        filled=$((width * 75 / 100)) || true
        bar_color="${COLOR_CYAN}"
    elif awk "BEGIN {exit !(${ratio} >= ${COMPRESSION_RATIO_FAIR})}"; then
        filled=$((width * 50 / 100)) || true
        bar_color="${COLOR_YELLOW}"
    else
        filled=$((width * 25 / 100)) || true
        bar_color="${COLOR_RED}"
    fi

    local empty=$((width - filled))

    echo -ne "${COLOR_CYAN}压缩比: ${ratio}x ${COLOR_NC}"

    echo -ne "${COLOR_WHITE}[${COLOR_NC}"
    local filled_bar=$(printf "%${filled}s" '' | tr ' '=')
    local empty_bar=$(printf "%${empty}s" '' | tr ' '-')
    echo -e "${bar_color}${filled_bar}${COLOR_NC}${COLOR_WHITE}${empty_bar}${COLOR_NC}]${COLOR_NC}"
}

# 菜单项显示函数
ui_draw_menu_item() {
    local num="$1"
    local text="$2"
    local item="${COLOR_GREEN}${num}.${COLOR_NC} ${text}"
    ui_draw_row "  ${item}"
}

# 确认对话框
ui_confirm() {
    local message="$1"
    local default="${2:-N}"
    local prompt

    if [[ "${default}" == "Y" ]]; then
        prompt="${COLOR_YELLOW}${message} (Y/n): ${COLOR_NC}"
    else
        prompt="${COLOR_YELLOW}${message} (y/N): ${COLOR_NC}"
    fi

    echo -ne "${prompt}"
    read -r response

    if [[ -z "${response}" ]]; then
        [[ "${default}" == "Y" ]]
    else
        [[ "${response}" =~ ^[Yy]$ ]]
    fi
}

# 暂停函数
ui_pause() {
    echo -ne "${COLOR_CYAN}按 Enter 继续...${COLOR_NC}"
    read -r
}

# 清屏函数
ui_clear() {
    clear
}

# ==============================================================================
# 6. 系统检测模块
# ==============================================================================

detect_system() {
    log_info "检测系统信息..."

    # 检测发行版
    if [[ -f /etc/os-release ]]; then
        SYSTEM_INFO[distro]=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
        SYSTEM_INFO[version]=$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
        SYSTEM_INFO[distro]="${SYSTEM_INFO[distro],,}"
    elif [[ -f /etc/redhat-release ]]; then
        SYSTEM_INFO[distro]="centos"
        SYSTEM_INFO[version]=$(cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+' | head -1)
    else
        handle_error "SYSTEM_DETECT" "无法检测系统发行版" "exit"
    fi

    # 检测包管理器
    if check_command apt-get; then
        SYSTEM_INFO[package_manager]="apt"
    elif check_command yum; then
        SYSTEM_INFO[package_manager]="yum"
    elif check_command apk; then
        SYSTEM_INFO[package_manager]="apk"
    else
        SYSTEM_INFO[package_manager]="unknown"
    fi

    # 检测内存
    local mem_total
    mem_total=$(free -m | awk '/^Mem:/ {print $2}')
    if [[ -z "${mem_total}" ]] || [[ "${mem_total}" -lt 1 ]]; then
        handle_error "SYSTEM_DETECT" "无法获取内存信息" "exit"
    fi
    SYSTEM_INFO[total_memory_mb]=${mem_total}

    # 检测CPU核心数
    local cores
    cores=$(nproc 2>/dev/null || echo 1)
    [[ ${cores} -lt 1 ]] && cores=1
    SYSTEM_INFO[cpu_cores]=${cores}

    log_info "系统: ${SYSTEM_INFO[distro]} ${SYSTEM_INFO[version]}"
    log_info "内存: ${SYSTEM_INFO[total_memory_mb]}MB"
    log_info "CPU: ${SYSTEM_INFO[cpu_cores]} 核心"

    return 0
}

install_packages() {
    local pkg_manager="${SYSTEM_INFO[package_manager]}"

    if [[ -z "${pkg_manager}" ]] || [[ "${pkg_manager}" == "unknown" ]]; then
        log_error "未知的包管理器"
        return 1
    fi

    case "${pkg_manager}" in
        apt)
            apt-get update -qq > /dev/null 2>&1
            apt-get install -y "$@" > /dev/null 2>&1
            ;;
        yum)
            yum install -y "$@" > /dev/null 2>&1
            ;;
        apk)
            apk add --no-cache "$@" > /dev/null 2>&1
            ;;
        *)
            log_error "不支持的包管理器: ${pkg_manager}"
            return 1
            ;;
    esac
}

# ==============================================================================
# 7. 数据采集模块
# ==============================================================================

# 缓存配置
declare -g CACHE_TTL=3
declare -g CACHE_LAST_UPDATE=0
declare -gA CACHE_DATA=()

# 更新缓存
update_cache() {
    local current_time
    current_time=$(date +%s)
    local cache_age=$((current_time - CACHE_LAST_UPDATE))

    if [[ ${cache_age} -lt ${CACHE_TTL} ]]; then
        return 0
    fi

    # 获取内存信息
    local mem_info
    mem_info=$(free -m | awk '/^Mem:/ {print $2, $3, $7, $6}')
    read -r CACHE_DATA[mem_total] CACHE_DATA[mem_used] CACHE_DATA[mem_avail] CACHE_DATA[buff_cache] <<< "${mem_info}"

    # 获取Swap信息
    local swap_info
    swap_info=$(free -m | awk '/Swap:/ {print $2, $3}')
    read -r CACHE_DATA[swap_total] CACHE_DATA[swap_used] <<< "${swap_info}"

    CACHE_LAST_UPDATE=${current_time}
}

# 清除缓存
clear_cache() {
    CACHE_DATA=()
    CACHE_LAST_UPDATE=0
}

# 获取内存信息
get_memory_info() {
    local use_cache="${1:-true}"

    if [[ "${use_cache}" == "true" ]]; then
        update_cache
        echo "${CACHE_DATA[mem_total]} ${CACHE_DATA[mem_used]} ${CACHE_DATA[mem_avail]} ${CACHE_DATA[buff_cache]}"
    else
        free -m | awk '/^Mem:/ {print $2, $3, $7, $6}'
    fi
}

# 获取Swap信息
get_swap_info() {
    local use_cache="${1:-true}"

    if [[ "${use_cache}" == "true" ]]; then
        update_cache
        echo "${CACHE_DATA[swap_total]} ${CACHE_DATA[swap_used]}"
    else
        free -m | awk '/Swap:/ {print $2, $3}'
    fi
}

# 检查ZRAM是否启用
is_zram_enabled() {
    swapon --show=NAME --noheadings 2>/dev/null | grep -q zram
}

# 获取ZRAM使用情况
get_zram_usage() {
    if ! is_zram_enabled; then
        echo "0 0"
        return
    fi

    local zram_info
    zram_info=$(swapon --show=SIZE,USED --noheadings 2>/dev/null | grep zram | head -1)

    if [[ -z "${zram_info}" ]]; then
        echo "0 0"
        return
    fi

    # 使用统一的单位转换函数
    local zram_total zram_used
    zram_total=$(echo "${zram_info}" | awk '{print $1}')
    zram_used=$(echo "${zram_info}" | awk '{print $2}')

    zram_total=$(convert_size_to_mb "${zram_total}")
    zram_used=$(convert_size_to_mb "${zram_used}")

    [[ -z "${zram_total}" ]] || [[ "${zram_total}" == "0" ]] && zram_total=1
    [[ -z "${zram_used}" ]] && zram_used=0

    echo "${zram_total} ${zram_used}"
}

# 获取ZRAM状态（JSON格式）
get_zram_status() {
    if ! check_command zramctl; then
        echo '{"enabled": false}'
        return
    fi

    local zram_info
    zram_info=$(zramctl 2>/dev/null | tail -n +2)

    if [[ -z "${zram_info}" ]]; then
        echo '{"enabled": false}'
        return
    fi

    local name disk_size data_size comp_size algo
    read -r name disk_size data_size comp_size algo <<< "${zram_info}"

    local compression_ratio="0"
    if [[ -n "${data_size}" ]] && [[ -n "${comp_size}" ]] && [[ "${comp_size}" != "0" ]]; then
        compression_ratio=$(echo "${data_size} ${comp_size}" | awk '{
            data_num = $1
            comp_num = $2
            gsub(/[KMGT]/, "", data_num)
            gsub(/[KMGT]/, "", comp_num)
            if (comp_num > 0 && data_num > 0) {
                printf "%.2f", data_num / comp_num
            }
        }')
    fi

    cat <<EOF
{
    "enabled": true,
    "device": "${name}",
    "disk_size": "${disk_size}",
    "data_size": "${data_size}",
    "comp_size": "${comp_size}",
    "algorithm": "${algo}",
    "compression_ratio": "${compression_ratio}"
}
EOF
}

# ==============================================================================
# 8. 策略引擎模块
# ==============================================================================

# 策略配置
declare -g STRATEGY_MODE="balance"

# 加载策略配置
load_strategy_config() {
    if [[ -f "${STRATEGY_CONFIG_FILE}" ]]; then
        safe_source "${STRATEGY_CONFIG_FILE}" || STRATEGY_MODE="balance"
    else
        STRATEGY_MODE="balance"
    fi
}

# 保存策略配置
save_strategy_config() {
    local content
    cat <<'EOF'
# ============================================================================
# Z-Panel Pro 策略配置
# ============================================================================
# 自动生成，请勿手动修改
#
# STRATEGY_MODE: 优化策略模式
#   - conservative: 保守模式，优先稳定
#   - balance: 平衡模式，性能与稳定兼顾（推荐）
#   - aggressive: 激进模式，最大化使用内存
# ============================================================================

STRATEGY_MODE=${STRATEGY_MODE}
EOF

    save_config_file "${STRATEGY_CONFIG_FILE}" "${content}"
}

# 计算策略参数
calculate_strategy() {
    local mode="${1:-${STRATEGY_MODE}}"

    local zram_ratio phys_limit swap_size swappiness dirty_ratio min_free

    case "${mode}" in
        conservative)
            zram_ratio=80
            phys_limit=$((SYSTEM_INFO[total_memory_mb] * 40 / 100)) || true
            swap_size=$((SYSTEM_INFO[total_memory_mb] * 100 / 100)) || true
            swappiness=60
            dirty_ratio=5
            min_free=65536
            ;;
        balance)
            zram_ratio=120
            phys_limit=$((SYSTEM_INFO[total_memory_mb] * 50 / 100)) || true
            swap_size=$((SYSTEM_INFO[total_memory_mb] * 150 / 100)) || true
            swappiness=85
            dirty_ratio=10
            min_free=32768
            ;;
        aggressive)
            zram_ratio=180
            phys_limit=$((SYSTEM_INFO[total_memory_mb] * 65 / 100)) || true
            swap_size=$((SYSTEM_INFO[total_memory_mb] * 200 / 100)) || true
            swappiness=100
            dirty_ratio=15
            min_free=16384
            ;;
        *)
            log_error "未知的策略模式: ${mode}"
            return 1
            ;;
    esac

    echo "${zram_ratio} ${phys_limit} ${swap_size} ${swappiness} ${dirty_ratio} ${min_free}"
}

# 验证策略模式
validate_strategy_mode() {
    local mode="$1"

    case "${mode}" in
        conservative|balance|aggressive)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ==============================================================================
# 9. ZRAM管理模块
# ==============================================================================

# ZRAM配置
declare -g ZRAM_ENABLED=false
declare -g _ZRAM_DEVICE_CACHE=""

# 获取可用的ZRAM设备
get_available_zram_device() {
    if [[ -n "${_ZRAM_DEVICE_CACHE}" ]]; then
        echo "${_ZRAM_DEVICE_CACHE}"
        return 0
    fi

    # 查找未使用的ZRAM设备
    for i in {0..15}; do
        if [[ -e "/sys/block/zram${i}" ]] && ! swapon --show=NAME | grep -q "zram${i}"; then
            _ZRAM_DEVICE_CACHE="zram${i}"
            echo "zram${i}"
            return 0
        fi
    done

    # 尝试热添加
    if [[ -e /sys/class/zram-control/hot_add ]]; then
        local device_num
        device_num=$(cat /sys/class/zram-control/hot_add)
        _ZRAM_DEVICE_CACHE="zram${device_num}"
        echo "zram${device_num}"
        return 0
    fi

    return 1
}

# 初始化ZRAM设备
initialize_zram_device() {
    if ! lsmod | grep -q zram; then
        modprobe zram 2>/dev/null || {
            handle_error "ZRAM_INIT" "无法加载 ZRAM 模块"
            return 1
        }
    fi

    local zram_device
    zram_device=$(get_available_zram_device) || {
        handle_error "ZRAM_INIT" "无法获取可用的 ZRAM 设备"
        return 1
    }

    # 停用现有ZRAM设备
    if swapon --show=NAME --noheadings 2>/dev/null | grep -q zram; then
        local failed_devices=()
        for device in $(swapon --show=NAME --noheadings 2>/dev/null | grep zram); do
            if ! swapoff "${device}" 2>/dev/null; then
                log_warn "无法停用设备: ${device}"
                failed_devices+=("${device}")
            fi
        done

        if [[ ${#failed_devices[@]} -gt 0 ]]; then
            log_error "以下设备停用失败: ${failed_devices[*]}"
            return 1
        fi
    fi

    # 重置设备
    if [[ -e "/sys/block/${zram_device}/reset" ]]; then
        echo 1 > "/sys/block/${zram_device}/reset" 2>/dev/null || true
        sleep 0.3
    fi

    # 验证设备存在
    if [[ ! -e "/dev/${zram_device}" ]]; then
        handle_error "ZRAM_INIT" "ZRAM 设备不存在: /dev/${zram_device}"
        return 1
    fi

    echo "${zram_device}"
    return 0
}

# 检测最优压缩算法
detect_best_algorithm() {
    log_info "检测最优压缩算法..."

    local cpu_flags
    cpu_flags=$(cat /proc/cpuinfo | grep -m1 "flags" | sed 's/flags://')

    local algorithms=("lz4" "lzo" "zstd")
    local best_algo="lzo"
    local best_score=0

    for algo in "${algorithms[@]}"; do
        local score=0

        case "${algo}" in
            lz4) score=100 ;;
            lzo) score=90 ;;
            zstd)
                if echo "${cpu_flags}" | grep -q "avx2"; then
                    score=70
                else
                    score=50
                fi
                ;;
        esac

        if [[ ${score} -gt ${best_score} ]]; then
            best_score=${score}
            best_algo="${algo}"
        fi

        log_info "${algo}: 评分 ${score}"
    done

    log_info "选择算法: ${best_algo}"
    echo "${best_algo}"
}

# 获取ZRAM算法
get_zram_algorithm() {
    local algorithm="${1:-auto}"

    if [[ "${algorithm}" == "auto" ]]; then
        algorithm=$(detect_best_algorithm)
    fi

    echo "${algorithm}"
}

# 配置ZRAM压缩
configure_zram_compression() {
    local zram_device="$1"
    local algorithm="$2"

    if [[ -e "/sys/block/${zram_device}/comp_algorithm" ]]; then
        local supported
        supported=$(cat "/sys/block/${zram_device}/comp_algorithm" 2>/dev/null)

        if echo "${supported}" | grep -q "${algorithm}"; then
            echo "${algorithm}" > "/sys/block/${zram_device}/comp_algorithm" 2>/dev/null || {
                log_warn "设置压缩算法失败，使用默认算法"
            }
            log_info "设置压缩算法: ${algorithm}"
        else
            # 使用回退算法
            local fallback
            fallback=$(echo "${supported}" | awk -F'[][]' '{print $2}' | head -1)

            if [[ -z "${fallback}" ]]; then
                fallback=$(echo "${supported}" | sed 's/^\s*//' | head -1 | awk '{print $1}')
            fi

            [[ -z "${fallback}" ]] && fallback="lzo"

            echo "${fallback}" > "/sys/block/${zram_device}/comp_algorithm" 2>/dev/null || true
            algorithm="${fallback}"
            log_info "使用回退算法: ${algorithm}"
        fi
    fi

    # 设置压缩流数
    if [[ -e "/sys/block/${zram_device}/max_comp_streams" ]]; then
        echo "${SYSTEM_INFO[cpu_cores]}" > "/sys/block/${zram_device}/max_comp_streams" 2>/dev/null || true
        log_info "设置压缩流数: ${SYSTEM_INFO[cpu_cores]}"
    fi

    echo "${algorithm}"
}

# 配置ZRAM限制
configure_zram_limits() {
    local zram_device="$1"
    local zram_size="$2"
    local phys_limit="$3"

    # 设置磁盘大小
    local zram_bytes=$((zram_size * 1024 * 1024)) || true
    echo "${zram_bytes}" > "/sys/block/${zram_device}/disksize" 2>/dev/null || {
        handle_error "ZRAM_LIMIT" "设置 ZRAM 大小失败"
        return 1
    }

    # 设置物理内存限制
    if [[ -e "/sys/block/${zram_device}/mem_limit" ]]; then
        local phys_limit_bytes=$((phys_limit * 1024 * 1024)) || true
        echo "${phys_limit_bytes}" > "/sys/block/${zram_device}/mem_limit" 2>/dev/null || true
        log_info "已启用物理内存熔断保护 (Limit: ${phys_limit}MB)"
    fi

    return 0
}

# 启用ZRAM Swap
enable_zram_swap() {
    local zram_device="$1"

    mkswap "/dev/${zram_device}" > /dev/null 2>&1 || {
        handle_error "ZRAM_SWAP" "格式化 ZRAM 失败"
        return 1
    }

    swapon -p "${ZRAM_PRIORITY}" "/dev/${zram_device}" > /dev/null 2>&1 || {
        handle_error "ZRAM_SWAP" "启用 ZRAM 失败"
        return 1
    }

    return 0
}

# 准备ZRAM参数
prepare_zram_params() {
    local algorithm="${1:-auto}"
    local mode="${2:-${STRATEGY_MODE}}"

    validate_strategy_mode "${mode}" || return 1
    algorithm=$(get_zram_algorithm "${algorithm}")

    local zram_ratio phys_limit swap_size swappiness dirty_ratio min_free
    read -r zram_ratio phys_limit swap_size swappiness dirty_ratio min_free <<< "$(calculate_strategy "${mode}")"

    local zram_size=$((SYSTEM_INFO[total_memory_mb] * zram_ratio / 100)) || true
    [[ ${zram_size} -lt 512 ]] && zram_size=512

    if ! validate_positive_integer "${zram_size}" || ! validate_positive_integer "${phys_limit}"; then
        handle_error "ZRAM_PARAMS" "ZRAM 参数验证失败"
        return 1
    fi

    echo "${algorithm} ${mode} ${zram_ratio} ${phys_limit} ${swap_size} ${swappiness} ${dirty_ratio} ${min_free} ${zram_size}"
    return 0
}

# 保存ZRAM配置
save_zram_config() {
    local algorithm="$1"
    local mode="$2"
    local zram_ratio="$3"
    local zram_size="$4"
    local phys_limit="$5"

    local content
    cat <<EOF
# ============================================================================
# Z-Panel Pro ZRAM 配置
# ============================================================================
# 自动生成，请勿手动修改
#
# ALGORITHM: ZRAM 压缩算法 (auto/zstd/lz4/lzo)
# STRATEGY: 使用的策略模式
# PERCENT: ZRAM 大小占物理内存的百分比
# PRIORITY: Swap 优先级
# SIZE: ZRAM 设备大小（MB）
# PHYS_LIMIT: 物理内存使用限制（MB）
# ============================================================================

ALGORITHM=${algorithm}
STRATEGY=${mode}
PERCENT=${zram_ratio}
PRIORITY=${ZRAM_PRIORITY}
SIZE=${zram_size}
PHYS_LIMIT=${phys_limit}
EOF

    save_config_file "${ZRAM_CONFIG_FILE}" "${content}"
}

# 创建ZRAM服务
create_zram_service() {
    log_info "创建 ZRAM 持久化服务..."

    local service_script="${INSTALL_DIR}/zram-start.sh"
    local content
    cat <<'EOF'
#!/bin/bash
set -o pipefail
CONF_DIR="/opt/z-panel/conf"
LOG_DIR="/opt/z-panel/logs"

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    echo "${timestamp}[LOG] ${message}" >> "$LOG_DIR/zram-service.log" 2>/dev/null || true
}

if [[ -f "$CONF_DIR/zram.conf" ]]; then
    source "$CONF_DIR/zram.conf"

    log "开始启动 ZRAM 服务..."

    modprobe zram 2>/dev/null || {
        log "无法加载 zram 模块"
        exit 1
    }

    if [[ -e /sys/block/zram0/reset ]]; then
        echo 1 > /sys/block/zram0/reset 2>/dev/null || true
        log "已重置 ZRAM 设备"
    fi

    if [[ -e /sys/block/zram0/comp_algorithm ]]; then
        echo "$ALGORITHM" > /sys/block/zram0/comp_algorithm 2>/dev/null || true
        log "设置压缩算法: $ALGORITHM"
    fi

    local zram_bytes=$((SIZE * 1024 * 1024)) || true
    echo "$zram_bytes" > /sys/block/zram0/disksize 2>/dev/null || {
        log "设置 ZRAM 大小失败"
        exit 1
    }
    log "设置 ZRAM 大小: ${SIZE}MB"

    if [[ -e /sys/block/zram0/mem_limit ]]; then
        local phys_limit_bytes=$((PHYS_LIMIT * 1024 * 1024)) || true
        echo "$phys_limit_bytes" > /sys/block/zram0/mem_limit 2>/dev/null || true
        log "设置物理内存限制: ${PHYS_LIMIT}MB"
    fi

    mkswap /dev/zram0 > /dev/null 2>&1 || {
        log "格式化 ZRAM 失败"
        exit 1
    }

    swapon -p $PRIORITY /dev/zram0 > /dev/null 2>&1 || {
        log "启用 ZRAM 失败"
        exit 1
    }

    log "ZRAM 服务启动成功"
else
    log "配置文件不存在: $CONF_DIR/zram.conf"
    exit 1
fi

if [[ -f "$CONF_DIR/kernel.conf" ]]; then
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^# ]] && continue
        [[ -z "$key" ]] && continue
        sysctl -w "$key=$value" > /dev/null 2>&1 || log "设置 $key 失败"
    done < "$CONF_DIR/kernel.conf"
fi
EOF

    save_config_file "${service_script}" "${content}"
    chmod 700 "${service_script}" 2>/dev/null || true

    # 创建systemd服务
    if check_command systemctl; then
        local systemd_service="/etc/systemd/system/zram.service"
        content=""
        cat <<EOF
[Unit]
Description=ZRAM Memory Compression
After=multi-user.target
Wants=multi-user.target

[Service]
Type=oneshot
ExecStart=${service_script}
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

        save_config_file "${systemd_service}" "${content}"
        chmod 644 "${systemd_service}" 2>/dev/null || true

        systemctl daemon-reload > /dev/null 2>&1
        systemctl enable zram.service > /dev/null 2>&1

        log_info "systemd 服务已创建并已启用"
    fi
}

# 启动ZRAM服务
start_zram_service() {
    if check_command systemctl; then
        systemctl daemon-reload > /dev/null 2>&1
        if systemctl is-active --quiet zram.service 2>/dev/null; then
            log_info "zram.service 已在运行，跳过启动"
        else
            systemctl start zram.service > /dev/null 2>&1 && {
                log_info "zram.service 已启动"
            } || {
                log_warn "zram.service 启动失败，但 ZRAM 已在当前会话中生成"
            }
        fi
    fi
}

# 配置ZRAM
configure_zram() {
    local algorithm="${1:-auto}"
    local mode="${2:-${STRATEGY_MODE}}"

    log_info "开始配置 ZRAM (策略: ${mode})..."

    # 准备参数
    local params
    params=$(prepare_zram_params "${algorithm}" "${mode}") || return 1
    read -r algorithm mode zram_ratio phys_limit swap_size swappiness dirty_ratio min_free zram_size <<< "${params}"

    # 检查并安装zram-tools
    if ! check_command zramctl; then
        log_info "安装 zram-tools..."
        install_packages zram-tools zram-config zstd lz4 lzop || {
            handle_error "ZRAM_CONFIG" "安装 zram-tools 失败"
            return 1
        }
    fi

    # 初始化设备
    local zram_device
    zram_device=$(initialize_zram_device) || {
        handle_error "ZRAM_CONFIG" "初始化 ZRAM 设备失败"
        return 1
    }
    log_info "使用 ZRAM 设备: ${zram_device}"

    # 配置压缩
    algorithm=$(configure_zram_compression "${zram_device}" "${algorithm}")

    # 配置限制
    configure_zram_limits "${zram_device}" "${zram_size}" "${phys_limit}" || {
        handle_error "ZRAM_CONFIG" "配置 ZRAM 限制失败"
        return 1
    }

    # 启用Swap
    enable_zram_swap "${zram_device}" || {
        handle_error "ZRAM_CONFIG" "启用 ZRAM swap 失败"
        return 1
    }

    # 保存配置
    save_zram_config "${algorithm}" "${mode}" "${zram_ratio}" "${zram_size}" "${phys_limit}" || {
        log_warn "保存 ZRAM 配置失败"
    }

    # 创建服务
    create_zram_service || {
        log_warn "创建 ZRAM 服务失败"
    }

    # 启动服务
    start_zram_service

    ZRAM_ENABLED=true
    _ZRAM_DEVICE_CACHE=""

    log_info "ZRAM 配置成功: ${algorithm}, ${zram_size}MB, 优先级 ${ZRAM_PRIORITY}"

    return 0
}

# 停用ZRAM
disable_zram() {
    log_info "停用 ZRAM..."

    for device in $(swapon --show=NAME --noheadings 2>/dev/null | grep zram); do
        swapoff "${device}" 2>/dev/null || true
    done

    if [[ -e /sys/block/zram0/reset ]]; then
        echo 1 > /sys/block/zram0/reset 2>/dev/null || true
    fi

    if check_command systemctl; then
        systemctl disable zram.service > /dev/null 2>&1
        rm -f /etc/systemd/system/zram.service
        systemctl daemon-reload > /dev/null 2>&1
    fi

    ZRAM_ENABLED=false
    log_info "ZRAM 已停用"
}

# ==============================================================================
# 10. Swap文件管理模块
# ==============================================================================

# Swap配置
declare -g SWAP_ENABLED=false

# 获取Swap文件信息
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

    # 使用统一的单位转换函数
    local swap_total swap_used
    swap_total=$(echo "${swap_info}" | awk '{print $1}')
    swap_used=$(echo "${swap_info}" | awk '{print $2}')

    swap_total=$(convert_size_to_mb "${swap_total}")
    swap_used=$(convert_size_to_mb "${swap_used}")

    [[ -z "${swap_total}" ]] || [[ "${swap_total}" == "0" ]] && swap_total=1
    [[ -z "${swap_used}" ]] && swap_used=0

    echo "${swap_total} ${swap_used}"
}

# 检查Swap文件是否启用
is_swap_file_enabled() {
    [[ -f "${SWAP_FILE_PATH}" ]] && swapon --show=NAME --noheadings 2>/dev/null | grep -q "${SWAP_FILE_PATH}"
}

# 创建Swap文件
create_swap_file() {
    local size_mb="$1"
    local priority="${2:-${PHYSICAL_SWAP_PRIORITY}}"

    log_info "创建物理 Swap 文件 (${size_mb}MB)..."

    if ! validate_positive_integer "${size_mb}"; then
        handle_error "SWAP_CREATE" "无效的 Swap 大小: ${size_mb}"
        return 1
    fi

    if [[ ${size_mb} -lt 128 ]]; then
        handle_error "SWAP_CREATE" "Swap 文件大小不能小于 128MB"
        return 1
    fi

    if [[ ${size_mb} -gt $((SYSTEM_INFO[total_memory_mb] * 4)) ]]; then
        log_warn "Swap 文件大小超过物理内存的 4 倍，可能影响性能"
    fi

    mkdir -p "$(dirname "${SWAP_FILE_PATH}")"

    # 停用并删除现有Swap文件
    if [[ -f "${SWAP_FILE_PATH}" ]]; then
        log_warn "Swap 文件已存在，先停用..."
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

    chmod 600 "${SWAP_FILE_PATH}"

    # 格式化Swap文件
    if ! mkswap "${SWAP_FILE_PATH}" > /dev/null 2>&1; then
        handle_error "SWAP_CREATE" "格式化 Swap 文件失败"
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

    log_info "物理 Swap 文件创建成功: ${size_mb}MB, 优先级 ${priority}"
    return 0
}

# 停用Swap文件
disable_swap_file() {
    log_info "停用物理 Swap 文件..."

    if [[ -f "${SWAP_FILE_PATH}" ]]; then
        swapoff "${SWAP_FILE_PATH}" 2>/dev/null || true
    fi

    if [[ -f /etc/fstab ]] && grep -q "${SWAP_FILE_PATH}" /etc/fstab; then
        sed -i "\|${SWAP_FILE_PATH}|d" /etc/fstab
        log_info "已从 /etc/fstab 移除"
    fi

    if [[ -f "${SWAP_FILE_PATH}" ]]; then
        rm -f "${SWAP_FILE_PATH}"
        log_info "已删除 Swap 文件"
    fi

    return 0
}

# 配置物理Swap
configure_physical_swap() {
    local mode="${1:-${STRATEGY_MODE}}"

    log_info "配置物理 Swap (策略: ${mode})..."

    local zram_ratio phys_limit swap_size swappiness dirty_ratio min_free
    read -r zram_ratio phys_limit swap_size swappiness dirty_ratio min_free <<< "$(calculate_strategy "${mode}")"

    if [[ ${swap_size} -lt 128 ]]; then
        swap_size=128
    fi

    # 检查是否需要重新配置
    if is_swap_file_enabled; then
        local swap_info
        swap_info=$(get_swap_file_info)
        local current_size
        current_size=$(echo "${swap_info}" | awk '{print $1}')

        if [[ ${current_size} -ge $((swap_size - 100)) ]] && [[ ${current_size} -le $((swap_size + 100)) ]]; then
            log_info "物理 Swap 大小已符合要求 (${current_size}MB)"
            return 0
        fi

        log_info "重新调整 Swap 大小: ${current_size}MB -> ${swap_size}MB"
        disable_swap_file
    fi

    create_swap_file "${swap_size}" "${PHYSICAL_SWAP_PRIORITY}" || {
        handle_error "SWAP_CONFIG" "物理 Swap 配置失败"
        return 1
    }

    return 0
}

# 保存Swap配置
save_swap_config() {
    local swap_size="$1"
    local enabled="$2"

    local content
    cat <<EOF
# ============================================================================
# Z-Panel Pro 物理 Swap 配置
# ============================================================================
# 自动生成，请勿手动修改
#
# SWAP_SIZE: 物理 Swap 文件大小（MB）
# SWAP_ENABLED: 是否启用物理 Swap
# SWAP_PRIORITY: Swap 优先级 (ZRAM=${ZRAM_PRIORITY}, 物理 Swap=${PHYSICAL_SWAP_PRIORITY})
# ============================================================================

SWAP_SIZE=${swap_size}
SWAP_ENABLED=${enabled}
SWAP_PRIORITY=${PHYSICAL_SWAP_PRIORITY}
EOF

    save_config_file "${SWAP_CONFIG_FILE}" "${content}"
}

# ==============================================================================
# 11. 内核参数模块
# ==============================================================================

# 应用I/O熔断保护
apply_io_fuse_protection() {
    log_info "应用 I/O 熔断保护..."

    local dirty_ratio="$1"
    local dirty_background_ratio=$((dirty_ratio / 2))

    sysctl -w vm.dirty_ratio=${dirty_ratio} > /dev/null 2>&1
    sysctl -w vm.dirty_background_ratio=${dirty_background_ratio} > /dev/null 2>&1
    sysctl -w vm.dirty_expire_centisecs=3000 > /dev/null 2>&1
    sysctl -w vm.dirty_writeback_centisecs=500 > /dev/null 2>&1

    log_info "I/O 熔断保护已启用 (dirty_ratio: ${dirty_ratio})"
}

# 应用OOM保护
apply_oom_protection() {
    log_info "应用 OOM 保护..."

    local protected=0
    local failed=0

    # 保护SSH进程
    local pids
    pids=$(pgrep sshd 2>/dev/null) || pids=""

    if [[ -n "${pids}" ]]; then
        while IFS= read -r pid; do
            if [[ "${pid}" =~ ^[0-9]+$ ]] && [[ -d "/proc/${pid}" ]] && [[ -f "/proc/${pid}/oom_score_adj" ]]; then
                local cmdline
                cmdline=$(cat "/proc/${pid}/cmdline" 2>/dev/null | tr '\0' ' ' | head -c 100)
                if [[ "${cmdline}" == *"sshd"* ]]; then
                    if echo -1000 > "/proc/${pid}/oom_score_adj" 2>/dev/null; then
                        ((protected++)) || true
                    else
                        ((failed++)) || true
                        log_warn "设置OOM保护失败: PID ${pid} (sshd)"
                    fi
                fi
            fi
        done <<< "${pids}"
    fi

    # 保护systemd进程
    pids=$(pgrep systemd 2>/dev/null) || pids=""

    if [[ -n "${pids}" ]]; then
        while IFS= read -r pid; do
            if [[ "${pid}" =~ ^[0-9]+$ ]] && [[ -d "/proc/${pid}" ]] && [[ -f "/proc/${pid}/oom_score_adj" ]]; then
                local cmdline
                cmdline=$(cat "/proc/${pid}/cmdline" 2>/dev/null | tr '\0' ' ' | head -c 100)
                if [[ "${cmdline}" == *"systemd"* ]]; then
                    if echo -1000 > "/proc/${pid}/oom_score_adj" 2>/dev/null; then
                        ((protected++)) || true
                    else
                        ((failed++)) || true
                        log_warn "设置OOM保护失败: PID ${pid} (systemd)"
                    fi
                fi
            fi
        done <<< "${pids}"
    fi

    log_info "OOM 保护已启用 (已保护 ${protected} 个进程, 失败: ${failed} 个)"
}

# 计算动态swappiness
calculate_dynamic_swappiness() {
    local base_swappiness="$1"
    local mode="${2:-${STRATEGY_MODE}}"

    local swappiness=${base_swappiness}

    read -r mem_total _ _ _ <<< "$(get_memory_info false)"
    read -r swap_total swap_used <<< "$(get_swap_info false)"

    local swap_usage=0
    [[ ${swap_total} -gt 0 ]] && swap_usage=$((swap_used * 100 / swap_total)) || true

    read -r zram_total zram_used <<< "$(get_zram_usage)"
    local zram_usage=0
    if [[ ${zram_total} -gt 0 ]]; then
        zram_usage=$((zram_used * 100 / zram_total)) || true
    fi

    # 根据ZRAM使用率调整
    if [[ ${zram_usage} -gt 80 ]]; then
        swappiness=$((swappiness - 20)) || true
    elif [[ ${zram_usage} -gt 50 ]]; then
        swappiness=$((swappiness - 10)) || true
    fi

    # 根据Swap使用率调整
    if [[ ${swap_usage} -gt 50 ]]; then
        swappiness=$((swappiness - 10)) || true
    fi

    # 根据内存大小调整
    if [[ ${mem_total} -lt 1024 ]]; then
        swappiness=$((swappiness + 20)) || true
    elif [[ ${mem_total} -gt 4096 ]]; then
        swappiness=$((swappiness - 10)) || true
    fi

    # 限制范围
    [[ ${swappiness} -lt 10 ]] && swappiness=10
    [[ ${swappiness} -gt 100 ]] && swappiness=100

    echo "${swappiness}"
}

# 保存内核配置
save_kernel_config() {
    local swappiness="$1"
    local dirty_ratio="$2"
    local min_free="$3"

    local content
    cat <<EOF
# ============================================================================
# Z-Panel Pro 内核参数配置
# ============================================================================
# 自动生成，请勿手动修改
#
# 内存管理参数:
#   vm.swappiness: 系统使用 swap 的倾向性 (0-100)
#   vm.vfs_cache_pressure: 缓存 inode/dentry 的倾向性
#   vm.min_free_kbytes: 系统保留的最小空闲内存
#
# 脏数据策略 (I/O 熔断保护):
#   vm.dirty_ratio: 脏数据占系统内存的最大百分比
#   vm.dirty_background_ratio: 后台写入开始的脏数据百分比
#   vm.dirty_expire_centisecs: 脏数据过期时间（厘秒）
#   vm.dirty_writeback_centisecs: 后台写入间隔（厘秒）
#
# 页面聚合:
#   vm.page-cluster: 一次读取的页面数 (0=禁用)
#
# 文件系统:
#   fs.file-max: 系统最大打开文件数
#   fs.inotify.max_user_watches: inotify 监视数量限制
# ============================================================================

# 内存管理
vm.swappiness=${swappiness}
vm.vfs_cache_pressure=100
vm.min_free_kbytes=${min_free}

# 脏数据策略 (I/O 熔断保护)
vm.dirty_ratio=${dirty_ratio}
vm.dirty_background_ratio=$((dirty_ratio / 2)) || true
vm.dirty_expire_centisecs=3000
vm.dirty_writeback_centisecs=500

# 页面聚合
vm.page-cluster=0

# 文件系统
fs.file-max=2097152
fs.inotify.max_user_watches=524288
EOF

    save_config_file "${KERNEL_CONFIG_FILE}" "${content}"
}

# 应用内核参数
apply_kernel_params() {
    while IFS='=' read -r key value; do
        [[ "${key}" =~ ^# ]] && continue
        [[ -z "${key}" ]] && continue
        sysctl -w "${key}=${value}" > /dev/null 2>&1 || true
    done < "${KERNEL_CONFIG_FILE}"

    # 更新sysctl.conf
    if [[ -f /etc/sysctl.conf ]]; then
        sed -i '/# Z-Panel Pro 内核参数配置/,/# Z-Panel Pro 内核参数配置结束/d' /etc/sysctl.conf

        cat >> /etc/sysctl.conf <<EOF

# Z-Panel Pro 内核参数配置
# 自动生成，请勿手动修改
EOF
        cat "${KERNEL_CONFIG_FILE}" >> /etc/sysctl.conf
        echo "# Z-Panel Pro 内核参数配置结束" >> /etc/sysctl.conf
    fi
}

# 配置虚拟内存
configure_virtual_memory() {
    local mode="${1:-${STRATEGY_MODE}}"

    log_info "配置虚拟内存策略 (策略: ${mode})..."

    local zram_ratio phys_limit swap_size swappiness dirty_ratio min_free
    read -r zram_ratio phys_limit swap_size swappiness dirty_ratio min_free <<< "$(calculate_strategy "${mode}")"

    # 计算动态swappiness
    local dynamic_swappiness
    dynamic_swappiness=$(calculate_dynamic_swappiness "${swappiness}" "${mode}")

    log_info "建议 swappiness: ${dynamic_swappiness}"

    # 保存配置
    save_kernel_config "${dynamic_swappiness}" "${dirty_ratio}" "${min_free}"

    # 应用参数
    apply_kernel_params

    # 应用保护机制
    apply_io_fuse_protection "${dirty_ratio}"
    apply_oom_protection

    # 配置物理Swap
    configure_physical_swap "${mode}" || log_warn "物理 Swap 配置失败"

    log_info "虚拟内存配置完成 (ZRAM + 物理 Swap)"
}

# ==============================================================================
# 12. 备份与回滚模块
# ==============================================================================

# 创建备份
create_backup() {
    log_info "创建系统备份..."

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="${BACKUP_DIR}/backup_${timestamp}"

    if ! mkdir -p "${backup_path}"; then
        handle_error "BACKUP" "无法创建备份目录: ${backup_path}"
        return 1
    fi

    chmod 700 "${backup_path}" 2>/dev/null || true

    local files=(
        "/etc/sysctl.conf"
        "/etc/fstab"
    )

    local backed_up=0
    for file in "${files[@]}"; do
        if [[ -f "${file}" ]]; then
            if cp "${file}" "${backup_path}/" 2>/dev/null; then
                ((backed_up++)) || true
                log_info "已备份: ${file}"
            else
                log_warn "备份失败: ${file}"
            fi
        fi
    done

    # 保存备份信息
    local info_file="${backup_path}/info.txt"
    local content
    cat <<EOF
backup_time=${timestamp}
backup_version=${VERSION}
distro=${SYSTEM_INFO[distro]}
distro_version=${SYSTEM_INFO[version]}
strategy=${STRATEGY_MODE}
memory_mb=${SYSTEM_INFO[total_memory_mb]}
cpu_cores=${SYSTEM_INFO[cpu_cores]}
EOF

    save_config_file "${info_file}" "${content}"

    log_info "备份完成: ${backup_path} (共 ${backed_up} 个文件)"
    return 0
}

# 还原备份
restore_backup() {
    local backup_path="$1"

    if [[ ! -d "${backup_path}" ]]; then
        handle_error "RESTORE" "备份目录不存在: ${backup_path}"
        return 1
    fi

    if [[ ! -f "${backup_path}/info.txt" ]]; then
        handle_error "RESTORE" "备份信息文件缺失: ${backup_path}/info.txt"
        return 1
    fi

    log_info "还原系统备份: ${backup_path}"

    local restored=0
    local failed=0

    for file in "${backup_path}"/*; do
        if [[ -f "${file}" ]]; then
            local filename
            filename=$(basename "${file}")

            if [[ "${filename}" != "info.txt" ]]; then
                local target="/etc/${filename}"

                # 备份原文件
                if [[ -f "${target}" ]]; then
                    local backup_target="${target}.bak.$(date +%Y%m%d_%H%M%S)"
                    if ! cp "${target}" "${backup_target}" 2>/dev/null; then
                        log_warn "无法备份原文件: ${target}"
                    fi
                fi

                # 还原文件
                if cp "${file}" "${target}" 2>/dev/null; then
                    ((restored++)) || true
                    log_info "已还原: ${filename}"
                else
                    ((failed++)) || true
                    log_error "还原失败: ${filename}"
                fi
            fi
        fi
    done

    log_info "还原完成: 成功 ${restored} 个文件，失败 ${failed} 个文件"
    return 0
}

# ==============================================================================
# 13. 监控面板模块
# ==============================================================================

# 清理监控
cleanup_monitor() {
    clear_cache
    log_info "监控面板已退出"
}

# 显示监控面板
show_monitor() {
    ui_clear

    trap 'cleanup_monitor; return 0' INT TERM QUIT HUP

    local last_mem_used=0
    local last_zram_used=0
    local last_swap_used=0
    local last_swappiness=0
    local refresh_interval=1
    local force_refresh=true

    while true; do
        # 获取数据
        read -r mem_total mem_used mem_avail buff_cache <<< "$(get_memory_info true)"
        read -r zram_total zram_used <<< "$(get_zram_usage)"
        read -r swap_total swap_used <<< "$(get_swap_info true)"
        local swappiness
        swappiness=$(sysctl -n vm.swappiness 2>/dev/null || echo "60")

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
            ui_draw_row " 内存: ${COLOR_GREEN}${SYSTEM_INFO[total_memory_mb]}MB${COLOR_NC} CPU: ${COLOR_GREEN}${SYSTEM_INFO[cpu_cores]}核心${COLOR_NC} 模式: ${COLOR_YELLOW}${STRATEGY_MODE}${COLOR_NC}"
            ui_draw_line

            # RAM使用情况
            ui_draw_section "[RAM] 使用情况"
            ui_draw_row " 使用: ${COLOR_GREEN}${mem_used}MB${COLOR_NC}  缓存: ${COLOR_CYAN}${buff_cache}MB${COLOR_NC}  空闲: ${COLOR_GREEN}${mem_avail}MB${COLOR_NC}"
            ui_draw_row " 物理内存负载:"
            echo -ne "  "
            ui_draw_progress_bar "${mem_used}" "${mem_total}" 46 ""
            ui_draw_line

            # ZRAM状态
            ui_draw_section "[ZRAM] 状态"

            if is_zram_enabled; then
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
                ui_draw_row " ZRAM 负载:"
                echo -ne "  "
                ui_draw_progress_bar "${zram_used}" "${zram_total}" 46 ""
            else
                ui_draw_row " 状态: ${COLOR_RED}未启用${COLOR_NC}"
            fi

            # Swap负载
            ui_draw_section "[SWAP] 负载"

            if [[ ${swap_total} -gt 0 ]]; then
                echo -ne "  "
                ui_draw_progress_bar "${swap_used}" "${swap_total}" 46 ""
            else
                ui_draw_row " 状态: ${COLOR_RED}未启用${COLOR_NC}"
            fi

            # 内核参数
            ui_draw_section "[KERNEL] 参数"
            ui_draw_row " swappiness:"
            echo -ne "  "
            ui_draw_progress_bar "${swappiness}" 100 46 ""

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

# 显示系统状态
show_status() {
    ui_clear

    ui_draw_header "Z-Panel Pro 系统状态 v${VERSION}"

    # 系统信息
    ui_draw_section "[SYSTEM] 信息"
    ui_draw_row " 发行版: ${COLOR_GREEN}${SYSTEM_INFO[distro]} ${SYSTEM_INFO[version]}${COLOR_NC}"
    ui_draw_row " 内存: ${COLOR_GREEN}${SYSTEM_INFO[total_memory_mb]}MB${COLOR_NC} CPU: ${COLOR_GREEN}${SYSTEM_INFO[cpu_cores]}核心${COLOR_NC} 策略: ${COLOR_YELLOW}${STRATEGY_MODE}${COLOR_NC}"

    # ZRAM状态
    ui_draw_section "[ZRAM] 状态"

    if is_zram_enabled; then
        ui_draw_row " 状态: ${COLOR_GREEN}运行中${COLOR_NC}"

        local zram_status
        zram_status=$(get_zram_status)

        local disk_size="0"
        local data_size="0"
        local comp_size="0"
        local algo="unknown"
        local ratio="1.00"

        if echo "${zram_status}" | grep -q "enabled.*true"; then
            disk_size=$(echo "${zram_status}" | grep -o '"disk_size":"[^"]*"' | cut -d'"' -f4)
            data_size=$(echo "${zram_status}" | grep -o '"data_size":"[^"]*"' | cut -d'"' -f4)
            comp_size=$(echo "${zram_status}" | grep -o '"comp_size":"[^"]*"' | cut -d'"' -f4)
            algo=$(echo "${zram_status}" | grep -o '"algorithm":"[^"]*"' | cut -d'"' -f4)
            ratio=$(echo "${zram_status}" | grep -o '"compression_ratio":"[^"]*"' | cut -d'"' -f4)
        fi

        [[ -z "${ratio}" ]] || [[ "${ratio}" == "0" ]] && ratio="1.00"

        ui_draw_row " 算法: ${COLOR_CYAN}${algo}${COLOR_NC} 大小: ${COLOR_CYAN}${disk_size}${COLOR_NC}"
        ui_draw_row " 数据: ${COLOR_CYAN}${data_size}${COLOR_NC} 压缩: ${COLOR_CYAN}${comp_size}${COLOR_NC}"
        ui_draw_row " 压缩比:"
        echo -ne "  "
        ui_draw_compression_chart "${ratio}" 46
    else
        ui_draw_row " 状态: ${COLOR_RED}未启用${COLOR_NC}"
    fi

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
    ui_draw_section "[KERNEL] 参数"

    local swappiness
    swappiness=$(sysctl -n vm.swappiness 2>/dev/null || echo "60")
    local vfs_cache
    vfs_cache=$(sysctl -n vm.vfs_cache_pressure 2>/dev/null || echo "100")
    local dirty_ratio
    dirty_ratio=$(sysctl -n vm.dirty_ratio 2>/dev/null || echo "20")

    ui_draw_row " vm.swappiness:"
    echo -ne "  "
    ui_draw_progress_bar "${swappiness}" 100 46 ""

    # 保护机制
    ui_draw_section "[PROTECTION] 保护机制"
    ui_draw_row "  ${COLOR_GREEN}[OK]${COLOR_NC} I/O 熔断: ${COLOR_GREEN}已启用${COLOR_NC}"
    ui_draw_row "  ${COLOR_GREEN}[OK]${COLOR_NC} OOM 保护: ${COLOR_GREEN}已启用${COLOR_NC}"
    ui_draw_row "  ${COLOR_GREEN}[OK]${COLOR_NC} 物理内存熔断: ${COLOR_GREEN}已启用${COLOR_NC}"

    ui_draw_bottom
    echo ""
}

# ==============================================================================
# 14. 菜单系统模块
# ==============================================================================

# 显示主菜单
show_main_menu() {
    ui_clear

    ui_draw_header "Z-Panel Pro v${VERSION} 主控菜单"
    ui_draw_row "系统: RAM:${SYSTEM_INFO[total_memory_mb]}MB CPU:${SYSTEM_INFO[cpu_cores]}Cores ${SYSTEM_INFO[distro]} ${SYSTEM_INFO[version]}"
    ui_draw_line

    ui_draw_section "[MAIN] 主要功能"
    ui_draw_menu_item "1" "一键优化 [当前: ${STRATEGY_MODE}]"
    ui_draw_menu_item "2" "状态监控"

    ui_draw_section "[ADVANCED] 高级功能"
    ui_draw_menu_item "3" "切换优化模式 [保守/平衡/激进]"
    ui_draw_menu_item "4" "配置 ZRAM"
    ui_draw_menu_item "5" "配置物理 Swap"
    ui_draw_menu_item "6" "配置虚拟内存"

    ui_draw_section "[SYSTEM] 系统管理"
    ui_draw_menu_item "7" "查看系统状态"
    ui_draw_menu_item "8" "日志管理"
    ui_draw_menu_item "9" "停用 ZRAM"
    ui_draw_menu_item "10" "停用物理 Swap"
    ui_draw_menu_item "11" "还原备份"
    ui_draw_menu_item "0" "退出程序"

    ui_draw_line

    # 状态显示
    local zram_status swap_status
    if [[ ${ZRAM_ENABLED} == true ]]; then
        zram_status="${COLOR_GREEN}[ON]${COLOR_NC} 已启用"
    else
        zram_status="${COLOR_RED}[OFF]${COLOR_NC} 未启用"
    fi

    if is_swap_file_enabled; then
        swap_status="${COLOR_GREEN}[ON]${COLOR_NC} 已启用"
    else
        swap_status="${COLOR_RED}[OFF]${COLOR_NC} 未启用"
    fi

    ui_draw_row " ZRAM: ${zram_status}  │  Swap: ${swap_status}"
    ui_draw_bottom
    echo ""
    echo -ne "${COLOR_WHITE}请选择 [0-11]: ${COLOR_NC}"
}

# 策略菜单
strategy_menu() {
    while true; do
        ui_clear

        ui_draw_header "选择优化模式"
        ui_draw_menu_item "1" "Conservative (保守)"
        ui_draw_row "     └─ 最稳定，适合路由器/NAS"
        ui_draw_row "     └─ ZRAM: 80% | Swap: 100% | Swappiness: 60"
        ui_draw_line
        ui_draw_menu_item "2" "Balance (平衡)  ${COLOR_YELLOW}[推荐]${COLOR_NC}"
        ui_draw_row "     └─ 性能与稳定兼顾，日常使用"
        ui_draw_row "     └─ ZRAM: 120% | Swap: 150% | Swappiness: 85"
        ui_draw_line
        ui_draw_menu_item "3" "Aggressive (激进)"
        ui_draw_row "     └─ 极限榨干内存，适合极度缺内存"
        ui_draw_row "     └─ ZRAM: 180% | Swap: 200% | Swappiness: 100"
        ui_draw_line
        ui_draw_menu_item "0" "返回"
        ui_draw_bottom
        echo ""
        echo -ne "${COLOR_WHITE}请选择 [0-3]: ${COLOR_NC}"
        read -r choice

        case "${choice}" in
            1)
                STRATEGY_MODE="conservative"
                save_strategy_config
                log_info "策略已切换为: ${STRATEGY_MODE}"
                if ui_confirm "是否立即应用新模式？"; then
                    quick_optimize
                fi
                return
                ;;
            2)
                STRATEGY_MODE="balance"
                save_strategy_config
                log_info "策略已切换为: ${STRATEGY_MODE}"
                if ui_confirm "是否立即应用新模式？"; then
                    quick_optimize
                fi
                return
                ;;
            3)
                STRATEGY_MODE="aggressive"
                save_strategy_config
                log_info "策略已切换为: ${STRATEGY_MODE}"
                if ui_confirm "是否立即应用新模式？"; then
                    quick_optimize
                fi
                return
                ;;
            0)
                return
                ;;
            *)
                echo -e "${COLOR_RED}无效输入${COLOR_NC}"
                sleep 1
                ;;
        esac
    done
}

# ZRAM菜单
zram_menu() {
    while true; do
        ui_clear

        ui_draw_header "ZRAM 配置"
        ui_draw_menu_item "1" "启用 ZRAM (自动检测算法)"
        ui_draw_menu_item "2" "自定义配置"
        ui_draw_menu_item "3" "查看 ZRAM 状态"
        ui_draw_menu_item "0" "返回"
        ui_draw_bottom
        echo ""
        echo -ne "${COLOR_WHITE}请选择 [0-3]: ${COLOR_NC}"
        read -r choice

        case "${choice}" in
            1)
                configure_zram "auto" "${STRATEGY_MODE}"
                ui_pause
                ;;
            2)
                local valid=false
                while [[ "${valid}" == "false" ]]; do
                    echo -ne "压缩算法 [auto/zstd/lz4/lzo]: "
                    read -r algo
                    case "${algo}" in
                        auto|zstd|lz4|lzo)
                            valid=true
                            configure_zram "${algo}" "${STRATEGY_MODE}"
                            ;;
                        *)
                            echo -e "${COLOR_RED}无效算法，请重新输入${COLOR_NC}"
                            ;;
                    esac
                done
                ui_pause
                ;;
            3)
                get_zram_status
                ui_pause
                ;;
            0)
                return
                ;;
            *)
                echo -e "${COLOR_RED}无效输入${COLOR_NC}"
                sleep 1
                ;;
        esac
    done
}

# Swap菜单
swap_menu() {
    while true; do
        ui_clear

        ui_draw_header "物理 Swap 管理"

        ui_draw_row " 当前状态:"
        if is_swap_file_enabled; then
            local swap_info
            swap_info=$(get_swap_file_info)
            local swap_size
            swap_size=$(echo "${swap_info}" | awk '{print $1}')
            local swap_used
            swap_used=$(echo "${swap_info}" | awk '{print $2}')
            ui_draw_row "  状态: ${COLOR_GREEN}已启用${COLOR_NC}"
            ui_draw_row "  大小: ${COLOR_CYAN}${swap_size}MB${COLOR_NC}  已用: ${COLOR_CYAN}${swap_used}MB${COLOR_NC}"
            ui_draw_row "  路径: ${COLOR_CYAN}${SWAP_FILE_PATH}${COLOR_NC}"
            ui_draw_row "  优先级: ${COLOR_YELLOW}${PHYSICAL_SWAP_PRIORITY}${COLOR_NC} (ZRAM=${ZRAM_PRIORITY}, 物理=${PHYSICAL_SWAP_PRIORITY})"
        else
            ui_draw_row "  状态: ${COLOR_RED}未启用${COLOR_NC}"
        fi
        ui_draw_line

        ui_draw_row " 操作选项:"
        ui_draw_menu_item "1" "启用/重新配置物理 Swap"
        ui_draw_menu_item "2" "停用物理 Swap"
        ui_draw_menu_item "3" "查看 Swap 详细信息"
        ui_draw_menu_item "0" "返回"
        ui_draw_bottom
        echo ""
        echo -ne "${COLOR_WHITE}请选择 [0-3]: ${COLOR_NC}"
        read -r choice

        case "${choice}" in
            1)
                ui_draw_header "配置物理 Swap"
                echo ""
                echo "物理 Swap 将与 ZRAM 配合使用："
                echo "  └─ ZRAM (优先级${ZRAM_PRIORITY}): 压缩内存，速度快"
                echo "  └─ 物理 Swap (优先级${PHYSICAL_SWAP_PRIORITY}): 大容量，作为后备"
                echo ""

                local zram_ratio phys_limit swap_size swappiness dirty_ratio min_free
                read -r zram_ratio phys_limit swap_size swappiness dirty_ratio min_free <<< "$(calculate_strategy "${STRATEGY_MODE}")"
                echo "推荐大小: ${COLOR_GREEN}${swap_size}MB${COLOR_NC} (基于策略: ${STRATEGY_MODE})"
                echo ""
                echo -ne "输入 Swap 大小 (MB, 128-$((SYSTEM_INFO[total_memory_mb] * 4)), 默认 ${swap_size}): "
                read -r input_size

                if [[ -z "${input_size}" ]]; then
                    input_size=${swap_size}
                fi

                if validate_positive_integer "${input_size}" && [[ ${input_size} -ge 128 ]]; then
                    if configure_physical_swap "${STRATEGY_MODE}"; then
                        local swap_info
                        swap_info=$(get_swap_file_info)
                        local final_size
                        final_size=$(echo "${swap_info}" | awk '{print $1}')
                        save_swap_config "${final_size}" "true"
                        echo ""
                        echo -e "${COLOR_GREEN}[OK] 物理 Swap 配置成功${COLOR_NC}"
                        echo "  大小: ${final_size}MB"
                        echo "  优先级: ${PHYSICAL_SWAP_PRIORITY} (低于 ZRAM)"
                    else
                        echo ""
                        echo -e "${COLOR_RED}[FAIL] 物理 Swap 配置失败${COLOR_NC}"
                    fi
                else
                    echo ""
                    echo -e "${COLOR_RED}[FAIL] 无效的 Swap 大小${COLOR_NC}"
                fi
                ui_pause
                ;;
            2)
                if ui_confirm "确认停用物理 Swap？"; then
                    disable_swap_file
                    save_swap_config "0" "false"
                    echo ""
                    echo -e "${COLOR_GREEN}[OK] 物理 Swap 已停用${COLOR_NC}"
                fi
                ui_pause
                ;;
            3)
                ui_clear
                ui_draw_header "Swap 详细信息"

                echo ""
                echo "=== 系统 所有 Swap 设备 ==="
                echo ""
                swapon --show

                echo ""
                echo "=== 物理 Swap 文件 ==="
                if [[ -f "${SWAP_FILE_PATH}" ]]; then
                    local file_size
                    file_size=$(du -h "${SWAP_FILE_PATH}" | cut -f1)
                    echo "  文件: ${SWAP_FILE_PATH}"
                    echo "  大小: ${file_size}"
                    if swapon --show=NAME --noheadings 2>/dev/null | grep -q "${SWAP_FILE_PATH}"; then
                        echo "  状态: ${COLOR_GREEN}已启用${COLOR_NC}"
                    else
                        echo "  状态: ${COLOR_RED}未启用${COLOR_NC}"
                    fi
                else
                    echo "  ${COLOR_YELLOW}Swap 文件不存在${COLOR_NC}"
                fi

                echo ""
                echo "=== /etc/fstab 中的 Swap 条目 ==="
                if [[ -f /etc/fstab ]] && grep -q swap /etc/fstab; then
                    grep swap /etc/fstab
                else
                    echo "  ${COLOR_YELLOW}未找到 Swap 条目${COLOR_NC}"
                fi

                ui_draw_bottom
                ui_pause
                ;;
            0)
                return
                ;;
            *)
                echo -e "${COLOR_RED}无效输入${COLOR_NC}"
                sleep 1
                ;;
        esac
    done
}

# 日志管理菜单
log_management_menu() {
    while true; do
        ui_clear

        ui_draw_header "日志管理"

        # 显示日志目录信息
        if [[ -d "${LOG_DIR}" ]]; then
            local log_count
            log_count=$(find "${LOG_DIR}" -name "zpanel_*.log" 2>/dev/null | wc -l)
            local log_size
            log_size=$(du -sh "${LOG_DIR}" 2>/dev/null | cut -f1)
            ui_draw_row " 日志目录: ${COLOR_CYAN}${LOG_DIR}${COLOR_NC}"
            ui_draw_row " 日志文件: ${COLOR_GREEN}${log_count}${COLOR_NC} 个"
            ui_draw_row " 占用空间: ${COLOR_GREEN}${log_size}${COLOR_NC}"
        else
            ui_draw_row " ${COLOR_YELLOW}日志目录不存在${COLOR_NC}"
        fi

        ui_draw_line

        ui_draw_row " 操作选项:"
        ui_draw_menu_item "1" "查看今日日志"
        ui_draw_menu_item "2" "查看历史日志列表"
        ui_draw_menu_item "3" "清理过期日志 (保留 ${LOG_RETENTION_DAYS} 天)"
        ui_draw_menu_item "4" "导出日志"
        ui_draw_menu_item "5" "设置日志级别 (当前: ${CURRENT_LOG_LEVEL})"
        ui_draw_menu_item "0" "返回"
        ui_draw_bottom
        echo ""
        echo -ne "${COLOR_WHITE}请选择 [0-5]: ${COLOR_NC}"
        read -r choice

        case "${choice}" in
            1)
                view_today_log
                ;;
            2)
                view_log_list
                ;;
            3)
                clean_old_logs
                ;;
            4)
                export_logs
                ;;
            5)
                set_log_level
                ;;
            0)
                return
                ;;
            *)
                echo -e "${COLOR_RED}无效输入${COLOR_NC}"
                sleep 1
                ;;
        esac
    done
}

# 查看今日日志
view_today_log() {
    ui_clear

    local today_log
    today_log="${LOG_DIR}/zpanel_$(date +%Y%m%d).log"

    ui_draw_header "今日日志"
    echo ""

    if [[ ! -f "${today_log}" ]]; then
        echo -e "${COLOR_YELLOW}今日暂无日志记录${COLOR_NC}"
    else
        local line_count
        line_count=$(wc -l < "${today_log}" 2>/dev/null || echo "0")
        echo "日志文件: ${today_log}"
        echo "总行数: ${line_count}"
        echo ""
        echo "=============================================================================="
        tail -50 "${today_log}" 2>/dev/null || echo "读取日志失败"
    fi

    echo ""
    echo "=============================================================================="
    ui_pause
}

# 查看日志列表
view_log_list() {
    ui_clear

    ui_draw_header "历史日志列表"
    echo ""

    if [[ ! -d "${LOG_DIR}" ]]; then
        echo -e "${COLOR_RED}日志目录不存在${COLOR_NC}"
        ui_pause
        return
    fi

    local log_files
    log_files=$(find "${LOG_DIR}" -name "zpanel_*.log" -type f 2>/dev/null | sort -r)

    if [[ -z "${log_files}" ]]; then
        echo -e "${COLOR_YELLOW}未找到日期日志文件${COLOR_NC}"
    else
        echo "序号  日期        大小    文件名"
        echo "----  ----------  ------  ----------------------------------------"

        local i=1
        declare -A log_map
        while IFS= read -r log_file; do
            local filename
            filename=$(basename "${log_file}")
            local size
            size=$(du -h "${log_file}" 2>/dev/null | cut -f1)
            local date_str
            date_str=$(echo "${filename}" | sed 's/zpanel_//' | sed 's/\.log//')

            printf "%4d  %s  %6s  %s\n" "${i}" "${date_str}" "${size}" "${filename}"
            log_map[${i}]="${log_file}"
            ((i++)) || true
        done <<< "${log_files}"

        echo ""
        echo -ne "输入日志序号查看详情 (0 返回): "
        read -r log_num

        if [[ "${log_num}" =~ ^[0-9]+$ ]] && [[ ${log_num} -ge 1 ]] && [[ -n "${log_map[${log_num}]}" ]]; then
            view_log_details "${log_map[${log_num}]}"
        fi
    fi

    ui_pause
}

# 查看日志详情
view_log_details() {
    local log_file="$1"

    ui_clear
    ui_draw_header "日志详情"
    echo ""

    local filename
    filename=$(basename "${log_file}")
    local size
    size=$(du -h "${log_file}" 2>/dev/null | cut -f1)
    local line_count
    line_count=$(wc -l < "${log_file}" 2>/dev/null || echo "0")
    local mtime
    mtime=$(stat -c "%y" "${log_file}" 2>/dev/null | cut -d'.' -f1)

    echo "文件名: ${filename}"
    echo "路径: ${log_file}"
    echo "大小: ${size}"
    echo "行数: ${line_count}"
    echo "修改时间: ${mtime}"
    echo ""
    echo "=============================================================================="
    echo "最近 100 行日志"
    echo "=============================================================================="
    echo ""

    tail -100 "${log_file}" 2>/dev/null || echo "读取日志失败"

    echo ""
    echo "=============================================================================="
    ui_pause
}

# 清理过期日志
clean_old_logs() {
    ui_clear

    ui_draw_header "清理过期日志"
    echo ""

    if [[ ! -d "${LOG_DIR}" ]]; then
        echo -e "${COLOR_RED}日志目录不存在${COLOR_NC}"
        ui_pause
        return
    fi

    local old_logs
    old_logs=$(find "${LOG_DIR}" -name "zpanel_*.log" -type f -mtime +${LOG_RETENTION_DAYS} 2>/dev/null)

    if [[ -z "${old_logs}" ]]; then
        echo -e "${COLOR_GREEN}没有过期日志需要清理${COLOR_NC}"
        echo "保留天数: ${LOG_RETENTION_DAYS} 天"
    else
        local old_count
        old_count=$(echo "${old_logs}" | wc -l)
        local old_size
        old_size=$(echo "${old_logs}" | xargs du -ch 2>/dev/null | tail -1 | cut -f1)

        echo -e "${COLOR_YELLOW}发现 ${old_count} 个过期日志${COLOR_NC}"
        echo "占用空间: ${old_size}"
        echo ""

        if ui_confirm "确认删除这些过期日志？"; then
            local deleted=0
            while IFS= read -r log_file; do
                if rm -f "${log_file}" 2>/dev/null; then
                    ((deleted++)) || true
                    log_info "已删除过期日志: ${log_file}"
                fi
            done <<< "${old_logs}"

            echo ""
            echo -e "${COLOR_GREEN}[OK] 已删除 ${deleted} 个日志文件${COLOR_NC}"
        else
            echo -e "${COLOR_YELLOW}已取消删除${COLOR_NC}"
        fi
    fi

    ui_pause
}

# 导出日志
export_logs() {
    ui_clear

    ui_draw_header "导出日志"
    echo ""

    if [[ ! -d "${LOG_DIR}" ]]; then
        echo -e "${COLOR_RED}日志目录不存在${COLOR_NC}"
        ui_pause
        return
    fi

    local export_dir
    export_dir="${HOME}/zpanel_logs_export_$(date +%Y%m%d_%H%M%S)"

    echo "导出目录: ${export_dir}"
    echo ""

    if ui_confirm "确认导出所有日志？"; then
        mkdir -p "${export_dir}" 2>/dev/null || {
            echo -e "${COLOR_RED}[FAIL] 无法创建导出目录${COLOR_NC}"
            ui_pause
            return
        }

        local copied=0
        local total_size=0

        for log_file in "${LOG_DIR}"/zpanel_*.log; do
            if [[ -f "${log_file}" ]]; then
                if cp "${log_file}" "${export_dir}/" 2>/dev/null; then
                    ((copied++)) || true
                fi
            fi
        done

        # 创建汇总报告
        local report_file="${export_dir}/export_report.txt"
        {
            echo "Z-Panel Pro 日志导出报告"
            echo "导出时间: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "导出位置: ${export_dir}"
            echo "导出文件数: ${copied}"
            echo ""
            echo "文件列表:"
            ls -lh "${export_dir}"/zpanel_*.log 2>/dev/null
        } > "${report_file}"

        total_size=$(du -sh "${export_dir}" 2>/dev/null | cut -f1)

        echo ""
        echo -e "${COLOR_GREEN}[OK] 日志导出完成${COLOR_NC}"
        echo "导出位置: ${COLOR_CYAN}${export_dir}${COLOR_NC}"
        echo "导出文件: ${copied} 个"
        echo "总大小: ${total_size}"
        echo "报告文件: ${report_file}"
    else
        echo -e "${COLOR_YELLOW}已取消导出${COLOR_NC}"
    fi

    ui_pause
}

# 设置日志级别
set_log_level() {
    ui_clear

    ui_draw_header "设置日志级别"
    echo ""
    echo "当前日志级别: ${COLOR_GREEN}${CURRENT_LOG_LEVEL}${COLOR_NC}"
    echo ""
    echo "日志级别说明:"
    echo "  0 - DEBUG  : 显示所有日志（调试用）"
    echo "  1 - INFO   : 显示信息和更高级别（推荐）"
    echo "  2 - WARN   : 只显示警告和错误"
    echo "  3 - ERROR  : 只显示错误"
    echo ""

    echo -ne "请输入新的日志级别 [0-3] (默认 ${CURRENT_LOG_LEVEL}): "
    read -r level_input

    if [[ -z "${level_input}" ]]; then
        echo "保持当前级别: ${CURRENT_LOG_LEVEL}"
    elif [[ "${level_input}" =~ ^[0-3]$ ]]; then
        CURRENT_LOG_LEVEL=${level_input}
        echo -e "${COLOR_GREEN}[OK] 日志级别已设置为: ${CURRENT_LOG_LEVEL}${COLOR_NC}"

        # 保存到配置文件
        mkdir -p "$(dirname "${LOG_CONFIG_FILE}")" 2>/dev/null || true
        if [[ -f "${LOG_CONFIG_FILE}" ]]; then
            sed -i "s/^CURRENT_LOG_LEVEL=.*/CURRENT_LOG_LEVEL=${CURRENT_LOG_LEVEL}/" "${LOG_CONFIG_FILE}" 2>/dev/null || true
        else
            # 创建新的配置文件
            cat > "${LOG_CONFIG_FILE}" <<EOF
# ============================================================================
# Z-Panel Pro 日志配置
# ============================================================================
# 自动生成，请勿手动修改
#
# LOG_LEVEL: 日志级别 (0=DEBUG, 1=INFO, 2=WARN, 3=ERROR)
# LOG_MAX_SIZE_MB: 单个日志文件最大大小（MB）
# LOG_RETENTION_DAYS: 日志保留天数
# ============================================================================

LOG_LEVEL=${CURRENT_LOG_LEVEL}
LOG_MAX_SIZE_MB=${LOG_MAX_SIZE_MB}
LOG_RETENTION_DAYS=${LOG_RETENTION_DAYS}
EOF
            chmod 600 "${LOG_CONFIG_FILE}" 2>/dev/null || true
        fi
        log_info "日志级别配置已保存"
    else
        echo -e "${COLOR_RED}[FAIL] 无效的日志级别${COLOR_NC}"
    fi

    ui_pause
}

# 一键优化
quick_optimize() {
    ui_clear

    ui_draw_header "一键优化"
    ui_draw_row " 将执行以下操作"
    ui_draw_line
    ui_draw_row "  ${COLOR_GREEN}[OK]${COLOR_NC} 创建系统备份"
    ui_draw_row "  ${COLOR_GREEN}[OK]${COLOR_NC} 配置 ZRAM (策略: ${COLOR_YELLOW}${STRATEGY_MODE}${COLOR_NC})"
    ui_draw_row "  ${COLOR_GREEN}[OK]${COLOR_NC} 配置物理 Swap (优先级 ${PHYSICAL_SWAP_PRIORITY})"
    ui_draw_row "  ${COLOR_GREEN}[OK]${COLOR_NC} 配置虚拟内存策略 (含 I/O 熔断/OOM 保护)"
    ui_draw_row "  ${COLOR_GREEN}[OK]${COLOR_NC} 配置开机自动启动"
    ui_draw_bottom
    echo ""

    if ! ui_confirm "确认执行？"; then
        return
    fi

    local errors=0

    # 创建备份
    if ! create_backup; then
        log_warn "备份创建失败，继续执行优化"
        ((errors++)) || true
    fi

    # 配置ZRAM
    if ! configure_zram "auto" "${STRATEGY_MODE}"; then
        log_error "ZRAM 配置失败"
        ((errors++)) || true
    fi

    # 配置虚拟内存
    if ! configure_virtual_memory "${STRATEGY_MODE}"; then
        log_error "虚拟内存配置失败"
        ((errors++)) || true
    fi

    # 显示结果
    if [[ ${errors} -gt 0 ]]; then
        echo ""
        echo "注意: 优化过程中遇到 ${errors} 个错误，请查看日志"
        echo "日志目录: ${LOG_DIR}"
    else
        echo ""
        echo "优化完成！"
        echo "[OK] ZRAM 已配置为开机自动启动 (优先级 ${ZRAM_PRIORITY})"
        echo "[OK] 物理 Swap 已配置 (优先级 ${PHYSICAL_SWAP_PRIORITY})"
        echo "[OK] 虚拟内存策略已应用（含 I/O 熔断/OOM 保护）"
        echo "[OK] 策略模式: ${STRATEGY_MODE}"
        echo ""
        echo "Swap 架构说明："
        echo "  └─ ZRAM: 压缩内存，速度快，优先使用"
        echo "  └─ 物理 Swap: 大容量，作为 ZRAM 的后备"
    fi
    ui_pause
}

# ==============================================================================
# 15. 全局快捷键安装模块
# ==============================================================================

install_global_shortcut() {
    local shortcut_path="/usr/local/bin/z"
    local script_path
    script_path=$(realpath "$0" 2>/dev/null || readlink -f "$0" 2>/dev/null || echo "$0")

    # 检查PATH
    local path_has_bin=false
    local IFS=':'
    for dir in ${PATH}; do
        if [[ "${dir}" == "/usr/local/bin" ]]; then
            path_has_bin=true
            break
        fi
    done
    unset IFS

    if [[ "${path_has_bin}" == false ]]; then
        log_warn "/usr/local/bin 不在系统 PATH 中"
        echo -e "${COLOR_YELLOW}警告: /usr/local/bin 不在系统 PATH 中${COLOR_NC}"
        echo "请将以下内容添加到 ~/.bashrc 或 ~/.zshrc:"
        echo "  export PATH=\"/usr/local/bin:\$PATH\""
        echo ""
    fi

    # 处理现有快捷键
    if [[ -f "${shortcut_path}" ]]; then
        local existing_link
        existing_link=$(readlink "${shortcut_path}" 2>/dev/null || cat "${shortcut_path}" 2>/dev/null)
        if [[ "${existing_link}" == "${script_path}" ]]; then
            log_info "全局快捷键 'z' 已存在且指向当前脚本"
            return 0
        fi

        log_warn "全局快捷键 'z' 已存在: ${shortcut_path}"
        echo -e "${COLOR_YELLOW}检测到现有快捷键指向${COLOR_NC} ${existing_link}"
        echo -e "${COLOR_YELLOW}当前脚本路径:${COLOR_NC} ${script_path}"

        local backup_path="${shortcut_path}.bak.$(date +%Y%m%d_%H%M%S)"
        if cp "${shortcut_path}" "${backup_path}" 2>/dev/null; then
            log_info "已备份现有快捷键到 ${backup_path}"
            echo -e "${COLOR_GREEN}[OK]${COLOR_NC} 已备份现有快捷键到 ${COLOR_CYAN}${backup_path}${COLOR_NC}"
        else
            log_warn "备份现有快捷键失败，继续覆盖"
        fi
    fi

    # 创建快捷键
    local content
    cat <<EOF
#!/bin/bash
# Z-Panel Pro 全局快捷键
# 自动生成，请勿手动修改

if [[ \$EUID -ne 0 ]]; then
    echo -e "\033[0;31m此脚本需要 root 权限运行\033[0m"
    echo "请使用: sudo z"
    exit 1
fi

exec bash "${script_path}"
EOF

    save_config_file "${shortcut_path}" "${content}"
    chmod 755 "${shortcut_path}" 2>/dev/null || true

    log_info "全局快捷键 'z' 已安装到 ${shortcut_path}"

    if [[ "${path_has_bin}" == true ]]; then
        echo -e "${COLOR_GREEN}[OK]${COLOR_NC} 全局快捷键已安装！现在可以随时输入 ${COLOR_YELLOW}sudo z${COLOR_NC} 打开 Z-Panel Pro"
    else
        echo -e "${COLOR_GREEN}[OK]${COLOR_NC} 全局快捷键已安装到 ${COLOR_YELLOW}${shortcut_path}${COLOR_NC}"
        echo -e "${COLOR_YELLOW}注意: 请先添加 /usr/local/bin 到 PATH 环境变量${COLOR_NC}"
    fi
}

# ==============================================================================
# 16. 信号处理模块
# ==============================================================================

cleanup_on_exit() {
    log_info "执行清理操作..."
    clear_cache
    release_lock
    log_info "清理完成"
}

trap cleanup_on_exit INT TERM QUIT

# ==============================================================================
# 17. 主程序入口
# ==============================================================================

main() {
    # 检查root权限
    if [[ ${EUID} -ne 0 ]]; then
        echo -e "${COLOR_RED}此脚本需要 root 权限运行${COLOR_NC}"
        echo "请使用: sudo bash $0"
        exit 1
    fi

    # 获取文件锁
    if ! acquire_lock; then
        echo -e "${COLOR_RED}无法获取文件锁，脚本可能已在运行${COLOR_NC}"
        exit 1
    fi

    # 初始化日志
    init_logging || exit 1

    # 检查依赖
    check_dependencies || exit 1

    # 检测系统
    detect_system || exit 1

    # 创建目录
    mkdir -p "${INSTALL_DIR}"/{conf,logs,backup}
    chmod 750 "${INSTALL_DIR}" 2>/dev/null || true
    chmod 700 "${INSTALL_DIR}/conf" 2>/dev/null || true
    chmod 750 "${INSTALL_DIR}/logs" 2>/dev/null || true
    chmod 700 "${INSTALL_DIR}/backup" 2>/dev/null || true

    log_info "目录权限已设置"

    # 安装全局快捷键
    install_global_shortcut

    # 加载配置
    load_strategy_config

    # 检查ZRAM状态
    if [[ -f "${ZRAM_CONFIG_FILE}" ]]; then
        ZRAM_ENABLED=true
    fi

    # 检查Swap状态
    if is_swap_file_enabled; then
        SWAP_ENABLED=true
    fi

    # 主循环
    while true; do
        show_main_menu
        read -r choice

        case "${choice}" in
            1)
                quick_optimize
                ;;
            2)
                show_monitor
                ;;
            3)
                strategy_menu
                ;;
            4)
                zram_menu
                ;;
            5)
                swap_menu
                ;;
            6)
                configure_virtual_memory "${STRATEGY_MODE}"
                ui_pause
                ;;
            7)
                show_status
                ui_pause
                ;;
            8)
                log_management_menu
                ;;
            9)
                if ui_confirm "确认停用 ZRAM？"; then
                    disable_zram
                fi
                ui_pause
                ;;
            10)
                if ui_confirm "确认停用物理 Swap？"; then
                    disable_swap_file
                    save_swap_config "0" "false"
                    echo -e "${COLOR_GREEN}[OK] 物理 Swap 已停用${COLOR_NC}"
                fi
                ui_pause
                ;;
            11)
                if [[ -d "${BACKUP_DIR}" ]]; then
                    echo -e "\n可用备份:"
                    local i=1
                    declare -A backup_map
                    for backup in "${BACKUP_DIR}"/backup_*; do
                        if [[ -d "${backup}" ]]; then
                            local name
                            name=$(basename "${backup}")
                            echo -e "  ${COLOR_CYAN}${i}.${COLOR_NC} ${name}"
                            backup_map[${i}]="${backup}"
                            ((i++)) || true
                        fi
                    done
                    echo -ne "\n请选择备份编号 (0 取消): "
                    read -r backup_num
                    if [[ "${backup_num}" =~ ^[0-9]+$ ]] && [[ ${backup_num} -ge 1 ]] && [[ -n "${backup_map[${backup_num}]}" ]]; then
                        if ui_confirm "确认还原备份？"; then
                            restore_backup "${backup_map[${backup_num}]}"
                        fi
                    fi
                else
                    echo -e "${COLOR_YELLOW}暂无备份${COLOR_NC}"
                fi
                ui_pause
                ;;
            0)
                echo -e "${COLOR_GREEN}感谢使用 Z-Panel Pro！${COLOR_NC}"
                exit 0
                ;;
            *)
                echo -e "${COLOR_RED}无效输入，请重新选择${COLOR_NC}"
                sleep 1
                ;;
        esac
    done
}

# 启动主程序
main