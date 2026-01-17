#!/bin/bash
# ==============================================================================
# Z-Panel Pro V8.0 - 工作流引擎
# ==============================================================================
# @description    企业级工作流引擎，支持DAG编排、并行执行、条件分支
# @version       8.0.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 工作流引擎配置
# ==============================================================================
declare -gA WORKFLOW_CONFIG=(
    [max_concurrent_tasks]="10"
    [task_timeout]="1800"
    [retry_on_failure]="true"
    [max_retries]="3"
    [persistence_enabled]="true"
    [persistence_dir]="/opt/Z-Panel-Pro/data/workflows"
    [log_dir]="/opt/Z-Panel-Pro/logs/workflows"
)

# ==============================================================================
# 工作流状态
# ==============================================================================
declare -gA WORKFLOWS=()
declare -gA WORKFLOW_STATUS=()
declare -gA WORKFLOW_TASKS=()
declare -gA WORKFLOW_TASK_STATUS=()
declare -gA WORKFLOW_TASK_DEPENDENCIES=()
declare -gA WORKFLOW_TASK_RESULTS=()

# ==============================================================================
# 工作流引擎状态
# ==============================================================================
declare -g WORKFLOW_ENGINE_RUNNING=false
declare -g WORKFLOW_ENGINE_PID=""

# ==============================================================================
# 安全命令白名单
# ==============================================================================
declare -gA WORKFLOW_SAFE_COMMANDS=(
    ["optimize_memory"]="allowed"
    ["clear_cache"]="allowed"
    ["monitor_zram"]="allowed"
    ["get_zram_info"]="allowed"
    ["start_zram"]="allowed"
    ["stop_zram"]="allowed"
    ["get_decision_engine_status"]="allowed"
    ["start_decision_engine"]="allowed"
    ["stop_decision_engine"]="allowed"
    ["adaptive_tune"]="allowed"
    ["get_memory_info"]="allowed"
    ["get_swap_info"]="allowed"
    ["get_system_info"]="allowed"
    ["get_health_status"]="allowed"
    ["get_zram_usage"]="allowed"
    ["get_cache_status"]="allowed"
    ["get_system_metrics"]="allowed"
    ["get_config_json"]="allowed"
    ["reload_config"]="allowed"
)

# ==============================================================================
# 安全工具函数
# ==============================================================================
# 验证命令是否安全
is_safe_workflow_command() {
    local command="$1"
    local task_type="$2"

    case "${task_type}" in
        shell)
            # 检查是否为白名单中的命令
            local cmd_name="${command%% *}"
            if [[ -n "${WORKFLOW_SAFE_COMMANDS[${cmd_name}]+isset}" ]]; then
                return 0
            fi

            # 检查命令格式 - 只允许安全的命令模式
            # 允许: 函数调用、简单命令
            # 禁止: 管道、重定向、命令替换、后台执行

            # 检查危险字符
            if [[ "${command}" =~ [|&;<>$`\(\)] ]]; then
                return 1
            fi

            # 检查命令注入模式
            if [[ "${command}" =~ (rm\ |dd\ |mkfs\ |fdisk\ |format\ |chmod\ |chown\ |chgrp\ ) ]]; then
                return 1
            fi

            # 只允许字母、数字、下划线、空格、连字符和点
            if [[ ! "${command}" =~ ^[a-zA-Z0-9_ ./-]+$ ]]; then
                return 1
            fi

            return 0
            ;;
        script)
            # 验证脚本路径
            local script_path="${command}"

            # 检查路径遍历
            if [[ "${script_path}" =~ \.\. ]]; then
                return 1
            fi

            # 检查绝对路径
            if [[ "${script_path}" != /* ]]; then
                return 1
            fi

            # 只允许特定目录的脚本
            local allowed_dirs=(
                "/opt/Z-Panel-Pro/scripts"
                "/opt/Z-Panel-Pro/bin"
                "/opt/Z-Panel-Pro/lib"
            )

            local is_allowed=false
            for dir in "${allowed_dirs[@]}"; do
                if [[ "${script_path}" == "${dir}"/* ]]; then
                    is_allowed=true
                    break
                fi
            done

            if [[ "${is_allowed}" == "false" ]]; then
                return 1
            fi

            # 检查符号链接
            if [[ -L "${script_path}" ]]; then
                return 1
            fi

            # 检查文件权限
            if [[ -f "${script_path}" ]]; then
                local perms=$(stat -c "%a" "${script_path}" 2>/dev/null)
                if [[ "${perms}" != "755" ]] && [[ "${perms}" != "744" ]] && [[ "${perms}" != "644" ]]; then
                    return 1
                fi
            fi

            return 0
            ;;
        builtin)
            # 内置函数必须存在于白名单中
            if [[ -n "${WORKFLOW_SAFE_COMMANDS[${command}]+isset}" ]]; then
                return 0
            fi

            # 检查函数名称格式
            if [[ ! "${command}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
                return 1
            fi

            # 检查函数是否存在
            if ! declare -F "${command}" >/dev/null 2>&1; then
                return 1
            fi

            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ==============================================================================
# 工作流定义
# ==============================================================================
# 创建工作流
create_workflow() {
    local workflow_id="$1"
    local name="$2"
    local description="${3:-}"

    if [[ -z "${workflow_id}" ]] || [[ -z "${name}" ]]; then
        log_error "缺少必需参数: workflow_id, name"
        return 1
    fi

    # 检查工作流是否已存在
    if [[ -n "${WORKFLOWS[${workflow_id}]+isset}" ]]; then
        log_error "工作流已存在: ${workflow_id}"
        return 1
    fi

    # 存储工作流信息
    WORKFLOWS["${workflow_id}_name"]="${name}"
    WORKFLOWS["${workflow_id}_description"]="${description}"
    WORKFLOWS["${workflow_id}_created"]=$(date +%s)
    WORKFLOWS["${workflow_id}_status"]="created"
    WORKFLOWS["${workflow_id}_tasks"]=""

    WORKFLOW_STATUS["${workflow_id}"]="created"

    log_info "工作流已创建: ${workflow_id} (${name})"

    # 持久化
    if [[ "${WORKFLOW_CONFIG[persistence_enabled]}" == "true" ]]; then
        persist_workflow "${workflow_id}"
    fi

    return 0
}

# 添加任务到工作流（安全版本）
add_workflow_task() {
    local workflow_id="$1"
    local task_id="$2"
    local command="$3"
    local task_type="${4:-shell}"
    local description="${5:-}"

    if [[ -z "${workflow_id}" ]] || [[ -z "${task_id}" ]] || [[ -z "${command}" ]]; then
        log_error "缺少必需参数: workflow_id, task_id, command"
        return 1
    fi

    # 检查工作流是否存在
    if [[ -z "${WORKFLOWS[${workflow_id}_name]+isset}" ]]; then
        log_error "工作流不存在: ${workflow_id}"
        return 1
    fi

    # 验证命令安全性
    if ! is_safe_workflow_command "${command}" "${task_type}"; then
        log_error "拒绝添加不安全的任务命令: ${command} (类型: ${task_type})"
        return 1
    fi

    # 存储任务信息
    local task_key="${workflow_id}:${task_id}"

    WORKFLOW_TASKS["${task_key}_command"]="${command}"
    WORKFLOW_TASKS["${task_key}_type"]="${task_type}"
    WORKFLOW_TASKS["${task_key}_description"]="${description}"
    WORKFLOW_TASKS["${task_key}_timeout"]="${WORKFLOW_CONFIG[task_timeout]}"
    WORKFLOW_TASKS["${task_key}_retries"]="0"

    WORKFLOW_TASK_STATUS["${task_key}"]="pending"

    # 更新工作流任务列表
    local tasks="${WORKFLOWS[${workflow_id}_tasks]}"
    if [[ -z "${tasks}" ]]; then
        tasks="${task_id}"
    else
        tasks+=" ${task_id}"
    fi
    WORKFLOWS["${workflow_id}_tasks"]="${tasks}"

    log_info "任务已添加: ${workflow_id}:${task_id}"

    return 0
}

# 添加任务依赖
add_task_dependency() {
    local workflow_id="$1"
    local task_id="$2"
    local depends_on="$3"

    local task_key="${workflow_id}:${task_id}"
    local dep_key="${workflow_id}:${depends_on}"

    local dependencies="${WORKFLOW_TASK_DEPENDENCIES[${task_key}]:-}"

    if [[ -z "${dependencies}" ]]; then
        dependencies="${dep_key}"
    else
        dependencies+=" ${dep_key}"
    fi

    WORKFLOW_TASK_DEPENDENCIES["${task_key}"]="${dependencies}"

    log_debug "添加依赖: ${task_key} -> ${dep_key}"
}

# ==============================================================================
# 工作流执行
# ==============================================================================
# 启动工作流
start_workflow() {
    local workflow_id="$1"

    # 检查工作流是否存在
    if [[ -z "${WORKFLOWS[${workflow_id}_name]+isset}" ]]; then
        log_error "工作流不存在: ${workflow_id}"
        return 1
    fi

    # 更新状态
    WORKFLOWS["${workflow_id}_status"]="running"
    WORKFLOWS["${workflow_id}_started"]=$(date +%s)
    WORKFLOW_STATUS["${workflow_id}"]="running"

    log_info "启动工作流: ${workflow_id}"

    # 持久化
    if [[ "${WORKFLOW_CONFIG[persistence_enabled]}" == "true" ]]; then
        persist_workflow "${workflow_id}"
    fi

    # 执行工作流
    execute_workflow "${workflow_id}" &

    return 0
}

# 执行工作流
execute_workflow() {
    local workflow_id="$1"

    local tasks="${WORKFLOWS[${workflow_id}_tasks]}"
    local completed_tasks=0
    local failed_tasks=0
    local total_tasks=$(echo "${tasks}" | wc -w)

    # 任务执行队列
    local -a pending_tasks=(${tasks})

    # 执行循环
    while [[ ${#pending_tasks[@]} -gt 0 ]]; do
        local -a ready_tasks=()
        local -a remaining_tasks=()

        # 检查哪些任务可以执行
        for task_id in "${pending_tasks[@]}"; do
            local task_key="${workflow_id}:${task_id}"
            local task_status="${WORKFLOW_TASK_STATUS[${task_key}]}"

            # 跳过已完成或失败的任务
            if [[ "${task_status}" == "completed" ]] || [[ "${task_status}" == "failed" ]]; then
                continue
            fi

            # 检查依赖是否满足
            if check_task_dependencies "${task_key}"; then
                ready_tasks+=("${task_id}")
            else
                remaining_tasks+=("${task_id}")
            fi
        done

        # 执行就绪的任务
        if [[ ${#ready_tasks[@]} -gt 0 ]]; then
            local -a running_pids=()

            for task_id in "${ready_tasks[@]}"; do
                local task_key="${workflow_id}:${task_id}"

                # 检查并发限制
                local running_count=$(count_running_tasks "${workflow_id}")
                local max_concurrent="${WORKFLOW_CONFIG[max_concurrent_tasks]}"

                if [[ ${running_count} -ge ${max_concurrent} ]]; then
                    remaining_tasks+=("${task_id}")
                    continue
                fi

                # 执行任务
                execute_workflow_task "${workflow_id}" "${task_id}" &
                running_pids+=($!)
            done

            # 等待任务完成
            for pid in "${running_pids[@]}"; do
                wait ${pid} 2>/dev/null || true
            done
        fi

        # 更新待处理任务列表
        pending_tasks=("${remaining_tasks[@]}")

        # 检查工作流是否完成
        local all_done=true
        for task_id in ${tasks}; do
            local task_key="${workflow_id}:${task_id}"
            local task_status="${WORKFLOW_TASK_STATUS[${task_key}]}"

            if [[ "${task_status}" == "pending" ]] || [[ "${task_status}" == "running" ]]; then
                all_done=false
                break
            fi
        done

        if [[ "${all_done}" == "true" ]]; then
            break
        fi

        # 避免忙等待
        sleep 1
    done

    # 统计结果
    for task_id in ${tasks}; do
        local task_key="${workflow_id}:${task_id}"
        local task_status="${WORKFLOW_TASK_STATUS[${task_key}]}"

        if [[ "${task_status}" == "completed" ]]; then
            ((completed_tasks++))
        elif [[ "${task_status}" == "failed" ]]; then
            ((failed_tasks++))
        fi
    done

    # 更新工作流状态
    if [[ ${failed_tasks} -eq 0 ]]; then
        WORKFLOWS["${workflow_id}_status"]="completed"
        WORKFLOW_STATUS["${workflow_id}"]="completed"
        log_info "工作流完成: ${workflow_id}"
    else
        WORKFLOWS["${workflow_id}_status"]="failed"
        WORKFLOW_STATUS["${workflow_id}"]="failed"
        log_error "工作流失败: ${workflow_id} (${failed_tasks}/${total_tasks} 任务失败)"
    fi

    WORKFLOWS["${workflow_id}_completed"]=$(date +%s)
    WORKFLOWS["${workflow_id}_completed_tasks"]="${completed_tasks}"
    WORKFLOWS["${workflow_id}_failed_tasks"]="${failed_tasks}"

    # 持久化
    if [[ "${WORKFLOW_CONFIG[persistence_enabled]}" == "true" ]]; then
        persist_workflow "${workflow_id}"
    fi
}

# 检查任务依赖
check_task_dependencies() {
    local task_key="$1"

    local dependencies="${WORKFLOW_TASK_DEPENDENCIES[${task_key}]:-}"

    if [[ -z "${dependencies}" ]]; then
        return 0
    fi

    for dep_key in ${dependencies}; do
        local dep_status="${WORKFLOW_TASK_STATUS[${dep_key}]}"

        if [[ "${dep_status}" != "completed" ]]; then
            return 1
        fi
    done

    return 0
}

# 统计运行中的任务
count_running_tasks() {
    local workflow_id="$1"
    local count=0

    for task_key in "${!WORKFLOW_TASK_STATUS[@]}"; do
        if [[ "${task_key}" == "${workflow_id}:"* ]]; then
            if [[ "${WORKFLOW_TASK_STATUS[${task_key}]}" == "running" ]]; then
                ((count++))
            fi
        fi
    done

    echo ${count}
}

# 执行工作流任务（安全版本）
execute_workflow_task() {
    local workflow_id="$1"
    local task_id="$2"

    local task_key="${workflow_id}:${task_id}"
    local command="${WORKFLOW_TASKS[${task_key}_command]}"
    local task_type="${WORKFLOW_TASKS[${task_key}_type]}"
    local timeout="${WORKFLOW_TASKS[${task_key}_timeout]}"

    # 二次验证命令安全性（防止运行时篡改）
    if ! is_safe_workflow_command "${command}" "${task_type}"; then
        log_error "拒绝执行不安全的任务命令: ${command} (类型: ${task_type})"
        WORKFLOW_TASK_STATUS["${task_key}"]="failed"
        WORKFLOW_TASK_RESULTS["${task_key}_exit_code"]="1"
        WORKFLOW_TASK_RESULTS["${task_key}_duration"]="0"
        WORKFLOW_TASK_RESULTS["${task_key}_output"]="Command rejected by security policy"
        return 1
    fi

    # 更新任务状态
    WORKFLOW_TASK_STATUS["${task_key}"]="running"

    log_info "执行任务: ${task_key}"

    # 创建日志文件
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local log_file="${WORKFLOW_CONFIG[log_dir]}/${workflow_id}_${task_id}_${timestamp}.log"
    mkdir -p "${WORKFLOW_CONFIG[log_dir]}"

    # 执行任务
    local start_time=$(date +%s)
    local exit_code=0
    local output=""

    case "${task_type}" in
        shell)
            # Shell命令执行 - 使用安全的函数调用方式
            if [[ "${timeout}" -gt 0 ]]; then
                # 使用数组传递参数，避免shell注入
                local cmd_name="${command%% *}"
                local cmd_args="${command#* }"
                if [[ "${cmd_args}" == "${command}" ]]; then
                    cmd_args=""
                fi

                # 安全执行白名单中的命令
                if [[ -n "${WORKFLOW_SAFE_COMMANDS[${cmd_name}]+isset}" ]]; then
                    if [[ -n "${cmd_args}" ]]; then
                        output=$(timeout ${timeout} "${cmd_name}" ${cmd_args} 2>&1)
                    else
                        output=$(timeout ${timeout} "${cmd_name}" 2>&1)
                    fi
                    exit_code=$?
                else
                    # 对于其他安全命令，使用受限的bash环境
                    output=$(timeout ${timeout} bash --restricted -c "${command}" 2>&1)
                    exit_code=$?
                fi
            else
                local cmd_name="${command%% *}"
                local cmd_args="${command#* }"
                if [[ "${cmd_args}" == "${command}" ]]; then
                    cmd_args=""
                fi

                if [[ -n "${WORKFLOW_SAFE_COMMANDS[${cmd_name}]+isset}" ]]; then
                    if [[ -n "${cmd_args}" ]]; then
                        output=$("${cmd_name}" ${cmd_args} 2>&1)
                    else
                        output=$("${cmd_name}" 2>&1)
                    fi
                    exit_code=$?
                else
                    output=$(bash --restricted -c "${command}" 2>&1)
                    exit_code=$?
                fi
            fi
            ;;
        script)
            # 脚本文件执行 - 二次验证
            if [[ -f "${command}" ]] && ! is_safe_workflow_command "${command}" "script"; then
                output="Script validation failed: ${command}"
                exit_code=1
            elif [[ -f "${command}" ]]; then
                # 检查符号链接
                if [[ -L "${command}" ]]; then
                    output="Symbolic links not allowed: ${command}"
                    exit_code=1
                else
                    output=$(bash "${command}" 2>&1)
                    exit_code=$?
                fi
            else
                output="Script not found: ${command}"
                exit_code=1
            fi
            ;;
        builtin)
            # 内置函数执行 - 安全调用
            if declare -F "${command}" >/dev/null 2>&1; then
                output=$("${command}" 2>&1)
                exit_code=$?
            else
                output="Builtin function not found: ${command}"
                exit_code=1
            fi
            ;;
        *)
            log_error "未知任务类型: ${task_type}"
            output="Unknown task type: ${task_type}"
            exit_code=1
            ;;
    esac

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # 记录结果
    WORKFLOW_TASK_RESULTS["${task_key}_exit_code"]="${exit_code}"
    WORKFLOW_TASK_RESULTS["${task_key}_duration"]="${duration}"
    WORKFLOW_TASK_RESULTS["${task_key}_output"]="${output}"

    # 保存日志
    echo "${output}" > "${log_file}"

    # 更新任务状态
    if [[ ${exit_code} -eq 0 ]]; then
        WORKFLOW_TASK_STATUS["${task_key}"]="completed"
        log_info "任务完成: ${task_key} (耗时: ${duration}s)"
    else
        WORKFLOW_TASK_STATUS["${task_key}"]="failed"
        log_error "任务失败: ${task_key} (退出码: ${exit_code}, 耗时: ${duration}s)"

        # 重试逻辑
        if [[ "${WORKFLOW_CONFIG[retry_on_failure]}" == "true" ]]; then
            local retries="${WORKFLOW_TASKS[${task_key}_retries]}"
            local max_retries="${WORKFLOW_CONFIG[max_retries]}"

            if [[ ${retries} -lt ${max_retries} ]]; then
                ((retries++))
                WORKFLOW_TASKS[${task_key}_retries]="${retries}"

                log_info "重试任务: ${task_key} (${retries}/${max_retries})"

                # 延迟后重试
                sleep $((retries * 5))

                execute_workflow_task "${workflow_id}" "${task_id}"
                return $?
            fi
        fi
    fi

    return ${exit_code}
}

# ==============================================================================
# 工作流管理
# ==============================================================================
# 停止工作流
stop_workflow() {
    local workflow_id="$1"

    if [[ "${WORKFLOW_STATUS[${workflow_id}]}" != "running" ]]; then
        log_warning "工作流未运行: ${workflow_id}"
        return 1
    fi

    WORKFLOWS["${workflow_id}_status"]="stopped"
    WORKFLOW_STATUS["${workflow_id}"]="stopped"

    # 停止所有运行中的任务
    for task_key in "${!WORKFLOW_TASK_STATUS[@]}"; do
        if [[ "${task_key}" == "${workflow_id}:"* ]]; then
            if [[ "${WORKFLOW_TASK_STATUS[${task_key}]}" == "running" ]]; then
                # 发送SIGTERM
                # 注意：这里需要更复杂的实现来跟踪任务PID
                WORKFLOW_TASK_STATUS["${task_key}"]="stopped"
            fi
        fi
    done

    log_info "工作流已停止: ${workflow_id}"
    return 0
}

# 重启工作流
restart_workflow() {
    local workflow_id="$1"

    # 重置所有任务状态
    for task_key in "${!WORKFLOW_TASK_STATUS[@]}"; do
        if [[ "${task_key}" == "${workflow_id}:"* ]]; then
            WORKFLOW_TASK_STATUS["${task_key}"]="pending"
            WORKFLOW_TASKS["${task_key}_retries"]="0"
        fi
    done

    # 重启工作流
    start_workflow "${workflow_id}"
}

# 删除工作流
delete_workflow() {
    local workflow_id="$1"

    # 停止工作流（如果正在运行）
    if [[ "${WORKFLOW_STATUS[${workflow_id}]}" == "running" ]]; then
        stop_workflow "${workflow_id}"
    fi

    # 删除工作流数据
    for key in "${!WORKFLOWS[@]}"; do
        if [[ "${key}" == "${workflow_id}_"* ]]; then
            unset WORKFLOWS["${key}"]
        fi
    done

    # 删除任务数据
    for task_key in "${!WORKFLOW_TASKS[@]}"; do
        if [[ "${task_key}" == "${workflow_id}:"* ]]; then
            unset WORKFLOW_TASKS["${task_key}"]
            unset WORKFLOW_TASK_STATUS["${task_key}"]
            unset WORKFLOW_TASK_DEPENDENCIES["${task_key}"]
            unset WORKFLOW_TASK_RESULTS["${task_key}_exit_code"]
            unset WORKFLOW_TASK_RESULTS["${task_key}_duration"]
            unset WORKFLOW_TASK_RESULTS["${task_key}_output"]
        fi
    done

    # 删除状态
    unset WORKFLOW_STATUS["${workflow_id}"]

    # 删除持久化文件
    if [[ "${WORKFLOW_CONFIG[persistence_enabled]}" == "true" ]]; then
        rm -f "${WORKFLOW_CONFIG[persistence_dir]}/${workflow_id}.json"
    fi

    log_info "工作流已删除: ${workflow_id}"
    return 0
}

# ==============================================================================
# 查询函数
# ==============================================================================
# 获取工作流列表
get_workflow_list() {
    local output=""

    for key in "${!WORKFLOWS[@]}"; do
        if [[ "${key}" == *"_name" ]]; then
            local workflow_id="${key%_name}"
            local name="${WORKFLOWS[${key}]}"
            local status="${WORKFLOW_STATUS[${workflow_id}]:-unknown}"
            local created="${WORKFLOWS[${workflow_id}_created]:-0}"
            local created_date=$(date -d "@${created}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "${created}")

            output+="${workflow_id}|${name}|${status}|${created_date}"$'\n'
        fi
    done

    echo "${output}"
}

# 获取工作流状态
get_workflow_status() {
    local workflow_id="$1"

    local name="${WORKFLOWS[${workflow_id}_name]:-}"
    local status="${WORKFLOW_STATUS[${workflow_id}]:-unknown}"
    local created="${WORKFLOWS[${workflow_id}_created]:-0}"
    local started="${WORKFLOWS[${workflow_id}_started]:-0}"
    local completed="${WORKFLOWS[${workflow_id}_completed]:-0}"
    local completed_tasks="${WORKFLOWS[${workflow_id}_completed_tasks]:-0}"
    local failed_tasks="${WORKFLOWS[${workflow_id}_failed_tasks]:-0}"

    cat <<EOF
{
    "workflow_id": "${workflow_id}",
    "name": "${name}",
    "status": "${status}",
    "created": ${created},
    "started": ${started},
    "completed": ${completed},
    "completed_tasks": ${completed_tasks},
    "failed_tasks": ${failed_tasks}
}
EOF
}

# 获取工作流任务状态
get_workflow_tasks_status() {
    local workflow_id="$1"

    local tasks="${WORKFLOWS[${workflow_id}_tasks]:-}"
    local output=""

    for task_id in ${tasks}; do
        local task_key="${workflow_id}:${task_id}"
        local task_status="${WORKFLOW_TASK_STATUS[${task_key}]:-unknown}"
        local exit_code="${WORKFLOW_TASK_RESULTS[${task_key}_exit_code]:-}"
        local duration="${WORKFLOW_TASK_RESULTS[${task_key}_duration]:-}"

        output+="${task_id}|${task_status}|${exit_code}|${duration}"$'\n'
    done

    echo "${output}"
}

# ==============================================================================
# 持久化
# ==============================================================================
# 持久化工作流
persist_workflow() {
    local workflow_id="$1"

    local workflow_file="${WORKFLOW_CONFIG[persistence_dir]}/${workflow_id}.json"
    mkdir -p "${WORKFLOW_CONFIG[persistence_dir]}"

    local tasks="${WORKFLOWS[${workflow_id}_tasks]}"
    local tasks_json=""

    for task_id in ${tasks}; do
        local task_key="${workflow_id}:${task_id}"
        local command="${WORKFLOW_TASKS[${task_key}_command]}"
        local task_type="${WORKFLOW_TASKS[${task_key}_type]}"
        local task_status="${WORKFLOW_TASK_STATUS[${task_key}]}"
        local dependencies="${WORKFLOW_TASK_DEPENDENCIES[${task_key}]:-}"

        tasks_json+=$(cat <<TASK
        {
            "task_id": "${task_id}",
            "command": "${command}",
            "type": "${task_type}",
            "status": "${task_status}",
            "dependencies": "${dependencies}"
        },
TASK
)
    done

    # 移除最后的逗号
    tasks_json="${tasks_json%,}"

    cat > "${workflow_file}" <<EOF
{
    "workflow_id": "${workflow_id}",
    "name": "${WORKFLOWS[${workflow_id}_name]}",
    "description": "${WORKFLOWS[${workflow_id}_description]}",
    "status": "${WORKFLOW_STATUS[${workflow_id}]}",
    "created": ${WORKFLOWS[${workflow_id}_created]},
    "started": ${WORKFLOWS[${workflow_id}_started]:-0},
    "completed": ${WORKFLOWS[${workflow_id}_completed]:-0},
    "completed_tasks": ${WORKFLOWS[${workflow_id}_completed_tasks]:-0},
    "failed_tasks": ${WORKFLOWS[${workflow_id}_failed_tasks]:-0},
    "tasks": [
${tasks_json}
    ]
}
EOF
}

# 加载持久化的工作流
load_persisted_workflows() {
    local persistence_dir="${WORKFLOW_CONFIG[persistence_dir]}"

    if [[ ! -d "${persistence_dir}" ]]; then
        return 0
    fi

    for workflow_file in "${persistence_dir}"/*.json; do
        if [[ -f "${workflow_file}" ]]; then
            if command -v jq &> /dev/null; then
                local workflow_id=$(jq -r '.workflow_id' "${workflow_file}")
                local name=$(jq -r '.name' "${workflow_file}")
                local description=$(jq -r '.description' "${workflow_file}")
                local status=$(jq -r '.status' "${workflow_file}")
                local created=$(jq -r '.created' "${workflow_file}")

                # 恢复工作流
                WORKFLOWS["${workflow_id}_name"]="${name}"
                WORKFLOWS["${workflow_id}_description"]="${description}"
                WORKFLOWS["${workflow_id}_created"]="${created}"
                WORKFLOWS["${workflow_id}_status"]="${status}"
                WORKFLOW_STATUS["${workflow_id}"]="${status}"

                # 恢复任务
                local task_count=$(jq '.tasks | length' "${workflow_file}")
                for ((i=0; i<task_count; i++)); do
                    local task_id=$(jq -r ".tasks[${i}].task_id" "${workflow_file}")
                    local command=$(jq -r ".tasks[${i}].command" "${workflow_file}")
                    local task_type=$(jq -r ".tasks[${i}].type" "${workflow_file}")
                    local task_status=$(jq -r ".tasks[${i}].status" "${workflow_file}")
                    local dependencies=$(jq -r ".tasks[${i}].dependencies" "${workflow_file}")

                    local task_key="${workflow_id}:${task_id}"
                    WORKFLOW_TASKS["${task_key}_command"]="${command}"
                    WORKFLOW_TASKS["${task_key}_type"]="${task_type}"
                    WORKFLOW_TASK_STATUS["${task_key}"]="${task_status}"

                    # 恢复依赖
                    if [[ -n "${dependencies}" ]]; then
                        WORKFLOW_TASK_DEPENDENCIES["${task_key}"]="${dependencies}"
                    fi

                    # 更新任务列表
                    local tasks="${WORKFLOWS[${workflow_id}_tasks]}"
                    if [[ -z "${tasks}" ]]; then
                        tasks="${task_id}"
                    else
                        tasks+=" ${task_id}"
                    fi
                    WORKFLOWS[${workflow_id}_tasks}="${tasks}"
                done

                log_info "加载工作流: ${workflow_id}"
            fi
        fi
    done
}

# ==============================================================================
# 预定义工作流
# ==============================================================================
# 创建默认工作流
create_default_workflows() {
    # 系统优化工作流
    create_workflow "system_optimization" "系统优化" "定期系统性能优化"
    add_workflow_task "system_optimization" "memory_cleanup" "optimize_memory normal" "shell" "内存清理"
    add_workflow_task "system_optimization" "cache_cleanup" "clear_cache" "shell" "缓存清理"
    add_workflow_task "system_optimization" "zram_monitor" "monitor_zram" "shell" "ZRAM监控"

    # ZRAM管理工作流
    create_workflow "zram_management" "ZRAM管理" "ZRAM设备管理"
    add_workflow_task "zram_management" "check_zram" "get_zram_info" "shell" "检查ZRAM状态"
    add_workflow_task "zram_management" "start_zram" "start_zram" "shell" "启动ZRAM"
    add_task_dependency "zram_management" "start_zram" "check_zram"

    # 决策引擎管理工作流
    create_workflow "decision_management" "决策引擎管理" "决策引擎生命周期管理"
    add_workflow_task "decision_management" "check_status" "get_decision_engine_status" "shell" "检查状态"
    add_workflow_task "decision_management" "start_engine" "start_decision_engine" "shell" "启动引擎"
    add_task_dependency "decision_management" "start_engine" "check_status"
    add_workflow_task "decision_management" "tune_parameters" "adaptive_tune" "shell" "参数调优"
    add_task_dependency "decision_management" "tune_parameters" "start_engine"

    log_info "默认工作流已创建"
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f create_workflow
export -f add_workflow_task
export -f add_task_dependency
export -f start_workflow
export -f execute_workflow
export -f check_task_dependencies
export -f count_running_tasks
export -f execute_workflow_task
export -f stop_workflow
export -f restart_workflow
export -f delete_workflow
export -f get_workflow_list
export -f get_workflow_status
export -f get_workflow_tasks_status
export -f persist_workflow
export -f load_persisted_workflows
export -f create_default_workflows
