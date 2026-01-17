#!/bin/bash
# ==============================================================================
# Z-Panel Pro - 策略引擎模块
# ==============================================================================
# @description    优化策略计算与管理
# @version       7.1.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 策略模式定义
# ==============================================================================
declare -gr STRATEGY_CONSERVATIVE="conservative"
declare -gr STRATEGY_BALANCE="balance"
declare -gr STRATEGY_AGGRESSIVE="aggressive"

# ==============================================================================
# 加载策略配置
# ==============================================================================
load_strategy_config() {
    if [[ -f "${STRATEGY_CONFIG_FILE}" ]]; then
        if safe_source "${STRATEGY_CONFIG_FILE}"; then
            log_debug "策略配置已加载: ${STRATEGY_MODE}"
        else
            STRATEGY_MODE="balance"
            log_warn "策略配置加载失败，使用默认策略"
        fi
    else
        STRATEGY_MODE="balance"
        log_debug "策略配置文件不存在，使用默认策略"
    fi
}

# ==============================================================================
# 保存策略配置
# ==============================================================================
save_strategy_config() {
    local content
    cat <<'EOF'
# ============================================================================
# Z-Panel Pro 策略配置
# ============================================================================
# 自动生成，请勿手动修改
#
# STRATEGY_MODE: 优化策略模式
#   - conservative: 保守模式，优先稳定
#   - balance: 平衡模式，性能与稳定兼顾（推荐）
#   - aggressive: 激进模式，最大化使用内存
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
# 验证策略模式
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
# 计算策略参数
# @param mode: 策略模式（默认为当前STRATEGY_MODE）
# @return: "zram_ratio phys_limit swap_size swappiness dirty_ratio min_free"
# ==============================================================================
calculate_strategy() {
    local mode="${1:-${STRATEGY_MODE}}"

    if ! validate_strategy_mode "${mode}"; then
        log_error "未知的策略模式: ${mode}"
        return 1
    fi

    local zram_ratio phys_limit swap_size swappiness dirty_ratio min_free

    case "${mode}" in
        ${STRATEGY_CONSERVATIVE})
            # 保守模式：最稳定，适合路由器/NAS
            zram_ratio=80
            phys_limit=$((SYSTEM_INFO[total_memory_mb] * 40 / 100)) || true
            swap_size=$((SYSTEM_INFO[total_memory_mb] * 100 / 100)) || true
            swappiness=60
            dirty_ratio=5
            min_free=65536
            ;;
        ${STRATEGY_BALANCE})
            # 平衡模式：性能与稳定兼顾，日常使用（推荐）
            zram_ratio=120
            phys_limit=$((SYSTEM_INFO[total_memory_mb] * 50 / 100)) || true
            swap_size=$((SYSTEM_INFO[total_memory_mb] * 150 / 100)) || true
            swappiness=85
            dirty_ratio=10
            min_free=32768
            ;;
        ${STRATEGY_AGGRESSIVE})
            # 激进模式：极限榨干内存，适合极度缺内存
            zram_ratio=180
            phys_limit=$((SYSTEM_INFO[total_memory_mb] * 65 / 100)) || true
            swap_size=$((SYSTEM_INFO[total_memory_mb] * 200 / 100)) || true
            swappiness=100
            dirty_ratio=15
            min_free=16384
            ;;
    esac

    # 确保最小值
    [[ ${zram_ratio} -lt 50 ]] && zram_ratio=50
    [[ ${phys_limit} -lt 128 ]] && phys_limit=128
    [[ ${swap_size} -lt 128 ]] && swap_size=128

    echo "${zram_ratio} ${phys_limit} ${swap_size} ${swappiness} ${dirty_ratio} ${min_free}"
}

# ==============================================================================
# 获取策略描述
# @param mode: 策略模式
# @return: 策略描述
# ==============================================================================
get_strategy_description() {
    local mode="${1:-${STRATEGY_MODE}}"

    case "${mode}" in
        ${STRATEGY_CONSERVATIVE})
            echo "保守模式：最稳定，适合路由器/NAS"
            ;;
        ${STRATEGY_BALANCE})
            echo "平衡模式：性能与稳定兼顾，日常使用（推荐）"
            ;;
        ${STRATEGY_AGGRESSIVE})
            echo "激进模式：极限榨干内存，适合极度缺内存"
            ;;
        *)
            echo "未知模式"
            ;;
    esac
}

# ==============================================================================
# 获取策略详情
# @param mode: 策略模式
# @return: 格式化的策略详情
# ==============================================================================
get_strategy_details() {
    local mode="${1:-${STRATEGY_MODE}}"
    local zram_ratio phys_limit swap_size swappiness dirty_ratio min_free

    read -r zram_ratio phys_limit swap_size swappiness dirty_ratio min_free <<< "$(calculate_strategy "${mode}")"

    cat <<EOF
策略模式: ${mode}
描述: $(get_strategy_description "${mode}")

参数配置:
  ZRAM 大小: ${zram_ratio}% 物理内存
  物理内存限制: ${phys_limit}MB
  Swap 大小: ${swap_size}MB
  Swappiness: ${swappiness}
  Dirty Ratio: ${dirty_ratio}%
  最小空闲内存: ${min_free}KB

适用场景:
  Conservative: 路由器、NAS、嵌入式设备
  Balance: 桌面、服务器、日常使用
  Aggressive: 低内存VPS、开发环境
EOF
}

# ==============================================================================
# 设置策略模式
# @param mode: 新的策略模式
# @return: 0为成功，1为失败
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
# 获取所有策略模式列表
# ==============================================================================
get_available_strategies() {
    echo "${STRATEGY_CONSERVATIVE}"
    echo "${STRATEGY_BALANCE}"
    echo "${STRATEGY_AGGRESSIVE}"
}