#!/bin/bash
# ==============================================================================
# Z-Panel Pro V8.0 - 策略管理器
# ==============================================================================
# @description    企业级策略管理系统，支持规则引擎、策略评估、动态调整
# @version       8.0.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 策略管理器配置
# ==============================================================================
declare -gA POLICY_CONFIG=(
    [policy_dir]="/opt/Z-Panel-Pro/config/policies"
    [cache_enabled]="true"
    [cache_ttl]="300"
    [evaluation_mode]="strict"
    [log_violations]="true"
    [auto_correct]="false"
    [audit_enabled]="true"
)

# ==============================================================================
# 策略定义
# ==============================================================================
declare -gA POLICIES=()
declare -gA POLICY_RULES=()
declare -gA POLICY_METADATA=()
declare -gA POLICY_CACHE=()

# ==============================================================================
# 策略类型
# ==============================================================================
declare -gA POLICY_TYPES=(
    [memory]="内存策略"
    [zram]="ZRAM策略"
    [swap]="Swap策略"
    [decision]="决策策略"
    [security]="安全策略"
    [performance]="性能策略"
)

# ==============================================================================
# 策略状态
# ==============================================================================
declare -gA POLICY_STATUS=()

# ==============================================================================
# 策略管理
# ==============================================================================
# 创建策略
create_policy() {
    local policy_id="$1"
    local policy_type="$2"
    local name="$3"
    local description="${4:-}"

    if [[ -z "${policy_id}" ]] || [[ -z "${policy_type}" ]] || [[ -z "${name}" ]]; then
        log_error "缺少必需参数: policy_id, policy_type, name"
        return 1
    fi

    # 检查策略类型是否有效
    if [[ -z "${POLICY_TYPES[${policy_type}]+isset}" ]]; then
        log_error "无效的策略类型: ${policy_type}"
        return 1
    fi

    # 检查策略是否已存在
    if [[ -n "${POLICIES[${policy_id}_name]+isset}" ]]; then
        log_error "策略已存在: ${policy_id}"
        return 1
    fi

    # 存储策略信息
    POLICIES["${policy_id}_type"]="${policy_type}"
    POLICIES["${policy_id}_name"]="${name}"
    POLICIES["${policy_id}_description"]="${description}"
    POLICIES["${policy_id}_created"]=$(date +%s)
    POLICIES["${policy_id}_updated"]=$(date +%s)
    POLICIES["${policy_id}_enabled"]="true"
    POLICIES["${policy_id}_priority"]="50"
    POLICIES["${policy_id}_rules"]=""

    POLICY_STATUS["${policy_id}"]="active"

    log_info "策略已创建: ${policy_id} (${policy_type})"

    # 持久化
    persist_policy "${policy_id}"

    return 0
}

# 添加规则
add_policy_rule() {
    local policy_id="$1"
    local rule_id="$2"
    local condition="$3"
    local action="$4"
    local severity="${5:-warning}"

    if [[ -z "${policy_id}" ]] || [[ -z "${rule_id}" ]] || [[ -z "${condition}" ]] || [[ -z "${action}" ]]; then
        log_error "缺少必需参数: policy_id, rule_id, condition, action"
        return 1
    fi

    # 检查策略是否存在
    if [[ -z "${POLICIES[${policy_id}_name]+isset}" ]]; then
        log_error "策略不存在: ${policy_id}"
        return 1
    fi

    # 存储规则
    local rule_key="${policy_id}:${rule_id}"

    POLICY_RULES["${rule_key}_condition"]="${condition}"
    POLICY_RULES["${rule_key}_action"]="${action}"
    POLICY_RULES["${rule_key}_severity"]="${severity}"
    POLICY_RULES["${rule_key}_enabled"]="true"

    # 更新策略规则列表
    local rules="${POLICIES[${policy_id}_rules]}"
    if [[ -z "${rules}" ]]; then
        rules="${rule_id}"
    else
        rules+=" ${rule_id}"
    fi
    POLICIES["${policy_id}_rules"]="${rules}"

    log_debug "规则已添加: ${rule_key}"

    # 持久化
    persist_policy "${policy_id}"

    return 0
}

# 启用策略
enable_policy() {
    local policy_id="$1"

    if [[ -z "${POLICIES[${policy_id}_name]+isset}" ]]; then
        log_error "策略不存在: ${policy_id}"
        return 1
    fi

    POLICIES["${policy_id}_enabled"]="true"
    POLICY_STATUS["${policy_id}"]="active"

    log_info "策略已启用: ${policy_id}"

    persist_policy "${policy_id}"

    return 0
}

# 禁用策略
disable_policy() {
    local policy_id="$1"

    if [[ -z "${POLICIES[${policy_id}_name]+isset}" ]]; then
        log_error "策略不存在: ${policy_id}"
        return 1
    fi

    POLICIES["${policy_id}_enabled"]="false"
    POLICY_STATUS["${policy_id}"]="inactive"

    log_info "策略已禁用: ${policy_id}"

    persist_policy "${policy_id}"

    return 0
}

# 删除策略
delete_policy() {
    local policy_id="$1"

    if [[ -z "${POLICIES[${policy_id}_name]+isset}" ]]; then
        log_error "策略不存在: ${policy_id}"
        return 1
    fi

    # 删除策略数据
    for key in "${!POLICIES[@]}"; do
        if [[ "${key}" == "${policy_id}_"* ]]; then
            unset POLICIES["${key}"]
        fi
    done

    # 删除规则
    for rule_key in "${!POLICY_RULES[@]}"; do
        if [[ "${rule_key}" == "${policy_id}:"* ]]; then
            unset POLICY_RULES["${rule_key}"]
        fi
    done

    # 删除状态
    unset POLICY_STATUS["${policy_id}"]

    # 删除缓存
    unset POLICY_CACHE["${policy_id}"]

    # 删除持久化文件
    local policy_file="${POLICY_CONFIG[policy_dir]}/${policy_id}.json"
    rm -f "${policy_file}"

    log_info "策略已删除: ${policy_id}"

    return 0
}

# ==============================================================================
# 策略评估
# ==============================================================================
# 评估策略
evaluate_policy() {
    local policy_id="$1"
    local context="$2"

    # 检查策略是否存在
    if [[ -z "${POLICIES[${policy_id}_name]+isset}" ]]; then
        log_error "策略不存在: ${policy_id}"
        return 1
    fi

    # 检查策略是否启用
    if [[ "${POLICIES[${policy_id}_enabled]}" != "true" ]]; then
        log_debug "策略未启用: ${policy_id}"
        return 0
    fi

    # 检查缓存
    if [[ "${POLICY_CONFIG[cache_enabled]}" == "true" ]]; then
        local cached_result=$(get_cached_policy_result "${policy_id}" "${context}")
        if [[ -n "${cached_result}" ]]; then
            echo "${cached_result}"
            return 0
        fi
    fi

    # 评估规则
    local rules="${POLICIES[${policy_id}_rules]}"
    local violations=()
    local actions=()

    for rule_id in ${rules}; do
        local rule_key="${policy_id}:${rule_id}"

        # 检查规则是否启用
        if [[ "${POLICY_RULES[${rule_key}_enabled]}" != "true" ]]; then
            continue
        fi

        local condition="${POLICY_RULES[${rule_key}_condition]}"
        local action="${POLICY_RULES[${rule_key}_action]}"
        local severity="${POLICY_RULES[${rule_key}_severity]}"

        # 评估条件
        if evaluate_condition "${condition}" "${context}"; then
            # 条件满足，记录违规
            violations+=("${rule_key}:${severity}")
            actions+=("${action}")

            # 记录违规
            if [[ "${POLICY_CONFIG[log_violations]}" == "true" ]]; then
                log_policy_violation "${policy_id}" "${rule_id}" "${severity}" "${context}"
            fi
        fi
    done

    # 构建结果
    local result
    if [[ ${#violations[@]} -gt 0 ]]; then
        result="violated"
    else
        result="compliant"
    fi

    local result_json=$(cat <<EOF
{
    "policy_id": "${policy_id}",
    "result": "${result}",
    "violations": [$(IFS=,; echo "${violations[*]}" | sed 's/[^,]*/"&"/g')],
    "actions": [$(IFS=,; echo "${actions[*]}" | sed 's/[^,]*/"&"/g')],
    "evaluated_at": $(date +%s)
}
EOF
)

    # 缓存结果
    if [[ "${POLICY_CONFIG[cache_enabled]}" == "true" ]]; then
        cache_policy_result "${policy_id}" "${context}" "${result_json}"
    fi

    echo "${result_json}"

    # 自动纠正
    if [[ "${result}" == "violated" ]] && [[ "${POLICY_CONFIG[auto_correct]}" == "true" ]]; then
        for action in "${actions[@]}"; do
            execute_policy_action "${action}"
        done
    fi

    return 0
}

# 评估条件
evaluate_condition() {
    local condition="$1"
    local context="$2"

    # 简单条件解析
    # 格式: key operator value
    local key=$(echo "${condition}" | cut -d' ' -f1)
    local operator=$(echo "${condition}" | cut -d' ' -f2)
    local value=$(echo "${condition}" | cut -d' ' -f3-)

    # 从上下文获取值
    local context_value=$(echo "${context}" | jq -r ".${key}" 2>/dev/null)

    if [[ -z "${context_value}" ]]; then
        return 1
    fi

    # 比较值
    case "${operator}" in
        "==")
            [[ "${context_value}" == "${value}" ]]
            ;;
        "!=")
            [[ "${context_value}" != "${value}" ]]
            ;;
        ">")
            [[ "${context_value}" -gt "${value}" ]]
            ;;
        ">=")
            [[ "${context_value}" -ge "${value}" ]]
            ;;
        "<")
            [[ "${context_value}" -lt "${value}" ]]
            ;;
        "<=")
            [[ "${context_value}" -le "${value}" ]]
            ;;
        "contains")
            [[ "${context_value}" == *"${value}"* ]]
            ;;
        "!contains")
            [[ "${context_value}" != *"${value}"* ]]
            ;;
        *)
            log_warning "未知操作符: ${operator}"
            return 1
            ;;
    esac
}

# 执行策略动作
execute_policy_action() {
    local action="$1"

    log_info "执行策略动作: ${action}"

    # 解析动作
    # 格式: type:parameters
    local action_type=$(echo "${action}" | cut -d':' -f1)
    local action_params=$(echo "${action}" | cut -d':' -f2-)

    case "${action_type}" in
        log)
            log_warning "策略违规: ${action_params}"
            ;;
        alert)
            send_alert "${action_params}"
            ;;
        optimize)
            optimize_memory "${action_params:-normal}"
            ;;
        start_zram)
            start_zram
            ;;
        stop_zram)
            stop_zram
            ;;
        start_decision_engine)
            start_decision_engine
            ;;
        stop_decision_engine)
            stop_decision_engine
            ;;
        *)
            log_warning "未知动作类型: ${action_type}"
            ;;
    esac
}

# ==============================================================================
# 批量评估
# ==============================================================================
# 评估所有策略
evaluate_all_policies() {
    local context="$1"
    local policy_type="${2:-}"

    local results=()

    for policy_id in "${!POLICIES[@]}"; do
        if [[ "${policy_id}" == *"_type" ]]; then
            local id="${policy_id%_type}"
            local type="${POLICIES[${policy_id}]}"

            # 检查类型过滤
            if [[ -n "${policy_type}" ]] && [[ "${type}" != "${policy_type}" ]]; then
                continue
            fi

            # 评估策略
            local result=$(evaluate_policy "${id}" "${context}")
            results+=("${result}")
        fi
    done

    # 返回结果
    local results_json=$(cat <<EOF
{
    "policies": [
$(IFS=$'\n'; echo "${results[*]}" | sed 's/^/        /')
    ],
    "evaluated_at": $(date +%s)
}
EOF
)

    echo "${results_json}"
}

# ==============================================================================
# 缓存管理
# ==============================================================================
# 缓存策略结果
cache_policy_result() {
    local policy_id="$1"
    local context="$2"
    local result="$3"

    local cache_key="${policy_id}:$(echo "${context}" | md5sum | cut -d' ' -f1)"
    local cache_time=$(date +%s)
    local ttl="${POLICY_CONFIG[cache_ttl]}"
    local expiry=$((cache_time + ttl))

    POLICY_CACHE["${cache_key}"]="${result}:${expiry}"
}

# 获取缓存结果
get_cached_policy_result() {
    local policy_id="$1"
    local context="$2"

    local cache_key="${policy_id}:$(echo "${context}" | md5sum | cut -d' ' -f1)"
    local cached="${POLICY_CACHE[${cache_key}]:-}"

    if [[ -n "${cached}" ]]; then
        local result="${cached%:*}"
        local expiry="${cached##*:}"
        local current_time=$(date +%s)

        if [[ ${current_time} -lt ${expiry} ]]; then
            echo "${result}"
            return 0
        else
            # 缓存过期
            unset POLICY_CACHE["${cache_key}"]
        fi
    fi

    return 1
}

# 清理过期缓存
cleanup_policy_cache() {
    local current_time=$(date +%s)

    for cache_key in "${!POLICY_CACHE[@]}"; do
        local cached="${POLICY_CACHE[${cache_key}]}"
        local expiry="${cached##*:}"

        if [[ ${current_time} -gt ${expiry} ]]; then
            unset POLICY_CACHE["${cache_key}"]
        fi
    done
}

# ==============================================================================
# 持久化
# ==============================================================================
# 持久化策略
persist_policy() {
    local policy_id="$1"

    local policy_file="${POLICY_CONFIG[policy_dir]}/${policy_id}.json"
    mkdir -p "${POLICY_CONFIG[policy_dir]}"

    local rules="${POLICIES[${policy_id}_rules]}"
    local rules_json=""

    for rule_id in ${rules}; do
        local rule_key="${policy_id}:${rule_id}"
        local condition="${POLICY_RULES[${rule_key}_condition]}"
        local action="${POLICY_RULES[${rule_key}_action]}"
        local severity="${POLICY_RULES[${rule_key}_severity]}"
        local enabled="${POLICY_RULES[${rule_key}_enabled]}"

        rules_json+=$(cat <<RULE
        {
            "rule_id": "${rule_id}",
            "condition": "${condition}",
            "action": "${action}",
            "severity": "${severity}",
            "enabled": ${enabled}
        },
RULE
)
    done

    # 移除最后的逗号
    rules_json="${rules_json%,}"

    cat > "${policy_file}" <<EOF
{
    "policy_id": "${policy_id}",
    "type": "${POLICIES[${policy_id}_type]}",
    "name": "${POLICIES[${policy_id}_name]}",
    "description": "${POLICIES[${policy_id}_description]}",
    "enabled": ${POLICIES[${policy_id}_enabled]},
    "priority": ${POLICIES[${policy_id}_priority]},
    "created": ${POLICIES[${policy_id}_created]},
    "updated": ${POLICIES[${policy_id}_updated]},
    "rules": [
${rules_json}
    ]
}
EOF
}

# 加载策略
load_policy() {
    local policy_file="$1"

    if [[ ! -f "${policy_file}" ]]; then
        log_error "策略文件不存在: ${policy_file}"
        return 1
    fi

    if command -v jq &> /dev/null; then
        local policy_id=$(jq -r '.policy_id' "${policy_file}")
        local policy_type=$(jq -r '.type' "${policy_file}")
        local name=$(jq -r '.name' "${policy_file}")
        local description=$(jq -r '.description' "${policy_file}")
        local enabled=$(jq -r '.enabled' "${policy_file}")
        local priority=$(jq -r '.priority' "${policy_file}")
        local created=$(jq -r '.created' "${policy_file}")
        local updated=$(jq -r '.updated' "${policy_file}")

        # 恢复策略
        POLICIES["${policy_id}_type"]="${policy_type}"
        POLICIES["${policy_id}_name"]="${name}"
        POLICIES["${policy_id}_description"]="${description}"
        POLICIES["${policy_id}_created"]="${created}"
        POLICIES["${policy_id}_updated"]="${updated}"
        POLICIES["${policy_id}_enabled"]="${enabled}"
        POLICIES["${policy_id}_priority"]="${priority}"

        if [[ "${enabled}" == "true" ]]; then
            POLICY_STATUS["${policy_id}"]="active"
        else
            POLICY_STATUS["${policy_id}"]="inactive"
        fi

        # 恢复规则
        local rule_count=$(jq '.rules | length' "${policy_file}")
        local rules=""

        for ((i=0; i<rule_count; i++)); do
            local rule_id=$(jq -r ".rules[${i}].rule_id" "${policy_file}")
            local condition=$(jq -r ".rules[${i}].condition" "${policy_file}")
            local action=$(jq -r ".rules[${i}].action" "${policy_file}")
            local severity=$(jq -r ".rules[${i}].severity" "${policy_file}")
            local rule_enabled=$(jq -r ".rules[${i}].enabled" "${policy_file}")

            local rule_key="${policy_id}:${rule_id}"
            POLICY_RULES["${rule_key}_condition"]="${condition}"
            POLICY_RULES["${rule_key}_action"]="${action}"
            POLICY_RULES["${rule_key}_severity"]="${severity}"
            POLICY_RULES["${rule_key}_enabled"]="${rule_enabled}"

            # 更新规则列表
            if [[ -z "${rules}" ]]; then
                rules="${rule_id}"
            else
                rules+=" ${rule_id}"
            fi
        done

        POLICIES["${policy_id}_rules"]="${rules}"

        log_info "加载策略: ${policy_id}"
        return 0
    fi

    return 1
}

# 加载所有策略
load_all_policies() {
    local policy_dir="${POLICY_CONFIG[policy_dir]}"

    if [[ ! -d "${policy_dir}" ]]; then
        log_info "策略目录不存在: ${policy_dir}"
        return 0
    fi

    for policy_file in "${policy_dir}"/*.json; do
        if [[ -f "${policy_file}" ]]; then
            load_policy "${policy_file}"
        fi
    done
}

# ==============================================================================
# 审计和报告
# ==============================================================================
# 记录策略违规
log_policy_violation() {
    local policy_id="$1"
    local rule_id="$2"
    local severity="$3"
    local context="$4"

    local audit_file="/opt/Z-Panel-Pro/logs/policy_audit.log"
    mkdir -p "/opt/Z-Panel-Pro/logs"

    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    cat >> "${audit_file}" <<EOF
[${timestamp}] POLICY_VIOLATION: policy=${policy_id}, rule=${rule_id}, severity=${severity}, context=${context}
EOF
}

# 生成策略报告
generate_policy_report() {
    local report_file="/opt/Z-Panel-Pro/logs/policy_report_$(date +%Y%m%d_%H%M%S).json"
    mkdir -p "/opt/Z-Panel-Pro/logs"

    local policies_json=""

    for policy_id in "${!POLICIES[@]}"; do
        if [[ "${policy_id}" == *"_type" ]]; then
            local id="${policy_id%_type}"
            local type="${POLICIES[${policy_id}]}"
            local name="${POLICIES[${id}_name]}"
            local enabled="${POLICIES[${id}_enabled]}"
            local status="${POLICY_STATUS[${id}]}"
            local rules="${POLICIES[${id}_rules]}"
            local rule_count=$(echo "${rules}" | wc -w)

            policies_json+=$(cat <<POLICY
    {
        "policy_id": "${id}",
        "type": "${type}",
        "name": "${name}",
        "enabled": ${enabled},
        "status": "${status}",
        "rule_count": ${rule_count}
    },
POLICY
)
        fi
    done

    # 移除最后的逗号
    policies_json="${policies_json%,}"

    cat > "${report_file}" <<EOF
{
    "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "total_policies": $(echo "${policies_json}" | grep -o '"policy_id"' | wc -l),
    "policies": [
${policies_json}
    ]
}
EOF

    echo "${report_file}"
}

# ==============================================================================
# 预定义策略
# ==============================================================================
# 创建默认策略
create_default_policies() {
    # 内存使用策略
    create_policy "memory_high_usage" "memory" "高内存使用" "当内存使用超过80%时触发"
    add_policy_rule "memory_high_usage" "memory_above_80" "memory_percent > 80" "log:Memory usage above 80%" "warning"
    add_policy_rule "memory_high_usage" "memory_above_90" "memory_percent > 90" "optimize:aggressive" "critical"

    # ZRAM使用策略
    create_policy "zram_high_usage" "zram" "高ZRAM使用" "当ZRAM使用超过70%时触发"
    add_policy_rule "zram_high_usage" "zram_above_70" "zram_percent > 70" "log:ZRAM usage above 70%" "warning"
    add_policy_rule "zram_high_usage" "zram_above_90" "zram_percent > 90" "log:ZRAM usage above 90%" "critical"

    # Swap使用策略
    create_policy "swap_active" "swap" "Swap激活" "当Swap被使用时触发"
    add_policy_rule "swap_active" "swap_in_use" "swap_used > 0" "log:Swap is being used" "warning"
    add_policy_rule "swap_active" "swap_high_usage" "swap_percent > 50" "optimize:normal" "critical"

    # 决策引擎策略
    create_policy "decision_engine_required" "decision" "决策引擎必需" "决策引擎必须运行"
    add_policy_rule "decision_engine_required" "de_not_running" "decision_running != true" "start_decision_engine" "critical"

    # 安全策略
    create_policy "security_policy" "security" "安全策略" "系统安全相关策略"
    add_policy_rule "security_policy" "root_login" "root_login_enabled == true" "log:Root login enabled" "warning"

    log_info "默认策略已创建"
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f create_policy
export -f add_policy_rule
export -f enable_policy
export -f disable_policy
export -f delete_policy
export -f evaluate_policy
export -f evaluate_condition
export -f execute_policy_action
export -f evaluate_all_policies
export -f cache_policy_result
export -f get_cached_policy_result
export -f cleanup_policy_cache
export -f persist_policy
export -f load_policy
export -f load_all_policies
export -f log_policy_violation
export -f generate_policy_report
export -f create_default_policies
