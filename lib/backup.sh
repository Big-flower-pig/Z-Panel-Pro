#!/bin/bash
# ==============================================================================
# Z-Panel Pro - 备份与回滚模�?# ==============================================================================
# @description    系统配置备份与恢�?# @version       7.1.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 创建备份
# @return: 备份路径
# ==============================================================================
create_backup() {
    log_info "创建系统备份..."

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="${BACKUP_DIR}/backup_${timestamp}"

    # 创建备份目录
    if ! mkdir -p "${backup_path}"; then
        handle_error "BACKUP" "无法创建备份目录: ${backup_path}"
        return 1
    fi

    # 设置目录权限
    chmod 700 "${backup_path}" 2>/dev/null || true

    # 备份文件列表
    local files=(
        "/etc/sysctl.conf"
        "/etc/fstab"
    )

    local backed_up=0
    for file in "${files[@]}"; do
        if [[ -f "${file}" ]]; then
            local filename
            filename=$(basename "${file}")

            # 验证文件�?            if ! validate_filename "${filename}"; then
                log_warn "跳过不安全的文件�? ${filename}"
                continue
            fi

            if cp "${file}" "${backup_path}/" 2>/dev/null; then
                ((backed_up++)) || true
                log_info "已备�? ${file}"
            else
                log_warn "备份失败: ${file}"
            fi
        fi
    done

    # 保存备份信息
    local info_file="${backup_path}/info.txt"
    local content
    cat <<EOF
backup_time=${timestamp}
backup_version=${VERSION}
distro=${SYSTEM_INFO[distro]}
distro_version=${SYSTEM_INFO[version]}
strategy=${STRATEGY_MODE}
memory_mb=${SYSTEM_INFO[total_memory_mb]}
cpu_cores=${SYSTEM_INFO[cpu_cores]}
files_backed_up=${backed_up}
EOF

    if save_config_file "${info_file}" "${content}"; then
        log_info "备份完成: ${backup_path} (�?${backed_up} 个文�?"
        echo "${backup_path}"
        return 0
    else
        log_error "备份信息保存失败"
        return 1
    fi
}

# ==============================================================================
# 还原备份
# @param backup_path: 备份目录路径
# @return: 0为成功，1为失�?# ==============================================================================
restore_backup() {
    local backup_path="$1"

    # 验证备份路径
    if [[ ! -d "${backup_path}" ]]; then
        handle_error "RESTORE" "备份目录不存�? ${backup_path}"
        return 1
    fi

    # 验证备份信息文件
    if [[ ! -f "${backup_path}/info.txt" ]]; then
        handle_error "RESTORE" "备份信息文件缺失: ${backup_path}/info.txt"
        return 1
    fi

    log_info "还原系统备份: ${backup_path}"

    local restored=0
    local failed=0

    # 遍历备份目录中的文件
    for file in "${backup_path}"/*; do
        if [[ -f "${file}" ]]; then
            local filename
            filename=$(basename "${file}")

            # 跳过信息文件
            if [[ "${filename}" == "info.txt" ]]; then
                continue
            fi

            # 验证文件�?            if ! validate_filename "${filename}"; then
                log_warn "跳过不安全的文件�? ${filename}"
                continue
            fi

            local target="/etc/${filename}"

            # 备份原文�?            if [[ -f "${target}" ]]; then
                local backup_target="${target}.bak.$(date +%Y%m%d_%H%M%S)"
                if ! cp "${target}" "${backup_target}" 2>/dev/null; then
                    log_warn "无法备份原文�? ${target}"
                else
                    log_info "原文件已备份: ${backup_target}"
                fi
            fi

            # 还原文件
            if cp "${file}" "${target}" 2>/dev/null; then
                ((restored++)) || true
                log_info "已还�? ${filename}"
            else
                ((failed++)) || true
                log_error "还原失败: ${filename}"
            fi
        fi
    done

    log_info "还原完成: 成功 ${restored} 个文件，失败 ${failed} 个文�?

    # 应用内核参数
    if [[ -f /etc/sysctl.conf ]]; then
        log_info "应用内核参数..."
        sysctl -p > /dev/null 2>&1 || true
    fi

    return 0
}

# ==============================================================================
# 列出所有备�?# @return: 备份列表
# ==============================================================================
list_backups() {
    echo "=== 可用备份列表 ==="
    echo ""

    if [[ ! -d "${BACKUP_DIR}" ]]; then
        echo "备份目录不存�? ${BACKUP_DIR}"
        return 1
    fi

    local backup_dirs=()
    while IFS= read -r -d '' dir; do
        backup_dirs+=("${dir}")
    done < <(find "${BACKUP_DIR}" -maxdepth 1 -type d -name "backup_*" -print0 2>/dev/null | sort -z)

    if [[ ${#backup_dirs[@]} -eq 0 ]]; then
        echo "暂无备份"
        return 0
    fi

    # 显示备份信息
    local i=1
    for backup_dir in "${backup_dirs[@]}"; do
        local backup_name
        backup_name=$(basename "${backup_dir}")
        local info_file="${backup_dir}/info.txt"

        if [[ -f "${info_file}" ]]; then
            local backup_time backup_version distro strategy
            while IFS='=' read -r key value; do
                [[ "${key}" =~ ^# ]] && continue
                case "${key}" in
                    backup_time) backup_time="${value}" ;;
                    backup_version) backup_version="${value}" ;;
                    distro) distro="${value}" ;;
                    strategy) strategy="${value}" ;;
                esac
            done < "${info_file}"

            printf "${COLOR_GREEN}%2d${COLOR_NC}. ${backup_name}\n" "${i}"
            printf "    时间: ${backup_time}\n"
            printf "    版本: ${backup_version}\n"
            printf "    系统: ${distro}\n"
            printf "    策略: ${strategy}\n"
        else
            printf "${COLOR_GREEN}%2d${COLOR_NC}. ${backup_name} ${COLOR_YELLOW}[信息缺失]${COLOR_NC}\n" "${i}"
        fi

        echo ""
        ((i++)) || true
    done
}

# ==============================================================================
# 删除备份
# @param backup_path: 备份目录路径
# @return: 0为成功，1为失�?# ==============================================================================
delete_backup() {
    local backup_path="$1"

    # 验证备份路径
    if [[ ! -d "${backup_path}" ]]; then
        handle_error "BACKUP_DELETE" "备份目录不存�? ${backup_path}"
        return 1
    fi

    # 确认删除
    if ! ui_confirm "确认删除备份: ${backup_path}?"; then
        return 0
    fi

    # 删除备份
    if rm -rf "${backup_path}" 2>/dev/null; then
        log_info "备份已删�? ${backup_path}"
        return 0
    else
        handle_error "BACKUP_DELETE" "删除备份失败"
        return 1
    fi
}

# ==============================================================================
# 清理过期备份
# @param retention_days: 保留天数（默�?0�?# @return: 0为成�?# ==============================================================================
clean_old_backups() {
    local retention_days="${1:-30}"

    log_info "清理过期备份 (保留 ${retention_days} �?..."

    if [[ ! -d "${BACKUP_DIR}" ]]; then
        return 0
    fi

    local deleted=0
    local current_time
    current_time=$(get_timestamp)

    # 查找过期备份
    while IFS= read -r -d '' backup_dir; do
        local backup_name
        backup_name=$(basename "${backup_dir}")

        # 提取备份时间
        local backup_time_str
        backup_time_str=$(echo "${backup_name}" | sed 's/backup_//')

        # 转换为时间戳
        local backup_timestamp
        backup_timestamp=$(date -d "${backup_time_str}" +%s 2>/dev/null || echo "0")

        # 计算年龄
        local age=$((current_time - backup_timestamp))
        local retention_seconds=$((retention_days * 86400))

        if [[ ${backup_timestamp} -gt 0 ]] && [[ ${age} -gt ${retention_seconds} ]]; then
            if rm -rf "${backup_dir}" 2>/dev/null; then
                ((deleted++)) || true
                log_info "已删除过期备�? ${backup_name}"
            else
                log_warn "删除失败: ${backup_name}"
            fi
        fi
    done < <(find "${BACKUP_DIR}" -maxdepth 1 -type d -name "backup_*" -print0 2>/dev/null)

    log_info "清理完成: 已删�?${deleted} 个过期备�?
    return 0
}

# ==============================================================================
# 获取备份信息
# @param backup_path: 备份目录路径
# @return: 备份信息
# ==============================================================================
get_backup_info() {
    local backup_path="$1"
    local info_file="${backup_path}/info.txt"

    if [[ ! -f "${info_file}" ]]; then
        echo "备份信息文件不存�?
        return 1
    fi

    cat "${info_file}"
}