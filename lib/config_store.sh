#!/bin/bash
# ==============================================================================
# Z-Panel Pro V8.0 - 配置存储优化
# ==============================================================================
# @description    高性能配置存储，支持分层配置、热重载、版本控制
# @version       8.0.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 配置存储配置
# ==============================================================================
declare -gA CONFIG_STORE_CONFIG=(
    [config_dir]="/opt/Z-Panel-Pro/config"
    [cache_dir]="/opt/Z-Panel-Pro/cache/config"
    [backup_dir]="/opt/Z-Panel-Pro/backups/config"
    [layers]="system,user,session"
    [cache_enabled]="true"
    [cache_ttl]="300"
    [auto_backup]="true"
    [backup_interval]="3600"
    [version_control]="true"
    [max_versions]="10"
)

# ==============================================================================
# 配置层级
# ==============================================================================
# 系统配置 - 只读，默认值
declare -gA CONFIG_SYSTEM=()

# 用户配置 - 可写，持久化
declare -gA CONFIG_USER=()

# 会话配置 - 临时，会话结束清除
declare -gA CONFIG_SESSION=()

# 运行时配置 - 运行时动态修改
declare -gA CONFIG_RUNTIME=()

# ==============================================================================
# 配置缓存
# ==============================================================================
declare -gA CONFIG_CACHE=()
declare -gA CONFIG_CACHE_TIME=()

# ==============================================================================
# 配置变更监听器
# ==============================================================================
declare -ga CONFIG_CHANGE_LISTENERS=()

# ==============================================================================
# 安全工具函数
# ==============================================================================
# 规范化路径（移除相对路径和符号链接）
normalize_path() {
    local path="$1"
    local base_dir="${2:-}"

    # 检查路径遍历攻击
    if [[ "${path}" =~ \.\./ ]] || [[ "${path}" =~ \.\.\\ ]] || [[ "${path}" =~ \.\.$ ]]; then
        log_error "拒绝路径遍历攻击: ${path}"
        return 1
    fi

    # 如果提供了基础目录，确保路径在基础目录内
    if [[ -n "${base_dir}" ]]; then
        # 解析绝对路径
        local abs_path=$(realpath -m "${path}" 2>/dev/null || echo "${path}")
        local abs_base=$(realpath -m "${base_dir}" 2>/dev/null || echo "${base_dir}")

        # 检查是否在基础目录内
        if [[ "${abs_path}" != "${abs_base}"/* ]]; then
            log_error "拒绝访问基础目录外的路径: ${path}"
            return 1
        fi

        echo "${abs_path}"
        return 0
    fi

    # 简单规范化
    echo "${path}"
    return 0
}

# 验证文件路径是否安全
is_safe_file_path() {
    local path="$1"
    local allowed_dir="${2:-}"

    # 检查空路径
    if [[ -z "${path}" ]]; then
        return 1
    fi

    # 检查路径遍历
    if [[ "${path}" =~ \.\./ ]] || [[ "${path}" =~ \.\.\\ ]] || [[ "${path}" =~ \.\.$ ]]; then
        return 1
    fi

    # 检查特殊字符
    if [[ "${path}" =~ [\|\&\;\<\>\$\`\(\)] ]]; then
        return 1
    fi

    # 如果有允许的目录，检查是否在允许的目录内
    if [[ -n "${allowed_dir}" ]]; then
        local normalized=$(normalize_path "${path}" "${allowed_dir}")
        if [[ $? -ne 0 ]]; then
            return 1
        fi
    fi

    return 0
}

# 验证文件是否存在且安全
is_safe_file() {
    local path="$1"

    # 检查是否存在
    if [[ ! -e "${path}" ]]; then
        return 1
    fi

    # 检查符号链接
    if [[ -L "${path}" ]]; then
        return 1
    fi

    # 检查文件类型
    if [[ ! -f "${path}" ]] && [[ ! -d "${path}" ]]; then
        return 1
    fi

    return 0
}

# ==============================================================================
# 初始化配置存储
# ==============================================================================
init_config_store() {
    log_info "初始化配置存储..."

    # 创建目录
    mkdir -p "${CONFIG_STORE_CONFIG[config_dir]}"
    mkdir -p "${CONFIG_STORE_CONFIG[cache_dir]}"
    mkdir -p "${CONFIG_STORE_CONFIG[backup_dir]}"

    # 加载系统配置
    load_system_config

    # 加载用户配置
    load_user_config

    # 启动自动备份
    if [[ "${CONFIG_STORE_CONFIG[auto_backup]}" == "true" ]]; then
        start_config_backup &
    fi

    log_info "配置存储初始化完成"
    return 0
}

# 加载系统配置
load_system_config() {
    local system_file="${CONFIG_STORE_CONFIG[config_dir]}/system.conf"

    if [[ -f "${system_file}" ]]; then
        while IFS='=' read -r key value; do
            # 跳过注释和空行
            if [[ -z "${key}" ]] || [[ "${key}" == \#* ]]; then
                continue
            fi

            # 移除值周围的引号
            value="${value#\"}"
            value="${value%\"}"

            CONFIG_SYSTEM["${key}"]="${value}"
        done < "${system_file}"

        log_debug "加载系统配置: ${system_file}"
    fi
}

# 加载用户配置
load_user_config() {
    local user_file="${CONFIG_STORE_CONFIG[config_dir]}/user.conf"

    if [[ -f "${user_file}" ]]; then
        while IFS='=' read -r key value; do
            if [[ -z "${key}" ]] || [[ "${key}" == \#* ]]; then
                continue
            fi

            value="${value#\"}"
            value="${value%\"}"

            CONFIG_USER["${key}"]="${value}"
        done < "${user_file}"

        log_debug "加载用户配置: ${user_file}"
    fi
}

# 保存用户配置
save_user_config() {
    local user_file="${CONFIG_STORE_CONFIG[config_dir]}/user.conf"

    # 创建备份
    if [[ "${CONFIG_STORE_CONFIG[version_control]}" == "true" ]]; then
        backup_config "user"
    fi

    # 写入配置
    {
        echo "# Z-Panel Pro 用户配置"
        echo "# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""

        for key in "${!CONFIG_USER[@]}"; do
            echo "${key}=\"${CONFIG_USER[${key}]}\""
        done
    } > "${user_file}"

    log_debug "保存用户配置: ${user_file}"
}

# ==============================================================================
# 配置读写
# ==============================================================================
# 获取配置（优先级：runtime > session > user > system）
get_config() {
    local key="$1"
    local default="${2:-}"

    # 检查缓存
    if [[ "${CONFIG_STORE_CONFIG[cache_enabled]}" == "true" ]]; then
        local cached=$(get_cached_config "${key}")
        if [[ -n "${cached}" ]]; then
            echo "${cached}"
            return 0
        fi
    fi

    # 按层级查找
    local value=""

    if [[ -n "${CONFIG_RUNTIME[${key}]+isset}" ]]; then
        value="${CONFIG_RUNTIME[${key}]}"
    elif [[ -n "${CONFIG_SESSION[${key}]+isset}" ]]; then
        value="${CONFIG_SESSION[${key}]}"
    elif [[ -n "${CONFIG_USER[${key}]+isset}" ]]; then
        value="${CONFIG_USER[${key}]}"
    elif [[ -n "${CONFIG_SYSTEM[${key}]+isset}" ]]; then
        value="${CONFIG_SYSTEM[${key}]}"
    else
        value="${default}"
    fi

    # 缓存结果
    if [[ "${CONFIG_STORE_CONFIG[cache_enabled]}" == "true" ]]; then
        cache_config "${key}" "${value}"
    fi

    echo "${value}"
}

# 设置配置
set_config() {
    local key="$1"
    local value="$2"
    local layer="${3:-user}"

    local old_value=$(get_config "${key}")

    case "${layer}" in
        runtime)
            CONFIG_RUNTIME["${key}"]="${value}"
            ;;
        session)
            CONFIG_SESSION["${key}"]="${value}"
            ;;
        user)
            CONFIG_USER["${key}"]="${value}"
            save_user_config
            ;;
        system)
            log_warning "系统配置是只读的，使用运行时层"
            CONFIG_RUNTIME["${key}"]="${value}"
            ;;
        *)
            log_error "无效的配置层级: ${layer}"
            return 1
            ;;
    esac

    # 清除缓存
    invalidate_cache "${key}"

    # 触发变更监听器
    trigger_config_change "${key}" "${old_value}" "${value}" "${layer}"

    return 0
}

# 删除配置
delete_config() {
    local key="$1"
    local layer="${2:-user}"

    local old_value=$(get_config "${key}")

    case "${layer}" in
        runtime)
            unset CONFIG_RUNTIME["${key}"]
            ;;
        session)
            unset CONFIG_SESSION["${key}"]
            ;;
        user)
            unset CONFIG_USER["${key}"]
            save_user_config
            ;;
        system)
            log_warning "无法删除系统配置"
            return 1
            ;;
        *)
            log_error "无效的配置层级: ${layer}"
            return 1
            ;;
    esac

    # 清除缓存
    invalidate_cache "${key}"

    # 触发变更监听器
    trigger_config_change "${key}" "${old_value}" "" "${layer}"

    return 0
}

# ==============================================================================
# 配置缓存
# ==============================================================================
# 缓存配置
cache_config() {
    local key="$1"
    local value="$2"

    local cache_time=$(date +%s)
    local ttl="${CONFIG_STORE_CONFIG[cache_ttl]}"
    local expiry=$((cache_time + ttl))

    CONFIG_CACHE["${key}"]="${value}"
    CONFIG_CACHE_TIME["${key}"]="${expiry}"
}

# 获取缓存配置
get_cached_config() {
    local key="$1"

    if [[ -n "${CONFIG_CACHE[${key}]+isset}" ]]; then
        local expiry="${CONFIG_CACHE_TIME[${key}]}"
        local current_time=$(date +%s)

        if [[ ${current_time} -lt ${expiry} ]]; then
            echo "${CONFIG_CACHE[${key}]}"
            return 0
        else
            # 缓存过期
            unset CONFIG_CACHE["${key}"]
            unset CONFIG_CACHE_TIME["${key}"]
        fi
    fi

    return 1
}

# 清除缓存
invalidate_cache() {
    local key="${1:-}"

    if [[ -z "${key}" ]]; then
        # 清除所有缓存
        for cache_key in "${!CONFIG_CACHE[@]}"; do
            unset CONFIG_CACHE["${cache_key}"]
            unset CONFIG_CACHE_TIME["${cache_key}"]
        done
    else
        # 清除指定键的缓存
        unset CONFIG_CACHE["${key}"]
        unset CONFIG_CACHE_TIME["${key}"]
    fi
}

# 清理过期缓存
cleanup_config_cache() {
    local current_time=$(date +%s)

    for key in "${!CONFIG_CACHE_TIME[@]}"; do
        local expiry="${CONFIG_CACHE_TIME[${key}]}"

        if [[ ${current_time} -ge ${expiry} ]]; then
            unset CONFIG_CACHE["${key}"]
            unset CONFIG_CACHE_TIME["${key}"]
        fi
    done
}

# ==============================================================================
# 配置变更监听
# ==============================================================================
# 注册变更监听器
register_config_listener() {
    local callback="$1"
    local key_filter="${2:-*}"

    CONFIG_CHANGE_LISTENERS+=("${callback}:${key_filter}")
}

# 触发配置变更
trigger_config_change() {
    local key="$1"
    local old_value="$2"
    local new_value="$3"
    local layer="$4"

    for listener in "${CONFIG_CHANGE_LISTENERS[@]}"; do
        local callback="${listener%%:*}"
        local key_filter="${listener##*:}"

        # 检查键是否匹配
        if [[ "${key}" == ${key_filter} ]] || [[ "${key_filter}" == "*" ]]; then
            ${callback} "${key}" "${old_value}" "${new_value}" "${layer}" 2>/dev/null || true
        fi
    done
}

# ==============================================================================
# 配置备份和恢复
# ==============================================================================
# 备份配置
backup_config() {
    local layer="${1:-all}"
    local backup_file="${CONFIG_STORE_CONFIG[backup_dir]}/config_$(date +%Y%m%d_%H%M%S).tar.gz"

    mkdir -p "${CONFIG_STORE_CONFIG[backup_dir]}"

    case "${layer}" in
        all)
            tar -czf "${backup_file}" -C "${CONFIG_STORE_CONFIG[config_dir]}" .
            ;;
        user)
            tar -czf "${backup_file}" -C "${CONFIG_STORE_CONFIG[config_dir]}" user.conf
            ;;
        system)
            tar -czf "${backup_file}" -C "${CONFIG_STORE_CONFIG[config_dir]}" system.conf
            ;;
        *)
            log_error "无效的配置层级: ${layer}"
            return 1
            ;;
    esac

    log_info "配置已备份: ${backup_file}"

    # 清理旧备份
    cleanup_old_backups

    echo "${backup_file}"
}

# 恢复配置（安全版本）
restore_config() {
    local backup_file="$1"

    # 验证文件路径
    if ! is_safe_file_path "${backup_file}" "${CONFIG_STORE_CONFIG[backup_dir]}"; then
        log_error "拒绝不安全的备份文件路径: ${backup_file}"
        return 1
    fi

    # 规范化路径
    local safe_path=$(normalize_path "${backup_file}" "${CONFIG_STORE_CONFIG[backup_dir]}")
    if [[ $? -ne 0 ]]; then
        return 1
    fi

    # 检查文件是否存在
    if [[ ! -f "${safe_path}" ]]; then
        log_error "备份文件不存在: ${safe_path}"
        return 1
    fi

    # 检查符号链接
    if [[ -L "${safe_path}" ]]; then
        log_error "拒绝恢复符号链接文件: ${safe_path}"
        return 1
    fi

    # 验证文件类型（必须是tar.gz）
    if ! file "${safe_path}" 2>/dev/null | grep -q "gzip compressed"; then
        log_error "无效的备份文件格式: ${safe_path}"
        return 1
    fi

    # 创建当前备份
    local current_backup="${CONFIG_STORE_CONFIG[backup_dir]}/config_before_restore_$(date +%Y%m%d_%H%M%S).tar.gz"
    tar -czf "${current_backup}" -C "${CONFIG_STORE_CONFIG[config_dir]}" .

    # 恢复配置
    tar -xzf "${safe_path}" -C "${CONFIG_STORE_CONFIG[config_dir]}"

    # 重新加载配置
    load_system_config
    load_user_config

    # 清除缓存
    invalidate_cache

    log_info "配置已恢复: ${safe_path}"
    log_info "当前配置已备份到: ${current_backup}"

    return 0
}

# 清理旧备份
cleanup_old_backups() {
    local max_versions="${CONFIG_STORE_CONFIG[max_versions]}"
    local backup_dir="${CONFIG_STORE_CONFIG[backup_dir]}"

    # 按时间排序并删除旧备份
    local backups=($(ls -t "${backup_dir}"/config_*.tar.gz 2>/dev/null))

    if [[ ${#backups[@]} -gt ${max_versions} ]]; then
        local old_backups=("${backups[@]:${max_versions}}")

        for old_backup in "${old_backups[@]}"; do
            rm -f "${old_backup}"
            log_debug "删除旧备份: ${old_backup}"
        done
    fi
}

# 自动备份
start_config_backup() {
    local interval="${CONFIG_STORE_CONFIG[backup_interval]}"

    while true; do
        sleep ${interval}

        if [[ "${CONFIG_STORE_CONFIG[auto_backup]}" == "true" ]]; then
            backup_config "all" > /dev/null
        fi
    done
}

# ==============================================================================
# 配置导入导出
# ==============================================================================
# 导出配置（安全版本）
export_config() {
    local output_file="${1:-${CONFIG_STORE_CONFIG[cache_dir]}/config_export.json}"
    local layer="${2:-all}"

    # 验证文件路径
    if ! is_safe_file_path "${output_file}" "${CONFIG_STORE_CONFIG[cache_dir]}"; then
        log_error "拒绝不安全的导出路径: ${output_file}"
        return 1
    fi

    # 规范化路径
    local safe_path=$(normalize_path "${output_file}" "${CONFIG_STORE_CONFIG[cache_dir]}")
    if [[ $? -ne 0 ]]; then
        return 1
    fi

    # 确保目录存在
    local output_dir=$(dirname "${safe_path}")
    mkdir -p "${output_dir}"

    local config_json="{"
    local first=true

    case "${layer}" in
        all)
            for layer_name in system user session runtime; do
                config_json+=$(export_layer_config "${layer_name}" "${first}")
                first=false
            done
            ;;
        *)
            config_json+=$(export_layer_config "${layer}" true)
            ;;
    esac

    config_json+=$'\n}'

    echo "${config_json}" > "${safe_path}"

    log_info "配置已导出到: ${safe_path}"
    echo "${safe_path}"
}

# 导出层级配置
export_layer_config() {
    local layer="$1"
    local first="${2:-false}"

    local json=""
    local -n config_ref

    case "${layer}" in
        system) config_ref=CONFIG_SYSTEM ;;
        user) config_ref=CONFIG_USER ;;
        session) config_ref=CONFIG_SESSION ;;
        runtime) config_ref=CONFIG_RUNTIME ;;
        *) return ;;
    esac

    if [[ "${first}" == "false" ]]; then
        json+=","
    fi

    json+=$'\n'    "'
    json+="${layer}"
    json+='": {'

    local inner_first=true
    for key in "${!config_ref[@]}"; do
        if [[ "${inner_first}" == "false" ]]; then
            json+=","
        fi

        json+=$'\n        "'
        json+="${key}"
        json+='": "'
        json+="${config_ref[${key}]}"
        json+='"'

        inner_first=false
    done

    json+=$'\n    }'

    echo "${json}"
}

# 导入配置（安全版本）
import_config() {
    local input_file="$1"
    local layer="${2:-user}"

    # 验证文件路径
    if ! is_safe_file_path "${input_file}" "${CONFIG_STORE_CONFIG[cache_dir]}"; then
        log_error "拒绝不安全的导入文件路径: ${input_file}"
        return 1
    fi

    # 规范化路径
    local safe_path=$(normalize_path "${input_file}" "${CONFIG_STORE_CONFIG[cache_dir]}")
    if [[ $? -ne 0 ]]; then
        return 1
    fi

    # 检查文件是否存在
    if [[ ! -f "${safe_path}" ]]; then
        log_error "文件不存在: ${safe_path}"
        return 1
    fi

    # 检查符号链接
    if [[ -L "${safe_path}" ]]; then
        log_error "拒绝导入符号链接文件: ${safe_path}"
        return 1
    fi

    # 验证文件类型（必须是JSON）
    if ! file "${safe_path}" 2>/dev/null | grep -qi "json\|text"; then
        log_error "无效的导入文件格式: ${safe_path}"
        return 1
    fi

    if ! command -v jq &> /dev/null; then
        log_error "jq 命令未找到，无法导入JSON配置"
        return 1
    fi

    local -n config_ref
    case "${layer}" in
        user) config_ref=CONFIG_USER ;;
        runtime) config_ref=CONFIG_RUNTIME ;;
        session) config_ref=CONFIG_SESSION ;;
        *)
            log_error "不能导入到系统配置层"
            return 1
            ;;
    esac

    # 读取并解析JSON
    local layer_data=$(jq -r ".${layer}" "${safe_path}")

    if [[ "${layer_data}" == "null" ]]; then
        log_warning "配置中未找到层级: ${layer}"
        return 1
    fi

    # 导入配置（验证键名）
    local keys=$(jq -r "keys[]" <<< "${layer_data}")

    for key in ${keys}; do
        # 验证键名格式
        if [[ ! "${key}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
            log_warning "跳过无效的配置键: ${key}"
            continue
        fi

        local value=$(jq -r ".${key}" <<< "${layer_data}")

        # 验证值不为null
        if [[ "${value}" == "null" ]]; then
            log_warning "跳过null值: ${key}"
            continue
        fi

        config_ref["${key}"]="${value}"
    done

    # 保存用户配置
    if [[ "${layer}" == "user" ]]; then
        save_user_config
    fi

    # 清除缓存
    invalidate_cache

    log_info "配置已导入: ${safe_path}"
    return 0
}

# ==============================================================================
# 配置验证
# ==============================================================================
# 验证配置
validate_config() {
    local key="$1"
    local value="$2"
    local validator="${3:-}"

    if [[ -z "${validator}" ]]; then
        return 0
    fi

    case "${validator}" in
        integer)
            [[ "${value}" =~ ^[0-9]+$ ]]
            ;;
        float)
            [[ "${value}" =~ ^[0-9]+(\.[0-9]+)?$ ]]
            ;;
        boolean)
            [[ "${value}" == "true" ]] || [[ "${value}" == "false" ]]
            ;;
        path)
            [[ "${value}" =~ ^/.*$ ]]
            ;;
        email)
            [[ "${value}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
            ;;
        url)
            [[ "${value}" =~ ^https?://.*$ ]]
            ;;
        *)
            # 自定义验证器
            ${validator} "${value}"
            ;;
    esac
}

# ==============================================================================
# 配置查询
# ==============================================================================
# 列出所有配置
list_config() {
    local layer="${1:-all}"
    local pattern="${2:-*}"

    local output=""

    case "${layer}" in
        all)
            for layer_name in system user session runtime; do
                output+=$(list_layer_config "${layer_name}" "${pattern}")
            done
            ;;
        *)
            output+=$(list_layer_config "${layer}" "${pattern}")
            ;;
    esac

    echo "${output}"
}

# 列出层级配置
list_layer_config() {
    local layer="$1"
    local pattern="${2:-*}"

    local output=""
    local -n config_ref

    case "${layer}" in
        system) config_ref=CONFIG_SYSTEM ;;
        user) config_ref=CONFIG_USER ;;
        session) config_ref=CONFIG_SESSION ;;
        runtime) config_ref=CONFIG_RUNTIME ;;
        *) return ;;
    esac

    for key in "${!config_ref[@]}"; do
        if [[ "${key}" == ${pattern} ]]; then
            output+="${layer}.${key}=${config_ref[${key}]}"$'\n'
        fi
    done

    echo "${output}"
}

# 获取配置统计
get_config_stats() {
    local stats=$(cat <<EOF
{
    "system_keys": ${#CONFIG_SYSTEM[@]},
    "user_keys": ${#CONFIG_USER[@]},
    "session_keys": ${#CONFIG_SESSION[@]},
    "runtime_keys": ${#CONFIG_RUNTIME[@]},
    "cached_keys": ${#CONFIG_CACHE[@]},
    "listeners": ${#CONFIG_CHANGE_LISTENERS[@]}
}
EOF
)

    echo "${stats}"
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f init_config_store
export -f load_system_config
export -f load_user_config
export -f save_user_config
export -f get_config
export -f set_config
export -f delete_config
export -f cache_config
export -f get_cached_config
export -f invalidate_cache
export -f cleanup_config_cache
export -f register_config_listener
export -f trigger_config_change
export -f backup_config
export -f restore_config
export -f cleanup_old_backups
export -f start_config_backup
export -f export_config
export -f export_layer_config
export -f import_config
export -f validate_config
export -f list_config
export -f list_layer_config
export -f get_config_stats
