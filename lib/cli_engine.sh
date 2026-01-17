#!/bin/bash
# ==============================================================================
# Z-Panel Pro V8.0 - CLI引擎
# ==============================================================================
# @description    增强型命令行界面引擎，支持自动补全、历史记录、语法高亮
# @version       8.0.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# CLI配置
# ==============================================================================
declare -gA CLI_CONFIG=(
    [history_file]="/opt/Z-Panel-Pro/tmp/cli_history"
    [history_size]="1000"
    [enable_completion]="true"
    [enable_syntax_highlight]="true"
    [enable_suggestions]="true"
    [prompt_format]="zpanel> "
    [show_errors]="true"
    [debug_mode]="false"
)

# ==============================================================================
# CLI状态
# ==============================================================================
declare -g CLI_RUNNING=false
declare -g CLI_HISTORY=()
declare -g CLI_HISTORY_INDEX=0
declare -gA CLI_ALIASES=()
declare -gA CLI_COMMANDS=()

# ==============================================================================
# 命令定义
# ==============================================================================
# 注册命令
register_cli_command() {
    local name="$1"
    local description="$2"
    local handler="$3"
    local args="${4:-}"

    CLI_COMMANDS["${name}_handler"]="${handler}"
    CLI_COMMANDS["${name}_desc"]="${description}"
    CLI_COMMANDS["${name}_args"]="${args}"

    log_debug "注册CLI命令: ${name}"
}

# 列出所有命令
list_cli_commands() {
    for key in "${!CLI_COMMANDS[@]}"; do
        if [[ "${key}" == *"_handler" ]]; then
            local name="${key%_handler}"
            local desc="${CLI_COMMANDS[${name}_desc]}"
            echo "  ${name} - ${desc}"
        fi
    done
}

# 查找命令
find_cli_command() {
    local name="$1"

    if [[ -n "${CLI_COMMANDS[${name}_handler]+isset}" ]]; then
        echo "${CLI_COMMANDS[${name}_handler]}"
        return 0
    fi

    # 检查别名
    if [[ -n "${CLI_ALIASES[${name}]+isset}" ]]; then
        local real_name="${CLI_ALIASES[${name}]}"
        echo "${CLI_COMMANDS[${real_name}_handler]}"
        return 0
    fi

    return 1
}

# 注册别名
register_cli_alias() {
    local alias="$1"
    local command="$2"

    CLI_ALIASES["${alias}"]="${command}"
    log_debug "注册CLI别名: ${alias} -> ${command}"
}

# ==============================================================================
# 历史记录
# ==============================================================================
# 加载历史记录
load_history() {
    local history_file="${CLI_CONFIG[history_file]}"

    if [[ -f "${history_file}" ]]; then
        mapfile -t CLI_HISTORY < "${history_file}"
        CLI_HISTORY_INDEX=${#CLI_HISTORY[@]}
        log_debug "加载历史记录: ${CLI_HISTORY_INDEX} 条"
    fi
}

# 保存历史记录
save_history() {
    local history_file="${CLI_CONFIG[history_file]}"
    local history_dir=$(dirname "${history_file}")

    mkdir -p "${history_dir}"

    local history_size="${CLI_CONFIG[history_size]}"
    local start_index=$(( ${#CLI_HISTORY[@]} - history_size ))

    if [[ ${start_index} -lt 0 ]]; then
        start_index=0
    fi

    printf '%s\n' "${CLI_HISTORY[@]:${start_index}}" > "${history_file}"
}

# 添加历史记录
add_to_history() {
    local command="$1"

    # 避免重复
    if [[ "${CLI_HISTORY[-1]}" != "${command}" ]] && [[ -n "${command}" ]]; then
        CLI_HISTORY+=("${command}")
        CLI_HISTORY_INDEX=${#CLI_HISTORY[@]}

        # 限制历史记录大小
        local history_size="${CLI_CONFIG[history_size]}"
        if [[ ${#CLI_HISTORY[@]} -gt ${history_size} ]]; then
            CLI_HISTORY=("${CLI_HISTORY[@]:1}")
        fi
    fi
}

# 获取上一条命令
get_previous_history() {
    if [[ ${CLI_HISTORY_INDEX} -gt 0 ]]; then
        ((CLI_HISTORY_INDEX--))
        echo "${CLI_HISTORY[$CLI_HISTORY_INDEX]}"
    fi
}

# 获取下一条命令
get_next_history() {
    if [[ ${CLI_HISTORY_INDEX} -lt $((${#CLI_HISTORY[@]} - 1)) ]]; then
        ((CLI_HISTORY_INDEX++))
        echo "${CLI_HISTORY[$CLI_HISTORY_INDEX]}"
    elif [[ ${CLI_HISTORY_INDEX} -eq $((${#CLI_HISTORY[@]} - 1)) ]]; then
        # 返回空行（当前位置）
        echo ""
    fi
}

# ==============================================================================
# 自动补全
# ==============================================================================
# 获取补全建议
get_completion() {
    local input="$1"

    local suggestions=()

    # 补全命令
    if [[ "${input}" != *" "* ]]; then
        for cmd in "${!CLI_COMMANDS[@]}"; do
            if [[ "${cmd}" == *"_handler" ]]; then
                local name="${cmd%_handler}"
                if [[ "${name}" == "${input}"* ]]; then
                    suggestions+=("${name}")
                fi
            fi
        done

        # 补全别名
        for alias in "${!CLI_ALIASES[@]}"; do
            if [[ "${alias}" == "${input}"* ]]; then
                suggestions+=("${alias}")
            fi
        done
    else
        # 补全参数
        local cmd="${input%% *}"
        local current_arg="${input##* }"

        local handler=$(find_cli_command "${cmd}")

        if [[ -n "${handler}" ]]; then
            local args="${CLI_COMMANDS[${cmd}_args]}"

            case "${args}" in
                *"[device]"*)
                    # 补全设备名
                    for dev in /dev/sd[a-z]* /dev/nvme[0-9]*; do
                        if [[ -e "${dev}" ]]; then
                            if [[ "${dev##*/}" == "${current_arg}"* ]]; then
                                suggestions+=("${dev##*/}")
                            fi
                        fi
                    done
                    ;;
                *"[file]"*)
                    # 补全文件名
                    for file in ${current_arg}*; do
                        if [[ -e "${file}" ]]; then
                            suggestions+=("${file}")
                        fi
                    done
                    ;;
                *"[algorithm]"*)
                    # 补全压缩算法
                    for algo in lzo lz4 zstd; do
                        if [[ "${algo}" == "${current_arg}"* ]]; then
                            suggestions+=("${algo}")
                        fi
                    done
                    ;;
            esac
        fi
    fi

    # 输出建议
    if [[ ${#suggestions[@]} -gt 0 ]]; then
        printf '%s\n' "${suggestions[@]}"
    fi
}

# 显示补全建议
show_completion() {
    local input="$1"

    local suggestions=($(get_completion "${input}"))

    if [[ ${#suggestions[@]} -gt 0 ]]; then
        echo ""
        echo "建议:"
        for suggestion in "${suggestions[@]}"; do
            echo "  ${suggestion}"
        done
    fi
}

# ==============================================================================
# 语法高亮
# ==============================================================================
# 高亮命令
highlight_command() {
    local command="$1"

    local highlighted=""

    # 高亮命令名
    local cmd="${command%% *}"
    highlighted+="\033[1;36m${cmd}\033[0m"

    # 高亮选项
    if [[ "${command}" == *" "* ]]; then
        local rest="${command#* }"
        highlighted+=" "

        # 高亮短选项
        highlighted=$(echo "${highlighted}${rest}" | sed -E 's/ (-[a-z]+)/ \033[1;33m\1\033[0m/g')

        # 高亮长选项
        highlighted=$(echo "${highlighted}" | sed -E 's/ (--[a-z-]+)/ \033[1;33m\1\033[0m/g')

        # 高亮参数值
        highlighted=$(echo "${highlighted}" | sed -E 's/ (=)([^ ]+)/\1\033[1;32m\2\033[0m/g')
    fi

    echo -e "${highlighted}"
}

# ==============================================================================
# 命令执行
# ==============================================================================
# 安全的处理器名称白名单验证
is_safe_handler() {
    local handler="$1"

    # 检查是否为已注册的安全处理器
    for key in "${!CLI_COMMANDS[@]}"; do
        if [[ "${key}" == *"_handler" ]]; then
            if [[ "${CLI_COMMANDS[${key}]}" == "${handler}" ]]; then
                return 0
            fi
        fi
    done

    return 1
}

# 安全的参数清理
sanitize_args() {
    local args="$1"
    local cmd="$2"

    # 获取命令的参数模式
    local args_pattern="${CLI_COMMANDS[${cmd}_args]}"

    # 如果没有参数定义，返回空
    if [[ -z "${args_pattern}" ]]; then
        echo ""
        return 0
    fi

    # 过滤危险字符
    # 移除: ; & | ` $ ( ) < > " ' 换行符 制表符
    local sanitized=""
    local char
    local i=0
    while [[ $i -lt ${#args} ]]; do
        char="${args:$i:1}"
        case "${char}" in
            ';'|'&'|'|'|'`'|'$'|'('|')'|'<'|'>'|'"'|"'"|$'\n'|$'\t')
                # 跳过危险字符
                ;;
            '\\')
                # 转义字符 - 只保留下一个字符
                ((i++))
                if [[ $i -lt ${#args} ]]; then
                    sanitized+="${args:$i:1}"
                fi
                ;;
            *)
                sanitized+="${char}"
                ;;
        esac
        ((i++))
    done

    echo "${sanitized}"
}

# 执行命令（安全版本）
execute_cli_command() {
    local command="$1"

    # 解析命令
    local cmd="${command%% *}"
    local args="${command#* }"

    if [[ "${args}" == "${command}" ]]; then
        args=""
    fi

    # 查找处理器
    local handler=$(find_cli_command "${cmd}")

    if [[ -n "${handler}" ]]; then
        # 验证处理器是否安全
        if ! is_safe_handler "${handler}"; then
            echo -e "\033[1;31m错误: 未授权的处理器\033[0m"
            log_error "拒绝执行未授权的处理器: ${handler}"
            return 1
        fi

        # 清理参数
        local clean_args=$(sanitize_args "${args}" "${cmd}")

        # 检查命令是否允许参数
        local args_pattern="${CLI_COMMANDS[${cmd}_args]}"
        if [[ -z "${args_pattern}" ]] && [[ -n "${clean_args}" ]]; then
            echo -e "\033[1;31m错误: 命令不接受参数\033[0m"
            log_error "命令 ${cmd} 不接受参数"
            return 1
        fi

        # 执行命令（使用数组传递参数，避免注入）
        if [[ "${CLI_CONFIG[debug_mode]}" == "true" ]]; then
            log_debug "执行命令: ${cmd} ${clean_args}"
        fi

        # 安全执行：使用函数调用而不是eval或直接执行
        if [[ -n "${clean_args}" ]]; then
            # 使用数组安全传递参数
            local arg_array=(${clean_args})
            "${handler}" "${arg_array[@]}"
        else
            "${handler}"
        fi
        local exit_code=$?

        # 显示错误
        if [[ ${exit_code} -ne 0 ]] && [[ "${CLI_CONFIG[show_errors]}" == "true" ]]; then
            echo -e "\033[1;31m命令执行失败 (退出码: ${exit_code})\033[0m"
        fi

        return ${exit_code}
    else
        echo -e "\033[1;31m未知命令: ${cmd}\033[0m"
        echo "输入 'help' 查看可用命令"
        return 1
    fi
}

# ==============================================================================
# 交互式Shell
# ==============================================================================
# 启动CLI Shell
start_cli_shell() {
    log_info "启动CLI Shell..."

    # 加载历史记录
    load_history

    # 设置readline
    if [[ -n "${BASH_VERSION}" ]]; then
        # 启用vi模式
        set -o vi 2>/dev/null || true

        # 设置历史记录
        HISTFILE="${CLI_CONFIG[history_file]}"
        HISTSIZE="${CLI_CONFIG[history_size]}"
        HISTCONTROL="ignoreboth:erasedups"

        # 启用历史记录扩展
        set -o histexpand 2>/dev/null || true
    fi

    CLI_RUNNING=true

    # 主循环
    while [[ "${CLI_RUNNING}" == "true" ]]; do
        # 显示提示符
        local prompt=$(build_prompt)

        # 读取输入
        read -e -r -p "${prompt}" input

        # 检查退出命令
        case "${input}" in
            exit|quit|q)
                CLI_RUNNING=false
                continue
                ;;
        esac

        # 添加到历史记录
        add_to_history "${input}"

        # 执行命令
        if [[ -n "${input}" ]]; then
            execute_cli_command "${input}"
        fi
    done

    # 保存历史记录
    save_history

    log_info "CLI Shell已退出"
}

# 构建提示符
build_prompt() {
    local prompt="${CLI_CONFIG[prompt_format]}"

    # 添加状态指示器
    if is_decision_engine_running; then
        prompt="\033[1;32m●\033[0m ${prompt}"
    else
        prompt="\033[1;30m○\033[0m ${prompt}"
    fi

    echo -e "${prompt}"
}

# ==============================================================================
# 默认命令处理器
# ==============================================================================
# 注册默认命令
register_default_cli_commands() {
    # 系统命令
    register_cli_command "status" "显示系统状态" "cli_status"
    register_cli_command "info" "显示系统信息" "cli_info"
    register_cli_command "health" "健康检查" "cli_health"

    # 内存命令
    register_cli_command "mem" "显示内存使用" "cli_memory"
    register_cli_command "mem-optimize" "优化内存" "cli_mem_optimize"

    # ZRAM命令
    register_cli_command "zram" "显示ZRAM状态" "cli_zram"
    register_cli_command "zram-start" "启动ZRAM" "cli_zram_start"
    register_cli_command "zram-stop" "停止ZRAM" "cli_zram_stop"
    register_cli_command "zram-resize" "调整ZRAM大小" "cli_zram_resize" "[size]"

    # Swap命令
    register_cli_command "swap" "显示Swap状态" "cli_swap"
    register_cli_command "swap-on" "启用Swap" "cli_swap_on"
    register_cli_command "swap-off" "禁用Swap" "cli_swap_off"

    # 决策引擎命令
    register_cli_command "de" "显示决策引擎状态" "cli_decision_engine"
    register_cli_command "de-start" "启动决策引擎" "cli_de_start"
    register_cli_command "de-stop" "停止决策引擎" "cli_de_stop"
    register_cli_command "de-decisions" "显示决策历史" "cli_de_decisions" "[count]"

    # 配置命令
    register_cli_command "config" "显示配置" "cli_config"
    register_cli_command "config-set" "设置配置" "cli_config_set" "[key] [value]"
    register_cli_command "config-get" "获取配置" "cli_config_get" "[key]"
    register_cli_command "config-reload" "重新加载配置" "cli_config_reload"

    # 监控命令
    register_cli_command "monitor" "启动监控" "cli_monitor" "[interval]"
    register_cli_command "metrics" "显示指标" "cli_metrics"

    # 缓存命令
    register_cli_command "cache" "显示缓存状态" "cli_cache"
    register_cli_command "cache-clear" "清除缓存" "cli_cache_clear"

    # 帮助命令
    register_cli_command "help" "显示帮助" "cli_help" "[command]"
    register_cli_command "version" "显示版本" "cli_version"

    # 注册别名
    register_cli_alias "s" "status"
    register_cli_alias "i" "info"
    register_cli_alias "h" "help"
    register_cli_alias "v" "version"
    register_cli_alias "m" "mem"
}

# 命令处理器实现
cli_status() {
    echo "=== Z-Panel Pro 状态 ==="
    echo ""

    # 决策引擎状态
    if is_decision_engine_running; then
        echo "决策引擎: $(tui_color success)运行中$(tui_color reset)"
    else
        echo "决策引擎: $(tui_color muted)已停止$(tui_color reset)"
    fi

    # ZRAM状态
    if is_zram_enabled; then
        echo "ZRAM: $(tui_color success)已启用$(tui_color reset)"
    else
        echo "ZRAM: $(tui_color muted)未启用$(tui_color reset)"
    fi

    # Swap状态
    local swap_info=$(get_swap_info false)
    local swap_total swap_used swap_percent
    read -r swap_total swap_used swap_percent <<< "${swap_info}"

    if [[ ${swap_total} -gt 0 ]]; then
        echo "Swap: $(tui_color highlight)${swap_percent}%$(tui_color reset) 使用"
    else
        echo "Swap: $(tui_color muted)未使用$(tui_color reset)"
    fi

    # 内存状态
    local mem_info=$(get_memory_info true)
    local mem_total mem_used mem_avail mem_percent
    read -r mem_total mem_used mem_avail mem_percent <<< "${mem_info}"

    echo "内存: $(tui_color highlight)${mem_percent}%$(tui_color reset) 使用"

    echo ""
}

cli_info() {
    local info=$(get_system_info)
    echo "${info}" | jq '.' 2>/dev/null || echo "${info}"
}

cli_health() {
    local health=$(get_health_status)
    echo "${health}" | jq '.' 2>/dev/null || echo "${health}"
}

cli_memory() {
    local mem_info=$(get_memory_info true)
    local mem_total mem_used mem_avail mem_percent
    read -r mem_total mem_used mem_avail mem_percent <<< "${mem_info}"

    echo "内存使用: ${mem_percent}%"
    echo "  总计: ${mem_total} MB"
    echo "  已用: ${mem_used} MB"
    echo "  可用: ${mem_avail} MB"
}

cli_mem_optimize() {
    local level="${1:-normal}"

    echo "开始内存优化 (${level})..."
    optimize_memory "${level}"
    echo "优化完成"
}

cli_zram() {
    local zram_info=$(get_zram_info)
    echo "${zram_info}" | jq '.' 2>/dev/null || echo "${zram_info}"
}

cli_zram_start() {
    echo "启动ZRAM..."
    start_zram
    echo "ZRAM已启动"
}

cli_zram_stop() {
    echo "停止ZRAM..."
    stop_zram
    echo "ZRAM已停止"
}

cli_zram_resize() {
    local size="$1"

    if [[ -z "${size}" ]]; then
        echo "错误: 请指定大小 (MB)"
        return 1
    fi

    echo "调整ZRAM大小为 ${size} MB..."
    resize_zram "${size}"
    echo "ZRAM已调整"
}

cli_swap() {
    local swap_info=$(get_swap_info true)
    local swap_total swap_used swap_percent
    read -r swap_total swap_used swap_percent <<< "${swap_info}"

    echo "Swap使用: ${swap_percent}%"
    echo "  总计: ${swap_total} MB"
    echo "  已用: ${swap_used} MB"
}

cli_swap_on() {
    echo "启用Swap..."
    enable_swap
    echo "Swap已启用"
}

cli_swap_off() {
    echo "禁用Swap..."
    disable_swap
    echo "Swap已禁用"
}

cli_decision_engine() {
    local status=$(get_decision_engine_status)
    echo "${status}" | jq '.' 2>/dev/null || echo "${status}"
}

cli_de_start() {
    echo "启动决策引擎..."
    start_decision_engine
    echo "决策引擎已启动"
}

cli_de_stop() {
    echo "停止决策引擎..."
    stop_decision_engine
    echo "决策引擎已停止"
}

cli_de_decisions() {
    local count="${1:-10}"
    local decisions=$(get_recent_decisions "${count}")
    echo "${decisions}" | jq '.' 2>/dev/null || echo "${decisions}"
}

cli_config() {
    local config=$(get_config_json)
    echo "${config}" | jq '.' 2>/dev/null || echo "${config}"
}

cli_config_set() {
    local key="$1"
    local value="$2"

    if [[ -z "${key}" ]] || [[ -z "${value}" ]]; then
        echo "错误: 请指定键和值"
        return 1
    fi

    set_config "${key}" "${value}"
    echo "配置已更新: ${key} = ${value}"
}

cli_config_get() {
    local key="$1"

    if [[ -z "${key}" ]]; then
        echo "错误: 请指定键"
        return 1
    fi

    local value=$(get_config "${key}")
    echo "${key} = ${value}"
}

cli_config_reload() {
    echo "重新加载配置..."
    reload_config
    echo "配置已重新加载"
}

cli_monitor() {
    local interval="${1:-5}"

    echo "启动监控 (间隔: ${interval}s)"
    echo "按 Ctrl+C 退出"
    echo ""

    while true; do
        clear
        date
        echo ""

        # 显示状态
        cli_status
        echo ""

        # 显示内存
        cli_memory
        echo ""

        # 显示ZRAM
        local zram_info=$(get_zram_usage)
        local zram_total zram_used zram_percent
        read -r zram_total zram_used zram_percent <<< "${zram_info}"
        echo "ZRAM: ${zram_percent}% 使用"

        sleep ${interval}
    done
}

cli_metrics() {
    local metrics=$(get_system_metrics)
    echo "${metrics}" | jq '.' 2>/dev/null || echo "${metrics}"
}

cli_cache() {
    local cache_status=$(get_cache_status)
    echo "${cache_status}" | jq '.' 2>/dev/null || echo "${cache_status}"
}

cli_cache_clear() {
    echo "清除缓存..."
    clear_cache
    echo "缓存已清除"
}

cli_help() {
    local command="$1"

    if [[ -n "${command}" ]]; then
        # 显示特定命令的帮助
        local handler=$(find_cli_command "${command}")

        if [[ -n "${handler}" ]]; then
            echo "命令: ${command}"
            echo "描述: ${CLI_COMMANDS[${command}_desc]}"

            local args="${CLI_COMMANDS[${command}_args]}"
            if [[ -n "${args}" ]]; then
                echo "参数: ${args}"
            fi
        else
            echo "未知命令: ${command}"
        fi
    else
        # 显示所有命令
        echo "=== Z-Panel Pro CLI 命令 ==="
        echo ""

        echo "系统命令:"
        echo "  status, s          显示系统状态"
        echo "  info, i            显示系统信息"
        echo "  health             健康检查"
        echo ""

        echo "内存命令:"
        echo "  mem, m             显示内存使用"
        echo "  mem-optimize       优化内存"
        echo ""

        echo "ZRAM命令:"
        echo "  zram               显示ZRAM状态"
        echo "  zram-start         启动ZRAM"
        echo "  zram-stop          停止ZRAM"
        echo "  zram-resize        调整ZRAM大小"
        echo ""

        echo "Swap命令:"
        echo "  swap               显示Swap状态"
        echo "  swap-on            启用Swap"
        echo "  swap-off           灰用Swap"
        echo ""

        echo "决策引擎命令:"
        echo "  de                 显示决策引擎状态"
        echo "  de-start           启动决策引擎"
        echo "  de-stop            停止决策引擎"
        echo "  de-decisions       显示决策历史"
        echo ""

        echo "配置命令:"
        echo "  config             显示配置"
        echo "  config-set         设置配置"
        echo "  config-get         获取配置"
        echo "  config-reload      重新加载配置"
        echo ""

        echo "监控命令:"
        echo "  monitor            启动监控"
        echo "  metrics            显示指标"
        echo ""

        echo "缓存命令:"
        echo "  cache              显示缓存状态"
        echo "  cache-clear        清除缓存"
        echo ""

        echo "其他命令:"
        echo "  help, h            显示帮助"
        echo "  version, v         显示版本"
        echo "  exit, quit, q      退出"
    fi
}

cli_version() {
    echo "Z-Panel Pro V8.0.0-Enterprise"
    echo "Copyright (c) 2024 Z-Panel Team"
}

# ==============================================================================
# 初始化
# ==============================================================================
# 初始化CLI引擎
init_cli_engine() {
    log_debug "初始化CLI引擎..."

    # 创建历史记录目录
    local history_dir=$(dirname "${CLI_CONFIG[history_file]}")
    mkdir -p "${history_dir}"

    # 注册默认命令
    register_default_cli_commands

    log_debug "CLI引擎初始化完成"
    return 0
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f register_cli_command
export -f list_cli_commands
export -f find_cli_command
export -f register_cli_alias
export -f load_history
export -f save_history
export -f add_to_history
export -f get_previous_history
export -f get_next_history
export -f get_completion
export -f show_completion
export -f highlight_command
export -f execute_cli_command
export -f start_cli_shell
export -f build_prompt
export -f init_cli_engine
