#!/bin/bash
# ==============================================================================
# Z-Panel Pro - 输入验证模块
# ==============================================================================
# @description    统一的输入验证与清理机制
# @version       7.2.0-Security
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 白名单验证
# ==============================================================================

# 验证配置键名
validate_config_key() {
    local key="$1"
    # 只允许字母、数字、下划线、点
    [[ "${key}" =~ ^[a-zA-Z_][a-zA-Z0-9_.]*$ ]]
}

# 验证路径（防止路径遍历）
validate_path_safe() {
    local path="$1"

    # 必须是绝对路径
    [[ "${path}" == /* ]] || return 1

    # 防止路径遍历
    [[ "${path}" != *".."* ]] || return 1

    # 防止空字节
    [[ "${path}" != *$'\0'* ]] || return 1

    return 0
}

# 解析并验证路径
resolve_safe_path() {
    local path="$1"
    local base_dir="${2:-}"

    # 验证原始路径
    validate_path_safe "${path}" || return 1

    # 使用 realpath 解析路径
    local resolved
    resolved=$(realpath -m "${path}" 2>/dev/null) || return 1

    # 验证解析后的路径
    validate_path_safe "${resolved}" || return 1

    # 如果提供了基础目录，验证路径在其下
    if [[ -n "${base_dir}" ]]; then
        local base_resolved
        base_resolved=$(realpath -m "${base_dir}" 2>/dev/null) || return 1

        # 检查解析后的路径是否在基础目录下
        case "${resolved}" in
            "${base_resolved}"*)
                echo "${resolved}"
                return 0
                ;;
            *)
                log_error "路径不在允许的目录下: ${resolved}"
                return 1
                ;;
        esac
    fi

    echo "${resolved}"
    return 0
}

# 验证文件名
validate_filename_safe() {
    local filename="$1"

    # 只允许字母、数字、下划线、点、连字符
    [[ "${filename}" =~ ^[a-zA-Z0-9_.-]+$ ]] && \
    [[ "${filename}" != ".." ]] && \
    [[ "${filename}" != "." ]] && \
    [[ "${filename}" != "..." ]]
}

# 验证包名称
validate_package_name() {
    local pkg="$1"
    # Linux 包命名规范
    [[ "${pkg}" =~ ^[a-z0-9][a-z0-9+.-]*$ ]]
}

# 验证整数
validate_integer() {
    local value="$1"
    [[ "${value}" =~ ^-?[0-9]+$ ]]
}

# 验证正整数
validate_positive_integer() {
    local value="$1"
    validate_integer "${value}" && [[ ${value} -gt 0 ]]
}

# 验证整数范围
validate_integer_range() {
    local value="$1"
    local min="$2"
    local max="$3"

    validate_integer "${value}" || return 1
    [[ ${value} -ge ${min} ]] && [[ ${value} -le ${max} ]]
}

# 验证浮点数
validate_float() {
    local value="$1"
    [[ "${value}" =~ ^-?[0-9]+\.?[0-9]*$ ]]
}

# 验证 sysctl 键
validate_sysctl_key() {
    local key="$1"
    # 白名单：只允许 vm.*, fs.*, net.*
    [[ "${key}" =~ ^(vm|fs|net)\.[a-zA-Z0-9_.]+$ ]]
}

# 验证 sysctl 值
validate_sysctl_value() {
    local value="$1"
    # 允许数字、点、连字符
    [[ "${value}" =~ ^[0-9.-]+$ ]]
}

# 验证 PID
validate_pid() {
    local pid="$1"
    validate_positive_integer "${pid}" && \
    [[ -d "/proc/${pid}" ]] && \
    [[ -f "/proc/${pid}/cmdline" ]]
}

# 验证端口号
validate_port() {
    local port="$1"
    validate_integer_range "${port}" 1 65535
}

# 验证 IP 地址
validate_ip_address() {
    local ip="$1"
    local ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'

    [[ "${ip}" =~ ${ip_regex} ]] || return 1

    # 验证每个段
    local IFS='.'
    read -ra octets <<< "${ip}"

    for octet in "${octets[@]}"; do
        [[ ${octet} -ge 0 ]] && [[ ${octet} -le 255 ]] || return 1
    done

    return 0
}

# 验证 URL
validate_url() {
    local url="$1"
    [[ "${url}" =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]+)?(/.*)?$ ]]
}

# ==============================================================================
# 输入清理
# ==============================================================================

# 清理 shell 元字符
sanitize_shell_input() {
    local input="$1"
    # 移除危险字符
    echo "${input}" | sed 's/[;&|`$()<>]/_/g'
}

# 清理路径输入
sanitize_path_input() {
    local input="$1"
    # 移除路径遍历字符
    echo "${input}" | sed 's/\.\.//g' | sed 's/^\///'
}

# 清理用户输入
sanitize_user_input() {
    local input="$1"
    # 移除 ANSI 转义序列
    local cleaned="${input}"

    # 使用参数扩展移除 ANSI 转义码
    while [[ "${cleaned}" == *$'\e'* ]]; do
        cleaned="${cleaned%%$'\e'*}${cleaned#*m}"
    done

    echo "${cleaned}"
}

# 清理日志消息（脱敏）
sanitize_log_message() {
    local message="$1"

    # 脱敏 IP 地址
    message=$(echo "${message}" | sed 's/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/***.***.***.***/g')

    # 脱敏路径
    message=$(echo "${message}" | sed 's|/home/[^/]\+/|/home/***/|g')

    # 脱敏用户名
    message=$(echo "${message}" | sed 's/user=[^[:space:]]\+/user=***/g')

    echo "${message}"
}

# ==============================================================================
# 长度限制
# ==============================================================================

# 验证输入长度
validate_input_length() {
    local input="$1"
    local max_length="${2:-255}"

    [[ ${#input} -le ${max_length} ]]
}

# 截断输入
truncate_input() {
    local input="$1"
    local max_length="${2:-255}"

    if [[ ${#input} -gt ${max_length} ]]; then
        echo "${input:0:${max_length}}"
    else
        echo "${input}"
    fi
}

# ==============================================================================
# 安全的配置文件解析
# ==============================================================================

# 安全读取配置
safe_read_config() {
    local file="$1"
    local key="$2"
    local default="${3:-}"

    # 验证文件存在
    [[ -f "${file}" ]] || { echo "${default}"; return 1; }

    # 验证键名
    validate_config_key "${key}" || { echo "${default}"; return 1; }

    # 安全读取
    local value
    value=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "${file}" 2>/dev/null | \
             sed "s/^[[:space:]]*${key}[[:space:]]*=//" | \
             sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
             head -1)

    # 移除引号
    value="${value%\"}"
    value="${value#\'}"
    value="${value%\"*}"
    value="${value#\'}*"

    echo "${value:-${default}}"
}

# 安全写入配置
safe_write_config() {
    local file="$1"
    local key="$2"
    local value="$3"

    # 验证键名
    validate_config_key "${key}" || return 1

    # 验证值
    [[ -n "${value}" ]] || return 1

    # 验证值不包含危险字符
    if [[ "${value}" =~ \$\(|`|\$\(.*\)|`.*` ]]; then
        log_error "配置值包含危险字符: ${key}"
        return 1
    fi

    # 创建目录
    mkdir -p "$(dirname "${file}")" || return 1

    # 设置目录权限
    chmod 700 "$(dirname "${file}")" || true

    # 创建临时文件
    local temp_file
    temp_file=$(mktemp "${file}.tmp.XXXXXX") || return 1

    # 复制原文件（如果存在）
    if [[ -f "${file}" ]]; then
        cp "${file}" "${temp_file}" || {
            rm -f "${temp_file}"
            return 1
        }
    fi

    # 更新或添加配置
    if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "${temp_file}" 2>/dev/null; then
        # 更新现有配置
        sed -i "s/^[[:space:]]*${key}[[:space:]]*=.*/${key}=${value}/" "${temp_file}"
    else
        # 添加新配置
        echo "${key}=${value}" >> "${temp_file}"
    fi

    # 原子移动
    if ! mv "${temp_file}" "${file}"; then
        rm -f "${temp_file}"
        return 1
    fi

    # 设置文件权限
    chmod 600 "${file}" || true
    chown root:root "${file}" 2>/dev/null || true

    return 0
}

# ==============================================================================
# 批量验证
# ==============================================================================

# 批量验证配置
validate_config_batch() {
    local file="$1"
    shift
    local required_keys=("$@")

    # 验证文件存在
    [[ -f "${file}" ]] || return 1

    local missing=()

    for key in "${required_keys[@]}"; do
        local value
        value=$(safe_read_config "${file}" "${key}")

        if [[ -z "${value}" ]]; then
            missing+=("${key}")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "缺少必需的配置: ${missing[*]}"
        return 1
    fi

    return 0
}
