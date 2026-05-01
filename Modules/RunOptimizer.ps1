# 检查管理员权限
function Test-Administrator {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# 如果不是管理员，提示用户
if (-not (Test-Administrator)) {
    Write-Host "此脚本需要管理员权限才能正常运行所有功能！" -ForegroundColor Red
    Write-Host "请右键点击PowerShell，选择'以管理员身份运行'，然后再次运行此脚本。" -ForegroundColor Yellow
    Read-Host "按Enter键退出"
    exit
}

# 设置脚本执行策略
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# 定义脚本所在路径
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrEmpty($ScriptPath)) {
    $ScriptPath = $PSScriptRoot
}
if ([string]::IsNullOrEmpty($ScriptPath)) {
    $ScriptPath = "."
}

# 设置模块路径
$ModulePath = Join-Path $ScriptPath "Modules"

# 导入模块
$NetworkModulePath = Join-Path $ModulePath "Network.Optimizer.ps1"
$GamingModulePath = Join-Path $ModulePath "Gaming.Optimizer.ps1"
$SystemModulePath = Join-Path $ModulePath "System.Optimizer.ps1"

# 导入模块
if (Test-Path $NetworkModulePath) { . $NetworkModulePath }
if (Test-Path $GamingModulePath) { . $GamingModulePath }
if (Test-Path $SystemModulePath) { . $SystemModulePath }

# 检查模块是否成功加载
$modulesLoaded = $true
if (-not (Get-Command -Name Get-NetworkOptimizations -ErrorAction SilentlyContinue)) {
    Write-Host "无法加载网络优化模块！" -ForegroundColor Red
    $modulesLoaded = $false
}
if (-not (Get-Command -Name Get-GamingOptimizations -ErrorAction SilentlyContinue)) {
    Write-Host "无法加载游戏优化模块！" -ForegroundColor Red
    $modulesLoaded = $false
}
if (-not (Get-Command -Name Get-SystemOptimizations -ErrorAction SilentlyContinue)) {
    Write-Host "无法加载系统优化模块！" -ForegroundColor Red
    $modulesLoaded = $false
}

if (-not $modulesLoaded) {
    Write-Host "请确保优化模块文件位于正确位置: $ModulePath" -ForegroundColor Yellow
    Read-Host "按Enter键退出"
    exit
}

# 创建菜单函数
function Show-Menu {
    Clear-Host
    Write-Host "======= Windows优化工具 =======" -ForegroundColor Cyan
    Write-Host 
    Write-Host "1: 系统优化" -ForegroundColor Green
    Write-Host "2: 游戏优化" -ForegroundColor Green
    Write-Host "3: 网络优化" -ForegroundColor Green
    Write-Host "4: 全部优化 (仅推荐用于新系统)" -ForegroundColor Yellow
    Write-Host "0: 退出" -ForegroundColor Red
    Write-Host 
    Write-Host "==========================" -ForegroundColor Cyan
}

# 显示优化选项列表
function Show-OptimizationList {
    param (
        [string]$Title,
        [array]$Options
    )
    
    Clear-Host
    Write-Host "======= $Title =======" -ForegroundColor Cyan
    Write-Host 
    
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host "$($i+1): $($Options[$i].Name) - $($Options[$i].Description)" -ForegroundColor Green
    }
    
    Write-Host "A: 应用所有优化" -ForegroundColor Yellow
    Write-Host "B: 返回主菜单" -ForegroundColor Red
    Write-Host 
    Write-Host "==========================" -ForegroundColor Cyan
}

# 主循环
$running = $true
while ($running) {
    Show-Menu
    $choice = Read-Host "请选择要执行的操作 (0-4)"
    
    switch ($choice) {
        "1" {
            $systemOpts = Get-SystemOptimizations
            $selecting = $true
            
            while ($selecting) {
                Show-OptimizationList -Title "系统优化选项" -Options $systemOpts
                $subChoice = Read-Host "请选择要应用的优化 (1-$($systemOpts.Count), A=全部, B=返回)"
                
                if ($subChoice -eq "B") {
                    $selecting = $false
                }
                elseif ($subChoice -eq "A") {
                    Write-Host "正在应用所有系统优化..." -ForegroundColor Cyan
                    for ($i = 0; $i -lt $systemOpts.Count; $i++) {
                        Write-Host "正在应用: $($systemOpts[$i].Name)" -ForegroundColor Yellow
                        Apply-SystemOptimization -Index $i
                    }
                    Read-Host "按Enter键继续"
                }
                elseif ([int]::TryParse($subChoice, [ref]$null)) {
                    $index = [int]$subChoice - 1
                    if ($index -ge 0 -and $index -lt $systemOpts.Count) {
                        Write-Host "正在应用: $($systemOpts[$index].Name)" -ForegroundColor Yellow
                        Apply-SystemOptimization -Index $index
                        Read-Host "按Enter键继续"
                    }
                }
            }
        }
        "2" {
            $gamingOpts = Get-GamingOptimizations
            $selecting = $true
            
            while ($selecting) {
                Show-OptimizationList -Title "游戏优化选项" -Options $gamingOpts
                $subChoice = Read-Host "请选择要应用的优化 (1-$($gamingOpts.Count), A=全部, B=返回)"
                
                if ($subChoice -eq "B") {
                    $selecting = $false
                }
                elseif ($subChoice -eq "A") {
                    Write-Host "正在应用所有游戏优化..." -ForegroundColor Cyan
                    for ($i = 0; $i -lt $gamingOpts.Count; $i++) {
                        Write-Host "正在应用: $($gamingOpts[$i].Name)" -ForegroundColor Yellow
                        Apply-GamingOptimization -Index $i
                    }
                    Read-Host "按Enter键继续"
                }
                elseif ([int]::TryParse($subChoice, [ref]$null)) {
                    $index = [int]$subChoice - 1
                    if ($index -ge 0 -and $index -lt $gamingOpts.Count) {
                        Write-Host "正在应用: $($gamingOpts[$index].Name)" -ForegroundColor Yellow
                        Apply-GamingOptimization -Index $index
                        Read-Host "按Enter键继续"
                    }
                }
            }
        }
        "3" {
            $networkOpts = Get-NetworkOptimizations
            $selecting = $true
            
            while ($selecting) {
                Show-OptimizationList -Title "网络优化选项" -Options $networkOpts
                $subChoice = Read-Host "请选择要应用的优化 (1-$($networkOpts.Count), A=全部, B=返回)"
                
                if ($subChoice -eq "B") {
                    $selecting = $false
                }
                elseif ($subChoice -eq "A") {
                    Write-Host "正在应用所有网络优化..." -ForegroundColor Cyan
                    for ($i = 0; $i -lt $networkOpts.Count; $i++) {
                        Write-Host "正在应用: $($networkOpts[$i].Name)" -ForegroundColor Yellow
                        Apply-NetworkOptimization -Index $i
                    }
                    Read-Host "按Enter键继续"
                }
                elseif ([int]::TryParse($subChoice, [ref]$null)) {
                    $index = [int]$subChoice - 1
                    if ($index -ge 0 -and $index -lt $networkOpts.Count) {
                        Write-Host "正在应用: $($networkOpts[$index].Name)" -ForegroundColor Yellow
                        Apply-NetworkOptimization -Index $index
                        Read-Host "按Enter键继续"
                    }
                }
            }
        }
        "4" {
            Write-Host "警告: 即将应用所有优化选项！这将修改系统的多个设置，建议仅用于新安装的系统。" -ForegroundColor Red
            $confirm = Read-Host "确定要继续吗? (Y/N)"
            
            if ($confirm -eq "Y" -or $confirm -eq "y") {
                # 系统优化
                $systemOpts = Get-SystemOptimizations
                Write-Host "正在应用所有系统优化..." -ForegroundColor Cyan
                for ($i = 0; $i -lt $systemOpts.Count; $i++) {
                    Write-Host "正在应用: $($systemOpts[$i].Name)" -ForegroundColor Yellow
                    Apply-SystemOptimization -Index $i
                }
                
                # 游戏优化
                $gamingOpts = Get-GamingOptimizations
                Write-Host "正在应用所有游戏优化..." -ForegroundColor Cyan
                for ($i = 0; $i -lt $gamingOpts.Count; $i++) {
                    Write-Host "正在应用: $($gamingOpts[$i].Name)" -ForegroundColor Yellow
                    Apply-GamingOptimization -Index $i
                }
                
                # 网络优化
                $networkOpts = Get-NetworkOptimizations
                Write-Host "正在应用所有网络优化..." -ForegroundColor Cyan
                for ($i = 0; $i -lt $networkOpts.Count; $i++) {
                    Write-Host "正在应用: $($networkOpts[$i].Name)" -ForegroundColor Yellow
                    Apply-NetworkOptimization -Index $i
                }
                
                Write-Host "所有优化已完成！建议重启计算机以使所有设置生效。" -ForegroundColor Green
                Read-Host "按Enter键继续"
            }
        }
        "0" {
            $running = $false
        }
    }
}

Write-Host "感谢使用Windows优化工具！" -ForegroundColor Cyan