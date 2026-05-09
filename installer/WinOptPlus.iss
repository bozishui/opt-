; WinOpt+ — Inno Setup script
;
; Build with installer\build.ps1 (which locates ISCC.exe and runs it on this file).
; Output: installer\dist\WinOptPlus-Setup-<version>.exe
;
; Design notes:
;  - PrivilegesRequired=lowest -> default is per-user install (no admin needed
;    just to install). PrivilegesRequiredOverridesAllowed=dialog lets the user
;    pick "All users" if they have admin.
;  - Shortcuts launch powershell.exe directly with -ExecutionPolicy Bypass and
;    -WindowStyle Hidden, so no separate launcher .exe is shipped and PS
;    execution policy can't block the script.
;  - Mark-of-the-Web is stripped from every shipped .ps1/.psm1/.xaml during
;    install via a [Run] step calling Unblock-File.
;  - Real-mode UAC elevation is handled inside Show-OptimizerGUI.ps1 itself.

[Setup]
AppId={{5F89BDF2-77DE-4A3C-A1D5-3353F6EE1428}
AppName=WinOpt+
AppVersion=2.0.0
AppPublisher=WinOpt+ Project
AppPublisherURL=https://github.com/bozishui/opt-
DefaultDirName={autopf}\WinOpt+
DefaultGroupName=WinOpt+
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DisableProgramGroupPage=yes
OutputDir=dist
OutputBaseFilename=WinOptPlus-Setup-2.0.0
Compression=lzma2/ultra
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
; SetupIconFile / UninstallDisplayIcon intentionally omitted - no app icon shipped yet.

[Languages]
Name: "english";           MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Files]
Source: "..\Show-OptimizerGUI.ps1";    DestDir: "{app}";           Flags: ignoreversion
Source: "..\WindowsOptimizerPlus.ps1"; DestDir: "{app}";           Flags: ignoreversion
Source: "..\Modules\*";                DestDir: "{app}\Modules";   Flags: ignoreversion recursesubdirs
Source: "..\Resources\*";              DestDir: "{app}\Resources"; Flags: ignoreversion recursesubdirs
Source: "..\README.md";                DestDir: "{app}";           Flags: ignoreversion

[Tasks]
Name: "desktopicon";  Description: "{cm:CreateDesktopIcon}";                 GroupDescription: "{cm:AdditionalIcons}"
Name: "demoshortcut"; Description: "Also create a Demo (DryRun) shortcut";    GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Icons]
Name: "{group}\WinOpt+"; Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Show-OptimizerGUI.ps1"""; \
  WorkingDir: "{app}"

Name: "{group}\WinOpt+ (Demo)"; Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Show-OptimizerGUI.ps1"" -DryRun"; \
  WorkingDir: "{app}"; Tasks: demoshortcut

Name: "{group}\Uninstall WinOpt+"; Filename: "{uninstallexe}"

Name: "{userdesktop}\WinOpt+"; Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Show-OptimizerGUI.ps1"""; \
  WorkingDir: "{app}"; Tasks: desktopicon

[Run]
; Strip Mark-of-the-Web so SmartScreen / PowerShell don't block the shipped scripts.
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -Command ""Get-ChildItem -LiteralPath '{app}' -Recurse -Include *.ps1,*.psm1,*.xaml | Unblock-File"""; \
  StatusMsg: "Unblocking script files..."; Flags: runhidden

; Optional post-install launch in demo mode (no UAC, safe preview).
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Show-OptimizerGUI.ps1"" -DryRun"; \
  Description: "Launch WinOpt+ in Demo mode"; Flags: postinstall nowait skipifsilent unchecked
