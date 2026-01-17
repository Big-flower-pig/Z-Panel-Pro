#!/bin/bash
# ==============================================================================
# Z-Panel Pro - 通用工具函数库
# ==============================================================================
# @description    通用工具函数集合，包含验证、转换等操作
# @version       7.1.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 输入验证函数
# ==============================================================================

# 验证正整数
validate_positive_integer() {
    local var="$1"
    [[ "${var}" =~ ^[0-9]+$ ]] && [[ ${var} -gt 0 ]]
}

# 验证数字（包括负数）
validate_number() {
    local var="$1"
    [[ "${var}" =~ ^-?[0-9]+$ ]]
}

# 验证浮点数
validate_float() {
    local var="$1"
    [[ "${var}" =~ ^-?[0-9]+\.?[0-9]*$ ]]
}

# 验证文件名（安全字符）
validate_filename() {
    local filename="$1"
    # 只允许字母、数字、下划线、点、连字符
    [[ "${filename}" =~ ^[a-zA-Z0-9_.-]+$ ]]
}

# 验证路径（防止路径遍历）
validate_path() {
    local path="$1"
    # 防止路径遍历，必须是绝对路径
    [[ "${path}" != *".."* ]] && [[ "${path}" == /* ]]
}

# 验证PID有效性
validate_pid() {
    local pid="$1"
    [[ "${pid}" =~ ^[0-9]+$ ]] && [[ -d "/proc/${pid}" ]] && [[ -f "/proc/${pid}/cmdline" ]]
}

# ==============================================================================
# 单位转换函数
# ==============================================================================

# 将大小字符串转换为MB
# @param size: 大小字符串，如 "1G", "512M", "2048K"
# @return: 转换后的MB数值
convert_size_to_mb() {
    local size="$1"
    local unit
    local num

    # 提取单位和数值
    unit="${size//[0-9.]/}"
    num="${size//[KMGTiB]/}"

    # 处理单位
    case "${unit}" in
        G|Gi)
            echo "$((num * 1024))"
            ;;
        M|Mi)
            echo "${num}"
            ;;
        K|Ki)
            echo "$((num / 1024))"
            ;;
        B|b|"")
            echo "$((num / 1048576))"
            ;;
        *)
            log_warn "未知的单位: ${unit}, 默认为MB"
            echo "${num}"
            ;;
    esac
}

# 将MB转换为人类可读格式
# @param mb: MB数值
# @return: 人类可读的大小字符串
convert_mb_to_human() {
    local mb="$1"

    if [[ ${mb} -ge 1048576 ]]; then
        echo "$((mb / 1048576))GB"
    elif [[ ${mb} -ge 1024 ]]; then
        echo "$((mb / 1024))GB"
    else
        echo "${mb}MB"
    fi
}

# ==============================================================================
# 计算函数
# ==============================================================================

# 计算百分比
# @param used: 已使用量
# @param total: 总量
# @return: 百分比值（0-100）
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

# 安全的浮点数比较
# @param op: 比较操作符 (lt, le, eq, ne, ge, gt)
# @param val1: 第一个值
# @param val2: 第二个值
# @return: 0为真，1为假
compare_float() {
    local op="$1"
    local val1="$2"
    local val2="$3"

    awk "BEGIN { exit !(${val1} ${op} ${val2}) }"
}

# ==============================================================================
# 文件操作函数
# ==============================================================================

# 安全的文件权限设置
# @param file: 文件路径
# @param expected_perms: 期望的权限（八进制，默认600）
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
            log_debug "文件权限已更新: ${file} -> ${expected_perms}"
        fi
    fi
    return 0
}

# 安全的目录权限设置
# @param dir: 目录路径
# @param expected_perms: 期望的权限（八进制，默认700）
ensure_dir_permissions() {
    local dir="$1"
    local expected_perms="${2:-700}"

    if [[ -d "${dir}" ]]; then
        local actual_perms
        actual_perms=$(stat -c "%a" "${dir}" 2>/dev/null || stat -f "%OLp" "${dir}" 2>/dev/null || echo "000")

        if [[ "${actual_perms}" != "${expected_perms}" ]]; then
            chmod "${expected_perms}" "${dir}" 2>/dev/null || {
                log_error "无法设置目录权限: ${dir}"
                return 1
            }
            log_debug "目录权限已更新: ${dir} -> ${expected_perms}"
        fi
    fi
    return 0
}

# 安全的配置加载
# @param file: 配置文件路径
# @return: 0为成功，1为失败
safe_source() {
    local file="$1"

    # 检查文件是否存在
    if [[ ! -f "${file}" ]]; then
        log_error "配置文件不存在: ${file}"
        return 1
    fi

    # 检查文件权限
    ensure_file_permissions "${file}" 600 || return 1

    # 检查文件内容安全性（防止命令注入）
    local dangerous_patterns=(
        '`'
        '\$\([^)]*\)'
        '>'
        '<'
        '&'
        ';'
        '\|'
    )

    for pattern in "${dangerous_patterns[@]}"; do
        if grep -qE "${pattern}" "${file}" 2>/dev/null; then
            log_error "配置文件包含危险字符: ${file}"
            return 1
        fi
    done

    # 安全加载
    source "${file}"
    return 0
}

# 配置保存函数（统一处理）
# @param file: 目标文件路径
# @param content: 文件内容
# @return: 0为成功，1为失败
save_config_file() {
    local file="$1"
    local content="$2"

    # 创建目录
    mkdir -p "$(dirname "${file}")" 2>/dev/null || {
        log_error "无法创建目录: $(dirname "${file}")"
        return 1
    }

    # 设置目录权限
    chmod 700 "$(dirname "${file}")" 2>/dev/null || true

    # 写入文件
    echo "${content}" > "${file}" 2>/dev/null || {
        log_error "无法写入文件: ${file}"
        return 1
    }

    # 设置文件权限
    chmod 600 "${file}" 2>/dev/null || true

    log_debug "配置文件已保存: ${file}"
    return 0
}

# ==============================================================================
# 命令检查函数
# ==============================================================================

# 检查命令是否存在
# @param cmd: 命令名称
# @return: 0为存在，1为不存在
check_command() {
    local cmd="$1"
    command -v "${cmd}" &> /dev/null
}

# 批量检查命令依赖
# @param commands: 需要检查的命令数组
# @return: 0为全部存在，1为有缺失
check_commands() {
    local commands=("$@")
    local missing=()

    for cmd in "${commands[@]}"; do
        if ! check_command "${cmd}"; then
            missing+=("${cmd}")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "缺少必需命令: ${missing[*]}"
        return 1
    fi

    return 0
}

# 检查系统依赖
# @return: 0为满足，1为缺失
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
# 字符串处理函数
# ==============================================================================

# 去除字符串两端的空白
trim() {
    local var="$1"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    echo "${var}"
}

# 转义特殊字符（用于sed等）
escape_sed_pattern() {
    local str="$1"
    echo "${str}" | sed 's/[[\.*^$()+?{|\\]/\\&/g'
}

# 转义Shell特殊字符
escape_shell_string() {
    local str="$1"
    printf '%q' "${str}"
}

# ==============================================================================
# 数组操作函数
# ==============================================================================

# 检查数组是否包含元素
# @param needle: 要查找的元素
# @param haystack: 数组名（不加@）
# @return: 0为包含，1为不包含
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
# @param array_name: 数组名（不加@）
# @return: 去重后的数组
array_unique() {
    local array_name="$1"
    local -n arr_ref="${array_name}"
    local -a unique=()

    for element in "${arr_ref[@]}"; do
        if ! array_contains "${element}" unique; then
            unique+=("${element}")
        fi
    done

    printf '%s\n' "${unique[@]}"
}

# ==============================================================================
# 时间处理函数
# ==============================================================================

# 获取当前时间戳（秒）
get_timestamp() {
    date +%s
}

# 格式化时间戳
# @param timestamp: Unix时间戳
# @param format: 格式字符串（默认：%Y-%m-%d %H:%M:%S）
format_timestamp() {
    local timestamp="$1"
    local format="${2:-%Y-%m-%d %H:%M:%S}"
    date -d "@${timestamp}" +"${format}" 2>/dev/null || \
    date -r "${timestamp}" +"${format}" 2>/dev/null || \
    echo "${timestamp}"
}

# 计算时间差
# @param start_ts: 开始时间戳
# @param end_ts: 结束时间戳
# @return: 秒数
time_diff() {
    local start_ts="$1"
    local end_ts="${2:-$(get_timestamp)}"
    echo $((end_ts - start_ts))
}

# ==============================================================================
# 进程管理函数
# ==============================================================================

# 检查进程是否运行
# @param pid: 进程ID
# @return: 0为运行中，1为未运行
is_process_running() {
    local pid="$1"
    [[ -d "/proc/${pid}" ]] 2>/dev/null
}

# 通过名称查找进程PID
# @param name: 进程名
# @return: PID列表（每行一个）
find_pids_by_name() {
    local name="$1"
    pgrep -f "${name}" 2>/dev/null || echo ""
}

# 安全地杀死进程
# @param pid: 进程ID
# @param signal: 信号（默认TERM）
# @return: 0为成功，1为失败
kill_process_safe() {
    local pid="$1"
    local signal="${2:-TERM}"

    if ! validate_pid "${pid}"; then
        log_error "无效的PID: ${pid}"
        return 1
    fi

    if kill -"${signal}" "${pid}" 2>/dev/null; then
        log_debug "进程 ${pid} 已发送 ${signal} 信号"
        return 0
    else
        log_warn "无法向进程 ${pid} 发送 ${signal} 信号"
        return 1
    fi
}