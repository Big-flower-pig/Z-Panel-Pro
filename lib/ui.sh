#!/bin/bash
# ==============================================================================
# Z-Panel Pro V9.0 - UI组件库
# ==============================================================================
# @description    提供统一的UI绘制函数
# @version       9.0.0-Lightweight
# @author        Z-Panel Team
# @license       MIT License
# ==============================================================================

# ==============================================================================
# UI边框绘制函数
# ==============================================================================

# 绘制顶部边框
ui_draw_top() {
    printf "${COLOR_CYAN}┌$(printf '%.0s─' $(seq 1 ${UI_WIDTH}))┐${COLOR_NC}\n"
}

# 绘制底部边框
ui_draw_bottom() {
    printf "${COLOR_CYAN}└$(printf '%.0s─' $(seq 1 ${UI_WIDTH}))┘${COLOR_NC}\n"
}

# 绘制分隔线
ui_draw_line() {
    printf "${COLOR_CYAN}├$(printf '%.0s─' $(seq 1 ${UI_WIDTH}))┤${COLOR_NC}\n"
}

# 绘制文本行
# @param text: 要显示的文本
# @param color: 可选颜色，默认为COLOR_NC
ui_draw_row() {
    local text="$1"
    local color="${2:-${COLOR_NC}}"

    # 移除ANSI转义序列计算宽度
    local plain_text
    plain_text=$(echo -e "${text}" | sed 's/\x1b\[[0-9;]*m//g')

    local pad=$(( UI_WIDTH - ${#plain_text} - 2 ))
    printf "${COLOR_CYAN}│${COLOR_NC} ${color}${text}${COLOR_NC}$(printf '%*s' ${pad} '')${COLOR_CYAN}│${COLOR_NC}\n"
}

# 绘制标题
# @param title: 标题文本
ui_draw_header() {
    ui_draw_top
    local title=" $1 "
    local pad=$(( (UI_WIDTH - ${#title}) / 2 ))
    printf "${COLOR_CYAN}│${COLOR_NC}$(printf '%*s' ${pad} '')${COLOR_WHITE}${title}${COLOR_NC}$(printf '%*s' $((UI_WIDTH-pad-${#title})) '')${COLOR_CYAN}│${COLOR_NC}\n"
    ui_draw_line
}

# 绘制章节标题
# @param title: 章节标题
ui_draw_section() {
    ui_draw_line
    ui_draw_row " ${COLOR_WHITE}$1${COLOR_NC}"
    ui_draw_line
}

# 绘制菜单项
# @param num: 选项编号
# @param text: 选项文本
ui_draw_menu_item() {
    local num="$1"
    local text="$2"
    local item="${COLOR_GREEN}${num}.${COLOR_NC} ${text}"
    ui_draw_row "  ${item}"
}

# ==============================================================================
# 进度条绘制函数
# ==============================================================================

# ==============================================================================
# 绘制进度条
# @param current: 当前值 (必需，>=0)
# @param total: 总值 (必需，>0)
# @param width: 进度条宽度 (可选，默认46，范围10-100)
# @param label: 标签文本 (可选)
# ==============================================================================
ui_draw_progress_bar() {
    # 参数验证
    if [[ ${#} -lt 2 ]]; then
        log_error "ui_draw_progress_bar: 缺少必需参数 (current, total)"
        return 1
    fi

    local current=$1
    local total=$2
    local width=${3:-46}
    local label="${4:-}"

    # 验证current为非负数
    if ! [[ "${current}" =~ ^[0-9]+$ ]]; then
        log_error "无效的current值: ${current} (必须是非负整数)"
        return 1
    fi

    # 验证total为正数
    if ! validate_positive_integer "${total}"; then
        log_error "无效的total值: ${total} (必须是正整数)"
        return 1
    fi

    # 验证width范围 (10-100)
    if [[ ${width} -lt 10 ]]; then
        width=10
    elif [[ ${width} -gt 100 ]]; then
        width=100
    fi

    [[ -n "${label}" ]] && echo -ne "${COLOR_WHITE}${label}${COLOR_NC} "

    # 边界检查
    [[ "${total}" -eq 0 ]] && total=1
    [[ "${current}" -gt "${total}" ]] && current=${total}

    local filled=$((current * width / total)) || true
    local empty=$((width - filled)) || true
    local percent=$((current * 100 / total)) || true

    # 根据百分比选择颜色
    local bar_color="${COLOR_GREEN}"
    if [[ ${percent} -ge ${PROGRESS_THRESHOLD_CRITICAL} ]]; then
        bar_color="${COLOR_RED}"
    elif [[ ${percent} -ge ${PROGRESS_THRESHOLD_HIGH} ]]; then
        bar_color="${COLOR_YELLOW}"
    elif [[ ${percent} -ge ${PROGRESS_THRESHOLD_MEDIUM} ]]; then
        bar_color="${COLOR_CYAN}"
    fi

    # 绘制进度条
    echo -ne "${COLOR_WHITE}[${COLOR_NC}"
    local filled_bar=$(printf "%${filled}s" '' | tr ' ' '=')
    local empty_bar=$(printf "%${empty}s" '' | tr ' ' '-')
    echo -ne "${bar_color}${filled_bar}${COLOR_NC}${COLOR_WHITE}${empty_bar}${COLOR_NC}]${COLOR_NC} "

    # 绘制百分比
    if [[ ${percent} -ge 90 ]]; then
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
# 压缩比图表绘制函数
# ==============================================================================

# ==============================================================================
# 绘制压缩比图表
# @param ratio: 压缩比 (必需，>=0)
# @param width: 图表宽度 (可选，默认46，范围10-100)
# ==============================================================================
ui_draw_compression_chart() {
    # 参数验证
    if [[ ${#} -eq 0 ]]; then
        log_error "ui_draw_compression_chart: 缺少必需参数 ratio"
        return 1
    fi

    local ratio=$1
    local width=${2:-46}

    # 验证ratio为非负数
    if ! [[ "${ratio}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        log_error "无效的ratio值: ${ratio} (必须是非负数)"
        return 1
    fi

    # 验证width范围 (10-100)
    if [[ ${width} -lt 10 ]]; then
        width=10
    elif [[ ${width} -gt 100 ]]; then
        width=100
    fi

    local filled=0
    local bar_color="${COLOR_GREEN}"

    # 根据压缩比确定填充比例
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

    echo -ne "${COLOR_CYAN}压缩比: ${ratio}x ${COLOR_NC}"

    echo -ne "${COLOR_WHITE}[${COLOR_NC}"
    local filled_bar=$(printf "%${filled}s" '' | tr ' ' '=')
    local empty_bar=$(printf "%${empty}s" '' | tr ' ' '-')
    echo -e "${bar_color}${filled_bar}${COLOR_NC}${COLOR_WHITE}${empty_bar}${COLOR_NC}]${COLOR_NC}"
}

# ==============================================================================
# 交互函数
# ==============================================================================

# 确认对话框
# @param message: 提示消息
# @param default: 默认值（Y/n或y/N，默认N）
# @return: 0表示确认，1表示取消
ui_confirm() {
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

# 暂停等待
ui_pause() {
    echo -ne "${COLOR_CYAN}按Enter继续...${COLOR_NC}"
    read -r
}

# 清屏
ui_clear() {
    clear
}

# ==============================================================================
# 输入框
# @param prompt: 提示文本 (必需)
# @param default: 默认值 (可选)
# @return: 用户输入
# ==============================================================================
ui_input() {
    # 参数验证
    if [[ ${#} -eq 0 ]]; then
        log_error "ui_input: 缺少必需参数 prompt"
        return 1
    fi

    local prompt="$1"
    local default="${2:-}"
    local result

    # 限制prompt长度 (最大200字符)
    if [[ ${#prompt} -gt 200 ]]; then
        log_warn "提示文本过长，已截断为200字符"
        prompt="${prompt:0:200}"
    fi

    echo -ne "${COLOR_WHITE}${prompt}${COLOR_NC}"
    read -r result

    if [[ -z "${result}" ]] && [[ -n "${default}" ]]; then
        echo "${default}"
    else
        echo "${result}"
    fi
}

# ==============================================================================
# 密码输入框
# @param prompt: 提示文本 (必需)
# @return: 密码
# ==============================================================================
ui_password() {
    # 参数验证
    if [[ ${#} -eq 0 ]]; then
        log_error "ui_password: 缺少必需参数 prompt"
        return 1
    fi

    local prompt="$1"
    local password

    # 限制prompt长度 (最大200字符)
    if [[ ${#prompt} -gt 200 ]]; then
        log_warn "提示文本过长，已截断为200字符"
        prompt="${prompt:0:200}"
    fi

    echo -ne "${COLOR_WHITE}${prompt}${COLOR_NC}"
    read -s -r password
    echo ""
    echo "${password}"
}

# ==============================================================================
# 菜单函数
# ==============================================================================

# ==============================================================================
# 单选菜单
# @param title: 菜单标题 (必需)
# @param options: 选项列表 (必需，至少1个选项)
# @return: 选中的选项编号（从1开始）
# ==============================================================================
ui_select_menu() {
    # 参数验证
    if [[ ${#} -lt 2 ]]; then
        log_error "ui_select_menu: 缺少必需参数 (title, options)"
        return 1
    fi

    local title="$1"
    shift
    local options=("$@")

    # 验证至少有一个选项
    if [[ ${#options[@]} -eq 0 ]]; then
        log_error "ui_select_menu: 选项列表不能为空"
        return 1
    fi

    # 验证选项数量不超过50个
    if [[ ${#options[@]} -gt 50 ]]; then
        log_warn "选项数量过多 (${#options[@]})，已限制为50个"
        options=("${options[@]:0:50}")
    fi

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

        echo -e "${COLOR_RED}无效选择${COLOR_NC}"
        sleep 1
    done
}

# ==============================================================================
# 多选菜单
# @param title: 菜单标题 (必需)
# @param options: 选项列表 (必需，至少1个选项)
# @return: 选中的选项编号（逗号分隔）
# ==============================================================================
ui_multi_select_menu() {
    # 参数验证
    if [[ ${#} -lt 2 ]]; then
        log_error "ui_multi_select_menu: 缺少必需参数 (title, options)"
        return 1
    fi

    local title="$1"
    shift
    local options=("$@")
    local -A selected

    # 验证至少有一个选项
    if [[ ${#options[@]} -eq 0 ]]; then
        log_error "ui_multi_select_menu: 选项列表不能为空"
        return 1
    fi

    # 验证选项数量不超过50个
    if [[ ${#options[@]} -gt 50 ]]; then
        log_warn "选项数量过多 (${#options[@]})，已限制为50个"
        options=("${options[@]:0:50}")
    fi

    while true; do
        ui_clear
        ui_draw_header "${title}"
        ui_draw_row "  使用方向键选择，空格切换，Enter确认"
        ui_draw_line

        local i=1
        for option in "${options[@]}"; do
            local marker=" "
            if [[ "${selected[$i]}" == "1" ]]; then
                marker="${COLOR_GREEN}*${COLOR_NC}"
            fi
            printf "${COLOR_CYAN}│${COLOR_NC} ${marker} %2d. %s$(printf '%*s' $((UI_WIDTH - ${#option} - 8)) '')${COLOR_CYAN}│${COLOR_NC}\n" "${i}" "${option}"
            ((i++)) || true
        done

        ui_draw_bottom
        echo ""
        echo -ne "${COLOR_WHITE}请选择 [1-${#options[@]} 空格切换 Enter确认]: ${COLOR_NC}"
        read -r choice

        if [[ -z "${choice}" ]]; then
            # 返回选择结果
            local result=""
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

# 显示表格
# @param headers: 表头数组
# @param rows: 行数据数组（每个元素是一行数据）
ui_show_table() {
    local headers=("$@")
    shift
    local -a rows=()

    # 计算列宽
    local -a col_widths=()
    local num_cols=${#headers[@]}

    # 初始化为表头宽度
    for ((i=0; i<num_cols; i++)); do
        col_widths[$i]=${#headers[$i]}
    done

    # 计算最大列宽（限制在UI宽度内）
    local max_width=$((UI_WIDTH - 4))
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

    # 显示占位行（实际使用时传入数据）
    ui_draw_row " ${COLOR_YELLOW}表格数据${COLOR_NC}"

    ui_draw_bottom
}
