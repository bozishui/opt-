# WinOpt+ (Windows Optimizer Plus)

PowerShell tooling for Windows 10/11 tuning: system, network, gaming, and temp cleanup modules, plus a WPF demo UI (`Show-OptimizerGUI.ps1`) and main script `WindowsOptimizerPlus.ps1`.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Some operations may require Administrator

## Quick start

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\WindowsOptimizerPlus.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Show-OptimizerGUI.ps1
```

## Layout

- `WindowsOptimizerPlus.ps1` — main entry
- `Show-OptimizerGUI.ps1` — GUI demo host
- `Resources/MainWindow.xaml` — main window
- `Modules/*.ps1` — feature modules

Back up data before use. The demo GUI may not execute all apply actions on the real system.
