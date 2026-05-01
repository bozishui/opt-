#
# Show-OptimizerGUI.ps1
# WinOpt+ 演示界面 — 加载 XAML、注入真实优化项数据、所有"应用"按钮一律走演示提示
#
# 用法:  powershell -NoProfile -ExecutionPolicy Bypass -File .\Show-OptimizerGUI.ps1
#
# 设计要点:
#  - GUI 演示模式下不调用任何 Apply-* 函数
#  - 真实数据通过现有 Get-*Optimizations / Get-CleanOptions 读取，仅用于呈现
#  - 不依赖管理员权限即可启动（仅在状态栏提示）
#

[CmdletBinding()]
param()

# ==========================================
# 路径与基础环境
# ==========================================
$Script:Root         = $PSScriptRoot
$Script:ModulesPath  = Join-Path $Script:Root 'Modules'
$Script:ResourcePath = Join-Path $Script:Root 'Resources'
$Script:LogsPath     = Join-Path $Script:Root 'Logs'
$Script:BackupsPath  = Join-Path $Script:Root 'Backups'
# UI 语言：'zh' | 'en'（默认中文；若当前线程 UI 文化非中文则默认英文）
$Script:UiLang = if ([string]::IsNullOrWhiteSpace([System.Threading.Thread]::CurrentThread.CurrentUICulture.Name) -or
    [System.Threading.Thread]::CurrentThread.CurrentUICulture.Name.StartsWith('zh', [System.StringComparison]::OrdinalIgnoreCase)) { 'zh' } else { 'en' }
$Script:CurrentNavKey = 'Dashboard'
foreach ($p in @($Script:LogsPath, $Script:BackupsPath)) {
    if (-not (Test-Path $p)) { New-Item $p -ItemType Directory -Force | Out-Null }
}

# 主脚本期待的 Script-scope 变量（被各模块引用）
$Script:Version          = '2.0.0'
$Script:ConfigVersion    = '2.0'
$Script:LogFile          = Join-Path $Script:LogsPath ("GUI_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
$Script:ErrorCollection  = @()
$Script:OperationStack   = New-Object System.Collections.Stack
$Script:RollbackRequired = $false
$Script:TestModeActive   = $true   # GUI 演示模式硬编码为 true
$Script:LoadedModules    = @{}

# ==========================================
# 最小桩函数 (替代主脚本的同名实现)
# ==========================================
function Write-Log {
    param([string]$Message, [string]$Level = 'Info', [switch]$NoConsole)
    $line = "[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Level, $Message
    try { Add-Content -Path $Script:LogFile -Value $line -Encoding UTF8 } catch { }
}
function Start-Operation       { param([string]$Name, [scriptblock]$RollbackAction = {}) ; @{ Name = $Name; StartTime = Get-Date } }
function Complete-Operation    { param([switch]$WithErrors) }
function Register-OperationError { param($ErrorRecord, [switch]$Fatal) ; Write-Log -Level Error -Message $ErrorRecord.Exception.Message }
function Invoke-Rollback       { }

# ==========================================
# 加载 .NET WPF assemblies
# ==========================================
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

# ==========================================
# 加载真实模块（不会触发 Show-MainMenu，仅注入函数）
# ==========================================
$modulesToLoad = @('System.Optimizer', 'Network.Optimizer', 'Gaming.Optimizer', 'Temp.Cleaner')
foreach ($m in $modulesToLoad) {
    $path = Join-Path $Script:ModulesPath ($m + '.ps1')
    if (-not (Test-Path $path)) {
        Write-Log -Level Warning -Message "模块缺失，跳过: $path"
        continue
    }
    function global:Export-ModuleMember { }
    try {
        . $path
        $Script:LoadedModules[$m] = $true
    }
    catch {
        Write-Log -Level Error -Message ("加载模块 {0} 失败: {1}" -f $m, $_.Exception.Message)
    }
    finally {
        Remove-Item function:\Export-ModuleMember -ErrorAction SilentlyContinue
    }
}

# ==========================================
# 加载 XAML
# ==========================================
$xamlFile = Join-Path $Script:ResourcePath 'MainWindow.xaml'
if (-not (Test-Path $xamlFile)) {
    $em = if ($Script:UiLang -eq 'en') { "UI file not found: $xamlFile" } else { "找不到 UI 文件: $xamlFile" }
    $et = if ($Script:UiLang -eq 'en') { 'WinOpt+ failed to start' } else { 'WinOpt+ 启动失败' }
    [System.Windows.MessageBox]::Show($em, $et, 'OK', 'Error') | Out-Null
    return
}
[xml]$xaml = Get-Content -Path $xamlFile -Raw -Encoding UTF8
$reader = New-Object System.Xml.XmlNodeReader $xaml
try {
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
}
catch {
    $em = if ($Script:UiLang -eq 'en') { "XAML parse error:`n$($_.Exception.Message)" } else { "XAML 解析失败:`n$($_.Exception.Message)" }
    $et = if ($Script:UiLang -eq 'en') { 'WinOpt+ failed to start' } else { 'WinOpt+ 启动失败' }
    [System.Windows.MessageBox]::Show($em, $et, 'OK', 'Error') | Out-Null
    return
}

# ==========================================
# 命名控件查找辅助函数
# ==========================================
function Find($name) { $window.FindName($name) }

# ==========================================
# 中英本地化
# ==========================================
function Get-UiStrings {
    param([ValidateSet('zh', 'en')] [string]$Lang)
    $tables = @{
        zh = @{
            'window.title'              = 'Windows 优化加强版'
            'banner.demo'               = '演示模式 — 当前界面仅作交互预览，所有「应用」「优化」「清理」按钮不会真正修改系统。'
            'sidebar.subtitle'          = 'Windows 优化加强版'
            'sidebar.copyright'         = '© 2026 youhua project'
            'nav.dashboard'             = '📊  仪表盘'
            'nav.system'                = '⚡  系统优化'
            'nav.network'               = '🌐  网络优化'
            'nav.gaming'                = '🎮  游戏优化'
            'nav.cleanup'               = '🧹  临时文件清理'
            'nav.settings'              = '⚙  设置'
            'nav.about'                 = 'ℹ  关于'
            'page.dashboard.title'      = '仪表盘'
            'card.os'                   = '操作系统'
            'card.cpu'                  = '处理器'
            'card.ram'                  = '内存'
            'card.disk'                 = '系统盘'
            'dashboard.score.label'     = '健康评分（演示数据）'
            'dashboard.score.section'   = '一键体检'
            'dashboard.score.desc'      = '扫描可优化项，包含系统、网络、游戏、临时文件四大维度。点击「开始扫描」会读取真实模块条目，但不修改系统。'
            'btn.scan'                  = '开始扫描'
            'btn.oneclick'              = '一键加速'
            'dashboard.modules.title'   = '模块加载状态'
            'page.system.title'         = '系统优化'
            'page.system.desc'          = '包含服务、启动项、磁盘、视觉效果、注册表等优化项。勾选要应用的项后点击「应用所选」。'
            'page.network.title'        = '网络优化'
            'page.network.desc'         = '包含 TCP 调优、DNS、MTU、QoS 等。'
            'page.gaming.title'         = '游戏优化'
            'page.gaming.desc'          = '包含高性能电源计划、GameMode、计时器精度、GPU 设置等。'
            'page.cleanup.title'        = '临时文件清理'
            'page.cleanup.desc'         = '扫描各类临时文件，预估可释放空间。'
            'cleanup.size.label'        = '预估可清理（演示数据）'
            'cleanup.section.title'     = '勾选下方分类后点击「立即清理」'
            'cleanup.section.desc'      = '包括 Windows 临时目录、用户临时目录、浏览器缓存、Windows Update 缓存、缩略图等。'
            'btn.cleanScan'             = '重新扫描'
            'btn.selectall'             = '全选'
            'btn.clearall'              = '清空'
            'btn.apply'                 = '应用所选'
            'btn.cleanupApply'          = '立即清理'
            'page.settings.title'       = '设置'
            'settings.run.title'        = '运行偏好'
            'settings.opt1'             = '操作前先创建系统还原点（推荐）'
            'settings.opt2'             = '操作前备份注册表项'
            'settings.opt3'             = '启动时自动检查更新'
            'settings.opt4'             = '开机自动启动 WinOpt+'
            'settings.diag.title'       = '日志与诊断'
            'settings.diag.logsBtn'     = '打开日志目录'
            'settings.diag.logsLine'    = '日志保留天数：30'
            'settings.diag.bkBtn'       = '打开备份目录'
            'settings.diag.bkLine'      = '备份保留：最近 10 次'
            'settings.cfg.title'        = '配置文件'
            'settings.cfg.export'       = '导出当前配置'
            'settings.cfg.import'       = '导入配置文件'
            'page.about.title'          = '关于'
            'about.appname'             = 'Windows 优化加强版'
            'about.versionline'         = 'WinOpt+ · v2.0.0 (演示界面)'
            'about.desc1'               = '一款面向 Windows 10/11 的系统优化工具，覆盖系统、网络、游戏、清理四大模块，配备完整的日志与回滚机制。'
            'about.desc2'               = '当前为演示界面：UI 已完成，业务后端复用现有 PowerShell 模块，但「应用」类操作目前不会真正执行。'
            'about.tech.title'          = '技术栈'
            'about.tech1'               = '• 前端：WPF (XAML) + PowerShell 5.1 host'
            'about.tech2'               = '• 后端：现有 6 个 .ps1 模块（系统/网络/游戏/清理/配置/UI）'
            'about.tech3'               = '• 配置：UTF-8 BOM PowerShell + JSON 持久化'
            'status.ready'              = '就绪'
            'status.current'            = '当前: {0}'
            'status.scanning'           = '正在扫描...'
            'status.scan.done'          = '扫描完成（演示）'
            'status.clean.rescanned'    = '已重新扫描清理项（演示数据）'
            'admin.yes'                 = '🛡 管理员模式'
            'admin.no'                  = '⚠ 非管理员（部分功能在正式版需要提权）'
            'module.loaded'             = '已加载'
            'module.missing'            = '未加载'
            'demo.toast.title'          = '演示模式'
            'demo.toast.body'           = "演示模式：「{0}」操作未真正执行。`n`n实际功能将在接入 GUI ↔ PowerShell 后端后启用。"
            'demo.toast.detail'         = '详情'
            'demo.scan.found'           = '已发现可优化项：{0} 项'
            'demo.detail.selected'      = '已选 {0} 项'
            'demo.detail.cleanup'       = '{0} 个分类，预估释放 {1}'
            'demo.action.scan'          = '扫描'
            'demo.action.oneclick'      = '一键加速'
            'demo.action.systemapply'   = '应用系统优化'
            'demo.action.networkapply'  = '应用网络优化'
            'demo.action.gamingapply'   = '应用游戏优化'
            'demo.action.cleanup'       = '清理临时文件'
            'demo.action.export'        = '导出配置'
            'demo.action.import'        = '导入配置'
            'pagekey.Dashboard'         = '仪表盘'
            'pagekey.System'            = '系统优化'
            'pagekey.Network'           = '网络优化'
            'pagekey.Gaming'            = '游戏优化'
            'pagekey.Cleanup'           = '临时文件清理'
            'pagekey.Settings'          = '设置'
            'pagekey.About'             = '关于'
            'ram.used'                  = '已用 {0:N1} GB'
            'disk.free'                 = '可用 {0} GB'
            'cpu.threads'               = '{0} 核 / {1} 线程'
        }
        en = @{
            'window.title'              = 'Windows Optimizer Plus'
            'banner.demo'               = 'Demo mode — this UI is for preview only. Apply / Optimize / Clean actions do not change your system.'
            'sidebar.subtitle'          = 'Windows Optimizer Plus'
            'sidebar.copyright'         = '© 2026 youhua project'
            'nav.dashboard'             = '📊  Dashboard'
            'nav.system'                = '⚡  System'
            'nav.network'               = '🌐  Network'
            'nav.gaming'                = '🎮  Gaming'
            'nav.cleanup'               = '🧹  Temp cleanup'
            'nav.settings'              = '⚙  Settings'
            'nav.about'                 = 'ℹ  About'
            'page.dashboard.title'      = 'Dashboard'
            'card.os'                   = 'Operating system'
            'card.cpu'                  = 'Processor'
            'card.ram'                  = 'Memory'
            'card.disk'                 = 'System drive'
            'dashboard.score.label'     = 'Health score (demo data)'
            'dashboard.score.section'   = 'Quick check-up'
            'dashboard.score.desc'      = 'Scan optimization items across system, network, gaming, and temp files. Start Scan loads real module entries without modifying the system.'
            'btn.scan'                  = 'Start scan'
            'btn.oneclick'              = 'Boost'
            'dashboard.modules.title'   = 'Module load status'
            'page.system.title'         = 'System optimization'
            'page.system.desc'          = 'Services, startup, disk, visual effects, registry, and more. Select items, then click Apply selected.'
            'page.network.title'        = 'Network optimization'
            'page.network.desc'         = 'TCP tuning, DNS, MTU, QoS, and related tweaks.'
            'page.gaming.title'         = 'Gaming optimization'
            'page.gaming.desc'          = 'High performance power plan, Game Mode, timer resolution, GPU settings, etc.'
            'page.cleanup.title'        = 'Temporary files'
            'page.cleanup.desc'         = 'Scan temp files and estimate reclaimable space.'
            'cleanup.size.label'        = 'Estimated reclaimable (demo data)'
            'cleanup.section.title'     = 'Select categories below, then click Clean now'
            'cleanup.section.desc'      = 'Includes Windows temp, user temp, browser cache, Windows Update cache, thumbnails, and more.'
            'btn.cleanScan'             = 'Rescan'
            'btn.selectall'             = 'Select all'
            'btn.clearall'              = 'Clear'
            'btn.apply'                 = 'Apply selected'
            'btn.cleanupApply'          = 'Clean now'
            'page.settings.title'       = 'Settings'
            'settings.run.title'        = 'Runtime preferences'
            'settings.opt1'             = 'Create a system restore point before changes (recommended)'
            'settings.opt2'             = 'Back up registry keys before changes'
            'settings.opt3'             = 'Check for updates on startup'
            'settings.opt4'             = 'Start WinOpt+ with Windows'
            'settings.diag.title'       = 'Logs & diagnostics'
            'settings.diag.logsBtn'     = 'Open logs folder'
            'settings.diag.logsLine'    = 'Log retention: 30 days'
            'settings.diag.bkBtn'       = 'Open backups folder'
            'settings.diag.bkLine'      = 'Backups kept: last 10'
            'settings.cfg.title'        = 'Configuration'
            'settings.cfg.export'       = 'Export current profile'
            'settings.cfg.import'       = 'Import profile'
            'page.about.title'          = 'About'
            'about.appname'             = 'Windows Optimizer Plus'
            'about.versionline'         = 'WinOpt+ · v2.0.0 (Demo UI)'
            'about.desc1'               = 'A Windows 10/11 tuning tool covering system, network, gaming, and cleanup with logging and rollback support.'
            'about.desc2'               = 'Demo UI: the shell is wired to existing PowerShell modules; apply-style actions are not executed yet.'
            'about.tech.title'          = 'Stack'
            'about.tech1'               = '• UI: WPF (XAML) + PowerShell 5.1 host'
            'about.tech2'               = '• Modules: existing .ps1 (system / network / gaming / cleanup / config / UI)'
            'about.tech3'               = '• Config: UTF-8 BOM PowerShell + JSON persistence'
            'status.ready'              = 'Ready'
            'status.current'            = 'Current: {0}'
            'status.scanning'           = 'Scanning...'
            'status.scan.done'          = 'Scan finished (demo)'
            'status.clean.rescanned'    = 'Cleanup rescanned (demo data)'
            'admin.yes'                 = '🛡 Administrator'
            'admin.no'                  = '⚠ Not elevated (some features may require admin in full release)'
            'module.loaded'             = 'loaded'
            'module.missing'            = 'not loaded'
            'demo.toast.title'          = 'Demo mode'
            'demo.toast.body'           = "Demo mode: “{0}” was not executed.`n`nReal execution will be enabled when the GUI is connected to the PowerShell backend."
            'demo.toast.detail'         = 'Details'
            'demo.scan.found'           = 'Items found: {0}'
            'demo.detail.selected'      = '{0} item(s) selected'
            'demo.detail.cleanup'       = '{0} categor(ies), about {1} reclaimable'
            'demo.action.scan'          = 'Scan'
            'demo.action.oneclick'      = 'One-click boost'
            'demo.action.systemapply'   = 'Apply system tweaks'
            'demo.action.networkapply'  = 'Apply network tweaks'
            'demo.action.gamingapply'   = 'Apply gaming tweaks'
            'demo.action.cleanup'       = 'Clean temp files'
            'demo.action.export'        = 'Export settings'
            'demo.action.import'        = 'Import settings'
            'pagekey.Dashboard'         = 'Dashboard'
            'pagekey.System'            = 'System'
            'pagekey.Network'           = 'Network'
            'pagekey.Gaming'            = 'Gaming'
            'pagekey.Cleanup'           = 'Cleanup'
            'pagekey.Settings'          = 'Settings'
            'pagekey.About'             = 'About'
            'ram.used'                  = '{0:N1} GB used'
            'disk.free'                 = '{0} GB free'
            'cpu.threads'               = '{0} cores / {1} threads'
        }
    }
    return $tables[$Lang]
}

function Get-UiStr {
    param([string]$Key, [string[]]$FormatArgs)
    $d = Get-UiStrings -Lang $Script:UiLang
    $s = $d[$Key]
    if (-not $s) { return $Key }
    if ($FormatArgs -and $FormatArgs.Count) { return $s -f $FormatArgs }
    return $s
}

function Set-TaggedLocalization {
    param(
        [System.Windows.DependencyObject]$Root,
        [hashtable]$Dict
    )
    if ($null -eq $Root) { return }
    if ($Root -is [System.Windows.FrameworkElement]) {
        $fe = [System.Windows.FrameworkElement]$Root
        $tag = $fe.Tag
        if ($null -ne $tag -and "$tag" -ne '') {
            $k = "$tag"
            if ($Dict.ContainsKey($k)) {
                $val = $Dict[$k]
                if ($Root -is [System.Windows.Controls.TextBlock]) {
                    ([System.Windows.Controls.TextBlock]$Root).Text = $val
                }
                elseif ($Root -is [System.Windows.Controls.Button]) {
                    ([System.Windows.Controls.Button]$Root).Content = $val
                }
                elseif ($Root -is [System.Windows.Controls.CheckBox]) {
                    ([System.Windows.Controls.CheckBox]$Root).Content = $val
                }
            }
        }
    }
    $n = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Root)
    for ($i = 0; $i -lt $n; $i++) {
        $ch = [System.Windows.Media.VisualTreeHelper]::GetChild($Root, $i)
        Set-TaggedLocalization -Root $ch -Dict $Dict
    }
}

function Update-AdminLabel {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    (Find 'LblAdmin').Text = if ($isAdmin) { Get-UiStr 'admin.yes' } else { Get-UiStr 'admin.no' }
}

function Find-VisualByTag {
    param(
        [System.Windows.DependencyObject]$Root,
        [string]$TagValue
    )
    if ($Root -is [System.Windows.FrameworkElement] -and "$([System.Windows.FrameworkElement]$Root.Tag)" -eq $TagValue) {
        return $Root
    }
    $c = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Root)
    for ($i = 0; $i -lt $c; $i++) {
        $ch = [System.Windows.Media.VisualTreeHelper]::GetChild($Root, $i)
        $hit = Find-VisualByTag -Root $ch -TagValue $TagValue
        if ($hit) { return $hit }
    }
    return $null
}

function Update-SidebarVersionLine {
    $v = $Script:Version
    $tb = Find 'TxtSidebarVersion'
    if ($tb) { $tb.Text = "v$v" }
    $aboutLine = Find-VisualByTag -Root $window -TagValue 'about.versionline'
    if ($aboutLine -is [System.Windows.Controls.TextBlock]) {
        $aboutLine.Text = if ($Script:UiLang -eq 'en') { "WinOpt+ · v$v (Demo UI)" } else { "WinOpt+ · v$v (演示界面)" }
    }
}

function Update-DashboardHardwareCaptions {
    if (-not $Script:UiDashData) { return }
    $d = $Script:UiDashData
    (Find 'LblCPUCores').Text = (Get-UiStr 'cpu.threads' -FormatArgs @($d.Cores, $d.Logical))
    (Find 'LblRAMUsage').Text = (Get-UiStr 'ram.used' -FormatArgs @(($d.TotalGB - $d.FreeGB)))
    if ($null -ne $d.DiskFreeGB) {
        (Find 'LblDiskFree').Text = (Get-UiStr 'disk.free' -FormatArgs @($d.DiskFreeGB))
    }
}

function Update-ModuleStatusList {
    $msList = Find 'ModuleStatusList'
    $msList.Items.Clear()
    $expectedModules = 'System.Optimizer', 'Network.Optimizer', 'Gaming.Optimizer', 'Temp.Cleaner'
    $loadedW = Get-UiStr 'module.loaded'
    $missW = Get-UiStr 'module.missing'
    foreach ($m in $expectedModules) {
        $row = New-Object System.Windows.Controls.DockPanel
        $row.Margin = '0,4,0,4'
        $loaded = $Script:LoadedModules.ContainsKey($m) -and $Script:LoadedModules[$m]
        $dot = New-Object System.Windows.Controls.Border
        $dot.Width = 8; $dot.Height = 8
        $dot.CornerRadius = 4
        $dot.Margin = '0,0,8,0'
        $dot.Background = if ($loaded) { '#107C10' } else { '#D13438' }
        [System.Windows.Controls.DockPanel]::SetDock($dot, 'Left')
        $row.Children.Add($dot) | Out-Null
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = "$m " + $(if ($loaded) { $loadedW } else { $missW })
        $tb.VerticalAlignment = 'Center'
        $row.Children.Add($tb) | Out-Null
        $msList.Items.Add($row) | Out-Null
    }
}

function Get-BilingualDemoItems {
    return @{
        System  = @(
            @{ NameZh = '禁用不必要的系统服务'; NameEn = 'Disable unnecessary system services'; DescZh = '关闭不常用的后台服务以节省资源'; DescEn = 'Stop rarely used background services to save resources' }
            @{ NameZh = '优化系统启动项'; NameEn = 'Optimize startup items'; DescZh = '禁用拖慢开机的启动项'; DescEn = 'Disable startup entries that slow boot' }
            @{ NameZh = '优化磁盘性能'; NameEn = 'Optimize disk performance'; DescZh = '调整 NTFS 与 SSD 相关参数'; DescEn = 'Tune NTFS and SSD-related settings' }
        )
        Network = @(
            @{ NameZh = '优化 TCP 参数'; NameEn = 'Optimize TCP settings'; DescZh = '调整窗口缩放、自动调谐等'; DescEn = 'Window scaling, autotuning, and related tweaks' }
            @{ NameZh = '设置最优 DNS'; NameEn = 'Set optimal DNS'; DescZh = '使用低延迟 DNS 服务器'; DescEn = 'Use low-latency DNS servers' }
            @{ NameZh = '禁用 WiFi 节能'; NameEn = 'Disable Wi-Fi power saving'; DescZh = '避免无线网卡进入节能态'; DescEn = 'Prevent the wireless adapter from power-saving states' }
        )
        Gaming  = @(
            @{ NameZh = '启用卓越性能电源计划'; NameEn = 'Enable Ultimate Performance power plan'; DescZh = '解锁隐藏的高性能电源方案'; DescEn = 'Unlock the hidden high-performance scheme' }
            @{ NameZh = '禁用全屏优化'; NameEn = 'Disable fullscreen optimizations'; DescZh = '降低部分游戏的输入延迟'; DescEn = 'May reduce input latency in some games' }
            @{ NameZh = '启用游戏模式'; NameEn = 'Enable Game Mode'; DescZh = '让 Windows 优先调度游戏进程'; DescEn = 'Let Windows prioritize game processes' }
        )
        Cleanup = @(
            @{ NameZh = 'Windows 临时文件夹'; NameEn = 'Windows temp folder'; DescZh = '系统临时目录'; DescEn = 'System temporary directory'; Enabled = $true }
            @{ NameZh = '用户临时文件夹'; NameEn = 'User temp folder'; DescZh = '当前用户临时目录'; DescEn = 'Current user temp directory'; Enabled = $true }
            @{ NameZh = '浏览器缓存'; NameEn = 'Browser cache'; DescZh = '主流浏览器缓存'; DescEn = 'Common browser caches'; Enabled = $false }
        )
    }
}

function ConvertFrom-BilingualRow {
    param([hashtable]$Row)
    $en = $null
    if ($Row.ContainsKey('Enabled')) { $en = $Row['Enabled'] }
    if ($Script:UiLang -eq 'en') {
        return [pscustomobject]@{ Name = $Row['NameEn']; Description = $Row['DescEn']; Enabled = $en }
    }
    return [pscustomobject]@{ Name = $Row['NameZh']; Description = $Row['DescZh']; Enabled = $en }
}

function Get-DemoOptionsLocalized {
    param(
        [string]$Cmd,
        [hashtable[]]$BilingualRows
    )
    if (Get-Command -Name $Cmd -ErrorAction SilentlyContinue) {
        try {
            $got = @(& $Cmd)
            if ($got -and $got.Count) { return @{ Source = 'module'; Items = $got } }
        }
        catch { Write-Log -Level Warning -Message "调用 $Cmd 失败: $_" }
    }
    $items = foreach ($r in $BilingualRows) { ConvertFrom-BilingualRow $r }
    return @{ Source = 'fallback'; Items = @($items) }
}

function Refresh-OptimizationLists {
    $bio = Get-BilingualDemoItems
    $Script:DemoSystemResult  = Get-DemoOptionsLocalized -Cmd 'Get-SystemOptimizations'  -BilingualRows $bio.System
    $Script:DemoNetworkResult = Get-DemoOptionsLocalized -Cmd 'Get-NetworkOptimizations' -BilingualRows $bio.Network
    $Script:DemoGamingResult  = Get-DemoOptionsLocalized -Cmd 'Get-GamingOptimizations'  -BilingualRows $bio.Gaming
    $Script:DemoCleanResult   = Get-DemoOptionsLocalized -Cmd 'Get-CleanOptions'         -BilingualRows $bio.Cleanup
    $Script:systemOpts  = $Script:DemoSystemResult.Items
    $Script:networkOpts = $Script:DemoNetworkResult.Items
    $Script:gamingOpts  = $Script:DemoGamingResult.Items
    $Script:cleanOpts   = $Script:DemoCleanResult.Items
    Set-CheckListItems -Container (Find 'ListSystem')  -Items $Script:systemOpts
    Set-CheckListItems -Container (Find 'ListNetwork') -Items $Script:networkOpts
    Set-CheckListItems -Container (Find 'ListGaming')  -Items $Script:gamingOpts
    Set-CheckListItems -Container (Find 'ListCleanup') -Items $Script:cleanOpts
}

function Set-LangButtonState {
    $bZh = Find 'BtnLangZh'
    $bEn = Find 'BtnLangEn'
    if ($bZh) { $bZh.Tag = if ($Script:UiLang -eq 'zh') { 'active' } else { $null } }
    if ($bEn) { $bEn.Tag = if ($Script:UiLang -eq 'en') { 'active' } else { $null } }
}

function Update-UiLanguage {
    $dict = Get-UiStrings -Lang $Script:UiLang
    $window.Title = $dict['window.title']
    Set-TaggedLocalization -Root $window -Dict $dict
    Update-SidebarVersionLine
    Update-DashboardHardwareCaptions
    Update-ModuleStatusList
    Refresh-OptimizationLists
    Update-AdminLabel
    Set-LangButtonState
    Set-StatusForNavKey -Key $Script:CurrentNavKey
}

function Set-StatusForNavKey {
    param([string]$Key)
    $label = Get-UiStr "pagekey.$Key"
    (Find 'LblStatus').Text = (Get-UiStr 'status.current' -FormatArgs @($label))
}

# ==========================================
# 演示提示 (统一替代真实 Apply-*)
# ==========================================
function Show-DemoToast {
    param([string]$Action, [string]$Detail = '')
    $body = Get-UiStr 'demo.toast.body' -FormatArgs @($Action)
    if ($Detail) {
        $body += "`n`n$(Get-UiStr 'demo.toast.detail'):`n$Detail"
    }
    [System.Windows.MessageBox]::Show($body, (Get-UiStr 'demo.toast.title'), 'OK', 'Information') | Out-Null
}

# ==========================================
# 渲染列表项 (CheckBox + 名称 + 描述)
# ==========================================
function Set-CheckListItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Windows.Controls.ItemsControl]$Container,
        [Parameter(Mandatory)] [object[]]$Items
    )
    $Container.Items.Clear()
    foreach ($it in $Items) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Margin = '16,10,16,10'
        $cb.IsChecked = $false
        # 部分项 (Temp.Cleaner) 可能带 Enabled 默认值
        if ($it.PSObject.Properties.Name -contains 'Enabled') { $cb.IsChecked = [bool]$it.Enabled }

        $sp = New-Object System.Windows.Controls.StackPanel
        $title = New-Object System.Windows.Controls.TextBlock
        $title.Text       = [string]$it.Name
        $title.FontWeight = 'SemiBold'
        $title.FontSize   = 13
        $sp.Children.Add($title) | Out-Null

        if ($it.PSObject.Properties.Name -contains 'Description' -and $it.Description) {
            $desc = New-Object System.Windows.Controls.TextBlock
            $desc.Text       = [string]$it.Description
            $desc.FontSize   = 11
            $desc.Foreground = [System.Windows.Media.Brushes]::Gray
            $desc.Margin     = '0,2,0,0'
            $desc.TextWrapping = 'Wrap'
            $sp.Children.Add($desc) | Out-Null
        }

        $cb.Content = $sp
        $Container.Items.Add($cb) | Out-Null

        # 在最后一项之外加分隔线
        $sep = New-Object System.Windows.Controls.Border
        $sep.Height = 1
        $sep.Background = '#EEEEEE'
        $sep.Margin = '16,0,16,0'
        $Container.Items.Add($sep) | Out-Null
    }
}

function Get-CheckedCount {
    param([System.Windows.Controls.ItemsControl]$Container)
    $n = 0
    foreach ($child in $Container.Items) {
        if ($child -is [System.Windows.Controls.CheckBox] -and $child.IsChecked) { $n++ }
    }
    return $n
}

function Set-AllChecked {
    param([System.Windows.Controls.ItemsControl]$Container, [bool]$Value)
    foreach ($child in $Container.Items) {
        if ($child -is [System.Windows.Controls.CheckBox]) { $child.IsChecked = $Value }
    }
}

# ==========================================
# 控件引用
# ==========================================
$pages = @{
    Dashboard = Find 'PageDashboard'
    System    = Find 'PageSystem'
    Network   = Find 'PageNetwork'
    Gaming    = Find 'PageGaming'
    Cleanup   = Find 'PageCleanup'
    Settings  = Find 'PageSettings'
    About     = Find 'PageAbout'
}
$navs = @{
    Dashboard = Find 'NavDashboard'
    System    = Find 'NavSystem'
    Network   = Find 'NavNetwork'
    Gaming    = Find 'NavGaming'
    Cleanup   = Find 'NavCleanup'
    Settings  = Find 'NavSettings'
    About     = Find 'NavAbout'
}

# ==========================================
# 导航逻辑
# ==========================================
function Switch-Page([string]$key) {
    $Script:CurrentNavKey = $key
    foreach ($k in $pages.Keys) {
        $pages[$k].Visibility = if ($k -eq $key) { 'Visible' } else { 'Collapsed' }
    }
    Set-StatusForNavKey -Key $key
}
foreach ($k in $navs.Keys) {
    $navs[$k].Add_Checked([scriptblock]::Create("Switch-Page '$k'"))
}

# ==========================================
# 仪表盘数据
# ==========================================
try {
    $os  = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" -ErrorAction Stop

    (Find 'LblOSName').Text   = $os.Caption
    (Find 'LblOSBuild').Text  = "Build $($os.BuildNumber)"
    (Find 'LblCPU').Text      = ($cpu.Name -replace '\s+', ' ').Trim()

    $totalGB = [math]::Round([double]$os.TotalVisibleMemorySize / 1MB, 1)
    $freeGB  = [math]::Round([double]$os.FreePhysicalMemory     / 1MB, 1)
    (Find 'LblRAM').Text       = "$totalGB GB"

    $diskFreeGB = $null
    if ($disk) {
        $sizeGB = [math]::Round([double]$disk.Size / 1GB, 0)
        $diskFreeGB = [math]::Round([double]$disk.FreeSpace / 1GB, 1)
        (Find 'LblDisk').Text     = "$($disk.DeviceID) $sizeGB GB"
    }

    $Script:UiDashData = @{
        Cores        = [int]$cpu.NumberOfCores
        Logical      = [int]$cpu.NumberOfLogicalProcessors
        TotalGB      = [double]$totalGB
        FreeGB       = [double]$freeGB
        DiskFreeGB   = $diskFreeGB
    }
    Update-DashboardHardwareCaptions
}
catch {
    Write-Log -Level Warning -Message "读取系统信息失败: $_"
    $Script:UiDashData = $null
}

# 演示评分 (固定 0-100 之间随机)
(Find 'LblScore').Text = (Get-Random -Minimum 60 -Maximum 95).ToString()

# 演示数据：清理预估
$bytesEstimate = (Get-Random -Minimum 500MB -Maximum 8GB)
(Find 'LblCleanupSize').Text = "{0:N1} GB" -f ($bytesEstimate / 1GB)

# ==========================================
# 按钮事件
# ==========================================
(Find 'BtnScan').Add_Click({
    $bar = Find 'ScanProgress'
    $bar.Value = 0
    (Find 'LblStatus').Text = Get-UiStr 'status.scanning'
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(40)
    $timer.Add_Tick({
        $bar.Value += 5
        if ($bar.Value -ge 100) {
            $timer.Stop()
            (Find 'LblStatus').Text = Get-UiStr 'status.scan.done'
            $cnt = $Script:systemOpts.Count + $Script:networkOpts.Count + $Script:gamingOpts.Count
            Show-DemoToast -Action (Get-UiStr 'demo.action.scan') -Detail (Get-UiStr 'demo.scan.found' -FormatArgs @($cnt))
        }
    })
    $timer.Start()
})

(Find 'BtnOneClick').Add_Click({ Show-DemoToast -Action (Get-UiStr 'demo.action.oneclick') })

(Find 'BtnSystemSelectAll').Add_Click({  Set-AllChecked -Container (Find 'ListSystem')  -Value $true })
(Find 'BtnSystemClearAll').Add_Click({   Set-AllChecked -Container (Find 'ListSystem')  -Value $false })
(Find 'BtnSystemApply').Add_Click({
    $n = Get-CheckedCount -Container (Find 'ListSystem')
    Show-DemoToast -Action (Get-UiStr 'demo.action.systemapply') -Detail (Get-UiStr 'demo.detail.selected' -FormatArgs @($n))
})

(Find 'BtnNetworkSelectAll').Add_Click({ Set-AllChecked -Container (Find 'ListNetwork') -Value $true })
(Find 'BtnNetworkClearAll').Add_Click({  Set-AllChecked -Container (Find 'ListNetwork') -Value $false })
(Find 'BtnNetworkApply').Add_Click({
    $n = Get-CheckedCount -Container (Find 'ListNetwork')
    Show-DemoToast -Action (Get-UiStr 'demo.action.networkapply') -Detail (Get-UiStr 'demo.detail.selected' -FormatArgs @($n))
})

(Find 'BtnGamingSelectAll').Add_Click({  Set-AllChecked -Container (Find 'ListGaming')  -Value $true })
(Find 'BtnGamingClearAll').Add_Click({   Set-AllChecked -Container (Find 'ListGaming')  -Value $false })
(Find 'BtnGamingApply').Add_Click({
    $n = Get-CheckedCount -Container (Find 'ListGaming')
    Show-DemoToast -Action (Get-UiStr 'demo.action.gamingapply') -Detail (Get-UiStr 'demo.detail.selected' -FormatArgs @($n))
})

(Find 'BtnCleanupSelectAll').Add_Click({ Set-AllChecked -Container (Find 'ListCleanup') -Value $true })
(Find 'BtnCleanupApply').Add_Click({
    $n = Get-CheckedCount -Container (Find 'ListCleanup')
    Show-DemoToast -Action (Get-UiStr 'demo.action.cleanup') -Detail (Get-UiStr 'demo.detail.cleanup' -FormatArgs @($n, (Find 'LblCleanupSize').Text))
})
(Find 'BtnCleanScan').Add_Click({
    $bytesEstimate = Get-Random -Minimum 500MB -Maximum 8GB
    (Find 'LblCleanupSize').Text = "{0:N1} GB" -f ($bytesEstimate / 1GB)
    (Find 'LblStatus').Text = Get-UiStr 'status.clean.rescanned'
})

(Find 'BtnOpenLogs').Add_Click({    Start-Process explorer.exe $Script:LogsPath })
(Find 'BtnOpenBackups').Add_Click({ Start-Process explorer.exe $Script:BackupsPath })
(Find 'BtnExportConfig').Add_Click({ Show-DemoToast -Action (Get-UiStr 'demo.action.export') })
(Find 'BtnImportConfig').Add_Click({ Show-DemoToast -Action (Get-UiStr 'demo.action.import') })

(Find 'BtnLangZh').Add_Click({
    $Script:UiLang = 'zh'
    Update-UiLanguage
})
(Find 'BtnLangEn').Add_Click({
    $Script:UiLang = 'en'
    Update-UiLanguage
})

# ==========================================
# 状态栏 / 首次语言套用
# ==========================================
Update-UiLanguage

# ==========================================
# 显示窗口
# ==========================================
[void]$window.ShowDialog()
