# Z-Panel Pro

Z-Panel Pro 是一个以单文件 Bash 脚本为核心的内存与虚拟内存优化工具，主打通过 ZRAM 与内核参数的协同调优来提升内存稀缺环境下的系统稳定性与性能。

## 核心亮点

- **分级策略**（conservative / balance / aggressive）
- **智能压缩算法选择**（lz4 / lzo / zstd）
- **ZRAM 与物理 Swap 联动**、I/O 熔断保护、OOM 保护
- **持久化支持**（systemd unit）与 **动态调整**（crontab）
- **安全加固**：命令注入防护、安全文件权限、信号处理
- **性能优化**：智能缓存、减少系统调用、高效循环
- **日志管理**：自动轮转、压缩备份、清理策略
- **模块化架构**：清晰的模块划分，易于维护和扩展

## 重构亮点 (v6.0.0-Refactored)

### 架构改进

- ✅ **模块化设计**：将代码按功能划分为独立模块
  - Core - 核心配置
  - Lock - 文件锁管理
  - Icons - 图标检测
  - UI Engine - 统一渲染系统
  - Logger - 日志记录
  - Utils - 工具函数
  - Cache - 缓存管理
  - Data Collector - 数据采集
  - System - 系统检测
  - Strategy - 策略引擎
  - ZRAM Device - ZRAM设备管理
  - Kernel - 内核参数
  - Backup - 备份与回滚
  - Log Management - 日志管理
  - Dynamic - 动态调整
  - Monitor - 监控面板
  - Menu - 菜单系统
  - Shortcut - 快捷键安装
  - Signal Handler - 信号处理

### UI系统重构

- ✅ **统一的渲染引擎**：
  - `ui_top()` - 绘制顶部边框
  - `ui_bot()` - 绘制底部边框
  - `ui_line()` - 绘制分隔线
  - `ui_row()` - 绘制单行内容
  - `ui_header()` - 绘制标题
  - `ui_section()` - 绘制章节
  - `ui_menu_item()` - 绘制菜单项
  - `show_progress_bar()` - 显示进度条
  - `show_compression_chart()` - 显示压缩比图表

### 代码质量提升

- ✅ **职责单一**：每个函数只做一件事
- ✅ **配置驱动**：使用数组和常量进行批量处理
- ✅ **数据与显示分离**：采集数据与渲染UI解耦
- ✅ **统一的函数命名**：采用模块前缀命名规范
- ✅ **完整的注释**：所有模块和关键函数都有详细说明

## 安全特性

- ✅ **命令注入防护**：`safe_source()` 函数严格验证配置文件内容
- ✅ **安全临时文件**：使用 `mktemp` 创建临时文件，避免竞争条件
- ✅ **文件权限控制**：配置目录 700，配置文件 600，脚本 755
- ✅ **信号处理**：捕获 INT/TERM/QUIT 信号，确保优雅退出
- ✅ **PID 验证**：在 OOM 保护中验证 PID 有效性，防止路径遍历
- ✅ **安全 Crontab 操作**：使用临时文件进行原子更新

## 性能优化

- ✅ **智能缓存系统**：内存信息缓存 3 秒，减少 `free` 调用
- ✅ **ZRAM 状态缓存**：避免重复的 `swapon` 查询
- ✅ **一次性数据获取**：`update_cache()` 只调用两次 `free -m`
- ✅ **动态设备选择**：`get_available_zram_device()` 自动查找可用设备
- ✅ **安全的百分比计算**：`calculate_percentage()` 防止除零错误

## 日志管理

- ✅ **自动日志轮转**：日志文件超过大小限制时自动压缩备份
- ✅ **清理过期日志**：根据保留天数自动清理旧日志
- ✅ **分页日志查看**：支持大日志文件的分页浏览
- ✅ **日志配置**：可自定义日志大小和保留天数

## 快速开始

### 下载脚本

```bash
curl -O https://raw.githubusercontent.com/Big-flower-pig/Z-Panel-Pro/main/Z-Panel.sh
```

或使用 wget：

```bash
wget https://raw.githubusercontent.com/Big-flower-pig/Z-Panel-Pro/main/Z-Panel.sh
```

赋予执行权限：

```bash
chmod +x Z-Panel.sh
```

### 运行脚本

1. **语法检查**（本地）

```bash
bash -n Z-Panel.sh
```

2. **可选静态检查**（若已安装 shellcheck）

```bash
shellcheck Z-Panel.sh
```

3. **交互式运行**（需要 root）

```bash
sudo bash Z-Panel.sh
```

或使用安装后的全局快捷键：

```bash
sudo z
```

## 重要路径

### 安装/配置目录：`/opt/z-panel`

- **配置文件**：`/opt/z-panel/conf`
  - `zram.conf` - ZRAM 配置
  - `kernel.conf` - 内核参数配置
  - `strategy.conf` - 策略模式配置
  - `log.conf` - 日志管理配置

- **日志**：`/opt/z-panel/logs`
  - `zpanel_YYYYMMDD.log` - 主程序日志
  - `dynamic.log` - 动态调整日志
  - `zram-service.log` - ZRAM 服务日志

- **备份**：`/opt/z-panel/backup`
  - `backup_YYYYMMDD_HHMMSS/` - 系统配置备份

- **共享库**：`/opt/z-panel/lib`
  - `common.sh` - 共享函数库

### 持久化服务

- **启动脚本**：`/opt/z-panel/zram-start.sh`
- **动态调整脚本**：`/opt/z-panel/dynamic-adjust.sh`
- **Systemd 服务**：`/etc/systemd/system/zram.service`
- **Crontab 任务**：每 5 分钟执行动态调整

## 使用说明

### 主菜单选项

1. **一键优化** - 执行完整的优化流程（推荐）
   - 创建系统备份
   - 配置 ZRAM（含压缩算法、物理内存熔断）
   - 配置虚拟内存策略（含 I/O 熔断/OOM 保护）
   - 启用动态调整模式
   - 配置开机自启动

2. **状态监控** - 实时查看系统资源使用情况
   - RAM 使用情况
   - ZRAM 状态和压缩比
   - Swap 负载
   - 内核参数

3. **日志管理** - 查看和管理日志文件
   - 设置日志大小限制
   - 设置日志保留天数
   - 查看日志文件列表
   - 分页查看日志
   - 清理过期日志

4. **切换优化模式** - 选择不同的优化策略
   - Conservative（保守）- 优先稳定性
   - Balance（平衡）- 性能与稳定兼顾（推荐）
   - Aggressive（激进）- 最大化利用内存

5. **配置 ZRAM** - 手动配置 ZRAM 设备
   - 自动检测压缩算法
   - 自定义压缩算法
   - 查看 ZRAM 状态

6. **配置虚拟内存** - 手动配置虚拟内存参数

7. **动态调整模式** - 管理自动调整功能
   - 启用/停用动态调整
   - 查看调整日志

8. **查看系统状态** - 显示完整的系统状态信息

9. **停用 ZRAM** - 安全地停用 ZRAM 设备

10. **还原备份** - 从之前的备份还原系统配置

### 策略模式对比

| 模式         | ZRAM 大小 | Swap 大小 | Swappiness | 适用场景             |
| ------------ | --------- | --------- | ---------- | -------------------- |
| Conservative | 80%       | 100%      | 60         | 路由器/NAS，最稳定   |
| Balance      | 120%      | 150%      | 85         | 日常使用，推荐       |
| Aggressive   | 180%      | 200%      | 100        | 极度缺内存，极限榨干 |

## 模块架构

### 核心模块 (Core)

- 全局配置常量
- 颜色定义
- UI配置
- 进度条阈值
- 压缩比阈值
- 全局状态变量

### 文件锁模块 (Lock)

- `acquire_lock()` - 获取文件锁
- `release_lock()` - 释放文件锁

### 图标检测模块 (Icons)

- `detect_nerd_font()` - 检测Nerd Font支持
- `init_icons()` - 初始化图标系统

### UI引擎模块 (UI Engine)

- `ui_top()` - 绘制顶部边框
- `ui_bot()` - 绘制底部边框
- `ui_line()` - 绘制分隔线
- `ui_row()` - 绘制单行内容
- `ui_header()` - 绘制标题
- `ui_section()` - 绘制章节
- `ui_menu_item()` - 绘制菜单项
- `show_progress_bar()` - 显示进度条
- `show_compression_chart()` - 显示压缩比图表

### 日志模块 (Logger)

- `log()` - 日志记录函数
- `pause()` - 暂停等待用户输入
- `confirm()` - 确认对话框

### 工具函数模块 (Utils)

- `calculate_percentage()` - 计算百分比
- `validate_number()` - 验证数字
- `validate_positive_int()` - 验证正整数
- `check_command()` - 检查命令
- `check_dependencies()` - 检查依赖
- `safe_source()` - 安全加载配置

### 缓存管理模块 (Cache)

- `update_cache()` - 更新缓存
- `clear_cache()` - 清空缓存

### 数据采集模块 (Data Collector)

- `get_memory_info()` - 获取内存信息
- `get_swap_info()` - 获取交换分区信息
- `is_zram_enabled()` - 检查ZRAM是否启用
- `clear_zram_cache()` - 清空ZRAM缓存
- `get_zram_usage()` - 获取ZRAM使用情况
- `get_zram_status()` - 获取ZRAM状态

### 系统检测模块 (System)

- `detect_system()` - 检测系统信息
- `install_packages()` - 安装软件包

### 策略引擎模块 (Strategy)

- `load_strategy_config()` - 加载策略配置
- `save_strategy_config()` - 保存策略配置
- `calculate_strategy()` - 计算策略参数
- `validate_zram_mode()` - 验证ZRAM模式

### ZRAM设备管理模块 (ZRAM Device)

- `get_available_zram_device()` - 获取可用ZRAM设备
- `initialize_zram_device()` - 初始化ZRAM设备
- `detect_best_algorithm()` - 检测最优算法
- `get_zram_algorithm()` - 获取ZRAM算法
- `configure_zram_compression()` - 配置压缩参数
- `configure_zram_limits()` - 配置限制参数
- `enable_zram_swap()` - 启用ZRAM swap
- `prepare_zram_params()` - 准备ZRAM参数
- `save_zram_config()` - 保存ZRAM配置
- `create_zram_service()` - 创建ZRAM服务
- `start_zram_service()` - 启动ZRAM服务
- `configure_zram()` - 配置ZRAM（主函数）
- `disable_zram()` - 停用ZRAM

### 内核参数模块 (Kernel)

- `apply_io_fuse_protection()` - 应用I/O熔断保护
- `apply_oom_protection()` - 应用OOM保护
- `calculate_dynamic_swappiness()` - 计算动态swappiness
- `save_kernel_config()` - 保存内核配置
- `apply_kernel_params()` - 应用内核参数
- `configure_virtual_memory()` - 配置虚拟内存

### 备份与回滚模块 (Backup)

- `create_backup()` - 创建备份
- `restore_backup()` - 还原备份

### 日志管理模块 (Log Management)

- `load_log_config()` - 加载日志配置
- `save_log_config()` - 保存日志配置
- `rotate_log()` - 轮转日志
- `clean_old_logs()` - 清理过期日志
- `log_config_menu()` - 日志配置菜单
- `view_log_paged()` - 分页查看日志

### 动态调整模块 (Dynamic)

- `create_dynamic_adjust_script()` - 创建动态调整脚本
- `safe_crontab_add()` - 安全添加crontab
- `safe_crontab_remove()` - 安全删除crontab
- `enable_dynamic_mode()` - 启用动态调整
- `disable_dynamic_mode()` - 停用动态调整

### 监控面板模块 (Monitor)

- `cleanup_monitor()` - 清理监控资源
- `show_monitor()` - 显示实时监控
- `show_status()` - 显示系统状态

### 菜单系统模块 (Menu)

- `show_main_menu()` - 显示主菜单
- `strategy_menu()` - 策略选择菜单
- `zram_menu()` - ZRAM配置菜单
- `dynamic_menu()` - 动态调整菜单
- `quick_optimize()` - 一键优化

### 全局快捷键安装模块 (Shortcut)

- `install_global_shortcut()` - 安装全局快捷键

### 信号处理模块 (Signal Handler)

- `cleanup_on_exit()` - 退出清理

## 开发/修改建议

针对贡献者与自动化代理：

- 使用仓内 `log` 函数输出所有用户可见信息（level: info/warn/error/debug），避免直接使用 `echo`
- 全局只读常量使用 `readonly`；可变全局使用 `declare -g`
- 配置文件由脚本自动生成。若新增配置项，请同时实现 `save_*_config` 与 `load_*_config`
- 修改涉及 system 文件（`/etc/sysctl.conf`, systemd unit 等）时，请在 PR 中写明外部副作用，并建议回滚步骤（脚本内已有 `create_backup` / `restore_backup`）
- 新增函数时，请添加完整的文档注释，包括：
  - 函数功能描述
  - `@param` 参数说明
  - `@return` 返回值说明
- 遵循模块化架构，将相关功能归类到对应模块
- 使用统一的UI渲染函数，保持界面一致性

## 安全最佳实践

- 配置文件必须使用 `safe_source()` 加载，防止命令注入
- 临时文件必须使用 `mktemp` 创建，避免竞争条件
- 敏感目录权限设置为 700，配置文件权限设置为 600
- 所有用户输入必须进行验证，特别是 PID、文件路径等
- 使用 `|| true` 处理算术运算，防止脚本因错误退出
- 信号处理器确保资源正确释放

## 性能最佳实践

- 使用缓存减少系统调用
- 一次性获取所有需要的数据
- 避免在循环中执行外部命令
- 使用内置的字符串操作而非外部命令
- 合理设置缓存 TTL，平衡实时性和性能

## 验证与回归

- 在真实或容器化 Linux 环境（需内核支持 zram 模块）进行集成验证
- 推荐先在 VM 中测试自动化流程
- 验证内容包括：
  - ZRAM 正确启用和配置
  - 内核参数正确应用
  - systemd 服务正常启动
  - 动态调整正常工作
  - 日志正确记录和轮转
  - 备份和还原功能正常
  - UI渲染正常，无布局问题

## 故障排除

### ZRAM 无法启用

1. 检查内核模块：`lsmod | grep zram`
2. 手动加载模块：`modprobe zram`
3. 检查设备：`ls -la /dev/zram*`

### 配置未生效

1. 检查配置文件：`cat /opt/z-panel/conf/*.conf`
2. 查看日志：`tail -f /opt/z-panel/logs/zpanel_*.log`
3. 手动应用：`sysctl -p /opt/z-panel/conf/kernel.conf`

### 动态调整不工作

1. 检查 crontab：`crontab -l | grep dynamic-adjust`
2. 查看调整日志：`tail -f /opt/z-panel/logs/dynamic.log`
3. 手动执行：`bash /opt/z-panel/dynamic-adjust.sh`

### UI显示异常

1. 检查终端宽度：确保终端宽度至少62字符
2. 检查Nerd Font支持：脚本会自动检测并降级
3. 检查颜色支持：确保终端支持ANSI颜色

## 版本信息

- **当前版本**：6.0.0-Refactored
- **构建日期**：2026-01-17
- **支持的系统**：Ubuntu, Debian, CentOS, Alpine 等 Linux 发行版
- **最低要求**：
  - Bash 4.0+
  - Root 权限
  - Linux kernel 3.0+
  - ZRAM 内核模块支持

## 更多信息

- **主脚本**：`Z-Panel.sh`（仓库根）
- **共享库**：`lib/common.sh`
- **技术审查**：`Z-Panel_Technical_Review_Report.md`
- **GitHub 仓库**：https://github.com/Big-flower-pig/Z-Panel-Pro

## 贡献指南

欢迎提交 Issue 和 Pull Request！

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

## 许可证

本项目采用 MIT 许可证 - 详见 LICENSE 文件

## 致谢

感谢所有贡献者和使用者的支持！

---

**注意**：本工具会修改系统关键配置，请在生产环境使用前充分测试。建议在虚拟机或测试环境中先进行验证。
