#!/bin/bash
# ==============================================================================
# Z-Panel Pro 一键安装脚本
# ==============================================================================
# 用法: curl -fsSL https://raw.githubusercontent.com/Big-flower-pig/Z-Panel-Pro/refs/heads/main/install.sh | bash
# ==============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    log_error "需要root权限，请使用: sudo bash $0"
    exit 1
fi

log_info "开始安装 Z-Panel Pro..."

# 安装目录
INSTALL_DIR="/opt/Z-Panel-Pro"
BIN_DIR="/usr/local/bin"

# 清理旧安装
if [[ -d "${INSTALL_DIR}" ]]; then
    log_info "清理旧安装..."
    rm -rf "${INSTALL_DIR}"
fi

# 克隆仓库
log_info "下载 Z-Panel Pro..."
git clone https://github.com/Big-flower-pig/Z-Panel-Pro.git "${INSTALL_DIR}"

# 转换所有脚本文件的换行符
log_info "转换文件格式..."
find "${INSTALL_DIR}" -type f -name "*.sh" -exec sed -i 's/\r$//' {} \;

# 设置执行权限
log_info "设置执行权限..."
chmod +x "${INSTALL_DIR}/Z-Panel.sh"
find "${INSTALL_DIR}/lib" -type f -name "*.sh" -exec chmod +x {} \;
find "${INSTALL_DIR}/bin" -type f -name "*.sh" -exec chmod +x {} \;

# 创建全局命令 z
log_info "注册全局命令 z..."
cat > "${BIN_DIR}/z" <<'EOF'
#!/bin/bash
# Z-Panel Pro 全局命令

if [[ -f "/opt/Z-Panel-Pro/Z-Panel.sh" ]]; then
    exec /opt/Z-Panel-Pro/Z-Panel.sh "$@"
else
    echo "错误: 未找到 Z-Panel Pro 安装"
    echo "请运行: curl -fsSL https://raw.githubusercontent.com/Big-flower-pig/Z-Panel-Pro/refs/heads/main/install.sh | bash"
    exit 1
fi
EOF

chmod +x "${BIN_DIR}/z"

# 显示安装信息
echo ""
echo "=========================================="
log_success "Z-Panel Pro 安装完成！"
echo "=========================================="
echo ""
echo "使用方法:"
echo "  z                    # 启动面板"
echo "  z -h                 # 查看帮助"
echo "  z -m                 # 实时监控"
echo "  z -s                 # 查看状态"
echo "  z -c                 # 配置向导"
echo ""
echo "安装位置: ${INSTALL_DIR}"
echo "全局命令: z"
echo ""
echo "=========================================="
