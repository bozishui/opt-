#
# WindowsOptimizerPlus.ps1
# 高级Windows优化工具 - 针对中国用户优化的系统性能与网络游戏体验提升工具
# 版本: 2.0.0
# 作者: Claude AI Assistant
# 日期: 2024年8月
#

#Requires -RunAsAdministrator
[CmdletBinding()]
param (
    [switch]$Silent,
    [switch]$NoBackup,
    [string]$ConfigFile,
    [switch]$ImportConfig,
    [string]$ExportConfig,
    [switch]$TestMode
)

# ==========================================
# 脚本版本和安全配置
# ==========================================
$Script:Version = "2.0.0"
$Script:ConfigVersion = "2.0" 
$Script:ModulesPath = Join-Path $PSScriptRoot "Modules"
$Script:LogsPath = Join-Path $PSScriptRoot "Logs"
$Script:BackupsPath = Join-Path $PSScriptRoot "Backups"
$Script:LogFile = Join-Path $LogsPath "WindowsOptimizerPlus_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$Script:StartTime = Get-Date

# 创建必要的目录结构
$requiredPaths = @($ModulesPath, $LogsPath, $BackupsPath)
foreach ($path in $requiredPaths) {
    if (-not (Test-Path -Path $path)) {
        try {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
            Write-Verbose "创建目录: $path"
        }
        catch {
            Write-Error "无法创建目录: $path. 错误: $_"
            exit 1
        }
    }
}

# ==========================================
# 错误处理和日志记录机制
# ==========================================

# 创建全局错误集合
$Script:ErrorCollection = @()
$Script:OperationStack = New-Object System.Collections.Stack
$Script:RollbackRequired = $false
$Script:TestModeActive = $TestMode

# 初始化错误日志函数
function Initialize-Logging {
    # 创建或追加日志文件
    $logHeader = @"
=============================================
Windows优化加强版 v$Script:Version - 日志记录
开始时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
操作系统: $(Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object -ExpandProperty Caption)
=============================================

"@
    
    try {
        $logHeader | Out-File -FilePath $Script:LogFile -Encoding UTF8 -Append
        Write-Verbose "日志文件初始化: $Script:LogFile"
    }
    catch {
        Write-Error "无法创建日志文件: $_"
    }
}

# 记录日志
function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Debug')]
        [string]$Level = 'Info',
        
        [Parameter()]
        [switch]$NoConsole
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # 添加到日志文件
    try {
        $logMessage | Out-File -FilePath $Script:LogFile -Encoding UTF8 -Append
    }
    catch {
        Write-Warning "无法写入日志: $_"
    }
    
    # 输出到控制台
    if (-not $NoConsole) {
        $consoleColors = @{
            'Info' = 'White'
            'Warning' = 'Yellow'
            'Error' = 'Red'
            'Success' = 'Green'
            'Debug' = 'DarkGray'
        }
        
        if ($Silent -and $Level -ne 'Error') {
            return
        }
        
        Write-Host $logMessage -ForegroundColor $consoleColors[$Level]
    }
}

# 更好的错误处理
function Start-Operation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter()]
        [scriptblock]$RollbackAction = {}
        
        # 补充：可以增加更多参数，如预期状态、验证条件等
    )
    
    $operation = @{
        Name = $Name
        StartTime = Get-Date
        Status = "Running"
        RollbackAction = $RollbackAction
        Errors = @()
    }
    
    $Script:OperationStack.Push($operation)
    Write-Log "开始操作: $Name" -Level Info
    
    return $operation
}

function Complete-Operation {
    [CmdletBinding()]
    param (
        [Parameter()]
        [switch]$WithErrors
    )
    
    if ($Script:OperationStack.Count -gt 0) {
        $operation = $Script:OperationStack.Pop()
        $duration = (Get-Date) - $operation.StartTime
        
        if ($WithErrors) {
            $operation.Status = "Failed"
            Write-Log "操作失败: $($operation.Name) (耗时: $($duration.TotalSeconds.ToString('0.00'))s)" -Level Error
        }
        else {
            $operation.Status = "Completed"
            Write-Log "操作完成: $($operation.Name) (耗时: $($duration.TotalSeconds.ToString('0.00'))s)" -Level Success
        }
        
        return $operation
    }
    else {
        Write-Log "尝试完成不存在的操作" -Level Warning
        return $null
    }
}

function Register-OperationError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        
        [Parameter()]
        [switch]$Fatal
    )
    
    $errorMessage = "错误: $($ErrorRecord.Exception.Message)"
    Write-Log $errorMessage -Level Error
    
    if ($Script:OperationStack.Count -gt 0) {
        $currentOperation = $Script:OperationStack.Peek()
        $currentOperation.Errors += $ErrorRecord
    }
    
    $Script:ErrorCollection += $ErrorRecord
    
    if ($Fatal) {
        $Script:RollbackRequired = $true
        Invoke-Rollback
    }
}

function Invoke-Rollback {
    [CmdletBinding()]
    param()
    
    Write-Log "开始回滚操作..." -Level Warning
    
    while ($Script:OperationStack.Count -gt 0) {
        $operation = $Script:OperationStack.Pop()
        
        try {
            Write-Log "正在回滚: $($operation.Name)" -Level Warning
            & $operation.RollbackAction
            Write-Log "回滚完成: $($operation.Name)" -Level Success
        }
        catch {
            Write-Log "回滚失败: $($operation.Name) - $_" -Level Error
        }
    }
    
    Write-Log "所有回滚操作已完成" -Level Warning
}

# ==========================================
# 模块化导入系统
# ==========================================

$Script:LoadedModules = @{}

function Import-OptimizationModule {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )
    
    # 如果模块已加载，则不再重复加载
    if ($Script:LoadedModules.ContainsKey($ModuleName)) {
        Write-Log "模块 $ModuleName 已加载" -Level Debug -NoConsole
        return $true
    }
    
    $modulePath = Join-Path $Script:ModulesPath "$ModuleName.ps1"
    
    if (-not (Test-Path -Path $modulePath)) {
        Write-Log "无法找到模块: $modulePath" -Level Error
        return $false
    }
    
    try {
        $operation = Start-Operation -Name "导入模块: $ModuleName"

        # 验证模块文件签名(如果启用了签名验证)
        if ($Script:VerifyModuleSignatures) {
            $signature = Get-AuthenticodeSignature -FilePath $modulePath
            if ($signature.Status -ne "Valid") {
                throw "模块签名验证失败: $ModuleName, 状态: $($signature.Status)"
            }
        }

        # 模块以 dot-source 方式加载，函数注入到当前作用域。
        # 各模块末尾的 Export-ModuleMember 在 dot-source 上下文会抛"can only be
        # called from inside a module"。dot-source 期间用同名 function 覆盖此
        # cmdlet（function 在 PS 中优先于 cmdlet），加载完毕再移除覆盖。
        function global:Export-ModuleMember { }
        try {
            . $modulePath
        }
        finally {
            Remove-Item function:\Export-ModuleMember -ErrorAction SilentlyContinue
        }
        $Script:LoadedModules[$ModuleName] = $true
        
        Write-Log "成功导入模块: $ModuleName" -Level Success
        Complete-Operation
        return $true
    }
    catch {
        Register-OperationError -ErrorRecord $_
        Complete-Operation -WithErrors
        return $false
    }
}

# 系统版本检测
function Get-WindowsVersionInfo {
    [CmdletBinding()]
    param()
    
    try {
        $operation = Start-Operation -Name "检测Windows版本"
        
        # 使用CimInstance而不是WMI
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $buildNumber = [int]$osInfo.BuildNumber
        
        $versionInfo = @{
            ProductName = $osInfo.Caption
            BuildNumber = $buildNumber
            Version = $osInfo.Version
            IsWindows11 = $buildNumber -ge 22000
            Is64Bit = [System.Environment]::Is64BitOperatingSystem
            Edition = $osInfo.OperatingSystemSKU
        }
        
        Write-Log "检测到系统: $($versionInfo.ProductName) (Build $buildNumber)" -Level Info
        
        Complete-Operation
        return $versionInfo
    }
    catch {
        Register-OperationError -ErrorRecord $_
        Complete-Operation -WithErrors
        
        # 返回基本信息以避免空引用异常
        return @{
            ProductName = "Unknown"
            BuildNumber = 0
            Version = "Unknown"
            IsWindows11 = $false
            Is64Bit = $false
        }
    }
}

# ==========================================
# 验证模块签名(可选功能)
# ==========================================
$Script:VerifyModuleSignatures = $false  # 默认禁用，未来可扩展

# ==========================================
# 主程序初始化
# ==========================================
Initialize-Logging
$Script:SystemInfo = Get-WindowsVersionInfo

# 导入必要的核心模块
$requiredModules = @(
    "System.Optimizer",
    "Network.Optimizer",
    "Gaming.Optimizer",
    "Temp.Cleaner",
    "Config.Manager",
    "UI.Functions"
)

$moduleLoadErrors = 0
foreach ($module in $requiredModules) {
    if (-not (Import-OptimizationModule -ModuleName $module)) {
        $moduleLoadErrors++
    }
}

if ($moduleLoadErrors -gt 0) {
    Write-Log "警告: $moduleLoadErrors 个模块加载失败，某些功能可能不可用" -Level Warning
}

# 检查是否启用了TestMode
if ($Script:TestModeActive) {
    Write-Log "测试模式已激活 - 所有操作将被记录但不会实际执行" -Level Warning
}

# ==========================================
# 显示主菜单并启动应用程序
# ==========================================
try {
    # 加载配置
    if ($ImportConfig -and $ConfigFile) {
        if (Test-Path $ConfigFile) {
            Import-Configuration -Path $ConfigFile
        }
        else {
            Write-Log "指定的配置文件不存在: $ConfigFile" -Level Error
        }
    }
    elseif (-not $ConfigFile) {
        # 使用默认配置
        Initialize-Configuration
    }
    
    # 这里将通过UI.Functions模块调用Show-MainMenu函数
    if (Get-Command -Name Show-MainMenu -ErrorAction SilentlyContinue) {
        Show-MainMenu
    }
    else {
        Write-Log "找不到主菜单函数，请确保UI.Functions模块已正确加载" -Level Error
    }
    
    # 如果需要导出配置
    if ($ExportConfig) {
        Export-Configuration -Path $ExportConfig
    }
}
catch {
    Write-Log "程序运行时出现错误: $_" -Level Error
    if ($Script:RollbackRequired) {
        Invoke-Rollback
    }
}
finally {
    # 记录程序运行总时间
    $duration = (Get-Date) - $Script:StartTime
    Write-Log "程序运行结束，总耗时: $($duration.TotalSeconds.ToString('0.00'))秒" -Level Info
    
    # 添加摘要信息到日志
    $endSummary = @"

=============================================
运行摘要:
总操作时间: $($duration.TotalSeconds.ToString('0.00'))秒
总错误数: $($Script:ErrorCollection.Count)
=============================================
"@
    
    $endSummary | Out-File -FilePath $Script:LogFile -Encoding UTF8 -Append
} 