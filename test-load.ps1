# Smoke test: simulate the main script's bootstrap WITHOUT requiring admin and WITHOUT calling Show-MainMenu.
# Verifies that all modules dot-source cleanly and that the expected functions are injected into scope.

$ErrorActionPreference = 'Continue'

# ---- Simulate $Script: state that modules expect ----
$Script:Version = '2.0.0'
$Script:ConfigVersion = '2.0'
$Script:ModulesPath = Join-Path $PSScriptRoot 'Modules'
$Script:LogsPath = Join-Path $PSScriptRoot 'Logs'
$Script:BackupsPath = Join-Path $PSScriptRoot 'Backups'
$Script:LogFile = Join-Path $Script:LogsPath ('TestLoad_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
$Script:StartTime = Get-Date
$Script:ErrorCollection = @()
$Script:OperationStack = New-Object System.Collections.Stack
$Script:RollbackRequired = $false
$Script:TestModeActive = $true
$Script:LoadedModules = @{}
$Script:VerifyModuleSignatures = $false
$Script:SystemInfo = @{
    ProductName = (Get-CimInstance -ClassName Win32_OperatingSystem).Caption
    BuildNumber = [int](Get-CimInstance -ClassName Win32_OperatingSystem).BuildNumber
    Version     = (Get-CimInstance -ClassName Win32_OperatingSystem).Version
    IsWindows11 = [int](Get-CimInstance -ClassName Win32_OperatingSystem).BuildNumber -ge 22000
    Is64Bit     = [System.Environment]::Is64BitOperatingSystem
}

foreach ($p in @($Script:LogsPath, $Script:BackupsPath)) {
    if (-not (Test-Path $p)) { New-Item $p -ItemType Directory -Force | Out-Null }
}

# ---- Stub the helpers the modules call ----
function Write-Log { param([string]$Message, [string]$Level='Info', [switch]$NoConsole) ; if (-not $NoConsole) { Write-Host "[$Level] $Message" -ForegroundColor DarkGray } }
function Start-Operation { param([string]$Name, [scriptblock]$RollbackAction={}) ; @{ Name=$Name; StartTime=Get-Date } }
function Complete-Operation { param([switch]$WithErrors) }
function Register-OperationError { param($ErrorRecord, [switch]$Fatal) ; Write-Host "[StubErr] $($ErrorRecord.Exception.Message)" -ForegroundColor Yellow }
function Invoke-Rollback { }

# ---- Dot-source each module, suppressing Export-ModuleMember stderr ----
$modules = 'System.Optimizer','Network.Optimizer','Gaming.Optimizer','Temp.Cleaner','Config.Manager','UI.Functions'
$loadFails = 0
foreach ($m in $modules) {
    $path = Join-Path $Script:ModulesPath ($m + '.ps1')
    Write-Host ""
    Write-Host "==> Loading $m" -ForegroundColor Cyan
    if (-not (Test-Path $path)) { Write-Host "    NOT FOUND: $path" -ForegroundColor Red; $loadFails++; continue }
    function global:Export-ModuleMember { }
    try {
        . $path
        $Script:LoadedModules[$m] = $true
        Write-Host "    OK" -ForegroundColor Green
    }
    catch {
        Write-Host "    FAIL: $_" -ForegroundColor Red
        $loadFails++
    }
    finally {
        Remove-Item function:\Export-ModuleMember -ErrorAction SilentlyContinue
    }
}

# ---- Verify expected functions are visible ----
Write-Host ""
Write-Host "==> Function visibility check" -ForegroundColor Cyan
$expected = @(
    'Get-SystemOptimizations','Apply-SystemOptimization',
    'Get-NetworkOptimizations','Apply-NetworkOptimization',
    'Get-GamingOptimizations','Apply-GamingOptimization',
    'Get-CleanOptions','Get-EstimatedTempSize','Start-TempFileCleaning',
    'Initialize-Configuration','Save-Configuration','Load-Configuration',
    'Show-MainMenu','Show-Header','Show-OptimizationSubMenu'
)
$missing = 0
foreach ($fn in $expected) {
    if (Get-Command -Name $fn -ErrorAction SilentlyContinue) {
        Write-Host ("    [OK]      {0}" -f $fn) -ForegroundColor Green
    } else {
        Write-Host ("    [MISSING] {0}" -f $fn) -ForegroundColor Red
        $missing++
    }
}

# ---- Try calling the read-only Get-* functions to ensure they execute ----
Write-Host ""
Write-Host "==> Invoking read-only Get-* (no system changes)" -ForegroundColor Cyan
foreach ($fn in 'Get-SystemOptimizations','Get-NetworkOptimizations','Get-GamingOptimizations','Get-CleanOptions') {
    if (Get-Command $fn -ErrorAction SilentlyContinue) {
        try {
            $r = & $fn
            $count = if ($r -is [System.Collections.IEnumerable] -and -not ($r -is [string])) { @($r).Count } else { 1 }
            Write-Host ("    {0}: {1} item(s)" -f $fn, $count) -ForegroundColor Green
        }
        catch {
            Write-Host ("    {0}: invocation failed - {1}" -f $fn, $_.Exception.Message) -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host ("RESULT: load fails = {0}, missing functions = {1}" -f $loadFails, $missing) -ForegroundColor (@('Green','Red')[[int]([bool]($loadFails+$missing))])
