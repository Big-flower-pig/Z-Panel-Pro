#!/bin/bash
# ==============================================================================
# Z-Panel Pro - ??????
# ==============================================================================
# @description    ?????????
# @version       7.1.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# ??????
# ==============================================================================
declare -gr STRATEGY_CONSERVATIVE="conservative"
declare -gr STRATEGY_BALANCE="balance"
declare -gr STRATEGY_AGGRESSIVE="aggressive"

# ==============================================================================
# ??????
# ==============================================================================
load_strategy_config() {
    if [[ -f "${STRATEGY_CONFIG_FILE}" ]]; then
        if safe_source "${STRATEGY_CONFIG_FILE}"; then
            log_debug "???????: ${STRATEGY_MODE}"
        else
            STRATEGY_MODE="balance"
            log_warn "???????????????"
        fi
    else
        STRATEGY_MODE="balance"
        log_debug "????????????????"
    fi
}

# ==============================================================================
# ??????
# ==============================================================================
save_strategy_config() {
    local content
    cat <<'EOF'
# ============================================================================
# Z-Panel Pro ????
# ============================================================================
# ???????????
#
# STRATEGY_MODE: ??????
#   - conservative: ??????????
#   - balance: ????????????????
#   - aggressive: ????????????
# ============================================================================

STRATEGY_MODE=${STRATEGY_MODE}
EOF

    if save_config_file "${STRATEGY_CONFIG_FILE}" "${content}"; then
        log_info "???????: ${STRATEGY_MODE}"
        return 0
    else
        log_error "????????"
        return 1
    fi
}

# ==============================================================================
# ??????
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
# ??????
# @param mode: ??????????STRATEGY_MODE?
# @return: "zram_ratio phys_limit swap_size swappiness dirty_ratio min_free"
# ==============================================================================
calculate_strategy() {
    local mode="${1:-${STRATEGY_MODE}}"

    if ! validate_strategy_mode "${mode}"; then
        log_error "???????: ${mode}"
        return 1
    fi

    local zram_ratio phys_limit swap_size swappiness dirty_ratio min_free

    case "${mode}" in
        ${STRATEGY_CONSERVATIVE})
            # ???????????????NAS
            zram_ratio=80
            phys_limit=$((SYSTEM_INFO[total_memory_mb] * 40 / 100)) || true
            swap_size=$((SYSTEM_INFO[total_memory_mb] * 100 / 100)) || true
            swappiness=60
            dirty_ratio=5
            min_free=65536
            ;;
        ${STRATEGY_BALANCE})
            # ?????????????????????
            zram_ratio=120
            phys_limit=$((SYSTEM_INFO[total_memory_mb] * 50 / 100)) || true
            swap_size=$((SYSTEM_INFO[total_memory_mb] * 150 / 100)) || true
            swappiness=85
            dirty_ratio=10
            min_free=32768
            ;;
        ${STRATEGY_AGGRESSIVE})
            # ???????????????????
            zram_ratio=180
            phys_limit=$((SYSTEM_INFO[total_memory_mb] * 65 / 100)) || true
            swap_size=$((SYSTEM_INFO[total_memory_mb] * 200 / 100)) || true
            swappiness=100
            dirty_ratio=15
            min_free=16384
            ;;
    esac

    # ?????
    [[ ${zram_ratio} -lt 50 ]] && zram_ratio=50
    [[ ${phys_limit} -lt 128 ]] && phys_limit=128
    [[ ${swap_size} -lt 128 ]] && swap_size=128

    echo "${zram_ratio} ${phys_limit} ${swap_size} ${swappiness} ${dirty_ratio} ${min_free}"
}

# ==============================================================================
# ??????
# @param mode: ????
# @return: ????
# ==============================================================================
get_strategy_description() {
    local mode="${1:-${STRATEGY_MODE}}"

    case "${mode}" in
        ${STRATEGY_CONSERVATIVE})
            echo "???????????????NAS"
            ;;
        ${STRATEGY_BALANCE})
            echo "?????????????????????"
            ;;
        ${STRATEGY_AGGRESSIVE})
            echo "???????????????????"
            ;;
        *)
            echo "????"
            ;;
    esac
}

# ==============================================================================
# ??????
# @param mode: ????
# @return: ????????
# ==============================================================================
get_strategy_details() {
    local mode="${1:-${STRATEGY_MODE}}"
    local zram_ratio phys_limit swap_size swappiness dirty_ratio min_free

    read -r zram_ratio phys_limit swap_size swappiness dirty_ratio min_free <<< "$(calculate_strategy "${mode}")"

    cat <<EOF
????: ${mode}
??: $(get_strategy_description "${mode}")

????:
  ZRAM ??: ${zram_ratio}% ????
  ??????: ${phys_limit}MB
  Swap ??: ${swap_size}MB
  Swappiness: ${swappiness}
  Dirty Ratio: ${dirty_ratio}%
  ??????: ${min_free}KB

????:
  Conservative: ????NAS??????
  Balance: ???????????
  Aggressive: ???VPS?????
EOF
}

# ==============================================================================
# ??????
# @param mode: ??????
# @return: 0????1???
# ==============================================================================
set_strategy_mode() {
    local mode="$1"

    if ! validate_strategy_mode "${mode}"; then
        log_error "???????: ${mode}"
        return 1
    fi

    STRATEGY_MODE="${mode}"
    log_info "????????: ${mode}"

    return 0
}

# ==============================================================================
# ????????
# ==============================================================================
get_strategy_mode() {
    echo "${STRATEGY_MODE}"
}

# ==============================================================================
# ??????????
# ==============================================================================
get_available_strategies() {
    echo "${STRATEGY_CONSERVATIVE}"
    echo "${STRATEGY_BALANCE}"
    echo "${STRATEGY_AGGRESSIVE}"
}
