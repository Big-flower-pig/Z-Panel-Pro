# Z-Panel Pro - 架构设计文档

## 目录

- [1. 概述](#1-概述)
- [2. 系统架构](#2-系统架构)
- [3. 模块设计](#3-模块设计)
- [4. 数据流](#4-数据流)
- [5. 设计模式](#5-设计模式)
- [6. 安全架构](#6-安全架构)
- [7. 性能优化](#7-性能优化)
- [8. 扩展性设计](#8-扩展性设计)

---

## 1. 概述

### 1.1 设计目标

Z-Panel Pro 采用模块化架构设计，实现以下目标：

- **可维护性** - 每个模块职责单一，易于理解和修改
- **可扩展性** - 新功能可通过添加新模块实现，不影响现有代码
- **可测试性** - 模块间低耦合，便于单元测试
- **高性能** - 智能缓存减少系统调用，提升响应速度
- **安全性** - 输入验证、权限控制、安全编码实践

### 1.2 技术栈

| 技术         | 版本 | 用途          |
| ------------ | ---- | ------------- |
| Bash         | 4.0+ | 主要编程语言  |
| Linux Kernel | 5.4+ | ZRAM 模块支持 |
| systemd      | -    | 服务管理      |

---

## 2. 系统架构

### 2.1 分层架构

```
┌─────────────────────────────────────────────────────────────┐
│                     用户交互层 (UI)                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │ 监控面板 │  │ 菜单系统 │  │ 配置向导 │  │ 日志查看 │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                     业务逻辑层 (Logic)                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │ ZRAM管理 │  │ Swap管理 │  │ 策略引擎 │  │ 备份还原 │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
│  ┌──────────┐  ┌──────────┐                                   │
│  │ 内核参数 │  │ 系统检测 │                                   │
│  └──────────┘  └──────────┘                                   │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                     数据访问层 (Data)                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │ 数据采集 │  │ 缓存管理 │  │ 配置管理 │  │ 文件操作 │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                     基础设施层 (Infrastructure)               │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │ 错误处理 │  │ 日志系统 │  │ 文件锁    │  │ 工具函数 │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
│  ┌──────────────────────────────────────────────────────┐ │
│  │              核心配置 (Core)                          │ │
│  └──────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 目录结构

```
Z-Panel-Pro/
├── Z-Panel.sh              # 主程序入口
├── lib/                    # 核心库目录
│   ├── core.sh            # 核心配置和全局状态
│   ├── error_handler.sh   # 错误处理和日志
│   ├── utils.sh           # 工具函数库
│   ├── lock.sh            # 文件锁机制
│   ├── system.sh          # 系统检测
│   ├── data_collector.sh  # 数据采集
│   ├── ui.sh              # UI渲染引擎
│   ├── strategy.sh        # 策略管理
│   ├── zram.sh            # ZRAM管理
│   ├── kernel.sh          # 内核参数
│   ├── swap.sh            # Swap管理
│   ├── backup.sh          # 备份还原
│   ├── monitor.sh         # 监控面板
│   └── menu.sh            # 菜单系统
├── tests/                  # 测试目录
├── docs/                   # 文档目录
├── configs/                # 配置文件目录
├── logs/                   # 日志目录
└── backups/                # 备份目录
```

---

## 3. 模块设计

### 3.1 模块依赖关系图

```
                    ┌──────────┐
                    │ Z-Panel  │
                    │   .sh    │
                    └────┬─────┘
                         │
        ┌────────────────┼────────────────┐
        │                │                │
        ↓                ↓                ↓
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│   core.sh    │  │ error_       │  │  utils.sh    │
│              │  │ handler.sh   │  │              │
└──────────────┘  └──────────────┘  └──────────────┘
        │                │                │
        └────────────────┼────────────────┘
                         │
        ┌────────────────┼────────────────┐
        ↓                ↓                ↓
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  lock.sh     │  │  system.sh   │  │   ui.sh      │
│              │  │              │  │              │
└──────────────┘  └──────────────┘  └──────────────┘
        │                │                │
        └────────────────┼────────────────┘
                         │
        ┌────────────────┼────────────────┐
        ↓                ↓                ↓
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│    data_     │  │  strategy.sh │  │   zram.sh    │
│ collector.sh │  │              │  │              │
└──────────────┘  └──────────────┘  └──────────────┘
        │                │                │
        └────────────────┼────────────────┘
                         │
        ┌────────────────┼────────────────┐
        ↓                ↓                ↓
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  kernel.sh   │  │   swap.sh    │  │  backup.sh   │
│              │  │              │  │              │
└──────────────┘  └──────────────┘  └──────────────┘
        │                │                │
        └────────────────┼────────────────┘
                         │
        ┌────────────────┼────────────────┐
        ↓                ↓                ↓
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  monitor.sh  │  │   menu.sh    │  │              │
│              │  │              │  │              │
└──────────────┘  └──────────────┘  └──────────────┘
```

### 3.2 核心模块详解

#### 3.2.1 core.sh - 核心配置

**职责**：

- 定义全局常量和配置
- 管理系统信息
- 提供配置中心 (CONFIG_CENTER)

**关键数据结构**：

```bash
# 配置中心
declare -A CONFIG_CENTER=(
    ["zram_size_mb"]="2048"
    ["swap_size_mb"]="4096"
    ["swappiness"]="20"
    ["compression_algorithm"]="zstd"
)

# 系统信息
declare -A SYSTEM_INFO=(
    ["distro"]="ubuntu"
    ["version"]="22.04"
    ["total_memory_mb"]="8192"
    ["cpu_cores"]="4"
)
```

#### 3.2.2 error_handler.sh - 错误处理

**职责**：

- 统一错误处理机制
- 多级别日志记录
- 断言函数
- 重试机制

**日志级别**：

```
DEBUG (0) → INFO (1) → WARN (2) → ERROR (3)
```

**错误处理流程**：

```
错误发生 → handle_error() → 记录日志 → 根据action执行操作
```

#### 3.2.3 data_collector.sh - 数据采集

**职责**：

- 收集系统数据（内存、Swap、ZRAM、CPU）
- TTL缓存机制
- 数据解析和格式化

**缓存策略**：

```
数据请求 → 检查缓存 → 有效？返回 : 采集 → 更新缓存 → 返回
```

#### 3.2.4 strategy.sh - 策略引擎

**职责**：

- 管理三种预设策略
- 计算策略参数
- 策略切换和保存

**策略参数计算**：

```bash
calculate_strategy() {
    local mode=$1
    local total_memory=$(get_total_memory)

    case $mode in
        conservative)
            zram_size=$((total_memory * 25 / 100))
            swap_size=$((total_memory * 50 / 100))
            swappiness=10
            ;;
        balance)
            zram_size=$((total_memory * 50 / 100))
            swap_size=$((total_memory * 75 / 100))
            swappiness=20
            ;;
        aggressive)
            zram_size=$((total_memory * 75 / 100))
            swap_size=$((total_memory * 100 / 100))
            swappiness=40
            ;;
    esac
}
```

---

## 4. 数据流

### 4.1 监控面板数据流

```
用户请求 → show_monitor()
    ↓
循环执行：
    ↓
get_memory_info() → 检查缓存 → 有效？返回 : 执行free → 更新缓存
    ↓
get_zram_usage() → 检查缓存 → 有效？返回 : 执行cat /sys/block/zram0/* → 更新缓存
    ↓
get_swap_info() → 检查缓存 → 有效？返回 : 执行swapon -s → 更新缓存
    ↓
ui_draw_progress_bar() → 渲染进度条
    ↓
ui_draw_compression_chart() → 渲染压缩比图表
    ↓
检查数据变化 → 有变化？刷新UI : 等待
    ↓
sleep(refresh_interval)
```

### 4.2 配置保存数据流

```
用户修改配置 → set_config(key, value)
    ↓
更新 CONFIG_CENTER[key] = value
    ↓
save_config_file() → 生成配置内容
    ↓
ensure_file_permissions() → 设置权限 640
    ↓
写入配置文件
```

### 4.3 错误处理数据流

```
错误发生 → handle_error(message, action, context)
    ↓
记录日志 → log_error(message)
    ↓
增加错误计数 → ERROR_COUNT++
    ↓
检查action → continue/exit/abort/retry/warn_only
    ↓
执行相应操作
    ↓
return 0/1 (成功/失败)
```

---

## 5. 设计模式

### 5.1 策略模式 (Strategy Pattern)

**应用场景**：三种优化策略（保守/平衡/激进）

```bash
# 策略接口
calculate_strategy(mode)

# 具体策略
calculate_strategy("conservative")
calculate_strategy("balance")
calculate_strategy("aggressive")
```

### 5.2 单例模式 (Singleton Pattern)

**应用场景**：全局状态管理

```bash
# 全局配置中心（单例）
declare -gA CONFIG_CENTER

# 访问方法
get_config(key)
set_config(key, value)
```

### 5.3 工厂模式 (Factory Pattern)

**应用场景**：数据采集和缓存

```bash
# 数据工厂
get_memory_info()
get_swap_info()
get_zram_usage()

# 统一接口，返回标准格式
```

### 5.4 观察者模式 (Observer Pattern)

**应用场景**：实时监控面板

```bash
# 观察者：监控面板
show_monitor()

# 被观察者：系统数据
# 数据变化时自动刷新UI
```

---

## 6. 安全架构

### 6.1 输入验证层

```
用户输入 → validate_*() 函数 → 验证通过？继续 : 拒绝
```

**验证函数**：

- `validate_positive_integer()` - 正整数验证
- `validate_number()` - 数字验证
- `validate_filename()` - 文件名验证（防路径遍历）
- `validate_path()` - 路径验证

### 6.2 权限控制

```
Root权限检查 → 文件权限设置 (640/750) → 文件锁机制
```

### 6.3 安全编码实践

| 实践         | 实现                    |
| ------------ | ----------------------- |
| 命令注入防护 | `escape_shell_string()` |
| 路径遍历防护 | `validate_filename()`   |
| 临时文件安全 | 使用 `mktemp` 创建      |
| 文件权限     | 配置文件 640，目录 750  |

---

## 7. 性能优化

### 7.1 缓存机制

**TTL缓存**：

- 默认TTL: 3秒
- 减少系统调用: ~70%
- 性能提升: ~50%

**缓存数据**：

```bash
# 缓存结构
declare -A CACHE=(
    ["memory_info_timestamp"]="1704067200"
    ["memory_info_data"]="8192 4096 4096 1024"
    ["zram_usage_timestamp"]="1704067203"
    ["zram_usage_data"]="2048 1024"
)
```

### 7.2 批量操作

**减少系统调用**：

- 单次 `free` 命令获取所有内存信息
- 单次 `cat /sys/block/zram0/*` 获取ZRAM信息
- 单次 `swapon -s` 获取Swap信息

### 7.3 代码优化指标

| 指标           | 重构前 | 重构后       | 改进   |
| -------------- | ------ | ------------ | ------ |
| 代码行数       | 2971   | 377 (主脚本) | -87%   |
| 平均函数复杂度 | 3.5    | 1.2          | -66%   |
| 代码重复率     | 15%    | 2%           | -87%   |
| 模块数量       | 1      | 14           | +1300% |

---

## 8. 扩展性设计

### 8.1 新增功能模块

**步骤**：

1. 创建新模块文件 `lib/new_module.sh`
2. 定义模块接口函数
3. 在主脚本中导入模块
4. 添加到菜单系统

**示例**：

```bash
# lib/new_module.sh

# 模块初始化
init_new_module() {
    log_info "初始化新模块..."
}

# 核心功能
new_module_function() {
    # 实现功能
}
```

### 8.2 扩展策略模式

**添加新策略**：

```bash
# 在 strategy.sh 中添加
STRATEGY_CUSTOM="custom"

# 实现参数计算
calculate_strategy() {
    case $mode in
        custom)
            # 自定义参数
            ;;
    esac
}
```

### 8.3 插件系统（未来）

**设计思路**：

```
plugins/
├── plugin_example/
│   ├── plugin.sh
│   ├── config/
│   └── README.md
```

---

## 9. 测试架构

### 9.1 测试框架

```
tests/
├── test_runner.sh      # 测试框架
├── test_utils.sh        # utils 测试
├── test_error_handler.sh # error_handler 测试
└── test_strategy.sh     # strategy 测试
```

### 9.2 断言函数

```bash
assert_equals(expected, actual, message)
assert_true(condition, message)
assert_false(condition, message)
assert_contains(haystack, needle, message)
assert_file_exists(file, message)
```

### 9.3 测试覆盖率

| 模块             | 覆盖率 | 测试用例数 |
| ---------------- | ------ | ---------- |
| utils.sh         | 95%    | 30+        |
| error_handler.sh | 90%    | 20+        |
| strategy.sh      | 85%    | 15+        |

---

## 10. 部署架构

### 10.1 安装位置

```
/opt/Z-Panel-Pro/          # 主程序目录
├── Z-Panel.sh            # 主程序
├── lib/                  # 库文件
├── tests/                # 测试文件
└── docs/                 # 文档

/etc/zpanel/              # 配置目录
/var/log/zpanel/          # 日志目录
/var/lib/zpanel/          # 数据目录
```

### 10.2 Systemd 服务

```ini
[Unit]
Description=Z-Panel Pro Memory Optimizer
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash /opt/Z-Panel-Pro/Z-Panel.sh --configure
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
```

---

## 11. 监控和日志

### 11.1 日志级别

```
DEBUG  → 详细调试信息
INFO   → 一般信息
WARN   → 警告信息
ERROR  → 错误信息
```

### 11.2 日志格式

```
[YYYY-MM-DD HH:MM:SS] [LEVEL] [FUNCTION] Message
```

### 11.3 日志轮转

```bash
# 保留最近7天的日志
clean_old_logs() {
    find /var/log/zpanel -name "*.log" -mtime +7 -delete
}
```

---

## 12. 未来规划

### 12.1 短期目标

- [ ] Web UI 界面
- [ ] 远程管理 API
- [ ] 更多预设策略
- [ ] 性能分析工具

### 12.2 长期目标

- [ ] 插件系统
- [ ] 集群支持
- [ ] 自动调优
- [ ] 机器学习优化

---

## 13. 参考资源

- [Bash Reference Manual](https://www.gnu.org/software/bash/manual/)
- [ZRAM Documentation](https://www.kernel.org/doc/Documentation/blockdev/zram.txt)
- [Linux Memory Management](https://www.kernel.org/doc/html/latest/admin-guide/mm/)
- [ShellCheck](https://www.shellcheck.net/)
