#!/bin/bash
# ==============================================================================
# Z-Panel Pro V8.0 - 系统检测模块
# ==============================================================================
# @description    系统信息检测与硬件环境分析
# @version       8.0.0-Enterprise
# @author        Z-Panel Team
# @license       MIT License
# ==============================================================================

# ==============================================================================
# 系统信息存储
# ==============================================================================
declare -gA SYSTEM_INFO=(
    [distro]=""
    [distro_id]=""
    [version]=""
    [version_id]=""
    [codename]=""
    [package_manager]=""
    [package_manager_family]=""
    [total_memory_mb]=0
    [total_memory_kb]=0
    [cpu_cores]=0
    [cpu_threads]=0
    [architecture]=""
    [kernel_version]=""
    [kernel_release]=""
    [uptime]=0
    [is_container]=false
    [is_virtual]=false
    [hypervisor]=""
)

# ==============================================================================
# 系统检测主函数
# ==============================================================================
detect_system() {
    log_info "正在检测系统环境..."

    # 检测发行版
    detect_distro

    # 检测包管理器
    detect_package_manager

    # 检测硬件
    detect_hardware

    # 检测内核
    detect_kernel

    # 检测环境
    detect_environment

    # 输出系统信息
    log_system_info

    return 0
}

# ==============================================================================
# 检测发行版
# ==============================================================================
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # 从 /etc/os-release 读取信息
        source /etc/os-release

        SYSTEM_INFO[distro]="${NAME}"
        SYSTEM_INFO[distro_id]="${ID}"
        SYSTEM_INFO[version]="${VERSION}"
        SYSTEM_INFO[version_id]="${VERSION_ID:-}"
        SYSTEM_INFO[codename]="${VERSION_CODENAME:-}"

        # 转换为小写以统一处理
        SYSTEM_INFO[distro]="${ID,,}"
    elif [[ -f /etc/redhat-release ]]; then
        SYSTEM_INFO[distro]="centos"
        SYSTEM_INFO[distro_id]="centos"
        SYSTEM_INFO[version]=$(cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+' | head -1)
    elif [[ -f /etc/alpine-release ]]; then
        SYSTEM_INFO[distro]="alpine"
        SYSTEM_INFO[distro_id]="alpine"
        SYSTEM_INFO[version]=$(cat /etc/alpine-release)
    elif [[ -f /etc/debian_version ]]; then
        SYSTEM_INFO[distro]="debian"
        SYSTEM_INFO[distro_id]="debian"
        SYSTEM_INFO[version]=$(cat /etc/debian_version)
    else
        handle_error "SYSTEM_DETECT" "无法识别系统发行版" "warn_only"
        SYSTEM_INFO[distro]="unknown"
        SYSTEM_INFO[distro_id]="unknown"
    fi
}

# ==============================================================================
# 检测包管理器
# ==============================================================================
detect_package_manager() {
    # 检测包管理器
    if check_command apt-get; then
        SYSTEM_INFO[package_manager]="apt"
        SYSTEM_INFO[package_manager_family]="debian"
    elif check_command apk; then
        SYSTEM_INFO[package_manager]="apk"
        SYSTEM_INFO[package_manager_family]="alpine"
    elif check_command dnf; then
        SYSTEM_INFO[package_manager]="dnf"
        SYSTEM_INFO[package_manager_family]="rpm"
    elif check_command yum; then
        SYSTEM_INFO[package_manager]="yum"
        SYSTEM_INFO[package_manager_family]="rpm"
    elif check_command zypper; then
        SYSTEM_INFO[package_manager]="zypper"
        SYSTEM_INFO[package_manager_family]="rpm"
    elif check_command pacman; then
        SYSTEM_INFO[package_manager]="pacman"
        SYSTEM_INFO[package_manager_family]="arch"
    elif check_command emerge; then
        SYSTEM_INFO[package_manager]="emerge"
        SYSTEM_INFO[package_manager_family]="gentoo"
    else
        SYSTEM_INFO[package_manager]="unknown"
        SYSTEM_INFO[package_manager_family]="unknown"
    fi
}

# ==============================================================================
# 检测硬件信息
# ==============================================================================
detect_hardware() {
    # 检测内存
    local mem_info
    mem_info=$(free -k | awk '/^Mem:/ {print $2}')

    if [[ -n "${mem_info}" ]] && [[ ${mem_info} -gt 0 ]]; then
        SYSTEM_INFO[total_memory_kb]=${mem_info}
        SYSTEM_INFO[total_memory_mb]=$((mem_info / 1024))
    else
        handle_error "SYSTEM_DETECT" "无法检测内存信息" "warn_only"
        SYSTEM_INFO[total_memory_mb]=0
        SYSTEM_INFO[total_memory_kb]=0
    fi

    # 检测CPU核心数
    local cores
    cores=$(nproc 2>/dev/null || echo "1")
    [[ ${cores} -lt 1 ]] && cores=1
    SYSTEM_INFO[cpu_cores]=${cores}

    # 检测CPU线程数
    local threads
    threads=$(nproc --all 2>/dev/null || echo "${cores}")
    [[ ${threads} -lt ${cores} ]] && threads=${cores}
    SYSTEM_INFO[cpu_threads]=${threads}

    # 检测架构
    SYSTEM_INFO[architecture]=$(uname -m)
}

# ==============================================================================
# 检测内核信息
# ==============================================================================
detect_kernel() {
    SYSTEM_INFO[kernel_release]=$(uname -r)
    SYSTEM_INFO[kernel_version]=$(uname -v)
}

# ==============================================================================
# 检测运行环境
# ==============================================================================
detect_environment() {
    # 检测运行时间
    local uptime_seconds
    uptime_seconds=$(cat /proc/uptime 2>/dev/null | awk '{print $1}')
    [[ -n "${uptime_seconds}" ]] && SYSTEM_INFO[uptime]=$(awk "BEGIN {printf \"%.0f\", ${uptime_seconds}}")

    # 检测容器环境
    SYSTEM_INFO[is_container]=$(is_container && echo "true" || echo "false")

    # 检测虚拟机
    SYSTEM_INFO[is_virtual]=$(is_virtual_machine && echo "true" || echo "false")

    # 检测虚拟化平台
    SYSTEM_INFO[hypervisor]=$(detect_hypervisor)
}

# ==============================================================================
# 检测虚拟化平台
# ==============================================================================
detect_hypervisor() {
    # 使用systemd-detect-virt
    if command -v systemd-detect-virt &>/dev/null; then
        local virt
        virt=$(systemd-detect-virt 2>/dev/null)
        [[ "${virt}" != "none" ]] && echo "${virt}" && return 0
    fi

    # 检查DMI信息
    if [[ -d /sys/class/dmi/id ]]; then
        local product_name
        product_name=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "")

        case "${product_name}" in
            *VMware*|*VMware*) echo "vmware"; return 0 ;;
            *VirtualBox*) echo "virtualbox"; return 0 ;;
            *QEMU*|*KVM*) echo "kvm"; return 0 ;;
            *Hyper-V*) echo "hyperv"; return 0 ;;
            *Xen*) echo "xen"; return 0 ;;
        esac
    fi

    # 检查CPU flags
    if grep -q "hypervisor" /proc/cpuinfo 2>/dev/null; then
        echo "unknown"
    fi

    echo "none"
}

# ==============================================================================
# 输出系统信息
# ==============================================================================
log_system_info() {
    log_info "系统: ${SYSTEM_INFO[distro]} ${SYSTEM_INFO[version]}"
    log_info "内核: ${SYSTEM_INFO[kernel_release]}"
    log_info "架构: ${SYSTEM_INFO[architecture]}"
    log_info "内存: ${SYSTEM_INFO[total_memory_mb]}MB"
    log_info "CPU: ${SYSTEM_INFO[cpu_cores]} 核心 / ${SYSTEM_INFO[cpu_threads]} 线程"
    log_info "包管理器: ${SYSTEM_INFO[package_manager]}"
    log_info "容器: $(get_boolean_string ${SYSTEM_INFO[is_container]})"
    log_info "虚拟机: $(get_boolean_string ${SYSTEM_INFO[is_virtual]})"
    [[ "${SYSTEM_INFO[hypervisor]}" != "none" ]] && log_info "虚拟化平台: ${SYSTEM_INFO[hypervisor]}"
}

# ==============================================================================
# 获取发行版信息
# ==============================================================================
get_distro() {
    echo "${SYSTEM_INFO[distro]}"
}

get_distro_id() {
    echo "${SYSTEM_INFO[distro_id]}"
}

get_distro_name() {
    echo "${SYSTEM_INFO[distro]}"
}

# ==============================================================================
# 获取版本信息
# ==============================================================================
get_version() {
    echo "${SYSTEM_INFO[version]}"
}

get_version_id() {
    echo "${SYSTEM_INFO[version_id]}"
}

get_codename() {
    echo "${SYSTEM_INFO[codename]}"
}

# ==============================================================================
# 获取包管理器信息
# ==============================================================================
get_package_manager() {
    echo "${SYSTEM_INFO[package_manager]}"
}

get_package_manager_family() {
    echo "${SYSTEM_INFO[package_manager_family]}"
}

# ==============================================================================
# 获取内存信息
# ==============================================================================
get_total_memory() {
    echo "${SYSTEM_INFO[total_memory_mb]}"
}

get_total_memory_kb() {
    echo "${SYSTEM_INFO[total_memory_kb]}"
}

# ==============================================================================
# 获取CPU信息
# ==============================================================================
get_cpu_cores() {
    echo "${SYSTEM_INFO[cpu_cores]}"
}

get_cpu_threads() {
    echo "${SYSTEM_INFO[cpu_threads]}"
}

# ==============================================================================
# 获取架构信息
# ==============================================================================
get_architecture() {
    echo "${SYSTEM_INFO[architecture]}"
}

# ==============================================================================
# 获取内核信息
# ==============================================================================
get_kernel_release() {
    echo "${SYSTEM_INFO[kernel_release]}"
}

get_kernel_version() {
    echo "${SYSTEM_INFO[kernel_version]}"
}

# ==============================================================================
# 检查内核版本
# ==============================================================================
check_kernel_version() {
    local min_version="$1"
    local current_version="${SYSTEM_INFO[kernel_release]}"

    # 解析版本号
    local current_major
    local current_minor
    local current_patch
    local min_major
    local min_minor
    local min_patch

    IFS='.-' read -ra current_parts <<< "${current_version}"
    IFS='.-' read -ra min_parts <<< "${min_version}"

    current_major=${current_parts[0]:-0}
    current_minor=${current_parts[1]:-0}
    current_patch=${current_parts[2]:-0}

    min_major=${min_parts[0]:-0}
    min_minor=${min_parts[1]:-0}
    min_patch=${min_parts[2]:-0}

    # 比较版本
    if [[ ${current_major} -gt ${min_major} ]]; then
        return 0
    elif [[ ${current_major} -eq ${min_major} ]]; then
        if [[ ${current_minor} -gt ${min_minor} ]]; then
            return 0
        elif [[ ${current_minor} -eq ${min_minor} ]]; then
            if [[ ${current_patch} -ge ${min_patch} ]]; then
                return 0
            fi
        fi
    fi

    return 1
}

# ==============================================================================
# 检查ZRAM支持
# ==============================================================================
check_zram_support() {
    # 检查内核模块是否存在
    local kernel_modules_dir="/lib/modules/$(uname -r)"

    if [[ -f "${kernel_modules_dir}/kernel/drivers/block/zram/zram.ko" ]] || \
       [[ -f "${kernel_modules_dir}/updates/dkms/zram.ko" ]]; then
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
# 检查systemd
# ==============================================================================
check_systemd() {
    check_command systemctl && check_command journalctl
}

# ==============================================================================
# 安装软件包
# ==============================================================================
install_packages() {
    local pkg_manager="${SYSTEM_INFO[package_manager]}"
    local packages=("$@")

    if [[ -z "${pkg_manager}" ]] || [[ "${pkg_manager}" == "unknown" ]]; then
        log_error "未知的包管理器"
        return 1
    fi

    log_info "正在安装: ${packages[*]}"

    case "${pkg_manager}" in
        apt)
            apt-get update -qq > /dev/null 2>&1 || {
                log_error "apt-get update 失败"
                return 1
            }
            DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}" > /dev/null 2>&1
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
        zypper)
            zypper install -y "${packages[@]}" > /dev/null 2>&1
            ;;
        *)
            log_error "不支持的包管理器: ${pkg_manager}"
            return 1
            ;;
    esac

    return $?
}

# ==============================================================================
# 检查软件包是否已安装
# ==============================================================================
is_package_installed() {
    local package="$1"
    local pkg_manager="${SYSTEM_INFO[package_manager]}"

    case "${pkg_manager}" in
        apt)
            dpkg -l "${package}" 2>/dev/null | grep -q "^ii"
            ;;
        yum|dnf|zypper)
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
# 获取系统运行时间
# ==============================================================================
get_uptime() {
    local uptime_seconds="${SYSTEM_INFO[uptime]}"
    local days=$((uptime_seconds / 86400))
    local hours=$(( (uptime_seconds % 86400) / 3600 ))
    local minutes=$(( (uptime_seconds % 3600) / 60 ))

    if [[ ${days} -gt 0 ]]; then
        echo "${days}天${hours}小时${minutes}分钟"
    elif [[ ${hours} -gt 0 ]]; then
        echo "${hours}小时${minutes}分钟"
    else
        echo "${minutes}分钟"
    fi
}

get_uptime_seconds() {
    echo "${SYSTEM_INFO[uptime]}"
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
    if [[ -d /proc/1/cgroup ]] && grep -q -E 'docker|kubepods|lxc' /proc/1/cgroup; then
        return 0
    fi

    # 检查/proc/1/cgroup
    if [[ -f /proc/1/cgroup ]]; then
        if grep -q ':[0-9]+:pids:/docker/' /proc/1/cgroup 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

# ==============================================================================
# 检查是否为虚拟机
# ==============================================================================
is_virtual_machine() {
    # 检查DMI信息
    if [[ -d /sys/class/dmi/id ]]; then
        local product_name
        product_name=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "")

        if [[ "${product_name}" =~ (VMware|VirtualBox|QEMU|KVM|Virtual Machine|Hyper-V|Xen) ]]; then
            return 0
        fi
    fi

    # 检查CPU flags
    if grep -q "hypervisor" /proc/cpuinfo 2>/dev/null; then
        return 0
    fi

    return 1
}

# ==============================================================================
# 获取系统摘要
# ==============================================================================
get_system_summary() {
    cat <<EOF
系统: ${SYSTEM_INFO[distro]} ${SYSTEM_INFO[version]}
架构: ${SYSTEM_INFO[architecture]}
内核: ${SYSTEM_INFO[kernel_release]}
内存: ${SYSTEM_INFO[total_memory_mb]}MB
CPU: ${SYSTEM_INFO[cpu_cores]} 核心 / ${SYSTEM_INFO[cpu_threads]} 线程
包管理器: ${SYSTEM_INFO[package_manager]}
运行时间: $(get_uptime)
容器: $(get_boolean_string ${SYSTEM_INFO[is_container]})
虚拟机: $(get_boolean_string ${SYSTEM_INFO[is_virtual]})
EOF
}

# ==============================================================================
# 获取系统信息JSON
# ==============================================================================
get_system_info_json() {
    cat <<EOF
{
    "distro": {
        "id": "${SYSTEM_INFO[distro_id]}",
        "name": "${SYSTEM_INFO[distro]}",
        "version": "${SYSTEM_INFO[version]}",
        "version_id": "${SYSTEM_INFO[version_id]}",
        "codename": "${SYSTEM_INFO[codename]}"
    },
    "kernel": {
        "release": "${SYSTEM_INFO[kernel_release]}",
        "version": "${SYSTEM_INFO[kernel_version]}"
    },
    "hardware": {
        "architecture": "${SYSTEM_INFO[architecture]}",
        "cpu_cores": ${SYSTEM_INFO[cpu_cores]},
        "cpu_threads": ${SYSTEM_INFO[cpu_threads]},
        "memory_mb": ${SYSTEM_INFO[total_memory_mb]},
        "memory_kb": ${SYSTEM_INFO[total_memory_kb]}
    },
    "package_manager": {
        "name": "${SYSTEM_INFO[package_manager]}",
        "family": "${SYSTEM_INFO[package_manager_family]}"
    },
    "environment": {
        "uptime_seconds": ${SYSTEM_INFO[uptime]},
        "is_container": ${SYSTEM_INFO[is_container]},
        "is_virtual": ${SYSTEM_INFO[is_virtual]},
        "hypervisor": "${SYSTEM_INFO[hypervisor]}"
    }
}
EOF
}

# ==============================================================================
# 获取布尔值字符串
# ==============================================================================
get_boolean_string() {
    local value="$1"
    [[ "${value}" == "true" ]] && echo "是" || echo "否"
}

# ==============================================================================
# 导出函数
# ==============================================================================
export -f detect_system
export -f detect_distro
export -f detect_package_manager
export -f detect_hardware
export -f detect_kernel
export -f detect_environment
export -f detect_hypervisor
export -f log_system_info
export -f get_distro
export -f get_distro_id
export -f get_distro_name
export -f get_version
export -f get_version_id
export -f get_codename
export -f get_package_manager
export -f get_package_manager_family
export -f get_total_memory
export -f get_total_memory_kb
export -f get_cpu_cores
export -f get_cpu_threads
export -f get_architecture
export -f get_kernel_release
export -f get_kernel_version
export -f check_kernel_version
export -f check_zram_support
export -f check_systemd
export -f install_packages
export -f is_package_installed
export -f get_uptime
export -f get_uptime_seconds
export -f is_container
export -f is_virtual_machine
export -f get_system_summary
export -f get_system_info_json
export -f get_boolean_string
