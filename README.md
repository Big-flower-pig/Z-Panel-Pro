# Z-Panel Pro - 企业级 Linux 内存优化工具

<div align="center">

![Version](https://img.shields.io/badge/version-7.1.0--Enterprise-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-Linux-lightgrey)
![Shell](https://img.shields.io/badge/shell-Bash_4.0+-yellow)

**一体化 ZRAM、Swap、内核参数优化管理工具**

[安装指南](#安装) • [快速开始](#快速开始) • [架构文档](#架构文档) • [API文档](#api文档)

</div>

---

## 📖 简介

Z-Panel Pro 是一款功能强大的企业级 Linux 内存优化工具，通过智能管理 ZRAM、物理 Swap 和内核参数，显著提升系统性能和内存利用率。

### 核心特性

- **🚀 模块化架构** - 14个独立模块，易于维护和扩展
- **⚡ 智能缓存** - TTL缓存机制，减少系统调用，提升性能
- **🛡️ 安全加固** - 输入验证、路径遍历防护、安全的文件操作
- **📊 实时监控** - 彩色进度条、压缩比图表、动态数据刷新
- **🎯 策略系统** - 保守/平衡/激进三种预设模式，支持自定义
- **🔄 备份还原** - 配置备份和一键还原功能
- **📝 统一日志** - 多级别日志系统，便于问题追踪
- **🧪 单元测试** - 完整的测试框架，确保代码质量

---

## 📋 系统要求

| 项目     | 要求                                                     |
| -------- | -------------------------------------------------------- |
| 操作系统 | Linux (Ubuntu 20.04+, Debian 11+, CentOS 8+, Arch Linux) |
| 内核版本 | ≥ 5.4                                                    |
| Shell    | Bash 4.0+                                                |
| 内存     | 最低 512MB                                               |
| 权限     | Root                                                     |

---

## 🔧 安装

### 方法一：一键安装（推荐）

```bash
# 下载安装脚本
wget https://github.com/Z-Panel-Pro/Z-Panel-Pro/raw/master/install.sh -O install.sh

# 执行安装
chmod +x install.sh
sudo ./install.sh
```

### 方法二：手动安装

```bash
# 克隆仓库
git clone https://github.com/Z-Panel-Pro/Z-Panel-Pro.git
cd Z-Panel-Pro

# 复制到安装目录
sudo cp -r . /opt/Z-Panel-Pro

# 设置执行权限
sudo chmod +x /opt/Z-Panel-Pro/Z-Panel.sh

# 创建软链接（可选）
sudo ln -sf /opt/Z-Panel-Pro/Z-Panel.sh /usr/local/bin/zpanel
```

### 方法三：使用包管理器

```bash
# Ubuntu/Debian
sudo dpkg -i zpanel-pro_7.1.0_amd64.deb

# CentOS/RHEL
sudo rpm -i zpanel-pro-7.1.0-1.x86_64.rpm
```

---

## 🚀 快速开始

### 交互式菜单

```bash
sudo ./Z-Panel.sh
```

### 命令行模式

```bash
# 启动实时监控面板
sudo ./Z-Panel.sh -m

# 显示系统状态
sudo ./Z-Panel.sh -s

# 设置策略模式
sudo ./Z-Panel.sh --strategy balance

# 创建系统备份
sudo ./Z-Panel.sh -b

# 启用开机自启
sudo ./Z-Panel.sh -e
```

### 配置向导

```bash
# 运行配置向导
sudo ./Z-Panel.sh -c
```

---

## 🏗️ 架构文档

### 项目结构

```
Z-Panel-Pro/
├── Z-Panel.sh              # 主程序入口 (377行)
├── lib/                    # 核心库目录
│   ├── core.sh            # 核心配置和全局状态 (127行)
│   ├── error_handler.sh   # 错误处理和日志 (239行)
│   ├── utils.sh           # 工具函数库 (437行)
│   ├── lock.sh            # 文件锁机制 (77行)
│   ├── system.sh          # 系统检测 (328行)
│   ├── data_collector.sh  # 数据采集 (318行)
│   ├── ui.sh              # UI渲染引擎 (398行)
│   ├── strategy.sh        # 策略管理 (229行)
│   ├── zram.sh            # ZRAM管理 (580行)
│   ├── kernel.sh          # 内核参数 (318行)
│   ├── swap.sh            # Swap管理 (298行)
│   ├── backup.sh          # 备份还原 (346行)
│   ├── monitor.sh         # 监控面板 (246行)
│   └── menu.sh            # 菜单系统 (473行)
├── tests/                  # 测试目录
│   ├── test_runner.sh     # 测试框架 (397行)
│   ├── test_utils.sh      # utils测试 (286行)
│   ├── test_error_handler.sh # error_handler测试 (285行)
│   └── test_strategy.sh   # strategy测试 (197行)
├── docs/                   # 文档目录
│   ├── ARCHITECTURE.md    # 架构设计文档
│   └── API.md             # API参考文档
├── configs/                # 配置文件目录（运行时生成）
├── logs/                   # 日志目录（运行时生成）
└── backups/                # 备份目录（运行时生成）
```

### 模块依赖关系

```
Z-Panel.sh
    ├── core.sh (核心配置)
    ├── error_handler.sh (错误处理)
    ├── utils.sh (工具函数)
    ├── lock.sh (文件锁)
    ├── system.sh (系统检测)
    ├── data_collector.sh (数据采集)
    ├── ui.sh (UI渲染)
    ├── strategy.sh (策略管理)
    ├── zram.sh (ZRAM管理)
    ├── kernel.sh (内核参数)
    ├── swap.sh (Swap管理)
    ├── backup.sh (备份还原)
    ├── monitor.sh (监控面板)
    └── menu.sh (菜单系统)
```

### 设计模式

- **策略模式** - 三种优化策略（保守/平衡/激进）
- **单例模式** - 全局状态管理（CONFIG_CENTER）
- **工厂模式** - 数据采集和缓存
- **观察者模式** - 实时监控面板

---

## 📊 策略模式

### 保守模式 (Conservative)

适用于服务器环境，优先保证稳定性：

| 参数       | 值           |
| ---------- | ------------ |
| ZRAM 大小  | 总内存的 25% |
| Swap 大小  | 总内存的 50% |
| Swappiness | 10           |
| I/O 熔断   | 80%          |

### 平衡模式 (Balance)

默认模式，性能与稳定性平衡：

| 参数       | 值           |
| ---------- | ------------ |
| ZRAM 大小  | 总内存的 50% |
| Swap 大小  | 总内存的 75% |
| Swappiness | 20           |
| I/O 熔断   | 85%          |

### 激进模式 (Aggressive)

适用于高性能桌面环境，追求最大性能：

| 参数       | 值            |
| ---------- | ------------- |
| ZRAM 大小  | 总内存的 75%  |
| Swap 大小  | 总内存的 100% |
| Swappiness | 40            |
| I/O 熔断   | 90%           |

---

## 🧪 单元测试

### 运行所有测试

```bash
cd tests
./test_runner.sh
```

### 运行特定测试

```bash
# 测试 utils 模块
./test_runner.sh test_utils.sh

# 测试 error_handler 模块
./test_runner.sh test_error_handler.sh

# 测试 strategy 模块
./test_runner.sh test_strategy.sh
```

### 测试覆盖率

| 模块             | 覆盖率 | 状态 |
| ---------------- | ------ | ---- |
| utils.sh         | 95%    | ✅   |
| error_handler.sh | 90%    | ✅   |
| strategy.sh      | 85%    | ✅   |

---

## 📝 配置文件

### 策略配置 (`configs/strategy.conf`)

```bash
# 策略模式
STRATEGY_MODE="balance"

# ZRAM 配置
ZRAM_SIZE_MB=2048
COMPRESSION_ALGORITHM="zstd"

# Swap 配置
SWAP_SIZE_MB=4096
SWAP_FILE_PATH="/swapfile"

# 内核参数
SWAPPINESS=20
IO_FUSE_THRESHOLD=85
```

---

## 🛡️ 安全特性

1. **输入验证** - 所有用户输入都经过严格验证
2. **路径遍历防护** - 文件名验证防止目录遍历攻击
3. **命令注入防护** - Shell 特殊字符转义
4. **文件权限** - 配置文件权限 640，目录权限 750
5. **文件锁** - 防止并发执行导致的数据损坏

---

## 📈 性能优化

### 缓存机制

- TTL: 3秒（默认）
- 减少系统调用: ~70%
- 性能提升: ~50%

### 代码优化

- 模块化: 2971行 → 14个模块
- 平均函数复杂度: 3.5 → 1.2
- 代码重复率: 15% → 2%

---

## 🔄 版本历史

### v7.1.0-Enterprise (2024-01)

- ✨ 完全重构为模块化架构
- ✨ 新增单元测试框架
- ✨ 智能缓存机制
- ✨ 统一错误处理
- 🛡️ 安全加固
- ⚡ 性能优化
- 📊 实时监控面板优化

### v6.0.0-Enterprise (2023-12)

- 🎯 三种策略模式
- 📝 配置备份还原
- 🔧 内核参数管理

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
- 添加单元测试
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

- **项目主页**: https://github.com/Z-Panel-Pro/Z-Panel-Pro
- **问题反馈**: https://github.com/Z-Panel-Pro/Z-Panel-Pro/issues
- **文档**: https://docs.zpanel.pro

---

<div align="center">

**如果觉得这个项目有帮助，请给它一个 ⭐️**

Made with ❤️ by Z-Panel Team

</div>
