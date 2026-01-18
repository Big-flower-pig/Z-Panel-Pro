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
# 策略常量
# ==============================================================================
declare -gr STRATEGY_CONSERVATIVE="conservative"
declare -gr STRATEGY_BALANCE="balance"
declare -gr STRATEGY_AGGRESSIVE="aggressive"

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
# 策略计算
# @param mode: 策略模式，默认使用STRATEGY_MODE
# @return: "zram_ratio phys_limit swap_size swappiness dirty_ratio min_free"
# ==============================================================================
calculate_strategy() {
    local mode="${1:-${STRATEGY_MODE}}"

    if ! validate_strategy_mode "${mode}"; then
        log_error "无效的策略模式: ${mode}"
        return 1
    fi

    local zram_ratio phys_limit swap_size swappiness dirty_ratio min_free

    case "${mode}" in
        ${STRATEGY_CONSERVATIVE})
            # 保守策略：稳定性和可靠性优先，适合NAS
            zram_ratio=80
            phys_limit=$((SYSTEM_INFO[total_memory_mb] * 40 / 100)) || true
            swap_size=$((SYSTEM_INFO[total_memory_mb] * 100 / 100)) || true
            swappiness=60
            dirty_ratio=5
            min_free=65536
            ;;
        ${STRATEGY_BALANCE})
            # 平衡策略：性能和稳定性兼顾，适合大多数场景
            zram_ratio=120
            phys_limit=$((SYSTEM_INFO[total_memory_mb] * 50 / 100)) || true
            swap_size=$((SYSTEM_INFO[total_memory_mb] * 150 / 100)) || true
            swappiness=85
            dirty_ratio=10
            min_free=32768
            ;;
        ${STRATEGY_AGGRESSIVE})
            # 激进策略：性能优先，适合高性能要求场景
            zram_ratio=180
            phys_limit=$((SYSTEM_INFO[total_memory_mb] * 65 / 100)) || true
            swap_size=$((SYSTEM_INFO[total_memory_mb] * 200 / 100)) || true
            swappiness=100
            dirty_ratio=15
            min_free=16384
            ;;
    esac

    # 边界检查
    [[ ${zram_ratio} -lt 50 ]] && zram_ratio=50
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
