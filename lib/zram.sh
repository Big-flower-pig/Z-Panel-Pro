#!/bin/bash
# ==============================================================================
# Z-Panel Pro - ZRAM管理模块
# ==============================================================================
# @description    ZRAM设备管理与配置
# @version       7.1.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 获取可用的ZRAM设备
# @return: 设备名称（如zram0）
# ==============================================================================
get_available_zram_device() {
    local cached_device
    cached_device=$(get_config "_zram_device_cache")

    if [[ -n "${cached_device}" ]]; then
        echo "${cached_device}"
        return 0
    fi

    # 查找未使用的ZRAM设备
    for i in {0..15}; do
        if [[ -e "/sys/block/zram${i}" ]] && ! swapon --show=NAME | grep -q "zram${i}"; then
            set_config "_zram_device_cache" "zram${i}"
            echo "zram${i}"
            return 0
        fi
    done

    # 尝试热添加
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
# 初始化ZRAM设备
# @return: 设备名称
# ==============================================================================
initialize_zram_device() {
    # 加载ZRAM模块
    if ! lsmod | grep -q zram; then
        if ! modprobe zram 2>/dev/null; then
            handle_error "ZRAM_INIT" "无法加载 ZRAM 模块" "exit"
        fi
        log_info "ZRAM 模块已加载"
    fi

    # 获取可用设备
    local zram_device
    zram_device=$(get_available_zram_device) || {
        handle_error "ZRAM_INIT" "无法获取可用的 ZRAM 设备" "exit"
    }

    # 停用现有ZRAM设备
    if swapon --show=NAME --noheadings 2>/dev/null | grep -q zram; then
        local failed_devices=()
        for device in $(swapon --show=NAME --noheadings 2>/dev/null | grep zram); do
            if ! swapoff "${device}" 2>/dev/null; then
                log_warn "无法停用设备: ${device}"
                failed_devices+=("${device}")
            fi
        done

        if [[ ${#failed_devices[@]} -gt 0 ]]; then
            log_error "以下设备停用失败: ${failed_devices[*]}"
            return 1
        fi
    fi

    # 重置设备
    if [[ -e "/sys/block/${zram_device}/reset" ]]; then
        echo 1 > "/sys/block/${zram_device}/reset" 2>/dev/null || true
        sleep 0.3
    fi

    # 验证设备存在
    if [[ ! -e "/dev/${zram_device}" ]]; then
        handle_error "ZRAM_INIT" "ZRAM 设备不存在: /dev/${zram_device}" "exit"
    fi

    log_info "ZRAM 设备已初始化: ${zram_device}"
    echo "${zram_device}"
    return 0
}

# ==============================================================================
# 检测最优压缩算法
# @return: 算法名称
# ==============================================================================
detect_best_algorithm() {
    log_info "检测最优压缩算法..."

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

        log_info "${algo}: 评分 ${score}"
    done

    log_info "选择算法: ${best_algo}"
    echo "${best_algo}"
}

# ==============================================================================
# 获取ZRAM算法
# @param algorithm: 算法名称（auto/具体算法名）
# @return: 算法名称
# ==============================================================================
get_zram_algorithm() {
    local algorithm="${1:-auto}"

    if [[ "${algorithm}" == "auto" ]]; then
        algorithm=$(detect_best_algorithm)
    fi

    echo "${algorithm}"
}

# ==============================================================================
# 配置ZRAM压缩
# @param zram_device: ZRAM设备名
# @param algorithm: 压缩算法
# @return: 实际使用的算法
# ==============================================================================
configure_zram_compression() {
    local zram_device="$1"
    local algorithm="$2"

    if [[ -e "/sys/block/${zram_device}/comp_algorithm" ]]; then
        local supported
        supported=$(cat "/sys/block/${zram_device}/comp_algorithm" 2>/dev/null)

        if echo "${supported}" | grep -q "${algorithm}"; then
            if echo "${algorithm}" > "/sys/block/${zram_device}/comp_algorithm" 2>/dev/null; then
                log_info "设置压缩算法: ${algorithm}"
            else
                log_warn "设置压缩算法失败，使用默认算法"
            fi
        else
            # 使用回退算法
            local fallback
            fallback=$(echo "${supported}" | awk -F'[][]' '{print $2}' | head -1)

            if [[ -z "${fallback}" ]]; then
                fallback=$(echo "${supported}" | sed 's/^\s*//' | head -1 | awk '{print $1}')
            fi

            [[ -z "${fallback}" ]] && fallback="lzo"

            echo "${fallback}" > "/sys/block/${zram_device}/comp_algorithm" 2>/dev/null || true
            algorithm="${fallback}"
            log_info "使用回退算法: ${algorithm}"
        fi
    fi

    # 设置压缩流数
    if [[ -e "/sys/block/${zram_device}/max_comp_streams" ]]; then
        echo "${SYSTEM_INFO[cpu_cores]}" > "/sys/block/${zram_device}/max_comp_streams" 2>/dev/null || true
        log_info "设置压缩流数: ${SYSTEM_INFO[cpu_cores]}"
    fi

    echo "${algorithm}"
}

# ==============================================================================
# 配置ZRAM限制
# @param zram_device: ZRAM设备名
# @param zram_size: ZRAM大小（MB）
# @param phys_limit: 物理内存限制（MB）
# @return: 0为成功，1为失败
# ==============================================================================
configure_zram_limits() {
    local zram_device="$1"
    local zram_size="$2"
    local phys_limit="$3"

    # 设置磁盘大小
    local zram_bytes=$((zram_size * 1024 * 1024)) || true
    if ! echo "${zram_bytes}" > "/sys/block/${zram_device}/disksize" 2>/dev/null; then
        handle_error "ZRAM_LIMIT" "设置 ZRAM 大小失败"
        return 1
    fi

    # 设置物理内存限制
    if [[ -e "/sys/block/${zram_device}/mem_limit" ]]; then
        local phys_limit_bytes=$((phys_limit * 1024 * 1024)) || true
        echo "${phys_limit_bytes}" > "/sys/block/${zram_device}/mem_limit" 2>/dev/null || true
        log_info "已启用物理内存熔断保护 (Limit: ${phys_limit}MB)"
    fi

    return 0
}

# ==============================================================================
# 启用ZRAM Swap
# @param zram_device: ZRAM设备名
# @return: 0为成功，1为失败
# ==============================================================================
enable_zram_swap() {
    local zram_device="$1"

    # 格式化ZRAM设备
    if ! mkswap "/dev/${zram_device}" > /dev/null 2>&1; then
        handle_error "ZRAM_SWAP" "格式化 ZRAM 失败"
        return 1
    fi

    # 启用Swap
    if ! swapon -p "$(get_config 'zram_priority')" "/dev/${zram_device}" > /dev/null 2>&1; then
        handle_error "ZRAM_SWAP" "启用 ZRAM 失败"
        return 1
    fi

    # 清除缓存
    set_config "_zram_device_cache" ""
    clear_cache

    ZRAM_ENABLED=true
    log_info "ZRAM Swap 已启用: ${zram_device}"
    return 0
}

# ==============================================================================
# 准备ZRAM参数
# @param algorithm: 压缩算法
# @param mode: 策略模式
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
        handle_error "ZRAM_PARAMS" "ZRAM 参数验证失败"
        return 1
    fi

    echo "${algorithm} ${mode} ${zram_ratio} ${phys_limit} ${swap_size} ${swappiness} ${dirty_ratio} ${min_free} ${zram_size}"
    return 0
}

# ==============================================================================
# 保存ZRAM配置
# @param algorithm: 压缩算法
# @param mode: 策略模式
# @param zram_ratio: ZRAM大小比例
# @param zram_size: ZRAM大小（MB）
# @param phys_limit: 物理内存限制（MB）
# @return: 0为成功，1为失败
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
# Z-Panel Pro ZRAM 配置
# ============================================================================
# 自动生成，请勿手动修改
#
# ALGORITHM: ZRAM 压缩算法 (auto/zstd/lz4/lzo)
# STRATEGY: 使用的策略模式
# PERCENT: ZRAM 大小占物理内存的百分比
# PRIORITY: Swap 优先级
# SIZE: ZRAM 设备大小（MB）
# PHYS_LIMIT: 物理内存使用限制（MB）
# ============================================================================

ALGORITHM=${algorithm}
STRATEGY=${mode}
PERCENT=${zram_ratio}
PRIORITY=$(get_config 'zram_priority')
SIZE=${zram_size}
PHYS_LIMIT=${phys_limit}
EOF

    if save_config_file "${ZRAM_CONFIG_FILE}" "${content}"; then
        log_info "ZRAM 配置已保存"
        return 0
    else
        log_error "ZRAM 配置保存失败"
        return 1
    fi
}

# ==============================================================================
# 创建ZRAM服务
# @return: 0为成功，1为失败
# ==============================================================================
create_zram_service() {
    log_info "创建 ZRAM 持久化服务..."

    local service_script="${INSTALL_DIR}/zram-start.sh"

    # 创建启动脚本
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

    log "开始启动 ZRAM 服务..."

    modprobe zram 2>/dev/null || {
        log "无法加载 zram 模块"
        exit 1
    }

    if [[ -e /sys/block/zram0/reset ]]; then
        echo 1 > /sys/block/zram0/reset 2>/dev/null || true
        log "已重置 ZRAM 设备"
    fi

    if [[ -e /sys/block/zram0/comp_algorithm ]]; then
        echo "$ALGORITHM" > /sys/block/zram0/comp_algorithm 2>/dev/null || true
        log "设置压缩算法: $ALGORITHM"
    fi

    local zram_bytes=$((SIZE * 1024 * 1024)) || true
    echo "$zram_bytes" > /sys/block/zram0/disksize 2>/dev/null || {
        log "设置 ZRAM 大小失败"
        exit 1
    }
    log "设置 ZRAM 大小: ${SIZE}MB"

    if [[ -e /sys/block/zram0/mem_limit ]]; then
        local phys_limit_bytes=$((PHYS_LIMIT * 1024 * 1024)) || true
        echo "$phys_limit_bytes" > /sys/block/zram0/mem_limit 2>/dev/null || true
        log "设置物理内存限制: ${PHYS_LIMIT}MB"
    fi

    mkswap /dev/zram0 > /dev/null 2>&1 || {
        log "格式化 ZRAM 失败"
        exit 1
    }

    swapon -p $PRIORITY /dev/zram0 > /dev/null 2>&1 || {
        log "启用 ZRAM 失败"
        exit 1
    }

    log "ZRAM 服务启动成功"
else
    log "配置文件不存在: $CONF_DIR/zram.conf"
    exit 1
fi

if [[ -f "$CONF_DIR/kernel.conf" ]]; then
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^# ]] && continue
        [[ -z "$key" ]] && continue
        sysctl -w "$key=$value" > /dev/null 2>&1 || log "设置 $key 失败"
    done < "$CONF_DIR/kernel.conf"
fi
SERVICE_SCRIPT

    chmod 700 "${service_script}" 2>/dev/null || true

    # 创建systemd服务
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

        log_info "systemd 服务已创建并已启用"
    fi

    return 0
}

# ==============================================================================
# 启动ZRAM服务
# @return: 0为成功，1为失败
# ==============================================================================
start_zram_service() {
    if check_systemd; then
        systemctl daemon-reload > /dev/null 2>&1
        if systemctl is-active --quiet zram.service 2>/dev/null; then
            log_info "zram.service 已在运行，跳过启动"
        else
            if systemctl start zram.service > /dev/null 2>&1; then
                log_info "zram.service 已启动"
            else
                log_warn "zram.service 启动失败，但 ZRAM 已在当前会话中生成"
            fi
        fi
    fi
}

# ==============================================================================
# 配置ZRAM（主函数）
# @param algorithm: 压缩算法（默认auto）
# @param mode: 策略模式（默认当前STRATEGY_MODE）
# @return: 0为成功，1为失败
# ==============================================================================
configure_zram() {
    local algorithm="${1:-auto}"
    local mode="${2:-${STRATEGY_MODE}}"

    log_info "开始配置 ZRAM (策略: ${mode})..."

    # 准备参数
    local params
    params=$(prepare_zram_params "${algorithm}" "${mode}") || return 1
    read -r algorithm mode zram_ratio phys_limit swap_size swappiness dirty_ratio min_free zram_size <<< "${params}"

    # 检查并安装zram-tools
    if ! check_command zramctl; then
        log_info "安装 zram-tools..."
        install_packages zram-tools zram-config zstd lz4 lzop || {
            handle_error "ZRAM_CONFIG" "安装 zram-tools 失败"
            return 1
        }
    fi

    # 初始化设备
    local zram_device
    zram_device=$(initialize_zram_device) || {
        handle_error "ZRAM_CONFIG" "初始化 ZRAM 设备失败"
        return 1
    }
    log_info "使用 ZRAM 设备: ${zram_device}"

    # 配置压缩
    algorithm=$(configure_zram_compression "${zram_device}" "${algorithm}")

    # 配置限制
    configure_zram_limits "${zram_device}" "${zram_size}" "${phys_limit}" || {
        handle_error "ZRAM_CONFIG" "配置 ZRAM 限制失败"
        return 1
    }

    # 启用Swap
    enable_zram_swap "${zram_device}" || {
        handle_error "ZRAM_CONFIG" "启用 ZRAM swap 失败"
        return 1
    }

    # 保存配置
    save_zram_config "${algorithm}" "${mode}" "${zram_ratio}" "${zram_size}" "${phys_limit}" || {
        log_warn "保存 ZRAM 配置失败"
    }

    # 创建服务
    create_zram_service || {
        log_warn "创建 ZRAM 服务失败"
    }

    # 启动服务
    start_zram_service

    set_config "_zram_device_cache" ""

    log_info "ZRAM 配置成功: ${algorithm}, ${zram_size}MB, 优先级 $(get_config 'zram_priority')"

    return 0
}

# ==============================================================================
# 停用ZRAM
# @return: 0为成功
# ==============================================================================
disable_zram() {
    log_info "停用 ZRAM..."

    # 停用所有ZRAM swap
    for device in $(swapon --show=NAME --noheadings 2>/dev/null | grep zram); do
        swapoff "${device}" 2>/dev/null || true
    done

    # 重置设备
    if [[ -e /sys/block/zram0/reset ]]; then
        echo 1 > /sys/block/zram0/reset 2>/dev/null || true
    fi

    # 禁用systemd服务
    if check_systemd; then
        systemctl disable zram.service > /dev/null 2>&1
        rm -f /etc/systemd/system/zram.service
        systemctl daemon-reload > /dev/null 2>&1
    fi

    # 清除缓存
    set_config "_zram_device_cache" ""
    clear_cache

    ZRAM_ENABLED=false
    log_info "ZRAM 已停用"
}