#!/bin/bash
# ==============================================================================
# Z-Panel Pro V8.0 - TUI引擎
# ==============================================================================
# @description    高级终端用户界面引擎，支持实时监控和交互
# @version       8.0.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# TUI配置
# ==============================================================================
declare -gA TUI_CONFIG=(
    [theme]="dark"              # dark/light/cyberpunk
    [refresh_rate]="500"        # 刷新率(ms)
    [show_graph]="true"         # 显示图形
    [show_trends]="true"       # 显示趋势
    [color_mode]="auto"        # auto/256color/truecolor
)

# ==============================================================================
# 颜色方案
# ==============================================================================
declare -gA TUI_COLORS=(
    # Dark Theme
    [dark_bg]="40"              [dark_fg]="37"
    [dark_header]="44"          [dark_highlight]="46"
    [dark_warning]="43"          [dark_error]="41"
    [dark_success]="42"          [dark_info]="45"
    [dark_muted]="240"

    # Cyberpunk Theme
    [cyber_bg]="17"             [cyber_fg]="15"
    [cyber_header]="54"         [cyber_highlight]="57"
    [cyber_warning]="226"        [cyber_error]="196"
    [cyber_success]="46"         [cyber_info]="27"
    [cyber_muted]="236"
)

# ==============================================================================
# TUI状态
# ==============================================================================
declare -g TUI_RUNNING=false
declare -g TUI_LAST_UPDATE=0
declare -gA TUI_WIDGETS=()
declare -gA TUI_LAYOUT=()

# ==============================================================================
# 终端检测
# ==============================================================================
detect_terminal() {
    local term="${TERM:-}"
    local cols="${LINES:-}"

    # 检测颜色支持
    if [[ "${term}" == *"256color"* ]] || [[ "${term}" == *"xterm-256color"* ]]; then
        TUI_CONFIG[color_mode]="256color"
    elif [[ "${COLORTERM}" == "truecolor"* ]] || [[ "${term}" == *"direct"* ]]; then
        TUI_CONFIG[color_mode]="truecolor"
    else
        TUI_CONFIG[color_mode]="auto"
    fi

    # 检测终端大小
    if command -v tput &> /dev/null; then
        COLUMNS=$(tput cols 2>/dev/null || echo 80)
        LINES=$(tput lines 2>/dev/null || echo 24)
    fi

    log_debug "终端检测: TERM=${term}, COLS=${COLUMNS}, LINES=${LINES}, COLOR=${TUI_CONFIG[color_mode]}"
}

# ==============================================================================
# 颜色控制
# ==============================================================================
tui_color() {
    local color="$1"
    local text="$2"
    local theme="${TUI_CONFIG[theme]}"

    local bg="${TUI_COLORS[${theme}_bg]:-40}"
    local fg="${TUI_COLORS[${theme}_fg]:-37}"

    case "${color}" in
        reset)      echo "\033[0m" ;;
        bold)       echo "\033[1m" ;;
        dim)        echo "\033[2m" ;;
        underline)   echo "\033[4m" ;;
        blink)      echo "\033[5m" ;;
        reverse)    echo "\033[7m" ;;
        hidden)     echo "\033[8m" ;;
        header)     echo "\033[48;5;${TUI_COLORS[${theme}_header]}m\033[38;5;15m" ;;
        highlight)  echo "\033[48;5;${TUI_COLORS[${theme}_highlight]}m\033[38;5;0m" ;;
        warning)    echo "\033[48;5;${TUI_COLORS[${theme}_warning]}m\033[38;5;0m" ;;
        error)      echo "\033[48;5;${TUI_COLORS[${theme}_error]}m\033[38;5;15m" ;;
        success)    echo "\033[48;5;${TUI_COLORS[${theme}_success]}m\033[38;5;0m" ;;
        info)       echo "\033[48;5;${TUI_COLORS[${theme}_info]}m\033[38;5;15m" ;;
        muted)      echo "\033[38;5;${TUI_COLORS[${theme}_muted]}m" ;;
        *)
            if [[ -n "${text}" ]]; then
                echo "\033[${fg}m${text}\033[0m"
            else
                echo "\033[${fg}m"
            fi
            ;;
    esac
}

# ==============================================================================
# 光标控制
# ==============================================================================
tui_cursor_save() { echo -ne "\033[s"; }
tui_cursor_restore() { echo -ne "\033[u"; }
tui_cursor_home() { echo -ne "\033[H"; }
tui_cursor_up() { echo -ne "\033[${1}A"; }
tui_cursor_down() { echo -ne "\033[${1}B"; }
tui_cursor_left() { echo -ne "\033[${1}D"; }
tui_cursor_right() { echo -ne "\033[${1}C"; }
tui_cursor_move() { echo -ne "\033[${2};${1}H"; }
tui_cursor_hide() { echo -ne "\033[?25l"; }
tui_cursor_show() { echo -ne "\033[?25h"; }

# ==============================================================================
# 屏幕控制
# ==============================================================================
tui_clear() { echo -ne "\033[2J\033[H"; }
tui_clear_line() { echo -ne "\033[2K"; }
tui_clear_to_end() { echo -ne "\033[K"; }
tui_clear_from_start() { echo -ne "\033[1K"; }

# ==============================================================================
# 绘制函数
# ==============================================================================
# 绘制边框
tui_draw_box() {
    local width="${1:-80}"
    local height="${2:-10}"
    local title="${3:-}"
    local x="${4:-0}"
    local y="${5:-0}"

    local top_left="┌"
    local top_right="┐"
    local bottom_left="└"
    local bottom_right="┘"
    local horizontal="─"
    local vertical="│"

    # 移动到起始位置
    tui_cursor_move $((y + 1)) $((x + 1))

    # 绘制上边框
    echo -n "$(tui_color header)${top_left}"
    if [[ -n "${title}" ]]; then
        local title_len=${#title}
        local padding=$(((width - title_len - 2) / 2))
        echo -n "$(tui_color bold)${title}$(tui_color reset)"
        echo -n "$(tui_color header)${horizontal}"
    fi
    for ((i=0; i<width; i++)); do echo -n "${horizontal}"; done
    echo -n "$(tui_color reset)${top_right}"

    # 绘制侧边和内容
    for ((i=1; i<height; i++)); do
        tui_cursor_move $((y + i + 1)) $((x + 1))
        echo -n "$(tui_color header)${vertical}$(tui_color reset)"
        for ((j=0; j<width; j++)); do echo -n " "; done
        echo -n "$(tui_color header)${vertical}$(tui_color reset)"
    done

    # 绘制底边框
    tui_cursor_move $((y + height + 1)) $((x + 1))
    echo -n "$(tui_color header)${bottom_left}"
    for ((i=0; i<width; i++)); do echo -n "${horizontal}"; done
    echo -n "${bottom_right}$(tui_color reset)"
}

# 绘制进度条
tui_draw_progress() {
    local current="$1"
    local total="$2"
    local width="${3:-50}"
    local label="${4:-}"

    local percent=$((current * 100 / total))
    local filled=$((width * current / total))
    local empty=$((width - filled))

    echo -n "$(tui_color info)"
    if [[ -n "${label}" ]]; then
        echo -n "${label}: "
    fi

    # 绘制进度条
    echo -n "$(tui_color highlight)"
    for ((i=0; i<filled; i++)); do echo -n "█"; done
    echo -n "$(tui_color muted)"
    for ((i=0; i<empty; i++)); do echo -n "░"; done

    echo -n "$(tui_color reset) ${percent}%"
}

# 绘制水平条形图
tui_draw_hbar() {
    local value="$1"
    local max="$2"
    local width="${3:-40}"
    local color="$4"

    local bar_width=$((width * value / max))
    local empty_width=$((width - bar_width))

    echo -n "$(tui_color ${color})"
    for ((i=0; i<bar_width; i++)); do echo -n "▓"; done
    echo -n "$(tui_color muted)"
    for ((i=0; i<empty_width; i++)); do echo -n "░"; done
    echo "$(tui_color reset) ${value}/${max}"
}

# 绘制垂直条形图
tui_draw_vbar() {
    local value="$1"
    local max="$2"
    local height="${3:-10}"
    local color="$4"

    local bar_height=$((height * value / max))

    for ((i=0; i<height; i++)); do
        if [[ $i -ge $((height - bar_height)) ]]; then
            echo "$(tui_color ${color})█$(tui_color reset)"
        else
            echo "$(tui_color muted)░$(tui_color reset)"
        fi
    done
}

# 绘制迷你图
tui_draw_sparkline() {
    local -n values=("$@")
    local width="${#values[@]}"
    local max_val=0

    # 找到最大值
    for val in "${values[@]}"; do
        [[ ${val} -gt ${max_val} ]] && max_val=${val}
    done

    # 绘制sparkline
    for val in "${values[@]}"; do
        if [[ ${max_val} -eq 0 ]]; then
            echo -n "▁"
        else
            local level=$((val * 8 / max_val))
            case ${level} in
                0) echo -n "▁" ;;
                1) echo -n "▂" ;;
                2) echo -n "▃" ;;
                3) echo -n "▄" ;;
                4) echo -n "▅" ;;
                5) echo -n "▆" ;;
                6) echo -n "▇" ;;
                7|8) echo -n "█" ;;
            esac
        fi
    done
}

# ==============================================================================
# 组件函数
# ==============================================================================
# 实时监控面板
tui_monitor_panel() {
    local refresh_interval="${TUI_CONFIG[refresh_rate]}"

    tui_clear
    tui_cursor_hide

    while [[ "${TUI_RUNNING}" == "true" ]]; do
        local current_time=$(date +%s)

        # 检查是否需要刷新
        if [[ $((current_time - TUI_LAST_UPDATE)) -ge $((refresh_interval / 1000)) ]]; then
            tui_clear

            # 绘制顶部标题栏
            tui_draw_header_bar

            # 获取系统数据
            local mem_info=$(get_memory_info true)
            local mem_total mem_used mem_avail mem_percent
            read -r mem_total mem_used mem_avail mem_percent <<< "${mem_info}"

            local zram_info=$(get_zram_usage)
            local zram_total zram_used zram_percent
            read -r zram_total zram_used zram_percent <<< "${zram_info}"

            local swap_info=$(get_swap_info true)
            local swap_total swap_used swap_percent
            read -r swap_total swap_used swap_percent <<< "${swap_info}"

            # 获取时序数据用于趋势图
            local mem_trend=($(get_time_series_data "memory_usage" 20 | cut -d':' -f2))

            # 绘制主面板
            tui_draw_main_panel "${mem_percent}" "${zram_percent}" "${swap_percent}" "${mem_trend[@]}"

            # 绘制决策引擎状态
            if is_decision_engine_running; then
                tui_draw_decision_engine_status
            fi

            # 绘制底部状态栏
            tui_draw_status_bar

            TUI_LAST_UPDATE=${current_time}
        fi

        # 读取键盘输入（非阻塞）
        read -t 0.1 -n 1 key 2>/dev/null || true
        case "${key}" in
            q|Q) TUI_RUNNING=false ;;
            r|R) tui_refresh ;;
        esac
    done

    tui_cursor_show
    tui_clear
}

# 绘制顶部标题栏
tui_draw_header_bar() {
    local width=${COLUMNS:-80}
    local title="Z-Panel Pro V8.0 - 实时监控"
    local time=$(date '+%Y-%m-%d %H:%M:%S')

    echo -n "$(tui_color header)"
    printf '╔'
    for ((i=0; i<width-2; i++)); do printf '═'; done
    printf '╗'
    echo "$(tui_color reset)"

    echo -n "$(tui_color header)║$(tui_color bold)"
    printf " %-${width}s " "${title}"
    echo -n "$(tui_color header)║ $(tui_color info)${time}$(tui_color reset)"

    echo -n "$(tui_color header)╠"
    for ((i=0; i<width-2; i++)); do printf '═'; done
    printf '╣'
    echo "$(tui_color reset)"
}

# 绘制主面板
tui_draw_main_panel() {
    local mem_percent="$1"
    local zram_percent="$2"
    local swap_percent="$3"
    shift 3
    local -n mem_trend=("$@")

    local width=${COLUMNS:-80}
    local panel_width=$((width - 10))

    # 内存使用面板
    tui_draw_box $((panel_width / 2 - 2)) 8 "内存使用" 1 2
    tui_cursor_move 5 4
    echo "$(tui_color bold)内存: $(tui_color highlight)${mem_percent}%$(tui_color reset)"
    tui_cursor_move 6 4
    tui_draw_hbar ${mem_percent} 100 $((panel_width / 2 - 8)) "success"

    # ZRAM使用面板
    tui_draw_box $((panel_width / 2 - 2)) 8 "ZRAM使用" $((panel_width / 2)) 2
    tui_cursor_move 5 $((panel_width / 2 + 4))
    echo "$(tui_color bold)ZRAM: $(tui_color highlight)${zram_percent}%$(tui_color reset)"
    tui_cursor_move 6 $((panel_width / 2 + 4))
    tui_draw_hbar ${zram_percent} 100 $((panel_width / 2 - 8)) "info"

    # Swap使用面板
    tui_draw_box $((panel_width / 2 - 2)) 8 "Swap使用" 1 12
    tui_cursor_move 5 4
    echo "$(tui_color bold)Swap: $(tui_color highlight)${swap_percent}%$(tui_color reset)"
    tui_cursor_move 6 4
    tui_draw_hbar ${swap_percent} 100 $((panel_width / 2 - 8)) "warning"

    # 趋势图
    if [[ "${TUI_CONFIG[show_trends]}" == "true" ]] && [[ ${#mem_trend[@]} -gt 5 ]]; then
        tui_draw_box $((panel_width - 4)) 6 "内存趋势" 1 22
        tui_cursor_move 24 4
        tui_draw_sparkline "${mem_trend[@]}"
    fi
}

# 绘制决策引擎状态
tui_draw_decision_engine_status() {
    local status=$(get_decision_engine_status)
    local is_running=$(echo "${status}" | grep -o '"running":[a-z]*' | cut -d':' -f2)
    local decision_count=$(echo "${status}" | grep -o '"decision_count":[0-9]*' | cut -d':' -f2)
    local last_type=$(echo "${status}" | grep -o '"last_decision_type":"[^"]*"' | cut -d'"' -f4)

    local width=${COLUMNS:-80}
    local box_width=$((width - 10))

    tui_draw_box ${box_width} 5 "智能决策引擎" 1 28

    if [[ "${is_running}" == "true" ]]; then
        tui_cursor_move 30 4
        echo "$(tui_color success)● 运行中$(tui_color reset)"
    else
        tui_cursor_move 30 4
        echo "$(tui_color muted)○ 已停止$(tui_color reset)"
    fi

    tui_cursor_move 31 4
    echo "$(tui_color info)决策次数: $(tui_color highlight)${decision_count}$(tui_color reset)"
    tui_cursor_move 32 4
    echo "$(tui_color info)上次决策: $(tui_color highlight)${last_type}$(tui_color reset)"
}

# 绘制状态栏
tui_draw_status_bar() {
    local width=${COLUMNS:-80}

    echo -n "$(tui_color header)╚"
    for ((i=0; i<width-2; i++)); do printf '═'; done
    printf '╝'
    echo "$(tui_color reset)"

    echo -n "$(tui_color header)║$(tui_color reset)"
    echo -n " [Q]退出  [R]刷新  "

    # 显示决策引擎状态
    if is_decision_engine_running; then
        echo -n "$(tui_color success)● DE$(tui_color reset)  "
    else
        echo -n "$(tui_color muted)○ DE$(tui_color reset)  "
    fi

    # 显示流处理器状态
    if is_stream_processor_running "metrics"; then
        echo -n "$(tui_color info)● SP$(tui_color reset)"
    else
        echo -n "$(tui_color muted)○ SP$(tui_color reset)"
    fi

    echo "$(tui_color header)║$(tui_color reset)"
}

# 刷新
tui_refresh() {
    TUI_LAST_UPDATE=0
    tui_clear
}

# ==============================================================================
# 交互式菜单
# ==============================================================================
# 交互式选择器
tui_select() {
    local title="$1"
    shift
    local -a options=("$@")

    local selection=0
    local key=""

    while true; do
        tui_clear

        # 绘制标题
        echo "$(tui_color header)╔═══════════════════════════════════════╗$(tui_color reset)"
        echo "$(tui_color header)║$(tui_color bold)$(tui_color highlight) ${title} $(tui_color reset)$(tui_color header)║$(tui_color reset)"
        echo "$(tui_color header)╠═══════════════════════════════════════╣$(tui_color reset)"

        # 绘制选项
        for i in "${!options[@]}"; do
            if [[ ${i} -eq ${selection} ]]; then
                echo "$(tui_color header)║$(tui_color highlight) > ${options[$i]} $(tui_color reset)$(tui_color header)║$(tui_color reset)"
            else
                echo "$(tui_color header)║$(tui_color muted)   ${options[$i]}   $(tui_color reset)$(tui_color header)║$(tui_color reset)"
            fi
        done

        echo "$(tui_color header)╚═══════════════════════════════════════╝$(tui_color reset)"
        echo -n "$(tui_color info)使用 ↑↓ 选择，Enter 确认，Q 取消: $(tui_color reset)"

        # 读取按键
        read -n 1 -s key 2>/dev/null
        case "${key}" in
            $'\e[A'|$'\e'[A)  # Up
                ((selection > 0)) && ((selection--))
                ;;
            $'\e[B'|$'\e'[B)  # Down
                ((selection < ${#options[@]} - 1)) && ((selection++))
                ;;
            '')  # Enter
                echo "${options[$selection]}"
                return 0
                ;;
            q|Q)  # Quit
                return 1
                ;;
        esac
    done
}

# 交互式输入
tui_input() {
    local prompt="$1"
    local default="${2:-}"
    local -n mask=("${@:3}")

    echo -n "$(tui_color info)${prompt}: $(tui_color reset)"

    if [[ ${#mask[@]} -gt 0 ]]; then
        # 密码输入模式
        local input=""
        local key=""
        while true; do
            read -n 1 -s key
            case "${key}" in
                '')  # Enter
                    echo ""
                    if [[ -z "${input}" ]]; then
                        echo "${default}"
                    else
                        echo "${input}"
                    fi
                    return 0
                    ;;
                $'\x7f'|$'\x08')  # Backspace
                    if [[ -n "${input}" ]]; then
                        input="${input%?}"
                        echo -ne "\b \b"
                    fi
                    ;;
                *)
                    input+="${key}"
                    echo -n "*"
                    ;;
            esac
        done
    else
        # 普通输入模式
        if [[ -n "${default}" ]]; then
            read -p "[${default}]: " input
            echo "${input:-${default}}"
        else
            read input
            echo "${input}"
        fi
    fi
}

# ==============================================================================
# 通知系统
# ==============================================================================
# 显示通知
tui_notify() {
    local level="$1"
    local title="$2"
    local message="$3"
    local duration="${4:-3}"

    local width=${COLUMNS:-80}
    local box_width=$((width / 2))
    local box_height=5

    local color="${level}"
    case "${level}" in
        success) color="success" ;;
        warning) color="warning" ;;
        error) color="error" ;;
        info) color="info" ;;
    esac

    # 保存当前光标位置
    tui_cursor_save

    # 绘制通知框
    local box_y=$((LINES / 2 - box_height / 2))
    local box_x=$((width / 2 - box_width / 2))

    tui_draw_box ${box_width} ${box_height} "${title}" ${box_x} ${box_y}

    # 显示消息
    tui_cursor_move $((box_y + 2)) $((box_x + 2))
    echo "$(tui_color ${color})${message}$(tui_color reset)"

    # 等待
    sleep ${duration}

    # 恢复光标
    tui_cursor_restore
}

# ==============================================================================
# 初始化和清理
# ==============================================================================
# 初始化TUI引擎
init_tui_engine() {
    log_debug "初始化TUI引擎..."

    # 检测终端
    detect_terminal

    # 设置终端模式
    stty -echo -icanon 2>/dev/null || true

    # 设置陷阱处理
    trap 'tui_cleanup' EXIT INT TERM

    log_debug "TUI引擎初始化完成"
    return 0
}

# 清理TUI引擎
cleanup_tui_engine() {
    log_debug "清理TUI引擎..."

    # 恢复终端模式
    stty echo icanon 2>/dev/null || true

    # 显示光标
    tui_cursor_show

    # 清除屏幕
    tui_clear

    log_debug "TUI引擎清理完成"
    return 0
}

# 启动实时监控
start_tui_monitor() {
    TUI_RUNNING=true
    tui_monitor_panel
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f tui_color
export -f tui_cursor_save
export -f tui_cursor_restore
export -f tui_draw_box
export -f tui_draw_progress
export -f tui_draw_hbar
export -f tui_draw_vbar
export -f tui_draw_sparkline
export -f tui_monitor_panel
export -f tui_select
export -f tui_input
export -f tui_notify
export -f init_tui_engine
export -f cleanup_tui_engine
export -f start_tui_monitor
