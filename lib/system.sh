#!/bin/bash
# ==============================================================================
# Z-Panel Pro - 系统检测模�?# ==============================================================================
# @description    系统信息检测与包管�?# @version       7.1.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

# ==============================================================================
# 检测系统信�?# ==============================================================================

detect_system() {
    log_info "检测系统信�?.."

    # 检测发行版
    if [[ -f /etc/os-release ]]; then
        SYSTEM_INFO[distro]=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
        SYSTEM_INFO[version]=$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
        SYSTEM_INFO[distro]="${SYSTEM_INFO[distro],,}"
    elif [[ -f /etc/redhat-release ]]; then
        SYSTEM_INFO[distro]="centos"
        SYSTEM_INFO[version]=$(cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+' | head -1)
    elif [[ -f /etc/alpine-release ]]; then
        SYSTEM_INFO[distro]="alpine"
        SYSTEM_INFO[version]=$(cat /etc/alpine-release)
    else
        handle_error "SYSTEM_DETECT" "无法检测系统发行版" "exit"
    fi

    # 检测包管理�?    if check_command apt-get; then
        SYSTEM_INFO[package_manager]="apt"
    elif check_command yum; then
        SYSTEM_INFO[package_manager]="yum"
    elif check_command apk; then
        SYSTEM_INFO[package_manager]="apk"
    elif check_command dnf; then
        SYSTEM_INFO[package_manager]="dnf"
    elif check_command pacman; then
        SYSTEM_INFO[package_manager]="pacman"
    else
        SYSTEM_INFO[package_manager]="unknown"
    fi

    # 检测内�?    local mem_total
    mem_total=$(free -m | awk '/^Mem:/ {print $2}')
    if [[ -z "${mem_total}" ]] || [[ "${mem_total}" -lt 1 ]]; then
        handle_error "SYSTEM_DETECT" "无法获取内存信息" "exit"
    fi
    SYSTEM_INFO[total_memory_mb]=${mem_total}

    # 检测CPU核心�?    local cores
    cores=$(nproc 2>/dev/null || echo 1)
    [[ ${cores} -lt 1 ]] && cores=1
    SYSTEM_INFO[cpu_cores]=${cores}

    log_info "系统: ${SYSTEM_INFO[distro]} ${SYSTEM_INFO[version]}"
    log_info "内存: ${SYSTEM_INFO[total_memory_mb]}MB"
    log_info "CPU: ${SYSTEM_INFO[cpu_cores]} 核心"
    log_info "包管理器: ${SYSTEM_INFO[package_manager]}"

    return 0
}

# ==============================================================================
# 获取系统发行�?# ==============================================================================
get_distro() {
    echo "${SYSTEM_INFO[distro]}"
}

# ==============================================================================
# 获取系统版本
# ==============================================================================
get_version() {
    echo "${SYSTEM_INFO[version]}"
}

# ==============================================================================
# 获取包管理器
# ==============================================================================
get_package_manager() {
    echo "${SYSTEM_INFO[package_manager]}"
}

# ==============================================================================
# 获取总内存（MB�?# ==============================================================================
get_total_memory() {
    echo "${SYSTEM_INFO[total_memory_mb]}"
}

# ==============================================================================
# 获取CPU核心�?# ==============================================================================
get_cpu_cores() {
    echo "${SYSTEM_INFO[cpu_cores]}"
}

# ==============================================================================
# 检查内核版�?# ==============================================================================
check_kernel_version() {
    local min_version="$1"
    local current_version
    current_version=$(uname -r | cut -d'.' -f1-2)

    # 简化版本比�?    local current_major
    local current_minor
    local min_major
    local min_minor

    current_major=$(echo "${current_version}" | cut -d'.' -f1)
    current_minor=$(echo "${current_version}" | cut -d'.' -f2)
    min_major=$(echo "${min_version}" | cut -d'.' -f1)
    min_minor=$(echo "${min_version}" | cut -d'.' -f2)

    if [[ ${current_major} -gt ${min_major} ]]; then
        return 0
    elif [[ ${current_major} -eq ${min_major} ]] && [[ ${current_minor} -ge ${min_minor} ]]; then
        return 0
    fi

    return 1
}

# ==============================================================================
# 检查ZRAM模块支持
# ==============================================================================
check_zram_support() {
    # 检查内核模块是否存�?    if [[ -f /lib/modules/$(uname -r)/kernel/drivers/block/zram/zram.ko ]] || \
       [[ -f /lib/modules/$(uname -r)/updates/dkms/zram.ko ]]; then
        return 0
    fi

    # 尝试加载模块
    if modprobe zram 2>/dev/null; then
        modprobe -r zram 2>/dev/null
        return 0
    fi

    return 1
}

# ==============================================================================
# 检查systemd支持
# ==============================================================================
check_systemd() {
    check_command systemctl
}

# ==============================================================================
# 安装软件�?# ==============================================================================
install_packages() {
    local pkg_manager="${SYSTEM_INFO[package_manager]}"
    local packages=("$@")

    if [[ -z "${pkg_manager}" ]] || [[ "${pkg_manager}" == "unknown" ]]; then
        log_error "未知的包管理�?
        return 1
    fi

    log_info "安装软件�? ${packages[*]}"

    case "${pkg_manager}" in
        apt)
            apt-get update -qq > /dev/null 2>&1
            apt-get install -y "${packages[@]}" > /dev/null 2>&1
            ;;
        yum)
            yum install -y "${packages[@]}" > /dev/null 2>&1
            ;;
        dnf)
            dnf install -y "${packages[@]}" > /dev/null 2>&1
            ;;
        apk)
            apk add --no-cache "${packages[@]}" > /dev/null 2>&1
            ;;
        pacman)
            pacman -S --noconfirm "${packages[@]}" > /dev/null 2>&1
            ;;
        *)
            log_error "不支持的包管理器: ${pkg_manager}"
            return 1
            ;;
    esac

    return $?
}

# ==============================================================================
# 检查软件包是否已安�?# ==============================================================================
is_package_installed() {
    local package="$1"
    local pkg_manager="${SYSTEM_INFO[package_manager]}"

    case "${pkg_manager}" in
        apt)
            dpkg -l "${package}" 2>/dev/null | grep -q "^ii"
            ;;
        yum|dnf)
            rpm -q "${package}" &> /dev/null
            ;;
        apk)
            apk info -e "${package}" &> /dev/null
            ;;
        pacman)
            pacman -Q "${package}" &> /dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# ==============================================================================
# 获取系统启动时间
# ==============================================================================
get_uptime() {
    local uptime_seconds
    uptime_seconds=$(cat /proc/uptime | awk '{print $1}')

    local days=$((uptime_seconds / 86400))
    local hours=$(( (uptime_seconds % 86400) / 3600 ))
    local minutes=$(( (uptime_seconds % 3600) / 60 ))

    echo "${days}�?${hours}小时 ${minutes}分钟"
}

# ==============================================================================
# 获取系统架构
# ==============================================================================
get_architecture() {
    uname -m
}

# ==============================================================================
# 检查是否为容器环境
# ==============================================================================
is_container() {
    # 检查docker
    if [[ -f /.dockerenv ]]; then
        return 0
    fi

    # 检查systemd cgroup
    if [[ -d /proc/1/cgroup ]] && grep -q docker /proc/1/cgroup; then
        return 0
    fi

    return 1
}

# ==============================================================================
# 检查是否为虚拟�?# ==============================================================================
is_virtual_machine() {
    # 检查DMI信息
    if [[ -d /sys/class/dmi/id ]]; then
        local product_name
        product_name=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "")

        if [[ "${product_name}" =~ (VMware|VirtualBox|QEMU|KVM|Virtual Machine) ]]; then
            return 0
        fi
    fi

    # 检查CPU flags
    if grep -q "hypervisor" /proc/cpuinfo; then
        return 0
    fi

    return 1
}

# ==============================================================================
# 获取系统信息摘要
# ==============================================================================
get_system_summary() {
    cat <<EOF
发行�? ${SYSTEM_INFO[distro]} ${SYSTEM_INFO[version]}
架构: $(get_architecture)
内核: $(uname -r)
内存: ${SYSTEM_INFO[total_memory_mb]}MB
CPU: ${SYSTEM_INFO[cpu_cores]} 核心
包管理器: ${SYSTEM_INFO[package_manager]}
运行时间: $(get_uptime)
容器: $(is_container && echo "�? || echo "�?)
虚拟�? $(is_virtual_machine && echo "�? || echo "�?)
EOF
}