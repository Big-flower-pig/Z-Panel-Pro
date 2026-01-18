#!/bin/bash
# ==============================================================================
# Z-Panel Pro V9.0 - 性能监控模块
# ==============================================================================
# @description    性能指标收集与监控
# @version       9.0.0-Lightweight
# @author        Z-Panel Team
# @license       MIT License
# ==============================================================================

# ==============================================================================
# 性能监控配置
# ==============================================================================
declare -gA PERFORMANCE_METRICS=(
    [function_calls]=0
    [cache_hits]=0
    [cache_misses]=0
    [system_calls]=0
    [disk_io_operations]=0
    [network_operations]=0
)

declare -gA FUNCTION_TIMINGS=()
declare -g PERFORMANCE_START_TIME=$(date +%s)
declare -g PERFORMANCE_MONITOR_ENABLED=true

# ==============================================================================
# 性能追踪
# ==============================================================================

# 开始性能计时
start_timer() {
    local timer_name="$1"
    FUNCTION_TIMINGS["${timer_name}_start"]=$(date +%s%N)
}

# 结束性能计时
end_timer() {
    local timer_name="$1"

    if [[ -n "${FUNCTION_TIMINGS[${timer_name}_start]:-}" ]]; then
        local start_time=${FUNCTION_TIMINGS[${timer_name}_start]}
        local end_time=$(date +%s%N)
        local duration=$(( (end_time - start_time) / 1000000 ))

        FUNCTION_TIMINGS["${timer_name}_duration"]=${duration}
        ((PERFORMANCE_METRICS[function_calls]++)) || true

        log_debug "性能: ${timer_name} 耗时 ${duration}ms"
    fi
}

# 追踪函数调用
track_function_call() {
    local function_name="$1"
    ((PERFORMANCE_METRICS[function_calls]++)) || true
}

# 追踪系统调用
track_system_call() {
    ((PERFORMANCE_METRICS[system_calls]++)) || true
}

# 追踪磁盘IO
track_disk_io() {
    ((PERFORMANCE_METRICS[disk_io_operations]++)) || true
}

# 追踪网络操作
track_network_operation() {
    ((PERFORMANCE_METRICS[network_operations]++)) || true
}

# ==============================================================================
# 性能报告
# ==============================================================================

# 获取性能报告
get_performance_report() {
    local uptime=$(($(date +%s) - PERFORMANCE_START_TIME))
    local function_calls=${PERFORMANCE_METRICS[function_calls]:-0}
    local system_calls=${PERFORMANCE_METRICS[system_calls]:-0}
    local disk_io=${PERFORMANCE_METRICS[disk_io_operations]:-0}
    local network_ops=${PERFORMANCE_METRICS[network_operations]:-0}

    # 计算平均调用率
    local calls_per_second=0
    [[ ${uptime} -gt 0 ]] && calls_per_second=$(echo "scale=2; ${function_calls} / ${uptime}" | bc)

    # 获取缓存统计
    local cache_stats
    cache_stats=$(get_cache_stats 2>/dev/null || echo '{"hits":0,"misses":0}')
    local cache_hits=$(echo "${cache_stats}" | grep -o '"hits": [0-9]*' | awk '{print $2}')
    local cache_misses=$(echo "${cache_stats}" | grep -o '"misses": [0-9]*' | awk '{print $2}')
    PERFORMANCE_METRICS[cache_hits]=${cache_hits}
    PERFORMANCE_METRICS[cache_misses]=${cache_misses}

    cat <<EOF
{
    "uptime_seconds": ${uptime},
    "metrics": {
        "function_calls": ${function_calls},
        "system_calls": ${system_calls},
        "disk_io_operations": ${disk_io},
        "network_operations": ${network_ops},
        "cache_hits": ${cache_hits},
        "cache_misses": ${cache_misses},
        "calls_per_second": ${calls_per_second}
    },
    "function_timings": {
$(for key in "${!FUNCTION_TIMINGS[@]}"; do
    [[ "${key}" =~ _duration$ ]] && echo "        \"${key%_duration}\": ${FUNCTION_TIMINGS[$key]},"
done | sed '$ s/,$//')
    }
}
EOF
}

# 获取性能摘要
get_performance_summary() {
    local uptime=$(($(date +%s) - PERFORMANCE_START_TIME))
    local function_calls=${PERFORMANCE_METRICS[function_calls]:-0}
    local cache_hits=${PERFORMANCE_METRICS[cache_hits]:-0}
    local cache_misses=${PERFORMANCE_METRICS[cache_misses]:-0}
    local total_cache=$((cache_hits + cache_misses))
    local cache_hit_rate=0
    [[ ${total_cache} -gt 0 ]] && cache_hit_rate=$((cache_hits * 100 / total_cache))

    cat <<EOF
性能监控摘要
================================================================================

运行时间: $(format_duration ${uptime}) 秒

性能指标:
  函数调用次数: ${function_calls}
  系统调用次数: ${PERFORMANCE_METRICS[system_calls]:-0}
  磁盘IO操作: ${PERFORMANCE_METRICS[disk_io_operations]:-0}
  网络操作次数: ${PERFORMANCE_METRICS[network_operations]:-0}

缓存统计:
  缓存命中: ${cache_hits}
  缓存未命中: ${cache_misses}
  缓存命中率: ${cache_hit_rate}%

================================================================================
EOF
}

# 重置性能统计
reset_performance_stats() {
    PERFORMANCE_METRICS=(
        [function_calls]=0
        [cache_hits]=0
        [cache_misses]=0
        [system_calls]=0
        [disk_io_operations]=0
        [network_operations]=0
    )
    FUNCTION_TIMINGS=()
    PERFORMANCE_START_TIME=$(date +%s)

    log_debug "性能统计已重置"
}

# ==============================================================================
# 性能分析
# ==============================================================================

# 分析性能瓶颈
analyze_performance_bottlenecks() {
    local report=""

    # 分析函数执行时间
    local slow_functions=()
    for key in "${!FUNCTION_TIMINGS[@]}"; do
        if [[ "${key}" =~ _duration$ ]]; then
            local duration=${FUNCTION_TIMINGS[$key]}
            local func_name="${key%_duration}"

            if [[ ${duration} -gt 1000 ]]; then
                slow_functions+=("${func_name}:${duration}ms")
            fi
        fi
    done

    if [[ ${#slow_functions[@]} -gt 0 ]]; then
        report+="检测到慢速函数:\n"
        for func in "${slow_functions[@]}"; do
            report+="  - ${func}\n"
        done
        report+="\n建议: 优化这些函数以提升性能\n"
    else
        report+="未检测到明显的性能瓶颈\n"
    fi

    # 分析缓存命中率
    local cache_hits=${PERFORMANCE_METRICS[cache_hits]:-0}
    local cache_misses=${PERFORMANCE_METRICS[cache_misses]:-0}
    local total_cache=$((cache_hits + cache_misses))

    if [[ ${total_cache} -gt 0 ]]; then
        local cache_hit_rate=$((cache_hits * 100 / total_cache))
        if [[ ${cache_hit_rate} -lt 70 ]]; then
            report+="警告: 缓存命中率较低 (${cache_hit_rate}%)\n"
            report+="建议: 检查缓存策略或增加缓存TTL\n"
        fi
    fi

    echo -e "${report}"
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f start_timer
export -f end_timer
export -f track_function_call
export -f track_system_call
export -f track_disk_io
export -f track_network_operation
export -f get_performance_report
export -f get_performance_summary
export -f reset_performance_stats
export -f analyze_performance_bottlenecks
