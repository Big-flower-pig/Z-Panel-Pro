# Z-Panel Pro - API 参考文档

## 目录

- [1. 核心配置 API](#1-核心配置-api)
- [2. 错误处理 API](#2-错误处理-api)
- [3. 工具函数 API](#3-工具函数-api)
- [4. 文件锁 API](#4-文件锁-api)
- [5. 系统检测 API](#5-系统检测-api)
- [6. 数据采集 API](#6-数据采集-api)
- [7. UI 渲染 API](#7-ui-渲染-api)
- [8. 策略管理 API](#8-策略管理-api)
- [9. ZRAM 管理 API](#9-zram-管理-api)
- [10. 内核参数 API](#10-内核参数-api)
- [11. Swap 管理 API](#11-swap-管理-api)
- [12. 备份还原 API](#12-备份还原-api)
- [13. 监控面板 API](#13-监控面板-api)
- [14. 菜单系统 API](#14-菜单系统-api)

---

## 1. 核心配置 API

### 1.1 常量定义

```bash
# 版本信息
readonly VERSION="7.1.0-Enterprise"
readonly MIN_KERNEL_VERSION="5.4"

# 目录路径
readonly SCRIPT_DIR="/opt/Z-Panel-Pro"
readonly LIB_DIR="${SCRIPT_DIR}/lib"
readonly CONFIG_DIR="/etc/zpanel"
readonly LOCK_DIR="/var/lock/zpanel"
readonly LOG_DIR="/var/log/zpanel"
readonly BACKUP_DIR="/var/lib/zpanel/backups"

# 文件路径
readonly LOG_FILE="${LOG_DIR}/zpanel.log"
readonly LOCK_FILE="${LOCK_DIR}/zpanel.lock"
readonly STRATEGY_CONFIG_FILE="${CONFIG_DIR}/strategy.conf"
readonly ZRAM_CONFIG_FILE="${CONFIG_DIR}/zram.conf"
readonly KERNEL_CONFIG_FILE="${CONFIG_DIR}/kernel.conf"
readonly SWAP_CONFIG_FILE="${CONFIG_DIR}/swap.conf"
readonly SYSTEMD_SERVICE_FILE="/etc/systemd/system/zpanel.service"
```

### 1.2 配置中心

#### `get_config(key)`

获取配置值

**参数**:

- `key` - 配置键名

**返回**:

- 配置值，如果不存在则返回空字符串

**示例**:

```bash
zram_size=$(get_config 'zram_size_mb')
```

#### `set_config(key, value)`

设置配置值

**参数**:

- `key` - 配置键名
- `value` - 配置值

**返回**:

- 0 (成功)

**示例**:

```bash
set_config 'zram_size_mb' '4096'
```

---

## 2. 错误处理 API

### 2.1 日志函数

#### `log_message(level, message)`

记录指定级别的日志

**参数**:

- `level` - 日志级别 (DEBUG|INFO|WARN|ERROR)
- `message` - 日志消息

**返回**:

- 0 (成功)

**示例**:

```bash
log_message "INFO" "系统启动成功"
```

#### `log_debug(message)`

记录 DEBUG 级别日志

**参数**:

- `message` - 日志消息

**示例**:

```bash
log_debug "缓存已更新"
```

#### `log_info(message)`

记录 INFO 级别日志

**参数**:

- `message` - 日志消息

**示例**:

```bash
log_info "ZRAM 已启用"
```

#### `log_warn(message)`

记录 WARN 级别日志

**参数**:

- `message` - 日志消息

**示例**:

```bash
log_warn "内存使用率超过 80%"
```

#### `log_error(message)`

记录 ERROR 级别日志

**参数**:

- `message` - 日志消息

**示例**:

```bash
log_error "ZRAM 配置失败"
```

### 2.2 错误处理

#### `handle_error(message, action, context)`

统一错误处理函数

**参数**:

- `message` - 错误消息
- `action` - 处理动作 (continue|exit|abort|retry|warn_only)
- `context` - 错误上下文（函数名）

**返回**:

- 0 (成功/继续)
- 1 (失败/退出)

**示例**:

```bash
handle_error "配置文件不存在" "exit" "load_config"
```

### 2.3 重试机制

#### `execute_with_retry(command, max_retries, delay, [context])`

执行命令并在失败时重试

**参数**:

- `command` - 要执行的命令
- `max_retries` - 最大重试次数
- `delay` - 重试间隔（秒）
- `context` - 上下文信息（可选）

**返回**:

- 命令输出（成功）
- 空字符串（失败）

**示例**:

```bash
result=$(execute_with_retry "systemctl restart zpanel" 3 1)
```

### 2.4 断言函数

#### `assert_equals(expected, actual, [message])`

断言两个值相等

**参数**:

- `expected` - 期望值
- `actual` - 实际值
- `message` - 错误消息（可选）

**示例**:

```bash
assert_equals "1" "${status}" "状态应该为 1"
```

#### `assert_not_empty(value, [message])`

断言值不为空

**参数**:

- `value` - 要检查的值
- `message` - 错误消息（可选）

**示例**:

```bash
assert_not_empty "${config}" "配置不能为空"
```

#### `assert_file_exists(file, [message])`

断言文件存在

**参数**:

- `file` - 文件路径
- `message` - 错误消息（可选）

**示例**:

```bash
assert_file_exists "${CONFIG_FILE}" "配置文件必须存在"
```

#### `assert_command_exists(command, [message])`

断言命令存在

**参数**:

- `command` - 命令名
- `message` - 错误消息（可选）

**示例**:

```bash
assert_command_exists "zramctl" "zramctl 命令必须可用"
```

---

## 3. 工具函数 API

### 3.1 验证函数

#### `validate_positive_integer(value)`

验证是否为正整数

**参数**:

- `value` - 要验证的值

**返回**:

- 0 (有效)
- 1 (无效)

**示例**:

```bash
if validate_positive_integer "${size}"; then
    echo "有效的正整数"
fi
```

#### `validate_number(value)`

验证是否为数字

**参数**:

- `value` - 要验证的值

**返回**:

- 0 (有效)
- 1 (无效)

#### `validate_float(value)`

验证是否为浮点数

**参数**:

- `value` - 要验证的值

**返回**:

- 0 (有效)
- 1 (无效)

#### `validate_filename(filename)`

验证文件名（防路径遍历）

**参数**:

- `filename` - 文件名

**返回**:

- 0 (有效)
- 1 (无效)

**示例**:

```bash
if validate_filename "${filename}"; then
    # 安全使用文件名
fi
```

### 3.2 转换函数

#### `convert_size_to_mb(size)`

将大小转换为 MB

**参数**:

- `size` - 大小（支持后缀：K/M/G）

**返回**:

- MB 值

**示例**:

```bash
mb=$(convert_size_to_mb "2G")  # 返回 2048
```

#### `convert_mb_to_human(mb)`

将 MB 转换为人类可读格式

**参数**:

- `mb` - MB 值

**返回**:

- 人类可读格式（如 "1.00 GB"）

**示例**:

```bash
human=$(convert_mb_to_human 2048)  # 返回 "2.00 GB"
```

### 3.3 计算函数

#### `calculate_percentage(value, total)`

计算百分比

**参数**:

- `value` - 值
- `total` - 总量

**返回**:

- 百分比（四舍五入）

**示例**:

```bash
percentage=$(calculate_percentage 50 100)  # 返回 50
```

#### `compare_float(a, b)`

比较两个浮点数

**参数**:

- `a` - 第一个数
- `b` - 第二个数

**返回**:

- 1 (a > b)
- 0 (a == b)
- -1 (a < b)

**示例**:

```bash
result=$(compare_float 1.5 1.3)  # 返回 1
```

### 3.4 文件操作

#### `ensure_file_permissions(file, mode)`

确保文件权限

**参数**:

- `file` - 文件路径
- `mode` - 权限模式（如 640）

**返回**:

- 0 (成功)
- 1 (失败)

**示例**:

```bash
ensure_file_permissions "${CONFIG_FILE}" 640
```

#### `safe_source(file)`

安全地加载配置文件

**参数**:

- `file` - 文件路径

**返回**:

- 0 (成功)
- 1 (失败)

**示例**:

```bash
if safe_source "${CONFIG_FILE}"; then
    echo "配置加载成功"
fi
```

---

## 4. 文件锁 API

### 4.1 锁管理

#### `acquire_lock()`

获取文件锁

**返回**:

- 0 (成功)
- 1 (失败，锁已被占用)

**示例**:

```bash
if ! acquire_lock; then
    echo "程序已在运行"
    exit 1
fi
```

#### `release_lock()`

释放文件锁

**返回**:

- 0 (成功)

**示例**:

```bash
release_lock
```

#### `is_lock_held()`

检查锁是否被占用

**返回**:

- 0 (未被占用)
- 1 (被占用)

**示例**:

```bash
if is_lock_held; then
    echo "程序正在运行"
fi
```

---

## 5. 系统检测 API

### 5.1 系统信息

#### `detect_system()`

检测系统信息（发行版、版本、包管理器等）

**返回**:

- 0 (成功)

**示例**:

```bash
detect_system
echo "发行版: $(get_distro)"
```

#### `get_distro()`

获取发行版名称

**返回**:

- 发行版名称

#### `get_version()`

获取系统版本

**返回**:

- 系统版本

#### `get_total_memory()`

获取总内存（MB）

**返回**:

- 总内存 MB

#### `get_cpu_cores()`

获取 CPU 核心数

**返回**:

- CPU 核心数

### 5.2 系统检查

#### `check_kernel_version()`

检查内核版本

**返回**:

- 0 (满足要求)
- 1 (不满足要求)

#### `check_zram_support()`

检查 ZRAM 支持

**返回**:

- 0 (支持)
- 1 (不支持)

---

## 6. 数据采集 API

### 6.1 内存信息

#### `get_memory_info(return_mb)`

获取内存信息

**参数**:

- `return_mb` - 是否返回 MB 格式（true/false）

**返回**:

- "total used available buff_cache" 格式的字符串

**示例**:

```bash
read -r total used avail cache <<< "$(get_memory_info true)"
```

#### `get_memory_usage()`

获取内存使用百分比

**返回**:

- 使用百分比

### 6.2 Swap 信息

#### `get_swap_info(return_mb)`

获取 Swap 信息

**参数**:

- `return_mb` - 是否返回 MB 格式（true/false）

**返回**:

- "total used" 格式的字符串

**示例**:

```bash
read -r total used <<< "$(get_swap_info true)"
```

### 6.3 ZRAM 信息

#### `is_zram_enabled()`

检查 ZRAM 是否启用

**返回**:

- 0 (启用)
- 1 (未启用)

#### `get_zram_usage()`

获取 ZRAM 使用情况

**返回**:

- "total used" 格式的字符串

#### `get_zram_compression_ratio()`

获取 ZRAM 压缩比

**返回**:

- 压缩比（如 "2.5"）

### 6.4 缓存管理

#### `clear_cache()`

清除所有缓存

**返回**:

- 0 (成功)

---

## 7. UI 渲染 API

### 7.1 绘图函数

#### `ui_draw_header(title)`

绘制标题

**参数**:

- `title` - 标题文本

**示例**:

```bash
ui_draw_header "Z-Panel Pro"
```

#### `ui_draw_line()`

绘制分隔线

#### `ui_draw_section(title)`

绘制区块标题

**参数**:

- `title` - 区块标题

#### `ui_draw_row(text)`

绘制一行文本

**参数**:

- `text` - 文本内容

#### `ui_draw_progress_bar(value, max, width, [label])`

绘制进度条

**参数**:

- `value` - 当前值
- `max` - 最大值
- `width` - 进度条宽度
- `label` - 标签（可选）

**示例**:

```bash
ui_draw_progress_bar 50 100 40 "内存使用"
```

#### `ui_draw_compression_chart(ratio, width)`

绘制压缩比图表

**参数**:

- `ratio` - 压缩比
- `width` - 图表宽度

**示例**:

```bash
ui_draw_compression_chart 2.5 40
```

### 7.2 交互函数

#### `ui_confirm(message)`

确认对话框

**参数**:

- `message` - 确认消息

**返回**:

- 0 (确认)
- 1 (取消)

**示例**:

```bash
if ui_confirm "确定要删除吗？"; then
    # 执行删除
fi
```

#### `ui_pause([message])`

暂停等待用户输入

**参数**:

- `message` - 提示消息（可选）

**示例**:

```bash
ui_pause "按任意键继续..."
```

#### `ui_input([prompt, default])`

输入对话框

**参数**:

- `prompt` - 提示信息（可选）
- `default` - 默认值（可选）

**返回**:

- 用户输入

**示例**:

```bash
size=$(ui_input "请输入ZRAM大小(MB)" "2048")
```

### 7.3 菜单函数

#### `ui_select_menu(title, options...)`

单选菜单

**参数**:

- `title` - 菜单标题
- `options...` - 选项列表

**返回**:

- 选中的选项

**示例**:

```bash
selected=$(ui_select_menu "选择压缩算法" "lz4" "lzo" "zstd")
```

#### `ui_multi_select_menu(title, options...)`

多选菜单

**参数**:

- `title` - 菜单标题
- `options...` - 选项列表

**返回**:

- 选中的选项（空格分隔）

**示例**:

```bash
selected=$(ui_multi_select_menu "选择功能" "ZRAM" "Swap" "Kernel")
```

---

## 8. 策略管理 API

### 8.1 策略常量

```bash
readonly STRATEGY_CONSERVATIVE="conservative"
readonly STRATEGY_BALANCE="balance"
readonly STRATEGY_AGGRESSIVE="aggressive"
```

### 8.2 策略操作

#### `validate_strategy_mode(mode)`

验证策略模式

**参数**:

- `mode` - 策略模式

**返回**:

- 0 (有效)
- 1 (无效)

#### `calculate_strategy(mode)`

计算策略参数

**参数**:

- `mode` - 策略模式

**返回**:

- 策略参数（JSON 格式）

**示例**:

```bash
params=$(calculate_strategy "balance")
```

#### `set_strategy_mode(mode)`

设置策略模式

**参数**:

- `mode` - 策略模式

**返回**:

- 0 (成功)

#### `get_strategy_mode()`

获取当前策略模式

**返回**:

- 策略模式

#### `get_strategy_description(mode)`

获取策略描述

**参数**:

- `mode` - 策略模式

**返回**:

- 策略描述

---

## 9. ZRAM 管理 API

### 9.1 ZRAM 配置

#### `configure_zram()`

配置 ZRAM（主函数）

**返回**:

- 0 (成功)
- 1 (失败)

**示例**:

```bash
if configure_zram; then
    echo "ZRAM 配置成功"
fi
```

#### `disable_zram()`

禁用 ZRAM

**返回**:

- 0 (成功)
- 1 (失败)

#### `get_zram_algorithm()`

获取当前压缩算法

**返回**:

- 压缩算法名称

#### `configure_zram_compression(algorithm)`

配置压缩算法

**参数**:

- `algorithm` - 压缩算法（lz4/lzo/zstd）

**返回**:

- 0 (成功)
- 1 (失败)

### 9.2 ZRAM 设备

#### `get_available_zram_device()`

获取可用的 ZRAM 设备

**返回**:

- 设备路径（如 /dev/zram0）

---

## 10. 内核参数 API

### 10.1 虚拟内存配置

#### `configure_virtual_memory()`

配置虚拟内存参数（主函数）

**返回**:

- 0 (成功)
- 1 (失败)

**示例**:

```bash
configure_virtual_memory
```

### 10.2 内核参数

#### `get_kernel_param(param)`

获取内核参数

**参数**:

- `param` - 参数名

**返回**:

- 参数值

**示例**:

```bash
swappiness=$(get_kernel_param "vm.swappiness")
```

#### `get_swappiness()`

获取 swappiness 值

**返回**:

- swappiness 值

### 10.3 保护机制

#### `apply_io_fuse_protection()`

应用 I/O 熔断保护

**返回**:

- 0 (成功)

#### `apply_oom_protection()`

应用 OOM 保护

**返回**:

- 0 (成功)

---

## 11. Swap 管理 API

### 11.1 Swap 配置

#### `configure_physical_swap([size_mb])`

配置物理 Swap

**参数**:

- `size_mb` - Swap 大小（MB，可选）

**返回**:

- 0 (成功)
- 1 (失败)

**示例**:

```bash
configure_physical_swap 4096
```

#### `disable_swap_file()`

禁用物理 Swap

**返回**:

- 0 (成功)
- 1 (失败)

### 11.2 Swap 信息

#### `get_swap_file_info()`

获取 Swap 文件信息

**返回**:

- Swap 文件信息

#### `is_swap_file_enabled()`

检查 Swap 文件是否启用

**返回**:

- 0 (启用)
- 1 (未启用)

---

## 12. 备份还原 API

### 12.1 备份操作

#### `create_backup()`

创建系统备份

**返回**:

- 备份 ID（成功）
- 空字符串（失败）

**示例**:

```bash
backup_id=$(create_backup)
```

#### `list_backups()`

列出所有备份

**返回**:

- 备份列表（每行一个）

#### `delete_backup(backup_id)`

删除备份

**参数**:

- `backup_id` - 备份 ID

**返回**:

- 0 (成功)
- 1 (失败)

### 12.2 还原操作

#### `restore_backup(backup_id)`

还原备份

**参数**:

- `backup_id` - 备份 ID

**返回**:

- 0 (成功)
- 1 (失败)

**示例**:

```bash
restore_backup "20240117_120000"
```

### 12.3 备份清理

#### `clean_old_backups(days)`

清理旧备份

**参数**:

- `days` - 保留天数

**返回**:

- 0 (成功)
- 1 (失败)

**示例**:

```bash
clean_old_backups 7
```

---

## 13. 监控面板 API

### 13.1 监控显示

#### `show_monitor()`

显示实时监控面板

**返回**:

- 无（持续运行）

**示例**:

```bash
show_monitor
```

#### `show_status()`

显示系统状态

**返回**:

- 无

**示例**:

```bash
show_status
```

---

## 14. 菜单系统 API

### 14.1 菜单操作

#### `show_main_menu()`

显示主菜单

**返回**:

- 无

#### `main_menu()`

主菜单入口（交互式）

**返回**:

- 无（持续运行直到退出）

**示例**:

```bash
main_menu
```

### 14.2 子菜单

#### `handle_zram_management()`

处理 ZRAM 管理菜单

#### `handle_swap_management()`

处理 Swap 管理菜单

#### `handle_strategy_management()`

处理策略管理菜单

---

## 15. 服务管理 API

### 15.1 服务操作

#### `is_service_installed()`

检查服务是否已安装

**返回**:

- 0 (已安装)
- 1 (未安装)

#### `enable_autostart()`

启用开机自启

**返回**:

- 0 (成功)

#### `disable_autostart()`

禁用开机自启

**返回**:

- 0 (成功)

---

## 附录 A: 错误代码

| 代码 | 含义       |
| ---- | ---------- |
| 0    | 成功       |
| 1    | 一般错误   |
| 2    | 权限不足   |
| 3    | 文件不存在 |
| 4    | 无效参数   |
| 5    | 系统不支持 |
| 6    | 配置错误   |
| 7    | 操作失败   |

---

## 附录 B: 配置文件格式

### strategy.conf

```bash
# 策略配置
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

## 附录 C: 日志格式

```
[2024-01-17 16:00:00] [INFO] [main] 系统启动成功
[2024-01-17 16:00:01] [DEBUG] [get_memory_info] 缓存已更新
[2024-01-17 16:00:02] [WARN] [monitor] 内存使用率超过 80%
[2024-01-17 16:00:03] [ERROR] [configure_zram] ZRAM 配置失败
```

---

**最后更新**: 2024-01-17
**文档版本**: 1.0.0
