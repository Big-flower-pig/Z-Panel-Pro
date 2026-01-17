#!/bin/bash

# Make pipes fail on first failed command, keep predictable locale and
# enable nullglob to avoid literal globs when none match.
set -o pipefail
set -euo pipefail
export LC_ALL=C
shopt -s nullglob

################################################################################
# Z-Panel Pro - 分级内存智能优化系统
#
# @description    专注于 ZRAM 压缩内存和系统虚拟内存的深度优化
# @version       5.0.0-Pro
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
# @usage         sudo bash z-panel.sh
# @requirements  - Bash 4.0+
#                - Root privileges
#                - Linux kernel 3.0+
################################################################################

# ============================================================================
# 全局配置
# ============================================================================

readonly SCRIPT_VERSION="5.0.0-Pro"
readonly BUILD_DATE="2026-01-17"
readonly SCRIPT_NAME="Z-Panel Pro 内存优化"

# 文件锁配置
readonly LOCK_FILE="/tmp/z-panel.lock"
readonly LOCK_FD=200

# 界面配置
declare -g USE_NERD_FONT=false
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

# 目录配置
readonly INSTALL_DIR="/opt/z-panel"
readonly CONF_DIR="$INSTALL_DIR/conf"
readonly LOG_DIR="$INSTALL_DIR/logs"
readonly BACKUP_DIR="$INSTALL_DIR/backup"
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

# 日志配置
declare -g LOG_MAX_SIZE_MB=50
declare -g LOG_RETENTION_DAYS=30

# 进度条和压缩比阈值常量
readonly PROGRESS_THRESHOLD_CRITICAL=90
readonly PROGRESS_THRESHOLD_HIGH=70
readonly PROGRESS_THRESHOLD_MEDIUM=50
readonly COMPRESSION_RATIO_EXCELLENT=3.0
readonly COMPRESSION_RATIO_GOOD=2.0
readonly COMPRESSION_RATIO_FAIR=1.5

# ZRAM设备缓存
declare -g _ZRAM_ENABLED_CACHE=""
declare -g _ZRAM_DEVICE_CACHE=""

# 系统信息
declare -g CURRENT_DISTRO=""
declare -g CURRENT_VERSION=""
declare -g PACKAGE_MANAGER=""
declare -g TOTAL_MEMORY_MB=0
declare -g CPU_CORES=0

# 状态变量
declare -g ZRAM_ENABLED=false
declare -g DYNAMIC_MODE=false
declare -g STRATEGY_MODE="balance"  # conservative, balance, aggressive

# 缓存变量（用于监控面板）
declare -g CACHE_MEM_TOTAL=0
declare -g CACHE_MEM_USED=0
declare -g CACHE_MEM_AVAIL=0
declare -g CACHE_BUFF_CACHE=0
declare -g CACHE_SWAP_TOTAL=0
declare -g CACHE_SWAP_USED=0
declare -g CACHE_LAST_UPDATE=0
declare -g CACHE_TTL=3  # 缓存有效期（秒）

# ============================================================================
# 文件锁功能
# ============================================================================

# 获取文件锁
# @return 0 表示成功获取锁，1 表示失败
acquire_lock() {
    # 尝试打开锁文件
    if ! eval "exec $LOCK_FD>\"$LOCK_FILE\""; then
        log error "无法创建锁文件: $LOCK_FILE"
        return 1
    fi

    # 尝试获取排他锁（非阻塞模式）
    if ! flock -n $LOCK_FD; then
        local pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "unknown")
        log error "脚本已在运行中 (PID: $pid)"
        log error "如需重新启动，请先运行: rm -f $LOCK_FILE"
        return 1
    fi

    # 将当前 PID 写入锁文件
    echo $$ > "$LOCK_FILE"

    log info "已获取文件锁 (PID: $$)"
    return 0
}

# 释放文件锁
release_lock() {
    if flock -u $LOCK_FD 2>/dev/null; then
        log info "已释放文件锁"
        rm -f "$LOCK_FILE" 2>/dev/null
    fi
}

# ============================================================================
# Nerd Font 检测和图标系统
# ============================================================================

# 检测系统是否支持 Nerd Font
# 检查多个来源以确定 Nerd Font 是否可用
# @return 0 表示支持 Nerd Font，1 表示不支持
detect_nerd_font() {
    local has_nerd_font=false

    # 方法 1: 检查字体配置文件
    if [[ -f ~/.config/fontconfig/fonts.conf ]] || [[ -f ~/.fonts.conf ]]; then
        local font_file="${HOME}/.config/fontconfig/fonts.conf"
        [[ -f "$font_file" ]] || font_file="${HOME}/.fonts.conf"
        if grep -qi "nerd\|hack\|fira\|jetbrains" "$font_file" 2>/dev/null; then
            has_nerd_font=true
        fi
    fi

    # 方法 2: 检查常见 Nerd Font 安装路径
    local font_dirs=(
        "/usr/share/fonts"
        "/usr/local/share/fonts"
        "${HOME}/.local/share/fonts"
        "${HOME}/.fonts"
    )

    for dir in "${font_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            if find "$dir" -iname "*nerd*" -o -iname "*hack*nerd*" -o -iname "*fira*nerd*" 2>/dev/null | grep -q .; then
                has_nerd_font=true
                break
            fi
        fi
    done

    # 方法 3: 检查环境变量
    if [[ -n "${TERM_PROGRAM:-}" ]] && [[ "${TERM_PROGRAM:-}" == "iTerm.app" ]]; then
        # iTerm2 通常支持 Nerd Font
        has_nerd_font=true
    fi

    if [[ -n "${TERMINAL_EMULATOR:-}" ]]; then
        if echo "${TERMINAL_EMULATOR:-}" | grep -qi "kitty\|alacritty\|wezterm"; then
            has_nerd_font=true
        fi
    fi

    # 方法 4: 检查终端能力（尝试打印 Nerd Font 图标）
    if command -v tput &> /dev/null; then
        local cols=$(tput cols 2>/dev/null || echo 80)
        if [[ $cols -gt 80 ]]; then
            # 宽终端更可能支持 Nerd Font
            has_nerd_font=true
        fi
    fi

    # 方法 5: 检查 LC_CTYPE 是否支持 UTF-8
    if [[ "${LC_ALL:-${LC_CTYPE:-}}" =~ UTF-8 ]]; then
        has_nerd_font=true
    fi

    $has_nerd_font && return 0 || return 1
}

# 初始化图标系统
# 根据检测到的环境设置合适的图标
init_icons() {
    if detect_nerd_font; then
        USE_NERD_FONT=true
        # Nerd Font 图标
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
        # ASCII 图标（默认）
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
# 输出格式化工具（支持中文字符宽度）
# ============================================================================

# 计算字符串的显示宽度（中文字符按2个宽度计算）
# @param str 输入字符串
# @return 显示宽度
string_display_width() {
    local str="$1"
    local width=0
    local i=0
    local len=${#str}
    local in_escape=false

    while [[ $i -lt $len ]]; do
        local char="${str:$i:1}"

        # 检测 ANSI 转义序列开始
        if [[ "$char" == $'\033' ]] || [[ "$char" == $'\e' ]]; then
            in_escape=true
            ((i++))
            continue
        fi

        # 在转义序列中，检查是否结束
        if [[ "$in_escape" == true ]]; then
            # 转义序列以 [m 结束（颜色代码）
            if [[ "$char" == "m" ]]; then
                in_escape=false
            fi
            ((i++))
            continue
        fi

        # 计算可见字符宽度
        # 检查是否为多字节字符（中文字符等）
        if [[ $(printf '%s' "$char" | wc -m) -gt 1 ]] || [[ $(printf '%s' "$char" | wc -c) -gt 1 ]]; then
            # 多字节字符通常占用2个显示宽度
            ((width += 2))
        else
            # 单字节字符占用1个显示宽度
            ((width += 1))
        fi
        ((i++))
    done

    echo $width
}

# 左对齐字符串到指定宽度（考虑中文字符宽度）
# @param str 输入字符串
# @param width 目标宽度
# @return 填充后的字符串
pad_left() {
    local str="$1"
    local width=$2
    local current_width=$(string_display_width "$str")
    local padding=$((width - current_width))

    if [[ $padding -gt 0 ]]; then
        printf '%s%*s' "$str" $padding ''
    else
        printf '%s' "$str"
    fi
}

# 右对齐字符串到指定宽度（考虑中文字符宽度）
# @param str 输入字符串
# @param width 目标宽度
# @return 填充后的字符串
pad_right() {
    local str="$1"
    local width=$2
    local current_width=$(string_display_width "$str")
    local padding=$((width - current_width))

    if [[ $padding -gt 0 ]]; then
        printf '%*s%s' $padding '' "$str"
    else
        printf '%s' "$str"
    fi
}

# 居中对齐字符串到指定宽度（考虑中文字符宽度）
# @param str 输入字符串
# @param width 目标宽度
# @return 填充后的字符串
pad_center() {
    local str="$1"
    local width=$2
    local current_width=$(string_display_width "$str")
    local padding=$((width - current_width))

    if [[ $padding -gt 0 ]]; then
        local left_pad=$((padding / 2))
        local right_pad=$((padding - left_pad))
        printf '%*s%s%*s' $left_pad '' "$str" $right_pad ''
    else
        printf '%s' "$str"
    fi
}


# ============================================================================
# 工具函数
# ============================================================================

# 日志记录函数
# @param level 日志级别 (info/warn/error/debug)
# @param message 日志消息
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

    # 写入日志文件
    if [[ -d "$LOG_DIR" ]]; then
        echo "${timestamp}${prefix} ${message}" >> "$LOG_DIR/zpanel_$(date +%Y%m%d).log"
    fi
}

# 暂停等待用户输入
pause() {
    echo -ne "${CYAN}按 Enter 继续...${NC}"
    read -r
}

# 确认对话框
# @param message 提示消息
# @param default 默认值 (Y/N)
# @return 0 表示确认，1 表示拒绝
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
# 工具检查函数
# ============================================================================

# 检查命令是否存在
# @param cmd 命令名称
# @return 0 表示存在，1 表示不存在
check_command() {
    local cmd=$1
    if ! command -v "$cmd" &> /dev/null; then
        log error "缺少必需命令: $cmd"
        return 1
    fi
    return 0
}

# 检查脚本依赖
# @return 0 表示所有依赖都已满足，1 表示缺少依赖
check_dependencies() {
    local missing=()

    for cmd in awk sed grep; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log error "缺少必需命令: ${missing[*]}"
        return 1
    fi

    return 0
}

# ============================================================================
# 缓存管理
# ============================================================================

# 更新内存信息缓存
# 减少系统调用次数，提高性能
update_cache() {
    local current_time=$(date +%s)
    local cache_age=$((current_time - CACHE_LAST_UPDATE))

    # 如果缓存未过期，直接返回
    if [[ $cache_age -lt $CACHE_TTL ]]; then
        return 0
    fi

    # 一次性获取所有内存信息，避免重复调用free
    local mem_info=$(free -m | awk '/^Mem:/ {print $2, $3, $7, $6}')
    local swap_info=$(free -m | awk '/Swap:/ {print $2, $3}')

    read -r CACHE_MEM_TOTAL CACHE_MEM_USED CACHE_MEM_AVAIL CACHE_BUFF_CACHE <<< "$mem_info"
    read -r CACHE_SWAP_TOTAL CACHE_SWAP_USED <<< "$swap_info"
    CACHE_LAST_UPDATE=$current_time
}

# 清空内存信息缓存
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
# 内存信息获取（统一接口）
# ============================================================================

# 获取内存信息
# @param use_cache 是否使用缓存 (true/false)
# @return 输出格式: "total used avail buff_cache" (单位: MB)
get_memory_info() {
    local use_cache=${1:-true}

    if [[ "$use_cache" == "true" ]]; then
        update_cache
        echo "$CACHE_MEM_TOTAL $CACHE_MEM_USED $CACHE_MEM_AVAIL $CACHE_BUFF_CACHE"
    else
        free -m | awk '/^Mem:/ {print $2, $3, $7, $6}'
    fi
}

# 获取交换分区信息
# @param use_cache 是否使用缓存 (true/false)
# @return 输出格式: "total used" (单位: MB)
get_swap_info() {
    local use_cache=${1:-true}

    if [[ "$use_cache" == "true" ]]; then
        update_cache
        echo "$CACHE_SWAP_TOTAL $CACHE_SWAP_USED"
    else
        free -m | awk '/Swap:/ {print $2, $3}'
    fi
}

# 获取 ZRAM 使用情况
# @return 输出格式: "total used" (单位: MB)
get_zram_usage() {
    if ! is_zram_enabled; then
        echo "0 0"
        return
    fi

    # 统一转换为MB单位
    local zram_total=$(swapon --show=SIZE --noheadings 2>/dev/null | grep zram | awk '{
        size = $1
        unit = substr($1, length($1))
        num = substr($1, 1, length($1)-1)
        if (unit == "G" || unit == "Gi") print num * 1024
        else if (unit == "M" || unit == "Mi") print num
        else if (unit == "K" || unit == "Ki") print num / 1024
        else print num / 1048576
    }' | head -1)

    local zram_used=$(swapon --show=USED --noheadings 2>/dev/null | grep zram | awk '{
        size = $1
        unit = substr($1, length($1))
        num = substr($1, 1, length($1)-1)
        if (unit == "G" || unit == "Gi") print num * 1024
        else if (unit == "M" || unit == "Mi") print num
        else if (unit == "K" || unit == "Ki") print num / 1024
        else print num / 1048576
    }' | head -1)

    [[ -z "$zram_total" || "$zram_total" == "0" ]] && zram_total=1
    [[ -z "$zram_used" ]] && zram_used=0

    echo "$zram_total $zram_used"
}

# ============================================================================
# 安全的配置加载
# ============================================================================

# 安全地加载配置文件
# 防止命令注入和恶意代码执行
# @param file 配置文件路径
# @return 0 表示成功，1 表示失败
safe_source() {
    local file=$1
    local pattern='^[A-Z_][A-Z0-9_]*='

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    # 更严格的验证：只允许变量赋值和注释
    if ! grep -qE "^($pattern|#.*$|$)" "$file"; then
        log error "配置文件包含不安全内容: $file"
        return 1
    fi

    # 检查是否有命令执行、重定向等危险操作
    if grep -qE '[`$()]|\$\(.*\)|>|<|&|;' "$file"; then
        log error "配置文件包含危险字符: $file"
        return 1
    fi

    # 在子shell中source，隔离变量
    (
        source "$file"
    )

    return 0
}

# ============================================================================
# 安全的百分比计算函数
# ============================================================================

# 安全地计算百分比
# 防止除零错误
# @param used 已使用量
# @param total 总量
# @return 百分比值 (0-100)
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

# ============================================================================
# ZRAM设备管理函数
# ============================================================================

# 获取可用的 ZRAM 设备
# 优先使用未启用的设备，如果没有则创建新设备
# @return 设备名称 (如: zram0)
get_available_zram_device() {
    # 返回缓存的设备（如果存在）
    if [[ -n "$_ZRAM_DEVICE_CACHE" ]]; then
        echo "$_ZRAM_DEVICE_CACHE"
        return 0
    fi

    # 查找可用的zram设备
    for i in {0..15}; do
        if [[ -e "/sys/block/zram$i" ]] && ! swapon --show=NAME | grep -q "zram$i"; then
            _ZRAM_DEVICE_CACHE="zram$i"
            echo "zram$i"
            return 0
        fi
    done

    # 如果没有可用设备，尝试创建新设备
    if [[ -e /sys/class/zram-control/hot_add ]]; then
        local device_num=$(cat /sys/class/zram-control/hot_add)
        _ZRAM_DEVICE_CACHE="zram$device_num"
        echo "zram$device_num"
        return 0
    fi

    return 1
}

# 检查 ZRAM 是否已启用
# 使用缓存避免重复的系统调用
# @return 0 表示已启用，1 表示未启用
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

# 清空 ZRAM 状态缓存
# 在 ZRAM 状态改变后调用此函数
clear_zram_cache() {
    _ZRAM_ENABLED_CACHE=""
    _ZRAM_DEVICE_CACHE=""
}

# ============================================================================
# 进度条和图表显示模块
# ============================================================================

# 显示进度条
# @param current 当前进度
# @param total 总进度
# @param width 进度条宽度 (默认: 40)
# @param label 进度条标签
show_progress_bar() {
    local current=$1
    local total=$2
    local width=${3:-40}
    local label=${4:-""}

    [[ -z "$label" ]] || echo -ne "${WHITE}$label${NC} "

    # 防止除零错误
    [[ "$total" -eq 0 ]] && total=1
    [[ "$current" -gt "$total" ]] && current=$total

    local filled=$((current * width / total)) || true
    local empty=$((width - filled)) || true
    local percent=$((current * 100 / total)) || true

    # 更现代的进度条样式
    local bar_color="$GREEN"
    if [[ $percent -ge $PROGRESS_THRESHOLD_CRITICAL ]]; then
        bar_color="$RED"
    elif [[ $percent -ge $PROGRESS_THRESHOLD_HIGH ]]; then
        bar_color="$YELLOW"
    elif [[ $percent -ge $PROGRESS_THRESHOLD_MEDIUM ]]; then
        bar_color="$CYAN"
    fi

    # 使用实心方块字符
    echo -ne "${WHITE}[${NC}"
    local filled_bar=$(printf "%${filled}s" '' | tr ' ' '█')
    local empty_bar=$(printf "%${empty}s" '' | tr ' ' '░')
    echo -ne "${bar_color}${filled_bar}${NC}${WHITE}${empty_bar}${NC}]${NC} "

    # 百分比带颜色
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

# 显示压缩比图表
# @param ratio 压缩比
# @param width 图表宽度 (默认: 30)
show_compression_chart() {
    local ratio=$1
    local width=${2:-30}

    # 更美观的压缩比显示
    local filled=0
    local bar_color="$GREEN"

    # 使用 awk 进行浮点数比较
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

    # 显示标签
    echo -ne "${CYAN}压缩比: ${ratio}x ${NC}"

    # 使用更现代的样式
    echo -ne "${WHITE}[${NC}"
    local filled_bar=$(printf "%${filled}s" '' | tr ' ' '█')
    local empty_bar=$(printf "%${empty}s" '' | tr ' ' '░')
    echo -e "${bar_color}${filled_bar}${NC}${WHITE}${empty_bar}${NC}]${NC}"
}

# 显示内存使用饼图
# @param mem_used 已使用内存 (MB)
# @param mem_total 总内存 (MB)
show_memory_pie() {
    local mem_used=$1
    local mem_total=$2
    local mem_avail=$((mem_total - mem_used)) || true
    local used_percent=$((mem_used * 100 / mem_total)) || true
    local avail_percent=$((100 - used_percent)) || true

    echo -e "  ${YELLOW}■${NC} 已用: ${mem_used}MB (${YELLOW}${used_percent}%${NC})"
    echo -e "  ${GREEN}■${NC} 可用: ${mem_avail}MB (${GREEN}${avail_percent}%${NC})"
    echo -e "  ${WHITE}■${NC} 总量: ${mem_total}MB"
}

# ============================================================================
# 日志管理模块
# ============================================================================

# 加载日志配置
load_log_config() {
    if [[ -f "$LOG_CONFIG_FILE" ]]; then
        safe_source "$LOG_CONFIG_FILE" || true
    fi
}

# 保存日志配置
save_log_config() {
    # 验证参数
    [[ ! "$LOG_MAX_SIZE_MB" =~ ^[0-9]+$ ]] && LOG_MAX_SIZE_MB=50
    [[ ! "$LOG_RETENTION_DAYS" =~ ^[0-9]+$ ]] && LOG_RETENTION_DAYS=30

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
}

# 日志管理菜单
log_config_menu() {
    load_log_config

    while true; do
        clear

        echo -e "${CYAN}┌─────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│${WHITE}$(pad_center "日志管理" 57)${CYAN}│${NC}"
        echo -e "${CYAN}├─────────────────────────────────────────────────────────┤${NC}"
        echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"
        echo -e "${CYAN}│${WHITE}$(pad_left "  当前配置:" 57)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  最大日志大小: ${GREEN}${LOG_MAX_SIZE_MB}MB${NC}$(pad_left "" 29)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  日志保留天数: ${GREEN}${LOG_RETENTION_DAYS}天${NC}$(pad_left "" 28)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"
        echo -e "${CYAN}│${WHITE}$(pad_left "  操作选项:" 57)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}1.${NC} 设置最大日志大小$(pad_left "" 33)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}2.${NC} 设置日志保留天数$(pad_left "" 33)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}3.${NC} 查看日志文件列表$(pad_left "" 31)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}4.${NC} 查看运行日志（分页）$(pad_left "" 28)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}5.${NC} 查看动态调整日志（分页）$(pad_left "" 24)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}6.${NC} 清理过期日志$(pad_left "" 36)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}0.${NC} 返回$(pad_left "" 46)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"
        echo -e "${CYAN}└─────────────────────────────────────────────────────────┘${NC}"
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
                echo -e "${CYAN}┌─────────────────────────────────────────────────────────┐${NC}"
                echo -e "${CYAN}│${WHITE}              日志文件列表${CYAN}                              │${NC}"
                echo -e "${CYAN}├─────────────────────────────────────────────────────────┤${NC}"
                echo -e "${CYAN}│${NC}                                                         ${CYAN}│${NC}"

                if [[ -d "$LOG_DIR" ]]; then
                    echo -e "${CYAN}│${WHITE}  ZPanel 日志:${CYAN}                                             ${CYAN}│${NC}"
                    echo -e "${CYAN}│${NC}                                                         ${CYAN}│${NC}"
                    shopt -s nullglob
                    for log in "$LOG_DIR"/zpanel_*.log; do
                        [[ -f "$log" ]] && {
                            local size=$(du -h "$log" | cut -f1)
                            # 使用更兼容的方式获取文件修改时间
                            local mtime
                            if stat -c %y "$log" &>/dev/null; then
                                mtime=$(stat -c %y "$log" 2>/dev/null | cut -d' ' -f1-2)
                            else
                                mtime=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$log" 2>/dev/null || date -r "$log" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "未知")
                            fi
                            local name=$(basename "$log")
                            echo -e "${CYAN}│${NC}  ${GREEN}•${NC} ${name}  ${CYAN}|${NC} ${size}  ${CYAN}|${NC} ${mtime}${CYAN}│${NC}"
                        }
                    done
                    shopt -u nullglob

                    echo -e "${CYAN}│${NC}                                                         ${CYAN}│${NC}"
                    echo -e "${CYAN}│${WHITE}  动态调整日志:${CYAN}                                             ${CYAN}│${NC}"
                    echo -e "${CYAN}│${NC}                                                         ${CYAN}│${NC}"
                    if [[ -f "$LOG_DIR/dynamic.log" ]]; then
                        local size=$(du -h "$LOG_DIR/dynamic.log" | cut -f1)
                        # 使用更兼容的方式获取文件修改时间
                        local mtime
                        if stat -c %y "$LOG_DIR/dynamic.log" &>/dev/null; then
                            mtime=$(stat -c %y "$LOG_DIR/dynamic.log" 2>/dev/null | cut -d' ' -f1-2)
                        else
                            mtime=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$LOG_DIR/dynamic.log" 2>/dev/null || date -r "$LOG_DIR/dynamic.log" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "未知")
                        fi
                        echo -e "${CYAN}│${NC}  ${GREEN}•${NC} dynamic.log  ${CYAN}|${NC} ${size}  ${CYAN}|${NC} ${mtime}${CYAN}│${NC}"
                    fi
                else
                    echo -e "${CYAN}│${YELLOW}  暂无日志文件${CYAN}                                              ${CYAN}│${NC}"
                fi

                echo -e "${CYAN}│${NC}                                                         ${CYAN}│${NC}"
                echo -e "${CYAN}└─────────────────────────────────────────────────────────┘${NC}"
                echo ""
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

# 分页查看日志
# @param log_type 日志类型 (zpanel/dynamic)
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

        echo -e "${CYAN}┌─────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│${WHITE}         日志查看: $(basename "$log_file")${CYAN}                     │${NC}"
        echo -e "${CYAN}├─────────────────────────────────────────────────────────┤${NC}"
        echo -e "${CYAN}│${NC}                                                         ${CYAN}│${NC}"
        echo -e "${CYAN}│${WHITE}  页码: ${GREEN}${page}${NC}${WHITE}/$(( (total_lines + lines - 1) / lines ))${NC}  ${WHITE}总行数: ${GREEN}${total_lines}${NC}          ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}                                                         ${CYAN}│${NC}"

        local start=$(( (page - 1) * lines + 1 ))
        local end=$((page * lines))

        sed -n "${start},${end}p" "$log_file" | while IFS= read -r line; do
            echo -e "${CYAN}│${NC}  ${line}${CYAN}                                                │${NC}"
        done

        echo -e "${CYAN}│${NC}                                                         ${CYAN}│${NC}"
        echo -e "${CYAN}├─────────────────────────────────────────────────────────┤${NC}"
        echo -e "${CYAN}│${WHITE}  n - 下一页  p - 上一页  q - 退出${CYAN}                    │${NC}"
        echo -e "${CYAN}│${NC}                                                         ${CYAN}│${NC}"
        echo -e "${CYAN}└─────────────────────────────────────────────────────────┘${NC}"
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

# 轮转日志文件
# 当日志文件超过指定大小时，创建压缩备份
# @param log_file 日志文件路径
# @param max_size_mb 最大大小 (MB)
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

    # 轮转日志文件
    local log_dir=$(dirname "$log_file")
    local log_base=$(basename "$log_file" .log)
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local archive_file="${log_dir}/${log_base}_${timestamp}.log"

    # 创建压缩备份
    if mv "$log_file" "$archive_file" && gzip "$archive_file"; then
        log info "日志已轮转: $(basename "$log_file") -> $(basename "$archive_file").gz"
    else
        log warn "日志轮转失败: $(basename "$log_file")"
    fi
}

clean_old_logs() {
    local cleaned=0

    for log in "$LOG_DIR"/zpanel_*.log; do
        if [[ -f "$log" ]]; then
            local log_date=$(basename "$log" | sed 's/zpanel_//' | sed 's/\.log//')
            # 使用更兼容的方式计算日志天数
            local log_age
            if date -d "$log_date" +%s &>/dev/null; then
                log_age=$(( ( $(date +%s) - $(date -d "$log_date" +%s) ) / 86400 )) || true
            else
                # 如果 date -d 不支持，使用文件修改时间
                local file_mtime
                if stat -c %Y "$log" &>/dev/null; then
                    file_mtime=$(stat -c %Y "$log")
                else
                    file_mtime=$(stat -f "%m" "$log")
                fi
                log_age=$(( ( $(date +%s) - file_mtime ) / 86400 )) || true
            fi

            if [[ $log_age -gt $LOG_RETENTION_DAYS ]]; then
                # 验证 log_age 是有效数字
                [[ "$log_age" =~ ^[0-9]+$ ]] || continue
                rm -f "$log" && {
                    ((cleaned++))
                    log info "删除过期日志: $(basename "$log")"
                } || log warn "删除失败: $(basename "$log")"
            fi
        fi
    done

    for log in "$LOG_DIR"/*.log; do
        if [[ -f "$log" ]]; then
            local size_mb=$(du -m "$log" | cut -f1)
            if [[ $size_mb -gt $LOG_MAX_SIZE_MB ]]; then
                # 使用 mktemp 创建安全的临时文件
                local temp_file
                temp_file=$(mktemp "${log}.tmp.XXXXXX") || {
                    log warn "无法创建临时文件: $(basename "$log")"
                    continue
                }

                if tail -1000 "$log" > "$temp_file" && mv "$temp_file" "$log"; then
                    ((cleaned++))
                    log info "截断过大日志: $(basename "$log")"
                else
                    rm -f "$temp_file"
                    log warn "截断失败: $(basename "$log")"
                fi
            fi
        fi
    done

    echo "清理完成，共处理 $cleaned 个日志文件"
}

# ============================================================================
# 系统检测模块
# ============================================================================

detect_system() {
    log info "检测系统信息..."

    if [[ -f /etc/os-release ]]; then
        # 使用 grep 提取信息，避免 source 导致的变量冲突
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

    # 验证内存信息
    TOTAL_MEMORY_MB=$(free -m | awk '/^Mem:/ {print $2}')
    if [[ -z "$TOTAL_MEMORY_MB" || "$TOTAL_MEMORY_MB" -lt 1 ]]; then
        log error "无法获取内存信息"
        exit 1
    fi

    # 验证 CPU 核心数
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
# 备份与回滚模块
# ============================================================================

create_backup() {
    log info "创建系统备份..."

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="$BACKUP_DIR/backup_$timestamp"

    if ! mkdir -p "$backup_path"; then
        log error "无法创建备份目录: $backup_path"
        return 1
    fi

    # 设置备份目录权限：仅允许 root 读写
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
EOF

    # 设置备份信息文件权限
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
                    # 创建原文件的备份
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
# 智能压缩算法检测模块
# ============================================================================

detect_best_algorithm() {
    log info "检测最优压缩算法..."

    local cpu_flags=$(cat /proc/cpuinfo | grep -m1 "flags" | sed 's/flags://')

    # ZRAM 实时压缩场景：速度优先，CPU 占用低
    local algorithms=("lz4" "lzo" "zstd")
    local best_algo="lzo"
    local best_score=0

    for algo in "${algorithms[@]}"; do
        local score=0

        case $algo in
            lz4)
                # lz4 速度极快，CPU 占用低，适合 ZRAM 实时压缩
                score=100
                ;;
            lzo)
                # lzo 兼容性最好，速度较快
                score=90
                ;;
            zstd)
                # zstd 压缩比高但 CPU 占用大，不推荐用于 ZRAM
                # 仅在 CPU 支持 AVX2 时考虑使用
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

# ============================================================================
# 分级策略引擎
# ============================================================================

load_strategy_config() {
    if [[ -f "$STRATEGY_CONFIG_FILE" ]]; then
        safe_source "$STRATEGY_CONFIG_FILE" || STRATEGY_MODE="balance"
    else
        STRATEGY_MODE="balance"
    fi
}

save_strategy_config() {
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
}

calculate_strategy() {
    local mode=$1

    local zram_ratio phys_limit swap_size swappiness dirty_ratio min_free

    case $mode in
        conservative)
            # 保守模式：优先稳定性
            zram_ratio=80
            phys_limit=$((TOTAL_MEMORY_MB * 40 / 100)) || true
            swap_size=$((TOTAL_MEMORY_MB * 100 / 100)) || true
            swappiness=60
            dirty_ratio=5
            min_free=65536
            ;;
        balance)
            # 平衡模式：默认选项
            zram_ratio=120
            phys_limit=$((TOTAL_MEMORY_MB * 50 / 100)) || true
            swap_size=$((TOTAL_MEMORY_MB * 150 / 100)) || true
            swappiness=85
            dirty_ratio=10
            min_free=32768
            ;;
        aggressive)
            # 激进模式：最大化利用
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

# ============================================================================
# ZRAM 配置模块
# ============================================================================

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

    local name=$(echo "$zram_info" | awk '{print $1}')
    local disk_size=$(echo "$zram_info" | awk '{print $2}')
    local data_size=$(echo "$zram_info" | awk '{print $3}')
    local comp_size=$(echo "$zram_info" | awk '{print $4}')
    local algo=$(echo "$zram_info" | awk '{print $5}')

    local compression_ratio="0"
    if [[ -n "$data_size" ]] && [[ -n "$comp_size" ]] && [[ "$comp_size" != "0" ]]; then
        local data_num=$(echo "$data_size" | sed 's/[KMGT]//g' | awk '{print $1*1}')
        local comp_num=$(echo "$comp_size" | sed 's/[KMGT]//g' | awk '{print $1*1}')
        if (( $(awk "BEGIN {print ($comp_num > 0)}") )) && (( $(awk "BEGIN {print ($data_num > 0)}") )); then
            compression_ratio=$(awk "BEGIN {printf \"%.2f\", $data_num / $comp_num}")
        fi
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

configure_zram() {
    local algorithm=${1:-"auto"}
    local mode=${2:-"$STRATEGY_MODE"}

    log info "开始配置 ZRAM (策略: $mode)..."

    # 验证模式
    if [[ "$mode" != "conservative" ]] && [[ "$mode" != "balance" ]] && [[ "$mode" != "aggressive" ]]; then
        log error "无效的策略模式: $mode"
        return 1
    fi

    if [[ "$algorithm" == "auto" ]]; then
        algorithm=$(detect_best_algorithm)
    fi

    read -r zram_ratio phys_limit swap_size swappiness dirty_ratio min_free <<< $(calculate_strategy "$mode")

    local zram_size=$((TOTAL_MEMORY_MB * zram_ratio / 100)) || true
    [[ $zram_size -lt 512 ]] && zram_size=512

    if ! command -v zramctl &> /dev/null; then
        log info "安装 zram-tools..."
        install_packages zram-tools zram-config zstd lz4 lzop || {
            log error "安装 zram-tools 失败"
            return 1
        }
    fi

    # 确保 ZRAM 模块已加载
    if ! lsmod | grep -q zram; then
        modprobe zram || {
            log error "无法加载 ZRAM 模块"
            return 1
        }
    fi

    # 获取或创建 ZRAM 设备
    local zram_device
    zram_device=$(get_available_zram_device) || {
        log error "无法获取可用的 ZRAM 设备"
        return 1
    }
    log info "使用 ZRAM 设备: $zram_device"

    # 停用已存在的 ZRAM swap
    if swapon --show=NAME --noheadings 2>/dev/null | grep -q zram; then
        for device in $(swapon --show=NAME --noheadings 2>/dev/null | grep zram); do
            swapoff "$device" 2>/dev/null || true
        done
    fi

    # 重置 ZRAM 设备
    if [[ -e "/sys/block/$zram_device/reset" ]]; then
        echo 1 > "/sys/block/$zram_device/reset" 2>/dev/null || true
        sleep 0.3
    fi

    # 检查设备路径是否存在
    if [[ ! -e "/dev/$zram_device" ]]; then
        log error "ZRAM 设备不存在: /dev/$zram_device"
        return 1
    fi

    # 设置压缩算法
    if [[ -e "/sys/block/$zram_device/comp_algorithm" ]]; then
        local supported=$(cat "/sys/block/$zram_device/comp_algorithm" 2>/dev/null)
        if echo "$supported" | grep -q "$algorithm"; then
            echo "$algorithm" > "/sys/block/$zram_device/comp_algorithm" 2>/dev/null || {
                log warn "设置压缩算法失败，使用默认算法"
            }
            log info "设置压缩算法: $algorithm"
        else
            # 修复正则表达式，避免 grep "Invalid range end" 错误
            # 使用 sed 替代 grep -oE 以提高兼容性
            local fallback=$(echo "$supported" | sed -n 's/.*\[\([^]]*\)\].*/\1/p' | head -1)
            [[ -z "$fallback" ]] && fallback="lzo"
            echo "$fallback" > "/sys/block/$zram_device/comp_algorithm" 2>/dev/null || true
            algorithm="$fallback"
            log info "使用回退算法: $algorithm"
        fi
    fi

    # 设置压缩流数
    if [[ -e "/sys/block/$zram_device/max_comp_streams" ]]; then
        echo "$CPU_CORES" > "/sys/block/$zram_device/max_comp_streams" 2>/dev/null || true
        log info "设置压缩流数: $CPU_CORES"
    fi

    # 设置 ZRAM 大小
    local zram_bytes=$((zram_size * 1024 * 1024)) || true
    echo "$zram_bytes" > "/sys/block/$zram_device/disksize" 2>/dev/null || {
        log error "设置 ZRAM 大小失败"
        log error "设备: /sys/block/$zram_device/disksize"
        return 1
    }

    # 物理内存熔断
    if [[ -e "/sys/block/$zram_device/mem_limit" ]]; then
        local phys_limit_bytes=$((phys_limit * 1024 * 1024)) || true
        echo "$phys_limit_bytes" > "/sys/block/$zram_device/mem_limit" 2>/dev/null || true
        log info "已启用物理内存熔断保护 (Limit: ${phys_limit}MB)"
    fi

    # 格式化 ZRAM 设备为 swap
    mkswap "/dev/$zram_device" > /dev/null 2>&1 || {
        log error "格式化 ZRAM 失败"
        log error "设备: /dev/$zram_device"
        return 1
    }

    # 启用 ZRAM swap
    swapon -p 100 "/dev/$zram_device" > /dev/null 2>&1 || {
        log error "启用 ZRAM 失败"
        log error "设备: /dev/$zram_device"
        return 1
    }

    if ! mkdir -p "$CONF_DIR"; then
        log error "无法创建配置目录: $CONF_DIR"
        return 1
    fi

    # 设置配置目录权限：仅允许 root 读写
    chmod 700 "$CONF_DIR" 2>/dev/null || true

    cat > "$ZRAM_CONFIG_FILE" <<'EOF'
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

    # 设置配置文件权限：仅允许 root 读写
    chmod 600 "$ZRAM_CONFIG_FILE" 2>/dev/null || true

    create_zram_service || {
        log warn "创建 ZRAM 服务失败"
    }

    ZRAM_ENABLED=true
    log info "ZRAM 配置成功: $algorithm, ${zram_size}MB, 优先级 100"

    return 0
}

create_zram_service() {
    log info "创建 ZRAM 持久化服务..."

    cat > "$INSTALL_DIR/zram-start.sh" <<'EOF'
#!/bin/bash
set -e
CONF_DIR="/opt/z-panel/conf"
LOG_DIR="/opt/z-panel/logs"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_DIR/zram-service.log" 2>/dev/null || true
}

# 安全的配置加载函数（与主脚本保持一致）
safe_source() {
    local file=$1
    local pattern='^[A-Z_][A-Z0-9_]*='

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    # 验证文件内容只包含安全的赋值语句
    if grep -vE "^(#|$pattern)" "$file" | grep -q '[^[:space:]]'; then
        log "配置文件包含不安全内容: $file"
        return 1
    fi

    source "$file"
    return 0
}

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

    # 物理内存熔断
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

# 应用内核参数
if [[ -f "$CONF_DIR/kernel.conf" ]]; then
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^# ]] && continue
        [[ -z "$key" ]] && continue
        sysctl -w "$key=$value" > /dev/null 2>&1 || log "设置 $key 失败"
    done < "$CONF_DIR/kernel.conf"
fi
EOF

    # 设置启动脚本权限：仅允许 root 执行
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

        # 设置 systemd 服务文件权限：仅允许 root 读写
        chmod 644 /etc/systemd/system/zram.service 2>/dev/null || true

        systemctl daemon-reload > /dev/null 2>&1
        systemctl enable zram.service > /dev/null 2>&1
        log info "systemd 服务已创建"
    fi
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
# 虚拟内存智能管理模块
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

    # 安全地处理 PID 列表，避免命令注入和路径遍历风险
    local pids
    pids=$(pgrep sshd 2>/dev/null) || pids=""

    if [[ -n "$pids" ]]; then
        while IFS= read -r pid; do
            # 验证 PID 是否为有效的数字
            if [[ "$pid" =~ ^[0-9]+$ ]] && [[ -d "/proc/$pid" ]]; then
                echo -1000 > "/proc/$pid/oom_score_adj" 2>/dev/null || true
            fi
        done <<< "$pids"
    fi

    pids=$(pgrep systemd 2>/dev/null) || pids=""

    if [[ -n "$pids" ]]; then
        while IFS= read -r pid; do
            # 验证 PID 是否为有效的数字
            if [[ "$pid" =~ ^[0-9]+$ ]] && [[ -d "/proc/$pid" ]]; then
                echo -1000 > "/proc/$pid/oom_score_adj" 2>/dev/null || true
            fi
        done <<< "$pids"
    fi

    log info "OOM 保护已启用 (SSH, systemd)"
}

configure_virtual_memory() {
    local mode=${1:-"$STRATEGY_MODE"}

    log info "配置虚拟内存策略 (策略: $mode)..."

    read -r zram_ratio phys_limit swap_size swappiness dirty_ratio min_free <<< $(calculate_strategy "$mode")

    # 使用缓存获取内存信息
    read -r mem_total _ _ _ <<< $(get_memory_info false)
    read -r swap_total swap_used <<< $(get_swap_info false)

    local swap_usage=0
    [[ $swap_total -gt 0 ]] && swap_usage=$((swap_used * 100 / swap_total)) || true

    # 使用缓存获取 ZRAM 信息
    read -r zram_total zram_used <<< $(get_zram_usage)
    local zram_usage=0
    if [[ $zram_total -gt 0 ]]; then
        zram_usage=$((zram_used * 100 / zram_total)) || true
    fi

    # 动态调整 swappiness
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

    log info "内存: ${mem_total}MB, Swap使用: ${swap_usage}%, ZRAM使用: ${zram_usage}%"
    log info "建议 swappiness: $swappiness"

    mkdir -p "$CONF_DIR"

    # 设置配置目录权限：仅允许 root 读写
    chmod 700 "$CONF_DIR" 2>/dev/null || true

    cat > "$KERNEL_CONFIG_FILE" <<'EOF'
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

    # 设置内核配置文件权限：仅允许 root 读写
    chmod 600 "$KERNEL_CONFIG_FILE" 2>/dev/null || true

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

    apply_io_fuse_protection "$dirty_ratio"
    apply_oom_protection

    log info "虚拟内存配置完成"
}

# ============================================================================
# 动态调整模块
# ============================================================================

enable_dynamic_mode() {
    log info "启用动态调整模式..."

    cat > "$INSTALL_DIR/dynamic-adjust.sh" <<'EOF'
#!/bin/bash
set -e
CONF_DIR="/opt/z-panel/conf"
LOG_DIR="/opt/z-panel/logs"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_DIR/dynamic-adjust.log" 2>/dev/null || true
}

# 统一的内存信息获取函数（使用缓存）
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

if [[ -f "$CONF_DIR/strategy.conf" ]]; then
    source "$CONF_DIR/strategy.conf"
else
    STRATEGY_MODE="balance"
fi

# 使用统一的函数获取内存信息
read -r mem_total mem_used mem_avail buff_cache <<< $(get_memory_info)
mem_percent=$((mem_used * 100 / mem_total)) || true

read -r swap_total swap_used <<< $(get_swap_info)
swap_usage=0
[[ $swap_total -gt 0 ]] && swap_usage=$((swap_used * 100 / swap_total)) || true

read -r zram_total zram_used <<< $(get_zram_usage)
zram_usage=0
[[ $zram_total -gt 0 ]] && zram_usage=$((zram_used * 100 / zram_total)) || true

# 计算最优 swappiness（与主脚本保持一致的逻辑）
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

    # 设置动态调整脚本权限：仅允许 root 执行
    chmod 700 "$INSTALL_DIR/dynamic-adjust.sh" 2>/dev/null || true

    # 安全的 crontab 操作：使用临时文件
    local cron_entry="*/5 * * * * $INSTALL_DIR/dynamic-adjust.sh"
    local cron_temp
    cron_temp=$(mktemp) || {
        log error "无法创建临时文件"
        return 1
    }

    # 获取当前 crontab 并过滤
    crontab -l 2>/dev/null | grep -v "dynamic-adjust.sh" > "$cron_temp" 2>/dev/null || true

    # 检查是否已存在
    if ! grep -q "dynamic-adjust.sh" "$cron_temp" 2>/dev/null; then
        echo "$cron_entry" >> "$cron_temp"
    fi

    # 安装新的 crontab
    crontab "$cron_temp" 2>/dev/null || {
        log error "crontab 安装失败"
        rm -f "$cron_temp"
        return 1
    }

    rm -f "$cron_temp"

    DYNAMIC_MODE=true
    log info "动态调整模式已启用 (每 5 分钟检查)"
}

disable_dynamic_mode() {
    log info "停用动态调整模式..."

    # 安全的 crontab 操作：使用临时文件
    local cron_temp
    cron_temp=$(mktemp) || {
        log error "无法创建临时文件"
        return 1
    }

    # 获取当前 crontab 并过滤掉 dynamic-adjust.sh
    crontab -l 2>/dev/null | grep -v "dynamic-adjust.sh" > "$cron_temp" 2>/dev/null || true

    # 安装新的 crontab
    crontab "$cron_temp" 2>/dev/null || {
        log error "crontab 更新失败"
        rm -f "$cron_temp"
        return 1
    }

    rm -f "$cron_temp"

    DYNAMIC_MODE=false
    log info "动态调整模式已停用"
}

# ============================================================================
# 增强监控面板模块
# ============================================================================

show_monitor() {
    clear

    # 捕获 Ctrl+C 信号
    trap 'return 0' INT

    while true; do
        clear

        # 顶部标题
        echo -e "${CYAN}┌─────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│${WHITE}       Z-Panel Pro 实时监控面板 v${SCRIPT_VERSION}${CYAN}                │${NC}"
        echo -e "${CYAN}├─────────────────────────────────────────────────────────┤${NC}"
        echo -e "${CYAN}│${WHITE}  内存: ${GREEN}${TOTAL_MEMORY_MB}MB${NC} ${WHITE}CPU: ${GREEN}${CPU_CORES}核心${NC} ${WHITE}模式: ${YELLOW}${STRATEGY_MODE}${CYAN}          │${NC}"
        echo -e "${CYAN}├─────────────────────────────────────────────────────────┤${NC}"
        echo -e "${CYAN}│${NC}                                                         ${CYAN}│${NC}"

        # 使用缓存获取内存信息
        read -r mem_total mem_used mem_avail buff_cache <<< $(get_memory_info true)

        echo -e "${CYAN}│${WHITE}  📊 RAM 使用情况${CYAN}                                        │${NC}"
        echo -e "${CYAN}│${NC}                                                         ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  使用: ${GREEN}${mem_used}MB${NC}  缓存: ${CYAN}${buff_cache}MB${NC}  空闲: ${GREEN}${mem_avail}MB${NC}           ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}                                                         ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  物理内存负载:                                          ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  "
        show_progress_bar "$mem_used" "$mem_total" 46 ""
        echo -e "${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}                                                         ${CYAN}│${NC}"

        # ZRAM 状态
        echo -e "${CYAN}├─────────────────────────────────────────────────────────┤${NC}"

        if swapon --show=NAME --noheadings 2>/dev/null | grep -q zram; then
            echo -e "${CYAN}│${WHITE}  💾 ZRAM 状态: ${GREEN}运行中${CYAN}                                  │${NC}"
            echo -e "${CYAN}│${NC}                                                         ${CYAN}│${NC}"

            local zram_status=$(get_zram_status)
            local algo=$(echo "$zram_status" | grep -o '"algorithm":"[^"]*"' | cut -d'"' -f4)
            local ratio=$(echo "$zram_status" | grep -o '"compression_ratio":"[^"]*"' | cut -d'"' -f4)
            [[ -z "$ratio" || "$ratio" == "0" ]] && ratio="1.00"

            # 使用缓存获取 ZRAM 信息
            read -r zram_total_kb zram_used_kb <<< $(get_zram_usage)

            echo -e "${CYAN}│${NC}  算法: ${CYAN}${algo}${NC}  压缩比: ${YELLOW}${ratio}x${NC}                              ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}                                                         ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}  ZRAM 压缩比:                                            ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}  "
            show_compression_chart "$ratio" 46
            echo -e "${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}                                                         ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}  ZRAM 负载:                                               ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}  "
            show_progress_bar "$zram_used_kb" "$zram_total_kb" 46 ""
            echo -e "${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}                                                         ${CYAN}│${NC}"
        else
            echo -e "${CYAN}│${WHITE}  💾 ZRAM 状态: ${RED}未启用${CYAN}                                      │${NC}"
            echo -e "${CYAN}│${NC}                                                         ${CYAN}│${NC}"
        fi

        # Swap 状态
        echo -e "${CYAN}├─────────────────────────────────────────────────────────┤${NC}"

        # 使用缓存获取 Swap 信息
        read -r swap_total swap_used <<< $(get_swap_info true)

        if [[ $swap_total -gt 0 ]]; then
            echo -e "${CYAN}│${WHITE}  🔄 Swap 负载:                                              ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}                                                         ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}  "
            show_progress_bar "$swap_used" "$swap_total" 46 ""
            echo -e "${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}                                                         ${CYAN}│${NC}"
        else
            echo -e "${CYAN}│${WHITE}  🔄 Swap 状态: ${RED}未启用${CYAN}                                        │${NC}"
            echo -e "${CYAN}│${NC}                                                         ${CYAN}│${NC}"
        fi

        # 内核参数
        echo -e "${CYAN}├─────────────────────────────────────────────────────────┤${NC}"
        echo -e "${CYAN}│${WHITE}  ⚙️  内核参数${CYAN}                                               │${NC}"
        echo -e "${CYAN}│${NC}                                                         ${CYAN}│${NC}"

        local swappiness=$(sysctl -n vm.swappiness 2>/dev/null || echo "60")
        echo -e "${CYAN}│${NC}  swappiness:                                              ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  "
        show_progress_bar "$swappiness" 100 46 ""
        echo -e "${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}                                                         ${CYAN}│${NC}"

        # 底部提示
        echo -e "${CYAN}└─────────────────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "${YELLOW}💡 按 ${WHITE}Ctrl+C${YELLOW} 返回主菜单${NC}"
        echo ""

        sleep 3
    done

    # 恢复信号处理
    trap - INT
}

show_status() {
    clear

    echo -e "${CYAN}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${WHITE}$(pad_center "Z-Panel Pro 系统状态 v${SCRIPT_VERSION}" 57)${CYAN}│${NC}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"

    # 系统信息
    echo -e "${CYAN}│${WHITE}$(pad_left "  📋 系统信息" 57)${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  发行版: ${GREEN}${CURRENT_DISTRO} ${CURRENT_VERSION}${NC}$(pad_left "" 31)${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  内存: ${GREEN}${TOTAL_MEMORY_MB}MB${NC}  CPU: ${GREEN}${CPU_CORES}核心${NC}  策略: ${YELLOW}${STRATEGY_MODE}${NC}$(pad_left "" 8)${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"

    # ZRAM 状态
    echo -e "${CYAN}├─────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${WHITE}$(pad_left "  💾 ZRAM 状态" 57)${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"

    if swapon --show=NAME --noheadings 2>/dev/null | grep -q zram; then
        echo -e "${CYAN}│${NC}  状态: ${GREEN}运行中${NC}$(pad_left "" 45)${CYAN}│${NC}"

        local zram_status=$(get_zram_status)
        local disk_size=$(echo "$zram_status" | grep -o '"disk_size":"[^"]*"' | cut -d'"' -f4)
        local data_size=$(echo "$zram_status" | grep -o '"data_size":"[^"]*"' | cut -d'"' -f4)
        local comp_size=$(echo "$zram_status" | grep -o '"comp_size":"[^"]*"' | cut -d'"' -f4)
        local algo=$(echo "$zram_status" | grep -o '"algorithm":"[^"]*"' | cut -d'"' -f4)
        local ratio=$(echo "$zram_status" | grep -o '"compression_ratio":"[^"]*"' | cut -d'"' -f4)

        echo -e "${CYAN}│${NC}  算法: ${CYAN}${algo}${NC}  大小: ${CYAN}${disk_size}${NC}$(pad_left "" 30)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  数据: ${CYAN}${data_size}${NC}  压缩: ${CYAN}${comp_size}${NC}$(pad_left "" 28)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  压缩比:$(pad_left "" 48)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  "
        show_compression_chart "$ratio" 46
        echo -e "${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"
    else
        echo -e "${CYAN}│${NC}  状态: ${RED}未启用${NC}$(pad_left "" 45)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"
    fi

    # Swap 状态
    echo -e "${CYAN}├─────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${WHITE}$(pad_left "  🔄 Swap 状态" 57)${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"

    read -r swap_total swap_used <<< "$(get_swap_info false)"

    if [[ $swap_total -eq 0 ]]; then
        echo -e "${CYAN}│${NC}  状态: ${RED}未启用${NC}$(pad_left "" 45)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"
    else
        echo -e "${CYAN}│${NC}  总量: ${CYAN}${swap_total}MB${NC}  已用: ${CYAN}${swap_used}MB${NC}$(pad_left "" 25)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  Swap 负载:$(pad_left "" 44)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  "
        show_progress_bar "$swap_used" "$swap_total" 46 ""
        echo -e "${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"
    fi

    # 内核参数
    echo -e "${CYAN}├─────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${WHITE}$(pad_left "  ⚙️  内核参数" 57)${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"

    local swappiness=$(sysctl -n vm.swappiness 2>/dev/null || echo "60")
    local vfs_cache=$(sysctl -n vm.vfs_cache_pressure 2>/dev/null || echo "100")
    local dirty_ratio=$(sysctl -n vm.dirty_ratio 2>/dev/null || echo "20")

    echo -e "${CYAN}│${NC}  vm.swappiness:$(pad_left "" 42)${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  "
    show_progress_bar "$swappiness" 100 46 ""
    echo -e "${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"

    # 保护机制
    echo -e "${CYAN}├─────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${WHITE}$(pad_left "  🛡️  保护机制" 57)${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  ${GREEN}•${NC} I/O 熔断: ${GREEN}已启用${NC}$(pad_left "" 35)${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  ${GREEN}•${NC} OOM 保护: ${GREEN}已启用${NC}$(pad_left "" 36)${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  ${GREEN}•${NC} 物理内存熔断: ${GREEN}已启用${NC}$(pad_left "" 30)${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"

    echo -e "${CYAN}└─────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

# ============================================================================
# 菜单系统
# ============================================================================

show_main_menu() {
    clear

    # 顶部标题栏
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${WHITE}$(pad_center "Z-Panel Pro v${SCRIPT_VERSION} 主控菜单" 57)${CYAN}│${NC}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${WHITE}$(pad_left "系统: RAM:${TOTAL_MEMORY_MB}MB CPU:${CPU_CORES}Cores ${CURRENT_DISTRO} ${CURRENT_VERSION}" 57)${CYAN}│${NC}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"

    # 主要功能
    echo -e "${CYAN}│${WHITE}$(pad_left "🚀 主要功能" 57)${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"

    local item1="  ${GREEN}1.${NC} 一键优化[${YELLOW}当前: ${STRATEGY_MODE}${NC}]"
    echo -e "${CYAN}│${NC}${item1}$(pad_right "" $((57 - $(string_display_width "$item1"))))${CYAN}│${NC}"

    local item2="  ${GREEN}2.${NC} 状态监控"
    echo -e "${CYAN}│${NC}${item2}$(pad_right "" $((57 - $(string_display_width "$item2"))))${CYAN}│${NC}"

    local item3="  ${GREEN}3.${NC} 日志管理"
    echo -e "${CYAN}│${NC}${item3}$(pad_right "" $((57 - $(string_display_width "$item3"))))${CYAN}│${NC}"

    echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"

    # 高级功能
    echo -e "${CYAN}│${WHITE}$(pad_left "⚙️  高级功能" 57)${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"

    local item4="  ${GREEN}4.${NC} 切换优化模式[${YELLOW}保守/平衡/激进${NC}]"
    echo -e "${CYAN}│${NC}${item4}$(pad_right "" $((57 - $(string_display_width "$item4"))))${CYAN}│${NC}"

    local item5="  ${GREEN}5.${NC} 配置 ZRAM"
    echo -e "${CYAN}│${NC}${item5}$(pad_right "" $((57 - $(string_display_width "$item5"))))${CYAN}│${NC}"

    local item6="  ${GREEN}6.${NC} 配置虚拟内存"
    echo -e "${CYAN}│${NC}${item6}$(pad_right "" $((57 - $(string_display_width "$item6"))))${CYAN}│${NC}"

    local item7="  ${GREEN}7.${NC} 动态调整模式"
    echo -e "${CYAN}│${NC}${item7}$(pad_right "" $((57 - $(string_display_width "$item7"))))${CYAN}│${NC}"

    echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"

    # 系统管理
    echo -e "${CYAN}│${WHITE}$(pad_left "🛠️  系统管理" 57)${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"

    local item8="  ${GREEN}8.${NC} 查看系统状态"
    echo -e "${CYAN}│${NC}${item8}$(pad_right "" $((57 - $(string_display_width "$item8"))))${CYAN}│${NC}"

    local item9="  ${GREEN}9.${NC} 停用 ZRAM"
    echo -e "${CYAN}│${NC}${item9}$(pad_right "" $((57 - $(string_display_width "$item9"))))${CYAN}│${NC}"

    local item10="  ${GREEN}10.${NC} 还原备份"
    echo -e "${CYAN}│${NC}${item10}$(pad_right "" $((57 - $(string_display_width "$item10"))))${CYAN}│${NC}"

    local item0="  ${GREEN}0.${NC} 退出程序"
    echo -e "${CYAN}│${NC}${item0}$(pad_right "" $((57 - $(string_display_width "$item0"))))${CYAN}│${NC}"

    echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"

    # 状态栏
    echo -e "${CYAN}├─────────────────────────────────────────────────────────┤${NC}"
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
    local status_text="  ZRAM: ${zram_status}  │  动态: ${dynamic_status}"
    echo -e "${CYAN}│${NC}$(pad_center "$status_text" 57)${CYAN}│${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -ne "${WHITE}请选择 [0-10]: ${NC}"
}

strategy_menu() {
    while true; do
        clear

        echo -e "${CYAN}┌─────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│${WHITE}$(pad_center "选择优化模式" 57)${CYAN}│${NC}"
        echo -e "${CYAN}├─────────────────────────────────────────────────────────┤${NC}"
        echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}1.${NC} Conservative (保守)$(pad_left "" 31)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}     • 最稳定，适合路由器/NAS$(pad_left "" 30)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}     • ZRAM: 80% | Swap: 100% | Swappiness: 60$(pad_left "" 9)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}2.${NC} Balance (平衡)  ${YELLOW}[推荐]${NC}$(pad_left "" 26)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}     • 性能与稳定兼顾，日常使用$(pad_left "" 24)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}     • ZRAM: 120% | Swap: 150% | Swappiness: 85$(pad_left "" 8)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}3.${NC} Aggressive (激进)$(pad_left "" 33)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}     • 极限榨干内存，适合极度缺内存$(pad_left "" 17)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}     • ZRAM: 180% | Swap: 200% | Swappiness: 100$(pad_left "" 7)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}0.${NC} 返回$(pad_left "" 50)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"
        echo -e "${CYAN}└─────────────────────────────────────────────────────────┘${NC}"
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

        echo -e "${CYAN}┌─────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│${WHITE}$(pad_center "ZRAM 配置" 57)${CYAN}│${NC}"
        echo -e "${CYAN}├─────────────────────────────────────────────────────────┤${NC}"
        echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}1.${NC} 启用 ZRAM (自动检测算法)$(pad_left "" 20)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}2.${NC} 自定义配置$(pad_left "" 38)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}3.${NC} 查看 ZRAM 状态$(pad_left "" 36)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}0.${NC} 返回$(pad_left "" 50)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"
        echo -e "${CYAN}└─────────────────────────────────────────────────────────┘${NC}"
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
                # 使用 jq 或 python3 格式化 JSON，如果没有则直接显示
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

        echo -e "${CYAN}┌─────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│${WHITE}$(pad_center "动态调整模式" 57)${CYAN}│${NC}"
        echo -e "${CYAN}├─────────────────────────────────────────────────────────┤${NC}"
        echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}1.${NC} 启用动态调整$(pad_left "" 38)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}2.${NC} 停用动态调整$(pad_left "" 38)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}3.${NC} 查看调整日志$(pad_left "" 38)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${GREEN}0.${NC} 返回$(pad_left "" 50)${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"
        echo -e "${CYAN}└─────────────────────────────────────────────────────────┘${NC}"
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
                    echo -e "${CYAN}┌─────────────────────────────────────────────────────────┐${NC}"
                    echo -e "${CYAN}│${WHITE}              动态调整日志${CYAN}                              │${NC}"
                    echo -e "${CYAN}├─────────────────────────────────────────────────────────┤${NC}"
                    echo -e "${CYAN}│${NC}                                                         ${CYAN}│${NC}"
                    tail -20 "$LOG_DIR/dynamic.log" | while IFS= read -r line; do
                        echo -e "${CYAN}│${NC}  ${line}${CYAN}                                                │${NC}"
                    done
                    echo -e "${CYAN}│${NC}                                                         ${CYAN}│${NC}"
                    echo -e "${CYAN}└─────────────────────────────────────────────────────────┘${NC}"
                    echo ""
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

    echo -e "${CYAN}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${WHITE}$(pad_center "一键优化" 57)${CYAN}│${NC}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"
    echo -e "${CYAN}│${WHITE}$(pad_left "  将执行以下操作:" 57)${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  ${GREEN}•${NC} 创建系统备份$(pad_left "" 40)${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  ${GREEN}•${NC} 配置 ZRAM (策略: ${YELLOW}${STRATEGY_MODE}${NC})$(pad_left "" 16)${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  ${GREEN}•${NC} 配置虚拟内存策略 (含 I/O 熔断/OOM 保护)$(pad_left "" 7)${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  ${GREEN}•${NC} 启用动态调整模式$(pad_left "" 35)${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  ${GREEN}•${NC} 配置开机自启动$(pad_left "" 38)${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}$(pad_center "" 57)${CYAN}│${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────┘${NC}"
    echo ""
    if ! confirm "确认执行？"; then
        return
    fi

    local errors=0

    # 1. 创建备份
    if ! create_backup; then
        log warn "备份创建失败，继续执行优化"
        ((errors++)) || true
    fi

    # 2. 配置 ZRAM（包含压缩算法、物理内存熔断）
    if ! configure_zram "auto" "$STRATEGY_MODE"; then
        log error "ZRAM 配置失败"
        ((errors++)) || true
    fi

    # 3. 配置虚拟内存（包含 I/O 熔断保护、OOM 保护、内核参数优化）
    if ! configure_virtual_memory "$STRATEGY_MODE"; then
        log error "虚拟内存配置失败"
        ((errors++)) || true
    fi

    # 4. 启用动态调整模式（自动优化 swappiness）
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
# 全局快捷键安装
# ============================================================================

install_global_shortcut() {
    local shortcut_path="/usr/local/bin/z"
    local script_path=$(realpath "$0" 2>/dev/null || readlink -f "$0" 2>/dev/null || echo "$0")

    # 检查快捷键是否已存在
    if [[ -f "$shortcut_path" ]]; then
        # 检查是否指向当前脚本
        local existing_link=$(readlink "$shortcut_path" 2>/dev/null || cat "$shortcut_path" 2>/dev/null)
        if [[ "$existing_link" == "$script_path" ]]; then
            return 0
        fi
    fi

    # 创建全局快捷键
    cat > "$shortcut_path" <<'EOF'
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

    # 设置快捷键脚本权限：允许所有用户执行，但仅 root 可修改
    chmod 755 "$shortcut_path" 2>/dev/null || true
    log info "全局快捷键 'z' 已安装到 $shortcut_path"
    echo -e "${GREEN}✓${NC} 全局快捷键已安装！现在可以随时输入 ${YELLOW}sudo z${NC} 打开 Z-Panel Pro"
}

# ============================================================================
# 信号处理模块
# ============================================================================

cleanup_on_exit() {
    log info "执行清理操作..."
    clear_zram_cache
    release_lock
    log info "清理完成"
}

# 注册信号处理器
trap cleanup_on_exit INT TERM QUIT

# ============================================================================
# 主程序
# ============================================================================

main() {
    # 检查是否以 root 权限运行
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}此脚本需要 root 权限运行${NC}"
        echo "请使用: sudo bash $0"
        exit 1
    fi

    # 获取文件锁，防止重复启动
    if ! acquire_lock; then
        echo -e "${RED}无法获取文件锁，脚本可能已在运行${NC}"
        exit 1
    fi

    # 初始化图标系统（检测 Nerd Font 环境）
    init_icons

    # 检查依赖（使用增强的 command -v 检测）
    check_dependencies || exit 1

    detect_system

    # 创建目录并设置安全权限
    mkdir -p "$INSTALL_DIR"/{conf,logs,backup}
    chmod 700 "$INSTALL_DIR/conf" 2>/dev/null || true
    chmod 755 "$INSTALL_DIR/logs" 2>/dev/null || true
    chmod 700 "$INSTALL_DIR/backup" 2>/dev/null || true

    # 创建全局快捷键 'z'
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