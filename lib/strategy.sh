#!/bin/bash
# ==============================================================================
# Z-Panel Pro V9.0 - 策略管理模块
# ==============================================================================
# @description    优化策略配置与计算
# @version       9.0.0-Lightweight
# @author        Z-Panel Team
# @license       MIT License
# ==============================================================================

# ==============================================================================
# 策略配置加载
# ==============================================================================
load_strategy_config() {
    if [[ -f "${STRATEGY_CONFIG_FILE}" ]]; then
        if safe_source "${STRATEGY_CONFIG_FILE}"; then
            log_debug "策略模式: ${STRATEGY_MODE}"
        else
            STRATEGY_MODE="balance"
            log_warn "策略配置加载失败，使用默认值"
        fi
    else
        STRATEGY_MODE="balance"
        log_debug "策略配置文件不存在，使用默认值"
    fi
}

# ==============================================================================
# 策略配置保存
# ==============================================================================
save_strategy_config() {
    local content
    cat <<'EOF'
# ============================================================================
# Z-Panel Pro 策略配置
# ============================================================================
# 自动生成，请勿手动修改
#
# STRATEGY_MODE: 策略模式
#   - conservative: 保守策略，适合稳定性和可靠性优先的场景
#   - balance: 平衡策略，适合大多数通用场景
#   - aggressive: 激进策略，适合性能优先的场景
# ============================================================================

STRATEGY_MODE=${STRATEGY_MODE}
EOF

    if save_config_file "${STRATEGY_CONFIG_FILE}" "${content}"; then
        log_info "策略配置已保存: ${STRATEGY_MODE}"
        return 0
    else
        log_error "策略配置保存失败"
        return 1
    fi
}

# ==============================================================================
# 策略验证
# ==============================================================================
validate_strategy_mode() {
    local mode="$1"

    case "${mode}" in
        ${STRATEGY_CONSERVATIVE}|${STRATEGY_BALANCE}|${STRATEGY_AGGRESSIVE})
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ==============================================================================
# ==============================================================================
# 策略计算
# @param mode: 策略模式 (可选，默认STRATEGY_MODE)
# @return: "zram_ratio phys_limit swap_size swappiness dirty_ratio min_free"
# ==============================================================================
calculate_strategy() {
    local mode="${1:-${STRATEGY_MODE}}"

    # 验证策略模式
    if ! validate_strategy_mode "${mode}"; then
        log_error "无效的策略模式: ${mode}，使用默认策略"
        mode="${STRATEGY_BALANCE}"
    fi

    # 验证系统信息
    local mem_total="${SYSTEM_INFO[total_memory_mb]}"
    if [[ ! "${mem_total}" =~ ^[0-9]+$ ]]; then
        log_error "无效的内存信息: ${mem_total}"
        return 1
    fi

    # 验证内存范围 (64MB-1TB)
    if [[ ${mem_total} -lt 64 ]]; then
        log_warn "内存大小过小，已自动调整为64MB"
        mem_total=64
    elif [[ ${mem_total} -gt 1048576 ]]; then
        log_warn "内存大小过大，已自动调整为1TB"
        mem_total=1048576
    fi

    local zram_ratio phys_limit swap_size swappiness dirty_ratio min_free

    case "${mode}" in
        ${STRATEGY_CONSERVATIVE})
            # 保守策略：稳定性和可靠性优先，适合NAS
            zram_ratio=80
            phys_limit=$((mem_total * 40 / 100)) || true
            swap_size=$((mem_total * 100 / 100)) || true
            swappiness=60
            dirty_ratio=5
            min_free=65536
            ;;
        ${STRATEGY_BALANCE})
            # 平衡策略：性能和稳定性兼顾，适合大多数场景
            zram_ratio=120
            phys_limit=$((mem_total * 50 / 100)) || true
            swap_size=$((mem_total * 150 / 100)) || true
            swappiness=85
            dirty_ratio=10
            min_free=32768
            ;;
        ${STRATEGY_AGGRESSIVE})
            # 激进策略：性能优先，适合高性能要求场景
            zram_ratio=180
            phys_limit=$((mem_total * 65 / 100)) || true
            swap_size=$((mem_total * 200 / 100)) || true
            swappiness=100
            dirty_ratio=15
            min_free=16384
            ;;
    esac

    # 边界检查
    [[ ${zram_ratio} -lt 50 ]] && zram_ratio=50
    [[ ${zram_ratio} -gt 200 ]] && zram_ratio=200
    [[ ${phys_limit} -lt 128 ]] && phys_limit=128
    [[ ${swap_size} -lt 128 ]] && swap_size=128

    echo "${zram_ratio} ${phys_limit} ${swap_size} ${swappiness} ${dirty_ratio} ${min_free}"
}

# ==============================================================================
# 获取策略描述
# @param mode: 策略模式
# @return: 描述文本
# ==============================================================================
get_strategy_description() {
    local mode="${1:-${STRATEGY_MODE}}"

    case "${mode}" in
        ${STRATEGY_CONSERVATIVE})
            echo "保守策略：稳定性和可靠性优先，适合NAS"
            ;;
        ${STRATEGY_BALANCE})
            echo "平衡策略：性能和稳定性兼顾，适合大多数场景"
            ;;
        ${STRATEGY_AGGRESSIVE})
            echo "激进策略：性能优先，适合高性能要求场景"
            ;;
        *)
            echo "未知策略"
            ;;
    esac
}

# ==============================================================================
# 获取策略详情
# @param mode: 策略模式
# @return: 策略详细信息
# ==============================================================================
get_strategy_details() {
    local mode="${1:-${STRATEGY_MODE}}"
    local zram_ratio phys_limit swap_size swappiness dirty_ratio min_free

    read -r zram_ratio phys_limit swap_size swappiness dirty_ratio min_free <<< "$(calculate_strategy "${mode}")"

    cat <<EOF
策略模式: ${mode}
描述: $(get_strategy_description "${mode}")

优化参数:
  ZRAM 比例: ${zram_ratio}% 物理内存
  物理限制: ${phys_limit}MB
  Swap 大小: ${swap_size}MB
  Swappiness: ${swappiness}
  Dirty Ratio: ${dirty_ratio}%
  保留内存: ${min_free}KB

策略说明:
  Conservative: 保守策略，适合NAS等稳定性优先场景
  Balance: 平衡策略，适合大多数通用场景
  Aggressive: 激进策略，适合VPS等性能优先场景
EOF
}

# ==============================================================================
# 设置策略模式
# @param mode: 策略模式
# @return: 0成功，1失败
# ==============================================================================
set_strategy_mode() {
    local mode="$1"

    if ! validate_strategy_mode "${mode}"; then
        log_error "无效的策略模式: ${mode}"
        return 1
    fi

    STRATEGY_MODE="${mode}"
    log_info "策略模式已设置为: ${mode}"

    return 0
}

# ==============================================================================
# 获取当前策略模式
# ==============================================================================
get_strategy_mode() {
    echo "${STRATEGY_MODE}"
}

# ==============================================================================
# 获取可用策略列表
# ==============================================================================
get_available_strategies() {
    echo "${STRATEGY_CONSERVATIVE}"
    echo "${STRATEGY_BALANCE}"
    echo "${STRATEGY_AGGRESSIVE}"
}

# ==============================================================================
# 自适应策略选择（世界顶级标准）
# ==============================================================================

# ==============================================================================
# 自适应策略分析器
# @return: JSON格式的分析结果
# ==============================================================================
analyze_adaptive_strategy() {
    local mem_usage zram_usage swap_usage load_avg
    local mem_pressure=0
    local score_conservative=0
    local score_balance=0
    local score_aggressive=0

    # 获取系统指标
    mem_usage=$(get_memory_usage false)
    if [[ ${?} -ne 0 ]] || [[ -z "${mem_usage}" ]]; then
        log_warn "获取内存使用率失败，使用默认值"
        mem_usage=50
    fi

    zram_usage=$(get_zram_usage_percent)
    if [[ ${?} -ne 0 ]] || [[ -z "${zram_usage}" ]]; then
        log_warn "获取ZRAM使用率失败，使用默认值"
        zram_usage=50
    fi

    swap_usage=$(get_swap_usage false)
    if [[ ${?} -ne 0 ]] || [[ -z "${swap_usage}" ]]; then
        log_warn "获取Swap使用率失败，使用默认值"
        swap_usage=20
    fi

    load_avg=$(awk '{print $1}' /proc/loadavg)
    if [[ ${?} -ne 0 ]] || [[ -z "${load_avg}" ]]; then
        log_warn "获取系统负载失败，使用默认值"
        load_avg=1.0
    fi

    # 边界检查
    [[ ${mem_usage} -lt 0 ]] && mem_usage=0
    [[ ${mem_usage} -gt 100 ]] && mem_usage=100
    [[ ${zram_usage} -lt 0 ]] && zram_usage=0
    [[ ${zram_usage} -gt 100 ]] && zram_usage=100
    [[ ${swap_usage} -lt 0 ]] && swap_usage=0
    [[ ${swap_usage} -gt 100 ]] && swap_usage=100

    # 内存压力分析 (权重: 40%)
    if [[ ${mem_usage} -gt 90 ]]; then
        mem_pressure=100
        ((score_aggressive += 40))
    elif [[ ${mem_usage} -gt 80 ]]; then
        mem_pressure=75
        ((score_aggressive += 30))
        ((score_balance += 10))
    elif [[ ${mem_usage} -gt 70 ]]; then
        mem_pressure=50
        ((score_balance += 25))
        ((score_aggressive += 15))
    elif [[ ${mem_usage} -gt 50 ]]; then
        mem_pressure=25
        ((score_balance += 30))
        ((score_conservative += 10))
    else
        mem_pressure=0
        ((score_conservative += 35))
        ((score_balance += 5))
    fi

    # ZRAM使用率分析 (权重: 25%)
    if [[ ${zram_usage} -gt 90 ]]; then
        ((score_aggressive += 25))
    elif [[ ${zram_usage} -gt 70 ]]; then
        ((score_aggressive += 20))
        ((score_balance += 5))
    elif [[ ${zram_usage} -gt 50 ]]; then
        ((score_balance += 20))
        ((score_aggressive += 5))
    elif [[ ${zram_usage} -gt 30 ]]; then
        ((score_balance += 15))
        ((score_conservative += 10))
    else
        ((score_conservative += 20))
        ((score_balance += 5))
    fi

    # Swap使用率分析 (权重: 20%)
    if [[ ${swap_usage} -gt 80 ]]; then
        ((score_aggressive += 20))
    elif [[ ${swap_usage} -gt 60 ]]; then
        ((score_aggressive += 15))
        ((score_balance += 5))
    elif [[ ${swap_usage} -gt 40 ]]; then
        ((score_balance += 15))
        ((score_aggressive += 5))
    elif [[ ${swap_usage} -gt 20 ]]; then
        ((score_balance += 10))
        ((score_conservative += 10))
    else
        ((score_conservative += 15))
        ((score_balance += 5))
    fi

    # 系统负载分析 (权重: 15%)
    local cpu_cores=${SYSTEM_INFO[cpu_cores]:-1}
    local load_percent=$(echo "${load_avg} ${cpu_cores}" | awk '{printf "%.0f", ($1 / $2) * 100}')

    if [[ ${load_percent} -gt 90 ]]; then
        ((score_aggressive += 15))
    elif [[ ${load_percent} -gt 70 ]]; then
        ((score_aggressive += 10))
        ((score_balance += 5))
    elif [[ ${load_percent} -gt 50 ]]; then
        ((score_balance += 12))
        ((score_aggressive += 3))
    elif [[ ${load_percent} -gt 30 ]]; then
        ((score_balance += 8))
        ((score_conservative += 7))
    else
        ((score_conservative += 12))
        ((score_balance += 3))
    fi

    # 确定推荐策略
    local recommended_strategy="${STRATEGY_BALANCE}"
    local max_score=${score_balance}

    if [[ ${score_aggressive} -gt ${max_score} ]]; then
        max_score=${score_aggressive}
        recommended_strategy="${STRATEGY_AGGRESSIVE}"
    fi

    if [[ ${score_conservative} -gt ${max_score} ]]; then
        recommended_strategy="${STRATEGY_CONSERVATIVE}"
    fi

    # 输出分析结果
    cat <<EOF
{
    "recommended_strategy": "${recommended_strategy}",
    "scores": {
        "conservative": ${score_conservative},
        "balance": ${score_balance},
        "aggressive": ${score_aggressive}
    },
    "metrics": {
        "memory_usage_percent": ${mem_usage},
        "zram_usage_percent": ${zram_usage},
        "swap_usage_percent": ${swap_usage},
        "load_average": ${load_avg},
        "load_percent": ${load_percent},
        "memory_pressure": ${mem_pressure}
    },
    "analysis": {
        "memory_pressure_weight": 40,
        "zram_usage_weight": 25,
        "swap_usage_weight": 20,
        "load_average_weight": 15
    }
}
EOF
}

# ==============================================================================
# 应用自适应策略
# @return: 0成功，1失败
# ==============================================================================
apply_adaptive_strategy() {
    log_info "分析系统状态，选择最优策略..."

    # 获取自适应策略推荐
    local analysis
    analysis=$(analyze_adaptive_strategy)
    if [[ ${?} -ne 0 ]] || [[ -z "${analysis}" ]]; then
        log_error "自适应策略分析失败"
        return 1
    fi

    # 提取推荐策略
    local recommended_strategy
    recommended_strategy=$(echo "${analysis}" | grep -o '"recommended_strategy":"[^"]*"' | cut -d'"' -f4)

    # 验证推荐策略
    if [[ -z "${recommended_strategy}" ]] || ! validate_strategy_mode "${recommended_strategy}"; then
        log_warn "推荐策略无效，使用默认策略"
        recommended_strategy="${STRATEGY_BALANCE}"
    fi

    # 提取分数
    local score_conservative score_balance score_aggressive
    score_conservative=$(echo "${analysis}" | grep -o '"conservative": [0-9]*' | awk '{print $2}')
    score_balance=$(echo "${analysis}" | grep -o '"balance": [0-9]*' | awk '{print $2}')
    score_aggressive=$(echo "${analysis}" | grep -o '"aggressive": [0-9]*' | awk '{print $2}')

    # 验证分数
    [[ -z "${score_conservative}" ]] && score_conservative=0
    [[ -z "${score_balance}" ]] && score_balance=0
    [[ -z "${score_aggressive}" ]] && score_aggressive=0

    log_info "策略评分: Conservative=${score_conservative}, Balance=${score_balance}, Aggressive=${score_aggressive}"
    log_info "推荐策略: ${recommended_strategy}"

    # 设置策略
    if set_strategy_mode "${recommended_strategy}"; then
        log_info "自适应策略已应用: ${recommended_strategy}"
        return 0
    else
        log_error "应用自适应策略失败"
        return 1
    fi
}

# 获取自适应策略报告
get_adaptive_strategy_report() {
    local analysis
    analysis=$(analyze_adaptive_strategy)

    local recommended_strategy
    recommended_strategy=$(echo "${analysis}" | grep -o '"recommended_strategy":"[^"]*"' | cut -d'"' -f4)

    local mem_usage zram_usage swap_usage load_avg
    mem_usage=$(echo "${analysis}" | grep -o '"memory_usage_percent": [0-9]*' | awk '{print $2}')
    zram_usage=$(echo "${analysis}" | grep -o '"zram_usage_percent": [0-9]*' | awk '{print $2}')
    swap_usage=$(echo "${analysis}" | grep -o '"swap_usage_percent": [0-9]*' | awk '{print $2}')
    load_avg=$(echo "${analysis}" | grep -o '"load_average": [0-9.]*' | awk '{print $2}')

    cat <<EOF
自适应策略分析报告
================================================================================

系统状态:
  内存使用率: ${mem_usage}%
  ZRAM使用率: ${zram_usage}%
  Swap使用率: ${swap_usage}%
  系统负载: ${load_avg}

推荐策略: ${recommended_strategy}

策略说明:
  Conservative: 保守策略，适合资源充足、稳定性优先的场景
  Balance: 平衡策略，适合大多数通用场景
  Aggressive: 激进策略，适合资源紧张、性能优先的场景

建议: 根据当前系统状态，推荐使用 ${recommended_strategy} 策略以获得最佳性能

================================================================================
EOF
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f load_strategy_config
export -f save_strategy_config
export -f validate_strategy_mode
export -f calculate_strategy
export -f get_strategy_description
export -f get_strategy_details
export -f set_strategy_mode
export -f get_strategy_mode
export -f get_available_strategies
export -f analyze_adaptive_strategy
export -f apply_adaptive_strategy
export -f get_adaptive_strategy_report
