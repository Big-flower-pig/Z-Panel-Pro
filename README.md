# Z-Panel Pro - 轻量级 Linux 内存优化工具

<div align="center">

![Version](https://img.shields.io/badge/version-9.0.0--Lightweight-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-Linux-lightgrey)
![Shell](https://img.shields.io/badge/shell-Bash_4.0+-yellow)

**简洁高效的 ZRAM、Swap、内核参数优化管理工具**

[安装指南](#安装) • [快速开始](#快速开始) • [使用说明](#使用说明)

</div>

---

## 📖 简介

Z-Panel Pro 是一款轻量级的 Linux 内存优化工具，专注于 ZRAM 管理、物理 Swap 优化和内核参数调优。通过简洁的 TUI 界面，您可以轻松管理系统内存，提升系统性能。

### 核心特性

- **🚀 ZRAM 管理** - 智能启用/停用 ZRAM，支持多种压缩算法
- **💾 Swap 优化** - 灵活的物理 Swap 创建和管理
- **⚙️ 内核调优** - 自动优化内核参数，提升内存管理效率
- **📊 实时监控** - 彩色进度条显示内存使用情况
- **🎯 三种策略** - 保守/平衡/激进三种预设模式
- **🎨 简洁界面** - 直观的 TUI 菜单系统
- **🔧 开机自启** - 支持 systemd 开机自动启动

---

## 📋 系统要求

| 项目     | 要求                                                     |
| -------- | -------------------------------------------------------- |
| 操作系统 | Linux (Ubuntu 20.04+, Debian 11+, CentOS 8+, Arch Linux) |
| 内核版本 | ≥ 5.4                                                    |
| Shell    | Bash 4.0+                                                |
| 内存     | 100MB+                                                   |
| 权限     | Root                                                     |

---

## 🔧 安装

### 🚀 一键安装（推荐）

最简单的安装方式，自动处理所有问题并注册全局命令：

```bash
curl -fsSL https://raw.githubusercontent.com/Big-flower-pig/Z-Panel-Pro/refs/heads/main/install.sh | bash
```

**安装完成后，使用全局命令 `z`：**

```bash
z                    # 启动面板
z -h                 # 查看帮助
z -m                 # 实时监控
z -s                 # 查看状态
z -c                 # 配置向导
```

**一键安装脚本功能：**

- ✅ 自动下载到 `/opt/Z-Panel-Pro`
- ✅ 自动转换文件格式（Windows → Unix）
- ✅ 自动设置执行权限
- ✅ 自动注册全局 `z` 命令
- ✅ 解决所有换行符和权限问题

---

### 📦 手动安装

**方式一：使用 curl 下载**

```bash
curl -fsSL https://raw.githubusercontent.com/Big-flower-pig/Z-Panel-Pro/refs/heads/main/Z-Panel.sh -o Z-Panel.sh; mkdir -p lib; cd lib; for file in core.sh error_handler.sh utils.sh lock.sh system.sh data_collector.sh ui.sh strategy.sh zram.sh kernel.sh swap.sh monitor.sh menu.sh; do curl -fsSL "https://raw.githubusercontent.com/Big-flower-pig/Z-Panel-Pro/refs/heads/main/lib/${file}" -o "${file}"; done; cd ..; sed -i 's/\r$//' Z-Panel.sh; chmod +x Z-Panel.sh; ./Z-Panel.sh
```

**方式二：使用 wget 下载**

```bash
wget -q https://raw.githubusercontent.com/Big-flower-pig/Z-Panel-Pro/refs/heads/main/Z-Panel.sh; mkdir -p lib; cd lib; for file in core.sh error_handler.sh utils.sh lock.sh system.sh data_collector.sh ui.sh strategy.sh zram.sh kernel.sh swap.sh monitor.sh menu.sh; do wget -q "https://raw.githubusercontent.com/Big-flower-pig/Z-Panel-Pro/refs/heads/main/lib/${file}"; done; cd ..; sed -i 's/\r$//' Z-Panel.sh; chmod +x Z-Panel.sh; ./Z-Panel.sh
```

**故障排除**：

如果遇到 "cannot execute: required file not found" 错误，请尝试以下方法：

```bash
# 方法1：使用 dos2unix 转换换行符
dos2unix Z-Panel.sh

# 方法2：使用 sed 转换换行符
sed -i 's/\r$//' Z-Panel.sh

# 方法3：使用 bash 直接执行（无需下载）
curl -fsSL https://raw.githubusercontent.com/Big-flower-pig/Z-Panel-Pro/refs/heads/main/Z-Panel.sh | bash
```

---

## 🚀 快速开始

### 使用全局命令 `z`（推荐）

```bash
# 启动面板
z

# 启动实时监控面板
z -m

# 显示系统状态
z -s

# 设置策略模式
z --strategy balance

# 启用开机自启
z -e
```

### 使用完整路径

```bash
# 如果是root用户，直接运行
./Z-Panel.sh

# 如果不是root用户，使用sudo
sudo ./Z-Panel.sh
```

**注意**: 所有命令都需要root权限。如果不是root用户，请在命令前添加`sudo`。

---

## 💻 使用说明

### 主菜单功能

1. **实时监控** - 查看内存、Swap、ZRAM 使用情况
2. **ZRAM管理** - 启用/停用 ZRAM，调整大小和压缩算法
3. **Swap管理** - 创建/删除物理 Swap 文件
4. **内核参数** - 优化虚拟内存相关内核参数
5. **优化策略** - 选择保守/平衡/激进模式
6. **系统信息** - 查看详细的系统状态
7. **高级设置** - 配置刷新间隔、日志级别、开机自启

### 策略模式

#### 保守模式 (Conservative)

适用于服务器环境，优先保证稳定性：

| 参数       | 值           |
| ---------- | ------------ |
| ZRAM 大小  | 总内存的 25% |
| Swap 大小  | 总内存的 50% |
| Swappiness | 10           |
| I/O 熔断   | 80%          |

#### 平衡模式 (Balance)

默认模式，性能与稳定性平衡：

| 参数       | 值           |
| ---------- | ------------ |
| ZRAM 大小  | 总内存的 50% |
| Swap 大小  | 总内存的 75% |
| Swappiness | 20           |
| I/O 熔断   | 85%          |

#### 激进模式 (Aggressive)

适用于高性能桌面环境，追求最大性能：

| 参数       | 值            |
| ---------- | ------------- |
| ZRAM 大小  | 总内存的 75%  |
| Swap 大小  | 总内存的 100% |
| Swappiness | 40            |
| I/O 熔断   | 90%           |

---

## 🏗️ 项目结构

```
Z-Panel-Pro/
├── Z-Panel.sh              # 主程序入口
├── install.sh              # 一键安装脚本
├── README.md               # 项目文档
├── lib/                    # 核心库目录
│   ├── core.sh            # 核心配置和常量
│   ├── error_handler.sh   # 错误处理和日志
│   ├── utils.sh           # 工具函数库
│   ├── lock.sh            # 文件锁机制
│   ├── system.sh          # 系统检测
│   ├── data_collector.sh   # 数据采集
│   ├── ui.sh              # UI渲染引擎
│   ├── strategy.sh        # 策略管理
│   ├── zram.sh            # ZRAM管理
│   ├── kernel.sh          # 内核参数
│   ├── swap.sh            # Swap管理
│   ├── monitor.sh         # 监控面板
│   └── menu.sh            # 菜单系统
└── etc/
    └── zpanel/
        └── lightweight.conf  # 轻量级配置文件
```

---

## 📝 配置文件

### 轻量级配置 (`etc/zpanel/lightweight.conf`)

```bash
# Z-Panel Pro 轻量级配置文件
# 版本: 9.0.0-Lightweight

# ZRAM 配置
zram_enabled=true
zram_size="2048"
compression_algorithm="lzo"

# Swap 配置
swap_enabled=true
swap_size="4096"
swap_file_path="/var/lib/zpanel/swapfile"

# 内核参数
swappiness=20
vfs_cache_pressure=50
dirty_ratio=10
dirty_background_ratio=5

# 日志配置
log_level="info"
log_file="/var/log/zpanel/zpanel.log"
log_max_size="10M"
log_max_files=5

# TUI 配置
tui_enabled=true
tui_refresh_interval=1

# 系统配置
auto_optimize=false
optimize_interval=3600
```

---

## 🛡️ 安全特性

1. **输入验证** - 所有用户输入都经过严格验证
2. **文件权限** - 配置文件权限 640，目录权限 750
3. **文件锁** - 防止并发执行导致的数据损坏
4. **安全日志** - 记录所有关键操作

---

## 📈 性能优化

- **ZRAM 压缩** - 使用 lzo/lz4/zstd 算法压缩内存
- **智能 Swap** - 根据策略自动调整 Swap 大小
- **内核优化** - 优化 vm.swappiness、vm.vfs_cache_pressure 等参数
- **实时监控** - 低开销的系统状态监控

---

## 🔄 版本历史

### v9.0.0-Lightweight (2026-01)

- ✨ 简化为轻量级工具
- ✨ 移除所有企业级功能
- ✨ 专注于 ZRAM/Swap/内核参数优化
- ✨ 简洁的 TUI 界面
- 🎯 代码量减少 60%
- ⚡ 启动速度提升 3x

### v8.1.1-Lightweight (2026-01)

- ✨ 一键安装脚本（自动处理换行符和权限）
- ✨ 全局 `z` 命令支持
- ✨ 改进安装体验

---

## 🤝 贡献指南

欢迎贡献代码！请遵循以下步骤：

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 提交 Pull Request

### 代码规范

- 遵循 ShellCheck 规范
- 保持代码简洁
- 更新相关文档

---

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件

---

## 🙏 致谢

- ZRAM 项目开发者
- Linux 内核社区
- 所有贡献者

---

## 📞 联系方式

- **项目主页**: https://github.com/Big-flower-pig/Z-Panel-Pro
- **问题反馈**: https://github.com/Big-flower-pig/Z-Panel-Pro/issues

---

<div align="center">

**如果觉得这个项目有帮助，请给它一个 ⭐️**

Made with ❤️ by Z-Panel Team

</div>
