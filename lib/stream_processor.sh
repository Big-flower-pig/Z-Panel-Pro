#!/bin/bash
# ==============================================================================
# Z-Panel Pro V8.0 - 流式数据处理引擎
# ==============================================================================
# @description    高效的流式数据处理和批量采集
# @version       8.0.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 流式处理器配置
# ==============================================================================
declare -gA STREAM_PROCESSOR=(
    # 管道配置
    [pipe_dir]="/tmp/zpanel/pipes"
    [buffer_size]="65536"      # 64KB buffer

    # 批量处理配置
    [batch_size]="100"          # 每批处理100条
    [batch_timeout]="1"         # 批处理超时（秒）

    # 性能配置
    [use_zero_copy]="true"      # 启用零拷贝
    [use_shared_memory]="true"  # 启用共享内存
)

# ==============================================================================
# 流式处理器状态
# ==============================================================================
declare -gA STREAM_PIPES=()
declare -gA STREAM_PROCESSES=()
declare -g STREAM_PROCESSOR_RUNNING=false

# ==============================================================================
# 管道管理函数
# ==============================================================================

# 创建命名管道
# @param name: 管道名称
# @return: 管道路径
create_named_pipe() {
    local name="$1"
    local pipe_dir="${STREAM_PROCESSOR[pipe_dir]}"
    local pipe_path="${pipe_dir}/${name}.pipe"

    # 创建管道目录
    mkdir -p "${pipe_dir}" 2>/dev/null || return 1

    # 删除已存在的管道
    [[ -p "${pipe_path}" ]] && rm -f "${pipe_path}"

    # 创建命名管道
    mkfifo "${pipe_path}" 2>/dev/null || {
        log_error "创建管道失败: ${pipe_path}"
        return 1
    }

    # 设置权限
    chmod 600 "${pipe_path}" 2>/dev/null || true

    # 记录管道
    STREAM_PIPES["${name}"]="${pipe_path}"

    log_debug "创建管道: ${pipe_path}"
    echo "${pipe_path}"
    return 0
}

# 删除命名管道
# @param name: 管道名称
delete_named_pipe() {
    local name="$1"
    local pipe_path="${STREAM_PIPES[${name}]}"

    [[ -z "${pipe_path}" ]] && return 0
    [[ ! -p "${pipe_path}" ]] && return 0

    rm -f "${pipe_path}" 2>/dev/null || true
    unset STREAM_PIPES["${name}"]

    log_debug "删除管道: ${pipe_path}"
    return 0
}

# 清理所有管道
cleanup_all_pipes() {
    for name in "${!STREAM_PIPES[@]}"; do
        delete_named_pipe "${name}"
    done
    return 0
}

# ==============================================================================
# 流式数据处理
# ==============================================================================

# 流式数据处理器
# @param input_pipe: 输入管道
# @param output_pipe: 输出管道（可选）
# @param processor_func: 处理函数名称
stream_processor() {
    local input_pipe="$1"
    local output_pipe="${2:-}"
    local processor_func="${3:-default_stream_processor}"

    # 验证输入管道
    [[ ! -p "${input_pipe}" ]] && {
        log_error "输入管道不存在: ${input_pipe}"
        return 1
    }

    log_debug "启动流式处理器: ${input_pipe} -> ${output_pipe}"

    # 打开输入管道（非阻塞）
    exec 3<>"${input_pipe}"

    # 处理循环
    local line_count=0
    local batch_buffer=""
    local last_batch_time=$(date +%s)

    while true; do
        # 读取数据
        if read -r -t 0.1 line <&3; then
            # 处理数据
            local processed
            processed=$(${processor_func} "${line}")

            # 添加到批处理缓冲区
            batch_buffer+="${processed}"$'\n'
            ((line_count++))

            # 检查批处理条件
            local current_time=$(date +%s)
            local batch_size="${STREAM_PROCESSOR[batch_size]}"
            local batch_timeout="${STREAM_PROCESSOR[batch_timeout]}"

            if [[ ${line_count} -ge ${batch_size} ]] || \
               [[ $((current_time - last_batch_time)) -ge ${batch_timeout} ]]; then

                # 输出批处理结果
                if [[ -n "${output_pipe}" ]]; then
                    echo "${batch_buffer}" > "${output_pipe}" 2>/dev/null || true
                else
                    echo "${batch_buffer}"
                fi

                # 重置缓冲区
                batch_buffer=""
                line_count=0
                last_batch_time=${current_time}
            fi
        fi

        # 检查处理器状态
        [[ "${STREAM_PROCESSOR_RUNNING}" == "false" ]] && break

        sleep 0.01
    done

    # 输出剩余数据
    if [[ -n "${batch_buffer}" ]]; then
        if [[ -n "${output_pipe}" ]]; then
            echo "${batch_buffer}" > "${output_pipe}" 2>/dev/null || true
        else
            echo "${batch_buffer}"
        fi
    fi

    # 关闭管道
    exec 3>&-

    log_debug "流式处理器退出"
    return 0
}

# 默认流处理器
# @param line: 输入行
# @return: 处理后的行
default_stream_processor() {
    local line="$1"

    # 基本处理：去除空白，转义特殊字符
    local processed
    processed=$(echo "${line}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/\\/\\\\/g;s/"/\\"/g')

    echo "${processed}"
}

# JSON 流处理器
# @param line: 输入行
# @return: JSON格式行
json_stream_processor() {
    local line="$1"

    # 基本处理
    local processed
    processed=$(default_stream_processor "${line}")

    # 尝试JSON验证
    if echo "${processed}" | jq -e '.' >/dev/null 2>&1; then
        echo "${processed}"
    else
        # 包装为JSON字符串
        echo "{\"value\": \"${processed}\", \"timestamp\": $(date +%s)}"
    fi
}

# ==============================================================================
# 批量数据采集
# ==============================================================================

# 批量采集所有系统指标
# @return: 格式化的批量数据
batch_collect_metrics() {
    local output
    output=$(
        # 内存信息
        echo "===MEMORY==="
        free -m 2>/dev/null

        # ZRAM信息
        echo "===ZRAM==="
        zramctl 2>/dev/null || echo "disabled"

        # Swap信息
        echo "===SWAP==="
        swapon --show=NAME,SIZE,USED,PRIO --noheadings 2>/dev/null || echo "none"

        # 系统负载
        echo "===LOAD==="
        cat /proc/loadavg 2>/dev/null

        # 内核参数
        echo "===KERNEL==="
        sysctl vm.swappiness vm.dirty_ratio vm.vfs_cache_pressure 2>/dev/null

        # CPU信息
        echo "===CPU==="
        grep -m1 "model name" /proc/cpuinfo 2>/dev/null || echo "unknown"

        # 进程信息（前20个）
        echo "===PROCESSES==="
        ps aux --sort=-%mem 2>/dev/null | head -20 || echo "none"
    )

    echo "${output}"
}

# 解析批量采集的数据
# @param batch_data: 批量数据
# @return: 关联数组格式的数据
parse_batch_metrics() {
    local batch_data="$1"

    # 使用临时文件存储解析结果
    local tmp_file="/tmp/zpanel/batch_parse_$$"
    mkdir -p "/tmp/zpanel" 2>/dev/null

    # 解析内存信息
    local mem_total mem_used mem_avail buff_cache
    mem_total=$(echo "${batch_data}" | sed -n '/===MEMORY===/,/===/p' | awk '/^Mem:/ {print $2}')
    mem_used=$(echo "${batch_data}" | sed -n '/===MEMORY===/,/===/p' | awk '/^Mem:/ {print $3}')
    mem_avail=$(echo "${batch_data}" | sed -n '/===MEMORY===/,/===/p' | awk '/^Mem:/ {print $7}')
    buff_cache=$(echo "${batch_data}" | sed -n '/===MEMORY===/,/===/p' | awk '/^Mem:/ {print $6}')

    # 解析ZRAM信息
    local zram_total zram_used zram_comp_ratio
    local zram_info
    zram_info=$(echo "${batch_data}" | sed -n '/===ZRAM===/,/===/p' | tail -1)
    if [[ "${zram_info}" != "disabled" ]]; then
        zram_total=$(echo "${zram_info}" | awk '{print $2}')
        zram_used=$(echo "${zram_info}" | awk '{print $3}')
        zram_comp_ratio=$(echo "${zram_info}" | awk '{print $4}')
    fi

    # 解析Swap信息
    local swap_total swap_used
    local swap_info
    swap_info=$(echo "${batch_data}" | sed -n '/===SWAP===/,/===/p' | head -1)
    if [[ "${swap_info}" != "none" ]]; then
        swap_total=$(echo "${swap_info}" | awk '{print $2}')
        swap_used=$(echo "${swap_info}" | awk '{print $3}')
    fi

    # 生成JSON输出
    cat <<EOF
{
    "memory": {
        "total": ${mem_total:-0},
        "used": ${mem_used:-0},
        "available": ${mem_avail:-0},
        "buff_cache": ${buff_cache:-0}
    },
    "zram": {
        "total": "${zram_total:-0}",
        "used": "${zram_used:-0}",
        "compression_ratio": "${zram_comp_ratio:-1.00}"
    },
    "swap": {
        "total": "${swap_total:-0}",
        "used": "${swap_used:-0}"
    },
    "timestamp": $(date +%s)
}
EOF

    # 清理临时文件
    rm -f "${tmp_file}" 2>/dev/null
}

# ==============================================================================
# 零拷贝优化
# ==============================================================================

# 零拷贝数据传输（使用 dd）
# @param input: 输入文件/管道
# @param output: 输出文件/管道
# @return: 0=成功, 1=失败
zero_copy_transfer() {
    local input="$1"
    local output="$2"
    local buffer_size="${STREAM_PROCESSOR[buffer_size]}"

    # 检查是否启用零拷贝
    [[ "${STREAM_PROCESSOR[use_zero_copy]}" != "true" ]] && {
        cp "${input}" "${output}" 2>/dev/null
        return $?
    }

    # 使用 dd 进行零拷贝传输
    dd if="${input}" of="${output}" \
       bs="${buffer_size}" \
       iflag=direct,nocache \
       oflag=direct,nocache \
       2>/dev/null

    return $?
}

# tee 数据复制
# @param input: 输入文件/管道
# @param output1: 输出文件1
# @param output2: 输出文件2
# @return: 0=成功, 1=失败
tee_data() {
    local input="$1"
    local output1="$2"
    local output2="$3"

    tee "${output1}" "${output2}" < "${input}" >/dev/null 2>&1
    return $?
}

# ==============================================================================
# 共享内存操作
# ==============================================================================

# 创建共享内存
# @param size: 大小（MB）
# @param name: 名称（可选）
# @return: 共享内存文件路径
create_shared_memory() {
    local size="$1"
    local name="${2:-zpanel}"
    local shm_file="/dev/shm/${name}"

    # 检查是否启用共享内存
    [[ "${STREAM_PROCESSOR[use_shared_memory]}" != "true" ]] && {
        echo ""
        return 0
    }

    # 创建共享内存文件
    dd if=/dev/zero of="${shm_file}" \
       bs=1M count="${size}" \
       2>/dev/null || {
        log_error "创建共享内存失败: ${shm_file}"
        return 1
    }

    # 设置权限
    chmod 600 "${shm_file}" 2>/dev/null || true

    log_debug "创建共享内存: ${shm_file} (${size}MB)"
    echo "${shm_file}"
    return 0
}

# 删除共享内存
# @param name: 名称
delete_shared_memory() {
    local name="$1"
    local shm_file="/dev/shm/${name}"

    [[ ! -f "${shm_file}" ]] && return 0

    rm -f "${shm_file}" 2>/dev/null || true

    log_debug "删除共享内存: ${shm_file}"
    return 0
}

# 写入共享内存
# @param shm_file: 共享内存文件
# @param data: 数据
write_shared_memory() {
    local shm_file="$1"
    local data="$2"

    [[ ! -f "${shm_file}" ]] && return 1

    echo "${data}" > "${shm_file}" 2>/dev/null || return 1

    return 0
}

# 读取共享内存
# @param shm_file: 共享内存文件
# @return: 数据
read_shared_memory() {
    local shm_file="$1"

    [[ ! -f "${shm_file}" ]] && return 1

    cat "${shm_file}" 2>/dev/null
}

# ==============================================================================
# 数据预处理
# ==============================================================================

# 预处理数据
# @param data: 原始数据
# @return: 预处理后的数据
preprocess_data() {
    local data="$1"

    # 去除空白
    data=$(echo "${data}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # 转义特殊字符
    data=$(echo "${data}" | sed 's/\\/\\\\/g;s/"/\\"/g;s/\$/\\$/g')

    echo "${data}"
}

# 数据转换
# @param data: 预处理后的数据
# @param format: 目标格式 (text/json/csv)
# @return: 转换后的数据
transform_data() {
    local data="$1"
    local format="${2:-text}"

    case "${format}" in
        json)
            # 转换为JSON
            echo "{\"value\": \"${data}\", \"timestamp\": $(date +%s)}"
            ;;
        csv)
            # 转换为CSV
            echo "${data},$(date +%s)"
            ;;
        *)
            # 默认文本格式
            echo "${data}"
            ;;
    esac
}

# 数据聚合
# @param data: 数据流
# @param agg_type: 聚合类型 (sum/avg/min/max/count)
# @return: 聚合结果
aggregate_data() {
    local data="$1"
    local agg_type="${2:-avg}"

    # 提取数值
    local values=()
    while IFS= read -r line; do
        local num
        num=$(echo "${line}" | grep -oP '[0-9]+(\.[0-9]+)?' | head -1)
        [[ -n "${num}" ]] && values+=("${num}")
    done <<< "${data}"

    [[ ${#values[@]} -eq 0 ]] && return 1

    case "${agg_type}" in
        sum)
            local sum=0
            for val in "${values[@]}"; do
                sum=$(echo "${sum} + ${val}" | bc -l 2>/dev/null || echo "${sum}")
            done
            echo "${sum}"
            ;;
        avg)
            local sum=0
            local count=${#values[@]}
            for val in "${values[@]}"; do
                sum=$(echo "${sum} + ${val}" | bc -l 2>/dev/null || echo "${sum}")
            done
            echo "scale=2; ${sum} / ${count}" | bc -l 2>/dev/null || echo "0"
            ;;
        min)
            local min="${values[0]}"
            for val in "${values[@]}"; do
                min=$(echo "if (${val} < ${min}) ${val} else ${min}" | bc -l 2>/dev/null || echo "${min}")
            done
            echo "${min}"
            ;;
        max)
            local max="${values[0]}"
            for val in "${values[@]}"; do
                max=$(echo "if (${val} > ${max}) ${val} else ${max}" | bc -l 2>/dev/null || echo "${max}")
            done
            echo "${max}"
            ;;
        count)
            echo "${#values[@]}"
            ;;
        *)
            echo "0"
            ;;
    esac
}

# ==============================================================================
# 流式处理器控制
# ==============================================================================

# 启动流式处理器
start_stream_processor() {
    local name="$1"
    local processor_func="${2:-default_stream_processor}"

    [[ "${STREAM_PROCESSOR_RUNNING}" == "true" ]] && {
        log_warn "流式处理器已在运行"
        return 0
    }

    # 创建管道
    local input_pipe
    input_pipe=$(create_named_pipe "${name}.in") || return 1

    local output_pipe
    output_pipe=$(create_named_pipe "${name}.out") || return 1

    # 启动处理器
    stream_processor "${input_pipe}" "${output_pipe}" "${processor_func}" &
    STREAM_PROCESSES["${name}"]=$!

    STREAM_PROCESSOR_RUNNING=true
    log_info "流式处理器已启动: ${name} (PID: ${STREAM_PROCESSES[${name}]})"

    return 0
}

# 停止流式处理器
stop_stream_processor() {
    local name="$1"

    local pid="${STREAM_PROCESSES[${name}]}"
    [[ -z "${pid}" ]] && return 0

    log_info "停止流式处理器: ${name} (PID: ${pid})"

    if kill -0 "${pid}" 2>/dev/null; then
        kill "${pid}" 2>/dev/null
        wait "${pid}" 2>/dev/null
    fi

    # 删除管道
    delete_named_pipe "${name}.in"
    delete_named_pipe "${name}.out"

    unset STREAM_PROCESSES["${name}"]

    # 检查是否还有处理器在运行
    local running_count=0
    for p in "${!STREAM_PROCESSES[@]}"; do
        [[ -n "${STREAM_PROCESSES[${p}]}" ]] && ((running_count++))
    done

    [[ ${running_count} -eq 0 ]] && STREAM_PROCESSOR_RUNNING=false

    return 0
}

# 停止所有流式处理器
stop_all_stream_processors() {
    for name in "${!STREAM_PROCESSES[@]}"; do
        stop_stream_processor "${name}"
    done

    STREAM_PROCESSOR_RUNNING=false
    return 0
}

# 检查流式处理器状态
is_stream_processor_running() {
    local name="$1"
    local pid="${STREAM_PROCESSES[${name}]}"

    [[ -z "${pid}" ]] && return 1
    [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null && return 0 || return 1
}

# 获取流式处理器状态
get_stream_processor_status() {
    cat <<EOF
{
    "running": ${STREAM_PROCESSOR_RUNNING},
    "processors": {
$(for name in "${!STREAM_PROCESSES[@]}"; do
    local pid="${STREAM_PROCESSES[${name}]}"
    local status="stopped"
    [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null && status="running"
    echo "        \"${name}\": {\"pid\": ${pid:-0}, \"status\": \"${status}\"},"
done | sed '$ s/,$//')
    },
    "config": {
        "pipe_dir": "${STREAM_PROCESSOR[pipe_dir]}",
        "buffer_size": ${STREAM_PROCESSOR[buffer_size]},
        "batch_size": ${STREAM_PROCESSOR[batch_size]},
        "batch_timeout": ${STREAM_PROCESSOR[batch_timeout]},
        "use_zero_copy": ${STREAM_PROCESSOR[use_zero_copy]},
        "use_shared_memory": ${STREAM_PROCESSOR[use_shared_memory]}
    }
}
EOF
}

# ==============================================================================
# 初始化和清理
# ==============================================================================

# 初始化流式处理器
init_stream_processor() {
    log_debug "初始化流式处理器..."

    # 创建管道目录
    mkdir -p "${STREAM_PROCESSOR[pipe_dir]}" 2>/dev/null || true

    # 创建共享内存目录
    mkdir -p "/dev/shm/zpanel" 2>/dev/null || true

    log_debug "流式处理器初始化完成"
    return 0
}

# 清理流式处理器
cleanup_stream_processor() {
    log_debug "清理流式处理器..."

    # 停止所有处理器
    stop_all_stream_processors

    # 清理所有管道
    cleanup_all_pipes

    # 清理共享内存
    rm -rf "/dev/shm/zpanel" 2>/dev/null || true

    log_debug "流式处理器清理完成"
    return 0
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f create_named_pipe
export -f delete_named_pipe
export -f stream_processor
export -f batch_collect_metrics
export -f parse_batch_metrics
export -f zero_copy_transfer
export -f create_shared_memory
export -f delete_shared_memory
