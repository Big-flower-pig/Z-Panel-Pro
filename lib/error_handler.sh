#!/bin/bash
# ==============================================================================
# Z-Panel Pro V8.0 - 错误处理模块
# ==============================================================================
# @description    统一的错误处理与日志记录系统
# @version       8.0.0-Enterprise
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

# ==============================================================================
# 错误上下文堆栈
# ==============================================================================
declare -ga ERROR_CONTEXT_STACK=()
declare -gA ERROR_CONTEXT=()

# ==============================================================================
# 错误处理器注册表
# ==============================================================================
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

    # 记录错误信息
    LAST_ERROR_CONTEXT="${context}"
    LAST_ERROR_MESSAGE="${message}"
    LAST_ERROR_CODE=${exit_code}

    # 增加错误计数
    ((ERROR_COUNT++)) || true

    # 保存错误上下文
    ERROR_CONTEXT["${context}"]="${message}"

    # 添加到上下文堆栈
    ERROR_CONTEXT_STACK+=("${context}:${message}")

    # 记录错误日志
    log_error "[${context}] ${message}"

    # 调用自定义错误处理器
    local handler="${ERROR_HANDLERS[${context}]}"
    if [[ -n "${handler}" ]] && [[ -x "${handler}" ]]; then
        "${handler}" "${context}" "${message}" "${exit_code}" || true
    fi

    # 根据动作处理错误
    case "${action}" in
        continue)
            return 1
            ;;
        exit)
            log_critical "程序终止 (退出码: ${exit_code})"
            cleanup_on_exit
            exit ${exit_code}
            ;;
        abort)
            log_error "操作中止"
            return 2
            ;;
        retry)
            log_warn "重试操作"
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
            log_error "未知错误处理动作: ${action}"
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

    local attempt=1
    local result
    local current_delay=${delay}

    while [[ ${attempt} -le ${max_attempts} ]]; do
        if "${command[@]}"; then
            log_debug "命令执行成功 (尝试 ${attempt}/${max_attempts})"
            return 0
        fi

        local exit_code=$?
        log_warn "命令执行失败 (尝试 ${attempt}/${max_attempts}), 退出码: ${exit_code}"

        if [[ ${attempt} -lt ${max_attempts} ]]; then
            log_debug "等待 ${current_delay} 秒后重试..."
            sleep ${current_delay}

            # 指数退避
            if [[ "${backoff}" == "true" ]]; then
                current_delay=$((current_delay * 2))
            fi
        fi

        ((attempt++)) || true
    done

    log_error "命令执行失败，已达到最大重试次数 ${max_attempts}"
    return 1
}

# ==============================================================================
# 带超时的命令执行
# ==============================================================================
execute_with_timeout() {
    local timeout="$1"
    shift
    local command=("$@")

    # 使用系统timeout命令
    if command -v timeout &>/dev/null; then
        timeout "${timeout}" "${command[@]}"
        return $?
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
            log_error "命令执行超时: ${command[*]}"
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

    if [[ "${expected}" != "${actual}" ]]; then
        handle_error "ASSERTION" "${message}" "warn_only"
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

    if ! validate_number "${value}"; then
        handle_error "ASSERTION" "${var_name} 不是有效数字: ${value}" "warn_only"
        return 1
    fi

    if [[ ${value} -lt ${min} ]] || [[ ${value} -gt ${max} ]]; then
        handle_error "ASSERTION" "${var_name} 超出范围 [${min}, ${max}]: ${value}" "warn_only"
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
