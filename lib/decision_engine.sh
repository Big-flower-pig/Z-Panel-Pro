#!/bin/bash
# ==============================================================================
# Z-Panel Pro V8.0 - 智能决策引擎
# ==============================================================================
# @description    基于时序数据分析和机器学习的内存优化决策引擎
# @version       8.0.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 决策引擎核心配置
# ==============================================================================
declare -gA DECISION_ENGINE=(
    # 时序数据配置
    [history_window]="300"      # 保留最近300个数据点（5分钟）
    [prediction_window]="60"     # 预测未来60秒

    # 预测算法配置
    [sma_period]="20"           # SMA计算周期
    [ema_alpha]="0.2"           # EMA平滑系数
    [trend_window]="30"         # 趋势检测窗口

    # 决策阈值
    [memory_pressure_high]="85"      # 高压阈值
    [memory_pressure_critical]="95"   # 临界阈值
    [zram_usage_high]="80"          # ZRAM高压阈值
    [zram_compression_min]="2.0"    # 最小压缩比
    [zram_compression_good]="3.0"   # 良好压缩比

    # 自适应参数
    [auto_tune]="true"          # 自动调优开关
    [learning_rate]="0.01"      # 学习率
    [decision_interval]="5"     # 决策间隔（秒）

    # 反馈循环
    [feedback_enabled]="true"   # 反馈循环开关
    [min_confidence]="70"       # 最小置信度
)

# ==============================================================================
# 时序数据存储
# ==============================================================================
declare -gA TIME_SERIES_DATA=(
    [memory_usage]=""
    [memory_available]=""
    [zram_usage]=""
    [zram_compression]=""
    [swap_usage]=""
    [io_pressure]=""
    [cpu_usage]=""
)

# 数据点时间戳
declare -gA TIME_SERIES_TIMESTAMPS=()

# ==============================================================================
# 决策历史
# ==============================================================================
declare -gA DECISION_HISTORY=(
    [last_decision_time]="0"
    [decision_count]="0"
    [success_count]="0"
    [failure_count]="0"
    [last_decision_type]="none"
)

# ==============================================================================
# 决策效果统计
# ==============================================================================
declare -gA DECISION_EFFECTS=(
    [last_baseline]=""
    [last_improvement]="0"
    [avg_improvement]="0"
    [total_evaluations]="0"
)

# ==============================================================================
# 决策引擎运行状态
# ==============================================================================
declare -g DECISION_ENGINE_PID=""
declare -g DECISION_ENGINE_RUNNING=false

# ==============================================================================
# 时序数据管理函数
# ==============================================================================

# 添加时序数据点
# @param metric: 指标名称
# @param value: 数据值
# @param timestamp: 时间戳（可选，默认当前时间）
# @return: 0=成功, 1=失败
add_time_series_data() {
    local metric="$1"
    local value="$2"
    local timestamp="${3:-$(date +%s)}"

    # 验证参数
    [[ -z "${metric}" ]] && return 1
    [[ -z "${value}" ]] && return 1

    # 获取当前数据
    local current_data="${TIME_SERIES_DATA[${metric}]}"
    local max_points="${DECISION_ENGINE[history_window]}"

    # 解析现有数据
    local points=()
    if [[ -n "${current_data}" ]]; then
        local IFS=$'\n'
        read -ra points <<< "${current_data}"
    fi

    # 超过最大长度，移除最旧的数据
    if [[ ${#points[@]} -ge ${max_points} ]]; then
        points=("${points[@]:1}")
    fi

    # 添加新数据点（格式：timestamp:value）
    points+=("${timestamp}:${value}")

    # 重新组合数据
    local IFS=$'\n'
    TIME_SERIES_DATA["${metric}"]="${points[*]}"

    # 更新时间戳
    TIME_SERIES_TIMESTAMPS["${metric}"]="${timestamp}"

    return 0
}

# 获取时序数据
# @param metric: 指标名称
# @param count: 获取数量（可选，默认10）
# @return: 数据点列表（每行：timestamp:value）
get_time_series_data() {
    local metric="$1"
    local count="${2:-10}"

    local data="${TIME_SERIES_DATA[${metric}]}"
    [[ -z "${data}" ]] && return 1

    local IFS=$'\n'
    local points=()
    read -ra points <<< "${data}"

    # 返回最近的 N 个数据点
    local start_idx=$((${#points[@]} - count))
    [[ ${start_idx} -lt 0 ]] && start_idx=0

    for ((i=start_idx; i<${#points[@]}; i++)); do
        echo "${points[i]}"
    done

    return 0
}

# 获取最新数据点
# @param metric: 指标名称
# @return: 最新值
get_latest_data_point() {
    local metric="$1"

    local data="${TIME_SERIES_DATA[${metric}]}"
    [[ -z "${data}" ]] && return 1

    # 获取最后一行
    echo "${data}" | tail -1 | cut -d':' -f2
}

# 清除时序数据
# @param metric: 指标名称（可选，不指定则清除所有）
clear_time_series_data() {
    local metric="$1"

    if [[ -z "${metric}" ]]; then
        # 清除所有数据
        for key in "${!TIME_SERIES_DATA[@]}"; do
            TIME_SERIES_DATA["${key}"]=""
        done
    else
        # 清除指定指标
        TIME_SERIES_DATA["${metric}"]=""
    fi

    return 0
}

# ==============================================================================
# 预测引擎
# ==============================================================================

# 简单移动平均预测 (Simple Moving Average)
# @param metric: 指标名称
# @param horizon: 预测步数（可选，默认10）
# @return: 预测值列表
predict_sma() {
    local metric="$1"
    local horizon="${2:-10}"

    # 获取历史数据
    local data
    data=$(get_time_series_data "${metric}" "${DECISION_ENGINE[sma_period]}")
    [[ -z "${data}" ]] && return 1

    # 提取值并计算平均值
    local sum=0
    local count=0
    local values=()

    while IFS=':' read -r timestamp value; do
        [[ -z "${value}" ]] && continue
        [[ ! "${value}" =~ ^[0-9]+(\.[0-9]+)?$ ]] && continue

        values+=("${value}")
        sum=$(echo "${sum} + ${value}" | bc -l 2>/dev/null || echo "${sum}")
        ((count++))
    done <<< "${data}"

    [[ ${count} -eq 0 ]] && return 1

    # 使用 bc 计算平均值（支持浮点数）
    local avg
    avg=$(echo "scale=2; ${sum} / ${count}" | bc -l 2>/dev/null || echo "${sum}")

    # 简单线性预测（返回相同值）
    local predictions=()
    for ((i=0; i<horizon; i++)); do
        predictions+=("${avg}")
    done

    echo "${predictions[@]}"
}

# 指数移动平均预测 (Exponential Moving Average)
# @param metric: 指标名称
# @param horizon: 预测步数（可选，默认10）
# @param alpha: 平滑系数（可选，默认配置值）
# @return: 预测值
predict_ema() {
    local metric="$1"
    local horizon="${2:-10}"
    local alpha="${3:-${DECISION_ENGINE[ema_alpha]}}"

    # 获取历史数据
    local data
    data=$(get_time_series_data "${metric}" 50)
    [[ -z "${data}" ]] && return 1

    # 计算 EMA
    local ema=0
    local count=0

    while IFS=':' read -r timestamp value; do
        [[ -z "${value}" ]] && continue
        [[ ! "${value}" =~ ^[0-9]+(\.[0-9]+)?$ ]] && continue

        if [[ ${count} -eq 0 ]]; then
            ema="${value}"
        else
            # EMA = alpha * value + (1 - alpha) * EMA
            ema=$(echo "scale=2; ${alpha} * ${value} + (1 - ${alpha}) * ${ema}" | bc -l 2>/dev/null || echo "${value}")
        fi
        ((count++))
    done <<< "${data}"

    [[ ${count} -eq 0 ]] && return 1

    # 返回 EMA 作为预测值
    echo "${ema}"
}

# 检测趋势
# @param metric: 指标名称
# @param window: 检测窗口（可选，默认配置值）
# @return: 趋势类型 (rising/falling/stable)
detect_trend() {
    local metric="$1"
    local window="${2:-${DECISION_ENGINE[trend_window]}}"

    # 获取历史数据
    local data
    data=$(get_time_series_data "${metric}" "${window}")
    [[ -z "${data}" ]] && return 1

    # 提取值
    local values=()
    while IFS=':' read -r timestamp value; do
        [[ -n "${value}" ]] && values+=("${value}")
    done <<< "${data}"

    [[ ${#values[@]} -lt 2 ]] && return 1

    # 计算简单线性回归斜率
    local n=${#values[@]}
    local sum_x=0 sum_y=0 sum_xy=0 sum_x2=0

    for ((i=0; i<n; i++)); do
        sum_x=$((sum_x + i))
        sum_y=$(echo "${sum_y} + ${values[i]}" | bc -l 2>/dev/null || echo "${sum_y}")
        sum_xy=$(echo "${sum_xy} + ${i} * ${values[i]}" | bc -l 2>/dev/null || echo "${sum_xy}")
        sum_x2=$((sum_x2 + i * i))
    done

    # 计算斜率
    local slope
    slope=$(echo "scale=4; (${n} * ${sum_xy} - ${sum_x} * ${sum_y}) / (${n} * ${sum_x2} - ${sum_x} * ${sum_x})" | bc -l 2>/dev/null || echo "0")

    # 判断趋势
    local threshold=0.5
    local slope_int
    slope_int=$(echo "${slope}" | cut -d'.' -f1)

    if [[ ${slope_int} -gt 0 ]]; then
        echo "rising"
    elif [[ ${slope_int} -lt 0 ]]; then
        echo "falling"
    else
        echo "stable"
    fi
}

# 预测未来趋势
# @param metric: 指标名称
# @param steps: 预测步数（可选，默认配置值）
# @return: JSON格式预测结果
predict_future_trend() {
    local metric="$1"
    local steps="${2:-${DECISION_ENGINE[prediction_window]}}"

    # 获取当前值
    local current_value
    current_value=$(get_latest_data_point "${metric}")
    [[ -z "${current_value}" ]] && return 1

    # 获取趋势
    local trend
    trend=$(detect_trend "${metric}")

    # 获取 EMA 预测
    local ema_prediction
    ema_prediction=$(predict_ema "${metric}" 1)

    # 生成预测结果
    cat <<EOF
{
    "metric": "${metric}",
    "current": ${current_value},
    "trend": "${trend}",
    "ema_prediction": ${ema_prediction},
    "steps": ${steps},
    "timestamp": $(date +%s)
}
EOF
}

# ==============================================================================
# 状态分析
# ==============================================================================

# 分析当前系统状态
# @return: JSON格式状态报告
analyze_current_state() {
    # 获取内存信息
    local mem_total mem_used mem_avail buff_cache
    read -r mem_total mem_used mem_avail buff_cache <<< "$(get_memory_info false)"

    # 获取 ZRAM 信息
    local zram_total zram_used
    read -r zram_total zram_used <<< "$(get_zram_usage)"

    # 获取 Swap 信息
    local swap_total swap_used
    read -r swap_total swap_used <<< "$(get_swap_info false)"

    # 获取压缩比
    local compression_ratio
    compression_ratio=$(get_zram_compression_ratio)

    # 获取 swappiness
    local swappiness
    swappiness=$(get_swappiness)

    # 计算关键指标
    local mem_usage_percent mem_avail_percent
    [[ ${mem_total} -gt 0 ]] && mem_usage_percent=$((mem_used * 100 / mem_total)) || mem_usage_percent=0
    [[ ${mem_total} -gt 0 ]] && mem_avail_percent=$((mem_avail * 100 / mem_total)) || mem_avail_percent=0

    local zram_usage_percent=0
    [[ ${zram_total} -gt 0 ]] && zram_usage_percent=$((zram_used * 100 / zram_total)) || zram_usage_percent=0

    local swap_usage_percent=0
    [[ ${swap_total} -gt 0 ]] && swap_usage_percent=$((swap_used * 100 / swap_total)) || swap_usage_percent=0

    # 记录时序数据
    add_time_series_data "memory_usage" "${mem_usage_percent}"
    add_time_series_data "memory_available" "${mem_avail_percent}"
    add_time_series_data "zram_usage" "${zram_usage_percent}"
    [[ -n "${compression_ratio}" ]] && add_time_series_data "zram_compression" "${compression_ratio}"
    add_time_series_data "swap_usage" "${swap_usage_percent}"

    # 生成状态报告
    cat <<EOF
{
    "memory": {
        "total": ${mem_total},
        "used": ${mem_used},
        "available": ${mem_avail},
        "buff_cache": ${buff_cache},
        "usage_percent": ${mem_usage_percent},
        "available_percent": ${mem_avail_percent}
    },
    "zram": {
        "total": ${zram_total},
        "used": ${zram_used},
        "usage_percent": ${zram_usage_percent},
        "compression_ratio": "${compression_ratio}"
    },
    "swap": {
        "total": ${swap_total},
        "used": ${swap_used},
        "usage_percent": ${swap_usage_percent}
    },
    "kernel": {
        "swappiness": ${swappiness}
    },
    "timestamp": $(date +%s)
}
EOF
}

# 分析内存压力等级
# @param mem_usage_percent: 内存使用率
# @return: 压力等级 (low/medium/high/critical)
analyze_memory_pressure() {
    local mem_usage_percent="$1"
    local critical_threshold="${DECISION_ENGINE[memory_pressure_critical]}"
    local high_threshold="${DECISION_ENGINE[memory_pressure_high]}"

    if [[ ${mem_usage_percent} -ge ${critical_threshold} ]]; then
        echo "critical"
    elif [[ ${mem_usage_percent} -ge ${high_threshold} ]]; then
        echo "high"
    elif [[ ${mem_usage_percent} -ge 60 ]]; then
        echo "medium"
    else
        echo "low"
    fi
}

# ==============================================================================
# 决策生成
# ==============================================================================

# 生成优化决策
# @param state_json: 系统状态JSON
# @return: JSON格式决策
generate_decision() {
    local state_json="$1"

    # 解析内存使用率
    local mem_usage_percent
    mem_usage_percent=$(echo "${state_json}" | grep -o '"usage_percent":[0-9]*' | head -1 | cut -d':' -f2)
    [[ -z "${mem_usage_percent}" ]] && mem_usage_percent=0

    # 解析内存可用率
    local mem_avail_percent
    mem_avail_percent=$(echo "${state_json}" | grep -o '"available_percent":[0-9]*' | cut -d':' -f2)
    [[ -z "${mem_avail_percent}" ]] && mem_avail_percent=0

    # 解析 ZRAM 使用率
    local zram_usage_percent
    zram_usage_percent=$(echo "${state_json}" | grep -o '"zram".*"usage_percent":[0-9]*' | tail -1 | cut -d':' -f2)
    [[ -z "${zram_usage_percent}" ]] && zram_usage_percent=0

    # 解析压缩比
    local compression_ratio
    compression_ratio=$(echo "${state_json}" | grep -o '"compression_ratio":"[0-9.]*"' | cut -d'"' -f4)
    [[ -z "${compression_ratio}" ]] && compression_ratio="1.00"

    # 解析 Swap 使用率
    local swap_usage_percent
    swap_usage_percent=$(echo "${state_json}" | grep -o '"swap".*"usage_percent":[0-9]*' | tail -1 | cut -d':' -f2)
    [[ -z "${swap_usage_percent}" ]] && swap_usage_percent=0

    # 解析 swappiness
    local swappiness
    swappiness=$(echo "${state_json}" | grep -o '"swappiness":[0-9]*' | cut -d':' -f2)
    [[ -z "${swappiness}" ]] && swappiness=60

    # 分析内存压力
    local pressure_level
    pressure_level=$(analyze_memory_pressure "${mem_usage_percent}")

    # 检测趋势
    local memory_trend
    memory_trend=$(detect_trend "memory_usage")

    # 生成决策
    local decision_type="none"
    local priority="low"
    local confidence=100
    local params=()

    case "${pressure_level}" in
        critical)
            decision_type="critical"
            priority="critical"
            params+=("action=emergency_tune")
            params+=("target=reduce_memory_pressure")
            params+=("reason=memory_usage_${mem_usage_percent}%")
            ;;
        high)
            decision_type="high"
            priority="high"
            params+=("action=aggressive_tune")
            params+=("target=reduce_memory_usage")
            params+=("reason=memory_usage_${mem_usage_percent}%")
            ;;
        medium)
            decision_type="medium"
            priority="medium"
            params+=("action=optimize")
            params+=("target=balance_performance")
            ;;
        low)
            decision_type="low"
            priority="low"
            params+=("action=maintain")
            params+=("target=keep_current")
            ;;
    esac

    # ZRAM 优化决策
    local zram_threshold="${DECISION_ENGINE[zram_usage_high]}"
    if [[ ${zram_usage_percent} -ge 90 ]]; then
        params+=("zram_action=increase_size")
        params+=("zram_ratio=150")
        priority="high"
    elif [[ ${zram_usage_percent} -ge ${zram_threshold} ]]; then
        params+=("zram_action=monitor")
    fi

    # 压缩比优化
    local comp_min="${DECISION_ENGINE[zram_compression_min]}"
    local comp_good="${DECISION_ENGINE[zram_compression_good]}"
    local comp_value
    comp_value=$(echo "${compression_ratio}" | cut -d'.' -f1)

    if [[ ${comp_value} -lt 2 ]] && [[ ${zram_usage_percent} -gt 50 ]]; then
        params+=("zram_action=optimize_compression")
        params+=("algorithm=lz4")
    fi

    # Swap 优化决策
    if [[ ${swap_usage_percent} -ge 50 ]]; then
        params+=("swap_action=reduce_swappiness")
        local new_swappiness=$((swappiness - 10))
        [[ ${new_swappiness} -lt 10 ]] && new_swappiness=10
        params+=("new_swappiness=${new_swappiness}")
    elif [[ ${swap_usage_percent} -le 10 ]] && [[ ${swappiness} -lt 60 ]]; then
        params+=("swap_action=increase_swappiness")
        local new_swappiness=$((swappiness + 10))
        [[ ${new_swappiness} -gt 100 ]] && new_swappiness=100
        params+=("new_swappiness=${new_swappiness}")
    fi

    # 生成决策JSON
    echo "{"
    echo "    \"type\": \"${decision_type}\","
    echo "    \"priority\": \"${priority}\","
    echo "    \"confidence\": ${confidence},"
    echo "    \"timestamp\": $(date +%s),"
    echo "    \"pressure_level\": \"${pressure_level}\","
    echo "    \"memory_trend\": \"${memory_trend}\","
    echo "    \"actions\": ["

    local first=true
    for param in "${params[@]}"; do
        [[ "${first}" == "true" ]] && first=false || echo ","
        echo -n "        \"${param}\""
    done

    echo ""
    echo "    ]"
    echo "}"
}

# ==============================================================================
# 决策执行
# ==============================================================================

# 执行决策
# @param decision_json: 决策JSON
# @return: 0=成功, 1=失败
execute_decision() {
    local decision_json="$1"

    # 解析决策类型
    local decision_type
    decision_type=$(echo "${decision_json}" | grep -o '"type":"[^"]*"' | cut -d'"' -f4)
    [[ -z "${decision_type}" ]] && return 1

    # 解析优先级
    local priority
    priority=$(echo "${decision_json}" | grep -o '"priority":"[^"]*"' | cut -d'"' -f4)

    # 记录决策
    log_debug "执行决策: type=${decision_type}, priority=${priority}"

    # 根据类型执行不同策略
    case "${decision_type}" in
        critical)
            apply_emergency_tuning
            ;;
        high)
            apply_aggressive_tuning
            ;;
        medium)
            apply_standard_tuning
            ;;
        low)
            # 无需操作
            return 0
            ;;
        none)
            return 0
            ;;
        *)
            log_warn "未知决策类型: ${decision_type}"
            return 1
            ;;
    esac

    # 更新决策历史
    DECISION_HISTORY[last_decision_time]=$(date +%s)
    DECISION_HISTORY[decision_count]=$((DECISION_HISTORY[decision_count] + 1))
    DECISION_HISTORY[last_decision_type]="${decision_type}"

    return 0
}

# 紧急调优策略
apply_emergency_tuning() {
    log_warn "应用紧急调优策略..."

    # 降低 swappiness 到最低
    sysctl -w vm.swappiness=10 > /dev/null 2>&1

    # 降低脏数据阈值
    sysctl -w vm.dirty_ratio=5 > /dev/null 2>&1
    sysctl -w vm.dirty_background_ratio=2 > /dev/null 2>&1

    # 加快脏数据写入
    sysctl -w vm.dirty_expire_centisecs=1000 > /dev/null 2>&1
    sysctl -w vm.dirty_writeback_centisecs=100 > /dev/null 2>&1

    # 尝试释放缓存
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

    log_warn "紧急调优完成"
}

# 激进调优策略
apply_aggressive_tuning() {
    log_info "应用激进调优策略..."

    # 调整 swappiness
    local new_swappiness=30
    sysctl -w vm.swappiness=${new_swappiness} > /dev/null 2>&1

    # 优化 ZRAM 参数
    if is_zram_enabled; then
        local cpu_cores
        cpu_cores=$(get_cpu_cores)
        echo "${cpu_cores}" > /sys/block/zram0/max_comp_streams 2>/dev/null || true
    fi

    log_info "激进调优完成"
}

# 标准调优策略
apply_standard_tuning() {
    log_debug "应用标准调优策略..."

    # 动态调整 swappiness
    local mem_total mem_used mem_avail
    read -r mem_total mem_used mem_avail _ <<< "$(get_memory_info false)"

    local mem_usage_percent=0
    [[ ${mem_total} -gt 0 ]] && mem_usage_percent=$((mem_used * 100 / mem_total))

    local new_swappiness=60

    if [[ ${mem_usage_percent} -gt 80 ]]; then
        new_swappiness=40
    elif [[ ${mem_usage_percent} -gt 60 ]]; then
        new_swappiness=50
    elif [[ ${mem_usage_percent} -lt 40 ]]; then
        new_swappiness=80
    fi

    local current_swappiness
    current_swappiness=$(get_swappiness)

    if [[ ${new_swappiness} -ne ${current_swappiness} ]]; then
        sysctl -w vm.swappiness=${new_swappiness} > /dev/null 2>&1
        log_debug "调整 swappiness: ${current_swappiness} → ${new_swappiness}"
    fi

    log_debug "标准调优完成"
}

# ==============================================================================
# 决策引擎控制
# ==============================================================================

# 启动决策引擎
start_decision_engine() {
    [[ "${DECISION_ENGINE_RUNNING}" == "true" ]] && {
        log_warn "决策引擎已在运行"
        return 0
    }

    log_info "启动智能决策引擎..."

    # 后台运行决策循环
    decision_engine_loop "${DECISION_ENGINE[decision_interval]}" &
    DECISION_ENGINE_PID=$!

    DECISION_ENGINE_RUNNING=true
    log_info "智能决策引擎已启动 (PID: ${DECISION_ENGINE_PID})"

    return 0
}

# 停止决策引擎
stop_decision_engine() {
    [[ "${DECISION_ENGINE_RUNNING}" == "false" ]] && return 0

    log_info "停止智能决策引擎..."

    if [[ -n "${DECISION_ENGINE_PID}" ]] && kill -0 "${DECISION_ENGINE_PID}" 2>/dev/null; then
        kill "${DECISION_ENGINE_PID}" 2>/dev/null
        wait "${DECISION_ENGINE_PID}" 2>/dev/null
    fi

    DECISION_ENGINE_PID=""
    DECISION_ENGINE_RUNNING=false

    log_info "智能决策引擎已停止"
    return 0
}

# 检查决策引擎状态
is_decision_engine_running() {
    [[ "${DECISION_ENGINE_RUNNING}" == "true" ]] && return 0 || return 1
}

# 获取决策引擎状态
get_decision_engine_status() {
    cat <<EOF
{
    "running": ${DECISION_ENGINE_RUNNING},
    "pid": "${DECISION_ENGINE_PID}",
    "decision_count": ${DECISION_HISTORY[decision_count]},
    "last_decision_type": "${DECISION_HISTORY[last_decision_type]}",
    "last_decision_time": ${DECISION_HISTORY[last_decision_time]},
    "auto_tune": ${DECISION_ENGINE[auto_tune]},
    "feedback_enabled": ${DECISION_ENGINE[feedback_enabled]}
}
EOF
}

# ==============================================================================
# 决策引擎主循环
# ==============================================================================

# 决策引擎主循环
# @param interval: 决策间隔（秒）
decision_engine_loop() {
    local interval="${1:-5}"

    log_info "决策引擎主循环启动，间隔: ${interval}秒"

    while true; do
        # 检查是否应该停止
        [[ "${DECISION_ENGINE_RUNNING}" == "false" ]] && break

        # 采集当前状态
        local state_json
        state_json=$(analyze_current_state)

        # 生成决策
        local decision_json
        decision_json=$(generate_decision "${state_json}")

        # 执行决策
        execute_decision "${decision_json}"

        # 等待下一次循环
        sleep "${interval}"
    done

    log_debug "决策引擎主循环退出"
}

# ==============================================================================
# 初始化函数
# ==============================================================================

# 初始化决策引擎
init_decision_engine() {
    log_debug "初始化智能决策引擎..."

    # 创建必要的目录
    mkdir -p "${CONF_DIR}" "${LOG_DIR}"

    log_debug "智能决策引擎初始化完成"
    return 0
}

# 清理决策引擎
cleanup_decision_engine() {
    log_debug "清理智能决策引擎..."

    # 停止决策引擎
    stop_decision_engine

    # 清理数据
    clear_time_series_data

    log_debug "智能决策引擎清理完成"
    return 0
}
