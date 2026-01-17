#!/bin/bash
# ==============================================================================
# Z-Panel Pro V8.0 - 文件锁模块
# ==============================================================================
# @description    原子文件锁机制，防止竞态条件
# @version       8.0.0-Enterprise
# @author        Z-Panel Team
# @license       MIT License
# ==============================================================================

# ==============================================================================
# 锁状态变量
# ==============================================================================
declare -gA LOCKS_HELD=()
declare -gA LOCK_TIMEOUTS=()
declare -g LOCK_ACQUISITION_TIMEOUT=30
declare -g LOCK_STALE_THRESHOLD=3600

# ==============================================================================
# 获取锁
# @param lock_file: 锁文件路径
# @param timeout: 获取超时时间（秒），默认30秒
# @return: 0成功或1失败
# ==============================================================================
acquire_lock() {
    local lock_file="${1:-${LOCK_FILE}}"
    local timeout="${2:-${LOCK_ACQUISITION_TIMEOUT}}"
    local lock_fd=200
    local start_time=$(date +%s)

    # 验证锁文件路径
    if ! validate_path "${lock_file}"; then
        log_error "无效的锁文件路径: ${lock_file}"
        return 1
    fi

    # 创建锁目录
    mkdir -p "$(dirname "${lock_file}")" 2>/dev/null || {
        log_error "无法创建锁目录: $(dirname "${lock_file}")"
        return 1
    }

    # 检查并清理过期锁
    if [[ -f "${lock_file}" ]]; then
        local lock_mtime
        lock_mtime=$(stat -c %Y "${lock_file}" 2>/dev/null || stat -f %m "${lock_file}" 2>/dev/null || echo "0")
        local current_time=$(date +%s)
        local lock_age=$((current_time - lock_mtime))

        if [[ ${lock_age} -gt ${LOCK_STALE_THRESHOLD} ]]; then
            log_warn "检测到过期锁（${lock_age}秒），将清理"
            rm -f "${lock_file}" 2>/dev/null || true
        fi
    fi

    # 尝试获取锁
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [[ ${elapsed} -ge ${timeout} ]]; then
            log_error "获取锁超时: ${lock_file}"
            return 1
        fi

        # 尝试打开文件描述符
        if eval "exec ${lock_fd}>\"${lock_file}\"" 2>/dev/null; then
            if flock -n ${lock_fd} 2>/dev/null; then
                # 写入当前PID和时间戳
                echo "$$|$(date +%s)" > "${lock_file}" 2>/dev/null

                # 记录锁信息
                LOCKS_HELD["${lock_file}"]="${lock_fd}"
                LOCK_TIMEOUTS["${lock_file}"]=${timeout}

                log_debug "已获取锁: ${lock_file} (FD: ${lock_fd})"
                return 0
            fi
        fi

        # 检查锁持有者
        if [[ -f "${lock_file}" ]]; then
            local lock_info
            lock_info=$(cat "${lock_file}" 2>/dev/null || echo "")
            local lock_pid="${lock_info%%|*}"
            local lock_time="${lock_info##*|}"

            if validate_pid "${lock_pid}" && [[ -n "${lock_time}" ]]; then
                log_error "锁已被持有 (PID: ${lock_pid}, 持续时间: $(format_duration $(( $(date +%s) - lock_time ))) )"
            else
                log_warn "锁持有者已不存在，将清理"
                rm -f "${lock_file}" 2>/dev/null || true
                continue
            fi
        fi

        # 等待后重试
        sleep 1
    done
}

# ==============================================================================
# 释放锁
# @param lock_file: 锁文件路径
# @return: 0成功
# ==============================================================================
release_lock() {
    local lock_file="${1:-${LOCK_FILE}}"
    local lock_fd="${LOCKS_HELD[${lock_file}]:-200}"

    if [[ -n "${lock_fd}" ]] && [[ ${lock_fd} -gt 0 ]]; then
        flock -u ${lock_fd} 2>/dev/null || true
        eval "exec ${lock_fd}>&-" 2>/dev/null || true
    fi

    rm -f "${lock_file}" 2>/dev/null || true

    # 清除锁记录
    unset LOCKS_HELD["${lock_file}"]
    unset LOCK_TIMEOUTS["${lock_file}"]

    log_debug "已释放锁: ${lock_file}"
    return 0
}

# ==============================================================================
# 检查是否持有锁
# @param lock_file: 锁文件路径
# @return: 0持有或1未持有
# ==============================================================================
is_lock_held() {
    local lock_file="${1:-${LOCK_FILE}}"
    local lock_fd="${LOCKS_HELD[${lock_file}]:-200}"

    [[ -n "${lock_fd}" ]] && [[ ${lock_fd} -gt 0 ]] && flock -n ${lock_fd} 2>/dev/null
}

# ==============================================================================
# 获取锁持有者PID
# @param lock_file: 锁文件路径
# @return: PID字符串
# ==============================================================================
get_lock_pid() {
    local lock_file="${1:-${LOCK_FILE}}"

    if [[ -f "${lock_file}" ]]; then
        local lock_info
        lock_info=$(cat "${lock_file}" 2>/dev/null || echo "")
        echo "${lock_info%%|*}"
    else
        echo ""
    fi
}

# ==============================================================================
# 获取锁详细信息
# @param lock_file: 锁文件路径
# @return: JSON格式的锁信息
# ==============================================================================
get_lock_info() {
    local lock_file="${1:-${LOCK_FILE}}"

    if [[ -f "${lock_file}" ]]; then
        local lock_info
        lock_info=$(cat "${lock_file}" 2>/dev/null || echo "")
        local lock_pid="${lock_info%%|*}"
        local lock_time="${lock_info##*|}"
        local lock_age=$(( $(date +%s) - lock_time ))

        cat <<EOF
{
    "file": "${lock_file}",
    "pid": ${lock_pid:-0},
    "acquired_time": ${lock_time:-0},
    "age_seconds": ${lock_age:-0},
    "is_process_running": $(is_process_running "${lock_pid}" && echo "true" || echo "false"),
    "is_held_by_current": $(is_lock_held "${lock_file}" && echo "true" || echo "false")
}
EOF
    else
        cat <<EOF
{
    "file": "${lock_file}",
    "status": "not_locked"
}
EOF
    fi
}

# ==============================================================================
# 强制释放锁（危险操作）
# @param lock_file: 锁文件路径
# @param force: 是否强制释放，默认false
# @return: 0成功或1失败
# ==============================================================================
force_release_lock() {
    local lock_file="${1:-${LOCK_FILE}}"
    local force="${2:-false}"

    log_warn "尝试强制释放锁: ${lock_file}"

    local lock_pid
    lock_pid=$(get_lock_pid "${lock_file}")

    if [[ -n "${lock_pid}" ]] && is_process_running "${lock_pid}"; then
        log_warn "锁持有者进程 ${lock_pid} 仍在运行"

        if [[ "${force}" != "true" ]]; then
            if ! ui_confirm "确认强制释放？这可能导致数据损坏"; then
                return 1
            fi
        fi
    fi

    release_lock "${lock_file}"
    log_info "锁已强制释放: ${lock_file}"
    return 0
}

# ==============================================================================
# 释放所有锁
# ==============================================================================
release_all_locks() {
    log_debug "释放所有锁..."

    for lock_file in "${!LOCKS_HELD[@]}"; do
        release_lock "${lock_file}"
    done

    return 0
}

# ==============================================================================
# 清理过期锁
# @param lock_dir: 锁文件目录
# @return: 清理数量
# ==============================================================================
cleanup_stale_locks() {
    local lock_dir="${1:-$(dirname "${LOCK_FILE}")}"
    local cleaned=0

    if [[ ! -d "${lock_dir}" ]]; then
        return 0
    fi

    while IFS= read -r -d '' lock_file; do
        local lock_mtime
        lock_mtime=$(stat -c %Y "${lock_file}" 2>/dev/null || stat -f %m "${lock_file}" 2>/dev/null || echo "0")
        local current_time=$(date +%s)
        local lock_age=$((current_time - lock_mtime))

        if [[ ${lock_age} -gt ${LOCK_STALE_THRESHOLD} ]]; then
            local lock_info
            lock_info=$(cat "${lock_file}" 2>/dev/null || echo "")
            local lock_pid="${lock_info%%|*}"

            if ! is_process_running "${lock_pid}"; then
                log_debug "清理过期锁: ${lock_file} (持有者已终止)"
                rm -f "${lock_file}" 2>/dev/null || true
                ((cleaned++)) || true
            fi
        fi
    done < <(find "${lock_dir}" -name "*.lock" -print0 2>/dev/null)

    log_debug "已清理 ${cleaned} 个过期锁"
    return 0
}

# ==============================================================================
# 设置锁获取超时
# @param timeout: 超时时间（秒）
# ==============================================================================
set_lock_timeout() {
    LOCK_ACQUISITION_TIMEOUT="${1:-30}"
    log_debug "锁获取超时已设置为: ${LOCK_ACQUISITION_TIMEOUT}秒"
}

# ==============================================================================
# 设置过期锁阈值
# @param threshold: 过期时间（秒）
# ==============================================================================
set_stale_lock_threshold() {
    LOCK_STALE_THRESHOLD="${1:-3600}"
    log_debug "过期锁阈值已设置为: ${LOCK_STALE_THRESHOLD}秒"
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f acquire_lock
export -f release_lock
export -f is_lock_held
export -f get_lock_pid
export -f get_lock_info
export -f force_release_lock
export -f release_all_locks
export -f cleanup_stale_locks
export -f set_lock_timeout
export -f set_stale_lock_threshold
