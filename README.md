# Z-Panel Pro - Linux 内存优化工具

<div align="center">

![Version](https://img.shields.io/badge/version-9.0.0--Lightweight-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-Linux-lightgrey)
![Shell](https://img.shields.io/badge/shell-Bash_4.0+-yellow)

** ZRAM、Swap、内核参数优化管理工具 V9.0.0 轻量版**

</div>

---

## 📖 简介

Z-Panel Pro 是一款专注于 Linux 内存优化的工具，提供 ZRAM 管理、物理 Swap 优化和内核参数调优功能。通过智能化的优化策略和完整的性能监控，轻松管理系统内存，提升运行效率。

---

## ✨ 核心特性

- **🚀 一键智能优化** - 自动检测系统环境，智能选择最优策略
- **🎯 自适应策略** - 基于内存、ZRAM、Swap、负载多维度动态调整
- **💾 ZRAM 管理** - 支持 lzo/lz4/zstd 压缩算法，动态大小调整
- **🔄 Swap 优化** - 智能创建物理 Swap，自动设置优先级
- **⚙️ 内核调优** - 自动优化 vm.swappiness、vm.vfs_cache_pressure 等参数
- **📊 实时监控** - 彩色进度条，实时显示内存、Swap、ZRAM 使用情况
- **🔒 审计日志** - 完整的操作审计和安全追踪
- **⚡ 优化快照** - 支持优化前状态捕获和回滚

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

```bash
curl -fsSL https://raw.githubusercontent.com/Big-flower-pig/Z-Panel-Pro/refs/heads/main/install.sh | bash
```

安装完成后使用全局命令 `z`：

```bash
z                    # 启动面板
z --optimize         # 一键智能优化
z -h                 # 查看帮助
z -m                 # 实时监控
z -s                 # 查看状态
```

### 📦 手动安装

**使用 curl：**

```bash
curl -fsSL https://raw.githubusercontent.com/Big-flower-pig/Z-Panel-Pro/refs/heads/main/Z-Panel.sh -o Z-Panel.sh; mkdir -p lib; cd lib; for file in core.sh error_handler.sh utils.sh lock.sh system.sh data_collector.sh ui.sh strategy.sh zram.sh kernel.sh swap.sh monitor.sh menu.sh performance_monitor.sh audit_log.sh; do curl -fsSL "https://raw.githubusercontent.com/Big-flower-pig/Z-Panel-Pro/refs/heads/main/lib/${file}" -o "${file}"; done; cd ..; sed -i 's/\r$//' Z-Panel.sh; chmod +x Z-Panel.sh; ./Z-Panel.sh
```

**使用 wget：**

```bash
wget -q https://raw.githubusercontent.com/Big-flower-pig/Z-Panel-Pro/refs/heads/main/Z-Panel.sh; mkdir -p lib; cd lib; for file in core.sh error_handler.sh utils.sh lock.sh system.sh data_collector.sh ui.sh strategy.sh zram.sh kernel.sh swap.sh monitor.sh menu.sh performance_monitor.sh audit_log.sh; do wget -q "https://raw.githubusercontent.com/Big-flower-pig/Z-Panel-Pro/refs/heads/main/lib/${file}"; done; cd ..; sed -i 's/\r$//' Z-Panel.sh; chmod +x Z-Panel.sh; ./Z-Panel.sh
```

**故障排除：**

如果遇到换行符问题：

```bash
sed -i 's/\r$//' Z-Panel.sh
# 或
dos2unix Z-Panel.sh
```

---

## 🚀 快速开始

### 使用全局命令 `z`

```bash
z --optimize         # 一键智能优化
z                    # 启动面板
z -m                 # 实时监控
z -s                 # 查看状态
z --performance      # 查看性能报告
z --audit            # 查看审计日志
z --adaptive         # 查看自适应策略分析
z --strategy balance # 设置策略模式
z -e                 # 启用开机自启
```

### 使用完整路径

```bash
./Z-Panel.sh         # root用户
sudo ./Z-Panel.sh    # 非root用户
```

---

## 💻 使用说明

### 主菜单功能

1. **🚀 一键智能优化** - 自动检测并优化所有参数
2. **📊 实时监控** - 查看内存、Swap、ZRAM 使用情况
3. **💾 ZRAM管理** - 启用/停用 ZRAM，调整大小和压缩算法
4. **🔄 Swap管理** - 创建/删除物理 Swap 文件
5. **⚙️ 内核参数** - 优化虚拟内存相关内核参数
6. **🎯 优化策略** - 选择保守/平衡/激进模式，或使用自适应策略
7. **📈 性能报告** - 查看性能报告、分析瓶颈、查看缓存统计
8. **🔒 审计日志** - 查看审计日志、审计统计、导出日志
9. **ℹ️ 系统信息** - 查看详细的系统状态
10. **🔧 高级设置** - 配置刷新间隔、日志级别、开机自启

### 策略模式

| 策略 | ZRAM大小 | Swap大小 | Swappiness | 适用场景   |
| ---- | -------- | -------- | ---------- | ---------- |
| 保守 | 80%      | 100%     | 60         | 服务器环境 |
| 平衡 | 120%     | 150%     | 85         | 默认模式   |
| 激进 | 180%     | 200%     | 100        | 高性能桌面 |

---

## 🏗️ 项目结构

```
Z-Panel-Pro/
├── Z-Panel.sh                 # 主程序入口
├── install.sh                 # 一键安装脚本
├── README.md                  # 项目文档
├── lib/                      # 核心库目录
│   ├── core.sh               # 核心配置和常量
│   ├── error_handler.sh      # 错误处理和日志
│   ├── utils.sh              # 工具函数库
│   ├── lock.sh               # 文件锁机制
│   ├── system.sh             # 系统检测
│   ├── data_collector.sh      # 数据采集和缓存统计
│   ├── ui.sh                 # UI渲染引擎
│   ├── strategy.sh           # 策略管理和自适应引擎
│   ├── zram.sh               # ZRAM管理
│   ├── kernel.sh             # 内核参数
│   ├── swap.sh               # Swap管理
│   ├── monitor.sh            # 监控面板
│   ├── menu.sh               # 菜单系统
│   ├── performance_monitor.sh # 性能监控系统
│   └── audit_log.sh          # 审计日志系统
└── etc/
    └── zpanel/
        └── lightweight.conf   # 轻量级配置文件
```

---

## 📝 配置文件

配置文件位置：`etc/zpanel/lightweight.conf`

```bash
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

# 日志配置
log_level="info"
log_file="/var/log/zpanel/zpanel.log"

# 性能监控配置
performance_monitoring=true
cache_stats_enabled=true

# 审计日志配置
audit_enabled=true
audit_log_file="/var/log/zpanel/audit.log"
```

---

## 🤝 贡献指南

欢迎贡献代码！

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 提交 Pull Request

---

## 📄 许可证

本项目采用 MIT 许可证

---

## 📞 联系方式

- **项目主页**: https://github.com/Big-flower-pig/Z-Panel-Pro
- **问题反馈**: https://github.com/Big-flower-pig/Z-Panel-Pro/issues

---

<div align="center">

**如果觉得这个项目有帮助，请给它一个 ⭐️**

Made with ❤️ by Z-Panel Team

</div>
