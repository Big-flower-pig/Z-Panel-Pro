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
- **完整的文档注释**：所有函数都有详细的参数说明

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

## 技术审查报告

详细的代码审查报告请参考：[`Z-Panel_Technical_Review_Report.md`](Z-Panel_Technical_Review_Report.md)

报告内容包括：

- 功能逻辑验证
- 代码质量与健壮性分析
- 性能优化建议
- 代码规范与可维护性评估
- 安全性审查

## 版本信息

- **当前版本**：5.0.0-Pro
- **构建日期**：2026-01-17
- **支持的系统**：Ubuntu, Debian, CentOS, Alpine 等 Linux 发行版
- **最低要求**：
  - Bash 4.0+
  - Root 权限
  - Linux kernel 3.0+
  - ZRAM 内核模块支持

## 更多信息

- **主脚本**：`Z-Panel.sh`（仓库根）
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
