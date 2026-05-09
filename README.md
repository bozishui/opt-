# WinOpt+ — Windows Optimizer Plus

A Windows 10/11 system tuning toolkit written in PowerShell, with a WPF (XAML)
desktop UI front-end. Bundles four optimization modules — **System**, **Network**,
**Gaming**, **Temp Cleanup** — behind a single GUI host or a classic interactive
CLI menu.

> **Status:** the GUI shell is fully wired; "Apply" actions can either run for
> real (with admin elevation) or stay in a no-op **demo mode** for previewing the
> UI without touching the system.

---

## What it does

| Module | What it tunes | Examples |
|---|---|---|
| **System.Optimizer** | Services, startup items, disk, visual effects, registry tweaks | Disable rarely used background services, optimize NTFS / SSD parameters, trim startup entries |
| **Network.Optimizer** | TCP/IP stack, DNS, MTU, QoS | TCP window scaling / autotuning, set low-latency DNS, disable Wi-Fi power saving |
| **Gaming.Optimizer** | Power plan, GPU & timer settings, Game Mode | Unlock the hidden Ultimate Performance plan, disable fullscreen optimizations, raise timer resolution |
| **Temp.Cleaner** | Temp / cache reclamation | Windows + user temp folders, Edge / Chrome / Firefox / IE caches, Windows Update download cache, Prefetch, thumbnail cache, WER reports, recycle bin |

Each module exposes a `Get-*Optimizations` (or `Get-CleanOptions`) function that
enumerates available items and an `Apply-*` (or `Start-TempFileCleaning`)
function that performs the change. The GUI reads the live list from each module
and renders it as a checkbox tree — what you see is what the module exports.

---

## How it works

```
                        ┌──────────────────────────────────────────┐
                        │   Show-OptimizerGUI.ps1  (host process)  │
                        │                                          │
                        │  1. Parse params (-DryRun / -NoElevate)  │
                        │  2. Self-elevate via UAC if needed       │
                        │  3. Load WPF assemblies                  │
                        │  4. Dot-source all Modules/*.ps1         │
                        │  5. Load Resources/MainWindow.xaml       │
                        │  6. Wire button handlers                 │
                        │  7. ShowDialog()                         │
                        └────────────┬─────────────────────────────┘
                                     │
        ┌────────────────────────────┼────────────────────────────┐
        ▼                            ▼                            ▼
  Modules/System.Optimizer   Modules/Network.Optimizer    Modules/Temp.Cleaner
  Get-SystemOptimizations    Get-NetworkOptimizations     Get-CleanOptions
  Apply-SystemOptimization   Apply-NetworkOptimization    Start-TempFileCleaning
```

Key behaviors:

- **Dual mode runtime.** A single switch (`-DryRun`) flips the host between
  *demo* (UI works, every Apply opens a "would have done X" dialog) and *real*
  (clicks call the module functions and modify the system). The default is
  *real mode with auto-elevation*; pass `-DryRun` to preview safely.
- **Auto-elevation.** Real mode re-launches itself via `Start-Process -Verb
  RunAs`. If the user dismisses UAC, the host gracefully degrades to demo mode
  rather than failing.
- **Module fallback.** If a module file is missing or a function fails to
  resolve, the GUI substitutes a small bilingual demo dataset so the interface
  still renders. The status bar shows which modules loaded.
- **Bilingual UI.** Chinese / English are switched at runtime via the language
  buttons in the top banner. Strings are tagged in XAML and resolved through a
  dictionary table — no XAML reload needed.
- **Logging & rollback.** Every operation goes through `Start-Operation` /
  `Complete-Operation`, which push a frame onto an operation stack with an
  optional rollback script-block. Errors call `Register-OperationError`; fatal
  errors trigger `Invoke-Rollback`, which pops the stack and runs each rollback
  in reverse. Logs land in `Logs/GUI_<timestamp>.log`.
- **Confirmation dialogs.** Before any real Apply, a YES/NO dialog lists the
  exact items being changed and recommends creating a system restore point.
  After execution a result dialog reports total / succeeded / failed counts.

---

## Effects / interface

Once launched, the window shows seven pages:

- **Dashboard** — live OS / CPU / RAM / system-drive cards, a demo health
  score, and a *Start scan* button that polls every module's `Get-*` function
  and reports the count of optimizable items found.
- **System / Network / Gaming** — the items returned by the corresponding
  module, rendered as checkboxes with names + descriptions. *Select all*,
  *Clear*, *Apply selected* per page.
- **Temp cleanup** — the cleanup categories from `Get-CleanOptions`, plus an
  estimated reclaimable-space figure. *Clean now* runs `Start-TempFileCleaning`
  with the selected categories and shows freed space.
- **Settings** — toggles for restore-point / registry-backup / auto-update /
  start-with-Windows; quick links to the `Logs/` and `Backups/` folders.
- **About** — version, stack, and credits.

The footer status bar shows current page, admin status (🛡 elevated /
⚠ non-elevated), and module load state.

---

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1 (built-in) **or** PowerShell 7+
- .NET WPF (`PresentationFramework`, ships with Windows)
- Administrator privileges for *real-mode* Apply operations (the GUI will
  trigger UAC automatically)

---

## Download & install

**Option A — One-click installer (recommended):**

1. Download `WinOptPlus-Setup-2.0.0.exe` from the Releases page.
2. Double-click and accept the wizard. Pick *Install for me only* (no admin
   required) or *All users* (admin).
3. Launch via the **WinOpt+** Start-Menu shortcut. UAC will prompt the first
   time you Apply real changes; pick **WinOpt+ (Demo)** to preview without UAC.

The installer pre-clears PowerShell execution policy and Windows
Mark-of-the-Web blocking, so no manual `Unblock-File` or
`Set-ExecutionPolicy` is required.

If you'd rather work from source, both options below still work.

**Option B — git clone:**

```powershell
git clone https://github.com/bozishui/opt-.git
cd opt-
```

**Option C — ZIP download:**

1. Visit <https://github.com/bozishui/opt-> and click **Code → Download ZIP**.
2. Right-click the ZIP → **Properties** → check **Unblock** → **OK** (avoids
   PowerShell's mark-of-the-web execution warning).
3. Extract anywhere, e.g. `C:\Tools\opt-`.

If PowerShell refuses to run the scripts because of execution policy, either
launch with `-ExecutionPolicy Bypass` (shown below) or run once per user:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

---

## Usage

### Launch the GUI (recommended)

```powershell
# Real mode — will trigger UAC and actually apply changes you confirm
powershell -NoProfile -ExecutionPolicy Bypass -File .\Show-OptimizerGUI.ps1

# Demo / preview mode — no UAC, no system changes
powershell -NoProfile -ExecutionPolicy Bypass -File .\Show-OptimizerGUI.ps1 -DryRun

# Already running elevated, skip the auto-elevation step
powershell -NoProfile -ExecutionPolicy Bypass -File .\Show-OptimizerGUI.ps1 -NoElevate
```

GUI flags:

| Flag | Effect |
|---|---|
| *(none)* | Real mode. Self-elevates via UAC. Apply buttons modify the system after a confirmation dialog. |
| `-DryRun` | Demo mode. All Apply / Optimize / Clean buttons show a toast "X was not executed" and never call the module's `Apply-*` functions. |
| `-NoElevate` | Skip auto-elevation. Useful when already in an admin shell or for debugging. |

### Launch the CLI menu

The original interactive console UI is still available:

```powershell
# Must be admin (the script declares #Requires -RunAsAdministrator)
powershell -NoProfile -ExecutionPolicy Bypass -File .\WindowsOptimizerPlus.ps1

# Headless / scripted modes
.\WindowsOptimizerPlus.ps1 -TestMode                          # dry-run, no changes
.\WindowsOptimizerPlus.ps1 -Silent -ConfigFile profile.json   # apply a saved profile
.\WindowsOptimizerPlus.ps1 -ExportConfig profile.json         # export current selection
```

### After running

- **Logs:** every run writes `Logs/GUI_<timestamp>.log` or
  `Logs/WindowsOptimizerPlus_<timestamp>.log` (Settings page → *Open logs
  folder*).
- **Backups:** registry exports and other rollback artifacts are kept under
  `Backups/` (Settings page → *Open backups folder*).
- **Undo:** if an operation fails fatally, the script auto-rolls back the
  current operation stack. Manual undo is via the `Backups/` snapshots.

---

## Project layout

```
opt-/
├── WindowsOptimizerPlus.ps1   # CLI entry point (interactive menu)
├── Show-OptimizerGUI.ps1      # WPF GUI host
├── Resources/
│   └── MainWindow.xaml        # WPF main window definition
├── Modules/
│   ├── System.Optimizer.ps1   # services, startup, registry, visual FX
│   ├── Network.Optimizer.ps1  # TCP / DNS / MTU / QoS
│   ├── Gaming.Optimizer.ps1   # power plan, Game Mode, timer / GPU
│   ├── Temp.Cleaner.ps1       # parallel temp / cache cleanup
│   ├── Config.Manager.ps1     # JSON profile import / export
│   ├── UI.Functions.ps1       # console UI helpers (CLI menu)
│   └── RunOptimizer.ps1       # batch / orchestration helpers
├── Logs/                      # runtime logs (gitignored)
├── Backups/                   # rollback artifacts (gitignored)
└── README.md
```

---

## Safety notes

- Always create a Windows **System Restore Point** before clicking any real
  Apply button. The confirmation dialog reminds you of this each time.
- Tweaks are well-known stable optimizations, but every system is different —
  use **DryRun** to preview, then enable a few categories at a time rather
  than smashing *Boost* on the first run.
- Some Apply operations cannot be undone purely in-process (e.g. service start
  type changes). The `Backups/` folder keeps registry exports for those cases.
- Do not run on a server, a managed corporate device, or anything you can't
  freely reimage.

---

## Development

- The project targets Windows PowerShell 5.1 host syntax — keep modules
  compatible with that runtime (no PowerShell 7-only operators).
- Source files use **UTF-16 LE BOM** so PS 5.1 reads non-ASCII strings
  correctly. Don't re-save them as UTF-8 without a BOM unless you also remove
  every multi-byte character.
- The XAML uses element `Tag` attributes as i18n keys; new strings should be
  added to `Get-UiStrings` in `Show-OptimizerGUI.ps1` for both `zh` and `en`.

---

## License

Use at your own risk. No warranty — see the disclaimer in
`WindowsOptimizerPlus.ps1`.
