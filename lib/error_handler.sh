#!/bin/bash
# ==============================================================================
# Z-Panel Pro V9.0 - 错误处理模块
# ==============================================================================
# @description    统一的错误处理与日志记录系统
# @version       9.0.0-Lightweight
# @author        Z-Panel Team
# @license       MIT License
# ==============================================================================

# ==============================================================================
# 日志级别常量
# ==============================================================================
declare -gr LOG_LEVEL_DEBUG=0
declare -gr LOG_LEVEL_INFO=1
declare -gr LOG_LEVEL_WARN=2
declare -gr LOG_LEVEL_ERROR=3
declare -gr LOG_LEVEL_CRITICAL=4

# ==============================================================================
# 错误状态变量
# ==============================================================================
declare -g CURRENT_LOG_LEVEL=${LOG_LEVEL_INFO}
declare -g ERROR_COUNT=0
declare -g WARN_COUNT=0
declare -g LAST_ERROR_CONTEXT=""
declare -g LAST_ERROR_MESSAGE=""
declare -g LAST_ERROR_CODE=0
declare -gA ERROR_CONTEXT=()
declare -ga ERROR_CONTEXT_STACK=()
declare -gA ERROR_HANDLERS=()

# ==============================================================================
# 日志配置
# ==============================================================================
declare -g LOG_FORMAT="timestamp,level,message"
declare -g LOG_DATE_FORMAT="%Y-%m-%d %H:%M:%S"
declare -g LOG_ENABLE_COLORS=true
declare -g LOG_ENABLE_FILE=true
declare -g LOG_MAX_FILE_SIZE_MB=50

# ==============================================================================
# 日志记录
# ==============================================================================
log_message() {
    local level=$1
    shift
    local message="$*"
    local timestamp="[${LOG_DATE_FORMAT:+$(date +"${LOG_DATE_FORMAT}")}]"

    local level_str color prefix
    case ${level} in
        ${LOG_LEVEL_DEBUG})
            level_str="DEBUG"
            color="${COLOR_CYAN}"
            prefix="[DEBUG]"
            ;;
        ${LOG_LEVEL_INFO})
            level_str="INFO"
            color="${COLOR_GREEN}"
            prefix="[INFO]"
            ;;
        ${LOG_LEVEL_WARN})
            level_str="WARN"
            color="${COLOR_YELLOW}"
            prefix="[WARN]"
            ((WARN_COUNT++)) || true
            ;;
        ${LOG_LEVEL_ERROR})
            level_str="ERROR"
            color="${COLOR_RED}"
            prefix="[ERROR]"
            ((ERROR_COUNT++)) || true
            ;;
        ${LOG_LEVEL_CRITICAL})
            level_str="CRITICAL"
            color="${COLOR_RED}"
            prefix="[CRITICAL]"
            ((ERROR_COUNT++)) || true
            ;;
        *)
            level_str="LOG"
            color="${COLOR_NC}"
            prefix="[LOG]"
            ;;
    esac

    # 输出到控制台
    if [[ ${level} -ge ${CURRENT_LOG_LEVEL} ]]; then
        if [[ "${LOG_ENABLE_COLORS}" == "true" ]]; then
            echo -e "${color}${timestamp}${prefix}${COLOR_NC} ${message}"
        else
            echo "${timestamp}${prefix} ${message}"
        fi
    fi

    # 输出到文件
    if [[ "${LOG_ENABLE_FILE}" == "true" ]] && [[ -d "${LOG_DIR}" ]]; then
        local log_file="${LOG_DIR}/zpanel_$(date +%Y%m%d).log"
        local log_line="${timestamp}${prefix} ${message}"

        # 检查文件大小并轮转
        if [[ -f "${log_file}" ]]; then
            local file_size_mb
            file_size_mb=$(du -m "${log_file}" 2>/dev/null | cut -f1 || echo "0")
            if [[ ${file_size_mb} -ge ${LOG_MAX_FILE_SIZE_MB} ]]; then
                mv "${log_file}" "${log_file}.old" 2>/dev/null || true
            fi
        fi

        echo "${log_line}" >> "${log_file}" 2>/dev/null || true
    fi
}

log_debug() { log_message ${LOG_LEVEL_DEBUG} "$@"; }
log_info() { log_message ${LOG_LEVEL_INFO} "$@"; }
log_warn() { log_message ${LOG_LEVEL_WARN} "$@"; }
log_error() { log_message ${LOG_LEVEL_ERROR} "$@"; }
log_critical() { log_message ${LOG_LEVEL_CRITICAL} "$@"; }

# ==============================================================================
# 错误处理
# ==============================================================================
handle_error() {
    local context="$1"
    local message="$2"
    local action="${3:-continue}"
    local exit_code="${4:-1}"

    # 参数验证
    if [[ -z "${context}" ]]; then
        context="UNKNOWN"
    fi

    if [[ -z "${message}" ]]; then
        message="未知错误"
    fi

    # 记录错误信息
    LAST_ERROR_CONTEXT="${context}"
    LAST_ERROR_MESSAGE="${message}"
    LAST_ERROR_CODE=${exit_code}

    # 增加错误计数
    ((ERROR_COUNT++)) || true

    # 保存错误上下文（包含时间戳）
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    ERROR_CONTEXT["${context}"]="${timestamp} | ${message}"

    # 添加到上下文堆栈（包含更多上下文信息）
    local stack_entry="${timestamp} | ${context} | ${message}"
    ERROR_CONTEXT_STACK+=("${stack_entry}")

    # 构建详细的错误信息
    local error_detail="[${context}] ${message}"
    error_detail+=" | 退出码: ${exit_code}"

    # 添加系统状态信息
    if [[ -n "${SYSTEM_INFO[total_memory_mb]:-}" ]]; then
        error_detail+=" | 内存: ${SYSTEM_INFO[total_memory_mb]}MB"
    fi

    if [[ -n "${SYSTEM_INFO[cpu_cores]:-}" ]]; then
        error_detail+=" | CPU核心: ${SYSTEM_INFO[cpu_cores]}"
    fi

    # 添加函数调用栈（如果可用）
    if [[ ${#ERROR_CONTEXT_STACK[@]} -gt 1 ]]; then
        error_detail+=" | 调用栈深度: ${#ERROR_CONTEXT_STACK[@]}"
    fi

    # 记录错误日志
    log_error "${error_detail}"

    # 调用自定义错误处理器
    local handler=""
    if [[ -v "ERROR_HANDLERS[${context}]" ]] 2>/dev/null; then
        handler="${ERROR_HANDLERS[${context}]}"
    fi
    if [[ -n "${handler}" ]] && [[ -x "${handler}" ]]; then
        "${handler}" "${context}" "${message}" "${exit_code}" || true
    fi

    # 根据动作处理错误
    case "${action}" in
        continue)
            return 1
            ;;
        exit)
            log_critical "程序终止 (退出码: ${exit_code}) | 总错误数: ${ERROR_COUNT}"
            cleanup_on_exit
            exit ${exit_code}
            ;;
        abort)
            log_error "操作中止 | 上下文: ${context}"
            return 2
            ;;
        retry)
            log_warn "重试操作 | 错误: ${message}"
            return 3
            ;;
        warn_only)
            log_warn "警告: ${message}"
            return 0
            ;;
        silent)
            return 1
            ;;
        *)
            log_error "未知错误处理动作: ${action} | 使用默认: continue"
            return 1
            ;;
    esac
}

# ==============================================================================
# 错误上下文管理
# ==============================================================================
push_error_context() {
    local context="$1"
    ERROR_CONTEXT_STACK+=("${context}")
}

pop_error_context() {
    [[ ${#ERROR_CONTEXT_STACK[@]} -gt 0 ]] && ERROR_CONTEXT_STACK=("${ERROR_CONTEXT_STACK[@]:0:${#ERROR_CONTEXT_STACK[@]}-1}")
}

get_error_context_stack() {
    local separator="${1:-" -> "}"
    local stack=""
    for entry in "${ERROR_CONTEXT_STACK[@]}"; do
        stack+="${entry}${separator}"
    done
    echo "${stack%${separator}}"
}

# ==============================================================================
# 带重试的命令执行
# ==============================================================================
execute_with_retry() {
    local max_attempts="$1"
    local delay="$2"
    local backoff="${3:-false}"
    shift 3
    local command=("$@")

    # 参数验证
    if ! validate_positive_integer "${max_attempts}"; then
        log_error "无效的最大重试次数: ${max_attempts}，使用默认值: 3"
        max_attempts=3
    fi

    # 边界检查：最大重试次数
    if [[ ${max_attempts} -gt 100 ]]; then
        log_warn "最大重试次数过大 (${max_attempts})，调整为: 100"
        max_attempts=100
    fi

    if ! validate_positive_integer "${delay}"; then
        log_error "无效的延迟时间: ${delay}，使用默认值: 1"
        delay=1
    fi

    # 边界检查：延迟时间
    if [[ ${delay} -gt 3600 ]]; then
        log_warn "延迟时间过大 (${delay}秒)，调整为: 3600秒"
        delay=3600
    fi

    local attempt=1
    local result
    local current_delay=${delay}
    local command_str="${command[*]}"

    log_debug "开始执行命令 (最大重试: ${max_attempts}, 初始延迟: ${delay}秒): ${command_str}"

    while [[ ${attempt} -le ${max_attempts} ]]; do
        if "${command[@]}"; then
            log_debug "命令执行成功 (尝试 ${attempt}/${max_attempts})"
            return 0
        fi

        local exit_code=$?
        log_warn "命令执行失败 (尝试 ${attempt}/${max_attempts}), 退出码: ${exit_code} | 命令: ${command_str}"

        if [[ ${attempt} -lt ${max_attempts} ]]; then
            log_debug "等待 ${current_delay} 秒后重试..."
            sleep ${current_delay}

            # 指数退避
            if [[ "${backoff}" == "true" ]]; then
                local new_delay=$((current_delay * 2))
                # 限制最大延迟为300秒（5分钟）
                if [[ ${new_delay} -gt 300 ]]; then
                    new_delay=300
                fi
                log_debug "指数退避: ${current_delay}秒 -> ${new_delay}秒"
                current_delay=${new_delay}
            fi
        fi

        ((attempt++)) || true
    done

    log_error "命令执行失败，已达到最大重试次数 ${max_attempts} | 命令: ${command_str}"
    return 1
}

# ==============================================================================
# 带超时的命令执行
# ==============================================================================
execute_with_timeout() {
    local timeout="$1"
    shift
    local command=("$@")
    local command_str="${command[*]}"

    # 参数验证
    if ! validate_positive_integer "${timeout}"; then
        log_error "无效的超时时间: ${timeout}，使用默认值: 30"
        timeout=30
    fi

    # 边界检查：超时时间
    if [[ ${timeout} -gt 86400 ]]; then
        log_warn "超时时间过大 (${timeout}秒)，调整为: 86400秒 (24小时)"
        timeout=86400
    fi

    log_debug "执行命令 (超时: ${timeout}秒): ${command_str}"

    # 使用系统timeout命令
    if command -v timeout &>/dev/null; then
        timeout "${timeout}" "${command[@]}"
        local exit_code=$?
        if [[ ${exit_code} -eq 124 ]]; then
            log_error "命令执行超时 (${timeout}秒): ${command_str}"
        fi
        return ${exit_code}
    else
        # 手动实现超时
        "${command[@]}" &
        local pid=$!
        local elapsed=0

        while [[ ${elapsed} -lt ${timeout} ]] && kill -0 ${pid} 2>/dev/null; do
            sleep 1
            ((elapsed++)) || true
        done

        if kill -0 ${pid} 2>/dev/null; then
            kill ${pid} 2>/dev/null || true
            wait ${pid} 2>/dev/null || true
            log_error "命令执行超时 (${timeout}秒): ${command_str}"
            return 124
        fi

        wait ${pid}
        return $?
    fi
}

# ==============================================================================
# 错误信息查询
# ==============================================================================
get_last_error() {
    echo "[${LAST_ERROR_CONTEXT}] ${LAST_ERROR_MESSAGE} (退出码: ${LAST_ERROR_CODE})"
}

# ==============================================================================
# 重置错误状态
# ==============================================================================
reset_error_state() {
    ERROR_COUNT=0
    WARN_COUNT=0
    LAST_ERROR_CONTEXT=""
    LAST_ERROR_MESSAGE=""
    LAST_ERROR_CODE=0
    ERROR_CONTEXT=()
    ERROR_CONTEXT_STACK=()
}

# ==============================================================================
# 获取错误统计
# ==============================================================================
get_error_stats() {
    cat <<EOF
{
    "error_count": ${ERROR_COUNT},
    "warn_count": ${WARN_COUNT},
    "last_error": {
        "context": "${LAST_ERROR_CONTEXT}",
        "message": "${LAST_ERROR_MESSAGE}",
        "code": ${LAST_ERROR_CODE}
    },
    "context_stack_size": ${#ERROR_CONTEXT_STACK[@]}
}
EOF
}

# ==============================================================================
# 错误处理器注册
# ==============================================================================
register_error_handler() {
    local context="$1"
    local handler="$2"

    if [[ ! -x "${handler}" ]]; then
        log_error "错误处理器不可执行: ${handler}"
        return 1
    fi

    ERROR_HANDLERS["${context}"]="${handler}"
    log_debug "错误处理器已注册: ${context} -> ${handler}"
    return 0
}

# ==============================================================================
# 断言函数
# ==============================================================================
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-断言失败: 期望 '${expected}', 实际 '${actual}'}"

    # 参数验证
    if [[ -z "${expected}" ]] || [[ -z "${actual}" ]]; then
        handle_error "ASSERTION" "断言参数不能为空 | 期望: '${expected}', 实际: '${actual}'" "warn_only"
        return 1
    fi

    if [[ "${expected}" != "${actual}" ]]; then
        local detail="${message} | 类型: ${expected_type} | 长度: ${#expected} vs ${#actual}"
        handle_error "ASSERTION" "${detail}" "warn_only"
        return 1
    fi
    return 0
}

assert_not_empty() {
    local value="$1"
    local var_name="${2:-值}"

    if [[ -z "${value}" ]]; then
        handle_error "ASSERTION" "${var_name} 不能为空" "warn_only"
        return 1
    fi
    return 0
}

assert_file_exists() {
    local file="$1"
    local message="${2:-文件不存在: ${file}}"

    if [[ ! -f "${file}" ]]; then
        handle_error "ASSERTION" "${message}" "warn_only"
        return 1
    fi
    return 0
}

assert_dir_exists() {
    local dir="$1"
    local message="${2:-目录不存在: ${dir}}"

    if [[ ! -d "${dir}" ]]; then
        handle_error "ASSERTION" "${message}" "warn_only"
        return 1
    fi
    return 0
}

assert_command_exists() {
    local cmd="$1"
    local message="${2:-命令不存在: ${cmd}}"

    if ! command -v "${cmd}" &> /dev/null; then
        handle_error "ASSERTION" "${message}" "warn_only"
        return 1
    fi
    return 0
}

assert_number_range() {
    local value="$1"
    local min="$2"
    local max="$3"
    local var_name="${4:-值}"

    # 参数验证
    if [[ -z "${value}" ]]; then
        handle_error "ASSERTION" "${var_name} 不能为空" "warn_only"
        return 1
    fi

    if ! validate_number "${value}"; then
        handle_error "ASSERTION" "${var_name} 不是有效数字: ${value} | 类型: $(typeof "${value}" 2>/dev/null || echo 'unknown')" "warn_only"
        return 1
    fi

    # 边界检查：min和max
    if [[ ${min} -gt ${max} ]]; then
        handle_error "ASSERTION" "范围参数错误: min (${min}) > max (${max})" "warn_only"
        return 1
    fi

    if [[ ${value} -lt ${min} ]] || [[ ${value} -gt ${max} ]]; then
        local diff_min=$((value - min))
        local diff_max=$((max - value))
        handle_error "ASSERTION" "${var_name} 超出范围 [${min}, ${max}]: ${value} | 偏差: min+${diff_min}, max-${diff_max}" "warn_only"
        return 1
    fi
    return 0
}

# ==============================================================================
# 日志初始化
# ==============================================================================
init_logging() {
    mkdir -p "${LOG_DIR}" 2>/dev/null || {
        echo "无法创建日志目录: ${LOG_DIR}" >&2
        return 1
    }
    chmod 750 "${LOG_DIR}" 2>/dev/null || true

    # 清理旧日志
    local retention_days="${CONFIG_CENTER[log_retention_days]:-30}"
    find "${LOG_DIR}" -name "zpanel_*.log" -mtime +${retention_days} -delete 2>/dev/null || true

    return 0
}

# ==============================================================================
# 设置日志级别
# ==============================================================================
set_log_level() {
    local level="$1"

    case "${level}" in
        0|debug|DEBUG)
            CURRENT_LOG_LEVEL=${LOG_LEVEL_DEBUG}
            ;;
        1|info|INFO)
            CURRENT_LOG_LEVEL=${LOG_LEVEL_INFO}
            ;;
        2|warn|WARN)
            CURRENT_LOG_LEVEL=${LOG_LEVEL_WARN}
            ;;
        3|error|ERROR)
            CURRENT_LOG_LEVEL=${LOG_LEVEL_ERROR}
            ;;
        4|critical|CRITICAL)
            CURRENT_LOG_LEVEL=${LOG_LEVEL_CRITICAL}
            ;;
        *)
            log_warn "未知日志级别: ${level}, 使用默认: INFO"
            CURRENT_LOG_LEVEL=${LOG_LEVEL_INFO}
            ;;
    esac

    log_info "日志级别已设置为: ${level}"
}

# ==============================================================================
# 设置日志格式
# ==============================================================================
set_log_format() {
    local format="$1"
    LOG_FORMAT="${format}"
    log_debug "日志格式已设置为: ${format}"
}

# ==============================================================================
# 退出清理
# ==============================================================================
cleanup_on_exit() {
    log_debug "执行退出清理..."
    # 清理资源
    # 释放锁
    # 关闭连接
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f log_message
export -f log_debug
export -f log_info
export -f log_warn
export -f log_error
export -f log_critical
export -f handle_error
export -f push_error_context
export -f pop_error_context
export -f get_error_context_stack
export -f execute_with_retry
export -f execute_with_timeout
export -f get_last_error
export -f reset_error_state
export -f get_error_stats
export -f register_error_handler
export -f init_logging
export -f set_log_level
export -f set_log_format
export -f assert_equals
export -f assert_not_empty
export -f assert_file_exists
export -f assert_dir_exists
export -f assert_command_exists
export -f assert_number_range
