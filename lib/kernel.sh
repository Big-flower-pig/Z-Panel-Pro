#!/bin/bash
# ==============================================================================
# Z-Panel Pro - ??????
# ==============================================================================
# @description    ???????????
# @version       7.1.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# ??I/O????
# @param dirty_ratio: ?????
# ==============================================================================
apply_io_fuse_protection() {
    local dirty_ratio="$1"
    local dirty_background_ratio=$((dirty_ratio / 2))

    log_info "?? I/O ????..."

    # ??????????????
    sysctl -w vm.dirty_ratio=${dirty_ratio} \
            vm.dirty_background_ratio=${dirty_background_ratio} \
            vm.dirty_expire_centisecs=3000 \
            vm.dirty_writeback_centisecs=500 > /dev/null 2>&1 || {
        log_warn "?? I/O ????????"
    }

    log_info "I/O ??????? (dirty_ratio: ${dirty_ratio})"
}

# ==============================================================================
# ??OOM??
# ==============================================================================
apply_oom_protection() {
    log_info "?? OOM ??..."

    local protected=0
    local failed=0

    # ??SSH??
    local pids
    pids=$(pgrep sshd 2>/dev/null) || pids=""

    if [[ -n "${pids}" ]]; then
        while IFS= read -r pid; do
            if validate_pid "${pid}" && [[ -f "/proc/${pid}/oom_score_adj" ]]; then
                local cmdline
                cmdline=$(cat "/proc/${pid}/cmdline" 2>/dev/null | tr '\0' ' ' | head -c 100)
                if [[ "${cmdline}" == *"sshd"* ]]; then
                    if echo -1000 > "/proc/${pid}/oom_score_adj" 2>/dev/null; then
                        ((protected++)) || true
                    else
                        ((failed++)) || true
                        log_warn "??OOM????: PID ${pid} (sshd)"
                    fi
                fi
            fi
        done <<< "${pids}"
    fi

    # ??systemd??
    pids=$(pgrep systemd 2>/dev/null) || pids=""

    if [[ -n "${pids}" ]]; then
        while IFS= read -r pid; do
            if validate_pid "${pid}" && [[ -f "/proc/${pid}/oom_score_adj" ]]; then
                local cmdline
                cmdline=$(cat "/proc/${pid}/cmdline" 2>/dev/null | tr '\0' ' ' | head -c 100)
                if [[ "${cmdline}" == *"systemd"* ]]; then
                    if echo -1000 > "/proc/${pid}/oom_score_adj" 2>/dev/null; then
                        ((protected++)) || true
                    else
                        ((failed++)) || true
                        log_warn "??OOM????: PID ${pid} (systemd)"
                    fi
                fi
            fi
        done <<< "${pids}"
    fi

    log_info "OOM ????? (??? ${protected} ??????: ${failed} ?)"
}

# ==============================================================================
# ????swappiness
# @param base_swappiness: ??swappiness?
# @param mode: ????
# @return: ??swappiness?
# ==============================================================================
calculate_dynamic_swappiness() {
    local base_swappiness="$1"
    local mode="${2:-${STRATEGY_MODE}}"

    local swappiness=${base_swappiness}

    read -r mem_total _ _ _ <<< "$(get_memory_info false)"
    read -r swap_total swap_used <<< "$(get_swap_info false)"

    local swap_usage=0
    [[ ${swap_total} -gt 0 ]] && swap_usage=$((swap_used * 100 / swap_total)) || true

    read -r zram_total zram_used <<< "$(get_zram_usage)"
    local zram_usage=0
    if [[ ${zram_total} -gt 0 ]]; then
        zram_usage=$((zram_used * 100 / zram_total)) || true
    fi

    # ??ZRAM?????
    if [[ ${zram_usage} -gt 80 ]]; then
        swappiness=$((swappiness - 20)) || true
    elif [[ ${zram_usage} -gt 50 ]]; then
        swappiness=$((swappiness - 10)) || true
    fi

    # ??Swap?????
    if [[ ${swap_usage} -gt 50 ]]; then
        swappiness=$((swappiness - 10)) || true
    fi

    # ????????
    if [[ ${mem_total} -lt 1024 ]]; then
        swappiness=$((swappiness + 20)) || true
    elif [[ ${mem_total} -gt 4096 ]]; then
        swappiness=$((swappiness - 10)) || true
    fi

    # ????
    [[ ${swappiness} -lt 10 ]] && swappiness=10
    [[ ${swappiness} -gt 100 ]] && swappiness=100

    echo "${swappiness}"
}

# ==============================================================================
# ??????
# @param swappiness: swappiness?
# @param dirty_ratio: ?????
# @param min_free: ???????KB?
# @return: 0????1???
# ==============================================================================
save_kernel_config() {
    local swappiness="$1"
    local dirty_ratio="$2"
    local min_free="$3"

    local content
    cat <<EOF
# ============================================================================
# Z-Panel Pro ??????
# ============================================================================
# ???????????
#
# ??????:
#   vm.swappiness: ???? swap ???? (0-100)
#   vm.vfs_cache_pressure: ?? inode/dentry ????
#   vm.min_free_kbytes: ???????????
#
# ????? (I/O ????):
#   vm.dirty_ratio: ??????????????
#   vm.dirty_background_ratio: ?????????????
#   vm.dirty_expire_centisecs: ???????????
#   vm.dirty_writeback_centisecs: ??????????
#
# ????:
#   vm.page-cluster: ???????? (0=??)
#
# ????:
#   fs.file-max: ?????????
#   fs.inotify.max_user_watches: inotify ??????
# ============================================================================

# ????
vm.swappiness=${swappiness}
vm.vfs_cache_pressure=100
vm.min_free_kbytes=${min_free}

# ????? (I/O ????)
vm.dirty_ratio=${dirty_ratio}
vm.dirty_background_ratio=$((dirty_ratio / 2)) || true
vm.dirty_expire_centisecs=3000
vm.dirty_writeback_centisecs=500

# ????
vm.page-cluster=0

# ????
fs.file-max=2097152
fs.inotify.max_user_watches=524288
EOF

    if save_config_file "${KERNEL_CONFIG_FILE}" "${content}"; then
        log_info "???????"
        return 0
    else
        log_error "????????"
        return 1
    fi
}

# ==============================================================================
# ??????
# @return: 0???
# ==============================================================================
apply_kernel_params() {
    log_info "??????..."

    # ??????
    while IFS='=' read -r key value; do
        [[ "${key}" =~ ^# ]] && continue
        [[ -z "${key}" ]] && continue
        sysctl -w "${key}=${value}" > /dev/null 2>&1 || true
    done < "${KERNEL_CONFIG_FILE}"

    # ??sysctl.conf
    if [[ -f /etc/sysctl.conf ]]; then
        # ?????
        local backup_file="/etc/sysctl.conf.bak.$(date +%Y%m%d_%H%M%S)"
        cp /etc/sysctl.conf "${backup_file}" 2>/dev/null || true

        # ??????
        sed -i '/# Z-Panel Pro ??????/,/# Z-Panel Pro ????????/d' /etc/sysctl.conf 2>/dev/null || true

        # ?????
        cat >> /etc/sysctl.conf <<EOF

# Z-Panel Pro ??????
# ???????????
EOF
        cat "${KERNEL_CONFIG_FILE}" >> /etc/sysctl.conf
        echo "# Z-Panel Pro ????????" >> /etc/sysctl.conf

        log_info "??????? /etc/sysctl.conf"
    fi
}

# ==============================================================================
# ??????
# @param mode: ????
# @return: 0????1???
# ==============================================================================
configure_virtual_memory() {
    local mode="${1:-${STRATEGY_MODE}}"

    log_info "???????? (??: ${mode})..."

    local zram_ratio phys_limit swap_size swappiness dirty_ratio min_free
    read -r zram_ratio phys_limit swap_size swappiness dirty_ratio min_free <<< "$(calculate_strategy "${mode}")"

    # ????swappiness
    local dynamic_swappiness
    dynamic_swappiness=$(calculate_dynamic_swappiness "${swappiness}" "${mode}")

    log_info "?? swappiness: ${dynamic_swappiness}"

    # ????
    if ! save_kernel_config "${dynamic_swappiness}" "${dirty_ratio}" "${min_free}"; then
        return 1
    fi

    # ????
    apply_kernel_params

    # ??????
    apply_io_fuse_protection "${dirty_ratio}"
    apply_oom_protection

    log_info "???????? (ZRAM + ?? Swap)"
    return 0
}
