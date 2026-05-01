# ==========================================
# UI.Functions.ps1
# 主菜单与交互界面 - 由 WindowsOptimizerPlus.ps1 dot-source 加载
# ==========================================

function Show-Header {
    [CmdletBinding()]
    param(
        [string]$Title = "Windows 优化加强版"
    )
    Clear-Host
    $sysLine = ""
    if ($Script:SystemInfo) {
        $sysLine = "$($Script:SystemInfo.ProductName) (Build $($Script:SystemInfo.BuildNumber))"
    }
    $tmFlag = ""
    if ($Script:TestModeActive) { $tmFlag = "  [测试模式]" }

    Write-Host ""
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host "   $Title  v$($Script:Version)$tmFlag" -ForegroundColor Cyan
    Write-Host "  ============================================" -ForegroundColor Cyan
    if ($sysLine) { Write-Host "  $sysLine" -ForegroundColor DarkGray }
    Write-Host ""
}

function Show-MainMenu {
    [CmdletBinding()]
    param()

    $running = $true
    while ($running) {
        Show-Header
        Write-Host "  请选择功能:" -ForegroundColor White
        Write-Host ""
        Write-Host "    1) 系统优化   (服务/启动项/磁盘/视觉效果/注册表)" -ForegroundColor Green
        Write-Host "    2) 网络优化   (TCP/DNS/MTU/QoS)" -ForegroundColor Green
        Write-Host "    3) 游戏优化   (高性能电源/GameMode/计时器/GPU)" -ForegroundColor Green
        Write-Host "    4) 临时文件清理" -ForegroundColor Green
        Write-Host "    5) 配置管理   (导入/导出/查看)" -ForegroundColor Green
        Write-Host "    6) 系统信息与已加载模块" -ForegroundColor Green
        Write-Host ""
        Write-Host "    0) 退出" -ForegroundColor Red
        Write-Host ""

        $choice = Read-Host "  请输入选项 (0-6)"

        switch ($choice) {
            "1" { Show-OptimizationSubMenu -Title "系统优化" -GetCmd "Get-SystemOptimizations"  -ApplyCmd "Apply-SystemOptimization" }
            "2" { Show-OptimizationSubMenu -Title "网络优化" -GetCmd "Get-NetworkOptimizations" -ApplyCmd "Apply-NetworkOptimization" }
            "3" { Show-OptimizationSubMenu -Title "游戏优化" -GetCmd "Get-GamingOptimizations"  -ApplyCmd "Apply-GamingOptimization" }
            "4" { Show-TempCleanMenu }
            "5" { Show-ConfigMenu }
            "6" { Show-SystemInfoMenu }
            "0" { $running = $false }
            default {
                Write-Host "  无效选择" -ForegroundColor Yellow
                Start-Sleep -Seconds 1
            }
        }
    }

    Write-Host ""
    Write-Host "  感谢使用！" -ForegroundColor Cyan
}

function Show-OptimizationSubMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Title,
        [Parameter(Mandatory)] [string]$GetCmd,
        [Parameter(Mandatory)] [string]$ApplyCmd
    )

    if (-not (Get-Command -Name $GetCmd -ErrorAction SilentlyContinue)) {
        Write-Host "  模块未加载: $GetCmd 不可用" -ForegroundColor Red
        Read-Host "  按 Enter 返回"
        return
    }
    if (-not (Get-Command -Name $ApplyCmd -ErrorAction SilentlyContinue)) {
        Write-Host "  模块未加载: $ApplyCmd 不可用" -ForegroundColor Red
        Read-Host "  按 Enter 返回"
        return
    }

    try {
        $opts = @(& $GetCmd)
    }
    catch {
        Write-Host "  调用 $GetCmd 失败: $_" -ForegroundColor Red
        Read-Host "  按 Enter 返回"
        return
    }

    if (-not $opts -or $opts.Count -eq 0) {
        Write-Host "  当前没有可用的优化项" -ForegroundColor Yellow
        Read-Host "  按 Enter 返回"
        return
    }

    $browsing = $true
    while ($browsing) {
        Show-Header -Title $Title
        for ($i = 0; $i -lt $opts.Count; $i++) {
            $name = $opts[$i].Name
            $desc = ""
            if ($opts[$i].PSObject.Properties.Name -contains 'Description') { $desc = $opts[$i].Description }
            Write-Host ("  {0,3}) {1}" -f ($i + 1), $name) -ForegroundColor Green -NoNewline
            if ($desc) { Write-Host "  - $desc" -ForegroundColor DarkGray } else { Write-Host "" }
        }
        Write-Host ""
        Write-Host "    A) 全部应用" -ForegroundColor Yellow
        Write-Host "    B) 返回主菜单" -ForegroundColor Red
        Write-Host ""
        $sub = Read-Host "  请选择"

        switch -Regex ($sub) {
            '^[Bb]$' { $browsing = $false }
            '^[Aa]$' {
                $confirm = Read-Host "  即将应用全部 $($opts.Count) 项 [$Title]，是否继续? (Y/N)"
                if ($confirm -match '^[Yy]$') {
                    for ($i = 0; $i -lt $opts.Count; $i++) {
                        Write-Host "  -> 正在应用: $($opts[$i].Name)" -ForegroundColor Cyan
                        try { & $ApplyCmd -Index $i } catch { Write-Host "     失败: $_" -ForegroundColor Red }
                    }
                    Read-Host "  全部完成。按 Enter 继续"
                }
            }
            '^\d+$' {
                $idx = [int]$sub - 1
                if ($idx -ge 0 -and $idx -lt $opts.Count) {
                    Write-Host "  -> 正在应用: $($opts[$idx].Name)" -ForegroundColor Cyan
                    try { & $ApplyCmd -Index $idx } catch { Write-Host "     失败: $_" -ForegroundColor Red }
                    Read-Host "  按 Enter 继续"
                }
                else {
                    Write-Host "  序号超出范围" -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                }
            }
            default { }
        }
    }
}

function Show-TempCleanMenu {
    Show-Header -Title "临时文件清理"
    if (-not (Get-Command -Name Get-EstimatedTempSize -ErrorAction SilentlyContinue)) {
        Write-Host "  Temp.Cleaner 模块未加载" -ForegroundColor Red
        Read-Host "  按 Enter 返回"
        return
    }

    Write-Host "  正在估算临时文件大小..." -ForegroundColor Cyan
    try { Get-EstimatedTempSize | Out-Host } catch { Write-Host "  估算失败: $_" -ForegroundColor Yellow }

    Write-Host ""
    $confirm = Read-Host "  开始清理? (Y/N)"
    if ($confirm -match '^[Yy]$') {
        if (Get-Command -Name Start-TempFileCleaning -ErrorAction SilentlyContinue) {
            try { Start-TempFileCleaning } catch { Write-Host "  清理过程出错: $_" -ForegroundColor Red }
        }
        else {
            Write-Host "  Start-TempFileCleaning 不可用" -ForegroundColor Red
        }
    }
    Read-Host "  按 Enter 返回"
}

function Show-ConfigMenu {
    Show-Header -Title "配置管理"
    Write-Host "    1) 导出当前配置到文件" -ForegroundColor Green
    Write-Host "    2) 从文件导入配置" -ForegroundColor Green
    Write-Host "    3) 查看当前配置概览" -ForegroundColor Green
    Write-Host ""
    Write-Host "    0) 返回" -ForegroundColor Red
    Write-Host ""

    $c = Read-Host "  请选择"
    switch ($c) {
        "1" {
            $defaultPath = Join-Path $env:USERPROFILE "Desktop\WinOptConfig.json"
            $p = Read-Host "  导出路径 (回车使用默认: $defaultPath)"
            if ([string]::IsNullOrWhiteSpace($p)) { $p = $defaultPath }
            if (Get-Command -Name Export-Configuration -ErrorAction SilentlyContinue) {
                Export-Configuration -Path $p
            }
            else { Write-Host "  Export-Configuration 不可用" -ForegroundColor Red }
            Read-Host "  按 Enter 返回"
        }
        "2" {
            $p = Read-Host "  配置文件路径"
            if (-not (Test-Path $p)) {
                Write-Host "  文件不存在: $p" -ForegroundColor Yellow
            }
            elseif (Get-Command -Name Import-Configuration -ErrorAction SilentlyContinue) {
                Import-Configuration -Path $p
            }
            else { Write-Host "  Import-Configuration 不可用" -ForegroundColor Red }
            Read-Host "  按 Enter 返回"
        }
        "3" {
            if ($Script:GlobalConfig) {
                $Script:GlobalConfig | ConvertTo-Json -Depth 5 | Out-Host
            }
            else {
                Write-Host "  尚未加载配置" -ForegroundColor Yellow
            }
            Read-Host "  按 Enter 返回"
        }
        "0" { return }
        default { return }
    }
}

function Show-SystemInfoMenu {
    Show-Header -Title "系统信息"
    if ($Script:SystemInfo) {
        $Script:SystemInfo.GetEnumerator() | Sort-Object Name | ForEach-Object {
            Write-Host ("  {0,-15}: {1}" -f $_.Key, $_.Value) -ForegroundColor Gray
        }
    }
    else {
        Write-Host "  系统信息不可用" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "  已加载模块:" -ForegroundColor Cyan
    if ($Script:LoadedModules -and $Script:LoadedModules.Keys.Count -gt 0) {
        foreach ($m in ($Script:LoadedModules.Keys | Sort-Object)) {
            Write-Host "    - $m" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "    (无)" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "  日志文件: $($Script:LogFile)" -ForegroundColor DarkGray
    Read-Host "  按 Enter 返回"
}
