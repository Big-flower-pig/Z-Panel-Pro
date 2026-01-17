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

readonly VERSION="5.0.0-Pro"
readonly BUILD_DATE="2026-01-17"
readonly SCRIPT_NAME="Z-Panel Pro 内存优化"

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
# 工具函数
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

    # 写入日志文件
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
# 工具检查函数
# ============================================================================

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

update_cache() {
    local current_time=$(date +%s)
    local cache_age=$((current_time - CACHE_LAST_UPDATE))

    # 如果缓存未过期，直接返回
    if [[ $cache_age -lt $CACHE_TTL ]]; then
        return 0
    fi

    # 更新缓存
    CACHE_MEM_TOTAL=$(free -m | awk '/^Mem:/ {print $2}')
    CACHE_MEM_USED=$(free -m | awk '/^Mem:/ {print $3}')
    CACHE_MEM_AVAIL=$(free -m | awk '/^Mem:/ {print $7}')
    CACHE_BUFF_CACHE=$(free -m | awk '/^Mem:/ {print $6}')
    CACHE_SWAP_TOTAL=$(free -m | awk '/Swap:/ {print $2}')
    CACHE_SWAP_USED=$(free -m | awk '/Swap:/ {print $3}')
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
# 内存信息获取（统一接口）
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

# ============================================================================
# 安全的配置加载
# ============================================================================

safe_source() {
    local file=$1
    local pattern='^[A-Z_][A-Z0-9_]*='

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    # 验证文件内容只包含安全的赋值语句
    if grep -vE "^(#|$pattern)" "$file" | grep -q '[^[:space:]]'; then
        log error "配置文件包含不安全内容: $file"
        return 1
    fi

    source "$file"
    return 0
}

# ============================================================================
# 进度条和图表显示模块
# ============================================================================

show_progress_bar() {
    local current=$1
    local total=$2
    local width=${3:-40}
    local label=${4:-""}

    [[ -z "$label" ]] || echo -ne "${WHITE}$label${NC} "

    # 防止除零错误
    [[ "$total" -eq 0 ]] && total=1
    [[ "$current" -gt "$total" ]] && current=$total

    local filled=$((current * width / total))
    local empty=$((width - filled))
    local percent=$((current * 100 / total))

    local color="$GREEN"
    [[ $percent -gt 70 ]] && color="$YELLOW"
    [[ $percent -gt 90 ]] && color="$RED"

    echo -ne "["
    for ((i=0; i<filled; i++)); do echo -ne "${color}#${NC}"; done
    for ((i=0; i<empty; i++)); do echo -ne "${WHITE}-${NC}"; done
    echo -ne "] ${CYAN}${percent}%${NC}\n"
}

show_compression_chart() {
    local ratio=$1
    local width=${2:-30}

    echo -ne "${CYAN}压缩比: ${ratio}x${NC} "

    local filled=0
    local color="$GREEN"

    # 使用 awk 进行浮点数比较，避免依赖 bc
    if (( $(awk "BEGIN {print ($ratio >= 3.0)}") )); then
        filled=$((width * 100 / 100))
    elif (( $(awk "BEGIN {print ($ratio >= 2.0)}") )); then
        filled=$((width * 75 / 100))
    elif (( $(awk "BEGIN {print ($ratio >= 1.5)}") )); then
        filled=$((width * 50 / 100))
        color="$YELLOW"
    else
        filled=$((width * 25 / 100))
        color="$RED"
    fi

    echo -ne "["
    for ((i=0; i<filled; i++)); do echo -ne "${color}#${NC}"; done
    for ((i=filled; i<width; i++)); do echo -ne "${WHITE}-${NC}"; done
    echo -e "]"
}

show_memory_pie() {
    local mem_used=$1
    local mem_total=$2
    local mem_avail=$((mem_total - mem_used))
    local used_percent=$((mem_used * 100 / mem_total))
    local avail_percent=$((100 - used_percent))

    echo -e "  ${YELLOW}■${NC} 已用: ${mem_used}MB (${YELLOW}${used_percent}%${NC})"
    echo -e "  ${GREEN}■${NC} 可用: ${mem_avail}MB (${GREEN}${avail_percent}%${NC})"
    echo -e "  ${WHITE}■${NC} 总量: ${mem_total}MB"
}

# ============================================================================
# 日志管理模块
# ============================================================================

load_log_config() {
    if [[ -f "$LOG_CONFIG_FILE" ]]; then
        safe_source "$LOG_CONFIG_FILE" || true
    fi
}

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

log_config_menu() {
    load_log_config

    while true; do
        clear

        echo -e "${CYAN}========================================${NC}"
        echo -e "${CYAN}  日志管理${NC}"
        echo -e "${CYAN}========================================${NC}\n"

        echo -e "${WHITE}当前配置:${NC}"
        echo -e "  最大日志大小: ${CYAN}${LOG_MAX_SIZE_MB}MB${NC}"
        echo -e "  日志保留天数: ${CYAN}${LOG_RETENTION_DAYS}天${NC}"

        echo -e "\n${GREEN}1.${NC} 设置最大日志大小"
        echo -e "  ${GREEN}2.${NC} 设置日志保留天数"
        echo -e "  ${GREEN}3.${NC} 查看日志文件列表"
        echo -e "  ${GREEN}4.${NC} 查看运行日志（分页）"
        echo -e "  ${GREEN}5.${NC} 查看动态调整日志（分页）"
        echo -e "  ${GREEN}6.${NC} 清理过期日志"
        echo -e "  ${GREEN}0.${NC} 返回"

        echo -e "\n${CYAN}========================================${NC}\n"

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
                echo -e "${CYAN}========================================${NC}"
                echo -e "${CYAN}  日志文件列表${NC}"
                echo -e "${CYAN}========================================${NC}\n"

                if [[ -d "$LOG_DIR" ]]; then
                    echo -e "${WHITE}ZPanel 日志:${NC}"
                    shopt -s nullglob
                    for log in "$LOG_DIR"/zpanel_*.log; do
                        [[ -f "$log" ]] && {
                            local size=$(du -h "$log" | cut -f1)
                            local mtime=$(stat -c %y "$log" 2>/dev/null | cut -d' ' -f1-2)
                            echo -e "  ${CYAN}$(basename "$log")${NC} - ${size} - ${mtime}"
                        }
                    done
                    shopt -u nullglob

                    echo -e "\n${WHITE}动态调整日志:${NC}"
                    if [[ -f "$LOG_DIR/dynamic.log" ]]; then
                        local size=$(du -h "$LOG_DIR/dynamic.log" | cut -f1)
                        echo -e "  ${CYAN}dynamic.log${NC} - ${size}"
                    fi
                else
                    echo -e "${YELLOW}暂无日志文件${NC}"
                fi

                echo -e "\n${CYAN}========================================${NC}\n"
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

        echo -e "${CYAN}========================================${NC}"
        echo -e "${CYAN}  日志查看: $(basename "$log_file")${NC}"
        echo -e "${CYAN}========================================${NC}\n"

        echo -e "${WHITE}页码: ${CYAN}${page}${NC}/${CYAN}$(( (total_lines + lines - 1) / lines ))${NC}  ${WHITE}总行数: ${CYAN}${total_lines}${NC}\n"

        local start=$(( (page - 1) * lines + 1 ))
        local end=$((page * lines))

        sed -n "${start},${end}p" "$log_file" | while IFS= read -r line; do
            line=$(echo "$line" | sed -e 's/\[INFO\]/\\033[0;36m[INFO]\\033[0m/g' \
                                      -e 's/\[WARN\]/\\033[1;33m[WARN]\\033[0m/g' \
                                      -e 's/\[ERROR\]/\\033[0;31m[ERROR]\\033[0m/g')
            echo -e "$line"
        done

        echo -e "\n${CYAN}========================================${NC}"
        echo -e "  ${GREEN}n${NC} - 下一页  ${GREEN}p${NC} - 上一页  ${GREEN}q${NC} - 退出"
        echo -e "${CYAN}========================================${NC}\n"

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

clean_old_logs() {
    local cleaned=0

    for log in "$LOG_DIR"/zpanel_*.log; do
        if [[ -f "$log" ]]; then
            local log_date=$(basename "$log" | sed 's/zpanel_//' | sed 's/\.log//')
            local log_age=$(( ( $(date +%s) - $(date -d "$log_date" +%s 2>/dev/null || echo 0) ) / 86400 ))

            if [[ $log_age -gt $LOG_RETENTION_DAYS ]]; then
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
                local temp_file="${log}.tmp.$$"
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

    echo -e "${GREEN}清理完成，共处理 $cleaned 个日志文件${NC}"
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

    local files=(
        "/etc/sysctl.conf"
        "/etc/fstab"
    )

    local backed_up=0
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            if cp "$file" "$backup_path/" 2>/dev/null; then
                ((backed_up++))
                log info "已备份: $file"
            else
                log warn "备份失败: $file"
            fi
        fi
    done

    cat > "$backup_path/info.txt" <<EOF
backup_time=$timestamp
backup_version=$VERSION
distro=$CURRENT_DISTRO
distro_version=$CURRENT_VERSION
strategy=$STRATEGY_MODE
EOF

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
                    ((restored++))
                    log info "已还原: $filename"
                else
                    ((failed++))
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
            phys_limit=$((TOTAL_MEMORY_MB * 40 / 100))
            swap_size=$((TOTAL_MEMORY_MB * 100 / 100))
            swappiness=60
            dirty_ratio=5
            min_free=65536
            ;;
        balance)
            # 平衡模式：默认选项
            zram_ratio=120
            phys_limit=$((TOTAL_MEMORY_MB * 50 / 100))
            swap_size=$((TOTAL_MEMORY_MB * 150 / 100))
            swappiness=85
            dirty_ratio=10
            min_free=32768
            ;;
        aggressive)
            # 激进模式：最大化利用
            zram_ratio=180
            phys_limit=$((TOTAL_MEMORY_MB * 65 / 100))
            swap_size=$((TOTAL_MEMORY_MB * 200 / 100))
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

    local zram_size=$((TOTAL_MEMORY_MB * zram_ratio / 100))
    [[ $zram_size -lt 512 ]] && zram_size=512

    if ! command -v zramctl &> /dev/null; then
        log info "安装 zram-tools..."
        install_packages zram-tools zram-config zstd lz4 lzop || {
            log error "安装 zram-tools 失败"
            return 1
        }
    fi

    if ! lsmod | grep -q zram; then
        modprobe zram || {
            log error "无法加载 ZRAM 模块"
            return 1
        }
    fi

    if swapon --show=NAME --noheadings 2>/dev/null | grep -q zram; then
        for device in $(swapon --show=NAME --noheadings 2>/dev/null | grep zram); do
            swapoff "$device" 2>/dev/null || true
        done
    fi

    if [[ -e /sys/block/zram0/reset ]]; then
        echo 1 > /sys/block/zram0/reset 2>/dev/null || true
        sleep 0.3
    fi

    if [[ -e /sys/block/zram0/comp_algorithm ]]; then
        local supported=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null)
        if echo "$supported" | grep -q "$algorithm"; then
            echo "$algorithm" > /sys/block/zram0/comp_algorithm 2>/dev/null || {
                log warn "设置压缩算法失败，使用默认算法"
            }
            log info "设置压缩算法: $algorithm"
        else
            local fallback=$(echo "$supported" | grep -oE '\[([^\]]+)\]' | head -1 | sed 's/[\[\]]//g')
            [[ -z "$fallback" ]] && fallback="lzo"
            echo "$fallback" > /sys/block/zram0/comp_algorithm 2>/dev/null || true
            algorithm="$fallback"
            log info "使用回退算法: $algorithm"
        fi
    fi

    if [[ -e /sys/block/zram0/max_comp_streams ]]; then
        echo "$CPU_CORES" > /sys/block/zram0/max_comp_streams 2>/dev/null || true
        log info "设置压缩流数: $CPU_CORES"
    fi

    local zram_bytes=$((zram_size * 1024 * 1024))
    echo "$zram_bytes" > /sys/block/zram0/disksize 2>/dev/null || {
        log error "设置 ZRAM 大小失败"
        return 1
    }

    # 物理内存熔断
    if [[ -e /sys/block/zram0/mem_limit ]]; then
        local phys_limit_bytes=$((phys_limit * 1024 * 1024))
        echo "$phys_limit_bytes" > /sys/block/zram0/mem_limit 2>/dev/null || true
        log info "已启用物理内存熔断保护 (Limit: ${phys_limit}MB)"
    fi

    mkswap /dev/zram0 > /dev/null 2>&1 || {
        log error "格式化 ZRAM 失败"
        return 1
    }

    swapon -p 100 /dev/zram0 > /dev/null 2>&1 || {
        log error "启用 ZRAM 失败"
        return 1
    }

    if ! mkdir -p "$CONF_DIR"; then
        log error "无法创建配置目录: $CONF_DIR"
        return 1
    fi

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

# 安全的配置加载函数
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

    local zram_bytes=$((SIZE * 1024 * 1024))
    echo "$zram_bytes" > /sys/block/zram0/disksize 2>/dev/null || {
        log "设置 ZRAM 大小失败"
        exit 1
    }
    log "设置 ZRAM 大小: ${SIZE}MB"

    # 物理内存熔断
    if [[ -e /sys/block/zram0/mem_limit ]]; then
        local phys_limit_bytes=$((PHYS_LIMIT * 1024 * 1024))
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
    chmod +x "$INSTALL_DIR/zram-start.sh"

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

    for pid in $(pgrep sshd); do
        echo -1000 > /proc/$pid/oom_score_adj 2>/dev/null || true
    done

    for pid in $(pgrep systemd); do
        echo -1000 > /proc/$pid/oom_score_adj 2>/dev/null || true
    done

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
    [[ $swap_total -gt 0 ]] && swap_usage=$((swap_used * 100 / swap_total))

    # 使用缓存获取 ZRAM 信息
    read -r zram_total zram_used <<< $(get_zram_usage)
    local zram_usage=0
    if [[ $zram_total -gt 0 ]]; then
        zram_usage=$((zram_used * 100 / zram_total))
    fi

    # 动态调整 swappiness
    if [[ $zram_usage -gt 80 ]]; then
        swappiness=$((swappiness - 20))
    elif [[ $zram_usage -gt 50 ]]; then
        swappiness=$((swappiness - 10))
    fi

    if [[ $swap_usage -gt 50 ]]; then
        swappiness=$((swappiness - 10))
    fi

    if [[ $mem_total -lt 1024 ]]; then
        swappiness=$((swappiness + 20))
    elif [[ $mem_total -gt 4096 ]]; then
        swappiness=$((swappiness - 10))
    fi

    [[ $swappiness -lt 10 ]] && swappiness=10
    [[ $swappiness -gt 100 ]] && swappiness=100

    log info "内存: ${mem_total}MB, Swap使用: ${swap_usage}%, ZRAM使用: ${zram_usage}%"
    log info "建议 swappiness: $swappiness"

    mkdir -p "$CONF_DIR"
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
vm.dirty_background_ratio=$((dirty_ratio / 2))
vm.dirty_expire_centisecs=3000
vm.dirty_writeback_centisecs=500

# 页面聚合
vm.page-cluster=0

# 文件系统
fs.file-max=2097152
fs.inotify.max_user_watches=524288
EOF

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

# 统一的内存信息获取函数
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
mem_percent=$((mem_used * 100 / mem_total))

read -r swap_total swap_used <<< $(get_swap_info)
swap_usage=0
[[ $swap_total -gt 0 ]] && swap_usage=$((swap_used * 100 / swap_total))

read -r zram_total zram_used <<< $(get_zram_usage)
zram_usage=0
[[ $zram_total -gt 0 ]] && zram_usage=$((zram_used * 100 / zram_total))

# 计算最优 swappiness
optimal_swappiness=60
if [[ $zram_usage -gt 80 ]]; then
    optimal_swappiness=30
elif [[ $zram_usage -gt 50 ]]; then
    optimal_swappiness=40
fi

if [[ $swap_usage -gt 50 ]]; then
    optimal_swappiness=$((optimal_swappiness - 10))
fi

if [[ $mem_total -lt 1024 ]]; then
    optimal_swappiness=$((optimal_swappiness + 20))
elif [[ $mem_total -gt 4096 ]]; then
    optimal_swappiness=$((optimal_swappiness - 10))
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

    chmod +x "$INSTALL_DIR/dynamic-adjust.sh"

    local cron_entry="*/5 * * * * $INSTALL_DIR/dynamic-adjust.sh"
    if ! crontab -l 2>/dev/null | grep -q "dynamic-adjust.sh"; then
        (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
    fi

    DYNAMIC_MODE=true
    log info "动态调整模式已启用 (每 5 分钟检查)"
}

disable_dynamic_mode() {
    log info "停用动态调整模式..."

    crontab -l 2>/dev/null | grep -v "dynamic-adjust.sh" | crontab -

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

        echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${WHITE}         Z-Panel Pro 实时监控面板 v${VERSION}        ${CYAN}║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════╣${NC}"
        printf "${CYAN}║${NC} 系统内存: ${WHITE}%4dMB${NC} | CPU: ${WHITE}%d核心${NC} | 模式: ${YELLOW}%s${NC} ${CYAN}║${NC}\n" "$TOTAL_MEMORY_MB" "$CPU_CORES" "$STRATEGY_MODE"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════╣${NC}"

        # 使用缓存获取内存信息
        read -r mem_total mem_used mem_avail buff_cache <<< $(get_memory_info true)

        printf "${CYAN}║${NC} [RAM] 使用: ${WHITE}%dMB${NC} / 缓存: ${WHITE}%dMB${NC} / 空闲: ${GREEN}%dMB${NC} ${CYAN}║${NC}\n" "$mem_used" "$buff_cache" "$mem_avail"
        echo -e "${CYAN}║${NC}                                               ${CYAN}║${NC}"

        printf "${CYAN}║${NC} 物理内存负载: "
        show_progress_bar "$mem_used" "$mem_total" 30 ""
        printf " ${CYAN}║${NC}\n"

        echo -e "${CYAN}╠══════════════════════════════════════════════════════╣${NC}"

        if swapon --show=NAME --noheadings 2>/dev/null | grep -q zram; then
            echo -e "${CYAN}║${NC} ZRAM状态: ${GREEN}运行中${NC}"

            local zram_status=$(get_zram_status)
            local algo=$(echo "$zram_status" | grep -o '"algorithm":"[^"]*"' | cut -d'"' -f4)
            local ratio=$(echo "$zram_status" | grep -o '"compression_ratio":"[^"]*"' | cut -d'"' -f4)
            [[ -z "$ratio" || "$ratio" == "0" ]] && ratio="1.00"

            # 使用缓存获取 ZRAM 信息
            read -r zram_total_kb zram_used_kb <<< $(get_zram_usage)

            printf "${CYAN}║${NC} 算法: ${CYAN}%s${NC} | 压缩比: ${CYAN}%s${NC}x ${CYAN}║${NC}\n" "$algo" "$ratio"

            echo -e "${CYAN}║${NC}                                               ${CYAN}║${NC}"
            printf "${CYAN}║${NC} ZRAM 压缩比: "
            show_compression_chart "$ratio" 25
            printf " ${CYAN}║${NC}\n"

            printf "${CYAN}║${NC} ZRAM 负载: "
            show_progress_bar "$zram_used_kb" "$zram_total_kb" 30 ""
            printf " ${CYAN}║${NC}\n"
        else
            echo -e "${CYAN}║${NC} ZRAM状态: ${RED}未启用${NC}                                      ${CYAN}║${NC}"
        fi

        echo -e "${CYAN}╠══════════════════════════════════════════════════════╣${NC}"

        # 使用缓存获取 Swap 信息
        read -r swap_total swap_used <<< $(get_swap_info true)

        if [[ $swap_total -gt 0 ]]; then
             printf "${CYAN}║${NC} Swap 负载: "
             show_progress_bar "$swap_used" "$swap_total" 30 ""
             printf " ${CYAN}║${NC}\n"
        else
             printf "${CYAN}║${NC} Swap 状态: ${RED}未启用${NC}                                      ${CYAN}║${NC}\n"
        fi

        echo -e "${CYAN}╠══════════════════════════════════════════════════════╣${NC}"

        local swappiness=$(sysctl -n vm.swappiness 2>/dev/null || echo "60")
        local vfs_cache=$(sysctl -n vm.vfs_cache_pressure 2>/dev/null || echo "100")
        local dirty_ratio=$(sysctl -n vm.dirty_ratio 2>/dev/null || echo "20")

        printf "${CYAN}║${NC} swappiness: "
        show_progress_bar "$swappiness" 100 25 ""
        printf " ${CYAN}║${NC}\n"

        echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
        echo -e "${WHITE}按 Ctrl+C 返回主菜单${NC}"

        sleep 3
    done

    # 恢复信号处理
    trap - INT
}

show_status() {
    clear

    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  Z-Panel Pro 系统状态 ${VERSION}${NC}"
    echo -e "${CYAN}========================================${NC}\n"

    echo -e "${WHITE}系统信息:${NC}"
    echo -e "  发行版: $CURRENT_DISTRO $CURRENT_VERSION"
    echo -e "  内存: ${TOTAL_MEMORY_MB}MB"
    echo -e "  CPU: ${CPU_CORES} 核心"
    echo -e "  策略: ${YELLOW}$STRATEGY_MODE${NC}"

    echo -e "\n${BLUE}【ZRAM 状态】${NC}"
    if swapon --show=NAME --noheadings 2>/dev/null | grep -q zram; then
        echo -e "  ${GREEN}已启用${NC}"

        local zram_status=$(get_zram_status)
        local disk_size=$(echo "$zram_status" | grep -o '"disk_size":"[^"]*"' | cut -d'"' -f4)
        local data_size=$(echo "$zram_status" | grep -o '"data_size":"[^"]*"' | cut -d'"' -f4)
        local comp_size=$(echo "$zram_status" | grep -o '"comp_size":"[^"]*"' | cut -d'"' -f4)
        local algo=$(echo "$zram_status" | grep -o '"algorithm":"[^"]*"' | cut -d'"' -f4)
        local ratio=$(echo "$zram_status" | grep -o '"compression_ratio":"[^"]*"' | cut -d'"' -f4)

        echo -e "  算法: ${CYAN}$algo${NC}"
        echo -e "  大小: $disk_size"
        echo -e "  数据: $data_size"
        echo -e "  压缩: $comp_size"
        show_compression_chart "$ratio" 25
    else
        echo -e "  ${RED}未启用${NC}"
    fi

    echo -e "\n${BLUE}【Swap 状态】${NC}"
    # 使用缓存获取 Swap 信息
    read -r swap_total swap_used <<< $(get_swap_info false)

    if [[ $swap_total -eq 0 ]]; then
        echo -e "  ${YELLOW}未启用${NC}"
    else
        echo -e "  总量: ${swap_total}MB"
        echo -e "  已用: ${YELLOW}${swap_used}MB${NC}"
        show_progress_bar "$swap_used" "$swap_total" 30 "Swap"
    fi

    echo -e "\n${BLUE}【内核参数】${NC}"
    local swappiness=$(sysctl -n vm.swappiness 2>/dev/null || echo "60")
    local vfs_cache=$(sysctl -n vm.vfs_cache_pressure 2>/dev/null || echo "100")
    local dirty_ratio=$(sysctl -n vm.dirty_ratio 2>/dev/null || echo "20")

    show_progress_bar "$swappiness" 100 25 "vm.swappiness"
    show_progress_bar "$vfs_cache" 200 25 "vm.vfs_cache_pressure"
    show_progress_bar "$dirty_ratio" 50 25 "vm.dirty_ratio"

    echo -e "\n${BLUE}【保护机制】${NC}"
    echo -e "  I/O 熔断: ${GREEN}已启用${NC}"
    echo -e "  OOM 保护: ${GREEN}已启用${NC}"
    echo -e "  物理内存熔断: ${GREEN}已启用${NC}"

    echo -e "\n${CYAN}========================================${NC}\n"
}

# ============================================================================
# 菜单系统
# ============================================================================

show_main_menu() {
    clear

    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}           Z-Panel Pro v${VERSION} 主控菜单              ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}║${NC} 检测到系统: ${YELLOW}RAM:%dMB${NC} | ${YELLOW}CPU:%d Cores${NC} | ${YELLOW}%s${NC} " "$TOTAL_MEMORY_MB" "$CPU_CORES" "$CURRENT_DISTRO $CURRENT_VERSION"
    printf "%*s${CYAN}║${NC}\n" $((50 - ${#CURRENT_DISTRO} - ${#CURRENT_VERSION} - ${#TOTAL_MEMORY_MB} - ${#CPU_CORES} - 10)) ""
    echo -e "${CYAN}╠══════════════════════════════════════════════════════╣${NC}"

    echo -e "${CYAN}║${NC}  ${GREEN}【主要功能】${NC}                                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}1.${NC} 一键优化 (当前模式: ${YELLOW}$STRATEGY_MODE${NC})${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}2.${NC} 状态监控 ${CYAN}[快捷键: z]${NC}                           ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}3.${NC} 日志管理                                         ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                        ${CYAN}║${NC}"

    echo -e "${CYAN}║${NC}  ${GREEN}【高级功能】${NC}                                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}4.${NC} 切换优化模式 (保守/平衡/激进)                     ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}5.${NC} 配置 ZRAM                                        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}6.${NC} 配置虚拟内存                                      ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}7.${NC} 动态调整模式                                      ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                        ${CYAN}║${NC}"

    echo -e "${CYAN}║${NC}  ${GREEN}【系统管理】${NC}                                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}8.${NC} 查看系统状态                                      ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}9.${NC} 停用 ZRAM                                        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}10.${NC} 还原备份                                          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}0.${NC} 退出程序                                         ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                        ${CYAN}║${NC}"

    echo -e "${CYAN}╠══════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  ZRAM: $([[ $ZRAM_ENABLED == true ]] && echo -e "${GREEN}已启用${NC}" || echo -e "${RED}未启用${NC}")  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  动态: $([[ $DYNAMIC_MODE == true ]] && echo -e "${GREEN}已启用${NC}" || echo -e "${RED}未启用${NC}")  ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}\n"

    echo -ne "${WHITE}请选择 [0-10]: ${NC}"
}

strategy_menu() {
    while true; do
        clear

        echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${WHITE}              选择优化模式                          ${CYAN}║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC}                                                        ${CYAN}║${NC}"

        echo -e "${CYAN}║${NC}  ${GREEN}1.${NC} Conservative (保守)                             ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}     - 最稳定，适合路由器/NAS                           ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}     - ZRAM: 80% | Swap: 100% | Swappiness: 60       ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}                                                        ${CYAN}║${NC}"

        echo -e "${CYAN}║${NC}  ${GREEN}2.${NC} Balance (平衡)  ${YELLOW}[推荐]${NC}                     ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}     - 性能与稳定兼顾，日常使用                         ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}     - ZRAM: 120% | Swap: 150% | Swappiness: 85       ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}                                                        ${CYAN}║${NC}"

        echo -e "${CYAN}║${NC}  ${GREEN}3.${NC} Aggressive (激进)                              ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}     - 极限榨干内存，适合极度缺内存                    ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}     - ZRAM: 180% | Swap: 200% | Swappiness: 100       ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}                                                        ${CYAN}║${NC}"

        echo -e "${CYAN}╠══════════════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC}  ${GREEN}0.${NC} 返回                                             ${CYAN}║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}\n"

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

        echo -e "${CYAN}========================================${NC}"
        echo -e "${CYAN}  ZRAM 配置${NC}"
        echo -e "${CYAN}========================================${NC}\n"

        echo -e "  ${GREEN}1.${NC} 启用 ZRAM (自动检测算法)"
        echo -e "  ${GREEN}2.${NC} 自定义配置"
        echo -e "  ${GREEN}3.${NC} 查看 ZRAM 状态"
        echo -e "  ${GREEN}0.${NC} 返回"

        echo -e "\n${CYAN}========================================${NC}\n"

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

        echo -e "${CYAN}========================================${NC}"
        echo -e "${CYAN}  动态调整模式${NC}"
        echo -e "${CYAN}========================================${NC}\n"

        echo -e "  ${GREEN}1.${NC} 启用动态调整"
        echo -e "  ${GREEN}2.${NC} 停用动态调整"
        echo -e "  ${GREEN}3.${NC} 查看调整日志"
        echo -e "  ${GREEN}0.${NC} 返回"

        echo -e "\n${CYAN}========================================${NC}\n"

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
                    echo -e "${CYAN}========================================${NC}"
                    echo -e "${CYAN}  动态调整日志${NC}"
                    echo -e "${CYAN}========================================${NC}\n"
                    tail -20 "$LOG_DIR/dynamic.log"
                    echo -e "\n${CYAN}========================================${NC}\n"
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

    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  一键优化${NC}"
    echo -e "${CYAN}========================================${NC}\n"

    echo -e "${WHITE}将执行以下操作:${NC}"
    echo -e "  1. 创建系统备份"
    echo -e "  2. 配置 ZRAM (策略: ${YELLOW}$STRATEGY_MODE${NC})"
    echo -e "  3. 配置虚拟内存策略"
    echo -e "  4. 应用 I/O 熔断保护"
    echo -e "  5. 应用 OOM 保护"
    echo -e "  6. 启用动态调整"

    echo -e "\n${YELLOW}确认执行？${NC}"
    if ! confirm "继续？"; then
        return
    fi

    local errors=0

    # 1. 创建备份
    if ! create_backup; then
        log warn "备份创建失败，继续执行优化"
        ((errors++))
    fi

    # 2. 配置 ZRAM
    if ! configure_zram "auto" "$STRATEGY_MODE"; then
        log error "ZRAM 配置失败"
        ((errors++))
    fi

    # 3. 配置虚拟内存
    if ! configure_virtual_memory "$STRATEGY_MODE"; then
        log error "虚拟内存配置失败"
        ((errors++))
    fi

    # 4. 启用动态调整
    if ! enable_dynamic_mode; then
        log warn "动态调整模式启用失败"
        ((errors++))
    fi

    if [[ $errors -gt 0 ]]; then
        echo -e "\n${YELLOW}注意: 优化过程中遇到 $errors 个错误，请检查日志${NC}"
        echo -e "${CYAN}日志目录: $LOG_DIR${NC}"
    else
        echo -e "\n${GREEN}优化完成！${NC}"
        echo -e "${GREEN}ZRAM 已配置为开机自动启动${NC}"
        echo -e "${GREEN}策略模式: $STRATEGY_MODE${NC}"
    fi
    pause
}

# ============================================================================
# 主程序
# ============================================================================

main() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}此脚本需要 root 权限运行${NC}"
        echo "请使用: sudo bash $0"
        exit 1
    fi

    # 检查依赖
    check_dependencies || exit 1

    detect_system
    mkdir -p "$INSTALL_DIR"/{conf,logs,backup}

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
            2|z|Z)
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
                            ((i++))
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