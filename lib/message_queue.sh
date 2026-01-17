#!/bin/bash
# ==============================================================================
# Z-Panel Pro V8.0 - 消息队列
# ==============================================================================
# @description    企业级消息队列，支持FIFO、优先级、延迟投递、持久化
# @version       8.0.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 消息队列配置
# ==============================================================================
declare -gA MQ_CONFIG=(
    [queue_dir]="/opt/Z-Panel-Pro/data/queues"
    [max_queue_size]="10000"
    [max_message_size]="10M"
    [persistence_enabled]="true"
    [delivery_mode]="persistent"
    [ack_timeout]="30"
    [retry_limit]="3"
    [dead_letter_queue]="true"
    [dlq_name]="dead_letter_queue"
)

# ==============================================================================
# 消息类型
# ==============================================================================
declare -gA MQ_MESSAGE_TYPES=(
    [direct]="直接消息"
    [fanout]="广播消息"
    [topic]="主题消息"
    [delayed]="延迟消息"
    [retry]="重试消息"
)

# ==============================================================================
# 消息队列存储
# ==============================================================================
declare -gA MQ_QUEUES=()
declare -gA MQ_MESSAGES=()
declare -gA MQ_CONSUMERS=()
declare -gA MQ_METADATA=()

# ==============================================================================
# 消息状态
# ==============================================================================
declare -gA MQ_DELIVERY_STATUS=()

# ==============================================================================
# 初始化消息队列
# ==============================================================================
init_message_queue() {
    log_info "初始化消息队列..."

    # 创建队列目录
    mkdir -p "${MQ_CONFIG[queue_dir]}"

    # 加载持久化的队列
    load_persisted_queues

    log_info "消息队列初始化完成"
    return 0
}

# ==============================================================================
# 队列管理
# ==============================================================================
# 创建队列
create_queue() {
    local queue_name="$1"
    local queue_type="${2:-direct}"
    local durable="${3:-true}"
    local auto_delete="${4:-false}"

    if [[ -z "${queue_name}" ]]; then
        log_error "缺少必需参数: queue_name"
        return 1
    fi

    # 检查队列是否已存在
    if [[ -n "${MQ_QUEUES[${queue_name}_type]+isset}" ]]; then
        log_error "队列已存在: ${queue_name}"
        return 1
    fi

    # 创建队列
    MQ_QUEUES["${queue_name}_type"]="${queue_type}"
    MQ_QUEUES["${queue_name}_durable"]="${durable}"
    MQ_QUEUES["${queue_name}_auto_delete"]="${auto_delete}"
    MQ_QUEUES["${queue_name}_created"]=$(date +%s)
    MQ_QUEUES["${queue_name}_messages"]="0"
    MQ_QUEUES["${queue_name}_consumers"]="0"
    MQ_QUEUES["${queue_name}_enabled"]="true"

    MQ_METADATA["${queue_name}_version"]="1.0"

    log_info "队列已创建: ${queue_name} (${queue_type})"

    # 持久化
    if [[ "${durable}" == "true" ]]; then
        persist_queue "${queue_name}"
    fi

    return 0
}

# 删除队列
delete_queue() {
    local queue_name="$1"

    if [[ -z "${MQ_QUEUES[${queue_name}_type]+isset}" ]]; then
        log_error "队列不存在: ${queue_name}"
        return 1
    fi

    # 删除队列数据
    for key in "${!MQ_QUEUES[@]}"; do
        if [[ "${key}" == "${queue_name}_"* ]]; then
            unset MQ_QUEUES["${key}"]
        fi
    done

    # 删除元数据
    unset MQ_METADATA["${queue_name}_version"]

    # 删除消息
    for key in "${!MQ_MESSAGES[@]}"; do
        if [[ "${key}" == "${queue_name}:"* ]]; then
            unset MQ_MESSAGES["${key}"]
        fi
    done

    # 删除消费者
    for key in "${!MQ_CONSUMERS[@]}"; do
        if [[ "${key}" == "${queue_name}:"* ]]; then
            unset MQ_CONSUMERS["${key}"]
        fi
    done

    # 删除持久化文件
    local queue_file="${MQ_CONFIG[queue_dir]}/${queue_name}.mq"
    rm -f "${queue_file}"

    log_info "队列已删除: ${queue_name}"
    return 0
}

# 清空队列
purge_queue() {
    local queue_name="$1"

    if [[ -z "${MQ_QUEUES[${queue_name}_type]+isset}" ]]; then
        log_error "队列不存在: ${queue_name}"
        return 1
    fi

    # 删除所有消息
    for key in "${!MQ_MESSAGES[@]}"; do
        if [[ "${key}" == "${queue_name}:"* ]]; then
            unset MQ_MESSAGES["${key}"]
        fi
    done

    # 重置消息计数
    MQ_QUEUES["${queue_name}_messages"]="0"

    log_info "队列已清空: ${queue_name}"
    return 0
}

# ==============================================================================
# 消息发布
# ==============================================================================
# 发布消息
publish_message() {
    local queue_name="$1"
    local message_body="$2"
    local priority="${3:-5}"
    local ttl="${4:-0}"
    local delay="${5:-0}"
    local headers="${6:-}"

    if [[ -z "${queue_name}" ]] || [[ -z "${message_body}" ]]; then
        log_error "缺少必需参数: queue_name, message_body"
        return 1
    fi

    # 检查队列是否存在
    if [[ -z "${MQ_QUEUES[${queue_name}_type]+isset}" ]]; then
        log_error "队列不存在: ${queue_name}"
        return 1
    fi

    # 检查队列是否启用
    if [[ "${MQ_QUEUES[${queue_name}_enabled]}" != "true" ]]; then
        log_error "队列已禁用: ${queue_name}"
        return 1
    fi

    # 检查消息大小
    local message_size=${#message_body}
    local max_size="${MQ_CONFIG[max_message_size]}"

    if [[ ${message_size} -gt ${max_size} ]]; then
        log_error "消息大小超过限制: ${message_size} > ${max_size}"
        return 1
    fi

    # 检查队列大小
    local queue_size="${MQ_QUEUES[${queue_name}_messages]}"
    local max_queue_size="${MQ_CONFIG[max_queue_size]}"

    if [[ ${queue_size} -ge ${max_queue_size} ]]; then
        log_warning "队列已满，丢弃消息: ${queue_name}"
        return 1
    fi

    # 生成消息ID
    local message_id=$(generate_message_id)

    # 计算投递时间
    local delivery_time=$(($(date +%s) + delay))

    # 创建消息
    local message="${message_id}|${queue_name}|${priority}|${ttl}|${delivery_time}|${headers}|${message_body}"

    # 添加到队列
    local message_key="${queue_name}:${message_id}"
    MQ_MESSAGES["${message_key}"]="${message}"

    # 更新队列统计
    MQ_QUEUES["${queue_name}_messages"]="$((queue_size + 1))"

    # 持久化
    if [[ "${MQ_CONFIG[persistence_enabled]}" == "true" ]]; then
        persist_queue "${queue_name}"
    fi

    log_debug "消息已发布: ${message_id} -> ${queue_name}"

    echo "${message_id}"
    return 0
}

# 生成消息ID
generate_message_id() {
    local timestamp=$(date +%s%N)
    local random=$(head -c 8 /dev/urandom | xxd -p)
    echo "msg_${timestamp}_${random}"
}

# ==============================================================================
# 消息消费
# ==============================================================================
# 注册消费者
register_consumer() {
    local queue_name="$1"
    local consumer_id="$2"
    local auto_ack="${3:-false}"
    local prefetch="${4:-1}"

    if [[ -z "${queue_name}" ]] || [[ -z "${consumer_id}" ]]; then
        log_error "缺少必需参数: queue_name, consumer_id"
        return 1
    fi

    # 检查队列是否存在
    if [[ -z "${MQ_QUEUES[${queue_name}_type]+isset}" ]]; then
        log_error "队列不存在: ${queue_name}"
        return 1
    fi

    # 注册消费者
    local consumer_key="${queue_name}:${consumer_id}"
    MQ_CONSUMERS["${consumer_key}_auto_ack"]="${auto_ack}"
    MQ_CONSUMERS["${consumer_key}_prefetch"]="${prefetch}"
    MQ_CONSUMERS["${consumer_key}_created"]=$(date +%s)
    MQ_CONSUMERS["${consumer_key}_messages"]="0"
    MQ_CONSUMERS["${consumer_key}_active"]="true"

    # 更新队列消费者计数
    local consumer_count="${MQ_QUEUES[${queue_name}_consumers]}"
    MQ_QUEUES[${queue_name}_consumers]=$((consumer_count + 1))

    log_debug "消费者已注册: ${consumer_id} -> ${queue_name}"

    return 0
}

# 注销消费者
unregister_consumer() {
    local queue_name="$1"
    local consumer_id="$2"

    local consumer_key="${queue_name}:${consumer_id}"

    # 删除消费者
    for key in "${!MQ_CONSUMERS[@]}"; do
        if [[ "${key}" == "${consumer_key}"* ]]; then
            unset MQ_CONSUMERS["${key}"]
        fi
    done

    # 更新队列消费者计数
    local consumer_count="${MQ_QUEUES[${queue_name}_consumers]}"
    MQ_QUEUES[${queue_name}_consumers]=$((consumer_count - 1))

    log_debug "消费者已注销: ${consumer_id} <- ${queue_name}"

    return 0
}

# 获取消息
get_message() {
    local queue_name="$1"
    local consumer_id="${2:-}"
    local auto_ack="${3:-false}"

    if [[ -z "${MQ_QUEUES[${queue_name}_type]+isset}" ]]; then
        log_error "队列不存在: ${queue_name}"
        return 1
    fi

    local current_time=$(date +%s)
    local found_message=""
    local found_message_key=""

    # 查找可投递的消息
    for key in "${!MQ_MESSAGES[@]}"; do
        if [[ "${key}" == "${queue_name}:"* ]]; then
            local message="${MQ_MESSAGES[${key}]}"
            local message_id=$(echo "${message}" | cut -d'|' -f1)
            local priority=$(echo "${message}" | cut -d'|' -f3)
            local ttl=$(echo "${message}" | cut -d'|' -f4)
            local delivery_time=$(echo "${message}" | cut -d'|' -f5)

            # 检查是否已投递
            if [[ -n "${MQ_DELIVERY_STATUS[${message_id}_delivered]+isset}" ]]; then
                continue
            fi

            # 检查投递时间
            if [[ ${delivery_time} -gt ${current_time} ]]; then
                continue
            fi

            # 检查TTL
            if [[ ${ttl} -gt 0 ]]; then
                local created_time=$(echo "${message}" | cut -d'|' -f2 | sed 's/.*|//')
                local created=$(echo "${created_time}" | cut -d'|' -f1)

                if [[ $((current_time - created)) -gt ${ttl} ]]; then
                    # 消息已过期
                    unset MQ_MESSAGES["${key}"]
                    continue
                fi
            fi

            # 找到消息
            if [[ -z "${found_message}" ]] || [[ ${priority} -gt $(echo "${found_message}" | cut -d'|' -f3) ]]; then
                found_message="${message}"
                found_message_key="${key}"
            fi
        fi
    done

    if [[ -z "${found_message}" ]]; then
        return 1
    fi

    # 标记消息已投递
    local message_id=$(echo "${found_message}" | cut -d'|' -f1)
    MQ_DELIVERY_STATUS["${message_id}_delivered"]="true"
    MQ_DELIVERY_STATUS["${message_id}_consumer"]="${consumer_id}"
    MQ_DELIVERY_STATUS["${message_id}_delivered_at"]=$(date +%s)

    # 自动确认
    if [[ "${auto_ack}" == "true" ]]; then
        ack_message "${queue_name}" "${message_id}" "${consumer_id}"
    fi

    # 更新消费者统计
    if [[ -n "${consumer_id}" ]]; then
        local consumer_key="${queue_name}:${consumer_id}"
        local consumer_messages="${MQ_CONSUMERS[${consumer_key}_messages]}"
        MQ_CONSUMERS["${consumer_key}_messages"]="$((consumer_messages + 1))"
    fi

    echo "${found_message}"
    return 0
}

# 确认消息
ack_message() {
    local queue_name="$1"
    local message_id="$2"
    local consumer_id="${3:-}"

    # 删除消息
    local message_key="${queue_name}:${message_id}"
    unset MQ_MESSAGES["${message_key}"]

    # 删除投递状态
    for key in "${!MQ_DELIVERY_STATUS[@]}"; do
        if [[ "${key}" == "${message_id}_"* ]]; then
            unset MQ_DELIVERY_STATUS["${key}"]
        fi
    done

    # 更新队列统计
    local queue_size="${MQ_QUEUES[${queue_name}_messages]}"
    MQ_QUEUES[${queue_name}_messages]=$((queue_size - 1))

    log_debug "消息已确认: ${message_id}"

    return 0
}

# 拒绝消息
reject_message() {
    local queue_name="$1"
    local message_id="$2"
    local requeue="${3:-false}"

    if [[ "${requeue}" == "true" ]]; then
        # 重新入队
        local message_key="${queue_name}:${message_id}"
        local message="${MQ_MESSAGES[${message_key}]}"

        # 删除投递状态
        for key in "${!MQ_DELIVERY_STATUS[@]}"; do
            if [[ "${key}" == "${message_id}_"* ]]; then
                unset MQ_DELIVERY_STATUS["${key}"]
            fi
        done

        log_debug "消息已重新入队: ${message_id}"
    else
        # 发送到死信队列
        if [[ "${MQ_CONFIG[dead_letter_queue]}" == "true" ]]; then
            local dlq_name="${MQ_CONFIG[dlq_name]}"

            # 确保死信队列存在
            if [[ -z "${MQ_QUEUES[${dlq_name}_type]+isset}" ]]; then
                create_queue "${dlq_name}" "direct" true false
            fi

            # 获取原消息
            local message_key="${queue_name}:${message_id}"
            local message="${MQ_MESSAGES[${message_key}]}"
            local message_body=$(echo "${message}" | cut -d'|' -f7)
            local headers="original_queue=${queue_name},original_message=${message_id}"

            # 发布到死信队列
            publish_message "${dlq_name}" "${message_body}" 1 0 0 "${headers}"

            # 删除原消息
            ack_message "${queue_name}" "${message_id}"

            log_debug "消息已发送到死信队列: ${message_id}"
        else
            # 直接删除
            ack_message "${queue_name}" "${message_id}"
            log_debug "消息已拒绝: ${message_id}"
        fi
    fi

    return 0
}

# ==============================================================================
# 队列持久化
# ==============================================================================
# 持久化队列
persist_queue() {
    local queue_name="$1"

    local queue_file="${MQ_CONFIG[queue_dir]}/${queue_name}.mq"

    # 写入队列元数据
    {
        echo "# Z-Panel Pro 消息队列"
        echo "# 队列名称: ${queue_name}"
        echo "# 类型: ${MQ_QUEUES[${queue_name}_type]}"
        echo "# 持久化: ${MQ_QUEUES[${queue_name}_durable]}"
        echo "# 创建时间: $(date -d "@${MQ_QUEUES[${queue_name}_created]}" '+%Y-%m-%d %H:%M:%S')"
        echo "# 版本: ${MQ_METADATA[${queue_name}_version]}"
        echo ""

        # 写入消息
        for key in "${!MQ_MESSAGES[@]}"; do
            if [[ "${key}" == "${queue_name}:"* ]]; then
                echo "${MQ_MESSAGES[${key}]}"
            fi
        done
    } > "${queue_file}"
}

# 加载队列
load_queue() {
    local queue_file="$1"

    if [[ ! -f "${queue_file}" ]]; then
        log_error "队列文件不存在: ${queue_file}"
        return 1
    fi

    local queue_name=$(basename "${queue_file}" .mq)

    # 读取队列元数据
    local queue_type=""
    local durable="true"
    local created=0
    local version="1.0"

    while IFS=':' read -r key value; do
        case "${key}" in
            "# 队列名称")
                queue_name="${value// /}"
                ;;
            "# 类型")
                queue_type="${value// /}"
                ;;
            "# 持久化")
                durable="${value// /}"
                ;;
            "# 创建时间")
                created=$(date -d "${value}" +%s 2>/dev/null || echo "0")
                ;;
            "# 版本")
                version="${value// /}"
                ;;
        esac
    done < "${queue_file}"

    # 创建队列
    if [[ -z "${MQ_QUEUES[${queue_name}_type]+isset}" ]]; then
        MQ_QUEUES["${queue_name}_type"]="${queue_type:-direct}"
        MQ_QUEUES["${queue_name}_durable"]="${durable}"
        MQ_QUEUES["${queue_name}_created"]="${created}"
        MQ_QUEUES["${queue_name}_messages"]="0"
        MQ_QUEUES["${queue_name}_consumers"]="0"
        MQ_QUEUES["${queue_name}_enabled"]="true"
        MQ_METADATA["${queue_name}_version"]="${version}"
    fi

    # 读取消息
    local message_count=0
    while IFS='|' read -r message_id queue priority ttl delivery_time headers message_body; do
        # 跳过注释和空行
        if [[ -z "${message_id}" ]] || [[ "${message_id}" == \#* ]]; then
            continue
        fi

        # 重建消息
        local message_key="${queue_name}:${message_id}"
        local message="${message_id}|${queue}|${priority}|${ttl}|${delivery_time}|${headers}|${message_body}"
        MQ_MESSAGES["${message_key}"]="${message}"
        ((message_count++))
    done < "${queue_file}"

    MQ_QUEUES["${queue_name}_messages"]="${message_count}"

    log_info "队列已加载: ${queue_name} (${message_count} 消息)"
    return 0
}

# 加载所有队列
load_persisted_queues() {
    local queue_dir="${MQ_CONFIG[queue_dir]}"

    if [[ ! -d "${queue_dir}" ]]; then
        return 0
    fi

    for queue_file in "${queue_dir}"/*.mq; do
        if [[ -f "${queue_file}" ]]; then
            load_queue "${queue_file}"
        fi
    done
}

# ==============================================================================
# 队列查询
# ==============================================================================
# 获取队列列表
list_queues() {
    local output=""

    for key in "${!MQ_QUEUES[@]}"; do
        if [[ "${key}" == *"_type" ]]; then
            local queue_name="${key%_type}"
            local type="${MQ_QUEUES[${key}]}"
            local messages="${MQ_QUEUES[${queue_name}_messages]}"
            local consumers="${MQ_QUEUES[${queue_name}_consumers]}"
            local enabled="${MQ_QUEUES[${queue_name}_enabled]}"

            output+="${queue_name}|${type}|${messages}|${consumers}|${enabled}"$'\n'
        fi
    done

    echo "${output}"
}

# 获取队列信息
get_queue_info() {
    local queue_name="$1"

    if [[ -z "${MQ_QUEUES[${queue_name}_type]+isset}" ]]; then
        log_error "队列不存在: ${queue_name}"
        return 1
    fi

    cat <<EOF
{
    "queue_name": "${queue_name}",
    "type": "${MQ_QUEUES[${queue_name}_type]}",
    "durable": ${MQ_QUEUES[${queue_name}_durable]},
    "auto_delete": ${MQ_QUEUES[${queue_name}_auto_delete]},
    "messages": ${MQ_QUEUES[${queue_name}_messages]},
    "consumers": ${MQ_QUEUES[${queue_name}_consumers]},
    "enabled": ${MQ_QUEUES[${queue_name}_enabled]},
    "created": ${MQ_QUEUES[${queue_name}_created]},
    "version": "${MQ_METADATA[${queue_name}_version]}"
}
EOF
}

# ==============================================================================
# 消息查询
# ==============================================================================
# 获取队列消息
get_queue_messages() {
    local queue_name="$1"
    local limit="${2:-100}"

    if [[ -z "${MQ_QUEUES[${queue_name}_type]+isset}" ]]; then
        log_error "队列不存在: ${queue_name}"
        return 1
    fi

    local messages=()

    for key in "${!MQ_MESSAGES[@]}"; do
        if [[ "${key}" == "${queue_name}:"* ]]; then
            messages+=("${MQ_MESSAGES[${key}]}")
        fi
    done

    # 按优先级排序
    IFS=$'\n' sorted_messages=($(sort -t'|' -k3 -rn <<< "${messages[*]}"))

    # 限制结果数量
    echo "${sorted_messages[@]:0:${limit}}"
}

# 获取消息统计
get_message_stats() {
    local queue_name="$1"

    if [[ -z "${MQ_QUEUES[${queue_name}_type]+isset}" ]]; then
        log_error "队列不存在: ${queue_name}"
        return 1
    fi

    local total_messages="${MQ_QUEUES[${queue_name}_messages]}"
    local total_consumers="${MQ_QUEUES[${queue_name}_consumers]}"
    local delivered_messages=0

    for key in "${!MQ_DELIVERY_STATUS[@]}"; do
        if [[ "${key}" == *"_delivered" ]] && [[ "${MQ_DELIVERY_STATUS[${key}]}" == "true" ]]; then
            ((delivered_messages++))
        fi
    done

    cat <<EOF
{
    "queue_name": "${queue_name}",
    "total_messages": ${total_messages},
    "pending_messages": $((total_messages - delivered_messages)),
    "delivered_messages": ${delivered_messages},
    "total_consumers": ${total_consumers}
}
EOF
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f init_message_queue
export -f create_queue
export -f delete_queue
export -f purge_queue
export -f publish_message
export -f generate_message_id
export -f register_consumer
export -f unregister_consumer
export -f get_message
export -f ack_message
export -f reject_message
export -f persist_queue
export -f load_queue
export -f load_persisted_queues
export -f list_queues
export -f get_queue_info
export -f get_queue_messages
export -f get_message_stats
