# Z-Panel-Pro

Z-Panel Pro 是一个以单文件 Bash 脚本为核心的内存与虚拟内存优化工具，主打通过 ZRAM 与内核参数的协同调优来提升内存稀缺环境下的系统稳定性与性能。

核心亮点

- 分级策略（conservative / balance / aggressive）
- 智能压缩算法选择（lz4 / lzo / zstd）
- ZRAM 与物理 Swap 联动、I/O 熔断保护、OOM 保护
- 支持持久化（systemd unit）与动态调整（crontab）

快速开始（在 Linux 主机上，以 root 运行）

1. 语法检查（本地）

```bash
bash -n Z-Panel.sh
```

2. 可选静态检查（若已安装 shellcheck）

```bash
shellcheck Z-Panel.sh
```

3. 交互式运行（需要 root）

```bash
sudo bash Z-Panel.sh
```

重要路径

- 安装/配置目录：`/opt/z-panel`
  - 配置文件：`/opt/z-panel/conf`（包括 `zram.conf`, `kernel.conf`, `strategy.conf`）
  - 日志：`/opt/z-panel/logs`（包含 `zpanel_YYYYMMDD.log`, `dynamic.log`）
  - 备份：`/opt/z-panel/backup`

- 持久化服务：脚本会在 `/opt/z-panel/zram-start.sh` 生成启动脚本，并可能在 `/etc/systemd/system/zram.service` 中创建 systemd unit。

开发/修改建议（针对贡献者与自动化代理）

- 使用仓内 `log` 函数输出所有用户可见信息（level: info/warn/error/debug），避免直接使用 `echo`。
- 全局只读常量使用 `readonly`；可变全局使用 `declare -g`。
- 配置文件由脚本自动生成。若新增配置项，请同时实现 `save_*_config` 与 `load_*_config`。
- 修改涉及 system 文件（`/etc/sysctl.conf`, systemd unit 等）时，请在 PR 中写明外部副作用，并建议回滚步骤（脚本内已有 `create_backup` / `restore_backup`）。


