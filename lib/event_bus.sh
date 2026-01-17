#!/bin/bash
# ==============================================================================
# Z-Panel Pro V8.0 - 事件总线
# ==============================================================================
# @description    企业级事件驱动系统，支持发布订阅、事件路由、异步处理
# @version       8.0.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 事件总线配置
# ==============================================================================
declare -gA EVENT_BUS_CONFIG=(
    [async_enabled]="true"
    [max_queue_size]="1000"
    [worker_threads]="4"
    [event_timeout]="30"
    [persistence_enabled]="true"
    [persistence_dir]="/opt/Z-Panel-Pro/data/events"
    [log_events]="true"
    [log_dir]="/opt/Z-Panel-Pro/logs/events"
)

# ==============================================================================
# 事件定义
# ==============================================================================
declare -gA EVENT_TYPES=(
    [system]="系统事件"
    [memory]="内存事件"
    [zram]="ZRAM事件"
    [swap]="Swap事件"
    [decision]="决策事件"
    [workflow]="工作流事件"
    [policy]="策略事件"
    [config]="配置事件"
    [security]="安全事件"
    [custom]="自定义事件"
)

# ==============================================================================
# 事件总线状态
# ==============================================================================
declare -g EVENT_BUS_RUNNING=false
declare -gA EVENT_SUBSCRIBERS=()
declare -gA EVENT_QUEUE=()
declare -gA EVENT_HISTORY=()
declare -gA EVENT_WORKERS=()

# ==============================================================================
# 事件结构
# ==============================================================================
# 事件格式: id,type,source,timestamp,data,metadata

# ==============================================================================
# 初始化事件总线
# ==============================================================================
init_event_bus() {
    log_info "初始化事件总线..."

    # 创建目录
    mkdir -p "${EVENT_BUS_CONFIG[persistence_dir]}"
    mkdir -p "${EVENT_BUS_CONFIG[log_dir]}"

    # 加载持久化的事件
    load_persisted_events

    log_info "事件总线初始化完成"
    return 0
}

# ==============================================================================
# 事件发布
# ==============================================================================
# 发布事件
publish_event() {
    local event_type="$1"
    local event_data="$2"
    local source="${3:-zpanel}"
    local metadata="${4:-}"

    # 生成事件ID
    local event_id=$(generate_event_id)

    # 创建事件
    local timestamp=$(date +%s)
    local event="${event_id}|${event_type}|${source}|${timestamp}|${event_data}|${metadata}"

    # 添加到队列
    add_event_to_queue "${event}"

    # 记录历史
    EVENT_HISTORY["${event_id}"]="${event}"

    # 记录日志
    if [[ "${EVENT_BUS_CONFIG[log_events]}" == "true" ]]; then
        log_event "${event}"
    fi

    # 立即触发订阅者（如果异步未启用）
    if [[ "${EVENT_BUS_CONFIG[async_enabled]}" != "true" ]]; then
        trigger_subscribers "${event_type}" "${event}"
    fi

    log_debug "事件已发布: ${event_id} (${event_type})"

    # 持久化
    if [[ "${EVENT_BUS_CONFIG[persistence_enabled]}" == "true" ]]; then
        persist_event "${event}"
    fi

    echo "${event_id}"
    return 0
}

# 生成事件ID
generate_event_id() {
    local timestamp=$(date +%s%N)
    local random=$(head -c 8 /dev/urandom | xxd -p)
    echo "evt_${timestamp}_${random}"
}

# 添加事件到队列
add_event_to_queue() {
    local event="$1"

    # 检查队列大小
    local queue_size="${#EVENT_QUEUE[@]}"
    local max_size="${EVENT_BUS_CONFIG[max_queue_size]}"

    if [[ ${queue_size} -ge ${max_size} ]]; then
        log_warning "事件队列已满，丢弃最旧的事件"
        EVENT_QUEUE=("${EVENT_QUEUE[@]:1}")
    fi

    EVENT_QUEUE+=("${event}")
}

# ==============================================================================
# 事件订阅
# ==============================================================================
# 安全的处理器名称验证
is_safe_event_handler() {
    local handler="$1"

    # 检查处理器名称格式：只允许字母、数字、下划线
    if [[ ! "${handler}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        return 1
    fi

    # 检查是否为已知的危险函数
    local dangerous_handlers=(
        "eval" "exec" "source" "system" "bash" "sh" "cmd"
        "rm" "dd" "mkfs" "fdisk" "format"
        "chmod" "chown" "chgrp" "setuid" "setgid"
    )

    for dangerous in "${dangerous_handlers[@]}"; do
        if [[ "${handler}" == "${dangerous}" ]]; then
            return 1
        fi
    done

    return 0
}

# 订阅事件（安全版本）
subscribe_event() {
    local event_type="$1"
    local handler="$2"
    local filter="${3:-}"

    if [[ -z "${event_type}" ]] || [[ -z "${handler}" ]]; then
        log_error "缺少必需参数: event_type, handler"
        return 1
    fi

    # 检查事件类型是否有效
    if [[ -z "${EVENT_TYPES[${event_type}]+isset}" ]] && [[ "${event_type}" != "*" ]]; then
        log_error "无效的事件类型: ${event_type}"
        return 1
    fi

    # 验证处理器名称是否安全
    if ! is_safe_event_handler "${handler}"; then
        log_error "拒绝注册不安全的处理器: ${handler}"
        return 1
    fi

    # 添加订阅者
    local subscriber_id="${event_type}:${handler}"
    EVENT_SUBSCRIBERS["${subscriber_id}_handler"]="${handler}"
    EVENT_SUBSCRIBERS["${subscriber_id}_filter"]="${filter}"
    EVENT_SUBSCRIBERS["${subscriber_id}_enabled"]="true"
    EVENT_SUBSCRIBERS["${subscriber_id}_created"]=$(date +%s)

    log_debug "订阅事件: ${event_type} -> ${handler}"

    return 0
}

# 取消订阅
unsubscribe_event() {
    local event_type="$1"
    local handler="$2"

    local subscriber_id="${event_type}:${handler}"

    # 删除订阅者
    for key in "${!EVENT_SUBSCRIBERS[@]}"; do
        if [[ "${key}" == "${subscriber_id}"* ]]; then
            unset EVENT_SUBSCRIBERS["${key}"]
        fi
    done

    log_debug "取消订阅: ${subscriber_id}"
    return 0
}

# 触发订阅者（安全版本）
trigger_subscribers() {
    local event_type="$1"
    local event="$2"

    # 解析事件
    local event_id=$(echo "${event}" | cut -d'|' -f1)
    local source=$(echo "${event}" | cut -d'|' -f3)
    local timestamp=$(echo "${event}" | cut -d'|' -f4)
    local data=$(echo "${event}" | cut -d'|' -f5)
    local metadata=$(echo "${event}" | cut -d'|' -f6)

    # 查找订阅者
    for key in "${!EVENT_SUBSCRIBERS[@]}"; do
        if [[ "${key}" == *"_handler" ]]; then
            local subscriber="${key%_handler}"
            local subscribed_type="${subscriber%%:*}"
            local handler="${EVENT_SUBSCRIBERS[${key}]}"
            local filter="${EVENT_SUBSCRIBERS[${subscriber}_filter]}"
            local enabled="${EVENT_SUBSCRIBERS[${subscriber}_enabled]}"

            # 检查是否启用
            if [[ "${enabled}" != "true" ]]; then
                continue
            fi

            # 检查事件类型匹配
            if [[ "${subscribed_type}" != "*" ]] && [[ "${subscribed_type}" != "${event_type}" ]]; then
                continue
            fi

            # 检查过滤器
            if [[ -n "${filter}" ]] && ! event_matches_filter "${event}" "${filter}"; then
                continue
            fi

            # 二次验证处理器安全性
            if ! is_safe_event_handler "${handler}"; then
                log_error "拒绝执行不安全的处理器: ${handler}"
                continue
            fi

            # 检查处理器是否存在
            if ! declare -F "${handler}" >/dev/null 2>&1; then
                log_error "处理器不存在: ${handler}"
                continue
            fi

            # 触发处理器（安全执行）
            if [[ "${EVENT_BUS_CONFIG[async_enabled]}" == "true" ]]; then
                # 异步处理 - 使用子进程隔离
                (
                    # 设置超时
                    local timeout="${EVENT_BUS_CONFIG[event_timeout]}"
                    timeout ${timeout} "${handler}" "${event_id}" "${event_type}" "${source}" "${timestamp}" "${data}" "${metadata}" 2>/dev/null
                ) &
            else
                # 同步处理
                local timeout="${EVENT_BUS_CONFIG[event_timeout]}"
                timeout ${timeout} "${handler}" "${event_id}" "${event_type}" "${source}" "${timestamp}" "${data}" "${metadata}" 2>/dev/null
            fi
        fi
    done
}

# 检查事件是否匹配过滤器
event_matches_filter() {
    local event="$1"
    local filter="$2"

    # 简单的JSON过滤器
    # 格式: key1=value1,key2=value2
    local data=$(echo "${event}" | cut -d'|' -f5)

    IFS=',' read -ra conditions <<< "${filter}"

    for condition in "${conditions[@]}"; do
        local key="${condition%%=*}"
        local expected="${condition#*=}"

        local actual=$(echo "${data}" | jq -r ".${key}" 2>/dev/null)

        if [[ "${actual}" != "${expected}" ]]; then
            return 1
        fi
    done

    return 0
}

# ==============================================================================
# 事件处理
# ==============================================================================
# 启动事件总线
start_event_bus() {
    log_info "启动事件总线..."

    EVENT_BUS_RUNNING=true

    # 启动工作线程
    if [[ "${EVENT_BUS_CONFIG[async_enabled]}" == "true" ]]; then
        local worker_threads="${EVENT_BUS_CONFIG[worker_threads]}"

        for ((i=0; i<worker_threads; i++)); do
            start_event_worker "${i}" &
            EVENT_WORKERS["${i}"]=$!
        done

        log_info "事件总线已启动 (${worker_threads} 工作线程)"
    else
        log_info "事件总线已启动（同步模式）"
    fi

    return 0
}

# 停止事件总线
stop_event_bus() {
    log_info "停止事件总线..."

    EVENT_BUS_RUNNING=false

    # 停止工作线程
    for worker_pid in "${EVENT_WORKERS[@]}"; do
        if [[ -n "${worker_pid}" ]] && kill -0 ${worker_pid} 2>/dev/null; then
            kill ${worker_pid}
            wait ${worker_pid} 2>/dev/null
        fi
    done

    EVENT_WORKERS=()

    log_info "事件总线已停止"
    return 0
}

# 启动事件工作线程
start_event_worker() {
    local worker_id="$1"

    while [[ "${EVENT_BUS_RUNNING}" == "true" ]]; do
        # 从队列获取事件
        if [[ ${#EVENT_QUEUE[@]} -gt 0 ]]; then
            local event="${EVENT_QUEUE[0]}"
            EVENT_QUEUE=("${EVENT_QUEUE[@]:1}")

            # 处理事件
            local event_type=$(echo "${event}" | cut -d'|' -f2)
            trigger_subscribers "${event_type}" "${event}"
        else
            # 队列为空，等待
            sleep 0.1
        fi
    done
}

# ==============================================================================
# 事件持久化
# ==============================================================================
# 持久化事件
persist_event() {
    local event="$1"
    local event_id=$(echo "${event}" | cut -d'|' -f1)

    local event_file="${EVENT_BUS_CONFIG[persistence_dir]}/${event_id}.evt"

    echo "${event}" > "${event_file}"
}

# 加载持久化的事件
load_persisted_events() {
    local persistence_dir="${EVENT_BUS_CONFIG[persistence_dir]}"

    if [[ ! -d "${persistence_dir}" ]]; then
        return 0
    fi

    for event_file in "${persistence_dir}"/*.evt; do
        if [[ -f "${event_file}" ]]; then
            local event=$(cat "${event_file}")
            local event_id=$(echo "${event}" | cut -d'|' -f1)

            EVENT_HISTORY["${event_id}"]="${event}"
        fi
    done

    log_debug "加载持久化事件完成"
}

# 清理旧事件
cleanup_old_events() {
    local max_age="${EVENT_BUS_CONFIG[event_timeout]}"
    local cutoff_time=$(($(date +%s) - max_age))

    local persistence_dir="${EVENT_BUS_CONFIG[persistence_dir]}"

    for event_file in "${persistence_dir}"/*.evt; do
        if [[ -f "${event_file}" ]]; then
            local event=$(cat "${event_file}")
            local timestamp=$(echo "${event}" | cut -d'|' -f4)
            local event_id=$(echo "${event}" | cut -d'|' -f1)

            if [[ ${timestamp} -lt ${cutoff_time} ]]; then
                rm -f "${event_file}"
                unset EVENT_HISTORY["${event_id}"]
            fi
        fi
    done
}

# ==============================================================================
# 事件日志
# ==============================================================================
# 记录事件日志
log_event() {
    local event="$1"
    local event_id=$(echo "${event}" | cut -d'|' -f1)
    local event_type=$(echo "${event}" | cut -d'|' -f2)

    local log_file="${EVENT_BUS_CONFIG[log_dir]}/events_$(date +%Y%m%d).log"

    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    cat >> "${log_file}" <<EOF
[${timestamp}] ${event_id} ${event_type} ${event}
EOF
}

# ==============================================================================
# 事件查询
# ==============================================================================
# 获取事件历史
get_event_history() {
    local event_type="${1:-}"
    local limit="${2:-100}"

    local results=()

    for event_id in "${!EVENT_HISTORY[@]}"; do
        local event="${EVENT_HISTORY[${event_id}]}"
        local current_type=$(echo "${event}" | cut -d'|' -f2)

        if [[ -z "${event_type}" ]] || [[ "${current_type}" == "${event_type}" ]] || [[ "${event_type}" == "*" ]]; then
            results+=("${event}")
        fi
    done

    # 按时间戳排序
    IFS=$'\n' sorted_results=($(sort -t'|' -k4 -rn <<< "${results[*]}"))

    # 限制结果数量
    echo "${sorted_results[@]:0:${limit}}"
}

# 获取事件详情
get_event_details() {
    local event_id="$1"

    if [[ -n "${EVENT_HISTORY[${event_id}]+isset}" ]]; then
        local event="${EVENT_HISTORY[${event_id}]"
        local event_type=$(echo "${event}" | cut -d'|' -f2)
        local source=$(echo "${event}" | cut -d'|' -f3)
        local timestamp=$(echo "${event}" | cut -d'|' -f4)
        local data=$(echo "${event}" | cut -d'|' -f5)
        local metadata=$(echo "${event}" | cut -d'|' -f6)

        cat <<EOF
{
    "event_id": "${event_id}",
    "type": "${event_type}",
    "source": "${source}",
    "timestamp": ${timestamp},
    "data": ${data},
    "metadata": ${metadata}
}
EOF
    else
        log_error "事件不存在: ${event_id}"
        return 1
    fi
}

# ==============================================================================
# 事件统计
# ==============================================================================
# 获取事件统计
get_event_stats() {
    local total_events=${#EVENT_HISTORY[@]}
    local queue_size=${#EVENT_QUEUE[@]}
    local subscriber_count=0
    local -A type_counts

    # 统计订阅者
    for key in "${!EVENT_SUBSCRIBERS[@]}"; do
        if [[ "${key}" == *"_handler" ]]; then
            ((subscriber_count++))

            local event_type="${key%%:*}"
            type_counts["${event_type}"]=$((type_counts[${event_type}] + 1))
        fi
    done

    # 统计事件类型
    local type_stats=""
    for event in "${EVENT_HISTORY[@]}"; do
        local event_type=$(echo "${event}" | cut -d'|' -f2)
        type_counts["${event_type}_events"]=$((type_counts[${event_type}_events] + 1))
    done

    cat <<EOF
{
    "total_events": ${total_events},
    "queue_size": ${queue_size},
    "subscriber_count": ${subscriber_count},
    "worker_count": ${#EVENT_WORKERS[@]},
    "running": ${EVENT_BUS_RUNNING}
}
EOF
}

# ==============================================================================
# 预定义事件处理器
# ==============================================================================
# 内存事件处理器
handle_memory_event() {
    local event_id="$1"
    local event_type="$2"
    local source="$3"
    local timestamp="$4"
    local data="$5"
    local metadata="$6"

    local mem_percent=$(echo "${data}" | jq -r '.memory_percent')

    if [[ ${mem_percent} -gt 90 ]]; then
        log_warning "内存使用过高: ${mem_percent}%"
        # 触发内存优化
        optimize_memory "aggressive"
    fi
}

# ZRAM事件处理器
handle_zram_event() {
    local event_id="$1"
    local event_type="$2"
    local source="$3"
    local timestamp="$4"
    local data="$5"
    local metadata="$6"

    local zram_percent=$(echo "${data}" | jq -r '.zram_percent')

    if [[ ${zram_percent} -gt 80 ]]; then
        log_warning "ZRAM使用过高: ${zram_percent}%"
        # 触发ZRAM调整
        adaptive_tune
    fi
}

# 决策事件处理器
handle_decision_event() {
    local event_id="$1"
    local event_type="$2"
    local source="$3"
    local timestamp="$4"
    local data="$5"
    local metadata="$6"

    local decision_type=$(echo "${data}" | jq -r '.decision_type')
    local decision_id=$(echo "${data}" | jq -r '.decision_id')

    log_info "决策执行: ${decision_type} (${decision_id})"
}

# 注册默认事件处理器
register_default_event_handlers() {
    # 内存事件
    subscribe_event "memory" "handle_memory_event"

    # ZRAM事件
    subscribe_event "zram" "handle_zram_event"

    # 决策事件
    subscribe_event "decision" "handle_decision_event"

    log_info "默认事件处理器已注册"
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f init_event_bus
export -f publish_event
export -f generate_event_id
export -f add_event_to_queue
export -f subscribe_event
export -f unsubscribe_event
export -f trigger_subscribers
export -f event_matches_filter
export -f start_event_bus
export -f stop_event_bus
export -f start_event_worker
export -f persist_event
export -f load_persisted_events
export -f cleanup_old_events
export -f log_event
export -f get_event_history
export -f get_event_details
export -f get_event_stats
export -f handle_memory_event
export -f handle_zram_event
export -f handle_decision_event
export -f register_default_event_handlers
