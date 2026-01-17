#!/bin/bash
# ==============================================================================
# Z-Panel Pro V8.0 - 轻量级安装脚本
# ==============================================================================
# @description    适用于资源受限环境的轻量级安装
# @version       8.0.0-Enterprise
# @author        Z-Panel Team
# ==============================================================================

set -e

# ==============================================================================
# 检测是否为root用户
# ==============================================================================
if [[ $EUID -ne 0 ]]; then
    echo "错误: 此脚本需要root权限"
    echo "请使用以下命令之一运行:"
    echo "  sudo bash $0"
    echo "  或者以root用户身份运行"
    exit 1
fi

# ==============================================================================
# 配置变量
# ==============================================================================
# 检测脚本目录（支持curl下载执行）
if [[ -n "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
else
    # 从管道执行时，使用当前目录或临时目录
    SCRIPT_DIR="$(pwd)"
fi

CONFIG_DIR="${SCRIPT_DIR}/etc/zpanel"
DATA_DIR="/var/lib/zpanel"
LOG_DIR="/tmp/zpanel/logs"

# ==============================================================================
# 颜色定义
# ==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ==============================================================================
# 日志函数
# ==============================================================================
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ==============================================================================
# 系统检查
# ==============================================================================
check_system() {
    log_info "检查系统环境..."

    # 检查操作系统
    if [[ ! -f /etc/os-release ]]; then
        log_error "不支持的操作系统"
        exit 1
    fi

    source /etc/os-release
    log_success "操作系统: ${PRETTY_NAME}"

    # 检查内存
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    if [[ ${total_mem} -lt 100 ]]; then
        log_warning "内存不足，建议至少100MB"
    else
        log_success "内存: ${total_mem}MB"
    fi

    # 检查磁盘空间
    local disk_space=$(df -m / | awk 'NR==2 {print $4}')
    if [[ ${disk_space} -lt 10240 ]]; then
        log_warning "磁盘空间不足，建议至少10GB"
    else
        log_success "可用磁盘: ${disk_space}MB"
    fi

    # 检查CPU
    local cpu_cores=$(nproc)
    if [[ ${cpu_cores} -lt 1 ]]; then
        log_error "CPU核心数不足"
        exit 1
    else
        log_success "CPU核心: ${cpu_cores}"
    fi
}

# ==============================================================================
# 安装依赖
# ==============================================================================
install_dependencies() {
    log_info "安装依赖..."

    # 检测包管理器
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt-get"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
    else
        log_error "不支持的包管理器"
        exit 1
    fi

    log_info "使用包管理器: ${PKG_MANAGER}"

    # 安装基础依赖
    case "${PKG_MANAGER}" in
        apt-get)
            apt-get update -y || true
            apt-get install -y bash bc curl jq 2>/dev/null || log_warning "部分依赖安装失败"
            ;;
        yum|dnf)
            ${PKG_MANAGER} install -y bash bc curl jq 2>/dev/null || log_warning "部分依赖安装失败"
            ;;
    esac

    log_success "依赖安装完成"
}

# ==============================================================================
# 创建目录结构
# ==============================================================================
create_directories() {
    log_info "创建目录结构..."

    mkdir -p "${DATA_DIR}"
    mkdir -p "${LOG_DIR}"
    mkdir -p "${CONFIG_DIR}"
    mkdir -p "/opt/Z-Panel-Pro/data/security"
    mkdir -p "/opt/Z-Panel-Pro/logs/security"

    log_success "目录创建完成"
}

# ==============================================================================
# 复制文件
# ==============================================================================
copy_files() {
    log_info "复制文件..."

    # 复制核心库（如果存在）
    if [[ -d "${SCRIPT_DIR}/lib" ]]; then
        cp -r "${SCRIPT_DIR}/lib" "${SCRIPT_DIR}/lib.bak" 2>/dev/null || true
    fi

    # 复制轻量级配置（如果存在）
    if [[ -f "${CONFIG_DIR}/lightweight.conf" ]]; then
        cp "${CONFIG_DIR}/lightweight.conf" "${DATA_DIR}/zpanel.conf"
    else
        log_warning "未找到配置文件 ${CONFIG_DIR}/lightweight.conf，将使用默认配置"
    fi

    log_success "文件复制完成"
}

# ==============================================================================
# 配置轻量级模式
# ==============================================================================
configure_lightweight() {
    log_info "配置轻量级模式..."

    # 创建配置文件（始终使用默认配置）
    cat > "${DATA_DIR}/zpanel.conf" <<'EOF'
# Z-Panel Pro 轻量级模式配置
ZPANEL_MODE="lightweight"
ZPANEL_LOG_LEVEL="error"
ZPANEL_TUI_ENABLED=true
ZPANEL_DECISION_ENGINE_ENABLED=true
ZPANEL_DB_TYPE="memory"
ZPANEL_CACHE_SIZE="10M"
ZPANEL_MAX_MEMORY="80M"
ZPANEL_ZRAM_ENABLED=true
ZPANEL_ZRAM_SIZE="128M"
EOF

    log_success "轻量级模式配置完成"
}

# ==============================================================================
# 创建启动脚本
# ==============================================================================
create_startup_script() {
    log_info "创建启动脚本..."

    # 检测是否从仓库安装
    local zpanel_sh=""
    if [[ -f "${SCRIPT_DIR}/Z-Panel.sh" ]]; then
        zpanel_sh="${SCRIPT_DIR}/Z-Panel.sh"
    elif [[ -f "/opt/Z-Panel-Pro/Z-Panel.sh" ]]; then
        zpanel_sh="/opt/Z-Panel-Pro/Z-Panel.sh"
    else
        log_warning "未找到Z-Panel.sh，请先克隆完整仓库"
        zpanel_sh="/opt/Z-Panel-Pro/Z-Panel.sh"
    fi

    cat > "${DATA_DIR}/start.sh" <<EOF
#!/bin/bash
# Z-Panel Pro 启动脚本

# 设置配置
export ZPANEL_CONFIG="\${0%/*}/zpanel.conf"
export ZPANEL_MODE="lightweight"

# 尝试找到Z-Panel.sh
if [[ -f "${zpanel_sh}" ]]; then
    exec "${zpanel_sh}" tui
elif [[ -f "/opt/Z-Panel-Pro/Z-Panel.sh" ]]; then
    exec "/opt/Z-Panel-Pro/Z-Panel.sh" tui
else
    echo "错误: 未找到Z-Panel.sh"
    echo "请先克隆完整仓库:"
    echo "  git clone https://github.com/Big-flower-pig/Z-Panel-Pro.git /opt/Z-Panel-Pro"
    exit 1
fi
EOF

    chmod +x "${DATA_DIR}/start.sh"

    log_success "启动脚本创建完成"
}

# ==============================================================================
# 安装ZRAM
# ==============================================================================
install_zram() {
    log_info "检查ZRAM..."

    if command -v zramctl &> /dev/null; then
        log_success "ZRAM已安装"
        return 0
    fi

    log_info "安装ZRAM..."

    # 安装zram-tools
    case "${PKG_MANAGER}" in
        apt-get)
            apt-get install -y zram-tools 2>/dev/null || log_warning "ZRAM安装失败"
            ;;
        yum|dnf)
            ${PKG_MANAGER} install -y zram 2>/dev/null || log_warning "ZRAM安装失败"
            ;;
    esac

    # 配置ZRAM
    if [[ -d /etc/default ]]; then
        cat > /etc/default/zramswap <<'EOF'
# ZRAM交换配置
ALGO=lzo
PERCENT=50
PRIORITY=100
EOF
    fi

    log_success "ZRAM安装完成"
}

# ==============================================================================
# 优化系统参数
# ==============================================================================
optimize_system() {
    log_info "优化系统参数..."

    # 创建sysctl配置
    if [[ -d /etc/sysctl.d ]]; then
        cat > /etc/sysctl.d/99-zpanel-lightweight.conf <<'EOF'
# Z-Panel Pro 轻量级模式优化
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=10
vm.dirty_background_ratio=5
fs.file-max=65535
net.core.somaxconn=128
net.ipv4.tcp_max_syn_backlog=128
EOF

        # 应用sysctl配置
        sysctl -p /etc/sysctl.d/99-zpanel-lightweight.conf 2>/dev/null || true
    fi

    # 优化ulimit
    if [[ -d /etc/security/limits.d ]]; then
        cat > /etc/security/limits.d/99-zpanel.conf <<'EOF'
* soft nofile 4096
* hard nofile 8192
EOF
    fi

    log_success "系统优化完成"
}

# ==============================================================================
# 创建systemd服务
# ==============================================================================
create_systemd_service() {
    log_info "创建systemd服务..."

    # 检查systemd是否存在
    if ! command -v systemctl &> /dev/null; then
        log_warning "systemd未找到，跳过服务创建"
        return 0
    fi

    cat > /etc/systemd/system/zpanel-lightweight.service <<EOF
[Unit]
Description=Z-Panel Pro Lightweight Mode
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${DATA_DIR}
Environment="ZPANEL_CONFIG=${DATA_DIR}/zpanel.conf"
Environment="ZPANEL_MODE=lightweight"
ExecStart=${DATA_DIR}/start.sh
Restart=on-failure
RestartSec=10
LimitNOFILE=8192
LimitMEM=100M

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload 2>/dev/null || true
    systemctl enable zpanel-lightweight.service 2>/dev/null || true

    log_success "systemd服务创建完成"
}

# ==============================================================================
# 显示安装信息
# ==============================================================================
show_install_info() {
    echo ""
    echo "=========================================="
    log_success "Z-Panel Pro 轻量级模式安装完成！"
    echo "=========================================="
    echo ""
    echo "安装位置: ${DATA_DIR}"
    echo "配置文件: ${DATA_DIR}/zpanel.conf"
    echo "日志目录: ${LOG_DIR}"
    echo ""
    echo "下一步操作:"
    echo "  1. 克隆完整仓库:"
    echo "     git clone https://github.com/Big-flower-pig/Z-Panel-Pro.git /opt/Z-Panel-Pro"
    echo ""
    echo "  2. 启动程序:"
    echo "     ${DATA_DIR}/start.sh"
    echo "     或"
    echo "     /opt/Z-Panel-Pro/Z-Panel.sh"
    echo ""
    echo "服务管理:"
    echo "  systemctl start zpanel-lightweight"
    echo "  systemctl stop zpanel-lightweight"
    echo "  systemctl status zpanel-lightweight"
    echo ""
    echo "轻量级模式特性:"
    echo "  - 仅启用核心优化功能"
    echo "  - 最小化内存占用 (~80MB)"
    echo "  - 使用内存后端存储"
    echo "  - TUI界面操作"
    echo ""
    echo "=========================================="
}

# ==============================================================================
# 主函数
# ==============================================================================
main() {
    echo ""
    echo "=========================================="
    echo "Z-Panel Pro V8.0 轻量级安装"
    echo "=========================================="
    echo ""

    # 执行安装步骤
    check_system
    install_dependencies
    create_directories
    copy_files
    configure_lightweight
    create_startup_script
    install_zram
    optimize_system
    create_systemd_service

    # 显示安装信息
    show_install_info
}

# 运行主函数
main "$@"
