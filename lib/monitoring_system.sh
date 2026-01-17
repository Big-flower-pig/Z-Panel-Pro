#!/bin/bash
# ==============================================================================
# Z-Panel Pro V8.0 - 监控系统增强
# ==============================================================================
# @description    企业级监控系统，支持Prometheus导出、告警规则、仪表板
# @version       8.0.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 监控系统配置
# ==============================================================================
declare -gA MONITORING_CONFIG=(
    [metrics_port]="9090"
    [metrics_path]="/metrics"
    [scrape_interval]="15"
    [alerting_enabled]="true"
    [alert_rules_file]="/opt/Z-Panel-Pro/config/alert_rules.yml"
    [metrics_dir]="/opt/Z-Panel-Pro/data/metrics"
    [retention_days]="7"
    [export_format]="prometheus"
    [dashboard_dir]="/opt/Z-Panel-Pro/web/dashboards"
)

# ==============================================================================
# 指标定义
# ==============================================================================
declare -gA MONITORING_METRICS=()
declare -gA MONITORING_METRICS_LABELS=()
declare -gA MONITORING_METRICS_HELP=()

# ==============================================================================
# 告警规则
# ==============================================================================
declare -gA ALERT_RULES=()
declare -gA ALERT_STATES=()

# ==============================================================================
# 监控系统状态
# ==============================================================================
declare -g MONITORING_RUNNING=false
declare -g MONITORING_PID=""

# ==============================================================================
# 指标类型
# ==============================================================================
declare -gA METRIC_TYPES=(
    [counter]="计数器（只增不减）"
    [gauge]="仪表盘（可增可减）"
    [histogram]="直方图（分布统计）"
    [summary]="摘要（分位数统计）"
)

# ==============================================================================
# 初始化监控系统
# ==============================================================================
init_monitoring_system() {
    log_info "初始化监控系统..."

    # 创建目录
    mkdir -p "${MONITORING_CONFIG[metrics_dir]}"
    mkdir -p "${MONITORING_CONFIG[dashboard_dir]}"

    # 加载告警规则
    load_alert_rules

    # 注册默认指标
    register_default_metrics

    log_info "监控系统初始化完成"
    return 0
}

# ==============================================================================
# 指标注册
# ==============================================================================
# 注册指标
register_metric() {
    local metric_name="$1"
    local metric_type="$2"
    local help_text="${3:-}"

    if [[ -z "${metric_name}" ]] || [[ -z "${metric_type}" ]]; then
        log_error "缺少必需参数: metric_name, metric_type"
        return 1
    fi

    # 检查指标类型是否有效
    if [[ -z "${METRIC_TYPES[${metric_type}]+isset}" ]]; then
        log_error "无效的指标类型: ${metric_type}"
        return 1
    fi

    # 检查指标是否已存在
    if [[ -n "${MONITORING_METRICS[${metric_name}_type]+isset}" ]]; then
        log_error "指标已存在: ${metric_name}"
        return 1
    fi

    # 注册指标
    MONITORING_METRICS["${metric_name}_type"]="${metric_type}"
    MONITORING_METRICS["${metric_name}_value"]="0"
    MONITORING_METRICS["${metric_name}_created"]=$(date +%s)
    MONITORING_METRICS["${metric_name}_updated"]=$(date +%s)

    MONITORING_METRICS_HELP["${metric_name}"]="${help_text}"

    log_debug "指标已注册: ${metric_name} (${metric_type})"
    return 0
}

# 设置指标值
set_metric() {
    local metric_name="$1"
    local value="$2"
    local labels="${3:-}"

    if [[ -z "${MONITORING_METRICS[${metric_name}_type]+isset}" ]]; then
        log_error "指标不存在: ${metric_name}"
        return 1
    fi

    local metric_type="${MONITORING_METRICS[${metric_name}_type]}"

    case "${metric_type}" in
        counter)
            # 计数器只增不减
            local current="${MONITORING_METRICS[${metric_name}_value]}"
            MONITORING_METRICS["${metric_name}_value"]="$((current + value))"
            ;;
        gauge)
            # 仪表盘可增可减
            MONITORING_METRICS["${metric_name}_value"]="${value}"
            ;;
        histogram)
            # 直方图需要特殊处理
            update_histogram "${metric_name}" "${value}" "${labels}"
            ;;
        summary)
            # 摘要需要特殊处理
            update_summary "${metric_name}" "${value}" "${labels}"
            ;;
    esac

    # 更新时间戳
    MONITORING_METRICS["${metric_name}_updated"]=$(date +%s)

    # 更新标签
    if [[ -n "${labels}" ]]; then
        MONITORING_METRICS_LABELS["${metric_name}"]="${labels}"
    fi
}

# 增加指标值
increment_metric() {
    local metric_name="$1"
    local value="${2:-1}"
    local labels="${3:-}"

    if [[ -z "${MONITORING_METRICS[${metric_name}_type]+isset}" ]]; then
        log_error "指标不存在: ${metric_name}"
        return 1
    fi

    local metric_type="${MONITORING_METRICS[${metric_name}_type]}"

    if [[ "${metric_type}" != "counter" ]] && [[ "${metric_type}" != "gauge" ]]; then
        log_error "指标类型不支持递增: ${metric_type}"
        return 1
    fi

    local current="${MONITORING_METRICS[${metric_name}_value]}"
    MONITORING_METRICS["${metric_name}_value"]="$((current + value))"
    MONITORING_METRICS["${metric_name}_updated"]=$(date +%s)

    if [[ -n "${labels}" ]]; then
        MONITORING_METRICS_LABELS["${metric_name}"]="${labels}"
    fi
}

# 获取指标值
get_metric() {
    local metric_name="$1"

    if [[ -z "${MONITORING_METRICS[${metric_name}_type]+isset}" ]]; then
        log_error "指标不存在: ${metric_name}"
        return 1
    fi

    echo "${MONITORING_METRICS[${metric_name}_value]}"
}

# 更新直方图
update_histogram() {
    local metric_name="$1"
    local value="$2"
    local labels="${3:-}"

    # 直方图需要记录分布
    local histogram_file="${MONITORING_CONFIG[metrics_dir]}/${metric_name}.hist"

    echo "${value}" >> "${histogram_file}"

    # 计算分位数
    local -A buckets
    buckets[0.05]=0
    buckets[0.25]=0
    buckets[0.50]=0
    buckets[0.75]=0
    buckets[0.90]=0
    buckets[0.95]=0
    buckets[0.99]=0

    while IFS= read -r v; do
        for bucket in "${!buckets[@]}"; do
            if (( $(echo "${v} <= ${bucket}" | bc -l) )); then
                ((buckets[${bucket}]++))
            fi
        done
    done < "${histogram_file}"

    # 更新指标值（使用总和）
    local sum=$(awk '{s+=$1} END {print s}' "${histogram_file}")
    MONITORING_METRICS["${metric_name}_value"]="${sum}"
    MONITORING_METRICS["${metric_name}_count"]=$(wc -l < "${histogram_file}")

    # 存储分位数
    for bucket in "${!buckets[@]}"; do
        MONITORING_METRICS["${metric_name}_bucket_${bucket}"]="${buckets[${bucket}]}"
    done
}

# 更新摘要
update_summary() {
    local metric_name="$1"
    local value="$2"
    local labels="${3:-}"

    # 摘要记录最近N个值
    local summary_file="${MONITORING_CONFIG[metrics_dir]}/${metric_name}.sum"
    local max_samples=1000

    # 添加新值
    echo "${value}" >> "${summary_file}"

    # 限制样本数量
    local line_count=$(wc -l < "${summary_file}")
    if [[ ${line_count} -gt ${max_samples} ]]; then
        tail -n ${max_samples} "${summary_file}" > "${summary_file}.tmp"
        mv "${summary_file}.tmp" "${summary_file}"
    fi

    # 计算分位数
    local sorted_values=$(sort -n "${summary_file}")
    local total=$(echo "${sorted_values}" | wc -l)

    local p50=$(echo "${sorted_values}" | awk "NR==int(${total}*0.5)")
    local p90=$(echo "${sorted_values}" | awk "NR==int(${total}*0.9)")
    local p95=$(echo "${sorted_values}" | awk "NR==int(${total}*0.95)")
    local p99=$(echo "${sorted_values}" | awk "NR==int(${total}*0.99)")

    MONITORING_METRICS["${metric_name}_value"]="${p50}"
    MONITORING_METRICS["${metric_name}_p50"]="${p50}"
    MONITORING_METRICS["${metric_name}_p90"]="${p90}"
    MONITORING_METRICS["${metric_name}_p95"]="${p95}"
    MONITORING_METRICS["${metric_name}_p99"]="${p99}"
    MONITORING_METRICS["${metric_name}_count"]="${total}"
}

# ==============================================================================
# Prometheus导出
# ==============================================================================
# 导出Prometheus格式
export_metrics_prometheus() {
    local output=""

    # 导出所有指标
    for key in "${!MONITORING_METRICS[@]}"; do
        if [[ "${key}" == *"_type" ]]; then
            local metric_name="${key%_type}"
            local metric_type="${MONITORING_METRICS[${key}]}"
            local help_text="${MONITORING_METRICS_HELP[${metric_name}]:-}"
            local labels="${MONITORING_METRICS_LABELS[${metric_name}]:-}"

            # 添加HELP注释
            if [[ -n "${help_text}" ]]; then
                output+="# HELP ${metric_name} ${help_text}"$'\n'
            fi

            # 添加TYPE注释
            output+="# TYPE ${metric_name} ${metric_type}"$'\n'

            # 添加指标值
            if [[ "${metric_type}" == "counter" ]] || [[ "${metric_type}" == "gauge" ]]; then
                local value="${MONITORING_METRICS[${metric_name}_value]}"
                local timestamp="${MONITORING_METRICS[${metric_name}_updated]}"

                if [[ -n "${labels}" ]]; then
                    output+="${metric_name}{${labels}} ${value} ${timestamp}"$'\n'
                else
                    output+="${metric_name} ${value} ${timestamp}"$'\n'
                fi
            elif [[ "${metric_type}" == "histogram" ]]; then
                # 导出直方图
                local sum="${MONITORING_METRICS[${metric_name}_value]}"
                local count="${MONITORING_METRICS[${metric_name}_count]:-0}"

                output+="${metric_name}_sum ${sum} ${timestamp}"$'\n'
                output+="${metric_name}_count ${count} ${timestamp}"$'\n'

                # 导出分位数桶
                for bucket in "0.05" "0.25" "0.50" "0.75" "0.90" "0.95" "0.99" "1.00"; do
                    local bucket_value="${MONITORING_METRICS[${metric_name}_bucket_${bucket}]:-0}"
                    output+="${metric_name}_bucket{le=\"${bucket}\"} ${bucket_value} ${timestamp}"$'\n'
                done
            elif [[ "${metric_type}" == "summary" ]]; then
                # 导出摘要
                local p50="${MONITORING_METRICS[${metric_name}_p50]:-0}"
                local p90="${MONITORING_METRICS[${metric_name}_p90]:-0}"
                local p95="${MONITORING_METRICS[${metric_name}_p95]:-0}"
                local p99="${MONITORING_METRICS[${metric_name}_p99]:-0}"
                local count="${MONITORING_METRICS[${metric_name}_count]:-0}"

                output+="${metric_name}{quantile=\"0.5\"} ${p50} ${timestamp}"$'\n'
                output+="${metric_name}{quantile=\"0.9\"} ${p90} ${timestamp}"$'\n'
                output+="${metric_name}{quantile=\"0.95\"} ${p95} ${timestamp}"$'\n'
                output+="${metric_name}{quantile=\"0.99\"} ${p99} ${timestamp}"$'\n'
                output+="${metric_name}_sum ${p50} ${timestamp}"$'\n'
                output+="${metric_name}_count ${count} ${timestamp}"$'\n'
            fi
        fi
    done

    echo "${output}"
}

# ==============================================================================
# 告警规则
# ==============================================================================
# 添加告警规则
add_alert_rule() {
    local rule_name="$1"
    local expression="$2"
    local duration="${3:-60}"
    local severity="${4:-warning}"
    local description="${5:-}"

    if [[ -z "${rule_name}" ]] || [[ -z "${expression}" ]]; then
        log_error "缺少必需参数: rule_name, expression"
        return 1
    fi

    ALERT_RULES["${rule_name}_expression"]="${expression}"
    ALERT_RULES["${rule_name}_duration"]="${duration}"
    ALERT_RULES["${rule_name}_severity"]="${severity}"
    ALERT_RULES["${rule_name}_description"]="${description}"
    ALERT_RULES["${rule_name}_enabled"]="true"

    ALERT_STATES["${rule_name}_state"]="inactive"
    ALERT_STATES["${rule_name}_last_triggered"]=0

    log_debug "告警规则已添加: ${rule_name}"
}

# 评估告警规则
evaluate_alert_rules() {
    for rule_name in "${!ALERT_RULES[@]}"; do
        if [[ "${rule_name}" == *"_enabled" ]] && [[ "${ALERT_RULES[${rule_name}]}" == "true" ]]; then
            local name="${rule_name%_enabled}"
            evaluate_alert "${name}"
        fi
    done
}

# 评估告警
evaluate_alert() {
    local rule_name="$1"

    local expression="${ALERT_RULES[${rule_name}_expression]}"
    local duration="${ALERT_RULES[${rule_name}_duration]}"
    local severity="${ALERT_RULES[${rule_name}_severity]}"
    local current_state="${ALERT_STATES[${rule_name}_state]}"
    local last_triggered="${ALERT_STATES[${rule_name}_last_triggered]}"

    # 解析并评估表达式
    # 简化实现：支持 metric_name operator value 格式
    local metric_name=$(echo "${expression}" | awk '{print $1}')
    local operator=$(echo "${expression}" | awk '{print $2}')
    local threshold=$(echo "${expression}" | awk '{print $3}')

    local metric_value=$(get_metric "${metric_name}" 2>/dev/null || echo "0")

    local triggered=false
    case "${operator}" in
        ">")  [[ ${metric_value} -gt ${threshold} ]] && triggered=true ;;
        ">=") [[ ${metric_value} -ge ${threshold} ]] && triggered=true ;;
        "<")  [[ ${metric_value} -lt ${threshold} ]] && triggered=true ;;
        "<=") [[ ${metric_value} -le ${threshold} ]] && triggered=true ;;
        "==") [[ ${metric_value} -eq ${threshold} ]] && triggered=true ;;
        "!=") [[ ${metric_value} -ne ${threshold} ]] && triggered=true ;;
    esac

    local current_time=$(date +%s)

    if [[ "${triggered}" == "true" ]]; then
        if [[ "${current_state}" == "inactive" ]]; then
            # 首次触发
            ALERT_STATES["${rule_name}_state"]="pending"
            ALERT_STATES["${rule_name}_last_triggered"]="${current_time}"
        elif [[ "${current_state}" == "pending" ]]; then
            # 检查持续时间
            if [[ $((current_time - last_triggered)) -ge ${duration} ]]; then
                # 告警触发
                ALERT_STATES["${rule_name}_state"]="firing"
                trigger_alert "${rule_name}" "${severity}"
            fi
        fi
    else
        # 条件不满足，重置状态
        ALERT_STATES["${rule_name}_state"]="inactive"
    fi
}

# 触发告警
trigger_alert() {
    local rule_name="$1"
    local severity="$2"

    local description="${ALERT_RULES[${rule_name}_description]:-}"

    log_warning "告警触发: ${rule_name} (${severity})"

    # 发送告警事件
    local alert_data=$(cat <<EOF
{
    "rule_name": "${rule_name}",
    "severity": "${severity}",
    "description": "${description}",
    "timestamp": $(date +%s)
}
EOF
)

    publish_event "security" "${alert_data}" "monitoring" "type=alert,severity=${severity}"
}

# 加载告警规则
load_alert_rules() {
    local rules_file="${MONITORING_CONFIG[alert_rules_file]}"

    if [[ ! -f "${rules_file}" ]]; then
        return 0
    fi

    # 解析YAML文件（简化实现）
    while IFS=':' read -r key value; do
        case "${key}" in
            *"_expression")
                local rule_name="${key%_expression}"
                ALERT_RULES["${rule_name}_expression"]="${value}"
                ;;
            *"_duration")
                local rule_name="${key%_duration}"
                ALERT_RULES["${rule_name}_duration"]="${value}"
                ;;
            *"_severity")
                local rule_name="${key%_severity}"
                ALERT_RULES["${rule_name}_severity"]="${value}"
                ;;
            *"_description")
                local rule_name="${key%_description}"
                ALERT_RULES["${rule_name}_description"]="${value}"
                ;;
        esac
    done < "${rules_file}"

    log_debug "告警规则已加载"
}

# ==============================================================================
# 监控服务器
# ==============================================================================
# 启动监控服务器
start_monitoring_server() {
    log_info "启动监控服务器..."

    local port="${MONITORING_CONFIG[metrics_port]}"
    local path="${MONITORING_CONFIG[metrics_path]}"

    # 使用socat启动HTTP服务器
    if command -v socat &> /dev/null; then
        socat TCP-LISTEN:${port},fork,reuseaddr EXEC:"/opt/Z-Panel-Pro/lib/monitoring_system.sh handle_metrics_request" &
        MONITORING_PID=$!
    else
        log_error "需要socat来启动监控服务器"
        return 1
    fi

    MONITORING_RUNNING=true

    # 启动告警评估
    if [[ "${MONITORING_CONFIG[alerting_enabled]}" == "true" ]]; then
        start_alert_evaluation &
    fi

    log_info "监控服务器已启动 (PID: ${MONITORING_PID})"
    return 0
}

# 停止监控服务器
stop_monitoring_server() {
    log_info "停止监控服务器..."

    if [[ -n "${MONITORING_PID}" ]] && kill -0 ${MONITORING_PID} 2>/dev/null; then
        kill ${MONITORING_PID}
        wait ${MONITORING_PID} 2>/dev/null
    fi

    MONITORING_RUNNING=false
    MONITORING_PID=""

    log_info "监控服务器已停止"
    return 0
}

# 处理指标请求
handle_metrics_request() {
    local request=$(cat)
    local method=$(echo "${request}" | head -n 1 | cut -d' ' -f1)
    local path=$(echo "${request}" | head -n 1 | cut -d' ' -f2)
    local metrics_path="${MONITORING_CONFIG[metrics_path]}"

    if [[ "${method}" == "GET" ]] && [[ "${path}" == "${metrics_path}" ]]; then
        local metrics=$(export_metrics_prometheus)
        local response="HTTP/1.1 200 OK"$'\n'
        response+="Content-Type: text/plain; version=0.0.4"$'\n'
        response+="Content-Length: ${#metrics}"$'\n'
        response+=$'\n'
        response+="${metrics}"
        echo "${response}"
    else
        local response="HTTP/1.1 404 Not Found"$'\n'
        response+="Content-Length: 0"$'\n'
        response+=$'\n'
        echo "${response}"
    fi
}

# 启动告警评估
start_alert_evaluation() {
    local interval="${MONITORING_CONFIG[scrape_interval]}"

    while [[ "${MONITORING_RUNNING}" == "true" ]]; do
        sleep ${interval}
        evaluate_alert_rules
    done
}

# ==============================================================================
# 默认指标
# ==============================================================================
# 注册默认指标
register_default_metrics() {
    # 系统指标
    register_metric "zpanel_memory_total" "gauge" "系统总内存（MB）"
    register_metric "zpanel_memory_used" "gauge" "系统已用内存（MB）"
    register_metric "zpanel_memory_percent" "gauge" "系统内存使用率（%）"
    register_metric "zpanel_zram_total" "gauge" "ZRAM总大小（MB）"
    register_metric "zpanel_zram_used" "gauge" "ZRAM已用大小（MB）"
    register_metric "zpanel_zram_percent" "gauge" "ZRAM使用率（%）"
    register_metric "zpanel_swap_total" "gauge" "Swap总大小（MB）"
    register_metric "zpanel_swap_used" "gauge" "Swap已用大小（MB）"
    register_metric "zpanel_swap_percent" "gauge" "Swap使用率（%）"

    # 决策引擎指标
    register_metric "zpanel_de_decisions_total" "counter" "决策引擎总决策次数"
    register_metric "zpanel_de_decisions_success" "counter" "决策引擎成功决策次数"
    register_metric "zpanel_de_decisions_failed" "counter" "决策引擎失败决策次数"
    register_metric "zpanel_de_decision_duration" "summary" "决策引擎决策耗时"

    # 工作流指标
    register_metric "zpanel_workflow_runs_total" "counter" "工作流总执行次数"
    register_metric "zpanel_workflow_runs_success" "counter" "工作流成功执行次数"
    register_metric "zpanel_workflow_runs_failed" "counter" "工作流失败执行次数"
    register_metric "zpanel_workflow_duration" "summary" "工作流执行耗时"

    # API指标
    register_metric "zpanel_api_requests_total" "counter" "API总请求次数"
    register_metric "zpanel_api_requests_success" "counter" "API成功请求次数"
    register_metric "zpanel_api_requests_failed" "counter" "API失败请求次数"
    register_metric "zpanel_api_request_duration" "summary" "API请求耗时"

    # 缓存指标
    register_metric "zpanel_cache_hits" "counter" "缓存命中次数"
    register_metric "zpanel_cache_misses" "counter" "缓存未命中次数"
    register_metric "zpanel_cache_size" "gauge" "缓存大小（字节）"

    # 默认告警规则
    add_alert_rule "high_memory_usage" "zpanel_memory_percent > 90" "300" "critical" "内存使用率超过90%"
    add_alert_rule "high_zram_usage" "zpanel_zram_percent > 80" "300" "warning" "ZRAM使用率超过80%"
    add_alert_rule "swap_in_use" "zpanel_swap_used > 0" "60" "warning" "Swap正在使用"

    log_debug "默认指标已注册"
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f init_monitoring_system
export -f register_metric
export -f set_metric
export -f increment_metric
export -f get_metric
export -f update_histogram
export -f update_summary
export -f export_metrics_prometheus
export -f add_alert_rule
export -f evaluate_alert_rules
export -f evaluate_alert
export -f trigger_alert
export -f load_alert_rules
export -f start_monitoring_server
export -f stop_monitoring_server
export -f handle_metrics_request
export -f start_alert_evaluation
export -f register_default_metrics
