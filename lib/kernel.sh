#!/bin/bash
# ==============================================================================
# Z-Panel Pro - 内核参数模块
# ==============================================================================
# @description    内核参数管理与保护机�?# @version       7.1.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 应用I/O熔断保护
# @param dirty_ratio: 脏数据比�?# ==============================================================================
apply_io_fuse_protection() {
    local dirty_ratio="$1"
    local dirty_background_ratio=$((dirty_ratio / 2))

    log_info "应用 I/O 熔断保护..."

    # 批量设置内核参数（优化性能�?    sysctl -w vm.dirty_ratio=${dirty_ratio} \
            vm.dirty_background_ratio=${dirty_background_ratio} \
            vm.dirty_expire_centisecs=3000 \
            vm.dirty_writeback_centisecs=500 > /dev/null 2>&1 || {
        log_warn "部分 I/O 熔断参数设置失败"
    }

    log_info "I/O 熔断保护已启�?(dirty_ratio: ${dirty_ratio})"
}

# ==============================================================================
# 应用OOM保护
# ==============================================================================
apply_oom_protection() {
    log_info "应用 OOM 保护..."

    local protected=0
    local failed=0

    # 保护SSH进程
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
                        log_warn "设置OOM保护失败: PID ${pid} (sshd)"
                    fi
                fi
            fi
        done <<< "${pids}"
    fi

    # 保护systemd进程
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
                        log_warn "设置OOM保护失败: PID ${pid} (systemd)"
                    fi
                fi
            fi
        done <<< "${pids}"
    fi

    log_info "OOM 保护已启�?(已保�?${protected} 个进�? 失败: ${failed} �?"
}

# ==============================================================================
# 计算动态swappiness
# @param base_swappiness: 基础swappiness�?# @param mode: 策略模式
# @return: 动态swappiness�?# ==============================================================================
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

    # 根据ZRAM使用率调�?    if [[ ${zram_usage} -gt 80 ]]; then
        swappiness=$((swappiness - 20)) || true
    elif [[ ${zram_usage} -gt 50 ]]; then
        swappiness=$((swappiness - 10)) || true
    fi

    # 根据Swap使用率调�?    if [[ ${swap_usage} -gt 50 ]]; then
        swappiness=$((swappiness - 10)) || true
    fi

    # 根据内存大小调整
    if [[ ${mem_total} -lt 1024 ]]; then
        swappiness=$((swappiness + 20)) || true
    elif [[ ${mem_total} -gt 4096 ]]; then
        swappiness=$((swappiness - 10)) || true
    fi

    # 限制范围
    [[ ${swappiness} -lt 10 ]] && swappiness=10
    [[ ${swappiness} -gt 100 ]] && swappiness=100

    echo "${swappiness}"
}

# ==============================================================================
# 保存内核配置
# @param swappiness: swappiness�?# @param dirty_ratio: 脏数据比�?# @param min_free: 最小空闲内存（KB�?# @return: 0为成功，1为失�?# ==============================================================================
save_kernel_config() {
    local swappiness="$1"
    local dirty_ratio="$2"
    local min_free="$3"

    local content
    cat <<EOF
# ============================================================================
# Z-Panel Pro 内核参数配置
# ============================================================================
# 自动生成，请勿手动修�?#
# 内存管理参数:
#   vm.swappiness: 系统使用 swap 的倾向�?(0-100)
#   vm.vfs_cache_pressure: 缓存 inode/dentry 的倾向�?#   vm.min_free_kbytes: 系统保留的最小空闲内�?#
# 脏数据策�?(I/O 熔断保护):
#   vm.dirty_ratio: 脏数据占系统内存的最大百分比
#   vm.dirty_background_ratio: 后台写入开始的脏数据百分比
#   vm.dirty_expire_centisecs: 脏数据过期时间（厘秒�?#   vm.dirty_writeback_centisecs: 后台写入间隔（厘秒）
#
# 页面聚合:
#   vm.page-cluster: 一次读取的页面�?(0=禁用)
#
# 文件系统:
#   fs.file-max: 系统最大打开文件�?#   fs.inotify.max_user_watches: inotify 监视数量限制
# ============================================================================

# 内存管理
vm.swappiness=${swappiness}
vm.vfs_cache_pressure=100
vm.min_free_kbytes=${min_free}

# 脏数据策�?(I/O 熔断保护)
vm.dirty_ratio=${dirty_ratio}
vm.dirty_background_ratio=$((dirty_ratio / 2)) || true
vm.dirty_expire_centisecs=3000
vm.dirty_writeback_centisecs=500

# 页面聚合
vm.page-cluster=0

# 文件系统
fs.file-max=2097152
fs.inotify.max_user_watches=524288
EOF

    if save_config_file "${KERNEL_CONFIG_FILE}" "${content}"; then
        log_info "内核配置已保�?
        return 0
    else
        log_error "内核配置保存失败"
        return 1
    fi
}

# ==============================================================================
# 应用内核参数
# @return: 0为成�?# ==============================================================================
apply_kernel_params() {
    log_info "应用内核参数..."

    # 批量应用参数
    while IFS='=' read -r key value; do
        [[ "${key}" =~ ^# ]] && continue
        [[ -z "${key}" ]] && continue
        sysctl -w "${key}=${value}" > /dev/null 2>&1 || true
    done < "${KERNEL_CONFIG_FILE}"

    # 更新sysctl.conf
    if [[ -f /etc/sysctl.conf ]]; then
        # 备份原文�?        local backup_file="/etc/sysctl.conf.bak.$(date +%Y%m%d_%H%M%S)"
        cp /etc/sysctl.conf "${backup_file}" 2>/dev/null || true

        # 移除旧的配置
        sed -i '/# Z-Panel Pro 内核参数配置/,/# Z-Panel Pro 内核参数配置结束/d' /etc/sysctl.conf 2>/dev/null || true

        # 添加新配�?        cat >> /etc/sysctl.conf <<EOF

# Z-Panel Pro 内核参数配置
# 自动生成，请勿手动修�?EOF
        cat "${KERNEL_CONFIG_FILE}" >> /etc/sysctl.conf
        echo "# Z-Panel Pro 内核参数配置结束" >> /etc/sysctl.conf

        log_info "内核参数已写�?/etc/sysctl.conf"
    fi
}

# ==============================================================================
# 配置虚拟内存
# @param mode: 策略模式
# @return: 0为成功，1为失�?# ==============================================================================
configure_virtual_memory() {
    local mode="${1:-${STRATEGY_MODE}}"

    log_info "配置虚拟内存策略 (策略: ${mode})..."

    local zram_ratio phys_limit swap_size swappiness dirty_ratio min_free
    read -r zram_ratio phys_limit swap_size swappiness dirty_ratio min_free <<< "$(calculate_strategy "${mode}")"

    # 计算动态swappiness
    local dynamic_swappiness
    dynamic_swappiness=$(calculate_dynamic_swappiness "${swappiness}" "${mode}")

    log_info "建议 swappiness: ${dynamic_swappiness}"

    # 保存配置
    if ! save_kernel_config "${dynamic_swappiness}" "${dirty_ratio}" "${min_free}"; then
        return 1
    fi

    # 应用参数
    apply_kernel_params

    # 应用保护机制
    apply_io_fuse_protection "${dirty_ratio}"
    apply_oom_protection

    log_info "虚拟内存配置完成 (ZRAM + 物理 Swap)"
    return 0
}