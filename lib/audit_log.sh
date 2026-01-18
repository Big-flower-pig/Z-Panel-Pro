#!/bin/bash
# ==============================================================================
# Z-Panel Pro V9.0 - 审计日志模块
# ==============================================================================
# @description    安全审计日志记录
# @version       9.0.0-Lightweight
# @author        Z-Panel Team
# @license       MIT License
# ==============================================================================

# ==============================================================================
# 审计日志配置
# ==============================================================================
declare -g AUDIT_LOG_DIR="${LOG_DIR}/audit"
declare -g AUDIT_LOG_FILE="${AUDIT_LOG_DIR}/audit.log"
declare -g AUDIT_LOG_MAX_SIZE_MB=100
declare -g AUDIT_LOG_RETENTION_DAYS=90
declare -g AUDIT_ENABLED=true

# ==============================================================================
# 审计事件类型
# ==============================================================================
readonly AUDIT_EVENT_SYSTEM_START="system_start"
readonly AUDIT_EVENT_SYSTEM_STOP="system_stop"
readonly AUDIT_EVENT_CONFIG_CHANGE="config_change"
readonly AUDIT_EVENT_ZRAM_ENABLE="zram_enable"
readonly AUDIT_EVENT_ZRAM_DISABLE="zram_disable"
readonly AUDIT_EVENT_SWAP_CREATE="swap_create"
readonly AUDIT_EVENT_SWAP_DELETE="swap_delete"
readonly AUDIT_EVENT_STRATEGY_CHANGE="strategy_change"
readonly AUDIT_EVENT_KERNEL_PARAM_CHANGE="kernel_param_change"
readonly AUDIT_EVENT_OPTIMIZE="optimize"
readonly AUDIT_EVENT_AUTH="authentication"
readonly AUDIT_EVENT_PRIVILEGE="privilege_escalation"
readonly AUDIT_EVENT_ERROR="error"

# ==============================================================================
# 审计日志初始化
# ==============================================================================

# 初始化审计日志
init_audit_log() {
    [[ "${AUDIT_ENABLED}" != "true" ]] && return 0

    # 创建审计日志目录
    mkdir -p "${AUDIT_LOG_DIR}" 2>/dev/null || {
        log_error "无法创建审计日志目录: ${AUDIT_LOG_DIR}"
        return 1
    }

    chmod 700 "${AUDIT_LOG_DIR}" 2>/dev/null || true

    # 设置文件权限
    if [[ ! -f "${AUDIT_LOG_FILE}" ]]; then
        touch "${AUDIT_LOG_FILE}" 2>/dev/null
        chmod 600 "${AUDIT_LOG_FILE}" 2>/dev/null || true
    fi

    # 清理旧日志
    find "${AUDIT_LOG_DIR}" -name "audit_*.log" -mtime +${AUDIT_LOG_RETENTION_DAYS} -delete 2>/dev/null || true

    log_debug "审计日志已初始化: ${AUDIT_LOG_FILE}"
    return 0
}

# ==============================================================================
# 审计日志记录
# ==============================================================================

# 记录审计事件
audit_log() {
    [[ "${AUDIT_ENABLED}" != "true" ]] && return 0

    local event_type="$1"
    shift
    local details="$*"

    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local timestamp_iso=$(date -Iseconds)
    local user="${USER:-$(whoami 2>/dev/null || echo 'unknown')}"
    local pid=$$
    local hostname=$(hostname)

    # 检查文件大小并轮转
    if [[ -f "${AUDIT_LOG_FILE}" ]]; then
        local file_size_mb
        file_size_mb=$(du -m "${AUDIT_LOG_FILE}" 2>/dev/null | cut -f1 || echo "0")

        if [[ ${file_size_mb} -ge ${AUDIT_LOG_MAX_SIZE_MB} ]]; then
            local archived_log="${AUDIT_LOG_FILE}.old.$(date +%Y%m%d_%H%M%S)"
            mv "${AUDIT_LOG_FILE}" "${archived_log}" 2>/dev/null || true
            touch "${AUDIT_LOG_FILE}" 2>/dev/null
            chmod 600 "${AUDIT_LOG_FILE}" 2>/dev/null || true
            log_debug "审计日志已轮转: ${archived_log}"
        fi
    fi

    # 记录审计日志
    cat >> "${AUDIT_LOG_FILE}" << EOF
[${timestamp}] [${event_type}] [${user}@${hostname}:${pid}] ${details}
EOF

    log_debug "审计日志已记录: ${event_type}"
}

# ==============================================================================
# 审计事件记录函数
# ==============================================================================

# 记录系统启动
audit_system_start() {
    audit_log "${AUDIT_EVENT_SYSTEM_START}" "系统启动 - 版本: ${VERSION} - 用户: ${USER}"
}

# 记录系统停止
audit_system_stop() {
    audit_log "${AUDIT_EVENT_SYSTEM_STOP}" "系统停止 - 用户: ${USER}"
}

# 记录配置变更
audit_config_change() {
    local key="$1"
    local old_value="$2"
    local new_value="$3"

    audit_log "${AUDIT_EVENT_CONFIG_CHANGE}" \
        "配置变更 - 键: ${key} - 旧值: ${old_value} - 新值: ${new_value}"
}

# 记录ZRAM启用
audit_zram_enable() {
    local device="$1"
    local size="$2"
    local algorithm="$3"

    audit_log "${AUDIT_EVENT_ZRAM_ENABLE}" \
        "ZRAM启用 - 设备: ${device} - 大小: ${size}MB - 算法: ${algorithm}"
}

# 记录ZRAM禁用
audit_zram_disable() {
    local device="$1"

    audit_log "${AUDIT_EVENT_ZRAM_DISABLE}" \
        "ZRAM禁用 - 设备: ${device}"
}

# 记录Swap创建
audit_swap_create() {
    local path="$1"
    local size="$2"

    audit_log "${AUDIT_EVENT_SWAP_CREATE}" \
        "Swap创建 - 路径: ${path} - 大小: ${size}MB"
}

# 记录Swap删除
audit_swap_delete() {
    local path="$1"

    audit_log "${AUDIT_EVENT_SWAP_DELETE}" \
        "Swap删除 - 路径: ${path}"
}

# 记录策略变更
audit_strategy_change() {
    local old_strategy="$1"
    local new_strategy="$2"

    audit_log "${AUDIT_EVENT_STRATEGY_CHANGE}" \
        "策略变更 - 旧策略: ${old_strategy} - 新策略: ${new_strategy}"
}

# 记录内核参数变更
audit_kernel_param_change() {
    local param="$1"
    local old_value="$2"
    local new_value="$3"

    audit_log "${AUDIT_EVENT_KERNEL_PARAM_CHANGE}" \
        "内核参数变更 - 参数: ${param} - 旧值: ${old_value} - 新值: ${new_value}"
}

# 记录优化操作
audit_optimize() {
    local strategy="$1"
    local snapshot_file="$2"

    audit_log "${AUDIT_EVENT_OPTIMIZE}" \
        "一键优化 - 策略: ${strategy} - 快照: ${snapshot_file}"
}

# 记录认证事件
audit_auth() {
    local result="$1"
    local method="$2"

    audit_log "${AUDIT_EVENT_AUTH}" \
        "认证事件 - 结果: ${result} - 方法: ${method} - 用户: ${USER}"
}

# 记录权限提升
audit_privilege_escalation() {
    local from_user="$1"
    local to_user="$2"

    audit_log "${AUDIT_EVENT_PRIVILEGE}" \
        "权限提升 - 从: ${from_user} - 到: ${to_user}"
}

# 记录错误事件
audit_error() {
    local context="$1"
    local message="$2"
    local exit_code="${3:-0}"

    audit_log "${AUDIT_EVENT_ERROR}" \
        "错误事件 - 上下文: ${context} - 消息: ${message} - 退出码: ${exit_code}"
}

# ==============================================================================
# 审计日志查询
# ==============================================================================

# 查询审计日志
query_audit_log() {
    local event_type="${1:-}"
    local since="${2:-}"
    local limit="${3:-100}"

    local query_file="${AUDIT_LOG_FILE}"

    # 按事件类型过滤
    if [[ -n "${event_type}" ]]; then
        query_file=$(grep "\[${event_type}\]" "${AUDIT_LOG_FILE}" || echo "")
    fi

    # 按时间过滤
    if [[ -n "${since}" ]]; then
        query_file=$(echo "${query_file}" | awk -v since="${since}" '$1 >= "["since' || echo "")
    fi

    # 限制结果数量
    echo "${query_file}" | tail -n ${limit}
}

# 获取审计统计
get_audit_stats() {
    local total_events=0
    local error_events=0
    local config_changes=0
    local zram_events=0
    local swap_events=0

    if [[ -f "${AUDIT_LOG_FILE}" ]]; then
        total_events=$(wc -l < "${AUDIT_LOG_FILE}" 2>/dev/null || echo "0")
        error_events=$(grep -c "\[${AUDIT_EVENT_ERROR}\]" "${AUDIT_LOG_FILE}" 2>/dev/null || echo "0")
        config_changes=$(grep -c "\[${AUDIT_EVENT_CONFIG_CHANGE}\]" "${AUDIT_LOG_FILE}" 2>/dev/null || echo "0")
        zram_events=$(grep -c "\[${AUDIT_EVENT_ZRAM_ENABLE}\|\[${AUDIT_EVENT_ZRAM_DISABLE}\]" "${AUDIT_LOG_FILE}" 2>/dev/null || echo "0")
        swap_events=$(grep -c "\[${AUDIT_EVENT_SWAP_CREATE}\|\[${AUDIT_EVENT_SWAP_DELETE}\]" "${AUDIT_LOG_FILE}" 2>/dev/null || echo "0")
    fi

    cat <<EOF
{
    "total_events": ${total_events},
    "error_events": ${error_events},
    "config_changes": ${config_changes},
    "zram_events": ${zram_events},
    "swap_events": ${swap_events},
    "audit_log_file": "${AUDIT_LOG_FILE}",
    "retention_days": ${AUDIT_LOG_RETENTION_DAYS},
    "max_size_mb": ${AUDIT_LOG_MAX_SIZE_MB}
}
EOF
}

# 生成审计报告
generate_audit_report() {
    local start_date="${1:-$(date -d '30 days ago' '+%Y-%m-%d')}"
    local end_date="${2:-$(date '+%Y-%m-%d')}"

    cat <<EOF
审计日志报告
================================================================================

报告周期: ${start_date} 至 ${end_date}
审计日志文件: ${AUDIT_LOG_FILE}

事件统计:
$(get_audit_stats)

最近事件:
$(query_audit_log "" "" 20)

================================================================================
EOF
}

# ==============================================================================
# 审计日志管理
# ==============================================================================

# 清理审计日志
cleanup_audit_logs() {
    local days="${1:-${AUDIT_LOG_RETENTION_DAYS}}"

    log_info "清理 ${days} 天前的审计日志..."

    local cleaned=0
    while IFS= read -r -d '' log_file; do
        rm -f "${log_file}" 2>/dev/null && ((cleaned++)) || true
    done < <(find "${AUDIT_LOG_DIR}" -name "audit_*.log" -mtime +${days} -print0 2>/dev/null)

    log_info "已清理 ${cleaned} 个审计日志文件"
    return 0
}

# 导出审计日志
export_audit_log() {
    local output_file="$1"
    local format="${2:-text}"

    if [[ ! -f "${AUDIT_LOG_FILE}" ]]; then
        log_error "审计日志文件不存在: ${AUDIT_LOG_FILE}"
        return 1
    fi

    case "${format}" in
        json)
            # 转换为JSON格式
            local json_output="["
            local first=true

            while IFS= read -r line; do
                if [[ "${first}" == "true" ]]; then
                    first=false
                else
                    json_output+=","
                fi

                # 解析日志行
                local timestamp=$(echo "${line}" | sed 's/\[//g' | cut -d']' -f1)
                local event_type=$(echo "${line}" | sed 's/.*\[\([^]]*\)\].*/\1/' | cut -d']' -f1)
                local details=$(echo "${line}" | sed 's/.*\]\s*//')

                json_output+=$(cat <<EOF
{
    "timestamp": "${timestamp}",
    "event_type": "${event_type}",
    "details": "${details}"
}
EOF
)
            done < "${AUDIT_LOG_FILE}"

            json_output+="]"
            echo "${json_output}" > "${output_file}"
            ;;
        csv)
            # 转换为CSV格式
            echo "timestamp,event_type,details" > "${output_file}"
            sed 's/\[/,/g; s/\]//g' "${AUDIT_LOG_FILE}" >> "${output_file}"
            ;;
        *)
            # 默认文本格式
            cp "${AUDIT_LOG_FILE}" "${output_file}"
            ;;
    esac

    log_info "审计日志已导出: ${output_file} (格式: ${format})"
    return 0
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f init_audit_log
export -f audit_log
export -f audit_system_start
export -f audit_system_stop
export -f audit_config_change
export -f audit_zram_enable
export -f audit_zram_disable
export -f audit_swap_create
export -f audit_swap_delete
export -f audit_strategy_change
export -f audit_kernel_param_change
export -f audit_optimize
export -f audit_auth
export -f audit_privilege_escalation
export -f audit_error
export -f query_audit_log
export -f get_audit_stats
export -f generate_audit_report
export -f cleanup_audit_logs
export -f export_audit_log
