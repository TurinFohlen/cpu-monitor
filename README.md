# CPU 调度延迟监控器

一个运行在 Termux 中的轻量级后台监控工具,通过周期性执行微基准测试来间接监测 Android 设备的 CPU 调度延迟和性能降低情况。

## 功能特性

- ✅ **微基准测试**: 使用轻量级 C 程序测量 CPU 性能
- ✅ **智能校准**: 交互式校准建立性能基准
- ✅ **后台监控**: 低开销持续监控,大部分时间休眠
- ✅ **及时报警**: 性能持续降低时通过系统通知提醒
- ✅ **灵活配置**: 可自定义阈值、检查间隔等参数
- ✅ **进程保护**: 使用唤醒锁和常驻通知提高存活率

## 应用场景

当 Android 系统对后台应用限制导致 CPU 降频、调度延迟增加时,此工具可以:
- 及时发现性能下降
- 提醒用户检查后台限制
- 辅助排查应用卡顿问题

## 系统要求

- **环境**: Termux (Android 终端模拟器)
- **权限**: 
  - 通知权限 (用于发送报警)
  - 建议关闭 Termux 的电池优化
- **依赖包**: 
  - `termux-api` - 发送通知和管理唤醒锁
  - `clang` - 编译 C 程序
  - `make` - 构建工具 (可选)
  - `bc` - 数学计算

## 安装步骤

### 1. 安装依赖

```bash
# 更新包列表
pkg update

# 安装必要的包
pkg install termux-api clang make bc

# 安装 Termux:API 应用(如果还没有)
# 从 F-Droid 或 GitHub Releases 下载安装
```

### 2. 授予权限

1. 打开 Android 设置 → 应用 → Termux
2. 授予"通知"权限
3. 电池 → 不限制 (建议,提高进程存活率)

### 3. 下载项目

```bash
cd ~
# 假设项目已下载到 ~/cpu-monitor
cd cpu-monitor
```

### 4. 编译

```bash
make
```

编译成功后会生成 `bench` 可执行文件。

## 使用方法

### 首次使用 - 校准

第一次使用需要进行校准,建立性能基准:

```bash
./monitor.sh calibrate
```

校准过程:
1. 程序会连续运行 10 次基准测试
2. 显示每次测试的耗时和频率
3. 计算平均值
4. 询问是否保存为基准
5. 自动计算报警阈值(默认 1.5 倍基准)

输出示例:
```
第  1 次: 123.45 μs (≈8132.25 次/秒)
第  2 次: 122.10 μs (≈8209.70 次/秒)
...
平均耗时: 122 μs,每秒可执行: 8209.70 次

是否将其作为基准耗时? (y/n):
```

### 启动监控

```bash
./monitor.sh start
```

监控程序将在后台运行,每隔一定时间(默认 60 秒)执行一次基准测试。

### 查看状态

```bash
./monitor.sh status
```

显示监控是否运行、当前配置和最近的日志。

### 停止监控

```bash
./monitor.sh stop
```

或者在收到通知时,点击"停止监控"按钮。

### 查看帮助

```bash
./monitor.sh help
```

## 配置说明

配置文件: `config` (由校准自动生成)

```bash
# 基准平均耗时(微秒)
BASELINE_US=122

# 阈值倍数(1.5 表示 150%)
THRESHOLD_MULTIPLIER=1.5

# 计算出的阈值(微秒)
THRESHOLD_US=183

# 检查间隔(秒)
CHECK_INTERVAL=60

# 连续超限次数触发报警
CONSECUTIVE_LIMIT=3
```

### 调整灵敏度

编辑 `config` 文件:

```bash
nano config  # 或使用其他编辑器
```

**调整阈值倍数**:
- `1.5` - 较灵敏,轻微性能下降即报警
- `2.0` - 较宽松,只在严重降低时报警

**调整检查间隔**:
- `30` - 频繁检查,快速发现问题,但开销稍高
- `120` - 低频检查,节省资源,适合长期监控

**调整连续次数**:
- `2` - 快速报警,可能误报
- `5` - 确认持续问题才报警,更稳定

修改后,重启监控使配置生效:
```bash
./monitor.sh stop
./monitor.sh start
```

## 工作原理

1. **微基准测试**: `bench.c` 程序执行固定次数(100万次)的整数运算,测量耗时
2. **建立基准**: 校准时测量正常状态下的平均耗时
3. **持续监控**: 定期运行 bench,比较当前耗时与阈值
4. **报警机制**: 连续超过阈值指定次数后发送通知

### 为什么不直接读取 CPU 频率?

在 Android 上,`/sys/devices/system/cpu/cpu*/cpufreq/` 等文件通常需要 root 权限。
微基准测试法不需要 root,通过实际运算耗时间接反映 CPU 性能,更直观且实用。

## 进程保护

为提高后台进程存活率,建议:

1. **启用唤醒锁**: 程序启动时自动获取 `termux-wake-lock`
2. **电池优化**: Android 设置中将 Termux 设为"不限制"
3. **持久通知**: 可以创建常驻通知(可选):
   ```bash
   termux-notification --ongoing --title "CPU监控运行中" --content "后台监控中..."
   ```

## 文件说明

```
cpu-monitor/
├── bench.c           # C语言微基准测试程序
├── bench             # 编译后的可执行文件
├── monitor.sh        # 主控脚本(校准、启动、停止)
├── config            # 配置文件(校准后生成)
├── config.example    # 配置文件示例
├── monitor.pid       # 进程PID文件(运行时生成)
├── monitor.log       # 监控日志
├── Makefile          # 编译脚本
├── test_simulate.sh  # 沙盒测试脚本
└── README.md         # 本文档
```

## 测试

项目包含自动化测试脚本,可在非 Termux 环境(普通 Linux)下测试:

```bash
chmod +x test_simulate.sh
./test_simulate.sh
```

测试内容:
- ✅ 校准模式
- ✅ 启动/停止功能
- ✅ 重复启动保护
- ✅ 正常负载(不触发报警)
- ✅ 超限负载(触发报警)

## 常见问题

### 1. 通知不显示?

**解决方法**:
- 检查是否安装了 Termux:API 应用
- 检查通知权限: 设置 → 应用 → Termux → 通知
- 测试通知: `termux-notification --title "测试" --content "内容"`

### 2. 后台进程被杀死?

**解决方法**:
- 关闭电池优化: 设置 → 应用 → Termux → 电池 → 不限制
- 不同厂商(小米、华为、OPPO等)可能有额外的后台限制,需在对应设置中放行
- 保持 Termux 在最近任务中不被清理

### 3. 误报太多?

**解决方法**:
- 增加 `THRESHOLD_MULTIPLIER` (如改为 2.0)
- 增加 `CONSECUTIVE_LIMIT` (如改为 5)
- 延长 `CHECK_INTERVAL` (如改为 120)

### 4. 漏报问题?

**解决方法**:
- 降低 `THRESHOLD_MULTIPLIER` (如改为 1.3)
- 降低 `CONSECUTIVE_LIMIT` (如改为 2)
- 缩短 `CHECK_INTERVAL` (如改为 30)
- 重新校准: `./monitor.sh calibrate`

### 5. CPU 占用率过高?

正常情况下,除了 `bench` 运行的瞬间(几十到几百毫秒),监控进程应该处于休眠状态,CPU 占用率接近 0%。

如果持续占用高:
- 检查 `CHECK_INTERVAL` 是否设置过短
- 查看 `monitor.log` 是否有异常
- 检查是否有多个实例在运行: `ps aux | grep monitor.sh`

### 6. 如何卸载?

```bash
# 停止监控
./monitor.sh stop

# 删除项目目录
cd ~
rm -rf cpu-monitor
```

## 开发与贡献

### 修改基准测试

编辑 `bench.c`,调整 `ITERATIONS` 宏:
```c
#define ITERATIONS 1000000  // 增加此值会增加测试耗时
```

重新编译:
```bash
make clean
make
```

然后重新校准:
```bash
./monitor.sh calibrate
```

### 沙盒测试

在开发机上测试(无需 Termux):
```bash
./test_simulate.sh
```

## 性能影响

- **磁盘占用**: < 100 KB
- **内存占用**: < 10 MB
- **CPU 占用**: 平均 < 0.1% (检查间隔 60s)
- **电池影响**: 可忽略不计

## 许可证

MIT License

## 技术支持

- 问题反馈: 提交 Issue
- 功能建议: 欢迎 Pull Request

## 更新日志

### v1.0.0 (2026-02-16)
- 初始版本
- 支持微基准测试
- 支持交互式校准
- 支持后台监控和通知
- 提供自动化测试

---

**注意**: 本工具仅用于监控和提醒,不能直接解决 Android 系统的后台限制问题。
要真正改善后台性能,可能需要:
- 调整系统设置
- 使用不同的 Android ROM
- Root 后修改内核参数
