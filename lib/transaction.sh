#!/bin/bash
# ==============================================================================
# Z-Panel Pro - 事务管理模块
# ==============================================================================
# @description    事务回滚机制
# @version       7.2.0-Security
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 事务状态
# ==============================================================================

declare -g TRANSACTION_ACTIVE=false
declare -gA TRANSACTION_BACKUP=()
declare -g TRANSACTION_ROLLBACK_HOOKS=()
declare -g TRANSACTION_NAME=""

# ==============================================================================
# 事务控制
# ==============================================================================

# 开始事务
transaction_begin() {
    local name="${1:-transaction}"

    if [[ "${TRANSACTION_ACTIVE}" == "true" ]]; then
        log_error "事务已在进行中: ${TRANSACTION_NAME}"
        return 1
    fi

    TRANSACTION_ACTIVE=true
    TRANSACTION_NAME="${name}"
    TRANSACTION_BACKUP=()
    TRANSACTION_ROLLBACK_HOOKS=()

    log_debug "事务开始: ${name}"
    return 0
}

# 提交事务
transaction_commit() {
    if [[ "${TRANSACTION_ACTIVE}" != "true" ]]; then
        log_warn "没有活动的事务"
        return 0
    fi

    log_debug "事务提交: ${TRANSACTION_NAME}"

    # 删除备份文件
    for file in "${!TRANSACTION_BACKUP[@]}"; do
        local backup_file="${TRANSACTION_BACKUP[${file}]}"
        if [[ -f "${backup_file}" ]]; then
            rm -f "${backup_file}" 2>/dev/null || true
            log_debug "删除备份: ${backup_file}"
        fi
    done

    # 清理状态
    TRANSACTION_ACTIVE=false
    TRANSACTION_NAME=""
    TRANSACTION_BACKUP=()
    TRANSACTION_ROLLBACK_HOOKS=()

    return 0
}

# 回滚事务
transaction_rollback() {
    if [[ "${TRANSACTION_ACTIVE}" != "true" ]]; then
        log_warn "没有活动的事务"
        return 0
    fi

    log_warn "事务回滚: ${TRANSACTION_NAME}"

    # 执行回滚钩子
    for hook in "${TRANSACTION_ROLLBACK_HOOKS[@]}"; do
        log_debug "执行回滚钩子: ${hook}"
        ${hook} 2>/dev/null || true
    done

    # 恢复备份文件
    for file in "${!TRANSACTION_BACKUP[@]}"; do
        local backup_file="${TRANSACTION_BACKUP[${file}]}"
        if [[ -f "${backup_file}" ]]; then
            if mv "${backup_file}" "${file}" 2>/dev/null; then
                log_debug "恢复文件: ${file}"
            else
                log_warn "无法恢复文件: ${file}"
            fi
        fi
    done

    # 清理状态
    TRANSACTION_ACTIVE=false
    TRANSACTION_NAME=""
    TRANSACTION_BACKUP=()
    TRANSACTION_ROLLBACK_HOOKS=()

    return 0
}

# 事务执行器
transaction_execute() {
    local func="$1"
    local name="${2:-transaction}"
    shift 2

    transaction_begin "${name}" || return 1

    if ${func} "$@"; then
        transaction_commit
        return 0
    else
        transaction_rollback
        return 1
    fi
}

# ==============================================================================
# 文件操作
# ==============================================================================

# 备份文件
transaction_backup() {
    local file="$1"

    if [[ "${TRANSACTION_ACTIVE}" != "true" ]]; then
        log_warn "没有活动的事务，跳过备份"
        return 0
    fi

    if [[ ! -f "${file}" ]]; then
        log_debug "文件不存在，跳过备份: ${file}"
        return 0
    fi

    # 创建备份文件
    local backup_file
    backup_file=$(mktemp "${file}.backup.XXXXXX") || {
        log_error "无法创建备份文件: ${file}"
        return 1
    }

    # 复制文件
    if ! cp "${file}" "${backup_file}"; then
        rm -f "${backup_file}"
        log_error "无法备份文件: ${file}"
        return 1
    fi

    # 设置备份文件权限
    chmod 600 "${backup_file}" 2>/dev/null || true

    # 记录备份
    TRANSACTION_BACKUP["${file}"]="${backup_file}"
    log_debug "备份文件: ${file} -> ${backup_file}"

    return 0
}

# 原子写入文件
transaction_write_file() {
    local file="$1"
    local content="$2"

    # 备份原文件
    if [[ -f "${file}" ]]; then
        transaction_backup "${file}" || return 1
    fi

    # 创建目录
    mkdir -p "$(dirname "${file}")" || return 1

    # 创建临时文件
    local temp_file
    temp_file=$(mktemp "${file}.tmp.XXXXXX") || return 1

    # 写入内容
    if ! echo "${content}" > "${temp_file}"; then
        rm -f "${temp_file}"
        return 1
    fi

    # 设置权限
    chmod 600 "${temp_file}" 2>/dev/null || true

    # 原子移动
    if ! mv "${temp_file}" "${file}"; then
        rm -f "${temp_file}"
        return 1
    fi

    log_debug "写入文件: ${file}"
    return 0
}

# ==============================================================================
# 钩子管理
# ==============================================================================

# 添加回滚钩子
transaction_add_rollback() {
    local hook="$1"

    if [[ "${TRANSACTION_ACTIVE}" != "true" ]]; then
        log_warn "没有活动的事务，跳过钩子"
        return 0
    fi

    TRANSACTION_ROLLBACK_HOOKS+=("${hook}")
    log_debug "添加回滚钩子: ${hook}"

    return 0
}

# 添加提交钩子
transaction_add_commit() {
    local hook="$1"

    if [[ "${TRANSACTION_ACTIVE}" != "true" ]]; then
        log_warn "没有活动的事务，跳过钩子"
        return 0
    fi

    # 将提交钩子包装为回滚钩子的反向操作
    local rollback_hook="transaction_undo_${#TRANSACTION_ROLLBACK_HOOKS[@]}"

    # 保存原始提交钩子
    declare -g "TRANSACTION_COMMIT_HOOK_${#TRANSACTION_ROLLBACK_HOOKS[@]}=${hook}"

    log_debug "添加提交钩子: ${hook}"
    return 0
}

# ==============================================================================
# 事务状态查询
# ==============================================================================

# 检查事务是否活动
transaction_is_active() {
    [[ "${TRANSACTION_ACTIVE}" == "true" ]]
}

# 获取事务名称
transaction_get_name() {
    echo "${TRANSACTION_NAME}"
}

# 获取备份文件列表
transaction_get_backups() {
    for file in "${!TRANSACTION_BACKUP[@]}"; do
        echo "${file} -> ${TRANSACTION_BACKUP[${file}]}"
    done
}

# 获取回滚钩子列表
transaction_get_hooks() {
    printf '%s\n' "${TRANSACTION_ROLLBACK_HOOKS[@]}"
}
