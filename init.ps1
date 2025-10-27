<#
.SYNOPSIS
System initializer for Windows that installs Python 3.11 (with pip), Git, and 1Password.

.DESCRIPTION
Mirrors the functionality of c:\workspace\shell\system-init\init.sh on Windows:
- Detects supported package manager (winget preferred, chocolatey, scoop)
- Performs system package update
- Installs:
    * Python 3.11 (and ensures pip for 3.11)
    * Git (latest stable)
    * 1Password (desktop app)
- Configures Python defaults:
    * Sets py launcher default to Python 3.11
    * Provides a 'python3' shim for shell usage
- Idempotent; safe to re-run
- Logs to: <script-dir>\system-init.log

.PARAMETER Yes
Non-interactive mode. Accepts agreements and suppresses prompts where possible.

.PARAMETER Help
Displays this help.

.EXAMPLE
PS> .\init.ps1 -Yes

.EXAMPLE
PS> pwsh -File .\init.ps1 --yes

.NOTES
- Compatible with Windows PowerShell 5.1 and PowerShell 7+.
- You may need to enable script execution first:
  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
- Run in an elevated session for system-wide changes (PATH updates, ProgramData writes).
- Logs are appended to the file for auditability.

.EXITCODES
0  success
10 unsupported OS or package manager
20 Python 3.11 install failed
21 pip for Python 3.11 install failed
30 Git install failed
40 1Password install failed
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Alias('y')]
    [switch]$Yes,

    [Alias('h')]
    [switch]$Help
)
# Map GNU-style args to PowerShell switches to preserve CLI behavior
if ($args -contains '--yes') { $Yes = $true }
if ($args -contains '--help' -or $args -contains '-h') { $Help = $true }

if ($Help) {
    Get-Help -Detailed
    exit 0
}

$ErrorActionPreference = 'Stop'

# Exit codes (mirroring init.sh)
$EC_UNSUPPORTED = 10
$EC_PYTHON      = 20
$EC_PIP         = 21
$EC_GIT         = 30
$EC_1PASSWORD   = 40

# Script context
$ScriptName = Split-Path -Leaf $PSCommandPath
$ScriptDir  = Split-Path -Parent $PSCommandPath
$LogFile    = Join-Path $ScriptDir 'system-init.log'

# Helpers
function Get-Timestamp { Get-Date -Format 'yyyy-MM-dd HH:mm:ss' }
function Write-Log {
    param(
        [ValidateSet('INFO','WARN','ERROR')] [string]$Level = 'INFO',
        [Parameter(Mandatory)] [string]$Message
    )
    $line = "{0} {1} {2}" -f (Get-Timestamp), $Level, $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}
function Die {
    param([int]$Code, [string]$Message)
    Write-Log -Level 'ERROR' -Message $Message
    exit $Code
}

# OS check
$OnWindows = $PSVersionTable.Platform -eq 'Win32NT' -or
                ($env:OS -like '*Windows*') -or
                ([System.Environment]::OSVersion.Platform -eq 'Win32NT')

if (-not $OnWindows) {
    Die $EC_UNSUPPORTED 'Unsupported OS. This script targets Windows only.'
}

# Elevation check
try {
    $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch {
    $IsAdmin = $false
}

# Network quick check
function Test-Network {
    try {
        $resp = Invoke-WebRequest -Uri 'https://example.com' -Method Head -TimeoutSec 10 -UseBasicParsing
        return $resp.StatusCode -ge 200 -and $resp.StatusCode -lt 400
    } catch {
        return $false
    }
}

# Package manager detection
function Detect-PM {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return 'winget' }
    elseif (Get-Command choco -ErrorAction SilentlyContinue) { return 'choco' }
    elseif (Get-Command scoop -ErrorAction SilentlyContinue) { return 'scoop' }
    else { return 'none' }
}
$PM = Detect-PM

Write-Log -Level 'INFO' -Message "Detected OS: Windows"
Write-Log -Level 'INFO' -Message "Detected package manager: $PM"
if ($PM -eq 'none') {
    Die $EC_UNSUPPORTED 'No supported package manager found (winget/choco/scoop).'
}

# PM helpers
function Update-SystemPackages {
    Write-Log -Level 'INFO' -Message "Updating packages via '$PM'..."
    try {
        switch ($PM) {
            'winget' {
                winget source update | Out-Null
                if ($Yes) {
                    winget upgrade --all --accept-package-agreements --accept-source-agreements --silent | Out-Null
                } else {
                    winget upgrade --all | Out-Null
                }
            }
            'choco' {
                choco upgrade all -y | Out-Null
            }
            'scoop' {
                scoop update | Out-Null
                scoop cleanup | Out-Null
            }
            default {
                Write-Log -Level 'WARN' -Message "Update step skipped for '$PM'."
            }
        }
        Write-Log -Level 'INFO' -Message "System packages updated successfully."
    } catch {
        Write-Log -Level 'WARN' -Message "System update failed via '$PM': $($_.Exception.Message)"
    }
}

# Generic winget installer with candidate IDs
function Install-WithWinget {
    param(
        [Parameter(Mandatory)] [string[]]$CandidateIds,
        [string]$DisplayName = ''
    )
    foreach ($id in $CandidateIds) {
        try {
            winget show -e --id $id | Out-Null
            Write-Log -Level 'INFO' -Message "Installing $DisplayName via winget id '$id'..."
            $extra = @()
            if ($Yes) { $extra += @('--accept-package-agreements','--accept-source-agreements','--silent') }
            winget install -e --id $id $extra | Out-Null
            return $true
        } catch {
            Write-Log -Level 'WARN' -Message "winget id '$id' not available or install failed: $($_.Exception.Message)"
        }
    }
    return $false
}

function Install-WithChoco {
    param(
        [Parameter(Mandatory)] [string]$CommandLine
    )
    try {
        Write-Log -Level 'INFO' -Message "Installing via chocolatey: $CommandLine"
        if ($Yes) {
            Invoke-Expression "choco install $CommandLine -y" | Out-Null
        } else {
            Invoke-Expression "choco install $CommandLine" | Out-Null
        }
        return $true
    } catch {
        Write-Log -Level 'WARN' -Message "choco install failed: $($_.Exception.Message)"
        return $false
    }
}

function Install-WithScoop {
    param(
        [Parameter(Mandatory)] [string]$PackageSpec
    )
    try {
        Write-Log -Level 'INFO' -Message "Installing via scoop: $PackageSpec"
        scoop install $PackageSpec | Out-Null
        return $true
    } catch {
        Write-Log -Level 'WARN' -Message "scoop install failed: $($_.Exception.Message)"
        return $false
    }
}

# Python helpers
function Get-Python311Exe {
    # Try py launcher first
    try {
        $exe = (py -3.11 -c 'import sys; print(sys.executable)' 2>$null)
        if ($exe -and (Test-Path $exe)) { return $exe.Trim() }
    } catch { }

    # Typical install paths
    $candidates = @(
        "$env:ProgramFiles\Python311\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
        "$env:ProgramFiles(x86)\Python311\python.exe"
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }

    # Try PATH resolution
    try {
        $cmd = Get-Command python -ErrorAction SilentlyContinue
        if ($cmd) {
            $ver = & $cmd.Source --version 2>$null
            if ($ver -match '^Python 3\.11') { return $cmd.Source }
        }
    } catch { }
    return $null
}

function Ensure-Pip311 {
    param([string]$Python311Exe)
    Write-Log -Level 'INFO' -Message "Ensuring pip for Python 3.11..."
    try {
        if ($Python311Exe) {
            & $Python311Exe -m pip --version 2>$null | Out-Null
            Write-Log -Level 'INFO' -Message "pip for Python 3.11 already present."
            return
        }
    } catch { }

    try {
        if ($Python311Exe) {
            & $Python311Exe -m ensurepip --upgrade | Out-Null
            Write-Log -Level 'INFO' -Message "pip installed via ensurepip."
            return
        }
    } catch { }

    try {
        Write-Log -Level 'INFO' -Message "Bootstrapping pip via get-pip.py..."
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "get-pip.py"
        Invoke-WebRequest -Uri 'https://bootstrap.pypa.io/get-pip.py' -OutFile $tmp -UseBasicParsing
        if ($Python311Exe) {
            & $Python311Exe $tmp | Out-Null
            Write-Log -Level 'INFO' -Message "pip installed via get-pip.py."
            return
        } else {
            # Fallback to py launcher
            py -3.11 $tmp | Out-Null
            Write-Log -Level 'INFO' -Message "pip installed via get-pip.py using py launcher."
            return
        }
    } catch {
        Die $EC_PIP "Failed to install pip for Python 3.11: $($_.Exception.Message)"
    }
}

function Set-PyLauncherDefaultTo311 {
    # Configure py.ini defaults (user-level; system-level if elevated)
    $content = @(
        '[defaults]',
        'python=3.11'
    )
    try {
        $userIni = Join-Path $env:LOCALAPPDATA 'py.ini'
        Set-Content -Path $userIni -Value $content -Force -Encoding ASCII
        Write-Log -Level 'INFO' -Message "Set user py.ini default to Python 3.11: $userIni"

        if ($IsAdmin -and $env:ProgramData) {
            $sysIni = Join-Path $env:ProgramData 'py.ini'
            Set-Content -Path $sysIni -Value $content -Force -Encoding ASCII
            Write-Log -Level 'INFO' -Message "Set system py.ini default to Python 3.11: $sysIni"
        }
    } catch {
        Write-Log -Level 'WARN' -Message "Failed to set py.ini defaults: $($_.Exception.Message)"
    }
}

function Ensure-UserBinOnPath {
    $userBin = Join-Path $env:USERPROFILE 'bin'
    if (-not (Test-Path $userBin)) {
        New-Item -ItemType Directory -Path $userBin -Force | Out-Null
        Write-Log -Level 'INFO' -Message "Created user bin directory: $userBin"
    }

    # Ensure PATH contains user bin (user-level)
    try {
        $regPath = 'HKCU:\Environment'
        $current = (Get-ItemProperty -Path $regPath -Name Path -ErrorAction SilentlyContinue).Path
        if ($current -and ($current -split ';' | ForEach-Object { $_.Trim() }) -contains $userBin) {
            # Already on PATH
        } else {
            $newPath = if ($current) { "$current;$userBin" } else { $userBin }
            Set-ItemProperty -Path $regPath -Name Path -Value $newPath
            Write-Log -Level 'INFO' -Message "Added user bin to PATH (registry). Restart shell to pick up changes."
        }
    } catch {
        Write-Log -Level 'WARN' -Message "Failed to update PATH in registry: $($_.Exception.Message)"
        try {
            # Fallback (may hit size limits)
            $env:Path = "$env:Path;$userBin"
            Write-Log -Level 'INFO' -Message "Appended user bin to PATH in current session."
        } catch { }
    }
    return $userBin
}

function Add-Python3Shim {
    param([string]$Python311Exe)
    try {
        $userBin = Ensure-UserBinOnPath
        $shim = Join-Path $userBin 'python3.cmd'
        $shimContent = "@echo off`r`npy -3.11 %*`r`n"
        Set-Content -Path $shim -Value $shimContent -Force -Encoding ASCII
        Write-Log -Level 'INFO' -Message "Created python3 shim: $shim"
    } catch {
        Write-Log -Level 'WARN' -Message "Failed to create python3 shim: $($_.Exception.Message)"
    }

    # PowerShell function alias in profile (works in PS sessions)
    try {
        $profilePath = $PROFILE.CurrentUserAllHosts
        if (-not (Test-Path $profilePath)) {
            New-Item -ItemType File -Path $profilePath -Force | Out-Null
        }

        $profileContent = Get-Content -Path $profilePath -ErrorAction SilentlyContinue
        $hasRefreshEnv = ($profileContent -join "`n") -match 'function\s+refreshenv'

        if (-not $hasRefreshEnv) {
            Add-Content -Path $profilePath -Value @'
function refreshenv {
    try {
        $machinePath = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" -Name Path -ErrorAction SilentlyContinue).Path
        $userPath    = (Get-ItemProperty -Path "HKCU:\Environment" -Name Path -ErrorAction SilentlyContinue).Path
        $combined    = ($machinePath, $userPath) -join ";"
        if ($combined) { $env:Path = $combined }
        Write-Host "Refreshed PATH for current session."
    } catch {
        Write-Host ("Failed to refresh PATH from registry: " + $_.Exception.Message)
    }
}
'@
            Write-Log -Level 'INFO' -Message "Persisted 'refreshenv' function to PowerShell profile: $profilePath"
        } else {
            Write-Log -Level 'INFO' -Message "PowerShell profile already contains 'refreshenv' function."
        }
    } catch {
        Write-Log -Level 'WARN' -Message "Failed to persist 'refreshenv' function: $($_.Exception.Message)"
    }
}
function Invoke-PostInit {
    Write-Log -Level 'INFO' -Message "Post-init: refreshing environment and validating setup"

    # Attempt to refresh PATH/env for current session
    Refresh-Environment

    # Ensure a convenient refresh helper exists for future sessions
    Ensure-RefreshEnvAlias

    # Verify Python 3.11 and pip
    try {
        $pyExe = Get-Python311Exe
        if ($pyExe) {
            $pyVer = (& $pyExe --version 2>$null)
            Write-Log -Level 'INFO' -Message "Python 3.11 detected: $pyVer ($pyExe)"

            try {
                $pipVer = (& $pyExe -m pip --version 2>$null)
                if ($pipVer) {
                    Write-Log -Level 'INFO' -Message "pip for Python 3.11 detected: $pipVer"
                } else {
                    Write-Log -Level 'WARN' -Message "pip for Python 3.11 not found."
                }
            } catch {
                Write-Log -Level 'WARN' -Message "pip check failed: $($_.Exception.Message)"
            }
        } else {
            Write-Log -Level 'WARN' -Message "Python 3.11 executable not found after install."
        }
    } catch {
        Write-Log -Level 'WARN' -Message "Python verification failed: $($_.Exception.Message)"
    }

    # Validate python3 shim (cmd) and resolution
    try {
        $userBin = Join-Path $env:USERPROFILE 'bin'
        $shim    = Join-Path $userBin 'python3.cmd'
        if (Test-Path $shim) {
            $python3Ver = (& python3 --version 2>$null)
            if ($python3Ver -match '^Python 3\.11') {
                Write-Log -Level 'INFO' -Message "python3 shim OK: $python3Ver"
            } else {
                Write-Log -Level 'WARN' -Message "python3 shim present but does not resolve to Python 3.11 (current: '${python3Ver}')"
            }
        } else {
            Write-Log -Level 'WARN' -Message "python3 shim not found at: $shim"
        }
    } catch {
        Write-Log -Level 'WARN' -Message "python3 shim verification failed: $($_.Exception.Message)"
    }

    # Verify Git
    try {
        $gitCmd = Get-Command git -ErrorAction SilentlyContinue
        if ($gitCmd) {
            Write-Log -Level 'INFO' -Message ("Git detected: " + (& $gitCmd.Source --version 2>$null))
        } else {
            $gitExe = Get-GitExe
            if ($gitExe) {
                Write-Log -Level 'INFO' -Message ("Git detected: " + (& $gitExe --version 2>$null))
            } else {
                Write-Log -Level 'WARN' -Message "Git not found after install."
            }
        }
    } catch {
        Write-Log -Level 'WARN' -Message "Git verification failed: $($_.Exception.Message)"
    }

    # Verify 1Password Desktop
    try {
        if (Test-1PasswordInstalled) {
            Write-Log -Level 'INFO' -Message "1Password Desktop present."
        } else {
            Write-Log -Level 'WARN' -Message "1Password Desktop not detected."
        }
    } catch {
        Write-Log -Level 'WARN' -Message "1Password Desktop check failed: $($_.Exception.Message)"
    }

    # Verify 1Password CLI ('op')
    try {
        $opCmd = Get-Command op -ErrorAction SilentlyContinue
        if ($opCmd) {
            Write-Log -Level 'INFO' -Message ("1Password CLI detected: " + (& $opCmd.Source --version 2>$null))
        } else {
            $opExe = Get-OpExe
            if ($opExe) {
                Write-Log -Level 'INFO' -Message ("1Password CLI detected: " + (& $opExe --version 2>$null))
            } else {
                Write-Log -Level 'WARN' -Message "1Password CLI ('op') not detected."
            }
        }
    } catch {
        Write-Log -Level 'WARN' -Message "1Password CLI verification failed: $($_.Exception.Message)"
    }

    Write-Log -Level 'INFO' -Message "Post-init verification complete. If new tools were added to PATH, restart your shell."
    # Optional: return a simple success flag
}

function Add-Python3Shim {
    param([string]$Python311Exe)
    try {
        $userBin = Ensure-UserBinOnPath
        $shim = Join-Path $userBin 'python3.cmd'
        $shimContent = "@echo off`r`npy -3.11 %*`r`n"
        Set-Content -Path $shim -Value $shimContent -Force -Encoding ASCII
        Write-Log -Level 'INFO' -Message "Created python3 shim: $shim"
    } catch {
        Write-Log -Level 'WARN' -Message "Failed to create python3 shim: $($_.Exception.Message)"
    }

    # PowerShell function alias in profile (works in PS sessions)
    try {
        $profilePath = $PROFILE.CurrentUserAllHosts
        if (-not (Test-Path $profilePath)) {
            New-Item -ItemType File -Path $profilePath -Force | Out-Null
        }
        $profileContent = Get-Content -Path $profilePath -ErrorAction SilentlyContinue
        if (-not ($profileContent -join "`n" -match 'function\s+python3')) {
            Add-Content -Path $profilePath -Value @'
function python3 { param([Parameter(ValueFromRemainingArguments=$true)][object[]]$Args) py -3.11 $Args }
'@
            Write-Log -Level 'INFO' -Message "Added 'python3' function to PowerShell profile: $profilePath"
        } else {
            Write-Log -Level 'INFO' -Message "PowerShell profile already contains a 'python3' function."
        }
    } catch {
        Write-Log -Level 'WARN' -Message "Failed to update PowerShell profile: $($_.Exception.Message)"
    }
}

# Installers
function Install-Python311 {
    $existing = Get-Python311Exe
    if ($existing) {
        Write-Log -Level 'INFO' -Message "Python 3.11 already installed: $existing"
        Ensure-Pip311 -Python311Exe $existing
        Set-PyLauncherDefaultTo311
        Add-Python3Shim -Python311Exe $existing
        return
    }

    Write-Log -Level 'INFO' -Message "Installing Python 3.11..."
    Update-SystemPackages

    $ok = $false
    switch ($PM) {
        'winget' {
            $ok = Install-WithWinget -CandidateIds @(
                'Python.Python.3.11',
                'Python.Python.3.11-x64',
                'Python.Python.3.11-arm64',
                'Python.Python.3.11-x86'
            ) -DisplayName 'Python 3.11'
        }
        'choco' {
            # Chocolatey "python" supports version range; install 3.11.*
            $ok = Install-WithChoco -CommandLine 'python --version 3.11.*'
        }
        'scoop' {
            # Scoop supports versioned buckets; may need main/extras buckets
            try { scoop bucket add versions | Out-Null } catch { }
            $ok = Install-WithScoop -PackageSpec 'python@3.11'
            if (-not $ok) { $ok = Install-WithScoop -PackageSpec 'python' } # fallback (latest)
        }
    }

    if (-not $ok) {
        Die $EC_PYTHON 'python3.11 not available via the detected package manager.'
    }

    # Verify install and proceed
    $exe = Get-Python311Exe
    if (-not $exe) {
        Die $EC_PYTHON 'Python 3.11 installation reported success, but executable not found.'
    }
    Write-Log -Level 'INFO' -Message ("Installed: " + (& $exe --version))

    Ensure-Pip311 -Python311Exe $exe
    Set-PyLauncherDefaultTo311
    Add-Python3Shim -Python311Exe $exe
}

function Refresh-Environment {
    # Use Chocolatey 'refreshenv' if available
    try {
        if (Get-Command refreshenv -ErrorAction SilentlyContinue) {
            refreshenv | Out-Null
            Write-Log -Level 'INFO' -Message 'Refreshed environment via refreshenv.'
            return
        }
    } catch { }

    # Rebuild PATH from registry for current session
    try {
        $machinePath = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name Path -ErrorAction SilentlyContinue).Path
        $userPath    = (Get-ItemProperty -Path 'HKCU:\Environment' -Name Path -ErrorAction SilentlyContinue).Path
        $combined    = ($machinePath, $userPath) -join ';'
        if ($combined) { $env:Path = $combined }
        Write-Log -Level 'INFO' -Message 'Refreshed PATH for current session.'
    } catch {
        Write-Log -Level 'WARN' -Message "Failed to refresh PATH: $($_.Exception.Message)"
    }

    # Broadcast environment change to other processes (new sessions pick it up)
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class NativeMethods {
public const int HWND_BROADCAST = 0xffff;
public const int WM_SETTINGCHANGE = 0x001A;
[DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, int Msg, IntPtr wParam, string lParam, int fuFlags, int uTimeout, out IntPtr lpdwResult);
}
"@ -ErrorAction SilentlyContinue | Out-Null
        [NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [IntPtr]::Zero, 'Environment', 0, 1000, [ref][IntPtr]::Zero) | Out-Null
    } catch { }
}

function Install-Git {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Log -Level 'INFO' -Message ("Git already installed: " + (& git --version))
        return
    }
    Write-Log -Level 'INFO' -Message "Installing Git..."
    Update-SystemPackages

    $ok = $false
    switch ($PM) {
        'winget' { $ok = Install-WithWinget -CandidateIds @('Git.Git') -DisplayName 'Git' }
        'choco'  { $ok = Install-WithChoco  -CommandLine 'git' }
        'scoop'  { $ok = Install-WithScoop  -PackageSpec 'git' }
    }
    if (-not $ok) {
        Die $EC_GIT 'Failed to install Git.'
    }

    # Refresh current session environment so PATH changes are picked up
    Refresh-Environment

    # Try resolving git from PATH; fall back to common install locations
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCmd) {
        Write-Log -Level 'INFO' -Message ("Git installed: " + (& $gitCmd.Source --version))
        return
    }

    $gitExe = Get-GitExe
    if ($gitExe) {
        # Prepend containing directory to PATH for this session
        $gitDir = Split-Path -Parent $gitExe
        if ($gitDir -and ($env:Path -split ';' | Where-Object { $_.Trim() -eq $gitDir }).Count -eq 0) {
            $env:Path = "$gitDir;$env:Path"
            Write-Log -Level 'INFO' -Message "Added '$gitDir' to PATH for current session."
        }
        Write-Log -Level 'INFO' -Message ("Git installed: " + (& $gitExe --version))
    } else {
        Die $EC_GIT 'Git installation completed, but executable not found in PATH or known locations.'
    }
}

function Get-GitExe {
    $candidates = @(
        "$env:ProgramFiles\Git\cmd\git.exe",
        "$env:ProgramFiles\Git\bin\git.exe",
        "$env:ProgramFiles\Git\mingw64\bin\git.exe",
        "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\git.exe",
        "$env:ProgramData\chocolatey\bin\git.exe",
        (Join-Path $env:USERPROFILE 'scoop\apps\git\current\bin\git.exe'),
        (Join-Path $env:USERPROFILE 'scoop\apps\git\current\mingw64\bin\git.exe')
    )
    foreach ($p in $candidates) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    try {
        $cmd = Get-Command git -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    } catch { }
    return $null
}

function Get-OpExe {
    $candidates = @(
        "$env:ProgramFiles\1Password CLI\op.exe",
        "$env:LOCALAPPDATA\Programs\1Password CLI\op.exe",
        "$env:LOCALAPPDATA\1Password\op.exe",
        "$env:ProgramData\chocolatey\bin\op.exe",
        (Join-Path $env:USERPROFILE 'scoop\apps\1password-cli\current\op.exe'),
        (Join-Path $env:USERPROFILE 'scoop\apps\op\current\op.exe')
    )
    foreach ($p in $candidates) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    try {
        $cmd = Get-Command op -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    } catch { }
    return $null
}

function Test-1PasswordInstalled {
    # 1Password desktop app typical paths
    $paths = @(
        "$env:ProgramFiles\1Password\1Password.exe",
        "$env:ProgramFiles\1Password 8\1Password.exe",
        "$env:LOCALAPPDATA\1Password\app\1Password.exe", # user install
        "$env:LOCALAPPDATA\Programs\1Password\1Password.exe"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $true }
    }
    # Try winget list
    try {
        $out = winget list 1Password 2>$null
        if ($out -match '1Password') { return $true }
    } catch { }
    return $false
}

function Install-1Password {
    if (Test-1PasswordInstalled) {
        Write-Log -Level 'INFO' -Message "1Password already installed."
        return
    }

    Write-Log -Level 'INFO' -Message "Installing 1Password (desktop)..."
    Update-SystemPackages

    $ok = $false
    switch ($PM) {
        'winget' {
            # Try likely IDs
            $ok = Install-WithWinget -CandidateIds @(
                'AgileBits.1Password',
                '1Password.1Password'
            ) -DisplayName '1Password'
        }
        'choco' {
            # Chocolatey package name can vary; try direct
            $ok = Install-WithChoco -CommandLine '1password'
            if (-not $ok) { $ok = Install-WithChoco -CommandLine 'onepassword' }
        }
        'scoop' {
            # Scoop often only has CLI 'op'; install desktop via winget recommended
            Write-Log -Level 'WARN' -Message "Scoop may not provide 1Password desktop; consider winget/choco."
            $ok = $false
        }
    }

    if (-not $ok -and -not (Test-1PasswordInstalled)) {
        Die $EC_1PASSWORD '1Password installation failed or package not found.'
    }

    if (Test-1PasswordInstalled) {
        Write-Log -Level 'INFO' -Message "1Password installed successfully."
    } else {
        Die $EC_1PASSWORD '1Password installation did not produce the desktop executable.'
    }
}

function Test-1PasswordCLIInstalled {
    $exe = Get-OpExe
    return [bool]$exe
}
function Install-1PasswordCLI {
    if (Test-1PasswordCLIInstalled) {
        Write-Log -Level 'INFO' -Message "1Password CLI already installed."
        return
    }

    Write-Log -Level 'INFO' -Message "Installing 1Password CLI..."
    Update-SystemPackages

    $ok = $false
    switch ($PM) {
        'winget' {
            $ok = Install-WithWinget -CandidateIds @(
                'AgileBits.1Password.CLI',
                '1Password.1PasswordCLI'
            ) -DisplayName '1Password CLI'
        }
        'choco' {
            $ok = Install-WithChoco -CommandLine '1password-cli'
            if (-not $ok) { $ok = Install-WithChoco -CommandLine 'op' }
        }
        'scoop' {
            try { scoop bucket add extras | Out-Null } catch { }
            $ok = Install-WithScoop -PackageSpec '1password-cli'
            if (-not $ok) { $ok = Install-WithScoop -PackageSpec 'op' }
        }
    }

    if (-not $ok -and -not (Test-1PasswordCLIInstalled)) {
        Die $EC_1PASSWORD '1Password CLI installation failed or package not found.'
    }

    Refresh-Environment

    $opCmd = Get-Command op -ErrorAction SilentlyContinue
    if ($opCmd) {
        Write-Log -Level 'INFO' -Message ("1Password CLI installed: " + (& $opCmd.Source --version))
        return
    }

    $opExe = Get-OpExe
    if ($opExe) {
        $opDir = Split-Path -Parent $opExe
        if ($opDir -and ($env:Path -split ';' | Where-Object { $_.Trim() -eq $opDir }).Count -eq 0) {
            $env:Path = "$opDir;$env:Path"
            Write-Log -Level 'INFO' -Message "Added '$opDir' to PATH for current session."
        }
        Write-Log -Level 'INFO' -Message ("1Password CLI installed: " + (& $opExe --version))
    } else {
        Die $EC_1PASSWORD '1Password CLI installation completed, but executable not found in PATH or known locations.'
    }
}

# Main execution (script scope)
Write-Log -Level 'INFO' -Message "Log file: $LogFile"
if (-not (Test-Network)) {
    Write-Log -Level 'WARN' -Message "Network check failed or web requests blocked. Proceeding; downloads may fail."
}

Write-Log -Level 'INFO' -Message "Pre-flight: Updating system packages"
Update-SystemPackages

Write-Log -Level 'INFO' -Message "Step 1/3: Installing Python 3.11 + pip"
Install-Python311

Write-Log -Level 'INFO' -Message "Step 2/3: Installing Git"
Install-Git

Write-Log -Level 'INFO' -Message "Step 3/3: Installing 1Password"
Install-1Password

Write-Log -Level 'INFO' -Message "Post-init: Validating environment and configuration"
Invoke-PostInit

Write-Log -Level 'INFO' -Message "Script completed successfully."
exit 0