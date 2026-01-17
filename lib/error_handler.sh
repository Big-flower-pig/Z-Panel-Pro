#!/bin/bash
# ==============================================================================
# Z-Panel Pro - 错误处理模块
# ==============================================================================
# @description    统一的错误处理与异常管理机制
# @version       7.1.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 日志级别定义
# ==============================================================================
declare -gr LOG_LEVEL_DEBUG=0
declare -gr LOG_LEVEL_INFO=1
declare -gr LOG_LEVEL_WARN=2
declare -gr LOG_LEVEL_ERROR=3

# ==============================================================================
# 全局错误状态
# ==============================================================================
declare -g CURRENT_LOG_LEVEL=${LOG_LEVEL_DEBUG}
declare -g ERROR_COUNT=0
declare -g LAST_ERROR_CONTEXT=""
declare -g LAST_ERROR_MESSAGE=""

# ==============================================================================
# 错误上下文追踪
# ==============================================================================
declare -gA ERROR_CONTEXT=()

# ==============================================================================
# 统一日志函数
# ==============================================================================
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
        echo -e "${color}${timestamp}${prefix}${COLOR_NC} ${message}"
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

# ==============================================================================
# 错误处理函数
# ==============================================================================
handle_error() {
    local context="$1"
    local message="$2"
    local action="${3:-continue}"
    local exit_code="${4:-1}"

    # 记录错误信息
    LAST_ERROR_CONTEXT="${context}"
    LAST_ERROR_MESSAGE="${message}"

    # 更新错误计数
    ((ERROR_COUNT++)) || true

    # 记录错误上下文
    ERROR_CONTEXT["${context}"]="${message}"

    # 记录日志
    log_error "[${context}] ${message}"

    # 根据动作类型处理
    case "${action}" in
        continue)
            return 1
            ;;
        exit)
            log_error "严重错误，退出程序 (代码: ${exit_code})"
            exit ${exit_code}
            ;;
        abort)
            log_error "操作中止"
            return 2
            ;;
        retry)
            log_warn "操作将重试"
            return 3
            ;;
        warn_only)
            log_warn "警告: ${message}"
            return 0
            ;;
        *)
            log_error "未知的错误处理动作: ${action}"
            return 1
            ;;
    esac
}

# ==============================================================================
# 带重试的操作执行
# ==============================================================================
execute_with_retry() {
    local max_attempts="$1"
    local delay="$2"
    shift 2
    local command=("$@")

    local attempt=1
    local result

    while [[ ${attempt} -le ${max_attempts} ]]; do
        if "${command[@]}"; then
            log_debug "操作成功 (尝试 ${attempt}/${max_attempts})"
            return 0
        fi

        local exit_code=$?
        log_warn "操作失败 (尝试 ${attempt}/${max_attempts}), 退出码: ${exit_code}"

        if [[ ${attempt} -lt ${max_attempts} ]]; then
            log_debug "等待 ${delay} 秒后重试..."
            sleep ${delay}
        fi

        ((attempt++)) || true
    done

    log_error "操作在 ${max_attempts} 次尝试后仍然失败"
    return 1
}

# ==============================================================================
# 获取最后错误信息
# ==============================================================================
get_last_error() {
    echo "[${LAST_ERROR_CONTEXT}] ${LAST_ERROR_MESSAGE}"
}

# ==============================================================================
# 重置错误状态
# ==============================================================================
reset_error_state() {
    ERROR_COUNT=0
    LAST_ERROR_CONTEXT=""
    LAST_ERROR_MESSAGE=""
    ERROR_CONTEXT=()
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
    local var_name="${2:-变量}"

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

assert_command_exists() {
    local cmd="$1"
    local message="${2:-命令不存在: ${cmd}}"

    if ! command -v "${cmd}" &> /dev/null; then
        handle_error "ASSERTION" "${message}" "warn_only"
        return 1
    fi
    return 0
}

# ==============================================================================
# 初始化日志目录
# ==============================================================================
init_logging() {
    mkdir -p "${LOG_DIR}" 2>/dev/null || {
        echo "无法创建日志目录: ${LOG_DIR}" >&2
        return 1
    }
    chmod 750 "${LOG_DIR}" 2>/dev/null || true
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
        *)
            log_warn "无效的日志级别: ${level}, 使用默认值 INFO"
            CURRENT_LOG_LEVEL=${LOG_LEVEL_INFO}
            ;;
    esac

    log_info "日志级别已设置为: ${level}"
}