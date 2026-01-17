#!/bin/bash
# ==============================================================================
# Z-Panel Pro - Swap??????
# ==============================================================================
# @description    ??Swap????
# @version       7.1.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# ??Swap????
# @return: "total_mb used_mb"
# ==============================================================================
get_swap_file_info() {
    if [[ ! -f "${SWAP_FILE_PATH}" ]]; then
        echo "0 0"
        return
    fi

    if ! swapon --show=NAME --noheadings 2>/dev/null | grep -q "${SWAP_FILE_PATH}"; then
        echo "0 0"
        return
    fi

    local swap_info
    swap_info=$(swapon --show=SIZE,USED --noheadings 2>/dev/null | grep "${SWAP_FILE_PATH}" | head -1)

    if [[ -z "${swap_info}" ]]; then
        echo "0 0"
        return
    fi

    # ???????????
    local swap_total swap_used
    swap_total=$(echo "${swap_info}" | awk '{print $1}')
    swap_used=$(echo "${swap_info}" | awk '{print $2}')

    swap_total=$(convert_size_to_mb "${swap_total}")
    swap_used=$(convert_size_to_mb "${swap_used}")

    [[ -z "${swap_total}" ]] || [[ "${swap_total}" == "0" ]] && swap_total=1
    [[ -z "${swap_used}" ]] && swap_used=0

    echo "${swap_total} ${swap_used}"
}

# ==============================================================================
# ??Swap??????
# @return: 0????1????
# ==============================================================================
is_swap_file_enabled() {
    [[ -f "${SWAP_FILE_PATH}" ]] && swapon --show=NAME --noheadings 2>/dev/null | grep -q "${SWAP_FILE_PATH}"
}

# ==============================================================================
# ??Swap??
# @param size_mb: Swap?????MB?
# @param priority: Swap???????PHYSICAL_SWAP_PRIORITY?
# @return: 0????1???
# ==============================================================================
create_swap_file() {
    local size_mb="$1"
    local priority="${2:-$(get_config 'physical_swap_priority')}"

    log_info "???? Swap ?? (${size_mb}MB)..."

    # ????
    if ! validate_positive_integer "${size_mb}"; then
        handle_error "SWAP_CREATE" "??? Swap ??: ${size_mb}"
        return 1
    fi

    if [[ ${size_mb} -lt 128 ]]; then
        handle_error "SWAP_CREATE" "Swap ???????? 128MB"
        return 1
    fi

    if [[ ${size_mb} -gt $((SYSTEM_INFO[total_memory_mb] * 4)) ]]; then
        log_warn "Swap ??????????? 4 ????????"
    fi

    # ????
    mkdir -p "$(dirname "${SWAP_FILE_PATH}")"

    # ???????Swap??
    if [[ -f "${SWAP_FILE_PATH}" ]]; then
        log_warn "Swap ?????????..."
        disable_swap_file
        rm -f "${SWAP_FILE_PATH}"
    fi

    # ??Swap??
    if ! fallocate -l "${size_mb}M" "${SWAP_FILE_PATH}" 2>/dev/null; then
        log_warn "fallocate ??????? dd..."
        dd if=/dev/zero of="${SWAP_FILE_PATH}" bs=1M count="${size_mb}" status=none || {
            handle_error "SWAP_CREATE" "?? Swap ????"
            return 1
        }
    fi

    # ??????
    chmod 600 "${SWAP_FILE_PATH}"

    # ???Swap??
    if ! mkswap "${SWAP_FILE_PATH}" > /dev/null 2>&1; then
        handle_error "SWAP_CREATE" "??? Swap ????"
        rm -f "${SWAP_FILE_PATH}"
        return 1
    fi

    # ??Swap??
    if ! swapon -p "${priority}" "${SWAP_FILE_PATH}" > /dev/null 2>&1; then
        handle_error "SWAP_CREATE" "?? Swap ????"
        rm -f "${SWAP_FILE_PATH}"
        return 1
    fi

    # ???fstab
    if [[ ! -f /etc/fstab ]] || ! grep -q "${SWAP_FILE_PATH}" /etc/fstab; then
        echo "${SWAP_FILE_PATH} none swap sw,pri=${priority} 0 0" >> /etc/fstab
        log_info "???? /etc/fstab"
    fi

    # ????
    clear_cache

    SWAP_ENABLED=true
    log_info "?? Swap ??????: ${size_mb}MB, ???: ${priority}"
    return 0
}

# ==============================================================================
# ??Swap??
# @return: 0???
# ==============================================================================
disable_swap_file() {
    log_info "???? Swap ??..."

    # ??Swap
    if [[ -f "${SWAP_FILE_PATH}" ]]; then
        swapoff "${SWAP_FILE_PATH}" 2>/dev/null || true
    fi

    # ?fstab??
    if [[ -f /etc/fstab ]] && grep -q "${SWAP_FILE_PATH}" /etc/fstab; then
        # ??fstab
        local backup_file="/etc/fstab.bak.$(date +%Y%m%d_%H%M%S)"
        cp /etc/fstab "${backup_file}" 2>/dev/null || true

        sed -i "\|${SWAP_FILE_PATH}|d" /etc/fstab
        log_info "?? /etc/fstab ??"
    fi

    # ????
    if [[ -f "${SWAP_FILE_PATH}" ]]; then
        rm -f "${SWAP_FILE_PATH}"
        log_info "??? Swap ??"
    fi

    # ????
    clear_cache

    SWAP_ENABLED=false
    return 0
}

# ==============================================================================
# ????Swap
# @param mode: ????
# @return: 0????1???
# ==============================================================================
configure_physical_swap() {
    local mode="${1:-${STRATEGY_MODE}}"

    log_info "???? Swap (??: ${mode})..."

    local zram_ratio phys_limit swap_size swappiness dirty_ratio min_free
    read -r zram_ratio phys_limit swap_size swappiness dirty_ratio min_free <<< "$(calculate_strategy "${mode}")"

    if [[ ${swap_size} -lt 128 ]]; then
        swap_size=128
    fi

    # ??????????
    if is_swap_file_enabled; then
        local swap_info
        swap_info=$(get_swap_file_info)
        local current_size
        current_size=$(echo "${swap_info}" | awk '{print $1}')

        local tolerance=100
        if [[ ${current_size} -ge $((swap_size - tolerance)) ]] && [[ ${current_size} -le $((swap_size + tolerance)) ]]; then
            log_info "?? Swap ??????? (${current_size}MB)"
            return 0
        fi

        log_info "???? Swap ??: ${current_size}MB -> ${swap_size}MB"
        disable_swap_file
    fi

    if ! create_swap_file "${swap_size}" "$(get_config 'physical_swap_priority')"; then
        handle_error "SWAP_CONFIG" "?? Swap ????"
        return 1
    fi

    return 0
}

# ==============================================================================
# ??Swap??
# @param swap_size: Swap???MB?
# @param enabled: ?????true/false?
# @return: 0????1???
# ==============================================================================
save_swap_config() {
    local swap_size="$1"
    local enabled="$2"

    local content
    cat <<EOF
# ============================================================================
# Z-Panel Pro ?? Swap ??
# ============================================================================
# ???????????
#
# SWAP_SIZE: ?? Swap ?????MB?
# SWAP_ENABLED: ?????? Swap
# SWAP_PRIORITY: Swap ????ZRAM=$(get_config 'zram_priority'), ?? Swap=$(get_config 'physical_swap_priority')?
# ============================================================================

SWAP_SIZE=${swap_size}
SWAP_ENABLED=${enabled}
SWAP_PRIORITY=$(get_config 'physical_swap_priority')
EOF

    if save_config_file "${SWAP_CONFIG_FILE}" "${content}"; then
        log_info "Swap ?????"
        return 0
    else
        log_error "Swap ??????"
        return 1
    fi
}

# ==============================================================================
# ????Swap????
# @return: ????Swap????
# ==============================================================================
get_all_swap_devices() {
    echo "=== ?? Swap ?? ==="
    echo ""

    if swapon --show=NAME,SIZE,USED,PRIO --noheadings 2>/dev/null | grep -q .; then
        printf "%-30s %10s %10s %10s\n" "??" "??" "??" "???"
        printf "%-30s %10s %10s %10s\n" "----" "----" "----" "----"

        swapon --show=NAME,SIZE,USED,PRIO --noheadings 2>/dev/null | while read -r name size used prio; do
            # ????
            local size_mb
            size_mb=$(convert_size_to_mb "${size}")
            local used_mb
            used_mb=$(convert_size_to_mb "${used}")

            printf "%-30s %10s %10s %10s\n" "${name}" "${size_mb}MB" "${used_mb}MB" "${prio}"
        done
    else
        echo "?????? Swap ??"
    fi

    echo ""
    echo "=== ?? ==="
    local swap_total swap_used
    read -r swap_total swap_used <<< "$(get_swap_info false)"
    printf "??: %sMB  ??: %sMB\n" "${swap_total}" "${swap_used}"
}
