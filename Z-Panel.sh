#!/bin/bash
set -o pipefail
export LC_ALL=C
shopt -s nullglob

################################################################################
# Z-Panel Pro - 分级内存智能优化系统 (重构版)
#
# @description    专注于 ZRAM 压缩内存和系统虚拟内存的深度优化
# @version       6.0.0-Refactored
# @author        Z-Panel Team
# @license       MIT
# @copyright     2026
#
# @features      - 分级策略（保守/平衡/激进）
#                - ZRAM 智能压缩（zstd/lz4/lzo）
#                - 持久化配置（重启后自动启用）
#                - 智能压缩算法检测
#                - ZRAM 与物理 Swap 智能联动
#                - I/O 熔断保护机制
#                - OOM 保护（SSH 进程）
#                - 物理内存熔断（mem_limit）
#                - 动态调整 vm.swappiness
#                - 内核参数深度优化
#                - 实时监控面板
#                - 日志管理系统
#                - 备份与回滚机制
#
# @usage         sudo bash Z-Panel.sh
# @requirements  - Bash 4.0+
#                - Root privileges
#                - Linux kernel 3.0+
################################################################################

# ============================================================================
# 核心配置模块 (Core)
# ============================================================================

# 版本信息
readonly SCRIPT_VERSION="6.0.0-Refactored"
readonly BUILD_DATE="2026-01-17"
readonly SCRIPT_NAME="Z-Panel Pro 内存优化"

# 文件锁配置
readonly LOCK_FILE="/tmp/z-panel.lock"
readonly LOCK_FD=200

# 目录配置
readonly INSTALL_DIR="/opt/z-panel"
readonly CONF_DIR="$INSTALL_DIR/conf"
readonly LOG_DIR="$INSTALL_DIR/logs"
readonly BACKUP_DIR="$INSTALL_DIR/backup"
readonly LIB_DIR="$INSTALL_DIR/lib"

# 配置文件路径
readonly ZRAM_CONFIG_FILE="$CONF_DIR/zram.conf"
readonly KERNEL_CONFIG_FILE="$CONF_DIR/kernel.conf"
readonly STRATEGY_CONFIG_FILE="$CONF_DIR/strategy.conf"
readonly LOG_CONFIG_FILE="$CONF_DIR/log.conf"

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly MAGENTA='\033[0;35m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m'

# UI配置
readonly UI_WIDTH=62

# 进度条阈值
readonly PROGRESS_THRESHOLD_CRITICAL=90
readonly PROGRESS_THRESHOLD_HIGH=70
readonly PROGRESS_THRESHOLD_MEDIUM=50

# 压缩比阈值
readonly COMPRESSION_RATIO_EXCELLENT=3.0
readonly COMPRESSION_RATIO_GOOD=2.0
readonly COMPRESSION_RATIO_FAIR=1.5

# 核心内核参数列表（用于循环处理）
readonly KERNEL_PARAMS=(
    "vm.swappiness"
    "vm.vfs_cache_pressure"
    "vm.page-cluster"
    "vm.dirty_ratio"
    "vm.dirty_background_ratio"
)

# 全局状态变量
declare -g ZRAM_ENABLED=false
declare -g DYNAMIC_MODE=false
declare -g STRATEGY_MODE="balance"
declare -g USE_NERD_FONT=false

# 图标变量
declare -g ICON_SUCCESS=""
declare -g ICON_ERROR=""
declare -g ICON_WARNING=""
declare -g ICON_INFO=""
declare -g ICON_CPU=""
declare -g ICON_RAM=""
declare -g ICON_DISK=""
declare -g ICON_SWAP=""
declare -g ICON_ZRAM=""
declare -g ICON_GEAR=""
declare -g ICON_SHIELD=""
declare -g ICON_CHART=""
declare -g ICON_TRASH=""
declare -g ICON_ROCKET=""
declare -g ICON_TOOLS=""

# 缓存变量
declare -g CACHE_MEM_TOTAL=0
declare -g CACHE_MEM_USED=0
declare -g CACHE_MEM_AVAIL=0
declare -g CACHE_BUFF_CACHE=0
declare -g CACHE_SWAP_TOTAL=0
declare -g CACHE_SWAP_USED=0
declare -g CACHE_LAST_UPDATE=0
declare -g CACHE_TTL=3
declare -g _ZRAM_ENABLED_CACHE=""
declare -g _ZRAM_DEVICE_CACHE=""

# 系统信息
declare -g CURRENT_DISTRO=""
declare -g CURRENT_VERSION=""
declare -g PACKAGE_MANAGER=""
declare -g TOTAL_MEMORY_MB=0
declare -g CPU_CORES=0

# 日志配置
declare -g LOG_MAX_SIZE_MB=50
declare -g LOG_RETENTION_DAYS=30

# ============================================================================
# 文件锁模块 (Lock)
# ============================================================================

acquire_lock() {
    if ! eval "exec $LOCK_FD>\"$LOCK_FILE\""; then
        echo "[ERROR] 无法创建锁文件: $LOCK_FILE"
        return 1
    fi

    if ! flock -n $LOCK_FD; then
        local pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "unknown")
        echo "[ERROR] 脚本已在运行中 (PID: $pid)"
        echo "[ERROR] 如需重新启动，请先运行: rm -f $LOCK_FILE"
        return 1
    fi

    echo $$ > "$LOCK_FILE"
    return 0
}

release_lock() {
    if flock -u $LOCK_FD 2>/dev/null; then
        rm -f "$LOCK_FILE" 2>/dev/null
    fi
}

# ============================================================================
# 图标检测模块 (Icons)
# ============================================================================

detect_nerd_font() {
    local has_nerd_font=false

    # 检查字体配置文件
    if [[ -f ~/.config/fontconfig/fonts.conf ]] || [[ -f ~/.fonts.conf ]]; then
        local font_file="${HOME}/.config/fontconfig/fonts.conf"
        [[ -f "$font_file" ]] || font_file="${HOME}/.fonts.conf"
        if grep -qi "nerd\|hack\|fira\|jetbrains" "$font_file" 2>/dev/null; then
            has_nerd_font=true
        fi
    fi

    # 检查字体目录
    local font_dirs=(
        "/usr/share/fonts"
        "/usr/local/share/fonts"
        "${HOME}/.local/share/fonts"
        "${HOME}/.fonts"
    )

    for dir in "${font_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            if find "$dir" -iname "*nerd*" 2>/dev/null | grep -q .; then
                has_nerd_font=true
                break
            fi
        fi
    done

    # 检查终端环境
    if [[ -n "${TERM_PROGRAM:-}" ]] && [[ "${TERM_PROGRAM:-}" == "iTerm.app" ]]; then
        has_nerd_font=true
    fi

    if [[ -n "${TERMINAL_EMULATOR:-}" ]]; then
        if echo "${TERMINAL_EMULATOR:-}" | grep -qi "kitty\|alacritty\|wezterm"; then
            has_nerd_font=true
        fi
    fi

    # 检查终端宽度
    if command -v tput &> /dev/null; then
        local cols=$(tput cols 2>/dev/null || echo 80)
        if [[ $cols -gt 80 ]]; then
            has_nerd_font=true
        fi
    fi

    $has_nerd_font && return 0 || return 1
}

init_icons() {
    if detect_nerd_font; then
        USE_NERD_FONT=true
        ICON_SUCCESS="✓"
        ICON_ERROR="✗"
        ICON_WARNING="⚠"
        ICON_INFO="ℹ"
        ICON_CPU="🔲"
        ICON_RAM="🔳"
        ICON_DISK="💾"
        ICON_SWAP="🔄"
        ICON_ZRAM="📦"
        ICON_GEAR="⚙️"
        ICON_SHIELD="🛡️"
        ICON_CHART="📊"
        ICON_TRASH="🗑️"
        ICON_ROCKET="🚀"
        ICON_TOOLS="🛠️"
    else
        USE_NERD_FONT=false
        ICON_SUCCESS="[OK]"
        ICON_ERROR="[!!]"
        ICON_WARNING="[!]"
        ICON_INFO="[i]"
        ICON_CPU="[CPU]"
        ICON_RAM="[RAM]"
        ICON_DISK="[DISK]"
        ICON_SWAP="[SWAP]"
        ICON_ZRAM="[ZRAM]"
        ICON_GEAR="[GEAR]"
        ICON_SHIELD="[SHIELD]"
        ICON_CHART="[CHART]"
        ICON_TRASH="[TRASH]"
        ICON_ROCKET="[ROCKET]"
        ICON_TOOLS="[TOOLS]"
    fi
}

# ============================================================================
# UI引擎模块 (UI Engine)
# ============================================================================

ui_line() {
    printf "${CYAN}├$(printf '%.0s─' $(seq 1 $UI_WIDTH))┤${NC}\n";
}

ui_top() {
    printf "${CYAN}┌$(printf '%.0s─' $(seq 1 $UI_WIDTH))┐${NC}\n";
}

ui_bot() {
    printf "${CYAN}└$(printf '%.0s─' $(seq 1 $UI_WIDTH))┘${NC}\n";
}

ui_row() {
    local text="$1" color="${2:-$NC}"
    local plain_text; plain_text=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g')
    local pad=$(( UI_WIDTH - ${#plain_text} - 2 ))
    printf "${CYAN}│${NC} ${color}${text}${NC}$(printf '%*s' $pad '')${CYAN}│${NC}\n"
}

ui_header() {
    ui_top
    local title=" $1 "
    local pad=$(( (UI_WIDTH - ${#title}) / 2 ))
    printf "${CYAN}│${NC}$(printf '%*s' $pad '')${WHITE}${title}${NC}$(printf '%*s' $((UI_WIDTH-pad-${#title})) '')${CYAN}│${NC}\n"
    ui_line
}

ui_section() {
    ui_line
    ui_row " ${WHITE}$1${NC}" "$WHITE"
    ui_line
}

ui_menu_item() {
    local num="$1"
    local text="$2"
    local item="${GREEN}${num}.${NC} ${text}"
    ui_row "  $item"
}

show_progress_bar() {
    local current=$1
    local total=$2
    local width=${3:-46}
    local label=${4:-""}

    [[ -z "$label" ]] || echo -ne "${WHITE}$label${NC} "

    [[ "$total" -eq 0 ]] && total=1
    [[ "$current" -gt "$total" ]] && current=$total

    local filled=$((current * width / total)) || true
    local empty=$((width - filled)) || true
    local percent=$((current * 100 / total)) || true

    local bar_color="$GREEN"
    if [[ $percent -ge $PROGRESS_THRESHOLD_CRITICAL ]]; then
        bar_color="$RED"
    elif [[ $percent -ge $PROGRESS_THRESHOLD_HIGH ]]; then
        bar_color="$YELLOW"
    elif [[ $percent -ge $PROGRESS_THRESHOLD_MEDIUM ]]; then
        bar_color="$CYAN"
    fi

    echo -ne "${WHITE}[${NC}"
    local filled_bar=$(printf "%${filled}s" '' | tr ' ' '█')
    local empty_bar=$(printf "%${empty}s" '' | tr ' ' '░')
    echo -ne "${bar_color}${filled_bar}${NC}${WHITE}${empty_bar}${NC}]${NC} "

    if [[ $percent -ge 90 ]]; then
        echo -e "${RED}${percent}%${NC}"
    elif [[ $percent -ge 70 ]]; then
        echo -e "${YELLOW}${percent}%${NC}"
    elif [[ $percent -ge 50 ]]; then
        echo -e "${CYAN}${percent}%${NC}"
    else
        echo -e "${GREEN}${percent}%${NC}"
    fi
}

show_compression_chart() {
    local ratio=$1
    local width=${2:-46}

    local filled=0
    local bar_color="$GREEN"

    if (( $(awk "BEGIN {print ($ratio >= $COMPRESSION_RATIO_EXCELLENT)}") )); then
        filled=$((width * 100 / 100)) || true
        bar_color="$GREEN"
    elif (( $(awk "BEGIN {print ($ratio >= $COMPRESSION_RATIO_GOOD)}") )); then
        filled=$((width * 75 / 100)) || true
        bar_color="$CYAN"
    elif (( $(awk "BEGIN {print ($ratio >= $COMPRESSION_RATIO_FAIR)}") )); then
        filled=$((width * 50 / 100)) || true
        bar_color="$YELLOW"
    else
        filled=$((width * 25 / 100)) || true
        bar_color="$RED"
    fi

    local empty=$((width - filled))

    echo -ne "${CYAN}压缩比: ${ratio}x ${NC}"

    echo -ne "${WHITE}[${NC}"
    local filled_bar=$(printf "%${filled}s" '' | tr ' ' '█')
    local empty_bar=$(printf "%${empty}s" '' | tr ' ' '░')
    echo -e "${bar_color}${filled_bar}${NC}${WHITE}${empty_bar}${NC}]${NC}"
}

# ============================================================================
# 日志模块 (Logger)
# ============================================================================

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"

    local color prefix
    case $level in
        info)
            color="$CYAN"
            prefix="[INFO]"
            ;;
        warn)
            color="$YELLOW"
            prefix="[WARN]"
            ;;
        error)
            color="$RED"
            prefix="[ERROR]"
            ;;
        debug)
            color="$PURPLE"
            prefix="[DEBUG]"
            ;;
        *)
            color="$NC"
            prefix="[LOG]"
            ;;
    esac

    echo -e "${color}${timestamp}${prefix}${NC} ${message}"

    if [[ -d "$LOG_DIR" ]]; then
        echo "${timestamp}${prefix} ${message}" >> "$LOG_DIR/zpanel_$(date +%Y%m%d).log"
    fi
}

pause() {
    echo -ne "${CYAN}按 Enter 继续...${NC}"
    read -r
}

confirm() {
    local message="$1"
    local default="${2:-N}"
    local prompt

    if [[ "$default" == "Y" ]]; then
        prompt="${YELLOW}${message} (Y/n): ${NC}"
    else
        prompt="${YELLOW}${message} (y/N): ${NC}"
    fi

    echo -ne "$prompt"
    read -r response

    if [[ -z "$response" ]]; then
        [[ "$default" == "Y" ]]
    else
        [[ "$response" =~ ^[Yy]$ ]]
    fi
}

# ============================================================================
# 工具函数模块 (Utils)
# ============================================================================

calculate_percentage() {
    local used=$1
    local total=$2

    if [[ -z "$total" ]] || [[ "$total" -eq 0 ]]; then
        echo 0
        return
    fi

    if [[ -z "$used" ]]; then
        used=0
    fi

    echo "$((used * 100 / total))"
}

validate_number() {
    local var=$1
    [[ "$var" =~ ^-?[0-9]+$ ]]
}

validate_positive_int() {
    local var=$1
    [[ "$var" =~ ^[0-9]+$ ]] && [[ $var -gt 0 ]]
}

check_command() {
    local cmd=$1
    if ! command -v "$cmd" &> /dev/null; then
        log error "缺少必需命令: $cmd"
        return 1
    fi
    return 0
}

check_dependencies() {
    local missing=()
    local warnings=()

    for cmd in awk sed grep; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    for cmd in modprobe swapon mkswap; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if ! command -v zramctl &> /dev/null; then
        warnings+=("zramctl")
    fi

    if ! command -v sysctl &> /dev/null; then
        warnings+=("sysctl")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log error "缺少必需命令: ${missing[*]}"
        echo ""
        echo "请安装缺失的依赖："
        echo "  Debian/Ubuntu: apt-get install -y ${missing[*]}"
        echo "  CentOS/RHEL: yum install -y ${missing[*]}"
        echo "  Alpine: apk add ${missing[*]}"
        echo ""
        return 1
    fi

    if [[ ${#warnings[@]} -gt 0 ]]; then
        log warn "缺少可选命令: ${warnings[*]}"
        log warn "某些功能可能无法正常使用"
    fi

    return 0
}

safe_source() {
    local file=$1
    local pattern='^[A-Z_][A-Z0-9_]*='

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    if ! grep -qE "^($pattern|#.*$|$)" "$file"; then
        log error "配置文件包含不安全内容: $file"
        return 1
    fi

    if grep -qE '`|\$\([^)]*\)|>|<|&|;' "$file"; then
        log error "配置文件包含危险字符: $file"
        return 1
    fi

    local file_perms=$(stat -c "%a" "$file" 2>/dev/null || stat -f "%OLp" "$file" 2>/dev/null || echo "000")
    if [[ "$file_perms" != "600" ]] && [[ "$file_perms" != "400" ]]; then
        log warn "配置文件权限不安全: $file (当前: $file_perms, 建议: 600)"
        chmod 600 "$file" 2>/dev/null || true
    fi

    source "$file"
    return 0
}

# ============================================================================
# 缓存管理模块 (Cache)
# ============================================================================

update_cache() {
    local current_time=$(date +%s)
    local cache_age=$((current_time - CACHE_LAST_UPDATE))

    if [[ $cache_age -lt $CACHE_TTL ]]; then
        return 0
    fi

    local mem_info=$(free -m | awk '/^Mem:/ {print $2, $3, $7, $6}')
    local swap_info=$(free -m | awk '/Swap:/ {print $2, $3}')

    read -r CACHE_MEM_TOTAL CACHE_MEM_USED CACHE_MEM_AVAIL CACHE_BUFF_CACHE <<< "$mem_info"
    read -r CACHE_SWAP_TOTAL CACHE_SWAP_USED <<< "$swap_info"
    CACHE_LAST_UPDATE=$current_time
}

clear_cache() {
    CACHE_MEM_TOTAL=0
    CACHE_MEM_USED=0
    CACHE_MEM_AVAIL=0
    CACHE_BUFF_CACHE=0
    CACHE_SWAP_TOTAL=0
    CACHE_SWAP_USED=0
    CACHE_LAST_UPDATE=0
}

# ============================================================================
# 数据采集模块 (Data Collector)
# ============================================================================

get_memory_info() {
    local use_cache=${1:-true}

    if [[ "$use_cache" == "true" ]]; then
        update_cache
        echo "$CACHE_MEM_TOTAL $CACHE_MEM_USED $CACHE_MEM_AVAIL $CACHE_BUFF_CACHE"
    else
        free -m | awk '/^Mem:/ {print $2, $3, $7, $6}'
    fi
}

get_swap_info() {
    local use_cache=${1:-true}

    if [[ "$use_cache" == "true" ]]; then
        update_cache
        echo "$CACHE_SWAP_TOTAL $CACHE_SWAP_USED"
    else
        free -m | awk '/Swap:/ {print $2, $3}'
    fi
}

is_zram_enabled() {
    if [[ -z "$_ZRAM_ENABLED_CACHE" ]]; then
        if swapon --show=NAME --noheadings 2>/dev/null | grep -q zram; then
            _ZRAM_ENABLED_CACHE=true
        else
            _ZRAM_ENABLED_CACHE=false
        fi
    fi
    [[ "$_ZRAM_ENABLED_CACHE" == "true" ]]
}

clear_zram_cache() {
    _ZRAM_ENABLED_CACHE=""
    _ZRAM_DEVICE_CACHE=""
}

get_zram_usage() {
    if ! is_zram_enabled; then
        echo "0 0"
        return
    fi

    local zram_info=$(swapon --show=SIZE,USED --noheadings 2>/dev/null | grep zram | head -1)

    if [[ -z "$zram_info" ]]; then
        echo "0 0"
        return
    fi

    local zram_total=$(echo "$zram_info" | awk '{
        size = $1
        unit = substr($1, length($1))
        num = substr($1, 1, length($1)-1)
        if (unit == "G" || unit == "Gi") print num * 1024
        else if (unit == "M" || unit == "Mi") print num
        else if (unit == "K" || unit == "Ki") print num / 1024
        else print num / 1048576
    }')

    local zram_used=$(echo "$zram_info" | awk '{
        size = $2
        unit = substr($2, length($2))
        num = substr($2, 1, length($2)-1)
        if (unit == "G" || unit == "Gi") print num * 1024
        else if (unit == "M" || unit == "Mi") print num
        else if (unit == "K" || unit == "Ki") print num / 1024
        else print num / 1048576
    }')

    [[ -z "$zram_total" || "$zram_total" == "0" ]] && zram_total=1
    [[ -z "$zram_used" ]] && zram_used=0

    echo "$zram_total $zram_used"
}

get_zram_status() {
    if ! command -v zramctl &> /dev/null; then
        echo '{"enabled": false}'
        return
    fi

    local zram_info=$(zramctl 2>/dev/null | tail -n +2)

    if [[ -z "$zram_info" ]]; then
        echo '{"enabled": false}'
        return
    fi

    local name disk_size data_size comp_size algo
    read -r name disk_size data_size comp_size algo <<< "$zram_info"

    local compression_ratio="0"
    if [[ -n "$data_size" ]] && [[ -n "$comp_size" ]] && [[ "$comp_size" != "0" ]]; then
        compression_ratio=$(echo "$data_size $comp_size" | awk '{
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
    "device": "$name",
    "disk_size": "$disk_size",
    "data_size": "$data_size",
    "comp_size": "$comp_size",
    "algorithm": "$algo",
    "compression_ratio": "$compression_ratio"
}
EOF
}

# ============================================================================
# 系统检测模块 (System)
# ============================================================================

detect_system() {
    log info "检测系统信息..."

    if [[ -f /etc/os-release ]]; then
        CURRENT_DISTRO=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
        CURRENT_VERSION=$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
        CURRENT_DISTRO="${CURRENT_DISTRO,,}"
    elif [[ -f /etc/redhat-release ]]; then
        CURRENT_DISTRO="centos"
        CURRENT_VERSION=$(cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+' | head -1)
    else
        log error "无法检测系统发行版"
        exit 1
    fi

    if command -v apt-get &> /dev/null; then
        PACKAGE_MANAGER="apt"
    elif command -v yum &> /dev/null; then
        PACKAGE_MANAGER="yum"
    elif command -v apk &> /dev/null; then
        PACKAGE_MANAGER="apk"
    fi

    TOTAL_MEMORY_MB=$(free -m | awk '/^Mem:/ {print $2}')
    if [[ -z "$TOTAL_MEMORY_MB" || "$TOTAL_MEMORY_MB" -lt 1 ]]; then
        log error "无法获取内存信息"
        exit 1
    fi

    CPU_CORES=$(nproc 2>/dev/null || echo 1)
    [[ $CPU_CORES -lt 1 ]] && CPU_CORES=1

    log info "系统: $CURRENT_DISTRO $CURRENT_VERSION"
    log info "内存: ${TOTAL_MEMORY_MB}MB"
    log info "CPU: ${CPU_CORES} 核心"
}

install_packages() {
    if [[ -z "$PACKAGE_MANAGER" ]]; then
        log error "未知的包管理器"
        return 1
    fi

    case $PACKAGE_MANAGER in
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
            log error "不支持的包管理器: $PACKAGE_MANAGER"
            return 1
            ;;
    esac
}

# ============================================================================
# 策略引擎模块 (Strategy)
# ============================================================================

load_strategy_config() {
    if [[ -f "$STRATEGY_CONFIG_FILE" ]]; then
        safe_source "$STRATEGY_CONFIG_FILE" || STRATEGY_MODE="balance"
    else
        STRATEGY_MODE="balance"
    fi
}

save_strategy_config() {
    mkdir -p "$CONF_DIR"
    chmod 700 "$CONF_DIR" 2>/dev/null || true

    cat > "$STRATEGY_CONFIG_FILE" <<EOF
# ============================================================================
# Z-Panel Pro 策略配置
# ============================================================================
# 自动生成，请勿手动修改
#
# STRATEGY_MODE: 优化策略模式
#   - conservative: 保守模式，优先稳定性
#   - balance: 平衡模式，性能与稳定兼顾（推荐）
#   - aggressive: 激进模式，最大化利用内存
# ============================================================================

STRATEGY_MODE=$STRATEGY_MODE
EOF

    chmod 600 "$STRATEGY_CONFIG_FILE" 2>/dev/null || true
}

calculate_strategy() {
    local mode=$1

    local zram_ratio phys_limit swap_size swappiness dirty_ratio min_free

    case $mode in
        conservative)
            zram_ratio=80
            phys_limit=$((TOTAL_MEMORY_MB * 40 / 100)) || true
            swap_size=$((TOTAL_MEMORY_MB * 100 / 100)) || true
            swappiness=60
            dirty_ratio=5
            min_free=65536
            ;;
        balance)
            zram_ratio=120
            phys_limit=$((TOTAL_MEMORY_MB * 50 / 100)) || true
            swap_size=$((TOTAL_MEMORY_MB * 150 / 100)) || true
            swappiness=85
            dirty_ratio=10
            min_free=32768
            ;;
        aggressive)
            zram_ratio=180
            phys_limit=$((TOTAL_MEMORY_MB * 65 / 100)) || true
            swap_size=$((TOTAL_MEMORY_MB * 200 / 100)) || true
            swappiness=100
            dirty_ratio=15
            min_free=16384
            ;;
        *)
            log error "未知的策略模式: $mode"
            return 1
            ;;
    esac

    echo "$zram_ratio $phys_limit $swap_size $swappiness $dirty_ratio $min_free"
}

validate_zram_mode() {
    local mode=$1

    if [[ "$mode" != "conservative" ]] && [[ "$mode" != "balance" ]] && [[ "$mode" != "aggressive" ]]; then
        log error "无效的策略模式: $mode"
        return 1
    fi
    return 0
}

# ============================================================================
# ZRAM设备管理模块 (ZRAM Device)
# ============================================================================

get_available_zram_device() {
    if [[ -n "$_ZRAM_DEVICE_CACHE" ]]; then
        echo "$_ZRAM_DEVICE_CACHE"
        return 0
    fi

    for i in {0..15}; do
        if [[ -e "/sys/block/zram$i" ]] && ! swapon --show=NAME | grep -q "zram$i"; then
            _ZRAM_DEVICE_CACHE="zram$i"
            echo "zram$i"
            return 0
        fi
    done

    if [[ -e /sys/class/zram-control/hot_add ]]; then
        local device_num=$(cat /sys/class/zram-control/hot_add)
        _ZRAM_DEVICE_CACHE="zram$device_num"
        echo "zram$device_num"
        return 0
    fi

    return 1
}

initialize_zram_device() {
    if ! lsmod | grep -q zram; then
        modprobe zram || {
            log error "无法加载 ZRAM 模块"
            return 1
        }
    fi

    local zram_device
    zram_device=$(get_available_zram_device) || {
        log error "无法获取可用的 ZRAM 设备"
        return 1
    }

    if swapon --show=NAME --noheadings 2>/dev/null | grep -q zram; then
        local failed_devices=()
        for device in $(swapon --show=NAME --noheadings 2>/dev/null | grep zram); do
            if ! swapoff "$device" 2>/dev/null; then
                log error "无法停用设备: $device"
                failed_devices+=("$device")
            fi
        done

        if [[ ${#failed_devices[@]} -gt 0 ]]; then
            log error "以下设备停用失败: ${failed_devices[*]}"
            return 1
        fi
    fi

    if [[ -e "/sys/block/$zram_device/reset" ]]; then
        echo 1 > "/sys/block/$zram_device/reset" 2>/dev/null || true
        sleep 0.3
    fi

    if [[ ! -e "/dev/$zram_device" ]]; then
        log error "ZRAM 设备不存在: /dev/$zram_device"
        return 1
    fi

    echo "$zram_device"
    return 0
}

detect_best_algorithm() {
    log info "检测最优压缩算法..."

    local cpu_flags=$(cat /proc/cpuinfo | grep -m1 "flags" | sed 's/flags://')
    local algorithms=("lz4" "lzo" "zstd")
    local best_algo="lzo"
    local best_score=0

    for algo in "${algorithms[@]}"; do
        local score=0

        case $algo in
            lz4)
                score=100
                ;;
            lzo)
                score=90
                ;;
            zstd)
                if echo "$cpu_flags" | grep -q "avx2"; then
                    score=70
                else
                    score=50
                fi
                ;;
        esac

        if [[ $score -gt $best_score ]]; then
            best_score=$score
            best_algo=$algo
        fi

        log info "$algo: 评分 $score"
    done

    log info "选择算法: $best_algo"
    echo "$best_algo"
}

get_zram_algorithm() {
    local algorithm=${1:-"auto"}

    if [[ "$algorithm" == "auto" ]]; then
        algorithm=$(detect_best_algorithm)
    fi
    echo "$algorithm"
}

configure_zram_compression() {
    local zram_device=$1
    local algorithm=$2

    if [[ -e "/sys/block/$zram_device/comp_algorithm" ]]; then
        local supported=$(cat "/sys/block/$zram_device/comp_algorithm" 2>/dev/null)
        if echo "$supported" | grep -q "$algorithm"; then
            echo "$algorithm" > "/sys/block/$zram_device/comp_algorithm" 2>/dev/null || {
                log warn "设置压缩算法失败，使用默认算法"
            }
            log info "设置压缩算法: $algorithm"
        else
            local fallback=""
            fallback=$(echo "$supported" | awk -F'[][]' '{print $2}' | head -1)

            if [[ -z "$fallback" ]]; then
                fallback=$(echo "$supported" | sed 's/^\s*//' | head -1 | awk '{print $1}')
            fi

            [[ -z "$fallback" ]] && fallback="lzo"

            echo "$fallback" > "/sys/block/$zram_device/comp_algorithm" 2>/dev/null || true
            algorithm="$fallback"
            log info "使用回退算法: $algorithm"
        fi
    fi

    if [[ -e "/sys/block/$zram_device/max_comp_streams" ]]; then
        echo "$CPU_CORES" > "/sys/block/$zram_device/max_comp_streams" 2>/dev/null || true
        log info "设置压缩流数: $CPU_CORES"
    fi

    echo "$algorithm"
}

configure_zram_limits() {
    local zram_device=$1
    local zram_size=$2
    local phys_limit=$3

    local zram_bytes=$((zram_size * 1024 * 1024)) || true
    echo "$zram_bytes" > "/sys/block/$zram_device/disksize" 2>/dev/null || {
        log error "设置 ZRAM 大小失败"
        return 1
    }

    if [[ -e "/sys/block/$zram_device/mem_limit" ]]; then
        local phys_limit_bytes=$((phys_limit * 1024 * 1024)) || true
        echo "$phys_limit_bytes" > "/sys/block/$zram_device/mem_limit" 2>/dev/null || true
        log info "已启用物理内存熔断保护 (Limit: ${phys_limit}MB)"
    fi

    return 0
}

enable_zram_swap() {
    local zram_device=$1

    mkswap "/dev/$zram_device" > /dev/null 2>&1 || {
        log error "格式化 ZRAM 失败"
        return 1
    }

    swapon -p 100 "/dev/$zram_device" > /dev/null 2>&1 || {
        log error "启用 ZRAM 失败"
        return 1
    }

    return 0
}

prepare_zram_params() {
    local algorithm=${1:-"auto"}
    local mode=${2:-"$STRATEGY_MODE"}

    validate_zram_mode "$mode" || return 1
    algorithm=$(get_zram_algorithm "$algorithm")

    local zram_ratio phys_limit swap_size swappiness dirty_ratio min_free
    read -r zram_ratio phys_limit swap_size swappiness dirty_ratio min_free <<< "$(calculate_strategy "$mode")"

    local zram_size=$((TOTAL_MEMORY_MB * zram_ratio / 100)) || true
    [[ $zram_size -lt 512 ]] && zram_size=512

    if ! validate_positive_int "$zram_size" || ! validate_positive_int "$phys_limit"; then
        log error "ZRAM 参数验证失败"
        return 1
    fi

    echo "$algorithm $mode $zram_ratio $phys_limit $swap_size $swappiness $dirty_ratio $min_free $zram_size"
    return 0
}

save_zram_config() {
    local algorithm=$1
    local mode=$2
    local zram_ratio=$3
    local zram_size=$4
    local phys_limit=$5

    mkdir -p "$CONF_DIR"
    chmod 700 "$CONF_DIR" 2>/dev/null || true

    cat > "$ZRAM_CONFIG_FILE" <<EOF
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

ALGORITHM=$algorithm
STRATEGY=$mode
PERCENT=$zram_ratio
PRIORITY=100
SIZE=$zram_size
PHYS_LIMIT=$phys_limit
EOF

    chmod 600 "$ZRAM_CONFIG_FILE" 2>/dev/null || true
    return 0
}

create_zram_service() {
    log info "创建 ZRAM 持久化服务..."

    cat > "$INSTALL_DIR/zram-start.sh" <<'EOF'
#!/bin/bash
set -o pipefail
CONF_DIR="/opt/z-panel/conf"
LOG_DIR="/opt/z-panel/logs"
LIB_DIR="/opt/z-panel/lib"

if [[ -f "$LIB_DIR/common.sh" ]]; then
    source "$LIB_DIR/common.sh"
else
    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_DIR/zram-service.log" 2>/dev/null || true
    }

    safe_source() {
        local file=$1
        local pattern='^[A-Z_][A-Z0-9_]*='
        if [[ ! -f "$file" ]]; then
            return 1
        fi
        if grep -qE '`|\$\([^)]*\)|>|<|&|;' "$file"; then
            log "配置文件包含危险字符: $file"
            return 1
        fi
        source "$file"
        return 0
    }
fi

if [[ -f "$CONF_DIR/zram.conf" ]]; then
    if ! safe_source "$CONF_DIR/zram.conf"; then
        log "配置文件加载失败"
        exit 1
    fi

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

    swapon -p 100 /dev/zram0 > /dev/null 2>&1 || {
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

    chmod 700 "$INSTALL_DIR/zram-start.sh" 2>/dev/null || true

    if command -v systemctl &> /dev/null; then
        cat > /etc/systemd/system/zram.service <<EOF
[Unit]
Description=ZRAM Memory Compression
After=multi-user.target
Wants=multi-user.target

[Service]
Type=oneshot
ExecStart=$INSTALL_DIR/zram-start.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

        chmod 644 /etc/systemd/system/zram.service 2>/dev/null || true

        systemctl daemon-reload > /dev/null 2>&1
        systemctl enable zram.service > /dev/null 2>&1

        log info "systemd 服务已创建并已启用"
    fi
}

start_zram_service() {
    if command -v systemctl &> /dev/null; then
        systemctl daemon-reload > /dev/null 2>&1
        if systemctl is-active --quiet zram.service 2>/dev/null; then
            log info "zram.service 已在运行，跳过启动"
        else
            systemctl start zram.service > /dev/null 2>&1 && {
                log info "zram.service 已启动"
            } || {
                log warn "zram.service 启动失败，但 ZRAM 已在当前会话中生效"
            }
        fi
    fi
}

configure_zram() {
    local algorithm=${1:-"auto"}
    local mode=${2:-"$STRATEGY_MODE"}

    log info "开始配置 ZRAM (策略: $mode)..."

    local params
    params=$(prepare_zram_params "$algorithm" "$mode") || return 1
    read -r algorithm mode zram_ratio phys_limit swap_size swappiness dirty_ratio min_free zram_size <<< "$params"

    if ! command -v zramctl &> /dev/null; then
        log info "安装 zram-tools..."
        install_packages zram-tools zram-config zstd lz4 lzop || {
            log error "安装 zram-tools 失败"
            return 1
        }
    fi

    local zram_device
    zram_device=$(initialize_zram_device) || {
        log error "初始化 ZRAM 设备失败"
        return 1
    }
    log info "使用 ZRAM 设备: $zram_device"

    algorithm=$(configure_zram_compression "$zram_device" "$algorithm")

    configure_zram_limits "$zram_device" "$zram_size" "$phys_limit" || {
        log error "配置 ZRAM 限制失败"
        return 1
    }

    enable_zram_swap "$zram_device" || {
        log error "启用 ZRAM swap 失败"
        return 1
    }

    save_zram_config "$algorithm" "$mode" "$zram_ratio" "$zram_size" "$phys_limit" || {
        log error "保存 ZRAM 配置失败"
        return 1
    }

    create_zram_service || {
        log warn "创建 ZRAM 服务失败"
    }

    start_zram_service

    ZRAM_ENABLED=true
    clear_zram_cache

    log info "ZRAM 配置成功: $algorithm, ${zram_size}MB, 优先级 100"

    return 0
}

disable_zram() {
    log info "停用 ZRAM..."

    for device in $(swapon --show=NAME --noheadings 2>/dev/null | grep zram); do
        swapoff "$device" 2>/dev/null || true
    done

    if [[ -e /sys/block/zram0/reset ]]; then
        echo 1 > /sys/block/zram0/reset 2>/dev/null || true
    fi

    if command -v systemctl &> /dev/null; then
        systemctl disable zram.service > /dev/null 2>&1
        rm -f /etc/systemd/system/zram.service
        systemctl daemon-reload > /dev/null 2>&1
    fi

    ZRAM_ENABLED=false
    log info "ZRAM 已停用"
}

# ============================================================================
# 内核参数模块 (Kernel)
# ============================================================================

apply_io_fuse_protection() {
    log info "应用 I/O 熔断保护..."

    local dirty_ratio=$1
    local dirty_background_ratio=$((dirty_ratio / 2))

    sysctl -w vm.dirty_ratio=$dirty_ratio > /dev/null 2>&1
    sysctl -w vm.dirty_background_ratio=$dirty_background_ratio > /dev/null 2>&1
    sysctl -w vm.dirty_expire_centisecs=3000 > /dev/null 2>&1
    sysctl -w vm.dirty_writeback_centisecs=500 > /dev/null 2>&1

    log info "I/O 熔断保护已启用 (dirty_ratio: $dirty_ratio)"
}

apply_oom_protection() {
    log info "应用 OOM 保护..."

    local protected=0
    local failed=0

    local pids
    pids=$(pgrep sshd 2>/dev/null) || pids=""

    if [[ -n "$pids" ]]; then
        while IFS= read -r pid; do
            if [[ "$pid" =~ ^[0-9]+$ ]] && [[ -d "/proc/$pid" ]] && [[ -f "/proc/$pid/oom_score_adj" ]]; then
                local cmdline=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ' | head -c 100)
                if [[ "$cmdline" == *"sshd"* ]]; then
                    if echo -1000 > "/proc/$pid/oom_score_adj" 2>/dev/null; then
                        ((protected++)) || true
                    else
                        ((failed++)) || true
                        log warn "设置OOM保护失败: PID $pid (sshd)"
                    fi
                fi
            fi
        done <<< "$pids"
    fi

    pids=$(pgrep systemd 2>/dev/null) || pids=""

    if [[ -n "$pids" ]]; then
        while IFS= read -r pid; do
            if [[ "$pid" =~ ^[0-9]+$ ]] && [[ -d "/proc/$pid" ]] && [[ -f "/proc/$pid/oom_score_adj" ]]; then
                local cmdline=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ' | head -c 100)
                if [[ "$cmdline" == *"systemd"* ]]; then
                    if echo -1000 > "/proc/$pid/oom_score_adj" 2>/dev/null; then
                        ((protected++)) || true
                    else
                        ((failed++)) || true
                        log warn "设置OOM保护失败: PID $pid (systemd)"
                    fi
                fi
            fi
        done <<< "$pids"
    fi

    log info "OOM 保护已启用 (已保护: $protected 个进程, 失败: $failed 个)"
}

calculate_dynamic_swappiness() {
    local base_swappiness=$1
    local mode=${2:-"$STRATEGY_MODE"}

    local swappiness=$base_swappiness

    read -r mem_total _ _ _ <<< $(get_memory_info false)
    read -r swap_total swap_used <<< $(get_swap_info false)

    local swap_usage=0
    [[ $swap_total -gt 0 ]] && swap_usage=$((swap_used * 100 / swap_total)) || true

    read -r zram_total zram_used <<< $(get_zram_usage)
    local zram_usage=0
    if [[ $zram_total -gt 0 ]]; then
        zram_usage=$((zram_used * 100 / zram_total)) || true
    fi

    if [[ $zram_usage -gt 80 ]]; then
        swappiness=$((swappiness - 20)) || true
    elif [[ $zram_usage -gt 50 ]]; then
        swappiness=$((swappiness - 10)) || true
    fi

    if [[ $swap_usage -gt 50 ]]; then
        swappiness=$((swappiness - 10)) || true
    fi

    if [[ $mem_total -lt 1024 ]]; then
        swappiness=$((swappiness + 20)) || true
    elif [[ $mem_total -gt 4096 ]]; then
        swappiness=$((swappiness - 10)) || true
    fi

    [[ $swappiness -lt 10 ]] && swappiness=10
    [[ $swappiness -gt 100 ]] && swappiness=100

    echo "$swappiness"
}

save_kernel_config() {
    local swappiness=$1
    local dirty_ratio=$2
    local min_free=$3

    mkdir -p "$CONF_DIR"
    chmod 700 "$CONF_DIR" 2>/dev/null || true

    cat > "$KERNEL_CONFIG_FILE" <<EOF
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
#   vm.dirty_background_ratio: 后台写入开始时的脏数据百分比
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
vm.swappiness=$swappiness
vm.vfs_cache_pressure=100
vm.min_free_kbytes=$min_free

# 脏数据策略 (I/O 熔断保护)
vm.dirty_ratio=$dirty_ratio
vm.dirty_background_ratio=$((dirty_ratio / 2)) || true
vm.dirty_expire_centisecs=3000
vm.dirty_writeback_centisecs=500

# 页面聚合
vm.page-cluster=0

# 文件系统
fs.file-max=2097152
fs.inotify.max_user_watches=524288
EOF

    chmod 600 "$KERNEL_CONFIG_FILE" 2>/dev/null || true
}

apply_kernel_params() {
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^# ]] && continue
        [[ -z "$key" ]] && continue
        sysctl -w "$key=$value" > /dev/null 2>&1 || true
    done < "$KERNEL_CONFIG_FILE"

    if [[ -f /etc/sysctl.conf ]]; then
        sed -i '/# Z-Panel Pro 内核参数配置/,/# Z-Panel Pro 内核参数配置结束/d' /etc/sysctl.conf

        cat >> /etc/sysctl.conf <<EOF

# Z-Panel Pro 内核参数配置
# 自动生成，请勿手动修改
EOF
        cat "$KERNEL_CONFIG_FILE" >> /etc/sysctl.conf
        echo "# Z-Panel Pro 内核参数配置结束" >> /etc/sysctl.conf
    fi
}

configure_virtual_memory() {
    local mode=${1:-"$STRATEGY_MODE"}

    log info "配置虚拟内存策略 (策略: $mode)..."

    read -r zram_ratio phys_limit swap_size swappiness dirty_ratio min_free <<< $(calculate_strategy "$mode")

    local dynamic_swappiness
    dynamic_swappiness=$(calculate_dynamic_swappiness "$swappiness" "$mode")

    log info "建议 swappiness: $dynamic_swappiness"

    save_kernel_config "$dynamic_swappiness" "$dirty_ratio" "$min_free"

    apply_kernel_params

    apply_io_fuse_protection "$dirty_ratio"
    apply_oom_protection

    log info "虚拟内存配置完成"
}

# ============================================================================
# 备份与回滚模块 (Backup)
# ============================================================================

create_backup() {
    log info "创建系统备份..."

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="$BACKUP_DIR/backup_$timestamp"

    if ! mkdir -p "$backup_path"; then
        log error "无法创建备份目录: $backup_path"
        return 1
    fi

    chmod 700 "$backup_path" 2>/dev/null || true

    local files=(
        "/etc/sysctl.conf"
        "/etc/fstab"
    )

    local backed_up=0
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            if cp "$file" "$backup_path/" 2>/dev/null; then
                ((backed_up++)) || true
                log info "已备份: $file"
            else
                log warn "备份失败: $file"
            fi
        fi
    done

    cat > "$backup_path/info.txt" <<EOF
backup_time=$timestamp
backup_version=$SCRIPT_VERSION
distro=$CURRENT_DISTRO
distro_version=$CURRENT_VERSION
strategy=$STRATEGY_MODE
memory_mb=$TOTAL_MEMORY_MB
cpu_cores=$CPU_CORES
EOF

    chmod 600 "$backup_path/info.txt" 2>/dev/null || true

    log info "备份完成: $backup_path (共 $backed_up 个文件)"
    return 0
}

restore_backup() {
    local backup_path=$1

    if [[ ! -d "$backup_path" ]]; then
        log error "备份目录不存在: $backup_path"
        return 1
    fi

    if [[ ! -f "$backup_path/info.txt" ]]; then
        log error "备份信息文件缺失: $backup_path/info.txt"
        return 1
    fi

    log info "还原系统备份: $backup_path"

    local restored=0
    local failed=0

    for file in "$backup_path"/*; do
        if [[ -f "$file" ]]; then
            local filename=$(basename "$file")
            if [[ "$filename" != "info.txt" ]]; then
                local target="/etc/$filename"
                if [[ -f "$target" ]]; then
                    local backup_target="${target}.bak.$(date +%Y%m%d_%H%M%S)"
                    if ! cp "$target" "$backup_target" 2>/dev/null; then
                        log warn "无法备份原文件: $target"
                    fi
                fi

                if cp "$file" "$target" 2>/dev/null; then
                    ((restored++)) || true
                    log info "已还原: $filename"
                else
                    ((failed++)) || true
                    log error "还原失败: $filename"
                fi
            fi
        fi
    done

    log info "还原完成: 成功 $restored 个文件，失败 $failed 个文件"
    return 0
}

# ============================================================================
# 日志管理模块 (Log Management)
# ============================================================================

load_log_config() {
    if [[ -f "$LOG_CONFIG_FILE" ]]; then
        safe_source "$LOG_CONFIG_FILE" || true
    fi
}

save_log_config() {
    [[ ! "$LOG_MAX_SIZE_MB" =~ ^[0-9]+$ ]] && LOG_MAX_SIZE_MB=50
    [[ ! "$LOG_RETENTION_DAYS" =~ ^[0-9]+$ ]] && LOG_RETENTION_DAYS=30

    mkdir -p "$CONF_DIR"
    chmod 700 "$CONF_DIR" 2>/dev/null || true

    cat > "$LOG_CONFIG_FILE" <<EOF
# ============================================================================
# Z-Panel Pro 日志配置
# ============================================================================
# 自动生成，请勿手动修改
#
# LOG_MAX_SIZE_MB: 单个日志文件最大大小（MB）
# LOG_RETENTION_DAYS: 日志文件保留天数
# ============================================================================

LOG_MAX_SIZE_MB=$LOG_MAX_SIZE_MB
LOG_RETENTION_DAYS=$LOG_RETENTION_DAYS
EOF

    chmod 600 "$LOG_CONFIG_FILE" 2>/dev/null || true
}

rotate_log() {
    local log_file=$1
    local max_size_mb=${2:-$LOG_MAX_SIZE_MB}

    if [[ ! -f "$log_file" ]]; then
        return 0
    fi

    local size_mb=$(du -m "$log_file" | cut -f1)

    if [[ $size_mb -lt $max_size_mb ]]; then
        return 0
    fi

    local log_dir=$(dirname "$log_file")
    local log_base=$(basename "$log_file" .log)
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local archive_file="${log_dir}/${log_base}_${timestamp}.log"

    if mv "$log_file" "$archive_file" && gzip "$archive_file"; then
        log info "日志已轮转: $(basename "$log_file") -> $(basename "$archive_file").gz"
    else
        log warn "日志轮转失败: $(basename "$log_file")"
    fi
}

clean_old_logs() {
    local cleaned=0
    local current_time=$(date +%s)

    shopt -s nullglob
    for log in "$LOG_DIR"/*.log; do
        [[ -f "$log" ]] || continue

        local log_name=$(basename "$log")
        local size_mb=$(du -m "$log" | cut -f1)

        if [[ $size_mb -gt $LOG_MAX_SIZE_MB ]]; then
            local temp_file
            temp_file=$(mktemp) || {
                log warn "无法创建临时文件: $log_name"
                continue
            }

            chmod 600 "$temp_file" 2>/dev/null || true

            if tail -1000 "$log" > "$temp_file" && mv "$temp_file" "$log"; then
                ((cleaned++)) || true
                log info "截断过大日志: $log_name"
            else
                rm -f "$temp_file"
                log warn "截断失败: $log_name"
            fi
            continue
        fi

        if [[ "$log_name" =~ ^zpanel_[0-9]{8}\.log$ ]]; then
            local log_date=$(echo "$log_name" | sed 's/zpanel_//' | sed 's/\.log//')
            local log_age

            local log_timestamp=0

            if date --version &>/dev/null 2>&1; then
                log_timestamp=$(date -d "$log_date" +%s 2>/dev/null || echo 0)
            else
                log_timestamp=$(date -j -f "%Y%m%d" "$log_date" +%s 2>/dev/null || echo 0)
            fi

            if [[ $log_timestamp -eq 0 ]]; then
                local file_mtime
                if stat -c %Y "$log" &>/dev/null; then
                    file_mtime=$(stat -c %Y "$log")
                else
                    file_mtime=$(stat -f "%m" "$log" 2>/dev/null || echo 0)
                fi
                log_age=$(( (current_time - file_mtime) / 86400 )) || true
            else
                log_age=$(( (current_time - log_timestamp) / 86400 )) || true
            fi

            if [[ "$log_age" =~ ^[0-9]+$ ]] && [[ $log_age -gt $LOG_RETENTION_DAYS ]]; then
                rm -f "$log" && {
                    ((cleaned++)) || true
                    log info "删除过期日志: $log_name"
                } || log warn "删除失败: $log_name"
            fi
        fi
    done
    shopt -u nullglob

    echo "清理完成，共处理 $cleaned 个日志文件"
}

log_config_menu() {
    load_log_config

    while true; do
        clear

        ui_header "日志管理"
        ui_row " 当前配置:"
        ui_row "  最大日志大小: ${GREEN}${LOG_MAX_SIZE_MB}MB${NC}"
        ui_row "  日志保留天数: ${GREEN}${LOG_RETENTION_DAYS}天${NC}"
        ui_line
        ui_row " 操作选项:"
        ui_menu_item "1" "设置最大日志大小"
        ui_menu_item "2" "设置日志保留天数"
        ui_menu_item "3" "查看日志文件列表"
        ui_menu_item "4" "查看运行日志（分页）"
        ui_menu_item "5" "查看动态调整日志（分页）"
        ui_menu_item "6" "清理过期日志"
        ui_menu_item "0" "返回"
        ui_bot

        echo ""
        echo -ne "${WHITE}请选择 [0-6]: ${NC}"
        read -r choice

        case $choice in
            1)
                local valid=false
                while [[ "$valid" == "false" ]]; do
                    echo -ne "\n设置最大日志大小 (MB, 10-500): "
                    read -r size
                    if [[ "$size" =~ ^[0-9]+$ ]] && [[ $size -ge 10 ]] && [[ $size -le 500 ]]; then
                        LOG_MAX_SIZE_MB=$size
                        save_log_config
                        echo -e "${GREEN}设置成功${NC}"
                        valid=true
                    else
                        echo -e "${RED}无效输入，请输入 10-500 之间的数字${NC}"
                    fi
                done
                pause
                ;;
            2)
                local valid=false
                while [[ "$valid" == "false" ]]; do
                    echo -ne "\n设置日志保留天数 (1-365): "
                    read -r days
                    if [[ "$days" =~ ^[0-9]+$ ]] && [[ $days -ge 1 ]] && [[ $days -le 365 ]]; then
                        LOG_RETENTION_DAYS=$days
                        save_log_config
                        echo -e "${GREEN}设置成功${NC}"
                        valid=true
                    else
                        echo -e "${RED}无效输入，请输入 1-365 之间的数字${NC}"
                    fi
                done
                pause
                ;;
            3)
                clear
                ui_header "日志文件列表"

                if [[ -d "$LOG_DIR" ]]; then
                    ui_row " ZPanel 日志:"
                    shopt -s nullglob
                    for log in "$LOG_DIR"/zpanel_*.log; do
                        [[ -f "$log" ]] && {
                            local size=$(du -h "$log" | cut -f1)
                            local mtime
                            if stat -c %y "$log" &>/dev/null; then
                                mtime=$(stat -c %y "$log" 2>/dev/null | cut -d' ' -f1-2)
                            else
                                mtime=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$log" 2>/dev/null || date -r "$log" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "未知")
                            fi
                            local name=$(basename "$log")
                            ui_row "  ${GREEN}•${NC} ${name} | ${size} | ${mtime}"
                        }
                    done
                    shopt -u nullglob

                    ui_row " 动态调整日志:"
                    if [[ -f "$LOG_DIR/dynamic.log" ]]; then
                        local size=$(du -h "$LOG_DIR/dynamic.log" | cut -f1)
                        local mtime
                        if stat -c %y "$LOG_DIR/dynamic.log" &>/dev/null; then
                            mtime=$(stat -c %y "$LOG_DIR/dynamic.log" 2>/dev/null | cut -d' ' -f1-2)
                        else
                            mtime=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$LOG_DIR/dynamic.log" 2>/dev/null || date -r "$LOG_DIR/dynamic.log" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "未知")
                        fi
                        ui_row "  ${GREEN}•${NC} dynamic.log | ${size} | ${mtime}"
                    fi
                else
                    ui_row " ${YELLOW}暂无日志文件${NC}"
                fi

                ui_bot
                pause
                ;;
            4)
                view_log_paged "zpanel"
                ;;
            5)
                view_log_paged "dynamic"
                ;;
            6)
                if confirm "确认清理过期日志？"; then
                    clean_old_logs
                fi
                pause
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效输入${NC}"
                sleep 1
                ;;
        esac
    done
}

view_log_paged() {
    local log_type=$1
    local log_file=""
    local lines=20
    local page=1
    local total_lines=0

    case $log_type in
        zpanel)
            log_file=$(ls -t "$LOG_DIR"/zpanel_*.log 2>/dev/null | head -1)
            ;;
        dynamic)
            log_file="$LOG_DIR/dynamic.log"
            ;;
    esac

    if [[ ! -f "$log_file" ]]; then
        echo -e "${YELLOW}日志文件不存在${NC}"
        pause
        return
    fi

    total_lines=$(wc -l < "$log_file")

    while true; do
        clear

        ui_header "日志查看: $(basename "$log_file")"
        ui_row " 页码: ${GREEN}${page}${NC}/$(( (total_lines + lines - 1) / lines ))  总行数: ${GREEN}${total_lines}${NC}"
        ui_line

        local start=$(( (page - 1) * lines + 1 ))
        local end=$((page * lines))

        sed -n "${start},${end}p" "$log_file" | while IFS= read -r line; do
            ui_row "  ${line}"
        done

        ui_bot
        echo -e "${YELLOW}n - 下一页  p - 上一页  q - 退出${NC}"
        echo ""
        echo -ne "${WHITE}请选择: ${NC}"
        read -r action

        case $action in
            n|N)
                if [[ $page -lt $(( (total_lines + lines - 1) / lines )) ]]; then
                    ((page++))
                fi
                ;;
            p|P)
                if [[ $page -gt 1 ]]; then
                    ((page--))
                fi
                ;;
            q|Q)
                return
                ;;
        esac
    done
}

# ============================================================================
# 动态调整模块 (Dynamic)
# ============================================================================

create_dynamic_adjust_script() {
    cat > "$INSTALL_DIR/dynamic-adjust.sh" <<'EOF'
#!/bin/bash
set -e
CONF_DIR="/opt/z-panel/conf"
LOG_DIR="/opt/z-panel/logs"
LIB_DIR="/opt/z-panel/lib"

if [[ -f "$LIB_DIR/common.sh" ]]; then
    source "$LIB_DIR/common.sh"
else
    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_DIR/dynamic-adjust.log" 2>/dev/null || true
    }

    get_memory_info() {
        free -m | awk '/^Mem:/ {print $2, $3, $7, $6}'
    }

    get_swap_info() {
        free -m | awk '/Swap:/ {print $2, $3}'
    }

    get_zram_usage() {
        if ! swapon --show=NAME --noheadings 2>/dev/null | grep -q zram; then
            echo "0 0"
            return
        fi

        local zram_total=$(swapon --show=SIZE --noheadings 2>/dev/null | grep zram | awk '{print $1}')
        local zram_used=$(swapon --show=USED --noheadings 2>/dev/null | grep zram | awk '{print $1}')

        [[ -z "$zram_total" || "$zram_total" == "0" ]] && zram_total=1
        [[ -z "$zram_used" ]] && zram_used=0

        echo "$zram_total $zram_used"
    }
fi

if [[ -f "$CONF_DIR/strategy.conf" ]]; then
    source "$CONF_DIR/strategy.conf"
else
    STRATEGY_MODE="balance"
fi

read -r mem_total mem_used mem_avail buff_cache <<< $(get_memory_info)
mem_percent=$((mem_used * 100 / mem_total)) || true

read -r swap_total swap_used <<< $(get_swap_info)
swap_usage=0
[[ $swap_total -gt 0 ]] && swap_usage=$((swap_used * 100 / swap_total)) || true

read -r zram_total zram_used <<< $(get_zram_usage)
zram_usage=0
[[ $zram_total -gt 0 ]] && zram_usage=$((zram_used * 100 / zram_total)) || true

optimal_swappiness=60
if [[ $zram_usage -gt 80 ]]; then
    optimal_swappiness=30
elif [[ $zram_usage -gt 50 ]]; then
    optimal_swappiness=40
fi

if [[ $swap_usage -gt 50 ]]; then
    optimal_swappiness=$((optimal_swappiness - 10)) || true
fi

if [[ $mem_total -lt 1024 ]]; then
    optimal_swappiness=$((optimal_swappiness + 20)) || true
elif [[ $mem_total -gt 4096 ]]; then
    optimal_swappiness=$((optimal_swappiness - 10)) || true
fi

[[ $optimal_swappiness -lt 10 ]] && optimal_swappiness=10
[[ $optimal_swappiness -gt 100 ]] && optimal_swappiness=100

current_swappiness=$(sysctl -n vm.swappiness 2>/dev/null || echo 60)
if [[ $optimal_swappiness -ne $current_swappiness ]]; then
    sysctl -w vm.swappiness=$optimal_swappiness > /dev/null 2>&1
    log "调整 swappiness: $current_swappiness -> $optimal_swappiness"
fi

log "内存: ${mem_percent}%, Swap: ${swap_usage}%, ZRAM: ${zram_usage}%, swappiness: $optimal_swappiness"
EOF

    chmod 700 "$INSTALL_DIR/dynamic-adjust.sh" 2>/dev/null || true
}

safe_crontab_add() {
    local cron_entry="$1"
    local cron_temp
    cron_temp=$(mktemp) || {
        log error "无法创建临时文件"
        return 1
    }

    chmod 600 "$cron_temp" 2>/dev/null || true

    if crontab -l 2>/dev/null > "$cron_temp"; then
        if ! grep -q "$(echo "$cron_entry" | awk '{print $NF}')" "$cron_temp"; then
            echo "$cron_entry" >> "$cron_temp"

            if grep -q "$(echo "$cron_entry" | awk '{print $NF}')" "$cron_temp"; then
                crontab "$cron_temp" 2>/dev/null || {
                    log error "crontab 安装失败"
                    rm -f "$cron_temp"
                    return 1
                }
            else
                log error "crontab 条目验证失败"
                rm -f "$cron_temp"
                return 1
            fi
        fi
    else
        echo "$cron_entry" > "$cron_temp"

        if grep -q "$(echo "$cron_entry" | awk '{print $NF}')" "$cron_temp"; then
            crontab "$cron_temp" 2>/dev/null || {
                log error "crontab 设置失败"
                rm -f "$cron_temp"
                return 1
            }
        else
            log error "crontab 条目验证失败"
            rm -f "$cron_temp"
            return 1
        fi
    fi

    rm -f "$cron_temp"
    return 0
}

safe_crontab_remove() {
    local pattern="$1"
    local cron_temp
    cron_temp=$(mktemp) || {
        log error "无法创建临时文件"
        return 1
    }

    chmod 600 "$cron_temp" 2>/dev/null || true

    if crontab -l 2>/dev/null > "$cron_temp"; then
        grep -v "$pattern" "$cron_temp" > "${cron_temp}.filtered" 2>/dev/null || true

        if [[ -f "${cron_temp}.filtered" ]]; then
            crontab "${cron_temp}.filtered" 2>/dev/null || log warn "crontab 更新失败"
            rm -f "${cron_temp}.filtered"
        fi
    fi

    rm -f "$cron_temp"
    return 0
}

enable_dynamic_mode() {
    log info "启用动态调整模式..."

    create_dynamic_adjust_script || {
        log error "创建动态调整脚本失败"
        return 1
    }

    local cron_entry="*/5 * * * * $INSTALL_DIR/dynamic-adjust.sh"
    safe_crontab_add "$cron_entry" || {
        log error "添加 crontab 失败"
        return 1
    }

    DYNAMIC_MODE=true
    log info "动态调整模式已启用 (每 5 分钟检查)"
}

disable_dynamic_mode() {
    log info "停用动态调整模式..."

    safe_crontab_remove "dynamic-adjust.sh"

    DYNAMIC_MODE=false
    log info "动态调整模式已停用"
}

# ============================================================================
# 监控面板模块 (Monitor)
# ============================================================================

cleanup_monitor() {
    clear_cache
    log info "监控面板已退出"
}

show_monitor() {
    clear

    trap 'cleanup_monitor; return 0' INT TERM QUIT HUP

    local last_mem_used=0
    local last_zram_used=0
    local last_swap_used=0
    local last_swappiness=0
    local refresh_interval=1
    local force_refresh=true

    while true; do
        read -r mem_total mem_used mem_avail buff_cache <<< $(get_memory_info true)
        read -r zram_total_kb zram_used_kb <<< $(get_zram_usage)
        read -r swap_total swap_used <<< $(get_swap_info true)
        local swappiness=$(sysctl -n vm.swappiness 2>/dev/null || echo "60")

        local data_changed=false
        if [[ $force_refresh == true ]] || \
           [[ $mem_used -ne $last_mem_used ]] || \
           [[ $zram_used_kb -ne $last_zram_used ]] || \
           [[ $swap_used -ne $last_swap_used ]] || \
           [[ $swappiness -ne $last_swappiness ]]; then
            data_changed=true
            force_refresh=false
        fi

        if [[ $data_changed == true ]]; then
            clear

            ui_header "Z-Panel Pro 实时监控面板 v${SCRIPT_VERSION}"
            ui_row " 内存: ${GREEN}${TOTAL_MEMORY_MB}MB${NC} CPU: ${GREEN}${CPU_CORES}核心${NC} 模式: ${YELLOW}${STRATEGY_MODE}${NC}"
            ui_line

            ui_section "📊 RAM 使用情况"
            ui_row " 使用: ${GREEN}${mem_used}MB${NC}  缓存: ${CYAN}${buff_cache}MB${NC}  空闲: ${GREEN}${mem_avail}MB${NC}"
            ui_row " 物理内存负载:"
            echo -ne "  "
            show_progress_bar "$mem_used" "$mem_total" 46 ""
            ui_line

            ui_section "💾 ZRAM 状态"

            if swapon --show=NAME --noheadings 2>/dev/null | grep -q zram; then
                ui_row " 状态: ${GREEN}运行中${NC}"

                local zram_status=$(get_zram_status)
                local algo_ratio=$(echo "$zram_status" | awk '{
                    gsub(/[[:space:]]/, "", $0)
                    gsub(/[{}"]/, "", $0)
                    for (i = 1; i <= NF; i++) {
                        if ($i ~ /^algorithm:/) {
                            split($i, a, ":")
                            algo = a[2]
                        }
                        if ($i ~ /^compression_ratio:/) {
                            split($i, a, ":")
                            ratio = a[2]
                        }
                    }
                }')
                local algo="${algo:-"unknown"}"
                local ratio="${ratio:-"1.00"}"
                [[ -z "$ratio" || "$ratio" == "0" ]] && ratio="1.00"

                ui_row " 算法: ${CYAN}${algo}${NC}  压缩比: ${YELLOW}${ratio}x${NC}"
                ui_row " ZRAM 压缩比:"
                echo -ne "  "
                show_compression_chart "$ratio" 46
                ui_row " ZRAM 负载:"
                echo -ne "  "
                show_progress_bar "$zram_used_kb" "$zram_total_kb" 46 ""
            else
                ui_row " 状态: ${RED}未启用${NC}"
            fi

            ui_section "🔄 Swap 负载"

            if [[ $swap_total -gt 0 ]]; then
                echo -ne "  "
                show_progress_bar "$swap_used" "$swap_total" 46 ""
            else
                ui_row " 状态: ${RED}未启用${NC}"
            fi

            ui_section "⚙️  内核参数"
            ui_row " swappiness:"
            echo -ne "  "
            show_progress_bar "$swappiness" 100 46 ""

            ui_bot
            echo ""
            echo -e "${YELLOW}💡 按 ${WHITE}Ctrl+C${YELLOW} 返回主菜单${NC}"
            echo ""

            last_mem_used=$mem_used
            last_zram_used_kb=$zram_used_kb
            last_swap_used=$swap_used
            last_swappiness=$swappiness
        fi

        sleep $refresh_interval
    done
}

show_status() {
    clear

    ui_header "Z-Panel Pro 系统状态 v${SCRIPT_VERSION}"

    ui_section "📋 系统信息"
    ui_row " 发行版: ${GREEN}${CURRENT_DISTRO} ${CURRENT_VERSION}${NC}"
    ui_row " 内存: ${GREEN}${TOTAL_MEMORY_MB}MB${NC}  CPU: ${GREEN}${CPU_CORES}核心${NC}  策略: ${YELLOW}${STRATEGY_MODE}${NC}"

    ui_section "💾 ZRAM 状态"

    if swapon --show=NAME --noheadings 2>/dev/null | grep -q zram; then
        ui_row " 状态: ${GREEN}运行中${NC}"

        local zram_status=$(get_zram_status)
        local disk_size data_size comp_size algo ratio
        eval "$(echo "$zram_status" | awk '{
            gsub(/[[:space:]]/, "", $0)
            gsub(/[{}"]/, "", $0)
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^disk_size:/) {
                    split($i, a, ":")
                    print "disk_size=\"" a[2] "\""
                }
                if ($i ~ /^data_size:/) {
                    split($i, a, ":")
                    print "data_size=\"" a[2] "\""
                }
                if ($i ~ /^comp_size:/) {
                    split($i, a, ":")
                    print "comp_size=\"" a[2] "\""
                }
                if ($i ~ /^algorithm:/) {
                    split($i, a, ":")
                    print "algo=\"" a[2] "\""
                }
                if ($i ~ /^compression_ratio:/) {
                    split($i, a, ":")
                    print "ratio=\"" a[2] "\""
                }
            }
        }')"
        [[ -z "$disk_size" ]] && disk_size="0"
        [[ -z "$data_size" ]] && data_size="0"
        [[ -z "$comp_size" ]] && comp_size="0"
        [[ -z "$algo" ]] && algo="unknown"
        [[ -z "$ratio" || "$ratio" == "0" ]] && ratio="1.00"

        ui_row " 算法: ${CYAN}${algo}${NC}  大小: ${CYAN}${disk_size}${NC}"
        ui_row " 数据: ${CYAN}${data_size}${NC}  压缩: ${CYAN}${comp_size}${NC}"
        ui_row " 压缩比:"
        echo -ne "  "
        show_compression_chart "$ratio" 46
    else
        ui_row " 状态: ${RED}未启用${NC}"
    fi

    ui_section "🔄 Swap 状态"

    read -r swap_total swap_used <<< "$(get_swap_info false)"

    if [[ $swap_total -eq 0 ]]; then
        ui_row " 状态: ${RED}未启用${NC}"
    else
        ui_row " 总量: ${CYAN}${swap_total}MB${NC}  已用: ${CYAN}${swap_used}MB${NC}"
        ui_row " Swap 负载:"
        echo -ne "  "
        show_progress_bar "$swap_used" "$swap_total" 46 ""
    fi

    ui_section "⚙️  内核参数"

    local swappiness=$(sysctl -n vm.swappiness 2>/dev/null || echo "60")
    local vfs_cache=$(sysctl -n vm.vfs_cache_pressure 2>/dev/null || echo "100")
    local dirty_ratio=$(sysctl -n vm.dirty_ratio 2>/dev/null || echo "20")

    ui_row " vm.swappiness:"
    echo -ne "  "
    show_progress_bar "$swappiness" 100 46 ""

    ui_section "🛡️  保护机制"
    ui_row "  ${GREEN}•${NC} I/O 熔断: ${GREEN}已启用${NC}"
    ui_row "  ${GREEN}•${NC} OOM 保护: ${GREEN}已启用${NC}"
    ui_row "  ${GREEN}•${NC} 物理内存熔断: ${GREEN}已启用${NC}"

    ui_bot
    echo ""
}

# ============================================================================
# 菜单系统模块 (Menu)
# ============================================================================

show_main_menu() {
    clear

    ui_header "Z-Panel Pro v${SCRIPT_VERSION} 主控菜单"
    ui_row "系统: RAM:${TOTAL_MEMORY_MB}MB CPU:${CPU_CORES}Cores ${CURRENT_DISTRO} ${CURRENT_VERSION}"
    ui_line

    ui_section "🚀 主要功能"
    ui_menu_item "1" "一键优化[${YELLOW}当前: ${STRATEGY_MODE}${NC}]"
    ui_menu_item "2" "状态监控"
    ui_menu_item "3" "日志管理"

    ui_section "⚙️  高级功能"
    ui_menu_item "4" "切换优化模式[${YELLOW}保守/平衡/激进${NC}]"
    ui_menu_item "5" "配置 ZRAM"
    ui_menu_item "6" "配置虚拟内存"
    ui_menu_item "7" "动态调整模式"

    ui_section "🛠️  系统管理"
    ui_menu_item "8" "查看系统状态"
    ui_menu_item "9" "停用 ZRAM"
    ui_menu_item "10" "还原备份"
    ui_menu_item "0" "退出程序"

    ui_line
    local zram_status
    if [[ $ZRAM_ENABLED == true ]]; then
        zram_status="${GREEN}●${NC} 已启用"
    else
        zram_status="${RED}○${NC} 未启用"
    fi
    local dynamic_status
    if [[ $DYNAMIC_MODE == true ]]; then
        dynamic_status="${GREEN}●${NC} 已启用"
    else
        dynamic_status="${RED}○${NC} 未启用"
    fi
    ui_row " ZRAM: ${zram_status}  │  动态: ${dynamic_status}"
    ui_bot
    echo ""
    echo -ne "${WHITE}请选择 [0-10]: ${NC}"
}

strategy_menu() {
    while true; do
        clear

        ui_header "选择优化模式"
        ui_menu_item "1" "Conservative (保守)"
        ui_row "     • 最稳定，适合路由器/NAS"
        ui_row "     • ZRAM: 80% | Swap: 100% | Swappiness: 60"
        ui_line
        ui_menu_item "2" "Balance (平衡)  ${YELLOW}[推荐]${NC}"
        ui_row "     • 性能与稳定兼顾，日常使用"
        ui_row "     • ZRAM: 120% | Swap: 150% | Swappiness: 85"
        ui_line
        ui_menu_item "3" "Aggressive (激进)"
        ui_row "     • 极限榨干内存，适合极度缺内存"
        ui_row "     • ZRAM: 180% | Swap: 200% | Swappiness: 100"
        ui_line
        ui_menu_item "0" "返回"
        ui_bot
        echo ""
        echo -ne "${WHITE}请选择 [0-3]: ${NC}"
        read -r choice

        case $choice in
            1)
                STRATEGY_MODE="conservative"
                save_strategy_config
                log info "策略已切换为: $STRATEGY_MODE"
                if confirm "是否立即应用新模式？"; then
                    quick_optimize
                fi
                return
                ;;
            2)
                STRATEGY_MODE="balance"
                save_strategy_config
                log info "策略已切换为: $STRATEGY_MODE"
                if confirm "是否立即应用新模式？"; then
                    quick_optimize
                fi
                return
                ;;
            3)
                STRATEGY_MODE="aggressive"
                save_strategy_config
                log info "策略已切换为: $STRATEGY_MODE"
                if confirm "是否立即应用新模式？"; then
                    quick_optimize
                fi
                return
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效输入${NC}"
                sleep 1
                ;;
        esac
    done
}

zram_menu() {
    while true; do
        clear

        ui_header "ZRAM 配置"
        ui_menu_item "1" "启用 ZRAM (自动检测算法)"
        ui_menu_item "2" "自定义配置"
        ui_menu_item "3" "查看 ZRAM 状态"
        ui_menu_item "0" "返回"
        ui_bot
        echo ""
        echo -ne "${WHITE}请选择 [0-3]: ${NC}"
        read -r choice

        case $choice in
            1)
                configure_zram "auto" "$STRATEGY_MODE"
                pause
                ;;
            2)
                local valid=false
                while [[ "$valid" == "false" ]]; do
                    echo -ne "压缩算法 [auto/zstd/lz4/lzo]: "
                    read -r algo
                    case "$algo" in
                        auto|zstd|lz4|lzo)
                            valid=true
                            configure_zram "$algo" "$STRATEGY_MODE"
                            ;;
                        *)
                            echo -e "${RED}无效算法，请重新输入${NC}"
                            ;;
                    esac
                done
                pause
                ;;
            3)
                if command -v jq &> /dev/null; then
                    get_zram_status | jq .
                elif command -v python3 &> /dev/null; then
                    get_zram_status | python3 -m json.tool 2>/dev/null || get_zram_status
                else
                    get_zram_status
                fi
                pause
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效输入${NC}"
                sleep 1
                ;;
        esac
    done
}

dynamic_menu() {
    while true; do
        clear

        ui_header "动态调整模式"
        ui_menu_item "1" "启用动态调整"
        ui_menu_item "2" "停用动态调整"
        ui_menu_item "3" "查看调整日志"
        ui_menu_item "0" "返回"
        ui_bot
        echo ""
        echo -ne "${WHITE}请选择 [0-3]: ${NC}"
        read -r choice

        case $choice in
            1)
                enable_dynamic_mode
                pause
                ;;
            2)
                if confirm "确认停用动态调整？"; then
                    disable_dynamic_mode
                fi
                pause
                ;;
            3)
                if [[ -f "$LOG_DIR/dynamic.log" ]]; then
                    clear
                    ui_header "动态调整日志"
                    tail -20 "$LOG_DIR/dynamic.log" | while IFS= read -r line; do
                        ui_row "  ${line}"
                    done
                    ui_bot
                else
                    echo -e "${YELLOW}暂无日志${NC}"
                fi
                pause
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效输入${NC}"
                sleep 1
                ;;
        esac
    done
}

quick_optimize() {
    clear

    ui_header "一键优化"
    ui_row " 将执行以下操作:"
    ui_line
    ui_row "  ${GREEN}•${NC} 创建系统备份"
    ui_row "  ${GREEN}•${NC} 配置 ZRAM (策略: ${YELLOW}${STRATEGY_MODE}${NC})"
    ui_row "  ${GREEN}•${NC} 配置虚拟内存策略 (含 I/O 熔断/OOM 保护)"
    ui_row "  ${GREEN}•${NC} 启用动态调整模式"
    ui_row "  ${GREEN}•${NC} 配置开机自启动"
    ui_bot
    echo ""
    if ! confirm "确认执行？"; then
        return
    fi

    local errors=0

    if ! create_backup; then
        log warn "备份创建失败，继续执行优化"
        ((errors++)) || true
    fi

    if ! configure_zram "auto" "$STRATEGY_MODE"; then
        log error "ZRAM 配置失败"
        ((errors++)) || true
    fi

    if ! configure_virtual_memory "$STRATEGY_MODE"; then
        log error "虚拟内存配置失败"
        ((errors++)) || true
    fi

    if ! enable_dynamic_mode; then
        log warn "动态调整模式启用失败"
        ((errors++)) || true
    fi

    if [[ $errors -gt 0 ]]; then
        echo ""
        echo "注意: 优化过程中遇到 $errors 个错误，请检查日志"
        echo "日志目录: $LOG_DIR"
    else
        echo ""
        echo "优化完成！"
        echo "✓ ZRAM 已配置为开机自动启动"
        echo "✓ 虚拟内存策略已应用（含 I/O 熔断/OOM 保护）"
        echo "✓ 动态调整模式已启用（每 5 分钟优化）"
        echo "✓ 策略模式: $STRATEGY_MODE"
    fi
    pause
}

# ============================================================================
# 全局快捷键安装模块 (Shortcut)
# ============================================================================

install_global_shortcut() {
    local shortcut_path="/usr/local/bin/z"
    local script_path=$(realpath "$0" 2>/dev/null || readlink -f "$0" 2>/dev/null || echo "$0")

    local path_has_bin=false
    local IFS=':'
    for dir in $PATH; do
        if [[ "$dir" == "/usr/local/bin" ]]; then
            path_has_bin=true
            break
        fi
    done
    unset IFS

    if [[ "$path_has_bin" == false ]]; then
        log warn "/usr/local/bin 不在系统 PATH 中"
        echo -e "${YELLOW}警告: /usr/local/bin 不在系统 PATH 中${NC}"
        echo "请将以下内容添加到 ~/.bashrc 或 ~/.zshrc:"
        echo "  export PATH=\"/usr/local/bin:\$PATH\""
        echo ""
    fi

    if [[ -f "$shortcut_path" ]]; then
        local existing_link=$(readlink "$shortcut_path" 2>/dev/null || cat "$shortcut_path" 2>/dev/null)
        if [[ "$existing_link" == "$script_path" ]]; then
            log info "全局快捷键 'z' 已存在且指向当前脚本"
            return 0
        fi

        log warn "全局快捷键 'z' 已存在: $shortcut_path"
        echo -e "${YELLOW}检测到现有快捷键指向:${NC} $existing_link"
        echo -e "${YELLOW}当前脚本路径:${NC} $script_path"

        local backup_path="${shortcut_path}.bak.$(date +%Y%m%d_%H%M%S)"
        if cp "$shortcut_path" "$backup_path" 2>/dev/null; then
            log info "已备份现有快捷键到: $backup_path"
            echo -e "${GREEN}✓${NC} 已备份现有快捷键到: ${CYAN}$backup_path${NC}"
        else
            log warn "备份现有快捷键失败，继续覆盖"
        fi
    fi

    cat > "$shortcut_path" <<EOF
#!/bin/bash
# Z-Panel Pro 全局快捷键
# 自动生成，请勿手动修改

if [[ \$EUID -ne 0 ]]; then
    echo -e "\033[0;31m此脚本需要 root 权限运行\033[0m"
    echo "请使用: sudo z"
    exit 1
fi

exec bash "$script_path"
EOF

    chmod 755 "$shortcut_path" 2>/dev/null || true
    log info "全局快捷键 'z' 已安装到 $shortcut_path"

    if [[ "$path_has_bin" == true ]]; then
        echo -e "${GREEN}✓${NC} 全局快捷键已安装！现在可以随时输入 ${YELLOW}sudo z${NC} 打开 Z-Panel Pro"
    else
        echo -e "${GREEN}✓${NC} 全局快捷键已安装到 ${YELLOW}$shortcut_path${NC}"
        echo -e "${YELLOW}注意: 请先添加 /usr/local/bin 到 PATH 环境变量${NC}"
    fi
}

# ============================================================================
# 信号处理模块 (Signal Handler)
# ============================================================================

cleanup_on_exit() {
    log info "执行清理操作..."
    clear_zram_cache
    release_lock
    log info "清理完成"
}

trap cleanup_on_exit INT TERM QUIT

# ============================================================================
# 主程序入口 (Main)
# ============================================================================

main() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}此脚本需要 root 权限运行${NC}"
        echo "请使用: sudo bash $0"
        exit 1
    fi

    if ! acquire_lock; then
        echo -e "${RED}无法获取文件锁，脚本可能已在运行${NC}"
        exit 1
    fi

    init_icons
    check_dependencies || exit 1
    detect_system

    mkdir -p "$INSTALL_DIR"/{conf,logs,backup,lib}

    chmod 750 "$INSTALL_DIR" 2>/dev/null || true
    chmod 700 "$INSTALL_DIR/conf" 2>/dev/null || true
    chmod 750 "$INSTALL_DIR/logs" 2>/dev/null || true
    chmod 700 "$INSTALL_DIR/backup" 2>/dev/null || true
    chmod 755 "$INSTALL_DIR/lib" 2>/dev/null || true

    log info "目录权限已设置"

    install_global_shortcut

    load_strategy_config
    load_log_config

    if [[ -f "$ZRAM_CONFIG_FILE" ]]; then
        ZRAM_ENABLED=true
    fi
    if crontab -l 2>/dev/null | grep -q "dynamic-adjust.sh"; then
        DYNAMIC_MODE=true
    fi

    while true; do
        show_main_menu
        read -r choice

        case $choice in
            1)
                quick_optimize
                ;;
            2)
                show_monitor
                ;;
            3)
                log_config_menu
                ;;
            4)
                strategy_menu
                ;;
            5)
                zram_menu
                ;;
            6)
                configure_virtual_memory "$STRATEGY_MODE"
                pause
                ;;
            7)
                dynamic_menu
                ;;
            8)
                show_status
                pause
                ;;
            9)
                if confirm "确认停用 ZRAM？"; then
                    disable_zram
                fi
                pause
                ;;
            10)
                if [[ -d "$BACKUP_DIR" ]]; then
                    echo -e "\n可用备份:"
                    local i=1
                    declare -A backup_map
                    for backup in "$BACKUP_DIR"/backup_*; do
                        if [[ -d "$backup" ]]; then
                            local name=$(basename "$backup")
                            echo -e "  ${CYAN}$i.${NC} $name"
                            backup_map[$i]="$backup"
                            ((i++)) || true
                        fi
                    done
                    echo -ne "\n请选择备份编号 (0 取消): "
                    read -r backup_num
                    if [[ "$backup_num" =~ ^[0-9]+$ ]] && [[ $backup_num -ge 1 ]] && [[ -n "${backup_map[$backup_num]}" ]]; then
                        if confirm "确认还原备份？"; then
                            restore_backup "${backup_map[$backup_num]}"
                        fi
                    fi
                else
                    echo -e "${YELLOW}暂无备份${NC}"
                fi
                pause
                ;;
            0)
                echo -e "${GREEN}感谢使用 $SCRIPT_NAME！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效输入，请重新选择${NC}"
                sleep 1
                ;;
        esac
    done
}

main