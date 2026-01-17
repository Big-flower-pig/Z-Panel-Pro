#!/bin/bash
# ==============================================================================
# Z-Panel Pro - 安全文件锁模块
# ==============================================================================
# @description    原子文件锁机制，防止竞态条件
# @version       7.2.0-Security
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 锁配置
# ==============================================================================

readonly LOCK_DIR="${LOCK_DIR:-/tmp}"
readonly LOCK_FILE="${LOCK_DIR}/zpanel.lock"
readonly LOCK_PID_FILE="${LOCK_DIR}/zpanel.pid"
readonly LOCK_TIMEOUT="${LOCK_TIMEOUT:-30}"
readonly LOCK_RETRY_DELAY="${LOCK_RETRY_DELAY:-1}"
readonly LOCK_FD=200

# ==============================================================================
# 获取文件锁（原子操作）
# ==============================================================================

acquire_lock() {
    local lock_timeout="${1:-${LOCK_TIMEOUT}}"
    local lock_retry_delay="${2:-${LOCK_RETRY_DELAY}}"
    local lock_retries=0
    local lock_file="${LOCK_FILE}"

    log_debug "尝试获取文件锁..."

    # 使用原子操作获取锁
    while [[ ${lock_retries} -lt ${lock_timeout} ]]; do
        # 使用 set -o noclobber 实现原子文件创建
        if (set -o noclobber; echo $$ > "${lock_file}") 2>/dev/null; then
            # 成功获取锁

            # 打开文件描述符用于 flock
            if ! eval "exec ${LOCK_FD}>\"${lock_file}\"" 2>/dev/null; then
                # 清理失败的锁文件
                rm -f "${lock_file}" 2>/dev/null
                ((lock_retries++)) || true
                sleep ${lock_retry_delay}
                continue
            fi

            # 使用 flock 增强锁机制
            if ! flock -n "${LOCK_FD}" 2>/dev/null; then
                # flock 失败，清理并重试
                rm -f "${lock_file}" 2>/dev/null
                ((lock_retries++)) || true
                sleep ${lock_retry_delay}
                continue
            fi

            # 验证锁文件内容
            local lock_pid
            lock_pid=$(cat "${lock_file}" 2>/dev/null || echo "unknown")

            if [[ "${lock_pid}" != "$$" ]]; then
                # 竞态条件：锁被其他进程获取
                rm -f "${lock_file}" 2>/dev/null
                ((lock_retries++)) || true
                sleep ${lock_retry_delay}
                continue
            fi

            # 写入 PID 文件
            echo $$ > "${LOCK_PID_FILE}" 2>/dev/null || true
            chmod 600 "${LOCK_PID_FILE}" 2>/dev/null || true

            # 设置清理陷阱
            trap 'release_lock; exit $?' EXIT INT TERM QUIT HUP

            log_debug "文件锁已获取 (PID: $$, FD: ${LOCK_FD})"
            return 0
        else
            # 锁文件已存在
            local existing_pid
            existing_pid=$(cat "${lock_file}" 2>/dev/null || echo "unknown")

            # 检查持有锁的进程是否还在运行
            if [[ "${existing_pid}" =~ ^[0-9]+$ ]] && \
               [[ -d "/proc/${existing_pid}" ]]; then
                # 进程仍在运行
                local elapsed_time
                elapsed_time=$(get_lock_age "${lock_file}")

                log_error "脚本已在运行 (PID: ${existing_pid}, 锁年龄: ${elapsed_time}s)"
                log_error "如需强制启动，请运行: zpanel --force-unlock"
                return 1
            else
                # 持有锁的进程已死，清理锁文件
                log_warn "清理死锁 (PID: ${existing_pid})"
                cleanup_stale_lock
                ((lock_retries++)) || true
                sleep ${lock_retry_delay}
                continue
            fi
        fi
    done

    log_error "获取文件锁超时 (${lock_timeout}s)"
    return 1
}

# ==============================================================================
# 释放文件锁
# ==============================================================================

release_lock() {
    local lock_file="${LOCK_FILE}"
    local lock_pid_file="${LOCK_PID_FILE}"

    # 验证锁文件属于当前进程
    if [[ -f "${lock_file}" ]]; then
        local lock_pid
        lock_pid=$(cat "${lock_file}" 2>/dev/null || echo "unknown")

        if [[ "${lock_pid}" == "$$" ]]; then
            # 释放 flock
            flock -u "${LOCK_FD}" 2>/dev/null || true

            # 关闭文件描述符
            eval "exec ${LOCK_FD}>&-" 2>/dev/null || true

            # 删除锁文件
            rm -f "${lock_file}" 2>/dev/null
            rm -f "${lock_pid_file}" 2>/dev/null

            log_debug "文件锁已释放 (PID: $$)"
        else
            log_warn "锁文件不属于当前进程 (锁PID: ${lock_pid}, 当前PID: $$)"
        fi
    fi

    # 清理陷阱
    trap - EXIT INT TERM QUIT HUP
}

# ==============================================================================
# 检查锁状态
# ==============================================================================

# 检查是否持有锁（原子操作，避免TOCTOU）
is_lock_held() {
    local lock_file="${LOCK_FILE}"

    # 使用原子操作：直接尝试读取并验证，避免单独检查文件存在性
    local lock_pid
    lock_pid=$(cat "${lock_file}" 2>/dev/null || echo "")

    # 如果读取失败或PID为空，认为未持有锁
    [[ -z "${lock_pid}" ]] && return 1

    # 验证PID格式
    [[ ! "${lock_pid}" =~ ^[0-9]+$ ]] && return 1

    # 检查是否为当前进程
    [[ "${lock_pid}" == "$$" ]]
}

# 检查锁是否被其他进程持有（原子操作，避免TOCTOU）
is_lock_active() {
    local lock_file="${LOCK_FILE}"

    # 使用原子操作：直接尝试读取并验证
    local lock_pid
    lock_pid=$(cat "${lock_file}" 2>/dev/null || echo "")

    # 如果读取失败或PID为空，认为锁未被持有
    [[ -z "${lock_pid}" ]] && return 1

    # 验证 PID 格式
    [[ ! "${lock_pid}" =~ ^[0-9]+$ ]] && return 1

    # 检查进程是否运行（使用kill -0进行原子检查）
    kill -0 "${lock_pid}" 2>/dev/null
}

# ==============================================================================
# 锁信息查询
# ==============================================================================

# 获取锁文件中的 PID（原子操作）
get_lock_pid() {
    local lock_file="${LOCK_FILE}"

    # 直接尝试读取，避免单独检查文件存在性
    cat "${lock_file}" 2>/dev/null || echo ""
}

# 获取锁年龄（秒）（原子操作）
get_lock_age() {
    local lock_file="${1:-${LOCK_FILE}}"

    # 直接尝试获取文件时间，避免单独检查文件存在性
    local lock_time
    lock_time=$(stat -c "%Y" "${lock_file}" 2>/dev/null || stat -f "%m" "${lock_file}" 2>/dev/null || echo "0")

    # 如果stat失败，返回0
    [[ "${lock_time}" == "0" ]] && { echo "0"; return; }

    local current_time
    current_time=$(date +%s)

    echo $((current_time - lock_time))
}

# 获取锁信息（原子操作）
get_lock_info() {
    local lock_file="${LOCK_FILE}"

    # 直接尝试读取，避免单独检查文件存在性
    local lock_pid
    lock_pid=$(cat "${lock_file}" 2>/dev/null || echo "")

    if [[ -z "${lock_pid}" ]]; then
        echo "锁文件不存在或为空"
        return 1
    fi

    local lock_age
    lock_age=$(get_lock_age "${lock_file}")

    local lock_time
    lock_time=$(stat -c "%y" "${lock_file}" 2>/dev/null || stat -f "%Sm" "${lock_file}" 2>/dev/null || echo "unknown")

    cat <<EOF
锁文件: ${lock_file}
持有进程: ${lock_pid}
锁年龄: ${lock_age} 秒
创建时间: ${lock_time}
EOF

    # 检查进程状态（使用kill -0进行原子检查）
    if [[ "${lock_pid}" =~ ^[0-9]+$ ]]; then
        if kill -0 "${lock_pid}" 2>/dev/null; then
            echo "进程状态: 运行中"

            # 显示进程信息
            if [[ -f "/proc/${lock_pid}/cmdline" ]]; then
                local cmdline
                cmdline=$(cat "/proc/${lock_pid}/cmdline" 2>/dev/null | tr '\0' ' ' | head -c 100)
                echo "命令行: ${cmdline}"
            fi
        else
            echo "进程状态: 已终止（死锁）"
        fi
    else
        echo "进程状态: 未知"
    fi
}

# ==============================================================================
# 锁清理
# ==============================================================================

# 清理死锁（使用原子操作避免TOCTOU）
cleanup_stale_lock() {
    local lock_file="${LOCK_FILE}"

    # 直接尝试读取PID
    local lock_pid
    lock_pid=$(cat "${lock_file}" 2>/dev/null || echo "")

    # 如果读取失败，清理可能损坏的锁文件
    if [[ -z "${lock_pid}" ]]; then
        rm -f "${lock_file}" 2>/dev/null
        rm -f "${LOCK_PID_FILE}" 2>/dev/null
        return 0
    fi

    # 验证 PID 格式
    [[ ! "${lock_pid}" =~ ^[0-9]+$ ]] && {
        rm -f "${lock_file}" 2>/dev/null
        rm -f "${LOCK_PID_FILE}" 2>/dev/null
        return 0
    }

    # 使用kill -0进行原子检查进程是否运行
    if kill -0 "${lock_pid}" 2>/dev/null; then
        log_error "进程 ${lock_pid} 仍在运行，无法清理锁"
        return 1
    fi

    # 进程已死，清理锁（使用原子操作）
    log_info "清理死锁 (PID: ${lock_pid})"
    rm -f "${lock_file}" 2>/dev/null
    rm -f "${LOCK_PID_FILE}" 2>/dev/null

    return 0
}

# 强制释放锁（危险操作，使用原子操作避免TOCTOU）
force_release_lock() {
    local lock_file="${LOCK_FILE}"

    log_warn "强制释放文件锁..."

    # 显示锁信息
    get_lock_info

    # 直接尝试读取PID
    local lock_pid
    lock_pid=$(cat "${lock_file}" 2>/dev/null || echo "")

    # 使用kill -0进行原子检查进程状态
    if [[ "${lock_pid}" =~ ^[0-9]+$ ]] && kill -0 "${lock_pid}" 2>/dev/null; then
        log_warn "锁文件中的进程 ${lock_pid} 仍在运行"

        # 询问确认
        if ! ui_confirm "确认强制释放？这可能导致数据损坏"; then
            return 1
        fi
    fi

    # 释放锁（原子操作）
    flock -u "${LOCK_FD}" 2>/dev/null || true
    eval "exec ${LOCK_FD}>&-" 2>/dev/null || true
    rm -f "${lock_file}" 2>/dev/null
    rm -f "${LOCK_PID_FILE}" 2>/dev/null

    log_info "文件锁已强制释放"
    return 0
}

# ==============================================================================
# 锁超时处理
# ==============================================================================

# 设置锁超时
set_lock_timeout() {
    local timeout="$1"

    if validate_positive_integer "${timeout}"; then
        declare -gx LOCK_TIMEOUT="${timeout}"
        log_debug "锁超时设置为: ${timeout}s"
    else
        log_error "无效的锁超时: ${timeout}"
        return 1
    fi
}

# 获取锁超时
get_lock_timeout() {
    echo "${LOCK_TIMEOUT}"
}
