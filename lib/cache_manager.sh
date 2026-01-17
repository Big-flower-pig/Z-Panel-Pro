#!/bin/bash
# ==============================================================================
# Z-Panel Pro V8.0 - 智能缓存管理器
# ==============================================================================
# @description    高性能LRU/LFU缓存管理，支持自适应TTL
# @version       8.0.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 缓存管理器配置
# ==============================================================================
declare -gA CACHE_MANAGER=(
    # LRU缓存配置
    [lru_max_size]="1000"          # LRU缓存最大条目数
    [lru_default_ttl]="60"          # 默认TTL（秒）

    # LFU缓存配置
    [lfu_max_size]="500"           # LFU缓存最大条目数
    [lfu_min_freq]="1"             # 最小访问频率

    # 自适应配置
    [adaptive_ttl]="true"           # 启用自适应TTL
    [ttl_adjust_factor]="1.2"       # TTL调整因子

    # 性能配置
    [enable_persistence]="false"    # 启用持久化
    [persistence_interval]="300"    # 持久化间隔（秒）
)

# ==============================================================================
# LRU缓存数据结构
# ==============================================================================
declare -gA CACHE_LRU=(
    [current_size]="0"
    [hit_count]="0"
    [miss_count]="0"
)

# LRU缓存数据
declare -gA CACHE_LRU_DATA=()

# LRU访问顺序（数组模拟链表）
declare -ga CACHE_LRU_ACCESS_ORDER=()

# LRU时间戳
declare -gA CACHE_LRU_TIMESTAMPS=()

# ==============================================================================
# LFU缓存数据结构
# ==============================================================================
declare -gA CACHE_LFU=(
    [current_size]="0"
    [hit_count]="0"
    [miss_count]="0"
)

# LFU缓存数据
declare -gA CACHE_LFU_DATA=()

# LFU访问频率
declare -gA CACHE_LFU_FREQUENCY=()

# ==============================================================================
# 缓存统计
# ==============================================================================
declare -gA CACHE_STATS=(
    [total_hits]="0"
    [total_misses]="0"
    [total_evictions]="0"
    [total_sets]="0"
    [start_time]="$(date +%s)"
)

# ==============================================================================
# LRU缓存函数
# ==============================================================================

# LRU缓存获取
# @param key: 缓存键
# @return: 缓存值（存在）或空字符串（不存在）
cache_lru_get() {
    local key="$1"

    # 检查缓存是否存在
    [[ -z "${CACHE_LRU_DATA[${key}]}" ]] && {
        ((CACHE_LRU[miss_count]++))
        ((CACHE_STATS[total_misses]++))
        return 1
    }

    # 检查TTL是否过期
    local timestamp="${CACHE_LRU_TIMESTAMPS[${key}]}"
    local current_time=$(date +%s)
    local ttl="${CACHE_MANAGER[lru_default_ttl]}"

    if [[ $((current_time - timestamp)) -gt ${ttl} ]]; then
        # 过期，删除缓存
        cache_lru_delete "${key}"
        ((CACHE_LRU[miss_count]++))
        ((CACHE_STATS[total_misses]++))
        return 1
    fi

    # 更新访问顺序（移到末尾）
    cache_lru_update_access_order "${key}"

    # 更新统计
    ((CACHE_LRU[hit_count]++))
    ((CACHE_STATS[total_hits]++))

    echo "${CACHE_LRU_DATA[${key}]}"
    return 0
}

# LRU缓存设置
# @param key: 缓存键
# @param value: 缓存值
# @param ttl: TTL（可选，默认使用配置值）
# @return: 0=成功, 1=失败
cache_lru_set() {
    local key="$1"
    local value="$2"
    local ttl="${3:-${CACHE_MANAGER[lru_default_ttl]}}"

    # 检查缓存大小
    local max_size="${CACHE_MANAGER[lru_max_size]}"
    local current_size="${CACHE_LRU[current_size]}"

    if [[ ${current_size} -ge ${max_size} ]]; then
        # 淘汰最久未使用的数据
        cache_lru_evict
    fi

    # 设置缓存
    CACHE_LRU_DATA["${key}"]="${value}"
    CACHE_LRU_TIMESTAMPS["${key}"]=$(date +%s)

    # 更新访问顺序
    cache_lru_update_access_order "${key}"

    # 更新大小
    if [[ -z "${CACHE_LRU_DATA[${key}_old]}" ]]; then
        ((CACHE_LRU[current_size]++))
    fi

    # 更新统计
    ((CACHE_STATS[total_sets]++))

    return 0
}

# LRU缓存删除
# @param key: 缓存键
# @return: 0=成功, 1=失败
cache_lru_delete() {
    local key="$1"

    # 检查缓存是否存在
    [[ -z "${CACHE_LRU_DATA[${key}]}" ]] && return 1

    # 删除缓存
    unset CACHE_LRU_DATA["${key}"]
    unset CACHE_LRU_TIMESTAMPS["${key}"]

    # 从访问顺序中移除
    cache_lru_remove_from_order "${key}"

    # 更新大小
    ((CACHE_LRU[current_size]--))

    return 0
}

# LRU缓存清空
cache_lru_clear() {
    CACHE_LRU_DATA=()
    CACHE_LRU_TIMESTAMPS=()
    CACHE_LRU_ACCESS_ORDER=()
    CACHE_LRU[current_size]="0"
    CACHE_LRU[hit_count]="0"
    CACHE_LRU[miss_count]="0"

    return 0
}

# LRU更新访问顺序
# @param key: 缓存键
cache_lru_update_access_order() {
    local key="$1"

    # 从访问顺序中移除
    cache_lru_remove_from_order "${key}"

    # 添加到末尾
    CACHE_LRU_ACCESS_ORDER+=("${key}")
}

# LRU从访问顺序中移除
# @param key: 缓存键
cache_lru_remove_from_order() {
    local key="$1"
    local new_order=()

    for item in "${CACHE_LRU_ACCESS_ORDER[@]}"; do
        [[ "${item}" != "${key}" ]] && new_order+=("${item}")
    done

    CACHE_LRU_ACCESS_ORDER=("${new_order[@]}")
}

# LRU淘汰最久未使用的数据
cache_lru_evict() {
    # 获取最久未使用的键（访问顺序的第一个）
    [[ ${#CACHE_LRU_ACCESS_ORDER[@]} -eq 0 ]] && return 0

    local lru_key="${CACHE_LRU_ACCESS_ORDER[0]}"

    # 删除缓存
    cache_lru_delete "${lru_key}"

    # 更新统计
    ((CACHE_STATS[total_evictions]++))

    log_debug "LRU淘汰: ${lru_key}"
}

# ==============================================================================
# LFU缓存函数
# ==============================================================================

# LFU缓存获取
# @param key: 缓存键
# @return: 缓存值（存在）或空字符串（不存在）
cache_lfu_get() {
    local key="$1"

    # 检查缓存是否存在
    [[ -z "${CACHE_LFU_DATA[${key}]}" ]] && {
        ((CACHE_LFU[miss_count]++))
        ((CACHE_STATS[total_misses]++))
        return 1
    }

    # 更新访问频率
    ((CACHE_LFU_FREQUENCY[${key}]++))

    # 更新统计
    ((CACHE_LFU[hit_count]++))
    ((CACHE_STATS[total_hits]++))

    echo "${CACHE_LFU_DATA[${key}]}"
    return 0
}

# LFU缓存设置
# @param key: 缓存键
# @param value: 缓存值
# @return: 0=成功, 1=失败
cache_lfu_set() {
    local key="$1"
    local value="$2"

    # 检查缓存大小
    local max_size="${CACHE_MANAGER[lfu_max_size]}"
    local current_size="${CACHE_LFU[current_size]}"

    if [[ ${current_size} -ge ${max_size} ]]; then
        # 淘汰最不经常使用的数据
        cache_lfu_evict
    fi

    # 设置缓存
    CACHE_LFU_DATA["${key}"]="${value}"
    CACHE_LFU_FREQUENCY["${key}"]=1

    # 更新大小
    if [[ -z "${CACHE_LFU_DATA[${key}_old]}" ]]; then
        ((CACHE_LFU[current_size]++))
    fi

    # 更新统计
    ((CACHE_STATS[total_sets]++))

    return 0
}

# LFU缓存删除
# @param key: 缓存键
# @return: 0=成功, 1=失败
cache_lfu_delete() {
    local key="$1"

    # 检查缓存是否存在
    [[ -z "${CACHE_LFU_DATA[${key}]}" ]] && return 1

    # 删除缓存
    unset CACHE_LFU_DATA["${key}"]
    unset CACHE_LFU_FREQUENCY["${key}"]

    # 更新大小
    ((CACHE_LFU[current_size]--))

    return 0
}

# LFU缓存清空
cache_lfu_clear() {
    CACHE_LFU_DATA=()
    CACHE_LFU_FREQUENCY=()
    CACHE_LFU[current_size]="0"
    CACHE_LFU[hit_count]="0"
    CACHE_LFU[miss_count]="0"

    return 0
}

# LFU淘汰最不经常使用的数据
cache_lfu_evict() {
    local min_freq=999999
    local min_key=""

    # 找到访问频率最低的键
    for key in "${!CACHE_LFU_FREQUENCY[@]}"; do
        local freq="${CACHE_LFU_FREQUENCY[${key}]}"
        if [[ ${freq} -lt ${min_freq} ]]; then
            min_freq=${freq}
            min_key="${key}"
        fi
    done

    # 删除缓存
    [[ -n "${min_key}" ]] && cache_lfu_delete "${min_key}"

    # 更新统计
    ((CACHE_STATS[total_evictions]++))

    log_debug "LFU淘汰: ${min_key} (频率: ${min_freq})"
}

# ==============================================================================
# 自适应TTL
# ==============================================================================

# 计算自适应TTL
# @param key: 缓存键
# @param access_count: 访问次数
# @return: 自适应TTL值
calculate_adaptive_ttl() {
    local key="$1"
    local access_count="${2:-1}"
    local default_ttl="${CACHE_MANAGER[lru_default_ttl]}"
    local adjust_factor="${CACHE_MANAGER[ttl_adjust_factor]}"

    # 未启用自适应TTL
    [[ "${CACHE_MANAGER[adaptive_ttl]}" != "true" ]] && {
        echo "${default_ttl}"
        return 0
    }

    # 根据访问次数调整TTL
    local adaptive_ttl
    adaptive_ttl=$(echo "scale=0; ${default_ttl} * (${adjust_factor} ^ ${access_count})" | bc -l 2>/dev/null || echo "${default_ttl}")

    # 限制最大TTL
    local max_ttl=$((default_ttl * 10))
    [[ ${adaptive_ttl} -gt ${max_ttl} ]] && adaptive_ttl=${max_ttl}

    echo "${adaptive_ttl}"
}

# ==============================================================================
# 统计函数
# ==============================================================================

# 获取LRU缓存命中率
get_lru_hit_rate() {
    local hits="${CACHE_LRU[hit_count]}"
    local misses="${CACHE_LRU[miss_count]}"
    local total=$((hits + misses))

    [[ ${total} -eq 0 ]] && echo "0" && return 0

    local rate=$(echo "scale=2; ${hits} * 100 / ${total}" | bc -l 2>/dev/null || echo "0")
    echo "${rate}"
}

# 获取LFU缓存命中率
get_lfu_hit_rate() {
    local hits="${CACHE_LFU[hit_count]}"
    local misses="${CACHE_LFU[miss_count]}"
    local total=$((hits + misses))

    [[ ${total} -eq 0 ]] && echo "0" && return 0

    local rate=$(echo "scale=2; ${hits} * 100 / ${total}" | bc -l 2>/dev/null || echo "0")
    echo "${rate}"
}

# 获取整体缓存命中率
get_cache_hit_rate() {
    local hits="${CACHE_STATS[total_hits]}"
    local misses="${CACHE_STATS[total_misses]}"
    local total=$((hits + misses))

    [[ ${total} -eq 0 ]] && echo "0" && return 0

    local rate=$(echo "scale=2; ${hits} * 100 / ${total}" | bc -l 2>/dev/null || echo "0")
    echo "${rate}"
}

# 获取缓存统计
get_cache_stats() {
    local uptime=$(( $(date +%s) - CACHE_STATS[start_time] ))

    cat <<EOF
{
    "lru": {
        "size": ${CACHE_LRU[current_size]},
        "max_size": ${CACHE_MANAGER[lru_max_size]},
        "hits": ${CACHE_LRU[hit_count]},
        "misses": ${CACHE_LRU[miss_count]},
        "hit_rate": $(get_lru_hit_rate)
    },
    "lfu": {
        "size": ${CACHE_LFU[current_size]},
        "max_size": ${CACHE_MANAGER[lfu_max_size]},
        "hits": ${CACHE_LFU[hit_count]},
        "misses": ${CACHE_LFU[miss_count]},
        "hit_rate": $(get_lfu_hit_rate)
    },
    "overall": {
        "total_hits": ${CACHE_STATS[total_hits]},
        "total_misses": ${CACHE_STATS[total_misses]},
        "total_evictions": ${CACHE_STATS[total_evictions]},
        "total_sets": ${CACHE_STATS[total_sets]},
        "hit_rate": $(get_cache_hit_rate),
        "uptime_seconds": ${uptime}
    }
}
EOF
}

# 重置缓存统计
reset_cache_stats() {
    CACHE_STATS=(
        [total_hits]="0"
        [total_misses]="0"
        [total_evictions]="0"
        [total_sets]="0"
        [start_time]="$(date +%s)"
    )

    CACHE_LRU[hit_count]="0"
    CACHE_LRU[miss_count]="0"
    CACHE_LFU[hit_count]="0"
    CACHE_LFU[miss_count]="0"

    log_debug "缓存统计已重置"
    return 0
}

# ==============================================================================
# 持久化函数
# ==============================================================================

# 保存缓存到文件
# @param file: 文件路径
save_cache_to_file() {
    local file="$1"

    [[ "${CACHE_MANAGER[enable_persistence]}" != "true" ]] && return 0

    mkdir -p "$(dirname "${file}")" 2>/dev/null || return 1

    # 保存LRU缓存
    {
        echo "# LRU Cache"
        for key in "${!CACHE_LRU_DATA[@]}"; do
            echo "${key}|${CACHE_LRU_DATA[${key}]}|${CACHE_LRU_TIMESTAMPS[${key}]}"
        done
    } > "${file}.lru" 2>/dev/null || return 1

    # 保存LFU缓存
    {
        echo "# LFU Cache"
        for key in "${!CACHE_LFU_DATA[@]}"; do
            echo "${key}|${CACHE_LFU_DATA[${key}]}|${CACHE_LFU_FREQUENCY[${key}]}"
        done
    } > "${file}.lfu" 2>/dev/null || return 1

    log_debug "缓存已保存到: ${file}"
    return 0
}

# 从文件加载缓存
# @param file: 文件路径
load_cache_from_file() {
    local file="$1"

    [[ ! -f "${file}.lru" ]] && [[ ! -f "${file}.lfu" ]] && return 1

    # 加载LRU缓存
    if [[ -f "${file}.lru" ]]; then
        while IFS='|' read -r key value timestamp; do
            [[ "${key}" == "#"* ]] && continue
            [[ -z "${key}" ]] && continue

            CACHE_LRU_DATA["${key}"]="${value}"
            CACHE_LRU_TIMESTAMPS["${key}"]="${timestamp}"
            CACHE_LRU_ACCESS_ORDER+=("${key}")
        done < "${file}.lru"

        CACHE_LRU[current_size]="${#CACHE_LRU_DATA[@]}"
    fi

    # 加载LFU缓存
    if [[ -f "${file}.lfu" ]]; then
        while IFS='|' read -r key value frequency; do
            [[ "${key}" == "#"* ]] && continue
            [[ -z "${key}" ]] && continue

            CACHE_LFU_DATA["${key}"]="${value}"
            CACHE_LFU_FREQUENCY["${key}"]="${frequency}"
        done < "${file}.lfu"

        CACHE_LFU[current_size]="${#CACHE_LFU_DATA[@]}"
    fi

    log_debug "缓存已从文件加载: ${file}"
    return 0
}

# ==============================================================================
# 初始化和清理
# ==============================================================================

# 初始化缓存管理器
init_cache_manager() {
    log_debug "初始化缓存管理器..."

    # 创建缓存目录
    mkdir -p "${CONF_DIR}/cache" 2>/dev/null || true

    # 加载持久化缓存
    if [[ "${CACHE_MANAGER[enable_persistence]}" == "true" ]]; then
        load_cache_from_file "${CONF_DIR}/cache/cache"
    fi

    log_debug "缓存管理器初始化完成"
    return 0
}

# 清理缓存管理器
cleanup_cache_manager() {
    log_debug "清理缓存管理器..."

    # 保存缓存
    if [[ "${CACHE_MANAGER[enable_persistence]}" == "true" ]]; then
        save_cache_to_file "${CONF_DIR}/cache/cache"
    fi

    # 清空缓存
    cache_lru_clear
    cache_lfu_clear

    log_debug "缓存管理器清理完成"
    return 0
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f cache_lru_get
export -f cache_lru_set
export -f cache_lru_delete
export -f cache_lru_clear
export -f cache_lfu_get
export -f cache_lfu_set
export -f cache_lfu_delete
export -f cache_lfu_clear
export -f get_cache_stats
export -f save_cache_to_file
export -f load_cache_from_file
