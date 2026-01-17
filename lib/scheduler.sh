#!/bin/bash
# ==============================================================================
# Z-Panel Pro V8.0 - 任务调度器
# ==============================================================================
# @description    企业级任务调度器，支持Cron表达式、依赖管理、失败重试
# @version       8.0.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 调度器配置
# ==============================================================================
declare -gA SCHEDULER_CONFIG=(
    [max_concurrent_jobs]="5"
    [job_timeout]="3600"
    [max_retries]="3"
    [retry_delay]="60"
    [check_interval]="10"
    [persistence_enabled]="true"
    [persistence_dir]="/opt/Z-Panel-Pro/data/scheduler"
    [log_dir]="/opt/Z-Panel-Pro/logs/scheduler"
)

# ==============================================================================
# 任务状态
# ==============================================================================
declare -gA SCHEDULER_JOBS=()
declare -gA SCHEDULER_JOB_STATUS=()
declare -gA SCHEDULER_JOB_DEPENDENCIES=()
declare -gA SCHEDULER_JOB_METADATA=()
declare -gA SCHEDULER_JOB_LOCKS=()

# ==============================================================================
# 调度器状态
# ==============================================================================
declare -g SCHEDULER_RUNNING=false
declare -g SCHEDULER_PID=""

# ==============================================================================
# Cron解析器
# ==============================================================================
# 解析Cron表达式
parse_cron_expression() {
    local cron_expr="$1"
    local timestamp="${2:-$(date +%s)}"

    IFS=' ' read -r minute hour day month weekday <<< "${cron_expr}"

    # 计算下一次执行时间
    local next_time=$(calculate_next_execution "${minute}" "${hour}" "${day}" "${month}" "${weekday}" "${timestamp}")

    echo "${next_time}"
}

# 计算下一次执行时间
calculate_next_execution() {
    local minute="$1"
    local hour="$2"
    local day="$3"
    local month="$4"
    local weekday="$5"
    local current_time="$6"

    local current_date=$(date -d "@${current_time}" "+%Y %m %d %H %M %w")
    read -r cur_year cur_month cur_day cur_hour cur_min cur_weekday <<< "${current_date}"

    # 从当前时间开始查找
    local year=${cur_year}
    local month=${cur_month}
    local day=${cur_day}
    local hour=${cur_hour}
    local min=${cur_min}

    # 递增时间直到匹配
    while true; do
        # 检查分钟
        if [[ "${minute}" == "*" ]] || [[ "${minute}" == *"${min}"* ]]; then
            # 检查小时
            if [[ "${hour}" == "*" ]] || [[ "${hour}" == *"${hour}"* ]]; then
                # 检查日期
                if [[ "${day}" == "*" ]] || [[ "${day}" == *"${day}"* ]]; then
                    # 检查月份
                    if [[ "${month}" == "*" ]] || [[ "${month}" == *"${month}"* ]]; then
                        # 检查星期
                        if [[ "${weekday}" == "*" ]] || [[ "${weekday}" == *"${cur_weekday}"* ]]; then
                            # 找到匹配
                            local next_time=$(date -d "${year}-${month}-${day} ${hour}:${min}:00" +%s 2>/dev/null)

                            if [[ -n "${next_time}" ]] && [[ ${next_time} -gt ${current_time} ]]; then
                                echo "${next_time}"
                                return 0
                            fi
                        fi
                    fi
                fi
            fi
        fi

        # 增加分钟
        ((min++))
        if [[ ${min} -ge 60 ]]; then
            min=0
            ((hour++))
            if [[ ${hour} -ge 24 ]]; then
                hour=0
                ((day++))

                # 检查月份天数
                local days_in_month=$(days_in_month "${month}" "${year}")
                if [[ ${day} -gt ${days_in_month} ]]; then
                    day=1
                    ((month++))
                    if [[ ${month} -gt 12 ]]; then
                        month=1
                        ((year++))
                    fi
                fi
            fi
        fi

        # 更新星期
        cur_weekday=$(( (cur_weekday + 1) % 7 ))
    done
}

# 获取月份天数
days_in_month() {
    local month="$1"
    local year="$2"

    case ${month} in
        1|3|5|7|8|10|12) echo 31 ;;
        4|6|9|11) echo 30 ;;
        2)
            if [[ $((year % 4)) -eq 0 ]] && [[ $((year % 100)) -ne 0 ]] || [[ $((year % 400)) -eq 0 ]]; then
                echo 29
            else
                echo 28
            fi
            ;;
        *) echo 30 ;;
    esac
}

# ==============================================================================
# 任务管理
# ==============================================================================
# 添加任务
schedule_job() {
    local job_id="$1"
    local cron_expr="$2"
    local command="$3"
    local description="${4:-}"

    if [[ -z "${job_id}" ]] || [[ -z "${cron_expr}" ]] || [[ -z "${command}" ]]; then
        log_error "缺少必需参数: job_id, cron_expr, command"
        return 1
    fi

    # 计算下一次执行时间
    local next_run=$(parse_cron_expression "${cron_expr}")

    # 存储任务信息
    SCHEDULER_JOBS["${job_id}_cron"]="${cron_expr}"
    SCHEDULER_JOBS["${job_id}_command"]="${command}"
    SCHEDULER_JOBS["${job_id}_description"]="${description}"
    SCHEDULER_JOBS["${job_id}_next_run"]="${next_run}"
    SCHEDULER_JOBS["${job_id}_last_run"]="0"
    SCHEDULER_JOBS["${job_id}_run_count"]="0"
    SCHEDULER_JOBS["${job_id}_fail_count"]="0"
    SCHEDULER_JOBS["${job_id}_enabled"]="true"

    # 初始化状态
    SCHEDULER_JOB_STATUS["${job_id}"]="pending"

    log_info "任务已调度: ${job_id} (${cron_expr})"

    # 持久化
    if [[ "${SCHEDULER_CONFIG[persistence_enabled]}" == "true" ]]; then
        persist_job "${job_id}"
    fi

    return 0
}

# 移除任务
unschedule_job() {
    local job_id="$1"

    # 删除任务数据
    for key in "${!SCHEDULER_JOBS[@]}"; do
        if [[ "${key}" == "${job_id}_"* ]]; then
            unset SCHEDULER_JOBS["${key}"]
        fi
    done

    # 删除状态
    unset SCHEDULER_JOB_STATUS["${job_id}"]

    # 删除依赖
    for key in "${!SCHEDULER_JOB_DEPENDENCIES[@]}"; do
        if [[ "${key}" == "${job_id}_"* ]] || [[ "${key}" == *"_${job_id}" ]]; then
            unset SCHEDULER_JOB_DEPENDENCIES["${key}"]
        fi
    done

    # 删除持久化文件
    if [[ "${SCHEDULER_CONFIG[persistence_enabled]}" == "true" ]]; then
        rm -f "${SCHEDULER_CONFIG[persistence_dir]}/${job_id}.json"
    fi

    log_info "任务已移除: ${job_id}"
    return 0
}

# 启用任务
enable_job() {
    local job_id="$1"
    SCHEDULER_JOBS["${job_id}_enabled"]="true"
    log_info "任务已启用: ${job_id}"
}

# 禁用任务
disable_job() {
    local job_id="$1"
    SCHEDULER_JOBS["${job_id}_enabled"]="false"
    log_info "任务已禁用: ${job_id}"
}

# ==============================================================================
# 任务依赖
# ==============================================================================
# 添加依赖
add_job_dependency() {
    local job_id="$1"
    local depends_on="$2"

    local dependencies="${SCHEDULER_JOB_DEPENDENCIES[${job_id}]:-}"

    if [[ -z "${dependencies}" ]]; then
        dependencies="${depends_on}"
    else
        dependencies+=" ${depends_on}"
    fi

    SCHEDULER_JOB_DEPENDENCIES["${job_id}"]="${dependencies}"

    log_debug "添加依赖: ${job_id} -> ${depends_on}"
}

# 检查依赖是否满足
check_dependencies() {
    local job_id="$1"

    local dependencies="${SCHEDULER_JOB_DEPENDENCIES[${job_id}]:-}"

    if [[ -z "${dependencies}" ]]; then
        return 0
    fi

    for dep in ${dependencies}; do
        local dep_status="${SCHEDULER_JOB_STATUS[${dep}]}"

        if [[ "${dep_status}" != "completed" ]] && [[ "${dep_status}" != "skipped" ]]; then
            log_debug "依赖未满足: ${job_id} 依赖 ${dep} (状态: ${dep_status})"
            return 1
        fi
    done

    return 0
}

# ==============================================================================
# 任务执行
# ==============================================================================
# 执行任务
execute_job() {
    local job_id="$1"

    log_info "执行任务: ${job_id}"

    # 检查依赖
    if ! check_dependencies "${job_id}"; then
        log_warning "任务依赖未满足: ${job_id}"
        SCHEDULER_JOB_STATUS["${job_id}"]="waiting"
        return 1
    fi

    # 获取任务命令
    local command="${SCHEDULER_JOBS[${job_id}_command]}"

    # 更新状态
    SCHEDULER_JOB_STATUS["${job_id}"]="running"
    SCHEDULER_JOBS["${job_id}_last_run"]=$(date +%s)

    # 创建日志文件
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local log_file="${SCHEDULER_CONFIG[log_dir]}/${job_id}_${timestamp}.log"
    mkdir -p "${SCHEDULER_CONFIG[log_dir]}"

    # 执行命令
    local start_time=$(date +%s)
    local exit_code=0

    if [[ "${SCHEDULER_CONFIG[persistence_enabled]}" == "true" ]]; then
        # 持久化执行状态
        update_job_status "${job_id}" "running"
    fi

    # 执行并记录日志
        ${command} > "${log_file}" 2>&1
        exit_code=$?
    )

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # 更新任务统计
    ((SCHEDULER_JOBS["${job_id}_run_count"]++))

    if [[ ${exit_code} -eq 0 ]]; then
        SCHEDULER_JOB_STATUS["${job_id}"]="completed"
        log_info "任务完成: ${job_id} (耗时: ${duration}s)"
    else
        SCHEDULER_JOB_STATUS["${job_id}"]="failed"
        ((SCHEDULER_JOBS["${job_id}_fail_count"]++))
        log_error "任务失败: ${job_id} (退出码: ${exit_code}, 耗时: ${duration}s)"

        # 重试逻辑
        local retry_count="${SCHEDULER_JOBS[${job_id}_retry_count]:-0}"
        local max_retries="${SCHEDULER_CONFIG[max_retries]}"

        if [[ ${retry_count} -lt ${max_retries} ]]; then
            ((retry_count++))
            SCHEDULER_JOBS["${job_id}_retry_count"]="${retry_count}"

            local retry_delay="${SCHEDULER_CONFIG[retry_delay]}"
            local retry_time=$(($(date +%s) + retry_delay))

            SCHEDULER_JOBS["${job_id}_next_run"]="${retry_time}"
            SCHEDULER_JOB_STATUS["${job_id}"]="retrying"

            log_info "任务将在 ${retry_delay}s 后重试: ${job_id} (${retry_count}/${max_retries})"
        fi
    fi

    # 计算下一次执行
    local cron_expr="${SCHEDULER_JOBS[${job_id}_cron]}"
    local next_run=$(parse_cron_expression "${cron_expr}" $(date +%s))
    SCHEDULER_JOBS["${job_id}_next_run"]="${next_run}"

    # 持久化
    if [[ "${SCHEDULER_CONFIG[persistence_enabled]}" == "true" ]]; then
        update_job_status "${job_id}" "${SCHEDULER_JOB_STATUS[${job_id}]}"
        persist_job "${job_id}"
    fi

    return ${exit_code}
}

# ==============================================================================
# 调度循环
# ==============================================================================
# 启动调度器
start_scheduler() {
    log_info "启动任务调度器..."

    # 创建目录
    mkdir -p "${SCHEDULER_CONFIG[persistence_dir]}"
    mkdir -p "${SCHEDULER_CONFIG[log_dir]}"

    # 加载持久化的任务
    if [[ "${SCHEDULER_CONFIG[persistence_enabled]}" == "true" ]]; then
        load_persisted_jobs
    fi

    SCHEDULER_RUNNING=true

    # 启动调度循环
    scheduler_loop &
    SCHEDULER_PID=$!

    log_info "任务调度器已启动 (PID: ${SCHEDULER_PID})"
    return 0
}

# 停止调度器
stop_scheduler() {
    log_info "停止任务调度器..."

    if [[ -n "${SCHEDULER_PID}" ]] && kill -0 ${SCHEDULER_PID} 2>/dev/null; then
        kill ${SCHEDULER_PID}
        wait ${SCHEDULER_PID} 2>/dev/null
    fi

    SCHEDULER_RUNNING=false
    SCHEDULER_PID=""

    log_info "任务调度器已停止"
    return 0
}

# 调度循环
scheduler_loop() {
    local check_interval="${SCHEDULER_CONFIG[check_interval]}"
    local max_concurrent="${SCHEDULER_CONFIG[max_concurrent_jobs]}"

    while [[ "${SCHEDULER_RUNNING}" == "true" ]]; do
        local current_time=$(date +%s)
        local running_count=0

        # 统计运行中的任务
        for job_id in "${!SCHEDULER_JOB_STATUS[@]}"; do
            if [[ "${SCHEDULER_JOB_STATUS[${job_id}]}" == "running" ]]; then
                ((running_count++))
            fi
        done

        # 检查待执行的任务
        for job_id in "${!SCHEDULER_JOBS[@]}"; do
            if [[ "${job_id}" == *"_enabled" ]]; then
                local id="${job_id%_enabled}"

                # 跳过已禁用的任务
                if [[ "${SCHEDULER_JOBS[${job_id}]}" != "true" ]]; then
                    continue
                fi

                # 检查是否到达执行时间
                local next_run="${SCHEDULER_JOBS[${id}_next_run]}"

                if [[ ${next_run} -le ${current_time} ]]; then
                    # 检查是否已达到最大并发数
                    if [[ ${running_count} -ge ${max_concurrent} ]]; then
                        log_debug "已达到最大并发数，跳过: ${id}"
                        continue
                    fi

                    # 检查任务状态
                    local status="${SCHEDULER_JOB_STATUS[${id}]}"

                    if [[ "${status}" != "running" ]] && [[ "${status}" != "waiting" ]]; then
                        # 执行任务
                        execute_job "${id}" &
                        ((running_count++))
                    fi
                fi
            fi
        done

        sleep ${check_interval}
    done
}

# ==============================================================================
# 持久化
# ==============================================================================
# 持久化任务
persist_job() {
    local job_id="$1"

    local job_file="${SCHEDULER_CONFIG[persistence_dir]}/${job_id}.json"

    cat > "${job_file}" <<EOF
{
    "job_id": "${job_id}",
    "cron": "${SCHEDULER_JOBS[${job_id}_cron]}",
    "command": "${SCHEDULER_JOBS[${job_id}_command]}",
    "description": "${SCHEDULER_JOBS[${job_id}_description]}",
    "next_run": "${SCHEDULER_JOBS[${job_id}_next_run]}",
    "last_run": "${SCHEDULER_JOBS[${job_id}_last_run]}",
    "run_count": "${SCHEDULER_JOBS[${job_id}_run_count]}",
    "fail_count": "${SCHEDULER_JOBS[${job_id}_fail_count]}",
    "enabled": "${SCHEDULER_JOBS[${job_id}_enabled]}",
    "status": "${SCHEDULER_JOB_STATUS[${job_id}]}"
}
EOF
}

# 更新任务状态
update_job_status() {
    local job_id="$1"
    local status="$2"

    local status_file="${SCHEDULER_CONFIG[persistence_dir]}/${job_id}.status"
    echo "${status}" > "${status_file}"
}

# 加载持久化的任务
load_persisted_jobs() {
    local persistence_dir="${SCHEDULER_CONFIG[persistence_dir]}"

    if [[ ! -d "${persistence_dir}" ]]; then
        return 0
    fi

    for job_file in "${persistence_dir}"/*.json; do
        if [[ -f "${job_file}" ]]; then
            local job_id=$(basename "${job_file}" .json)

            # 读取任务配置
            if command -v jq &> /dev/null; then
                local cron=$(jq -r '.cron' "${job_file}")
                local command=$(jq -r '.command' "${job_file}")
                local description=$(jq -r '.description' "${job_file}")
                local next_run=$(jq -r '.next_run' "${job_file}")
                local last_run=$(jq -r '.last_run' "${job_file}")
                local run_count=$(jq -r '.run_count' "${job_file}")
                local fail_count=$(jq -r '.fail_count' "${job_file}")
                local enabled=$(jq -r '.enabled' "${job_file}")
                local status=$(jq -r '.status' "${job_file}")

                # 恢复任务
                SCHEDULER_JOBS["${job_id}_cron"]="${cron}"
                SCHEDULER_JOBS["${job_id}_command"]="${command}"
                SCHEDULER_JOBS["${job_id}_description"]="${description}"
                SCHEDULER_JOBS["${job_id}_next_run"]="${next_run}"
                SCHEDULER_JOBS["${job_id}_last_run"]="${last_run}"
                SCHEDULER_JOBS["${job_id}_run_count"]="${run_count}"
                SCHEDULER_JOBS["${job_id}_fail_count"]="${fail_count}"
                SCHEDULER_JOBS["${job_id}_enabled"]="${enabled}"
                SCHEDULER_JOB_STATUS["${job_id}"]="${status}"

                log_info "加载任务: ${job_id}"
            fi
        fi
    done
}

# ==============================================================================
# 查询函数
# ==============================================================================
# 获取任务列表
get_job_list() {
    local output=""

    for job_id in "${!SCHEDULER_JOBS[@]}"; do
        if [[ "${job_id}" == *"_cron" ]]; then
            local id="${job_id%_cron}"
            local cron="${SCHEDULER_JOBS[${job_id}]}"
            local enabled="${SCHEDULER_JOBS[${id}_enabled]}"
            local status="${SCHEDULER_JOB_STATUS[${id}]}"
            local next_run="${SCHEDULER_JOBS[${id}_next_run]}"
            local run_count="${SCHEDULER_JOBS[${id}_run_count]}"
            local fail_count="${SCHEDULER_JOBS[${id}_fail_count]}"

            local next_run_date=$(date -d "@${next_run}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "${next_run}")

            output+="${id}|${cron}|${enabled}|${status}|${next_run_date}|${run_count}|${fail_count}"$'\n'
        fi
    done

    echo "${output}"
}

# 获取任务状态
get_job_status() {
    local job_id="$1"

    local status="${SCHEDULER_JOB_STATUS[${job_id}]:-unknown}"
    local enabled="${SCHEDULER_JOBS[${job_id}_enabled]:-false}"
    local next_run="${SCHEDULER_JOBS[${job_id}_next_run]:-0}"
    local last_run="${SCHEDULER_JOBS[${job_id}_last_run]:-0}"
    local run_count="${SCHEDULER_JOBS[${job_id}_run_count]:-0}"
    local fail_count="${SCHEDULER_JOBS[${job_id}_fail_count]:-0}"

    cat <<EOF
{
    "job_id": "${job_id}",
    "status": "${status}",
    "enabled": ${enabled},
    "next_run": ${next_run},
    "last_run": ${last_run},
    "run_count": ${run_count},
    "fail_count": ${fail_count}
}
EOF
}

# ==============================================================================
# 预定义任务
# ==============================================================================
# 注册默认任务
register_default_jobs() {
    # 内存优化任务（每小时）
    schedule_job "memory_optimize" "0 * * * *" "optimize_memory normal" "定期内存优化"

    # ZRAM监控任务（每5分钟）
    schedule_job "zram_monitor" "*/5 * * * *" "monitor_zram" "ZRAM监控"

    # 决策引擎清理任务（每天）
    schedule_job "decision_cleanup" "0 0 * * *" "cleanup_decision_history" "决策历史清理"

    # 缓存清理任务（每30分钟）
    schedule_job "cache_cleanup" "*/30 * * * *" "clear_cache" "缓存清理"

    # 系统健康检查（每10分钟）
    schedule_job "health_check" "*/10 * * * *" "check_system_health" "系统健康检查"

    log_info "默认任务已注册"
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f parse_cron_expression
export -f calculate_next_execution
export -f days_in_month
export -f schedule_job
export -f unschedule_job
export -f enable_job
export -f disable_job
export -f add_job_dependency
export -f check_dependencies
export -f execute_job
export -f start_scheduler
export -f stop_scheduler
export -f scheduler_loop
export -f persist_job
export -f update_job_status
export -f load_persisted_jobs
export -f get_job_list
export -f get_job_status
export -f register_default_jobs
