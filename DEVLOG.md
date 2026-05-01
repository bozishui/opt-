# WindowsOptimizerPlus 开发日志

## 2026-05-01T23:10:38Z — 演示型 GUI（WPF + XAML + PowerShell）

### 目标
把现有 PS 后端套上一层"软件级"GUI，但**不接通**任何 `Apply-*` 真实修改逻辑——只验证交互、布局、信息架构。

### 技术栈
- **前端**：WPF (XAML) — 由 PowerShell 通过 `[XamlReader]::Load` 加载
- **后端**：现有 PS 模块 dot-source 加载（仅 `Get-*` 用于真实数据）
- **零外部依赖**：双击 `Show-OptimizerGUI.ps1` 即跑（PS 5.1+ 自带 WPF 支持）

### 新增文件

| 文件 | 用途 |
|------|------|
| `Resources/MainWindow.xaml` | 主窗口 XAML（约 320 行）：左侧栏导航 + 7 页内容区 + 顶部演示横幅 + 底部状态栏 |
| `Show-OptimizerGUI.ps1` | 启动入口（约 240 行）：加载 XAML、注入真实数据、绑定事件、统一演示提示 |

### UI 信息架构

| 页面 | 内容 |
|------|------|
| 仪表盘 | OS/CPU/RAM/磁盘 实时卡片 + 健康评分 + 一键扫描进度条 + 模块加载状态 |
| 系统优化 | `Get-SystemOptimizations` → 复选框列表 + 全选/清空/应用 |
| 网络优化 | `Get-NetworkOptimizations` → 同上 |
| 游戏优化 | `Get-GamingOptimizations` → 同上 |
| 临时清理 | `Get-CleanOptions` → 列表 + 预估可清理空间 + 立即清理 |
| 设置 | 还原点/备份/日志/配置导入导出 |
| 关于 | 版本信息 + 技术栈 |

### 演示模式安全保证
所有"应用"类按钮统一绑定到 `Show-DemoToast`，只弹 MessageBox 显示"演示模式未真正执行"。
**`Apply-*Optimization` 函数被代码层面禁止调用**（GUI launcher 不导出/不引用）。

### 验证结果
- PS 语法解析：OK
- XAML 解析：OK
- `Show-OptimizerGUI.ps1` 后台启动 4 秒后进程仍存活 → 窗口成功显示

### 后续待办（GUI → 真后端）
1. 修复 `Apply-*` 对 `$Script:TestModeActive` 的尊重（让 -TestMode 真"只读"）
2. 把 GUI 的 Apply 按钮接到真实模块（先在 TestMode 下 dry-run）
3. 长任务（清理、扫描）改用 PowerShell Runspace 异步执行，避免阻塞 UI 线程
4. 状态栏接 Write-Log 流，做实时滚动
5. 装饰：自定义图标、应用程序清单、PS2EXE 或 C# 重写以打包成单 exe

## 2026-05-01T22:50:56Z — 让 PowerShell 项目跑起来 (bootstrap fix)

### 出发点
旧版 `WindowsOptimizerPlus.ps1 v2.0.0` 框架完整但**整体跑不起来**，存在 4 处阻塞性问题。

### 修复清单

| # | 问题 | 修复 |
|---|------|------|
| 1 | 主脚本 require `Service.Optimizer` 模块，但模块不存在 | 从 `$requiredModules` 列表中移除（其实际函数 `Get-OptimizableServices` 已在 `System.Optimizer.ps1` 中） |
| 2 | `Modules/RunOptimizer.ps1.ps1` 文件名带双扩展名 | 重命名为 `RunOptimizer.ps1` |
| 3 | `Modules/UI.Functions.ps1` 是 0 字节空文件，主脚本调用的 `Show-MainMenu` 不存在 | 新建该模块，提供 `Show-Header` / `Show-MainMenu` / `Show-OptimizationSubMenu` / `Show-TempCleanMenu` / `Show-ConfigMenu` / `Show-SystemInfoMenu` |
| 4 | `WindowsOptimizerPlus.ps1` / `Config.Manager.ps1` / `Temp.Cleaner.ps1` / `RunOptimizer.ps1` 是无 BOM 的 UTF-8，PowerShell 5.1 默认按 GBK 解析中文导致语法错乱 | 全部转换为 **UTF-8 with BOM**（含中文的 PS1 文件唯一稳定方案） |
| 5 | 各核心模块末尾有 `Export-ModuleMember`，但主脚本以 dot-source 方式加载，会触发"can only be called from inside a module"终止性错误，让 catch 误把模块标记为加载失败 | 在 `Import-OptimizationModule` 里 dot-source 期间用 `function global:Export-ModuleMember { }` 临时覆盖该 cmdlet，加载完毕再 `Remove-Item function:\Export-ModuleMember` 还原 |

### 验证结果（非管理员上下文，模拟 bootstrap）

执行 `test-load.ps1` 输出：

```
==> Loading System.Optimizer       OK
==> Loading Network.Optimizer      OK
==> Loading Gaming.Optimizer       OK
==> Loading Temp.Cleaner           OK
==> Loading Config.Manager         OK
==> Loading UI.Functions           OK

15/15 函数可见
Get-SystemOptimizations: 10 item(s)
Get-NetworkOptimizations: 10 item(s)
Get-GamingOptimizations: 10 item(s)
Get-CleanOptions: 14 item(s)

RESULT: load fails = 0, missing functions = 0
```

### 已知遗留 / 后续工作

- **3 个核心模块仍是 UTF-16 LE BOM 编码**（System / Network / Gaming），暂未统一为 UTF-8 BOM 以避免引入风险；后续 GUI 化时再统一。
- `Service.Optimizer` 模块原计划独立，但服务相关函数实际散落在 `System.Optimizer.ps1`。可考虑后续重构拆分。
- `Apply-*Optimization` 函数尚未对 `$Script:TestModeActive` 做"只读不写"的尊重——目前 `-TestMode` 仅是日志标记，实际执行仍会改注册表。**这是 GUI 化之前必须修的**。
- `Config.Manager.ps1` 中函数动词 `Load-` 不符合 PowerShell 推荐动词；非阻塞，可后续重构为 `Import-`。

### 文件变更摘要

```
M  WindowsOptimizerPlus.ps1        (改 require 列表 + Import-OptimizationModule 加载策略 + 编码)
M  Modules/Config.Manager.ps1      (仅编码: UTF-8 -> UTF-8 BOM)
M  Modules/Temp.Cleaner.ps1        (仅编码)
A  Modules/UI.Functions.ps1        (从空文件实现完整 UI 层 ~210 行)
R  Modules/RunOptimizer.ps1.ps1 -> Modules/RunOptimizer.ps1 (重命名 + 编码)
A  test-load.ps1                   (开发态冒烟测试脚本，非管理员可跑，不修改系统)
A  DEVLOG.md                       (本文件)
```
