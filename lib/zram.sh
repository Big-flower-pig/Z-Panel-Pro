#!/bin/bash
# ==============================================================================
# Z-Panel Pro - ZRAM????
# ==============================================================================
# @description    ZRAM???????
# @version       7.1.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# ?????ZRAM??
# @return: ??????zram0?
# ==============================================================================
get_available_zram_device() {
    local cached_device
    cached_device=$(get_config "_zram_device_cache")

    if [[ -n "${cached_device}" ]]; then
        echo "${cached_device}"
        return 0
    fi

    # ??????ZRAM??
    for i in {0..15}; do
        if [[ -e "/sys/block/zram${i}" ]] && ! swapon --show=NAME | grep -q "zram${i}"; then
            set_config "_zram_device_cache" "zram${i}"
            echo "zram${i}"
            return 0
        fi
    done

    # ?????
    if [[ -e /sys/class/zram-control/hot_add ]]; then
        local device_num
        device_num=$(cat /sys/class/zram-control/hot_add)
        set_config "_zram_device_cache" "zram${device_num}"
        echo "zram${device_num}"
        return 0
    fi

    return 1
}

# ==============================================================================
# ???ZRAM??
# @return: ????
# ==============================================================================
initialize_zram_device() {
    # ??ZRAM??
    if ! lsmod | grep -q zram; then
        if ! modprobe zram 2>/dev/null; then
            handle_error "ZRAM_INIT" "???? ZRAM ??" "exit"
        fi
        log_info "ZRAM ?????"
    fi

    # ??????
    local zram_device
    zram_device=$(get_available_zram_device) || {
        handle_error "ZRAM_INIT" "??????? ZRAM ??" "exit"
    }

    # ????ZRAM??
    if swapon --show=NAME --noheadings 2>/dev/null | grep -q zram; then
        local failed_devices=()
        for device in $(swapon --show=NAME --noheadings 2>/dev/null | grep zram); do
            if ! swapoff "${device}" 2>/dev/null; then
                log_warn "??????: ${device}"
                failed_devices+=("${device}")
            fi
        done

        if [[ ${#failed_devices[@]} -gt 0 ]]; then
            log_error "????????: ${failed_devices[*]}"
            return 1
        fi
    fi

    # ????
    if [[ -e "/sys/block/${zram_device}/reset" ]]; then
        echo 1 > "/sys/block/${zram_device}/reset" 2>/dev/null || true
        sleep 0.3
    fi

    # ??????
    if [[ ! -e "/dev/${zram_device}" ]]; then
        handle_error "ZRAM_INIT" "ZRAM ?????: /dev/${zram_device}" "exit"
    fi

    log_info "ZRAM ??????: ${zram_device}"
    echo "${zram_device}"
    return 0
}

# ==============================================================================
# ????????
# @return: ????
# ==============================================================================
detect_best_algorithm() {
    log_info "????????..."

    local cpu_flags
    cpu_flags=$(cat /proc/cpuinfo | grep -m1 "flags" | sed 's/flags://')

    local algorithms=("lz4" "lzo" "zstd")
    local best_algo="lzo"
    local best_score=0

    for algo in "${algorithms[@]}"; do
        local score=0

        case "${algo}" in
            lz4) score=100 ;;
            lzo) score=90 ;;
            zstd)
                if echo "${cpu_flags}" | grep -q "avx2"; then
                    score=70
                else
                    score=50
                fi
                ;;
        esac

        if [[ ${score} -gt ${best_score} ]]; then
            best_score=${score}
            best_algo="${algo}"
        fi

        log_info "${algo}: ?? ${score}"
    done

    log_info "????: ${best_algo}"
    echo "${best_algo}"
}

# ==============================================================================
# ??ZRAM??
# @param algorithm: ?????auto/??????
# @return: ????
# ==============================================================================
get_zram_algorithm() {
    local algorithm="${1:-auto}"

    if [[ "${algorithm}" == "auto" ]]; then
        algorithm=$(detect_best_algorithm)
    fi

    echo "${algorithm}"
}

# ==============================================================================
# ??ZRAM??
# @param zram_device: ZRAM???
# @param algorithm: ????
# @return: ???????
# ==============================================================================
configure_zram_compression() {
    local zram_device="$1"
    local algorithm="$2"

    if [[ -e "/sys/block/${zram_device}/comp_algorithm" ]]; then
        local supported
        supported=$(cat "/sys/block/${zram_device}/comp_algorithm" 2>/dev/null)

        if echo "${supported}" | grep -q "${algorithm}"; then
            if echo "${algorithm}" > "/sys/block/${zram_device}/comp_algorithm" 2>/dev/null; then
                log_info "??????: ${algorithm}"
            else
                log_warn "???????????????"
            fi
        else
            # ??????
            local fallback
            fallback=$(echo "${supported}" | awk -F'[][]' '{print $2}' | head -1)

            if [[ -z "${fallback}" ]]; then
                fallback=$(echo "${supported}" | sed 's/^\s*//' | head -1 | awk '{print $1}')
            fi

            [[ -z "${fallback}" ]] && fallback="lzo"

            echo "${fallback}" > "/sys/block/${zram_device}/comp_algorithm" 2>/dev/null || true
            algorithm="${fallback}"
            log_info "??????: ${algorithm}"
        fi
    fi

    # ??????
    if [[ -e "/sys/block/${zram_device}/max_comp_streams" ]]; then
        echo "${SYSTEM_INFO[cpu_cores]}" > "/sys/block/${zram_device}/max_comp_streams" 2>/dev/null || true
        log_info "??????: ${SYSTEM_INFO[cpu_cores]}"
    fi

    echo "${algorithm}"
}

# ==============================================================================
# ??ZRAM??
# @param zram_device: ZRAM???
# @param zram_size: ZRAM???MB?
# @param phys_limit: ???????MB?
# @return: 0????1???
# ==============================================================================
configure_zram_limits() {
    local zram_device="$1"
    local zram_size="$2"
    local phys_limit="$3"

    # ??????
    local zram_bytes=$((zram_size * 1024 * 1024)) || true
    if ! echo "${zram_bytes}" > "/sys/block/${zram_device}/disksize" 2>/dev/null; then
        handle_error "ZRAM_LIMIT" "?? ZRAM ????"
        return 1
    fi

    # ????????
    if [[ -e "/sys/block/${zram_device}/mem_limit" ]]; then
        local phys_limit_bytes=$((phys_limit * 1024 * 1024)) || true
        echo "${phys_limit_bytes}" > "/sys/block/${zram_device}/mem_limit" 2>/dev/null || true
        log_info "????????????Limit: ${phys_limit}MB?"
    fi

    return 0
}

# ==============================================================================
# ??ZRAM Swap
# @param zram_device: ZRAM???
# @return: 0????1???
# ==============================================================================
enable_zram_swap() {
    local zram_device="$1"

    # ???ZRAM??
    if ! mkswap "/dev/${zram_device}" > /dev/null 2>&1; then
        handle_error "ZRAM_SWAP" "??? ZRAM ??"
        return 1
    fi

    # ??Swap
    if ! swapon -p "$(get_config 'zram_priority')" "/dev/${zram_device}" > /dev/null 2>&1; then
        handle_error "ZRAM_SWAP" "?? ZRAM ??"
        return 1
    fi

    # ????
    set_config "_zram_device_cache" ""
    clear_cache

    ZRAM_ENABLED=true
    log_info "ZRAM Swap ???: ${zram_device}"
    return 0
}

# ==============================================================================
# ??ZRAM??
# @param algorithm: ????
# @param mode: ????
# @return: "algorithm mode zram_ratio phys_limit swap_size swappiness dirty_ratio min_free zram_size"
# ==============================================================================
prepare_zram_params() {
    local algorithm="${1:-auto}"
    local mode="${2:-${STRATEGY_MODE}}"

    validate_strategy_mode "${mode}" || return 1
    algorithm=$(get_zram_algorithm "${algorithm}")

    local zram_ratio phys_limit swap_size swappiness dirty_ratio min_free
    read -r zram_ratio phys_limit swap_size swappiness dirty_ratio min_free <<< "$(calculate_strategy "${mode}")"

    local zram_size=$((SYSTEM_INFO[total_memory_mb] * zram_ratio / 100)) || true
    [[ ${zram_size} -lt 512 ]] && zram_size=512

    if ! validate_positive_integer "${zram_size}" || ! validate_positive_integer "${phys_limit}"; then
        handle_error "ZRAM_PARAMS" "ZRAM ??????"
        return 1
    fi

    echo "${algorithm} ${mode} ${zram_ratio} ${phys_limit} ${swap_size} ${swappiness} ${dirty_ratio} ${min_free} ${zram_size}"
    return 0
}

# ==============================================================================
# ??ZRAM??
# @param algorithm: ????
# @param mode: ????
# @param zram_ratio: ZRAM????
# @param zram_size: ZRAM???MB?
# @param phys_limit: ???????MB?
# @return: 0????1???
# ==============================================================================
save_zram_config() {
    local algorithm="$1"
    local mode="$2"
    local zram_ratio="$3"
    local zram_size="$4"
    local phys_limit="$5"

    local content
    cat <<EOF
# ============================================================================
# Z-Panel Pro ZRAM ??
# ============================================================================
# ???????????
#
# ALGORITHM: ZRAM ???? (auto/zstd/lz4/lzo)
# STRATEGY: ???????
# PERCENT: ZRAM ???????????
# PRIORITY: Swap ???
# SIZE: ZRAM ?????MB?
# PHYS_LIMIT: ?????????MB?
# ============================================================================

ALGORITHM=${algorithm}
STRATEGY=${mode}
PERCENT=${zram_ratio}
PRIORITY=$(get_config 'zram_priority')
SIZE=${zram_size}
PHYS_LIMIT=${phys_limit}
EOF

    if save_config_file "${ZRAM_CONFIG_FILE}" "${content}"; then
        log_info "ZRAM ?????"
        return 0
    else
        log_error "ZRAM ??????"
        return 1
    fi
}

# ==============================================================================
# ??ZRAM??
# @return: 0????1???
# ==============================================================================
create_zram_service() {
    log_info "?? ZRAM ?????..."

    local service_script="${INSTALL_DIR}/zram-start.sh"

    # ??????
    cat > "${service_script}" <<'SERVICE_SCRIPT'
#!/bin/bash
set -o pipefail
CONF_DIR="/opt/z-panel/conf"
LOG_DIR="/opt/z-panel/logs"

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    echo "${timestamp}[LOG] ${message}" >> "$LOG_DIR/zram-service.log" 2>/dev/null || true
}

if [[ -f "$CONF_DIR/zram.conf" ]]; then
    source "$CONF_DIR/zram.conf"

    log "???? ZRAM ??..."

    modprobe zram 2>/dev/null || {
        log "???? zram ??"
        exit 1
    }

    if [[ -e /sys/block/zram0/reset ]]; then
        echo 1 > /sys/block/zram0/reset 2>/dev/null || true
        log "??? ZRAM ??"
    fi

    if [[ -e /sys/block/zram0/comp_algorithm ]]; then
        echo "$ALGORITHM" > /sys/block/zram0/comp_algorithm 2>/dev/null || true
        log "??????: $ALGORITHM"
    fi

    local zram_bytes=$((SIZE * 1024 * 1024)) || true
    echo "$zram_bytes" > /sys/block/zram0/disksize 2>/dev/null || {
        log "?? ZRAM ????"
        exit 1
    }
    log "?? ZRAM ??: ${SIZE}MB"

    if [[ -e /sys/block/zram0/mem_limit ]]; then
        local phys_limit_bytes=$((PHYS_LIMIT * 1024 * 1024)) || true
        echo "$phys_limit_bytes" > /sys/block/zram0/mem_limit 2>/dev/null || true
        log "????????: ${PHYS_LIMIT}MB"
    fi

    mkswap /dev/zram0 > /dev/null 2>&1 || {
        log "??? ZRAM ??"
        exit 1
    }

    swapon -p $PRIORITY /dev/zram0 > /dev/null 2>&1 || {
        log "?? ZRAM ??"
        exit 1
    }

    log "ZRAM ??????"
else
    log "???????: $CONF_DIR/zram.conf"
    exit 1
fi

if [[ -f "$CONF_DIR/kernel.conf" ]]; then
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^# ]] && continue
        [[ -z "$key" ]] && continue
        sysctl -w "$key=$value" > /dev/null 2>&1 || log "?? $key ??"
    done < "$CONF_DIR/kernel.conf"
fi
SERVICE_SCRIPT

    chmod 700 "${service_script}" 2>/dev/null || true

    # ??systemd??
    if check_systemd; then
        local systemd_service="/etc/systemd/system/zram.service"

        cat > "${systemd_service}" <<SYSTEMD_SERVICE
[Unit]
Description=ZRAM Memory Compression
After=multi-user.target
Wants=multi-user.target

[Service]
Type=oneshot
ExecStart=${service_script}
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SYSTEMD_SERVICE

        chmod 644 "${systemd_service}" 2>/dev/null || true

        systemctl daemon-reload > /dev/null 2>&1
        systemctl enable zram.service > /dev/null 2>&1

        log_info "systemd ?????????"
    fi

    return 0
}

# ==============================================================================
# ??ZRAM??
# @return: 0????1???
# ==============================================================================
start_zram_service() {
    if check_systemd; then
        systemctl daemon-reload > /dev/null 2>&1
        if systemctl is-active --quiet zram.service 2>/dev/null; then
            log_info "zram.service ?????????"
        else
            if systemctl start zram.service > /dev/null 2>&1; then
                log_info "zram.service ???"
            else
                log_warn "zram.service ?????? ZRAM ?????????"
            fi
        fi
    fi
}

# ==============================================================================
# ??ZRAM?????
# @param algorithm: ???????auto?
# @param mode: ?????????STRATEGY_MODE?
# @return: 0????1???
# ==============================================================================
configure_zram() {
    local algorithm="${1:-auto}"
    local mode="${2:-${STRATEGY_MODE}}"

    log_info "???? ZRAM (??: ${mode})..."

    # ????
    local params
    params=$(prepare_zram_params "${algorithm}" "${mode}") || return 1
    read -r algorithm mode zram_ratio phys_limit swap_size swappiness dirty_ratio min_free zram_size <<< "${params}"

    # ?????zram-tools
    if ! check_command zramctl; then
        log_info "?? zram-tools..."
        install_packages zram-tools zram-config zstd lz4 lzop || {
            handle_error "ZRAM_CONFIG" "?? zram-tools ??"
            return 1
        }
    fi

    # ?????
    local zram_device
    zram_device=$(initialize_zram_device) || {
        handle_error "ZRAM_CONFIG" "??? ZRAM ????"
        return 1
    }
    log_info "?? ZRAM ??: ${zram_device}"

    # ????
    algorithm=$(configure_zram_compression "${zram_device}" "${algorithm}")

    # ????
    configure_zram_limits "${zram_device}" "${zram_size}" "${phys_limit}" || {
        handle_error "ZRAM_CONFIG" "?? ZRAM ????"
        return 1
    }

    # ??Swap
    enable_zram_swap "${zram_device}" || {
        handle_error "ZRAM_CONFIG" "?? ZRAM swap ??"
        return 1
    }

    # ????
    save_zram_config "${algorithm}" "${mode}" "${zram_ratio}" "${zram_size}" "${phys_limit}" || {
        log_warn "?? ZRAM ????"
    }

    # ????
    create_zram_service || {
        log_warn "?? ZRAM ????"
    }

    # ????
    start_zram_service

    set_config "_zram_device_cache" ""

    log_info "ZRAM ????: ${algorithm}, ${zram_size}MB, ???: $(get_config 'zram_priority')"

    return 0
}

# ==============================================================================
# ??ZRAM
# @return: 0???
# ==============================================================================
disable_zram() {
    log_info "?? ZRAM..."

    # ????ZRAM swap
    for device in $(swapon --show=NAME --noheadings 2>/dev/null | grep zram); do
        swapoff "${device}" 2>/dev/null || true
    done

    # ????
    if [[ -e /sys/block/zram0/reset ]]; then
        echo 1 > /sys/block/zram0/reset 2>/dev/null || true
    fi

    # ??systemd??
    if check_systemd; then
        systemctl disable zram.service > /dev/null 2>&1
        rm -f /etc/systemd/system/zram.service
        systemctl daemon-reload > /dev/null 2>&1
    fi

    # ????
    set_config "_zram_device_cache" ""
    clear_cache

    ZRAM_ENABLED=false
    log_info "ZRAM ???"
}
