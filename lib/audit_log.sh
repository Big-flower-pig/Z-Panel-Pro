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
declare -g AUDIT_LOG_DIR=""
declare -g AUDIT_LOG_FILE=""
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

# ==============================================================================
# 初始化审计日志
# @return: 0成功，1失败
# ==============================================================================
init_audit_log() {
    # 参数验证
    if [[ "${AUDIT_ENABLED}" != "true" ]]; then
        return 0
    fi

    # 初始化审计日志路径
    if [[ -z "${AUDIT_LOG_DIR}" ]]; then
        # 如果LOG_DIR未定义，使用默认值
        if [[ -z "${LOG_DIR}" ]]; then
            LOG_DIR="/opt/Z-Panel-Pro/logs"
            log_warn "LOG_DIR 未定义，使用默认值: ${LOG_DIR}"
        fi
        AUDIT_LOG_DIR="${LOG_DIR}/audit"
        AUDIT_LOG_FILE="${AUDIT_LOG_DIR}/audit.log"
    fi

    # 验证路径（忽略错误）
    validate_path "${AUDIT_LOG_DIR}" 2>/dev/null || {
        log_warn "审计日志目录路径验证失败: ${AUDIT_LOG_DIR}"
    }

    # 创建审计日志目录（忽略错误）
    mkdir -p "${AUDIT_LOG_DIR}" 2>/dev/null || {
        log_warn "无法创建审计日志目录: ${AUDIT_LOG_DIR}"
        return 0
    }

    chmod 700 "${AUDIT_LOG_DIR}" 2>/dev/null || true

    # 设置文件权限
    if [[ ! -f "${AUDIT_LOG_FILE}" ]]; then
        touch "${AUDIT_LOG_FILE}" 2>/dev/null || true
        chmod 600 "${AUDIT_LOG_FILE}" 2>/dev/null || true
    fi

    # 验证保留天数范围 (1-365)
    if [[ ${AUDIT_LOG_RETENTION_DAYS} -lt 1 ]]; then
        log_warn "审计日志保留天数过小，已自动调整为1天"
        AUDIT_LOG_RETENTION_DAYS=1
    elif [[ ${AUDIT_LOG_RETENTION_DAYS} -gt 365 ]]; then
        log_warn "审计日志保留天数过大，已自动调整为365天"
        AUDIT_LOG_RETENTION_DAYS=365
    fi

    # 清理旧日志
    find "${AUDIT_LOG_DIR}" -name "audit_*.log" -mtime +${AUDIT_LOG_RETENTION_DAYS} -delete 2>/dev/null || true

    log_debug "审计日志已初始化: ${AUDIT_LOG_FILE}"
    return 0
}

# ==============================================================================
# 审计日志记录
# ==============================================================================

# ==============================================================================
# 记录审计事件
# @param event_type: 事件类型 (必需)
# @param details: 事件详情 (可选)
# @return: 0成功
# ==============================================================================
audit_log() {
    # 参数验证
    if [[ ${#} -eq 0 ]]; then
        log_error "audit_log: 缺少必需参数 event_type"
        return 1
    fi

    local event_type="$1"
    shift
    local details="$*"

    # 检查审计日志是否启用
    if [[ "${AUDIT_ENABLED}" != "true" ]]; then
        return 0
    fi

    # 验证事件类型不为空
    if [[ -z "${event_type}" ]]; then
        log_error "audit_log: 事件类型不能为空"
        return 1
    fi

    # 限制详情长度 (最大1000字符)
    if [[ ${#details} -gt 1000 ]]; then
        log_warn "审计详情过长，已截断为1000字符"
        details="${details:0:1000}"
    fi

    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local timestamp_iso=$(date -Iseconds)
    local user="${USER:-$(whoami 2>/dev/null || echo 'unknown')}"
    local pid=$$
    local hostname=$(hostname)

    # 检查文件大小并轮转
    if [[ -f "${AUDIT_LOG_FILE}" ]]; then
        local file_size_mb
        file_size_mb=$(du -m "${AUDIT_LOG_FILE}" 2>/dev/null | cut -f1 || echo "0")

        # 验证最大文件大小 (10-1000MB)
        if [[ ${AUDIT_LOG_MAX_SIZE_MB} -lt 10 ]]; then
            log_warn "审计日志最大文件大小过小，已自动调整为10MB"
            AUDIT_LOG_MAX_SIZE_MB=10
        elif [[ ${AUDIT_LOG_MAX_SIZE_MB} -gt 1000 ]]; then
            log_warn "审计日志最大文件大小过大，已自动调整为1000MB"
            AUDIT_LOG_MAX_SIZE_MB=1000
        fi

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

# ==============================================================================
# 查询审计日志
# @param event_type: 事件类型过滤 (可选)
# @param since: 起始时间 (可选，格式: YYYY-MM-DD)
# @param limit: 返回结果数量限制 (可选，默认100，最大1000)
# @return: 查询结果
# ==============================================================================
query_audit_log() {
    local event_type="${1:-}"
    local since="${2:-}"
    local limit="${3:-100}"

    # 参数验证
    if [[ ${limit} -lt 1 ]]; then
        log_warn "查询限制过小，已自动调整为1"
        limit=1
    elif [[ ${limit} -gt 1000 ]]; then
        log_warn "查询限制过大，已自动调整为1000"
        limit=1000
    fi

    local query_file="${AUDIT_LOG_FILE}"

    # 检查日志文件是否存在
    if [[ ! -f "${AUDIT_LOG_FILE}" ]]; then
        log_warn "审计日志文件不存在: ${AUDIT_LOG_FILE}"
        return 0
    fi

    # 按事件类型过滤
    if [[ -n "${event_type}" ]]; then
        query_file=$(grep "\[${event_type}\]" "${AUDIT_LOG_FILE}" 2>/dev/null || echo "")
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

# ==============================================================================
# 清理审计日志
# @param days: 清理天数 (可选，默认为AUDIT_LOG_RETENTION_DAYS，范围1-365)
# @return: 0成功，1失败
# ==============================================================================
cleanup_audit_logs() {
    local days="${1:-${AUDIT_LOG_RETENTION_DAYS}}"

    # 参数验证
    if [[ ! "${days}" =~ ^[0-9]+$ ]]; then
        log_error "无效的天数参数: ${days}"
        return 1
    fi

    if [[ ${days} -lt 1 ]]; then
        log_warn "清理天数过小，已自动调整为1天"
        days=1
    elif [[ ${days} -gt 365 ]]; then
        log_warn "清理天数过大，已自动调整为365天"
        days=365
    fi

    # 检查目录是否存在
    if [[ ! -d "${AUDIT_LOG_DIR}" ]]; then
        log_warn "审计日志目录不存在: ${AUDIT_LOG_DIR}"
        return 0
    fi

    log_info "清理 ${days} 天前的审计日志..."

    local cleaned=0
    while IFS= read -r -d '' log_file; do
        if rm -f "${log_file}" 2>/dev/null; then
            ((cleaned++)) || true
        fi
    done < <(find "${AUDIT_LOG_DIR}" -name "audit_*.log" -mtime +${days} -print0 2>/dev/null)

    log_info "已清理 ${cleaned} 个审计日志文件"
    return 0
}

# ==============================================================================
# 导出审计日志
# @param output_file: 输出文件路径 (必需)
# @param format: 导出格式 (可选，默认text，支持json/csv/text)
# @return: 0成功，1失败
# ==============================================================================
export_audit_log() {
    # 参数验证
    if [[ ${#} -eq 0 ]]; then
        log_error "export_audit_log: 缺少必需参数 output_file"
        return 1
    fi

    local output_file="$1"
    local format="${2:-text}"

    # 验证输出文件路径
    if ! validate_path "${output_file}"; then
        log_error "无效的输出文件路径: ${output_file}"
        return 1
    fi

    # 验证格式参数
    if [[ "${format}" != "json" ]] && [[ "${format}" != "csv" ]] && [[ "${format}" != "text" ]]; then
        log_warn "不支持的导出格式: ${format}，使用默认格式text"
        format="text"
    fi

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

                # 转义JSON特殊字符
                details=$(echo "${details}" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g')

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

    chmod 640 "${output_file}" 2>/dev/null || true
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
