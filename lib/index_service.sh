#!/bin/bash
# ==============================================================================
# Z-Panel Pro V8.0 - 索引服务
# ==============================================================================
# @description    高性能索引服务，支持全文搜索、快速查询、缓存优化
# @version       8.0.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 索引服务配置
# ==============================================================================
declare -gA INDEX_CONFIG=(
    [index_dir]="/opt/Z-Panel-Pro/data/indexes"
    [cache_enabled]="true"
    [cache_size]="10000"
    [auto_reindex]="true"
    [rebuild_interval]="3600"
    [max_index_size]="100M"
    [compression]="gzip"
    [index_version]="1.0"
)

# ==============================================================================
# 索引类型
# ==============================================================================
declare -gA INDEX_TYPES=(
    [hash]="哈希索引"
    [btree]="B树索引"
    [fulltext]="全文索引"
    [spatial]="空间索引"
    [inverted]="倒排索引"
)

# ==============================================================================
# 索引存储
# ==============================================================================
declare -gA INDEXES=()
declare -gA INDEX_METADATA=()
declare -gA INDEX_CACHE=()
declare -gA INDEX_STATS=()

# ==============================================================================
# 倒排索引（用于全文搜索）
# ==============================================================================
declare -gA INVERTED_INDEX=()

# ==============================================================================
# 初始化索引服务
# ==============================================================================
init_index_service() {
    log_info "初始化索引服务..."

    # 创建索引目录
    mkdir -p "${INDEX_CONFIG[index_dir]}"

    # 加载现有索引
    load_all_indexes

    # 启动自动重建
    if [[ "${INDEX_CONFIG[auto_reindex]}" == "true" ]]; then
        start_index_rebuild &
    fi

    log_info "索引服务初始化完成"
    return 0
}

# ==============================================================================
# 索引创建
# ==============================================================================
# 创建索引
create_index() {
    local index_name="$1"
    local index_type="$2"
    local source="${3:-}"
    local description="${4:-}"

    if [[ -z "${index_name}" ]] || [[ -z "${index_type}" ]]; then
        log_error "缺少必需参数: index_name, index_type"
        return 1
    fi

    # 检查索引类型是否有效
    if [[ -z "${INDEX_TYPES[${index_type}]+isset}" ]]; then
        log_error "无效的索引类型: ${index_type}"
        return 1
    fi

    # 检查索引是否已存在
    if [[ -n "${INDEXES[${index_name}_type]+isset}" ]]; then
        log_error "索引已存在: ${index_name}"
        return 1
    fi

    # 创建索引
    INDEXES["${index_name}_type"]="${index_type}"
    INDEXES["${index_name}_source"]="${source}"
    INDEXES["${index_name}_description"]="${description}"
    INDEXES["${index_name}_created"]=$(date +%s)
    INDEXES["${index_name}_updated"]=$(date +%s)
    INDEXES["${index_name}_entries"]="0"
    INDEXES["${index_name}_size"]="0"
    INDEXES["${index_name}_enabled"]="true"

    INDEX_METADATA["${index_name}_version"]="${INDEX_CONFIG[index_version]}"

    # 初始化统计
    INDEX_STATS["${index_name}_queries"]="0"
    INDEX_STATS["${index_name}_hits"]="0"
    INDEX_STATS["${index_name}_misses"]="0"

    log_info "索引已创建: ${index_name} (${index_type})"

    # 持久化
    persist_index "${index_name}"

    return 0
}

# 删除索引
delete_index() {
    local index_name="$1"

    if [[ -z "${INDEXES[${index_name}_type]+isset}" ]]; then
        log_error "索引不存在: ${index_name}"
        return 1
    fi

    # 删除索引数据
    for key in "${!INDEXES[@]}"; do
        if [[ "${key}" == "${index_name}_"* ]]; then
            unset INDEXES["${key}"]
        fi
    done

    # 删除元数据
    unset INDEX_METADATA["${index_name}_version"]

    # 删除统计
    unset INDEX_STATS["${index_name}_queries"]
    unset INDEX_STATS["${index_name}_hits"]
    unset INDEX_STATS["${index_name}_misses"]

    # 删除缓存
    unset INDEX_CACHE["${index_name}"]

    # 删除倒排索引
    for key in "${!INVERTED_INDEX[@]}"; do
        if [[ "${key}" == "${index_name}:"* ]]; then
            unset INVERTED_INDEX["${key}"]
        fi
    done

    # 删除持久化文件
    local index_file="${INDEX_CONFIG[index_dir]}/${index_name}.idx"
    rm -f "${index_file}"

    log_info "索引已删除: ${index_name}"
    return 0
}

# 重建索引
rebuild_index() {
    local index_name="$1"

    if [[ -z "${INDEXES[${index_name}_type]+isset}" ]]; then
        log_error "索引不存在: ${index_name}"
        return 1
    fi

    local index_type="${INDEXES[${index_name}_type]}"
    local source="${INDEXES[${index_name}_source]}"

    log_info "重建索引: ${index_name}"

    # 清空现有索引
    clear_index_data "${index_name}"

    # 根据类型重建
    case "${index_type}" in
        hash)
            rebuild_hash_index "${index_name}" "${source}"
            ;;
        btree)
            rebuild_btree_index "${index_name}" "${source}"
            ;;
        fulltext)
            rebuild_fulltext_index "${index_name}" "${source}"
            ;;
        inverted)
            rebuild_inverted_index "${index_name}" "${source}"
            ;;
        *)
            log_error "不支持的索引类型: ${index_type}"
            return 1
            ;;
    esac

    # 更新时间戳
    INDEXES["${index_name}_updated"]=$(date +%s)

    # 持久化
    persist_index "${index_name}"

    log_info "索引重建完成: ${index_name}"
    return 0
}

# 清空索引数据
clear_index_data() {
    local index_name="$1"

    # 清空倒排索引
    for key in "${!INVERTED_INDEX[@]}"; do
        if [[ "${key}" == "${index_name}:"* ]]; then
            unset INVERTED_INDEX["${key}"]
        fi
    done

    # 重置统计
    INDEXES["${index_name}_entries"]="0"
    INDEXES["${index_name}_size"]="0"
}

# ==============================================================================
# 哈希索引
# ==============================================================================
# 重建哈希索引
rebuild_hash_index() {
    local index_name="$1"
    local source="$2"

    # 从源加载数据
    if [[ -f "${source}" ]]; then
        while IFS='|' read -r key value; do
            add_hash_index_entry "${index_name}" "${key}" "${value}"
        done < "${source}"
    fi
}

# 添加哈希索引条目
add_hash_index_entry() {
    local index_name="$1"
    local key="$2"
    local value="$3"

    local index_key="${index_name}:${key}"
    INVERTED_INDEX["${index_key}"]="${value}"

    # 更新统计
    local entries="${INDEXES[${index_name}_entries]}"
    INDEXES["${index_name}_entries"]="$((entries + 1))"
}

# 查询哈希索引
query_hash_index() {
    local index_name="$1"
    local key="$2"

    local index_key="${index_name}:${key}"
    local result="${INVERTED_INDEX[${index_key}]:-}"

    # 更新统计
    INDEX_STATS["${index_name}_queries"]="$((INDEX_STATS[${index_name}_queries] + 1))"

    if [[ -n "${result}" ]]; then
        INDEX_STATS["${index_name}_hits"]="$((INDEX_STATS[${index_name}_hits] + 1))"
        echo "${result}"
        return 0
    else
        INDEX_STATS["${index_name}_misses"]="$((INDEX_STATS[${index_name}_misses] + 1))"
        return 1
    fi
}

# ==============================================================================
# 全文索引
# ==============================================================================
# 重建全文索引
rebuild_fulltext_index() {
    local index_name="$1"
    local source="$2"

    if [[ -f "${source}" ]]; then
        while IFS='|' read -r doc_id content; do
            add_fulltext_index_entry "${index_name}" "${doc_id}" "${content}"
        done < "${source}"
    fi
}

# 添加全文索引条目
add_fulltext_index_entry() {
    local index_name="$1"
    local doc_id="$2"
    local content="$3"

    # 分词
    local words=$(echo "${content}" | tr -cs '[:alpha:]' '\n' | tr '[:upper:]' '[:lower:]')

    # 构建倒排索引
    for word in ${words}; do
        # 跳过停用词
        if is_stop_word "${word}"; then
            continue
        fi

        local word_key="${index_name}:${word}"
        local docs="${INVERTED_INDEX[${word_key}]:-}"

        if [[ -z "${docs}" ]]; then
            docs="${doc_id}"
        elif [[ "${docs}" != *"${doc_id}"* ]]; then
            docs+=" ${doc_id}"
        fi

        INVERTED_INDEX["${word_key}"]="${docs}"
    done

    # 更新统计
    local entries="${INDEXES[${index_name}_entries]}"
    INDEXES["${index_name}_entries"]="$((entries + 1))"
}

# 全文搜索
search_fulltext() {
    local index_name="$1"
    local query="$2"
    local limit="${3:-10}"

    # 分词
    local query_words=$(echo "${query}" | tr -cs '[:alpha:]' '\n' | tr '[:upper:]' '[:lower:]')

    local -A doc_scores=()
    local word_count=0

    # 查找匹配的文档
    for word in ${query_words}; do
        if is_stop_word "${word}"; then
            continue
        fi

        local word_key="${index_name}:${word}"
        local docs="${INVERTED_INDEX[${word_key}]:-}"

        if [[ -n "${docs}" ]]; then
            for doc_id in ${docs}; do
                local score="${doc_scores[${doc_id}]:-0}"
                doc_scores[${doc_id}]="$((score + 1))"
            done
        fi

        ((word_count++))
    done

    # 更新统计
    INDEX_STATS["${index_name}_queries"]="$((INDEX_STATS[${index_name}_queries] + 1))"

    # 排序结果
    local results=()
    for doc_id in "${!doc_scores[@]}"; do
        local score="${doc_scores[${doc_id}]}"
        results+=("${score}:${doc_id}")
    done

    IFS=$'\n' sorted_results=($(sort -rn -t':' -k1 <<< "${results[*]}"))

    # 输出结果
    local count=0
    for result in "${sorted_results[@]}"; do
        if [[ ${count} -ge ${limit} ]]; then
            break
        fi

        local doc_id="${result##*:}"
        echo "${doc_id}"
        ((count++))
    done

    if [[ ${count} -gt 0 ]]; then
        INDEX_STATS["${index_name}_hits"]="$((INDEX_STATS[${index_name}_hits] + 1))"
    else
        INDEX_STATS["${index_name}_misses"]="$((INDEX_STATS[${index_name}_misses} + 1))"
    fi
}

# 倒排索引
rebuild_inverted_index() {
    local index_name="$1"
    local source="$2"

    if [[ -f "${source}" ]]; then
        while IFS='|' read -r key value; do
            add_inverted_index_entry "${index_name}" "${key}" "${value}"
        done < "${source}"
    fi
}

# 添加倒排索引条目
add_inverted_index_entry() {
    local index_name="$1"
    local key="$2"
    local value="$3"

    local index_key="${index_name}:${key}"
    local values="${INVERTED_INDEX[${index_key}]:-}"

    if [[ -z "${values}" ]]; then
        values="${value}"
    else
        values+=" ${value}"
    fi

    INVERTED_INDEX["${index_key}"]="${values}"

    # 更新统计
    local entries="${INDEXES[${index_name}_entries]}"
    INDEXES["${index_name}_entries"]="$((entries + 1))"
}

# 查询倒排索引
query_inverted_index() {
    local index_name="$1"
    local key="$2"

    local index_key="${index_name}:${key}"
    local result="${INVERTED_INDEX[${index_key}]:-}"

    # 更新统计
    INDEX_STATS["${index_name}_queries"]="$((INDEX_STATS[${index_name}_queries] + 1))"

    if [[ -n "${result}" ]]; then
        INDEX_STATS["${index_name}_hits"]="$((INDEX_STATS[${index_name}_hits] + 1))"
        echo "${result}"
        return 0
    else
        INDEX_STATS["${index_name}_misses"]="$((INDEX_STATS[${index_name}_misses} + 1))"
        return 1
    fi
}

# ==============================================================================
# 停用词
# ==============================================================================
# 停用词列表
declare -gA STOP_WORDS=(
    [the]="1"
    [a]="1"
    [an]="1"
    [and]="1"
    [or]="1"
    [but]="1"
    [in]="1"
    [on]="1"
    [at]="1"
    [to]="1"
    [for]="1"
    [of]="1"
    [with]="1"
    [is]="1"
    [are]="1"
    [was]="1"
    [were]="1"
    [be]="1"
    [been]="1"
    [have]="1"
    [has]="1"
    [had]="1"
    [do]="1"
    [does]="1"
    [did]="1"
    [this]="1"
    [that]="1"
    [these]="1"
    [those]="1"
    [i]="1"
    [you]="1"
    [he]="1"
    [she]="1"
    [it]="1"
    [we]="1"
    [they]="1"
)

# 检查是否是停用词
is_stop_word() {
    local word="$1"

    if [[ -n "${STOP_WORDS[${word}]+isset}" ]]; then
        return 0
    fi

    return 1
}

# ==============================================================================
# 索引持久化
# ==============================================================================
# 持久化索引
persist_index() {
    local index_name="$1"

    local index_file="${INDEX_CONFIG[index_dir]}/${index_name}.idx"

    # 写入元数据
    {
        echo "# Z-Panel Pro 索引文件"
        echo "# 索引名称: ${index_name}"
        echo "# 类型: ${INDEXES[${index_name}_type]}"
        echo "# 创建时间: $(date -d "@${INDEXES[${index_name}_created]}" '+%Y-%m-%d %H:%M:%S')"
        echo "# 更新时间: $(date -d "@${INDEXES[${index_name}_updated]}" '+%Y-%m-%d %H:%M:%S')"
        echo "# 版本: ${INDEX_METADATA[${index_name}_version]}"
        echo ""

        # 写入索引数据
        for key in "${!INVERTED_INDEX[@]}"; do
            if [[ "${key}" == "${index_name}:"* ]]; then
                echo "${key}|${INVERTED_INDEX[${key}]}"
            fi
        done
    } > "${index_file}"

    # 压缩
    if [[ "${INDEX_CONFIG[compression]}" == "gzip" ]]; then
        gzip -f "${index_file}"
    fi
}

# 加载索引
load_index() {
    local index_file="$1"

    if [[ ! -f "${index_file}" ]]; then
        log_error "索引文件不存在: ${index_file}"
        return 1
    fi

    local temp_file="${index_file}"

    # 解压
    if [[ "${index_file}" == *.gz ]]; then
        temp_file="${index_file%.gz}"
        gunzip -c "${index_file}" > "${temp_file}"
    fi

    # 读取索引
    while IFS='|' read -r key value; do
        # 跳过注释和空行
        if [[ -z "${key}" ]] || [[ "${key}" == \#* ]]; then
            continue
        fi

        INVERTED_INDEX["${key}"]="${value}"
    done < "${temp_file}"

    # 清理临时文件
    if [[ "${temp_file}" != "${index_file}" ]]; then
        rm -f "${temp_file}"
    fi

    log_info "索引已加载: ${index_file}"
    return 0
}

# 加载所有索引
load_all_indexes() {
    local index_dir="${INDEX_CONFIG[index_dir]}"

    if [[ ! -d "${index_dir}" ]]; then
        return 0
    fi

    for index_file in "${index_dir}"/*.idx; do
        if [[ -f "${index_file}" ]] || [[ -f "${index_file}.gz" ]]; then
            load_index "${index_file}"
        fi
    done
}

# ==============================================================================
# 索引查询
# ==============================================================================
# 通用查询接口
query_index() {
    local index_name="$1"
    local query="$2"
    local query_type="${3:-auto}"

    if [[ -z "${INDEXES[${index_name}_type]+isset}" ]]; then
        log_error "索引不存在: ${index_name}"
        return 1
    fi

    local index_type="${INDEXES[${index_name}_type]}"

    # 自动检测查询类型
    if [[ "${query_type}" == "auto" ]]; then
        if [[ "${query}" == *" "* ]]; then
            query_type="fulltext"
        else
            query_type="hash"
        fi
    fi

    case "${query_type}" in
        hash)
            query_hash_index "${index_name}" "${query}"
            ;;
        inverted)
            query_inverted_index "${index_name}" "${query}"
            ;;
        fulltext)
            search_fulltext "${index_name}" "${query}"
            ;;
        *)
            log_error "不支持的查询类型: ${query_type}"
            return 1
            ;;
    esac
}

# ==============================================================================
# 索引统计
# ==============================================================================
# 获取索引统计
get_index_stats() {
    local index_name="$1"

    if [[ -z "${INDEXES[${index_name}_type]+isset}" ]]; then
        log_error "索引不存在: ${index_name}"
        return 1
    fi

    local stats=$(cat <<EOF
{
    "index_name": "${index_name}",
    "type": "${INDEXES[${index_name}_type]}",
    "entries": ${INDEXES[${index_name}_entries]},
    "size": "${INDEXES[${index_name}_size]}",
    "queries": ${INDEX_STATS[${index_name}_queries]},
    "hits": ${INDEX_STATS[${index_name}_hits]},
    "misses": ${INDEX_STATS[${index_name}_misses]},
    "hit_rate": $(calculate_hit_rate "${index_name}"),
    "created": ${INDEXES[${index_name}_created]},
    "updated": ${INDEXES[${index_name}_updated]}
}
EOF
)

    echo "${stats}"
}

# 计算命中率
calculate_hit_rate() {
    local index_name="$1"

    local queries="${INDEX_STATS[${index_name}_queries]}"
    local hits="${INDEX_STATS[${index_name}_hits]}"

    if [[ ${queries} -eq 0 ]]; then
        echo "0.00"
    else
        bc <<< "scale=2; ${hits} / ${queries} * 100"
    fi
}

# 获取所有索引列表
list_indexes() {
    local output=""

    for key in "${!INDEXES[@]}"; do
        if [[ "${key}" == *"_type" ]]; then
            local index_name="${key%_type}"
            local type="${INDEXES[${key}]}"
            local entries="${INDEXES[${index_name}_entries]}"
            local enabled="${INDEXES[${index_name}_enabled]}"

            output+="${index_name}|${type}|${entries}|${enabled}"$'\n'
        fi
    done

    echo "${output}"
}

# ==============================================================================
# 索引维护
# ==============================================================================
# 启动索引重建
start_index_rebuild() {
    local interval="${INDEX_CONFIG[rebuild_interval]}"

    while true; do
        sleep ${interval}

        # 重建所有索引
        for key in "${!INDEXES[@]}"; do
            if [[ "${key}" == *"_type" ]]; then
                local index_name="${key%_type}"
                local enabled="${INDEXES[${index_name}_enabled]}"

                if [[ "${enabled}" == "true" ]]; then
                    rebuild_index "${index_name}" > /dev/null
                fi
            fi
        done
    done
}

# 优化索引
optimize_index() {
    local index_name="$1"

    log_info "优化索引: ${index_name}"

    # 重建索引
    rebuild_index "${index_name}"

    # 清理缓存
    unset INDEX_CACHE["${index_name}"]

    log_info "索引优化完成: ${index_name}"
    return 0
}

# 获取索引大小
get_index_size() {
    local index_name="$1"

    local size=0

    for key in "${!INVERTED_INDEX[@]}"; do
        if [[ "${key}" == "${index_name}:"* ]]; then
            local value="${INVERTED_INDEX[${key}]}"
            size=$((${size} + ${#key} + ${#value}))
        fi
    done

    echo "${size}"
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f init_index_service
export -f create_index
export -f delete_index
export -f rebuild_index
export -f clear_index_data
export -f rebuild_hash_index
export -f add_hash_index_entry
export -f query_hash_index
export -f rebuild_fulltext_index
export -f add_fulltext_index_entry
export -f search_fulltext
export -f rebuild_inverted_index
export -f add_inverted_index_entry
export -f query_inverted_index
export -f is_stop_word
export -f persist_index
export -f load_index
export -f load_all_indexes
export -f query_index
export -f get_index_stats
export -f calculate_hit_rate
export -f list_indexes
export -f start_index_rebuild
export -f optimize_index
export -f get_index_size
