#!/bin/bash
# ==============================================================================
# Z-Panel Pro - UI引擎模块
# ==============================================================================
# @description    统一的UI渲染引擎
# @version       7.1.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# UI基础绘制函数
# ==============================================================================

# 绘制顶部边框
ui_draw_top() {
    printf "${COLOR_CYAN}�?(printf '%.0s─' $(seq 1 ${UI_WIDTH}))�?{COLOR_NC}\n"
}

# 绘制底部边框
ui_draw_bottom() {
    printf "${COLOR_CYAN}�?(printf '%.0s─' $(seq 1 ${UI_WIDTH}))�?{COLOR_NC}\n"
}

# 绘制分隔�?ui_draw_line() {
    printf "${COLOR_CYAN}�?(printf '%.0s─' $(seq 1 ${UI_WIDTH}))�?{COLOR_NC}\n"
}

# 绘制单行内容
# @param text: 要显示的文本
# @param color: 颜色（可选，默认为COLOR_NC�?ui_draw_row() {
    local text="$1"
    local color="${2:-${COLOR_NC}}"

    # 移除ANSI转义码计算长�?    local plain_text
    plain_text=$(echo -e "${text}" | sed 's/\x1b\[[0-9;]*m//g')

    local pad=$(( UI_WIDTH - ${#plain_text} - 2 ))
    printf "${COLOR_CYAN}�?{COLOR_NC} ${color}${text}${COLOR_NC}$(printf '%*s' ${pad} '')${COLOR_CYAN}�?{COLOR_NC}\n"
}

# 绘制标题
# @param title: 标题文本
ui_draw_header() {
    ui_draw_top
    local title=" $1 "
    local pad=$(( (UI_WIDTH - ${#title}) / 2 ))
    printf "${COLOR_CYAN}�?{COLOR_NC}$(printf '%*s' ${pad} '')${COLOR_WHITE}${title}${COLOR_NC}$(printf '%*s' $((UI_WIDTH-pad-${#title})) '')${COLOR_CYAN}�?{COLOR_NC}\n"
    ui_draw_line
}

# 绘制章节
# @param title: 章节标题
ui_draw_section() {
    ui_draw_line
    ui_draw_row " ${COLOR_WHITE}$1${COLOR_NC}"
    ui_draw_line
}

# 绘制菜单�?# @param num: 菜单编号
# @param text: 菜单文本
ui_draw_menu_item() {
    local num="$1"
    local text="$2"
    local item="${COLOR_GREEN}${num}.${COLOR_NC} ${text}"
    ui_draw_row "  ${item}"
}

# ==============================================================================
# 进度条显示函�?# ==============================================================================

# 绘制进度�?# @param current: 当前进度�?# @param total: 总�?# @param width: 进度条宽度（可选，默认46�?# @param label: 标签（可选）
ui_draw_progress_bar() {
    local current=$1
    local total=$2
    local width=${3:-46}
    local label="${4:-}"

    [[ -n "${label}" ]] && echo -ne "${COLOR_WHITE}${label}${COLOR_NC} "

    # 防止除零
    [[ "${total}" -eq 0 ]] && total=1
    [[ "${current}" -gt "${total}" ]] && current=${total}

    local filled=$((current * width / total)) || true
    local empty=$((width - filled)) || true
    local percent=$((current * 100 / total)) || true

    # 颜色选择
    local bar_color="${COLOR_GREEN}"
    if [[ ${percent} -ge ${PROGRESS_THRESHOLD_CRITICAL} ]]; then
        bar_color="${COLOR_RED}"
    elif [[ ${percent} -ge ${PROGRESS_THRESHOLD_HIGH} ]]; then
        bar_color="${COLOR_YELLOW}"
    elif [[ ${percent} -ge ${PROGRESS_THRESHOLD_MEDIUM} ]]; then
        bar_color="${COLOR_CYAN}"
    fi

    # 渲染进度�?    echo -ne "${COLOR_WHITE}[${COLOR_NC}"
    local filled_bar=$(printf "%${filled}s" '' | tr ' ' '=')
    local empty_bar=$(printf "%${empty}s" '' | tr ' ' '-')
    echo -ne "${bar_color}${filled_bar}${COLOR_NC}${COLOR_WHITE}${empty_bar}${COLOR_NC}]${COLOR_NC} "

    # 渲染百分�?    if [[ ${percent} -ge 90 ]]; then
        echo -e "${COLOR_RED}${percent}%${COLOR_NC}"
    elif [[ ${percent} -ge 70 ]]; then
        echo -e "${COLOR_YELLOW}${percent}%${COLOR_NC}"
    elif [[ ${percent} -ge 50 ]]; then
        echo -e "${COLOR_CYAN}${percent}%${COLOR_NC}"
    else
        echo -e "${COLOR_GREEN}${percent}%${COLOR_NC}"
    fi
}

# ==============================================================================
# 压缩比图表显示函�?# ==============================================================================

# 绘制压缩比图�?# @param ratio: 压缩�?# @param width: 图表宽度（可选，默认46�?ui_draw_compression_chart() {
    local ratio=$1
    local width=${2:-46}

    local filled=0
    local bar_color="${COLOR_GREEN}"

    # 使用awk进行浮点比较
    if compare_float "ge" "${ratio}" "${COMPRESSION_RATIO_EXCELLENT}"; then
        filled=$((width * 100 / 100)) || true
        bar_color="${COLOR_GREEN}"
    elif compare_float "ge" "${ratio}" "${COMPRESSION_RATIO_GOOD}"; then
        filled=$((width * 75 / 100)) || true
        bar_color="${COLOR_CYAN}"
    elif compare_float "ge" "${ratio}" "${COMPRESSION_RATIO_FAIR}"; then
        filled=$((width * 50 / 100)) || true
        bar_color="${COLOR_YELLOW}"
    else
        filled=$((width * 25 / 100)) || true
        bar_color="${COLOR_RED}"
    fi

    local empty=$((width - filled))

    echo -ne "${COLOR_CYAN}压缩�? ${ratio}x ${COLOR_NC}"

    echo -ne "${COLOR_WHITE}[${COLOR_NC}"
    local filled_bar=$(printf "%${filled}s" '' | tr ' ' '=')
    local empty_bar=$(printf "%${empty}s" '' | tr ' ' '-')
    echo -e "${bar_color}${filled_bar}${COLOR_NC}${COLOR_WHITE}${empty_bar}${COLOR_NC}]${COLOR_NC}"
}

# ==============================================================================
# 交互函数
# ==============================================================================

# 确认对话�?# @param message: 确认消息
# @param default: 默认值（Y/n或y/N，默认N�?# @return: 0为确认，1为取�?ui_confirm() {
    local message="$1"
    local default="${2:-N}"
    local prompt

    if [[ "${default}" == "Y" ]]; then
        prompt="${COLOR_YELLOW}${message} (Y/n): ${COLOR_NC}"
    else
        prompt="${COLOR_YELLOW}${message} (y/N): ${COLOR_NC}"
    fi

    echo -ne "${prompt}"
    read -r response

    if [[ -z "${response}" ]]; then
        [[ "${default}" == "Y" ]]
    else
        [[ "${response}" =~ ^[Yy]$ ]]
    fi
}

# 暂停等待用户输入
ui_pause() {
    echo -ne "${COLOR_CYAN}�?Enter 继续...${COLOR_NC}"
    read -r
}

# 清屏
ui_clear() {
    clear
}

# 获取用户输入
# @param prompt: 提示信息
# @param default: 默认值（可选）
# @return: 用户输入
ui_input() {
    local prompt="$1"
    local default="${2:-}"
    local result

    echo -ne "${COLOR_WHITE}${prompt}${COLOR_NC}"
    read -r result

    if [[ -z "${result}" ]] && [[ -n "${default}" ]]; then
        echo "${default}"
    else
        echo "${result}"
    fi
}

# 获取密码输入（不回显�?# @param prompt: 提示信息
# @return: 密码
ui_password() {
    local prompt="$1"
    local password

    echo -ne "${COLOR_WHITE}${prompt}${COLOR_NC}"
    read -s -r password
    echo ""
    echo "${password}"
}

# ==============================================================================
# 选择菜单
# ==============================================================================

# 单选菜�?# @param title: 菜单标题
# @param options: 选项数组
# @return: 选中的索引（�?开始）
ui_select_menu() {
    local title="$1"
    shift
    local options=("$@")

    while true; do
        ui_clear
        ui_draw_header "${title}"

        local i=1
        for option in "${options[@]}"; do
            ui_draw_menu_item "${i}" "${option}"
            ((i++)) || true
        done

        ui_draw_bottom
        echo ""
        echo -ne "${COLOR_WHITE}请选择 [1-${#options[@]}]: ${COLOR_NC}"
        read -r choice

        if [[ "${choice}" =~ ^[0-9]+$ ]] && \
           [[ ${choice} -ge 1 ]] && \
           [[ ${choice} -le ${#options[@]} ]]; then
            echo "${choice}"
            return 0
        fi

        echo -e "${COLOR_RED}无效输入${COLOR_NC}"
        sleep 1
    done
}

# 多选菜�?# @param title: 菜单标题
# @param options: 选项数组
# @return: 选中的索引列表（逗号分隔�?ui_multi_select_menu() {
    local title="$1"
    shift
    local options=("$@")
    local -A selected

    while true; do
        ui_clear
        ui_draw_header "${title}"
        ui_draw_row "  使用空格选择，Enter确认"
        ui_draw_line

        local i=1
        for option in "${options[@]}"; do
            local marker=" "
            if [[ "${selected[$i]}" == "1" ]]; then
                marker="${COLOR_GREEN}*${COLOR_NC}"
            fi
            printf "${COLOR_CYAN}�?{COLOR_NC} ${marker} %2d. %s$(printf '%*s' $((UI_WIDTH - ${#option} - 8)) '')${COLOR_CYAN}�?{COLOR_NC}\n" "${i}" "${option}"
            ((i++)) || true
        done

        ui_draw_bottom
        echo ""
        echo -ne "${COLOR_WHITE}请选择 [1-${#options[@]} �?Enter确认]: ${COLOR_NC}"
        read -r choice

        if [[ -z "${choice}" ]]; then
            # 返回选中的索�?            local result=""
            for i in "${!selected[@]}"; do
                if [[ "${selected[$i]}" == "1" ]]; then
                    [[ -n "${result}" ]] && result+=","
                    result+="${i}"
                fi
            done
            echo "${result}"
            return 0
        fi

        if [[ "${choice}" =~ ^[0-9]+$ ]] && \
           [[ ${choice} -ge 1 ]] && \
           [[ ${choice} -le ${#options[@]} ]]; then
            if [[ "${selected[$choice]}" == "1" ]]; then
                selected[$choice]="0"
            else
                selected[$choice]="1"
            fi
        fi
    done
}

# ==============================================================================
# 表格显示函数
# ==============================================================================

# 显示简单表�?# @param headers: 表头数组
# @param rows: 行数组（每行是一个数组）
ui_show_table() {
    local headers=("$@")
    shift
    local -a rows=()

    # 计算每列宽度
    local -a col_widths=()
    local num_cols=${#headers[@]}

    # 初始化列�?    for ((i=0; i<num_cols; i++)); do
        col_widths[$i]=${#headers[$i]}
    done

    # 更新列宽（这里简化处理，实际应遍历所有行�?    local max_width=$((UI_WIDTH - 4))
    local col_width=$((max_width / num_cols))

    for ((i=0; i<num_cols; i++)); do
        col_widths[$i]=${col_width}
    done

    # 绘制表头
    ui_draw_header "表格"

    local header_row=""
    for ((i=0; i<num_cols; i++)); do
        local header="${headers[$i]}"
        printf -v header "%-${col_width}s" "${header}"
        header_row+="${COLOR_WHITE}${header}${COLOR_NC} "
    done
    ui_draw_row " ${header_row}"
    ui_draw_line

    # 绘制数据行（简化处理）
    ui_draw_row " ${COLOR_YELLOW}暂无数据${COLOR_NC}"

    ui_draw_bottom
}