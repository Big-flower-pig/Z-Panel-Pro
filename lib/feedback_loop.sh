#!/bin/bash
# ==============================================================================
# Z-Panel Pro V8.0 - 反馈循环模块
# ==============================================================================
# @description    评估决策效果，基于反馈调整参数，持续优化模型
# @version       8.0.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 反馈循环配置
# ==============================================================================
declare -gA FEEDBACK_CONFIG=(
    # 评估窗口
    [evaluation_window]="300"       # 评估窗口（秒），5分钟
    [min_sample_size]="10"          # 最小样本数

    # 反馈权重
    [weight_memory]="0.3"           # 内存指标权重
    [weight_swap]="0.2"             # Swap使用权重
    [weight_latency]="0.2"          # 延迟权重
    [weight_stability]="0.3"        # 稳定性权重

    # 学习参数
    [learning_rate]="0.1"           # 学习率
    [momentum]="0.9"                # 动量系数
    [decay_factor]="0.99"           # 衰减因子

    # 阈值
    [good_threshold]="0.7"          # 好的反馈阈值
    [bad_threshold]="0.3"           # 坏的反馈阈值
)

# ==============================================================================
# 决策历史记录
# ==============================================================================
declare -gA FEEDBACK_DECISION_HISTORY=(
    [count]="0"
    [last_decision_id]="0"
)

# 决策记录数组
declare -ga FEEDBACK_DECISIONS=()

# 决策效果记录
declare -gA FEEDBACK_DECISION_EFFECTS=()

# ==============================================================================
# 参数调整历史
# ==============================================================================
declare -gA FEEDBACK_PARAM_ADJUSTMENTS=(
    [count]="0"
)

# 参数调整记录
declare -ga FEEDBACK_ADJUSTMENTS=()

# ==============================================================================
# 模型学习数据
# ==============================================================================
declare -gA FEEDBACK_MODEL=(
    [total_decisions]="0"
    [good_decisions]="0"
    [bad_decisions]="0"
    [average_score]="0"
    [improvement_rate]="0"
)

# 特征权重（用于决策）
declare -gA FEEDBACK_FEATURE_WEIGHTS=(
    [memory_pressure]="0.25"
    [swap_usage]="0.20"
    [system_load]="0.15"
    [io_wait]="0.10"
    [cache_hit_rate]="0.15"
    [prediction_accuracy]="0.15"
)

# ==============================================================================
# 反馈数据存储
# ==============================================================================
declare -gA FEEDBACK_DATA=(
    [memory_before]=""
    [memory_after]=""
    [swap_before]=""
    [swap_after]=""
    [latency_before]=""
    [latency_after]=""
    [stability_score]=""
)

# ==============================================================================
# 决策记录管理
# ==============================================================================

# 创建新决策记录
# @param decision_type: 决策类型
# @param decision_details: 决策详情
# @return: 决策ID
create_decision_record() {
    local decision_type="$1"
    local decision_details="$2"

    local decision_id=$((FEEDBACK_DECISION_HISTORY[last_decision_id] + 1))
    local timestamp=$(date +%s)

    # 创建决策记录
    local record="${decision_id}|${timestamp}|${decision_type}|${decision_details}"
    FEEDBACK_DECISIONS+=("${record}")

    # 更新历史
    ((FEEDBACK_DECISION_HISTORY[last_decision_id]++))
    ((FEEDBACK_DECISION_HISTORY[count]++))
    ((FEEDBACK_MODEL[total_decisions]++))

    log_debug "创建决策记录: ID=${decision_id}, 类型=${decision_type}"
    echo "${decision_id}"
    return 0
}

# 记录决策前的状态
# @param decision_id: 决策ID
# @param state: 状态数据（JSON格式）
record_before_state() {
    local decision_id="$1"
    local state="$2"

    FEEDBACK_DECISION_EFFECTS["${decision_id}_before"]="${state}"

    log_debug "记录决策前状态: ID=${decision_id}"
    return 0
}

# 记录决策后的状态
# @param decision_id: 决策ID
# @param state: 状态数据（JSON格式）
record_after_state() {
    local decision_id="$1"
    local state="$2"

    FEEDBACK_DECISION_EFFECTS["${decision_id}_after"]="${state}"

    log_debug "记录决策后状态: ID=${decision_id}"
    return 0
}

# ==============================================================================
# 效果评估
# ==============================================================================

# 评估决策效果
# @param decision_id: 决策ID
# @return: 反馈分数（0-1）
evaluate_decision_effect() {
    local decision_id="$1"

    local before_state="${FEEDBACK_DECISION_EFFECTS[${decision_id}_before]}"
    local after_state="${FEEDBACK_DECISION_EFFECTS[${decision_id}_after]}"

    [[ -z "${before_state}" ]] || [[ -z "${after_state}" ]] && {
        log_warn "无法评估决策效果: 缺少状态数据"
        return 1
    }

    # 解析状态数据
    local mem_before=$(echo "${before_state}" | grep -o '"memory_percent":[0-9.]*' | cut -d: -f2)
    local mem_after=$(echo "${after_state}" | grep -o '"memory_percent":[0-9.]*' | cut -d: -f2)
    local swap_before=$(echo "${before_state}" | grep -o '"swap_percent":[0-9.]*' | cut -d: -f2)
    local swap_after=$(echo "${after_state}" | grep -o '"swap_percent":[0-9.]*' | cut -d: -f2)

    # 计算内存改善分数
    local mem_score
    if [[ -n "${mem_before}" ]] && [[ -n "${mem_after}" ]]; then
        local mem_diff=$(echo "${mem_before} - ${mem_after}" | bc -l 2>/dev/null || echo "0")
        mem_score=$(echo "scale=3; (${mem_diff} / 100) + 0.5" | bc -l 2>/dev/null || echo "0.5")
        # 限制范围
        mem_score=$(echo "if (${mem_score} < 0) 0; if (${mem_score} > 1) 1; ${mem_score}" | bc -l 2>/dev/null || echo "0.5")
    else
        mem_score="0.5"
    fi

    # 计算Swap改善分数
    local swap_score
    if [[ -n "${swap_before}" ]] && [[ -n "${swap_after}" ]]; then
        local swap_diff=$(echo "${swap_before} - ${swap_after}" | bc -l 2>/dev/null || echo "0")
        swap_score=$(echo "scale=3; (${swap_diff} / 100) + 0.5" | bc -l 2>/dev/null || echo "0.5")
        swap_score=$(echo "if (${swap_score} < 0) 0; if (${swap_score} > 1) 1; ${swap_score}" | bc -l 2>/dev/null || echo "0.5")
    else
        swap_score="0.5"
    fi

    # 加权计算总分
    local weight_memory="${FEEDBACK_CONFIG[weight_memory]}"
    local weight_swap="${FEEDBACK_CONFIG[weight_swap]}"

    local total_score
    total_score=$(echo "scale=3; ${mem_score} * ${weight_memory} + ${swap_score} * ${weight_swap}" | bc -l 2>/dev/null || echo "0.5")

    # 更新模型统计
    local is_good
    is_good=$(echo "${total_score} >= ${FEEDBACK_CONFIG[good_threshold]}" | bc -l 2>/dev/null || echo "0")
    local is_bad
    is_bad=$(echo "${total_score} <= ${FEEDBACK_CONFIG[bad_threshold]}" | bc -l 2>/dev/null || echo "0")

    if [[ "${is_good}" == "1" ]]; then
        ((FEEDBACK_MODEL[good_decisions]++))
    elif [[ "${is_bad}" == "1" ]]; then
        ((FEEDBACK_MODEL[bad_decisions]++))
    fi

    # 更新平均分数
    local avg="${FEEDBACK_MODEL[average_score]}"
    local total="${FEEDBACK_MODEL[total_decisions]}"
    FEEDBACK_MODEL[average_score]=$(echo "scale=3; (${avg} * (${total} - 1) + ${total_score}) / ${total}" | bc -l 2>/dev/null || echo "${total_score}")

    # 记录效果
    FEEDBACK_DECISION_EFFECTS["${decision_id}_score"]="${total_score}"
    FEEDBACK_DECISION_EFFECTS["${decision_id}_evaluated"]="1"

    log_debug "决策效果评估: ID=${decision_id}, 分数=${total_score}"
    echo "${total_score}"
    return 0
}

# 批量评估决策效果
# @param window: 评估窗口（秒）
evaluate_recent_decisions() {
    local window="${1:-${FEEDBACK_CONFIG[evaluation_window]}}"
    local current_time=$(date +%s)
    local cutoff_time=$((current_time - window))

    local evaluated_count=0
    local total_score=0

    # 遍历决策记录
    for record in "${FEEDBACK_DECISIONS[@]}"; do
        local decision_id=$(echo "${record}" | cut -d'|' -f1)
        local timestamp=$(echo "${record}" | cut -d'|' -f2)
        local evaluated="${FEEDBACK_DECISION_EFFECTS[${decision_id}_evaluated]:-0}"

        # 跳过已评估或超出窗口的决策
        [[ "${evaluated}" == "1" ]] && continue
        [[ ${timestamp} -lt ${cutoff_time} ]] && continue

        # 评估决策
        local score=$(evaluate_decision_effect "${decision_id}")
        [[ -n "${score}" ]] && {
            total_score=$(echo "${total_score} + ${score}" | bc -l 2>/dev/null || echo "${total_score}")
            ((evaluated_count++))
        }
    done

    # 计算平均分数
    local avg_score="0"
    [[ ${evaluated_count} -gt 0 ]] && {
        avg_score=$(echo "scale=3; ${total_score} / ${evaluated_count}" | bc -l 2>/dev/null || echo "0")
    }

    log_info "批量评估完成: ${evaluated_count}个决策, 平均分数=${avg_score}"
    echo "${avg_score}"
    return 0
}

# ==============================================================================
# 参数调整
# ==============================================================================

# 根据反馈调整参数
# @param param_name: 参数名称
# @param feedback_score: 反馈分数（0-1）
# @param direction: 调整方向（increase/decrease/auto）
adjust_parameter() {
    local param_name="$1"
    local feedback_score="${2:-0.5}"
    local direction="${3:-auto}"

    # 确定调整方向
    if [[ "${direction}" == "auto" ]]; then
        if (( $(echo "${feedback_score} > 0.5" | bc -l 2>/dev/null || echo "0") )); then
            direction="increase"
        else
            direction="decrease"
        fi
    fi

    # 计算调整幅度
    local learning_rate="${FEEDBACK_CONFIG[learning_rate]}"
    local adjustment
    adjustment=$(echo "scale=4; ${learning_rate} * ${feedback_score}" | bc -l 2>/dev/null || echo "0")

    # 获取当前参数值
    local current_value
    case "${param_name}" in
        swappiness)
            current_value=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "60")
            ;;
        zram_compression)
            current_value="${CONFIG[zram_compression]:-lzo}"
            ;;
        cache_ttl)
            current_value="${CACHE_MANAGER[lru_default_ttl]:-60}"
            ;;
        *)
            log_warn "未知参数: ${param_name}"
            return 1
            ;;
    esac

    # 计算新值
    local new_value
    case "${param_name}" in
        swappiness)
            if [[ "${direction}" == "increase" ]]; then
                new_value=$(echo "scale=0; ${current_value} + (${adjustment} * 20)" | bc -l 2>/dev/null || echo "${current_value}")
            else
                new_value=$(echo "scale=0; ${current_value} - (${adjustment} * 20)" | bc -l 2>/dev/null || echo "${current_value}")
            fi
            # 限制范围
            new_value=$(echo "if (${new_value} < 0) 0; if (${new_value} > 100) 100; ${new_value}" | bc -l 2>/dev/null || echo "${current_value}")
            ;;
        cache_ttl)
            if [[ "${direction}" == "increase" ]]; then
                new_value=$(echo "scale=0; ${current_value} + (${adjustment} * 30)" | bc -l 2>/dev/null || echo "${current_value}")
            else
                new_value=$(echo "scale=0; ${current_value} - (${adjustment} * 30)" | bc -l 2>/dev/null || echo "${current_value}")
            fi
            # 限制范围
            new_value=$(echo "if (${new_value} < 10) 10; if (${new_value} > 600) 600; ${new_value}" | bc -l 2>/dev/null || echo "${current_value}")
            CACHE_MANAGER[lru_default_ttl]="${new_value}"
            ;;
    esac

    # 记录调整
    local timestamp=$(date +%s)
    local adjustment_record="${timestamp}|${param_name}|${current_value}|${new_value}|${feedback_score}|${direction}"
    FEEDBACK_ADJUSTMENTS+=("${adjustment_record}")
    ((FEEDBACK_PARAM_ADJUSTMENTS[count]++))

    log_info "参数调整: ${param_name} ${current_value} -> ${new_value} (反馈分数: ${feedback_score})"
    echo "${new_value}"
    return 0
}

# 调整特征权重
# @param feature_name: 特征名称
# @param feedback_score: 反馈分数
adjust_feature_weight() {
    local feature_name="$1"
    local feedback_score="${2:-0.5}"

    # 检查特征是否存在
    [[ -z "${FEEDBACK_FEATURE_WEIGHTS[${feature_name}]}" ]] && {
        log_warn "未知特征: ${feature_name}"
        return 1
    }

    local current_weight="${FEEDBACK_FEATURE_WEIGHTS[${feature_name}]}"
    local learning_rate="${FEEDBACK_CONFIG[learning_rate]}"

    # 计算新权重
    local delta
    delta=$(echo "scale=4; ${learning_rate} * (${feedback_score} - 0.5)" | bc -l 2>/dev/null || echo "0")

    local new_weight
    new_weight=$(echo "scale=4; ${current_weight} + ${delta}" | bc -l 2>/dev/null || echo "${current_weight}")

    # 限制范围
    new_weight=$(echo "if (${new_weight} < 0.05) 0.05; if (${new_weight} > 0.5) 0.5; ${new_weight}" | bc -l 2>/dev/null || echo "${current_weight}")

    # 归一化权重
    local total_weight=0
    for f in "${!FEEDBACK_FEATURE_WEIGHTS[@]}"; do
        total_weight=$(echo "${total_weight} + ${FEEDBACK_FEATURE_WEIGHTS[${f}]}" | bc -l 2>/dev/null || echo "0")
    done

    # 更新权重
    FEEDBACK_FEATURE_WEIGHTS["${feature_name}"]="${new_weight}"

    log_debug "特征权重调整: ${feature_name} ${current_weight} -> ${new_weight}"
    return 0
}

# ==============================================================================
# 模型学习
# ==============================================================================

# 从历史决策学习
learn_from_history() {
    local window="${1:-3600}"  # 默认1小时
    local current_time=$(date +%s)
    local cutoff_time=$((current_time - window))

    local good_count=0
    local bad_count=0
    declare -A feature_scores

    # 分析历史决策
    for record in "${FEEDBACK_DECISIONS[@]}"; do
        local decision_id=$(echo "${record}" | cut -d'|' -f1)
        local timestamp=$(echo "${record}" | cut -d'|' -f2)
        local score="${FEEDBACK_DECISION_EFFECTS[${decision_id}_score]:-}"

        [[ -z "${score}" ]] && continue
        [[ ${timestamp} -lt ${cutoff_time} ]] && continue

        # 统计好坏决策
        if (( $(echo "${score} >= ${FEEDBACK_CONFIG[good_threshold]}" | bc -l 2>/dev/null || echo "0") )); then
            ((good_count++))
        elif (( $(echo "${score} <= ${FEEDBACK_CONFIG[bad_threshold]}" | bc -l 2>/dev/null || echo "0") )); then
            ((bad_count++))
        fi
    done

    # 计算改进率
    local total_decisions=$((good_count + bad_count))
    local improvement_rate="0"
    [[ ${total_decisions} -gt 0 ]] && {
        improvement_rate=$(echo "scale=3; ${good_count} / ${total_decisions}" | bc -l 2>/dev/null || echo "0")
    }

    FEEDBACK_MODEL[improvement_rate]="${improvement_rate}"

    log_debug "模型学习: 好决策=${good_count}, 坏决策=${bad_count}, 改进率=${improvement_rate}"
    return 0
}

# 应用衰减因子
apply_decay() {
    local decay_factor="${FEEDBACK_CONFIG[decay_factor]}"

    # 衰减决策影响
    for key in "${!FEEDBACK_DECISION_EFFECTS[@]}"; do
        [[ "${key}" != *"_score" ]] && continue
        local score="${FEEDBACK_DECISION_EFFECTS[${key}]}"
        local new_score
        new_score=$(echo "scale=3; ${score} * ${decay_factor}" | bc -l 2>/dev/null || echo "${score}")
        FEEDBACK_DECISION_EFFECTS[${key}]="${new_score}"
    done

    log_debug "应用衰减因子: ${decay_factor}"
    return 0
}

# 获取推荐调整
get_recommended_adjustments() {
    local recommendations=()

    # 分析最近的反馈
    local recent_score=$(evaluate_recent_decisions "${FEEDBACK_CONFIG[evaluation_window]}")

    # 根据分数推荐调整
    if (( $(echo "${recent_score} < ${FEEDBACK_CONFIG[bad_threshold]}" | bc -l 2>/dev/null || echo "0") )); then
        recommendations+=("需要更激进的优化策略")
        recommendations+=("建议降低swappiness以减少swap使用")
        recommendations+=("建议增加缓存TTL以减少I/O")
    elif (( $(echo "${recent_score} > ${FEEDBACK_CONFIG[good_threshold]}" | bc -l 2>/dev/null || echo "0") )); then
        recommendations+=("当前策略效果良好")
        recommendations+=("可以适当放宽限制以获得更好性能")
    else
        recommendations+=("当前策略效果一般")
        recommendations+=("建议继续监控并微调参数")
    fi

    printf '%s\n' "${recommendations[@]}"
    return 0
}

# ==============================================================================
# 统计和报告
# ==============================================================================

# 获取反馈循环统计
get_feedback_stats() {
    local uptime=$(( $(date +%s) - FEEDBACK_MODEL[start_time]:-$(date +%s) ))

    cat <<EOF
{
    "decisions": {
        "total": ${FEEDBACK_MODEL[total_decisions]},
        "good": ${FEEDBACK_MODEL[good_decisions]},
        "bad": ${FEEDBACK_MODEL[bad_decisions]},
        "average_score": ${FEEDBACK_MODEL[average_score]},
        "improvement_rate": ${FEEDBACK_MODEL[improvement_rate]}
    },
    "adjustments": {
        "count": ${FEEDBACK_PARAM_ADJUSTMENTS[count]}
    },
    "feature_weights": {
        "memory_pressure": ${FEEDBACK_FEATURE_WEIGHTS[memory_pressure]},
        "swap_usage": ${FEEDBACK_FEATURE_WEIGHTS[swap_usage]},
        "system_load": ${FEEDBACK_FEATURE_WEIGHTS[system_load]},
        "io_wait": ${FEEDBACK_FEATURE_WEIGHTS[io_wait]},
        "cache_hit_rate": ${FEEDBACK_FEATURE_WEIGHTS[cache_hit_rate]},
        "prediction_accuracy": ${FEEDBACK_FEATURE_WEIGHTS[prediction_accuracy]}
    },
    "config": {
        "evaluation_window": ${FEEDBACK_CONFIG[evaluation_window]},
        "learning_rate": ${FEEDBACK_CONFIG[learning_rate]},
        "good_threshold": ${FEEDBACK_CONFIG[good_threshold]},
        "bad_threshold": ${FEEDBACK_CONFIG[bad_threshold]}
    }
}
EOF
}

# 导出反馈历史
export_feedback_history() {
    local output_file="$1"

    {
        echo "# Decision History"
        for record in "${FEEDBACK_DECISIONS[@]}"; do
            echo "${record}"
        done

        echo -e "\n# Decision Effects"
        for key in "${!FEEDBACK_DECISION_EFFECTS[@]}"; do
            echo "${key}=${FEEDBACK_DECISION_EFFECTS[${key}]}"
        done

        echo -e "\n# Parameter Adjustments"
        for adjustment in "${FEEDBACK_ADJUSTMENTS[@]}"; do
            echo "${adjustment}"
        done
    } > "${output_file}" 2>/dev/null || return 1

    log_info "反馈历史已导出: ${output_file}"
    return 0
}

# ==============================================================================
# 初始化和清理
# ==============================================================================

# 初始化反馈循环模块
init_feedback_loop() {
    log_debug "初始化反馈循环模块..."

    # 创建数据目录
    mkdir -p "${CONF_DIR}/feedback" 2>/dev/null || true

    # 加载历史数据
    local history_file="${CONF_DIR}/feedback/history"
    if [[ -f "${history_file}" ]]; then
        load_feedback_history "${history_file}"
    fi

    log_debug "反馈循环模块初始化完成"
    return 0
}

# 清理反馈循环模块
cleanup_feedback_loop() {
    log_debug "清理反馈循环模块..."

    # 保存历史数据
    local history_file="${CONF_DIR}/feedback/history"
    export_feedback_history "${history_file}"

    # 应用衰减
    apply_decay

    log_debug "反馈循环模块清理完成"
    return 0
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f create_decision_record
export -f record_before_state
export -f record_after_state
export -f evaluate_decision_effect
export -f evaluate_recent_decisions
export -f adjust_parameter
export -f adjust_feature_weight
export -f learn_from_history
export -f get_feedback_stats
export -f get_recommended_adjustments
