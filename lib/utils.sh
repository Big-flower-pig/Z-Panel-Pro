#!/bin/bash
# ==============================================================================
# Z-Panel Pro V9.0 - 工具函数库
# ==============================================================================
# @description    通用工具函数与辅助功能集合
# @version       9.0.0-Lightweight
# @author        Z-Panel Team
# @license       MIT License
# ==============================================================================

# ==============================================================================
# 验证函数
# ==============================================================================

# ==============================================================================
# 验证正整数
# @param var: 待验证的变量
# @return: 0表示验证通过，1表示验证失败
# @example: validate_positive_integer "123" && echo "有效"
# ==============================================================================
validate_positive_integer() {
    local var="$1"
    [[ "${var}" =~ ^[0-9]+$ ]] && [[ ${var} -gt 0 ]]
}

# 验证数字（可负）
validate_number() {
    local var="$1"
    [[ "${var}" =~ ^-?[0-9]+$ ]]
}

# 验证浮点数
validate_float() {
    local var="$1"
    [[ "${var}" =~ ^-?[0-9]+\.?[0-9]*$ ]]
}

# 验证文件名（安全）
validate_filename() {
    local filename="$1"
    # 只允许字母、数字、下划线、点、连字符
    [[ "${filename}" =~ ^[a-zA-Z0-9_.-]+$ ]] && [[ "${filename}" != ".." ]] && [[ "${filename}" != "." ]]
}

# 验证路径（安全）
validate_path() {
    local path="$1"
    # 防止路径遍历攻击
    [[ "${path}" != *".."* ]] && [[ "${path}" == /* ]]
}

# 验证PID有效性
validate_pid() {
    local pid="$1"
    [[ "${pid}" =~ ^[0-9]+$ ]] && [[ -d "/proc/${pid}" ]] && [[ -f "/proc/${pid}/cmdline" ]]
}

# 验证端口号
validate_port() {
    local port="$1"
    validate_number "${port}" && [[ ${port} -ge 1 ]] && [[ ${port} -le 65535 ]]
}

# 验证IP地址
validate_ip() {
    local ip="$1"
    local IFS='.'
    local -a octets=(${ip})

    [[ ${#octets[@]} -eq 4 ]] || return 1

    for octet in "${octets[@]}"; do
        [[ "${octet}" =~ ^[0-9]+$ ]] || return 1
        [[ ${octet} -ge 0 ]] && [[ ${octet} -le 255 ]] || return 1
    done

    return 0
}

# ==============================================================================
# 转换函数
# ==============================================================================

# ==============================================================================
# 转换大小到MB
# @param size: 待转换的大小字符串（如 "1024M", "1G", "512K"）
# @return: 转换后的MB值（保留2位小数）
# @example: convert_size_to_mb "1G"  # 输出: 1024.00
# @example: convert_size_to_mb "512M"  # 输出: 512.00
# ==============================================================================
convert_size_to_mb() {
    local size="$1"
    local unit num

    # 提取单位和数值
    unit="${size//[0-9.]/}"
    num="${size//[KMGTiB]/}"

    # 转换
    case "${unit}" in
        G|Gi|GB)
            awk "BEGIN {printf \"%.2f\", ${num} * 1024}"
            ;;
        M|Mi|MB|"")
            awk "BEGIN {printf \"%.2f\", ${num}}"
            ;;
        K|Ki|KB)
            awk "BEGIN {printf \"%.2f\", ${num} / 1024}"
            ;;
        T|Ti|TB)
            awk "BEGIN {printf \"%.2f\", ${num} * 1024 * 1024}"
            ;;
        B|b)
            awk "BEGIN {printf \"%.2f\", ${num} / 1048576}"
            ;;
        *)
            log_warn "未知单位: ${unit}, 返回MB"
            awk "BEGIN {printf \"%.2f\", ${num}}"
            ;;
    esac
}

# 转换MB到人类可读格式
convert_mb_to_human() {
    local mb="$1"

    if [[ $(awk "BEGIN {print ($mb >= 1048576)}") == "1" ]]; then
        awk "BEGIN {printf \"%.2fTB\", ${mb} / 1048576}"
    elif [[ $(awk "BEGIN {print ($mb >= 1024)}") == "1" ]]; then
        awk "BEGIN {printf \"%.2fGB\", ${mb} / 1024}"
    else
        awk "BEGIN {printf \"%.2fMB\", ${mb}}"
    fi
}

# 转换字节到人类可读格式
convert_bytes_to_human() {
    local bytes="$1"

    if [[ ${bytes} -ge 1099511627776 ]]; then
        awk "BEGIN {printf \"%.2fTB\", ${bytes} / 1099511627776}"
    elif [[ ${bytes} -ge 1073741824 ]]; then
        awk "BEGIN {printf \"%.2fGB\", ${bytes} / 1073741824}"
    elif [[ ${bytes} -ge 1048576 ]]; then
        awk "BEGIN {printf \"%.2fMB\", ${bytes} / 1048576}"
    elif [[ ${bytes} -ge 1024 ]]; then
        awk "BEGIN {printf \"%.2fKB\", ${bytes} / 1024}"
    else
        echo "${bytes}B"
    fi
}

# ==============================================================================
# 计算函数
# ==============================================================================

# ==============================================================================
# 计算百分比
# @param used: 已使用的值
# @param total: 总值
# @return: 百分比（保留2位小数），如果total为0则返回0
# @example: calculate_percentage "512" "1024"  # 输出: 50.00
# ==============================================================================
calculate_percentage() {
    local used="$1"
    local total="$2"

    if [[ -z "${total}" ]] || [[ $(awk "BEGIN {print (${total} == 0)}") == "1" ]]; then
        echo 0
        return
    fi

    if [[ -z "${used}" ]]; then
        used=0
    fi

    awk "BEGIN {printf \"%.2f\", ${used} * 100 / ${total}}"
}

# 比较浮点数
compare_float() {
    local op="$1"
    local val1="$2"
    local val2="$3"

    awk "BEGIN { exit !(${val1} ${op} ${val2}) }"
}

# 计算平均值
calculate_average() {
    local -a values=("$@")
    local sum=0
    local count=${#values[@]}

    [[ ${count} -eq 0 ]] && { echo 0; return; }

    for val in "${values[@]}"; do
        sum=$(awk "BEGIN {print ${sum} + ${val}}")
    done

    awk "BEGIN {printf \"%.2f\", ${sum} / ${count}}"
}

# 计算最大值
calculate_max() {
    local -a values=("$@")
    local max="${values[0]}"

    for val in "${values[@]}"; do
        if [[ $(awk "BEGIN {print (${val} > ${max})") == "1" ]]; then
            max="${val}"
        fi
    done

    echo "${max}"
}

# 计算最小值
calculate_min() {
    local -a values=("$@")
    local min="${values[0]}"

    for val in "${values[@]}"; do
        if [[ $(awk "BEGIN {print (${val} < ${min})") == "1" ]]; then
            min="${val}"
        fi
    done

    echo "${min}"
}

# ==============================================================================
# 文件操作函数
# ==============================================================================

# ==============================================================================
# 确保文件权限正确
# @param file: 文件路径
# @param expected_perms: 期望的权限（默认600）
# @return: 0成功，1失败
# @example: ensure_file_permissions "/etc/config" "644"
# ==============================================================================
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
            log_debug "已更新文件权限: ${file} -> ${expected_perms}"
        fi
    fi
    return 0
}

# 确保目录权限正确
ensure_dir_permissions() {
    local dir="$1"
    local expected_perms="${2:-750}"

    if [[ -d "${dir}" ]]; then
        local actual_perms
        actual_perms=$(stat -c "%a" "${dir}" 2>/dev/null || stat -f "%OLp" "${dir}" 2>/dev/null || echo "000")

        if [[ "${actual_perms}" != "${expected_perms}" ]]; then
            chmod "${expected_perms}" "${dir}" 2>/dev/null || {
                log_error "无法设置目录权限: ${dir}"
                return 1
            }
            log_debug "已更新目录权限: ${dir} -> ${expected_perms}"
        fi
    fi
    return 0
}

# ==============================================================================
# 安全加载配置文件
# @param file: 配置文件路径
# @return: 0成功，1失败
# @description: 检查文件存在性、权限，并扫描潜在危险模式后安全加载
# @example: safe_source "/etc/zpanel/config.conf"
# ==============================================================================
safe_source() {
    local file="$1"

    # 检查文件存在
    if [[ ! -f "${file}" ]]; then
        log_error "配置文件不存在: ${file}"
        return 1
    fi

    # 检查权限
    ensure_file_permissions "${file}" 600 || return 1

    # 检查危险模式（防止代码注入）
    # 只检查命令执行相关的危险模式
    # 使用固定字符串匹配，避免正则表达式错误
    if grep -v '^[[:space:]]*#' "${file}" 2>/dev/null | grep -qF '\$('; then
        log_warn "检测到潜在危险模式: \$( 在 ${file}"
        log_warn "请检查配置文件内容"
    fi
    if grep -v '^[[:space:]]*#' "${file}" 2>/dev/null | grep -qF '`'; then
        log_warn "检测到潜在危险模式: \` 在 ${file}"
        log_warn "请检查配置文件内容"
    fi
    if grep -v '^[[:space:]]*#' "${file}" 2>/dev/null | grep -q '&&'; then
        log_warn "检测到潜在危险模式: && 在 ${file}"
        log_warn "请检查配置文件内容"
    fi
    if grep -v '^[[:space:]]*#' "${file}" 2>/dev/null | grep -q '||'; then
        log_warn "检测到潜在危险模式: || 在 ${file}"
        log_warn "请检查配置文件内容"
    fi
    if grep -v '^[[:space:]]*#' "${file}" 2>/dev/null | grep -q ';'; then
        log_warn "检测到潜在危险模式: ; 在 ${file}"
        log_warn "请检查配置文件内容"
    fi

    # 加载文件
    source "${file}"
    return 0
}

# ==============================================================================
# 安全保存配置文件
# @param file: 文件路径
# @param content: 文件内容
# @param perms: 文件权限（默认600）
# @return: 0成功，1失败
# @description: 使用原子写入方式保存文件，防止写入失败导致文件损坏
# @example: save_config_file "/etc/config" "key=value" "644"
# ==============================================================================
save_config_file() {
    local file="$1"
    local content="$2"
    local perms="${3:-600}"

    # 创建目录
    mkdir -p "$(dirname "${file}")" 2>/dev/null || {
        log_error "无法创建目录: $(dirname "${file}")"
        return 1
    }

    # 设置目录权限
    chmod 700 "$(dirname "${file}")" 2>/dev/null || true

    # 使用原子写入（防止写入失败导致文件损坏）
    local temp_file="${file}.tmp.$$"
    if echo "${content}" > "${temp_file}" 2>/dev/null; then
        chmod "${perms}" "${temp_file}" 2>/dev/null || true
        mv "${temp_file}" "${file}" 2>/dev/null || {
            rm -f "${temp_file}"
            log_error "无法保存文件: ${file}"
            return 1
        }
    else
        rm -f "${temp_file}"
        log_error "无法写入临时文件: ${temp_file}"
        return 1
    fi

    log_debug "已保存配置文件: ${file}"
    return 0
}

# ==============================================================================
# 安全删除文件/目录
# @param path: 文件或目录路径
# @return: 0成功，1失败
# @description: 验证路径安全性，防止误删系统关键目录
# @example: safe_delete "/tmp/zpanel_temp"
# ==============================================================================
safe_delete() {
    local path="$1"

    # 验证路径
    if ! validate_path "${path}"; then
        log_error "无效路径: ${path}"
        return 1
    fi

    # 检查禁止目录（扩展列表）
    local forbidden_dirs=(
        "/"
        "/etc"
        "/bin"
        "/sbin"
        "/usr"
        "/usr/bin"
        "/usr/sbin"
        "/usr/lib"
        "/usr/local"
        "/var"
        "/var/log"
        "/var/run"
        "/var/lib"
        "/home"
        "/root"
        "/boot"
        "/dev"
        "/proc"
        "/sys"
        "/lib"
        "/lib64"
        "/opt"
        "/srv"
        "/tmp"
    )

    for dir in "${forbidden_dirs[@]}"; do
        # 检查完全匹配或子目录
        if [[ "${path}" == "${dir}" ]] || [[ "${path}" == "${dir}/*" ]]; then
            log_error "禁止删除系统目录: ${path}"
            return 1
        fi
    done

    # 额外安全检查：确保路径不包含关键系统目录
    local system_dirs=("etc" "bin" "sbin" "usr" "var" "home" "root" "boot" "dev" "proc" "sys" "lib" "opt" "srv")
    for sys_dir in "${system_dirs[@]}"; do
        if [[ "${path}" == *"/${sys_dir}"* ]]; then
            log_warn "路径包含系统目录: ${sys_dir}"
            log_warn "请确认操作: ${path}"
        fi
    done

    if [[ -f "${path}" ]]; then
        rm -f "${path}" 2>/dev/null || {
            log_error "无法删除文件: ${path}"
            return 1
        }
    elif [[ -d "${path}" ]]; then
        rm -rf "${path}" 2>/dev/null || {
            log_error "无法删除目录: ${path}"
            return 1
        }
    fi

    return 0
}

# ==============================================================================
# 命令检查函数
# ==============================================================================

# ==============================================================================
# 检查命令是否存在
# @param cmd: 命令名称
# @return: 0存在，1不存在
# @example: check_command "awk" && echo "awk已安装"
# ==============================================================================
check_command() {
    local cmd="$1"
    command -v "${cmd}" &> /dev/null
}

# 检查多个命令
check_commands() {
    local commands=("$@")
    local missing=()

    for cmd in "${commands[@]}"; do
        if ! check_command "${cmd}"; then
            missing+=("${cmd}")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "缺少命令: ${missing[*]}"
        return 1
    fi

    return 0
}

# ==============================================================================
# 检查依赖
# @return: 0所有依赖满足，1缺少必需依赖
# @description: 检查必需和可选命令，提供安装建议
# @example: check_dependencies
# ==============================================================================
check_dependencies() {
    local missing=()
    local warnings=()

    # 必需命令
    for cmd in awk sed grep tr cut head tail sort uniq wc; do
        check_command "${cmd}" || missing+=("${cmd}")
    done

    for cmd in modprobe swapon mkswap swapoff; do
        check_command "${cmd}" || missing+=("${cmd}")
    done

    # 可选命令
    check_command zramctl || warnings+=("zramctl")
    check_command sysctl || warnings+=("sysctl")
    check_command bc || warnings+=("bc")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "缺少必需命令: ${missing[*]}"
        echo ""
        echo "安装命令:"
        echo "  Debian/Ubuntu: apt-get install -y ${missing[*]}"
        echo "  CentOS/RHEL: yum install -y ${missing[*]}"
        echo "  Alpine: apk add ${missing[*]}"
        echo ""
        return 1
    fi

    if [[ ${#warnings[@]} -gt 0 ]]; then
        log_warn "缺少可选命令: ${warnings[*]}"
        log_warn "部分功能可能不可用"
    fi

    return 0
}

# ==============================================================================
# 字符串处理函数
# ==============================================================================

# 去除首尾空白
trim() {
    local var="$1"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    echo -n "${var}"
}

# 转义sed特殊字符
escape_sed_pattern() {
    local str="$1"
    echo "${str}" | sed 's/[[\.*^$()+?{|\\]/\\&/g'
}

# 转义Shell特殊字符
escape_shell_string() {
    local str="$1"
    printf '%q' "${str}"
}

# 转义正则表达式特殊字符
escape_regex() {
    local str="$1"
    echo "${str}" | sed 's/[[\.*^$()+?{|\\]/\\&/g'
}

# 转换为小写
to_lower() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

# 转换为大写
to_upper() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

# 检查字符串包含
string_contains() {
    local haystack="$1"
    local needle="$2"
    [[ "${haystack}" == *"${needle}"* ]]
}

# ==============================================================================
# 数组处理函数
# ==============================================================================

# 检查数组是否包含元素
array_contains() {
    local needle="$1"
    local haystack_name="$2"
    local -n arr_ref="${haystack_name}"

    for element in "${arr_ref[@]}"; do
        if [[ "${element}" == "${needle}" ]]; then
            return 0
        fi
    done
    return 1
}

# 数组去重
array_unique() {
    local array_name="$1"
    local -n arr_ref="${array_name}"
    local -A seen=()
    local -a unique=()

    for element in "${arr_ref[@]}"; do
        if [[ -z "${seen[${element}]:-}" ]]; then
            unique+=("${element}")
            seen["${element}"]=1
        fi
    done

    printf '%s\n' "${unique[@]}"
}

# 数组排序
array_sort() {
    local array_name="$1"
    local -n arr_ref="${array_name}"
    local -a sorted=("${arr_ref[@]}")

    printf '%s\n' "${sorted[@]}" | sort
}

# 数组反转
array_reverse() {
    local array_name="$1"
    local -n arr_ref="${array_name}"
    local -a reversed=()

    for ((i=${#arr_ref[@]}-1; i>=0; i--)); do
        reversed+=("${arr_ref[i]}")
    done

    printf '%s\n' "${reversed[@]}"
}

# ==============================================================================
# 时间处理函数
# ==============================================================================

# 获取当前时间戳
get_timestamp() {
    date +%s
}

# 获取当前时间戳（毫秒）
get_timestamp_ms() {
    date +%s%3N 2>/dev/null || echo "$(date +%s)000"
}

# 格式化时间戳
format_timestamp() {
    local timestamp="$1"
    local format="${2:-%Y-%m-%d %H:%M:%S}"
    date -d "@${timestamp}" +"${format}" 2>/dev/null || \
    date -r "${timestamp}" +"${format}" 2>/dev/null || \
    echo "${timestamp}"
}

# 计算时间差
time_diff() {
    local start_ts="$1"
    local end_ts="${2:-$(get_timestamp)}"
    echo $((end_ts - start_ts))
}

# 格式化持续时间
format_duration() {
    local seconds="$1"
    local days=$((seconds / 86400))
    local hours=$(( (seconds % 86400) / 3600 ))
    local minutes=$(( (seconds % 3600) / 60 ))
    local secs=$((seconds % 60))

    if [[ ${days} -gt 0 ]]; then
        echo "${days}天${hours}小时${minutes}分钟"
    elif [[ ${hours} -gt 0 ]]; then
        echo "${hours}小时${minutes}分钟"
    elif [[ ${minutes} -gt 0 ]]; then
        echo "${minutes}分钟${secs}秒"
    else
        echo "${secs}秒"
    fi
}

# ==============================================================================
# 进程管理函数
# ==============================================================================

# ==============================================================================
# 检查进程是否运行
# @param pid: 进程ID
# @return: 0运行中，1未运行
# @example: is_process_running "1234" && echo "进程运行中"
# ==============================================================================
is_process_running() {
    local pid="$1"
    [[ -d "/proc/${pid}" ]] 2>/dev/null
}

# 根据名称查找PID
find_pids_by_name() {
    local name="$1"
    pgrep -f "${name}" 2>/dev/null || echo ""
}

# 安全终止进程
kill_process_safe() {
    local pid="$1"
    local signal="${2:-TERM}"

    if ! validate_pid "${pid}"; then
        log_error "无效PID: ${pid}"
        return 1
    fi

    if kill -"${signal}" "${pid}" 2>/dev/null; then
        log_debug "已发送 ${pid} 信号 ${signal}"
        return 0
    else
        log_warn "无法发送信号到 ${pid} 使用 ${signal}"
        return 1
    fi
}

# 等待进程结束
wait_process() {
    local pid="$1"
    local timeout="${2:-30}"
    local elapsed=0

    while [[ ${elapsed} -lt ${timeout} ]] && is_process_running "${pid}"; do
        sleep 1
        ((elapsed++)) || true
    done

    if is_process_running "${pid}"; then
        log_warn "进程 ${pid} 在 ${timeout} 秒后未结束"
        return 1
    fi

    return 0
}

# ==============================================================================
# 网络函数
# ==============================================================================

# ==============================================================================
# 检查端口是否监听
# @param port: 端口号
# @param protocol: 协议类型（tcp/udp，默认tcp）
# @return: 0监听中，1未监听
# @example: is_port_listening "80" "tcp" && echo "端口80监听中"
# ==============================================================================
is_port_listening() {
    local port="$1"
    local protocol="${2:-tcp}"

    case "${protocol}" in
        tcp)
            ss -tln 2>/dev/null | grep -q ":${port} "
            ;;
        udp)
            ss -uln 2>/dev/null | grep -q ":${port} "
            ;;
        *)
            return 1
            ;;
    esac
}

# 获取本地IP地址
get_local_ip() {
    local iface="${1:-}"

    if [[ -n "${iface}" ]]; then
        ip addr show "${iface}" 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1
    else
        ip route get 1 2>/dev/null | awk '{print $7}' | head -1
    fi
}

# 检查网络连通性
check_connectivity() {
    local host="${1:-8.8.8.8}"
    local timeout="${2:-5}"
    local count="${3:-1}"

    ping -c "${count}" -W "${timeout}" "${host}" &>/dev/null
}

# ==============================================================================
# 包管理函数
# ==============================================================================
# 注意：包管理器检测和安装函数已移至 system.sh
# 使用 get_package_manager() 和 install_packages() 从 system.sh

# ==============================================================================
# 统一的服务管理接口
# ==============================================================================

# ==============================================================================
# 通用systemctl封装（兼容systemd和OpenRC）
# @param command: 服务操作命令（start/stop/restart/status等）
# @param service_name: 服务名称
# @return: 执行结果的退出码
# @description: 自动检测系统类型，使用正确的服务管理工具
# @example: systemctl_wrapper "start" "nginx"
# ==============================================================================
systemctl_wrapper() {
    local command="$1"
    local service_name="$2"

    if command -v apk &>/dev/null; then
        # Alpine Linux 使用 OpenRC
        service "${service_name}" "${command}"
    else
        # 其他发行版使用 systemd
        /bin/systemctl "${command}" "${service_name}"
    fi
}

# 启动服务
service_start() {
    local service_name="$1"
    if systemctl_wrapper start "${service_name}" &>/dev/null; then
        log_info "${service_name} 服务已启动"
        return 0
    else
        log_error "启动 ${service_name} 服务失败"
        return 1
    fi
}

# 停止服务
service_stop() {
    local service_name="$1"
    if systemctl_wrapper stop "${service_name}" &>/dev/null; then
        log_info "${service_name} 服务已停止"
        return 0
    else
        log_error "停止 ${service_name} 服务失败"
        return 1
    fi
}

# 重启服务
service_restart() {
    local service_name="$1"
    if systemctl_wrapper restart "${service_name}" &>/dev/null; then
        log_info "${service_name} 服务已重启"
        return 0
    else
        log_error "重启 ${service_name} 服务失败"
        return 1
    fi
}

# 查看服务状态
service_status() {
    local service_name="$1"
    systemctl_wrapper status "${service_name}"
}

# 启用开机自启
service_enable() {
    local service_name="$1"
    if command -v apk &>/dev/null; then
        # Alpine Linux
        rc-update add "${service_name}" default
    else
        # systemd
        /bin/systemctl enable "${service_name}" &>/dev/null
    fi
    log_info "${service_name} 已设置为开机自启"
}

# 禁用开机自启
service_disable() {
    local service_name="$1"
    if command -v apk &>/dev/null; then
        # Alpine Linux
        rc-update del "${service_name}" default
    else
        # systemd
        /bin/systemctl disable "${service_name}" &>/dev/null
    fi
    log_info "${service_name} 已禁用开机自启"
}

# 检查是否使用systemd
# 注意：check_systemd() 已移至 system.sh，使用该模块的版本
check_systemd() {
    # 检查systemd进程
    pgrep systemd &>/dev/null && [[ -d /run/systemd/system ]]
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f validate_positive_integer
export -f validate_number
export -f validate_float
export -f validate_filename
export -f validate_path
export -f validate_pid
export -f convert_size_to_mb
export -f convert_mb_to_human
export -f convert_bytes_to_human
export -f calculate_percentage
export -f compare_float
export -f calculate_average
export -f calculate_max
export -f calculate_min
export -f ensure_file_permissions
export -f ensure_dir_permissions
export -f safe_source
export -f save_config_file
export -f safe_delete
export -f check_command
export -f check_commands
export -f check_dependencies
export -f trim
export -f escape_sed_pattern
export -f escape_shell_string
export -f escape_regex
export -f to_lower
export -f to_upper
export -f string_contains
export -f get_timestamp
export -f get_timestamp_ms
export -f format_timestamp
export -f time_diff
export -f format_duration
export -f is_process_running
export -f find_pids_by_name
export -f kill_process_safe
export -f wait_process
export -f systemctl_wrapper
export -f service_start
export -f service_stop
export -f service_restart
export -f service_status
export -f service_enable
export -f service_disable
