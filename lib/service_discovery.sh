#!/bin/bash
# ==============================================================================
# Z-Panel Pro V8.0 - 服务发现
# ==============================================================================
# @description    服务发现和注册机制，支持健康检查、负载均衡
# @version       8.0.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 服务发现配置
# ==============================================================================
declare -gA SERVICE_DISCOVERY_CONFIG=(
    [registry_type]="consul"
    [consul_addr]="localhost:8500"
    [consul_token]=""
    [health_check_interval]="10"
    [health_check_timeout]="5"
    [deregister_critical]="30"
    [service_ttl]="60"
    [load_balancer]="round_robin"
    [retry_attempts]="3"
    [retry_delay]="1"
)

# ==============================================================================
# 服务注册表
# ==============================================================================
declare -gA SERVICE_REGISTRY=()
declare -gA SERVICE_HEALTH=()
declare -gA SERVICE_INSTANCES=()

# ==============================================================================
# 负载均衡状态
# ==============================================================================
declare -gA LOAD_BALANCER_STATE=()

# ==============================================================================
# 服务发现状态
# ==============================================================================
declare -g SERVICE_DISCOVERY_RUNNING=false

# ==============================================================================
# 初始化服务发现
# ==============================================================================
init_service_discovery() {
    log_info "初始化服务发现..."

    # 创建目录
    mkdir -p "/opt/Z-Panel-Pro/tmp/service_discovery"

    # 加载服务注册表
    load_service_registry

    # 启动健康检查
    start_health_check

    log_info "服务发现初始化完成"
    return 0
}

# ==============================================================================
# 服务注册
# ==============================================================================
# 注册服务
register_service() {
    local service_name="$1"
    local service_address="$2"
    local service_port="${3:-}"
    local service_metadata="${4:-}"
    local health_check_url="${5:-/health}"

    if [[ -z "${service_name}" ]] || [[ -z "${service_address}" ]]; then
        log_error "缺少必需参数: service_name, service_address"
        return 1
    fi

    local service_id="${service_name}_$(date +%s)_${RANDOM}"
    local registered_at=$(date +%s)

    # 存储服务信息
    SERVICE_REGISTRY["${service_id}_name"]="${service_name}"
    SERVICE_REGISTRY["${service_id}_address"]="${service_address}"
    SERVICE_REGISTRY["${service_id}_port"]="${service_port}"
    SERVICE_REGISTRY["${service_id}_metadata"]="${service_metadata}"
    SERVICE_REGISTRY["${service_id}_health_check_url"]="${health_check_url}"
    SERVICE_REGISTRY["${service_id}_registered_at"]="${registered_at}"
    SERVICE_REGISTRY["${service_id}_status"]="healthy"
    SERVICE_REGISTRY["${service_id}_last_check"]="${registered_at}"

    # 添加到服务实例列表
    local instances="${SERVICE_INSTANCES[${service_name}]:-}"
    if [[ -n "${instances}" ]]; then
        SERVICE_INSTANCES[${service_name}]="${instances},${service_id}"
    else
        SERVICE_INSTANCES[${service_name}]="${service_id}"
    fi

    # 初始化健康状态
    SERVICE_HEALTH["${service_id}_healthy"]="true"
    SERVICE_HEALTH["${service_id}_last_healthy"]="${registered_at}"
    SERVICE_HEALTH["${service_id}_fail_count"]="0"

    # 初始化负载均衡状态
    LOAD_BALANCER_STATE["${service_name}_index"]="0"
    LOAD_BALANCER_STATE["${service_name}_connections"]="0"

    log_info "服务已注册: ${service_name} -> ${service_address}:${service_port}"
    return 0
}

# 注销服务
deregister_service() {
    local service_id="$1"

    if [[ -z "${service_id}" ]]; then
        log_error "缺少必需参数: service_id"
        return 1
    fi

    local service_name="${SERVICE_REGISTRY[${service_id}_name]:-}"

    if [[ -z "${service_name}" ]]; then
        log_error "服务不存在: ${service_id}"
        return 1
    fi

    # 从注册表中删除
    for key in "${!SERVICE_REGISTRY[@]}"; do
        if [[ "${key}" == "${service_id}_"* ]]; then
            unset SERVICE_REGISTRY["${key}"]
        fi
    done

    # 从健康状态中删除
    for key in "${!SERVICE_HEALTH[@]}"; do
        if [[ "${key}" == "${service_id}_"* ]]; then
            unset SERVICE_HEALTH["${key}"]
        fi
    done

    # 从实例列表中删除
    local instances="${SERVICE_INSTANCES[${service_name}]:-}"
    local new_instances=""
    IFS=',' read -ra INSTANCE_ARRAY <<< "${instances}"
    for instance in "${INSTANCE_ARRAY[@]}"; do
        if [[ "${instance}" != "${service_id}" ]]; then
            if [[ -n "${new_instances}" ]]; then
                new_instances+=",${instance}"
            else
                new_instances="${instance}"
            fi
        fi
    done
    SERVICE_INSTANCES[${service_name}]="${new_instances}"

    log_info "服务已注销: ${service_id}"
    return 0
}

# ==============================================================================
# 服务发现
# ==============================================================================
# 发现服务
discover_service() {
    local service_name="$1"
    local exclude_unhealthy="${2:-true}"

    if [[ -z "${service_name}" ]]; then
        log_error "缺少必需参数: service_name"
        return 1
    fi

    local instances="${SERVICE_INSTANCES[${service_name}]:-}"

    if [[ -z "${instances}" ]]; then
        log_error "服务未找到: ${service_name}"
        return 1
    fi

    local healthy_instances=""
    IFS=',' read -ra INSTANCE_ARRAY <<< "${instances}"
    for instance in "${INSTANCE_ARRAY[@]}"; do
        local is_healthy="${SERVICE_HEALTH[${instance}_healthy]:-true}"
        if [[ "${exclude_unhealthy}" == "true" ]] && [[ "${is_healthy}" != "true" ]]; then
            continue
        fi

        if [[ -n "${healthy_instances}" ]]; then
            healthy_instances+=",${instance}"
        else
            healthy_instances="${instance}"
        fi
    done

    if [[ -z "${healthy_instances}" ]]; then
        log_error "没有可用的健康实例: ${service_name}"
        return 1
    fi

    echo "${healthy_instances}"
}

# 获取服务地址
get_service_address() {
    local service_id="$1"

    if [[ -z "${service_id}" ]]; then
        log_error "缺少必需参数: service_id"
        return 1
    fi

    local address="${SERVICE_REGISTRY[${service_id}_address]:-}"
    local port="${SERVICE_REGISTRY[${service_id}_port]:-}"

    if [[ -z "${address}" ]]; then
        log_error "服务不存在: ${service_id}"
        return 1
    fi

    if [[ -n "${port}" ]]; then
        echo "${address}:${port}"
    else
        echo "${address}"
    fi
}

# ==============================================================================
# 负载均衡
# ==============================================================================
# 选择服务实例（负载均衡）
select_service_instance() {
    local service_name="$1"
    local load_balancer="${2:-${SERVICE_DISCOVERY_CONFIG[load_balancer]}}"

    local instances=$(discover_service "${service_name}" "true")

    if [[ -z "${instances}" ]]; then
        return 1
    fi

    IFS=',' read -ra INSTANCE_ARRAY <<< "${instances}"
    local selected_instance=""

    case "${load_balancer}" in
        round_robin)
            selected_instance=$(select_round_robin "${service_name}" "${INSTANCE_ARRAY[@]}")
            ;;
        random)
            selected_instance=$(select_random "${INSTANCE_ARRAY[@]}")
            ;;
        least_connections)
            selected_instance=$(select_least_connections "${service_name}" "${INSTANCE_ARRAY[@]}")
            ;;
        ip_hash)
            selected_instance=$(select_ip_hash "${service_name}" "${INSTANCE_ARRAY[@]}")
            ;;
        *)
            selected_instance=$(select_round_robin "${service_name}" "${INSTANCE_ARRAY[@]}")
            ;;
    esac

    echo "${selected_instance}"
}

# 轮询选择
select_round_robin() {
    local service_name="$1"
    shift
    local instances=("$@")

    local current_index="${LOAD_BALANCER_STATE[${service_name}_index]:-0}"
    local instance_count=${#instances[@]}

    local selected="${instances[$((current_index % instance_count))]}"
    LOAD_BALANCER_STATE["${service_name}_index"]="$((current_index + 1))"

    # 更新连接数
    local connections="${LOAD_BALANCER_STATE[${service_name}_connections]:-0}"
    LOAD_BALANCER_STATE["${service_name}_connections"]="$((connections + 1))"

    echo "${selected}"
}

# 随机选择
select_random() {
    local instances=("$@")
    local instance_count=${#instances[@]}
    local random_index=$((RANDOM % instance_count))

    echo "${instances[$random_index]}"
}

# 最少连接选择
select_least_connections() {
    local service_name="$1"
    shift
    local instances=("$@")

    local selected=""
    local min_connections=-1

    for instance in "${instances[@]}"; do
        local connections="${LOAD_BALANCER_STATE[${service_name}_${instance}_connections]:-0}"

        if [[ ${min_connections} -lt 0 ]] || [[ ${connections} -lt ${min_connections} ]]; then
            min_connections=${connections}
            selected="${instance}"
        fi
    done

    # 更新连接数
    local connections="${LOAD_BALANCER_STATE[${service_name}_${selected}_connections]:-0}"
    LOAD_BALANCER_STATE["${service_name}_${selected}_connections"]="$((connections + 1))"

    echo "${selected}"
}

# IP哈希选择
select_ip_hash() {
    local service_name="$1"
    shift
    local instances=("$@")

    local client_ip="${REMOTE_ADDR:-127.0.0.1}"
    local hash=$(echo "${client_ip}" | md5sum | cut -d' ' -f1)
    local hash_value=$((16#${hash:0:8}))

    local instance_count=${#instances[@]}
    local selected_index=$((hash_value % instance_count))

    echo "${instances[$selected_index]}"
}

# 释放连接
release_connection() {
    local service_name="$1"
    local service_id="$2"

    if [[ -n "${service_name}" ]] && [[ -n "${service_id}" ]]; then
        local connections="${LOAD_BALANCER_STATE[${service_name}_${service_id}_connections]:-0}"
        if [[ ${connections} -gt 0 ]]; then
            LOAD_BALANCER_STATE["${service_name}_${service_id}_connections"]="$((connections - 1))"
        fi
    fi
}

# ==============================================================================
# 健康检查
# ==============================================================================
# 健康检查服务
check_service_health() {
    local service_id="$1"

    if [[ -z "${service_id}" ]]; then
        log_error "缺少必需参数: service_id"
        return 1
    fi

    local address="${SERVICE_REGISTRY[${service_id}_address]:-}"
    local port="${SERVICE_REGISTRY[${service_id}_port]:-}"
    local health_check_url="${SERVICE_REGISTRY[${service_id}_health_check_url]:-/health}"
    local timeout="${SERVICE_DISCOVERY_CONFIG[health_check_timeout]}"

    local service_url="${address}"
    if [[ -n "${port}" ]]; then
        service_url="${address}:${port}"
    fi

    local is_healthy=false

    # 使用curl进行健康检查
    if command -v curl &> /dev/null; then
        local response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "${timeout}" "http://${service_url}${health_check_url}" 2>/dev/null)

        if [[ "${response}" == "200" ]] || [[ "${response}" == "204" ]]; then
            is_healthy=true
        fi
    # 使用nc进行端口检查
    elif command -v nc &> /dev/null; then
        if nc -z -w "${timeout}" "${address}" "${port}" 2>/dev/null; then
            is_healthy=true
        fi
    fi

    # 更新健康状态
    local current_time=$(date +%s)
    if [[ "${is_healthy}" == "true" ]]; then
        SERVICE_HEALTH["${service_id}_healthy"]="true"
        SERVICE_HEALTH["${service_id}_last_healthy"]="${current_time}"
        SERVICE_HEALTH["${service_id}_fail_count"]="0"
        SERVICE_REGISTRY["${service_id}_status"]="healthy"
    else
        local fail_count="${SERVICE_HEALTH[${service_id}_fail_count]:-0}"
        fail_count=$((fail_count + 1))
        SERVICE_HEALTH["${service_id}_fail_count"]="${fail_count}"

        local deregister_threshold="${SERVICE_DISCOVERY_CONFIG[deregister_critical]}"
        if [[ ${fail_count} -ge ${deregister_threshold} ]]; then
            SERVICE_HEALTH["${service_id}_healthy"]="false"
            SERVICE_REGISTRY["${service_id}_status"]="critical"
            log_warning "服务不健康: ${service_id} (连续失败 ${fail_count} 次)"
        fi
    fi

    SERVICE_REGISTRY["${service_id}_last_check"]="${current_time}"

    return 0
}

# 启动健康检查
start_health_check() {
    log_info "启动健康检查..."

    local interval="${SERVICE_DISCOVERY_CONFIG[health_check_interval]}"

    (
        while true; do
            sleep "${interval}"

            # 检查所有服务
            for service_id in "${!SERVICE_REGISTRY[@]}"; do
                if [[ "${service_id}" == *"_name" ]]; then
                    local id="${service_id%_name}"
                    check_service_health "${id}"
                fi
            done
        done
    ) &

    log_info "健康检查已启动"
}

# ==============================================================================
# 重试机制
# ==============================================================================
# 带重试的服务调用
call_service_with_retry() {
    local service_name="$1"
    local endpoint="$2"
    local method="${3:-GET}"
    local data="${4:-}"
    local max_attempts="${5:-${SERVICE_DISCOVERY_CONFIG[retry_attempts]}}"
    local delay="${6:-${SERVICE_DISCOVERY_CONFIG[retry_delay]}}"

    local attempt=1
    local response=""

    while [[ ${attempt} -le ${max_attempts} ]]; do
        local service_id=$(select_service_instance "${service_name}")

        if [[ -z "${service_id}" ]]; then
            log_error "无法选择服务实例: ${service_name}"
            sleep "${delay}"
            ((attempt++))
            continue
        fi

        local service_address=$(get_service_address "${service_id}")
        local url="http://${service_address}${endpoint}"

        # 调用服务
        if [[ "${method}" == "GET" ]]; then
            response=$(curl -s -X GET "${url}" 2>/dev/null)
        elif [[ "${method}" == "POST" ]]; then
            response=$(curl -s -X POST -H "Content-Type: application/json" -d "${data}" "${url}" 2>/dev/null)
        elif [[ "${method}" == "PUT" ]]; then
            response=$(curl -s -X PUT -H "Content-Type: application/json" -d "${data}" "${url}" 2>/dev/null)
        elif [[ "${method}" == "DELETE" ]]; then
            response=$(curl -s -X DELETE "${url}" 2>/dev/null)
        fi

        local exit_code=$?

        if [[ ${exit_code} -eq 0 ]]; then
            # 释放连接
            release_connection "${service_name}" "${service_id}"
            echo "${response}"
            return 0
        fi

        log_warning "服务调用失败 (尝试 ${attempt}/${max_attempts}): ${service_name} -> ${url}"

        # 释放连接
        release_connection "${service_name}" "${service_id}"

        sleep "${delay}"
        ((attempt++))
    done

    log_error "服务调用失败，已达到最大重试次数: ${service_name}"
    return 1
}

# ==============================================================================
# Consul集成
# ==============================================================================
# 注册到Consul
register_to_consul() {
    local service_name="$1"
    local service_address="$2"
    local service_port="${3:-}"

    if [[ "${SERVICE_DISCOVERY_CONFIG[registry_type]}" != "consul" ]]; then
        return 0
    fi

    local consul_addr="${SERVICE_DISCOVERY_CONFIG[consul_addr]}"
    local consul_token="${SERVICE_DISCOVERY_CONFIG[consul_token]:-}"

    local service_data=$(cat <<EOF
{
    "ID": "${service_name}",
    "Name": "${service_name}",
    "Address": "${service_address}",
    "Port": ${service_port:-0},
    "Check": {
        "HTTP": "http://${service_address}:${service_port}/health",
        "Interval": "${SERVICE_DISCOVERY_CONFIG[health_check_interval]}s",
        "Timeout": "${SERVICE_DISCOVERY_CONFIG[health_check_timeout]}s",
        "DeregisterCriticalServiceAfter": "${SERVICE_DISCOVERY_CONFIG[deregister_critical]}s"
    }
}
EOF
)

    local token_param=""
    if [[ -n "${consul_token}" ]]; then
        token_param="?token=${consul_token}"
    fi

    curl -s -X PUT -H "Content-Type: application/json" -d "${service_data}" \
        "http://${consul_addr}/v1/agent/service/register${token_param}" 2>/dev/null
}

# 从Consul注销
deregister_from_consul() {
    local service_name="$1"

    if [[ "${SERVICE_DISCOVERY_CONFIG[registry_type]}" != "consul" ]]; then
        return 0
    fi

    local consul_addr="${SERVICE_DISCOVERY_CONFIG[consul_addr]}"
    local consul_token="${SERVICE_DISCOVERY_CONFIG[consul_token]:-}"

    local token_param=""
    if [[ -n "${consul_token}" ]]; then
        token_param="?token=${consul_token}"
    fi

    curl -s -X PUT "http://${consul_addr}/v1/agent/service/deregister/${service_name}${token_param}" 2>/dev/null
}

# 从Consul发现服务
discover_from_consul() {
    local service_name="$1"

    if [[ "${SERVICE_DISCOVERY_CONFIG[registry_type]}" != "consul" ]]; then
        return 1
    fi

    local consul_addr="${SERVICE_DISCOVERY_CONFIG[consul_addr]}"
    local consul_token="${SERVICE_DISCOVERY_CONFIG[consul_token]:-}"

    local token_param=""
    if [[ -n "${consul_token}" ]]; then
        token_param="?token=${consul_token}"
    fi

    curl -s "http://${consul_addr}/v1/health/service/${service_name}${token_param}" 2>/dev/null
}

# ==============================================================================
# 服务状态查询
# ==============================================================================
# 获取所有服务
get_all_services() {
    local services=""

    for service_name in "${!SERVICE_INSTANCES[@]}"; do
        if [[ -n "${services}" ]]; then
            services+=",${service_name}"
        else
            services="${service_name}"
        fi
    done

    echo "${services}"
}

# 获取服务详细信息
get_service_details() {
    local service_name="$1"

    if [[ -z "${service_name}" ]]; then
        log_error "缺少必需参数: service_name"
        return 1
    fi

    local instances="${SERVICE_INSTANCES[${service_name}]:-}"

    if [[ -z "${instances}" ]]; then
        return 1
    fi

    local details=""
    IFS=',' read -ra INSTANCE_ARRAY <<< "${instances}"
    for instance in "${INSTANCE_ARRAY[@]}"; do
        details+="Service ID: ${instance}"$'\n'
        details+="  Address: ${SERVICE_REGISTRY[${instance}_address]}"$'\n'
        details+="  Port: ${SERVICE_REGISTRY[${instance}_port]}"$'\n'
        details+="  Status: ${SERVICE_REGISTRY[${instance}_status]}"$'\n'
        details+="  Healthy: ${SERVICE_HEALTH[${instance}_healthy]}"$'\n'
        details+="  Last Check: ${SERVICE_REGISTRY[${instance}_last_check]}"$'\n'
        details+=$'\n'
    done

    echo "${details}"
}

# ==============================================================================
# 持久化
# ==============================================================================
# 加载服务注册表
load_service_registry() {
    local registry_file="/opt/Z-Panel-Pro/tmp/service_discovery/registry.db"

    if [[ -f "${registry_file}" ]]; then
        source "${registry_file}"
        log_debug "服务注册表已加载"
    fi
}

# 保存服务注册表
save_service_registry() {
    local registry_file="/opt/Z-Panel-Pro/tmp/service_discovery/registry.db"

    # 保存注册表
    declare -p SERVICE_REGISTRY > "${registry_file}"

    log_debug "服务注册表已保存"
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f init_service_discovery
export -f register_service
export -f deregister_service
export -f discover_service
export -f get_service_address
export -f select_service_instance
export -f select_round_robin
export -f select_random
export -f select_least_connections
export -f select_ip_hash
export -f release_connection
export -f check_service_health
export -f start_health_check
export -f call_service_with_retry
export -f register_to_consul
export -f deregister_from_consul
export -f discover_from_consul
export -f get_all_services
export -f get_service_details
export -f load_service_registry
export -f save_service_registry
