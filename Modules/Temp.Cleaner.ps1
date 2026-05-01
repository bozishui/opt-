# ==========================================
# Temp.Cleaner.ps1
# 临时文件清理模块 - 使用并行处理加速临时文件清理操作
# ==========================================

# 清理选项定义
$Script:CleanOptions = @(
    @{Name="Windows临时文件夹"; Path="$env:windir\Temp\*"; Description="清理系统临时文件夹中的所有文件"; Enabled=$true},
    @{Name="用户临时文件夹"; Path="$env:TEMP\*"; Description="清理当前用户的临时文件夹"; Enabled=$true},
    @{Name="Windows更新缓存"; Path="$env:windir\SoftwareDistribution\Download\*"; Description="清理Windows更新下载的文件"; Enabled=$true},
    @{Name="预取文件"; Path="$env:windir\Prefetch\*"; Description="清理Windows预取文件，有助于解决某些应用启动问题"; Enabled=$true},
    @{Name="回收站"; Path="RecycleBin"; Description="清空所有用户的回收站"; Enabled=$true},
    @{Name="IE缓存"; Path="$env:LOCALAPPDATA\Microsoft\Windows\INetCache\*"; Description="清理Internet Explorer浏览器缓存"; Enabled=$true},
    @{Name="IE Cookies"; Path="$env:LOCALAPPDATA\Microsoft\Windows\INetCookies\*"; Description="清理Internet Explorer Cookie（可能会导致登录状态丢失）"; Enabled=$false},
    @{Name="Microsoft Edge缓存"; Path="$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\*"; Description="清理Microsoft Edge浏览器缓存"; Enabled=$true},
    @{Name="Google Chrome缓存"; Path="$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache\*"; Description="清理Google Chrome浏览器缓存"; Enabled=$true},
    @{Name="Firefox缓存"; Path="$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2\*"; Description="清理Firefox浏览器缓存"; Enabled=$true},
    @{Name="缩略图缓存"; Path="$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db"; Description="清理Windows资源管理器的缩略图缓存"; Enabled=$true},
    @{Name="Windows日志文件"; Path="$env:windir\Logs\*"; Description="清理Windows各种日志文件"; Enabled=$false},
    @{Name="Windows错误报告"; Path="$env:LOCALAPPDATA\Microsoft\Windows\WER\*"; Description="清理Windows错误报告文件"; Enabled=$true},
    @{Name="Windows诊断数据"; Path="$env:PROGRAMDATA\Microsoft\Diagnosis\*"; Description="清理Windows诊断数据文件"; Enabled=$false}
)

# 获取临时文件清理选项
function Get-CleanOptions {
    return $Script:CleanOptions
}

# 估计清理前的临时文件总大小
function Get-EstimatedTempSize {
    [CmdletBinding()]
    param (
        [Parameter()]
        [array]$Options = $Script:CleanOptions
    )
    
    $operation = Start-Operation -Name "估计临时文件大小"
    
    try {
        $enabledOptions = $Options | Where-Object { $_.Enabled }
        $totalSize = 0
        
        foreach ($option in $enabledOptions) {
            try {
                if ($option.Path -eq "RecycleBin") {
                    # 回收站大小计算
                    $shell = New-Object -ComObject Shell.Application
                    $recycleBin = $shell.Namespace(0xA)
                    
                    if ($recycleBin) {
                        $items = $recycleBin.Items()
                        foreach ($item in $items) {
                            try {
                                if ($item.Size) {
                                    $totalSize += $item.Size
                                }
                            }
                            catch {
                                # 忽略个别项目的错误
                                Write-Log "无法获取回收站项目大小: $_" -Level Debug -NoConsole
                            }
                        }
                    }
                }
                else {
                    # 常规文件大小计算
                    $size = (Get-ChildItem -Path $option.Path -Recurse -Force -ErrorAction SilentlyContinue | 
                            Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                    
                    if ($size) {
                        $totalSize += $size
                    }
                }
            }
            catch {
                Write-Log "无法估计 $($option.Name) 的大小: $_" -Level Debug -NoConsole
            }
        }
        
        # 转换总大小为更友好的格式
        $sizeInfo = @{
            Bytes = $totalSize
            KB = [Math]::Round($totalSize / 1KB, 2)
            MB = [Math]::Round($totalSize / 1MB, 2)
            GB = [Math]::Round($totalSize / 1GB, 2)
            Formatted = Format-FileSize -SizeInBytes $totalSize
        }
        
        Write-Log "估计需要清理的临时文件总大小: $($sizeInfo.Formatted)" -Level Info
        Complete-Operation
        return $sizeInfo
    }
    catch {
        Register-OperationError -ErrorRecord $_
        Complete-Operation -WithErrors
        
        # 返回默认值
        return @{
            Bytes = 0
            KB = 0
            MB = 0
            GB = 0
            Formatted = "0 B"
        }
    }
}

# 格式化文件大小
function Format-FileSize {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [double]$SizeInBytes
    )
    
    if ($SizeInBytes -ge 1TB) {
        return "$([Math]::Round($SizeInBytes / 1TB, 2)) TB"
    }
    elseif ($SizeInBytes -ge 1GB) {
        return "$([Math]::Round($SizeInBytes / 1GB, 2)) GB"
    }
    elseif ($SizeInBytes -ge 1MB) {
        return "$([Math]::Round($SizeInBytes / 1MB, 2)) MB"
    }
    elseif ($SizeInBytes -ge 1KB) {
        return "$([Math]::Round($SizeInBytes / 1KB, 2)) KB"
    }
    else {
        return "$SizeInBytes B"
    }
}

# 清理单个临时文件选项
function Clear-SingleTempOption {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$Option,
        
        [Parameter()]
        [switch]$Force
    )

    try {
        $result = @{
            Name = $Option.Name
            Success = $false
            SizeCleared = 0
            ErrorMessage = $null
        }
        
        # 检查测试模式
        if ($Script:TestModeActive -and -not $Force) {
            Write-Log "测试模式: 模拟清理 $($Option.Name)" -Level Info
            $result.Success = $true
            return $result
        }
        
        # 获取清理前大小
        $beforeSize = 0
        
        if ($Option.Path -eq "RecycleBin") {
            # 清空回收站
            $shell = New-Object -ComObject Shell.Application
            $items = $shell.Namespace(0xA).items()
            
            if ($items) {
                foreach ($item in $items) {
                    if ($item.Size) {
                        $beforeSize += $item.Size
                    }
                }
                
                # 清空回收站
                $recycler = (New-Object -ComObject Shell.Application).Namespace(0xa)
                $recycler.items() | ForEach-Object { 
                    Remove-Item -Path $_.Path -Recurse -Force -ErrorAction SilentlyContinue 
                }
            }
        }
        else {
            # 普通文件清理
            try {
                $beforeSize = (Get-ChildItem -Path $Option.Path -Recurse -Force -ErrorAction SilentlyContinue | 
                            Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                
                # 确保数值有效
                if ($null -eq $beforeSize) { $beforeSize = 0 }
                
                # 删除文件
                Remove-Item -Path $Option.Path -Recurse -Force -ErrorAction SilentlyContinue
            }
            catch {
                $result.ErrorMessage = $_.Exception.Message
                return $result
            }
        }
        
        $result.Success = $true
        $result.SizeCleared = $beforeSize
        
        return $result
    }
    catch {
        return @{
            Name = $Option.Name
            Success = $false
            SizeCleared = 0
            ErrorMessage = $_.Exception.Message
        }
    }
}

# 并行清理临时文件
function Clear-TempFilesParallel {
    [CmdletBinding()]
    param (
        [Parameter()]
        [array]$Options = $Script:CleanOptions,
        
        [Parameter()]
        [int]$ThrottleLimit = 5,
        
        [Parameter()]
        [switch]$Force
    )
    
    $operation = Start-Operation -Name "并行清理临时文件"
    
    try {
        $enabledOptions = $Options | Where-Object { $_.Enabled }
        
        if ($enabledOptions.Count -eq 0) {
            Write-Log "没有选择任何清理选项" -Level Warning
            Complete-Operation
            return @{
                Success = $true
                SizeCleared = 0
                Details = @()
            }
        }
        
        # 估计清理前总大小
        $sizeInfo = Get-EstimatedTempSize -Options $enabledOptions
        Write-Log "开始清理 $($enabledOptions.Count) 个临时文件项目，预计可释放: $($sizeInfo.Formatted)" -Level Info
        
        # 创建一个并行执行的RunspacePool
        $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $ThrottleLimit, $sessionState, $Host)
        $pool.Open()
        
        $scriptBlock = {
            param($option, $force, $testMode)
            
            # 定义辅助函数（在每个runspace中）
            function Clear-SingleItem {
                param($opt, $forceClean, $isTestMode)
                
                try {
                    $result = @{
                        Name = $opt.Name
                        Success = $false
                        SizeCleared = 0
                        ErrorMessage = $null
                    }
                    
                    # 检查测试模式
                    if ($isTestMode -and -not $forceClean) {
                        $result.Success = $true
                        return $result
                    }
                    
                    # 获取清理前大小
                    $beforeSize = 0
                    
                    if ($opt.Path -eq "RecycleBin") {
                        # 清空回收站
                        $shell = New-Object -ComObject Shell.Application
                        $items = $shell.Namespace(0xA).items()
                        
                        if ($items) {
                            foreach ($item in $items) {
                                if ($item.Size) {
                                    $beforeSize += $item.Size
                                }
                            }
                            
                            # 清空回收站
                            $recycler = (New-Object -ComObject Shell.Application).Namespace(0xa)
                            $recycler.items() | ForEach-Object { 
                                Remove-Item -Path $_.Path -Recurse -Force -ErrorAction SilentlyContinue 
                            }
                        }
                    }
                    else {
                        # 普通文件清理
                        try {
                            $beforeSize = (Get-ChildItem -Path $opt.Path -Recurse -Force -ErrorAction SilentlyContinue | 
                                        Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                            
                            # 确保数值有效
                            if ($null -eq $beforeSize) { $beforeSize = 0 }
                            
                            # 删除文件
                            Remove-Item -Path $opt.Path -Recurse -Force -ErrorAction SilentlyContinue
                        }
                        catch {
                            $result.ErrorMessage = $_.Exception.Message
                            return $result
                        }
                    }
                    
                    $result.Success = $true
                    $result.SizeCleared = $beforeSize
                    
                    return $result
                }
                catch {
                    return @{
                        Name = $opt.Name
                        Success = $false
                        SizeCleared = 0
                        ErrorMessage = $_.Exception.Message
                    }
                }
            }
            
            # 执行清理
            Clear-SingleItem -opt $option -forceClean $force -isTestMode $testMode
        }
        
        # 创建并发任务
        $jobs = @()
        foreach ($option in $enabledOptions) {
            $powershell = [System.Management.Automation.PowerShell]::Create()
            $powershell.RunspacePool = $pool
            
            [void]$powershell.AddScript($scriptBlock)
            [void]$powershell.AddParameter("option", $option)
            [void]$powershell.AddParameter("force", $Force)
            [void]$powershell.AddParameter("testMode", $Script:TestModeActive)
            
            $jobInfo = @{
                PowerShell = $powershell
                Result = $powershell.BeginInvoke()
                Option = $option
            }
            
            $jobs += $jobInfo
            Write-Log "添加清理任务: $($option.Name)" -Level Debug -NoConsole
        }
        
        # 收集结果
        $results = @()
        $totalSizeCleared = 0
        $successCount = 0
        $failureCount = 0
        
        foreach ($job in $jobs) {
            $result = $job.PowerShell.EndInvoke($job.Result)
            $job.PowerShell.Dispose()
            
            if ($result.Success) {
                $successCount++
                $totalSizeCleared += $result.SizeCleared
                $formattedSize = Format-FileSize -SizeInBytes $result.SizeCleared
                Write-Log "成功清理: $($job.Option.Name), 清理了 $formattedSize" -Level Success
            }
            else {
                $failureCount++
                Write-Log "清理失败: $($job.Option.Name), 错误: $($result.ErrorMessage)" -Level Error
            }
            
            $results += $result
        }
        
        # 清理和关闭RunspacePool
        $pool.Close()
        $pool.Dispose()
        
        # 准备结果摘要
        $summary = @{
            Success = ($failureCount -eq 0)
            SizeCleared = $totalSizeCleared
            FormattedSizeCleared = Format-FileSize -SizeInBytes $totalSizeCleared
            SuccessCount = $successCount
            FailureCount = $failureCount
            TotalCount = $enabledOptions.Count
            Details = $results
        }
        
        Write-Log "临时文件清理完成，共释放: $($summary.FormattedSizeCleared)" -Level Success
        Complete-Operation
        return $summary
    }
    catch {
        Register-OperationError -ErrorRecord $_
        Complete-Operation -WithErrors
        
        return @{
            Success = $false
            SizeCleared = 0
            FormattedSizeCleared = "0 B"
            SuccessCount = 0
            FailureCount = 0
            TotalCount = 0
            Details = @()
            Error = $_.Exception.Message
        }
    }
}

# 主清理函数
function Start-TempFileCleaning {
    [CmdletBinding()]
    param (
        [Parameter()]
        [array]$Options,
        
        [Parameter()]
        [switch]$Force,
        
        [Parameter()]
        [int]$ThrottleLimit = 5
    )
    
    $operation = Start-Operation -Name "启动临时文件清理"
    
    try {
        # 如果未指定选项，使用当前启用的选项
        if (-not $Options) {
            $Options = $Script:CleanOptions | Where-Object { $_.Enabled }
        }
        
        # 开始清理
        $result = Clear-TempFilesParallel -Options $Options -ThrottleLimit $ThrottleLimit -Force:$Force
        
        # 日志记录
        $successRate = [Math]::Round(($result.SuccessCount / $result.TotalCount) * 100)
        Write-Log "清理成功率: $successRate% ($($result.SuccessCount)/$($result.TotalCount))" -Level Info
        
        Complete-Operation
        return $result
    }
    catch {
        Register-OperationError -ErrorRecord $_
        Complete-Operation -WithErrors
        return $null
    }
}

# 设置清理选项状态
function Set-CleanOptionState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$OptionName,
        
        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )
    
    $option = $Script:CleanOptions | Where-Object { $_.Name -eq $OptionName }
    
    if ($option) {
        $option.Enabled = $Enabled
        return $true
    }
    
    return $false
}

# 添加自定义清理选项
function Add-CustomCleanOption {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter()]
        [string]$Description = "自定义清理项",
        
        [Parameter()]
        [bool]$Enabled = $true
    )
    
    # 检查是否已存在
    $existing = $Script:CleanOptions | Where-Object { $_.Name -eq $Name }
    
    if ($existing) {
        # 更新现有选项
        $existing.Path = $Path
        $existing.Description = $Description
        $existing.Enabled = $Enabled
    }
    else {
        # 添加新选项
        $newOption = @{
            Name = $Name
            Path = $Path
            Description = $Description
            Enabled = $Enabled
        }
        
        $Script:CleanOptions += $newOption
    }
    
    return $true
}

# 导出功能函数
Export-ModuleMember -Function Get-CleanOptions
Export-ModuleMember -Function Get-EstimatedTempSize
Export-ModuleMember -Function Clear-TempFilesParallel
Export-ModuleMember -Function Start-TempFileCleaning
Export-ModuleMember -Function Set-CleanOptionState
Export-ModuleMember -Function Add-CustomCleanOption 