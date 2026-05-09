[CmdletBinding()]
param([switch]$OpenOutput)

$ErrorActionPreference = 'Stop'
$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$issFile = Join-Path $here 'WinOptPlus.iss'

$iscc = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $iscc) {
    Write-Host "Inno Setup 6 not found. Install with:" -ForegroundColor Yellow
    Write-Host "  winget install JRSoftware.InnoSetup"  -ForegroundColor Cyan
    exit 1
}

& $iscc $issFile
if ($LASTEXITCODE -ne 0) { throw "ISCC.exe failed with exit code $LASTEXITCODE" }

$outDir = Join-Path $here 'dist'
Write-Host "OK -> $outDir" -ForegroundColor Green
if ($OpenOutput) { Invoke-Item $outDir }
