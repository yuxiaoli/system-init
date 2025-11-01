@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: =============================================================================
:: System Initializer for Windows (Batch)
:: =============================================================================
:: SYNOPSIS
::   Installs Python 3.11 (with pip), Git, 1Password (desktop), and 1Password CLI.
::   Mirrors behavior of c:\workspace\shell\system-init\init.ps1 for CMD environments.
::
:: USAGE
::   init.bat --yes
::   init.bat --no-update
::   init.bat --help
::
:: PARAMETERS
::   --yes, -y       Non-interactive mode; accepts agreements and reduces prompts.
::   --help, -h      Show help.
::   --no-update     Skip pre-update of system packages.
::
:: EXIT CODES (same as init.ps1)
::   0   success
::   10  unsupported OS or package manager
::   20  Python 3.11 install failed
::   21  pip for Python 3.11 install failed
::   30  Git install failed
::   40  1Password install failed
::
:: LOGGING
::   Appends to %SCRIPT_DIR%\system-init.log, printing lines as:
::   YYYY-MM-DD HH:MM:SS LEVEL message
::
:: SECURITY CHECKS
::   - Requires OP_SERVICE_ACCOUNT_TOKEN to proceed; otherwise exits early.
::   - Admin detection for system-level changes (ProgramData writes).
::   - Restrictive ACL for SSH private key written by post-init.
::
:: VERSION CONTROL / MODIFICATION HISTORY
::   Version: 1.0.0
::   Created: 2025-11-01
::   Modified: 2025-11-01
::   VCS Commit: auto-detected via `git rev-parse --short HEAD` if available.
:: =============================================================================

:: -----------------------------
:: Script context and defaults
:: -----------------------------
set "SCRIPT_NAME=%~nx0"
set "SCRIPT_DIR=%~dp0"
set "LOG_FILE=%SCRIPT_DIR%system-init.log"

:: Exit codes
set "EC_UNSUPPORTED=10"
set "EC_PYTHON=20"
set "EC_PIP=21"
set "EC_GIT=30"
set "EC_1PASSWORD=40"

:: Flags
set "YES=0"
set "HELP=0"
set "NOUPDATE=0"

:: -----------------------------
:: Arg parsing (GNU-style flags)
:: -----------------------------
:parse_args
if "%~1"=="" goto after_parse
if /I "%~1"=="--yes"       set "YES=1" & shift & goto parse_args
if /I "%~1"=="-y"          set "YES=1" & shift & goto parse_args
if /I "%~1"=="--help"      set "HELP=1" & shift & goto parse_args
if /I "%~1"=="-h"          set "HELP=1" & shift & goto parse_args
if /I "%~1"=="--no-update" set "NOUPDATE=1" & shift & goto parse_args
shift
goto parse_args
:after_parse

if "%HELP%"=="1" (
    echo.
    echo Usage: %SCRIPT_NAME% [--yes|-y] [--no-update] [--help|-h]
    echo.
    echo Installs Python 3.11 (+pip), Git, 1Password desktop, and 1Password CLI.
    echo Logs to: %LOG_FILE%
    echo Exit codes: 0 success, 10 unsupported, 20 py311 failed, 21 pip failed, 30 git failed, 40 1Password failed
    exit /b 0
)

:: -----------------------------
:: Helpers
:: -----------------------------
:timestamp
for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"`) do set "TS=%%T"
exit /b 0

:log
set "LEVEL=%~1"
shift
set "MSG=%*"
call :timestamp
echo %TS% %LEVEL% %MSG%
>>"%LOG_FILE%" echo %TS% %LEVEL% %MSG%
exit /b 0

:die
set "CODE=%~1"
shift
set "MSG=%*"
call :log ERROR "%MSG%"
exit /b %CODE%

:: -----------------------------
:: OS check (Windows-only)
:: -----------------------------
if /I not "%OS%"=="Windows_NT" (
    call :die %EC_UNSUPPORTED% "Unsupported OS. This script targets Windows only."
)
call :log INFO "Detected OS: Windows"

:: -----------------------------
:: VCS info (optional)
:: -----------------------------
set "VCS_COMMIT="
where git >nul 2>&1 && for /f "usebackq delims=" %%C in (`git rev-parse --short HEAD 2^>nul`) do set "VCS_COMMIT=%%C"
if defined VCS_COMMIT (
    call :log INFO "Version control commit: %VCS_COMMIT%"
) else (
    call :log INFO "Version control commit: N/A"
)

:: -----------------------------
:: OP token presence
:: -----------------------------
if not defined OP_SERVICE_ACCOUNT_TOKEN (
    call :log WARN "OP_SERVICE_ACCOUNT_TOKEN is not set. Exiting."
    exit /b 0
)

:: -----------------------------
:: Elevation check
:: -----------------------------
set "ISADMIN=0"
net session >nul 2>&1 && set "ISADMIN=1"
if "%ISADMIN%"=="1" (
    call :log INFO "Elevation: Administrator"
) else (
    call :log INFO "Elevation: Standard user"
)

:: -----------------------------
:: Network quick check
:: -----------------------------
:TestNetwork
curl.exe -I -s -S --max-time 10 https://example.com >nul 2>&1
if errorlevel 1 (
    call :log WARN "Network check failed or web requests blocked. Proceeding; downloads may fail."
) else (
    call :log INFO "Network check succeeded."
)

:: -----------------------------
:: Package manager detection
:: -----------------------------
set "PM=none"
where winget >nul 2>&1 && set "PM=winget"
if "%PM%"=="none" where choco >nul 2>&1 && set "PM=choco"
if "%PM%"=="none" where scoop >nul 2>&1 && set "PM=scoop"

call :log INFO "Detected package manager: %PM%"
if "%PM%"=="none" (
    call :die %EC_UNSUPPORTED% "No supported package manager found (winget/choco/scoop)."
)

:: -----------------------------
:: PM helpers
:: -----------------------------
:UpdateSystemPackages
if "%NOUPDATE%"=="1" (
    call :log INFO "Skipping system package update (--no-update)."
    exit /b 0
)
call :log INFO "Updating packages via '%PM%'..."
set "RC=0"
if /I "%PM%"=="winget" (
    winget source update >nul 2>&1
    if "%YES%"=="1" (
        winget upgrade --all --accept-package-agreements --accept-source-agreements --silent >nul 2>&1
    ) else (
        winget upgrade --all >nul 2>&1
    )
    set "RC=%ERRORLEVEL%"
) else if /I "%PM%"=="choco" (
    choco upgrade all -y >nul 2>&1
    set "RC=%ERRORLEVEL%"
) else if /I "%PM%"=="scoop" (
    scoop update >nul 2>&1
    scoop cleanup >nul 2>&1
    set "RC=0"
)
if not "%RC%"=="0" (
    call :log WARN "System update failed via '%PM%'."
) else (
    call :log INFO "System packages updated successfully."
)
exit /b 0

:TryWingetInstall
set "ID=%~1"
set "NAME=%~2"
winget show -e --id "%ID%" >nul 2>&1
if errorlevel 1 (
    call :log WARN "winget id '%ID%' not available."
    exit /b 1
)
call :log INFO "Installing %NAME% via winget id '%ID%'..."
if "%YES%"=="1" (
    winget install -e --id "%ID%" --accept-package-agreements --accept-source-agreements --silent >nul 2>&1
) else (
    winget install -e --id "%ID%" >nul 2>&1
)
if errorlevel 1 (
    call :log WARN "winget id '%ID%' install failed."
    exit /b 1
)
exit /b 0

:InstallWithChoco
set "CMDLINE=%*"
call :log INFO "Installing via chocolatey: %CMDLINE%"
if "%YES%"=="1" (
    call choco install %CMDLINE% -y >nul 2>&1
) else (
    call choco install %CMDLINE% >nul 2>&1
)
if errorlevel 1 (
    call :log WARN "choco install failed."
    exit /b 1
)
exit /b 0

:InstallWithScoop
set "PKG=%~1"
call :log INFO "Installing via scoop: %PKG%"
scoop install %PKG% >nul 2>&1
if errorlevel 1 (
    call :log WARN "scoop install failed."
    exit /b 1
)
exit /b 0

:: -----------------------------
:: Python helpers
:: -----------------------------
:GetPython311Exe
set "PY311="
for /f "usebackq delims=" %%I in (`py -3.11 -c "import sys; print(sys.executable)" 2^>nul`) do set "PY311=%%I"
if defined PY311 if exist "%PY311%" exit /b 0
if exist "%ProgramFiles%\Python311\python.exe" set "PY311=%ProgramFiles%\Python311\python.exe" & exit /b 0
if exist "%LOCALAPPDATA%\Programs\Python\Python311\python.exe" set "PY311=%LOCALAPPDATA%\Programs\Python\Python311\python.exe" & exit /b 0
if exist "%ProgramFiles(x86)%\Python311\python.exe" set "PY311=%ProgramFiles(x86)%\Python311\python.exe" & exit /b 0
for /f "usebackq tokens=*" %%P in (`where python 2^>nul`) do (
    for /f "usebackq tokens=2 delims= " %%V in (`"%%P" --version 2^>nul`) do (
        echo %%V | findstr /R /C:"^3\.11" >nul && set "PY311=%%P"
    )
)
exit /b 0

:EnsurePip311
set "PY311_EXE=%~1"
call :log INFO "Ensuring pip for Python 3.11..."
if exist "%PY311_EXE%" (
    "%PY311_EXE%" -m pip --version >nul 2>&1
    if not errorlevel 1 (
        call :log INFO "pip for Python 3.11 already present."
        exit /b 0
    )
)
if exist "%PY311_EXE%" (
    "%PY311_EXE%" -m ensurepip --upgrade >nul 2>&1
    if not errorlevel 1 (
        call :log INFO "pip installed via ensurepip."
        exit /b 0
    )
)
call :log INFO "Bootstrapping pip via get-pip.py..."
set "TMP_PIP=%TEMP%\get-pip.py"
curl.exe -s -L -o "%TMP_PIP%" https://bootstrap.pypa.io/get-pip.py >nul 2>&1
if exist "%PY311_EXE%" (
    "%PY311_EXE%" "%TMP_PIP%" >nul 2>&1
    if errorlevel 1 (
        call :die %EC_PIP% "Failed to install pip for Python 3.11 via get-pip.py."
    )
    call :log INFO "pip installed via get-pip.py."
) else (
    py -3.11 "%TMP_PIP%" >nul 2>&1
    if errorlevel 1 (
        call :die %EC_PIP% "Failed to install pip for Python 3.11 via get-pip.py using py launcher."
    )
    call :log INFO "pip installed via get-pip.py using py launcher."
)
exit /b 0

:SetPyLauncherDefaultTo311
set "USER_INI=%LOCALAPPDATA%\py.ini"
(
    echo [defaults]
    echo python=3.11
)>"%USER_INI%"
call :log INFO "Set user py.ini default to Python 3.11: %USER_INI%"

if "%ISADMIN%"=="1" (
    if defined ProgramData (
        set "SYS_INI=%ProgramData%\py.ini"
        (
            echo [defaults]
            echo python=3.11
        )>"%SYS_INI%"
        call :log INFO "Set system py.ini default to Python 3.11: %SYS_INI%"
    )
)
exit /b 0

:EnsureUserBinOnPath
set "USER_BIN=%USERPROFILE%\bin"
if not exist "%USER_BIN%" (
    mkdir "%USER_BIN%" >nul 2>&1
    call :log INFO "Created user bin directory: %USER_BIN%"
)
:: Update PATH in registry via PowerShell for reliability
powershell -NoProfile -Command ^
    "$reg='HKCU:\Environment';$p=(Get-ItemProperty -Path $reg -Name Path -ErrorAction SilentlyContinue).Path;" ^
    "if($p){$arr=$p -split ';' | %{$_.Trim()};" ^
    "if(-not ($arr -contains $env:USERPROFILE+'\bin')){Set-ItemProperty -Path $reg -Name Path -Value ($p+';'+$env:USERPROFILE+'\bin')}} " ^
    "else {Set-ItemProperty -Path $reg -Name Path -Value ($env:USERPROFILE+'\bin')}" >nul 2>&1
if errorlevel 1 (
    call :log WARN "Failed to update PATH in registry."
) else (
    call :log INFO "Added user bin to PATH (registry). Restart shell to pick up changes."
)
set "RET_USER_BIN=%USER_BIN%"
exit /b 0

:AddPython3Shim
set "PY311_EXE=%~1"
call :EnsureUserBinOnPath
set "USER_BIN=%RET_USER_BIN%"
set "SHIM=%USER_BIN%\python3.cmd"
(
    echo @echo off
    echo py -3.11 %%*
)>"%SHIM%"
call :log INFO "Created python3 shim: %SHIM%"
:: Add a PowerShell function in profile as a convenience (optional)
set "PROFILE_PS=%USERPROFILE%\Documents\WindowsPowerShell\profile.ps1"
if not exist "%PROFILE_PS%" (
    type nul > "%PROFILE_PS%"
)
findstr /R /C:"function\s\+python3" "%PROFILE_PS%" >nul 2>&1 || (
    >>"%PROFILE_PS%" echo function python3 { param([Parameter(ValueFromRemainingArguments=$true)][object[]]$Args) py -3.11 $Args }
    call :log INFO "Added 'python3' function to PowerShell profile: %PROFILE_PS%"
)
exit /b 0

:RefreshEnvironment
:: Try Chocolatey's refreshenv if available
where refreshenv >nul 2>&1 && (call refreshenv >nul 2>&1 & call :log INFO "Refreshed environment via refreshenv." & exit /b 0)
:: Rebuild PATH in current session from registry
powershell -NoProfile -Command ^
    "$mp=(Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name Path -ErrorAction SilentlyContinue).Path;" ^
    "$up=(Get-ItemProperty -Path 'HKCU:\Environment' -Name Path -ErrorAction SilentlyContinue).Path;" ^
    "$combined=$mp; if($up){$combined += ';'+$up}; [Environment]::SetEnvironmentVariable('Path',$combined,'Process');" ^
    "[void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms');" ^
    "$null=$combined" >nul 2>&1
if errorlevel 1 (
    call :log WARN "Failed to refresh PATH."
) else (
    call :log INFO "Refreshed PATH for current session."
)
exit /b 0

:: -----------------------------
:: Git helpers
:: -----------------------------
:GetGitExe
set "GITEXE="
for %%P in (
    "%ProgramFiles%\Git\cmd\git.exe"
    "%ProgramFiles%\Git\bin\git.exe"
    "%ProgramFiles%\Git\mingw64\bin\git.exe"
    "%LOCALAPPDATA%\Programs\Git\cmd\git.exe"
    "%LOCALAPPDATA%\Programs\Git\bin\git.exe"
    "%ProgramData%\chocolatey\bin\git.exe"
    "%USERPROFILE%\scoop\apps\git\current\bin\git.exe"
    "%USERPROFILE%\scoop\apps\git\current\mingw64\bin\git.exe"
) do (
    if exist "%%~fP" set "GITEXE=%%~fP"
)
exit /b 0

:InstallGit
where git >nul 2>&1
if not errorlevel 1 (
    for /f "usebackq delims=" %%V in (`git --version 2^>nul`) do call :log INFO "Git already installed: %%V"
    exit /b 0
)
call :log INFO "Installing Git..."
if "%NOUPDATE%"=="0" (
    call :UpdateSystemPackages
) else (
    call :log INFO "Skipping system package update (--no-update flag)."
)

set "OK=1"
if /I "%PM%"=="winget" (
    call :TryWingetInstall "Git.Git" "Git" || set "OK=0"
) else if /I "%PM%"=="choco" (
    call :InstallWithChoco git || set "OK=0"
) else if /I "%PM%"=="scoop" (
    call :InstallWithScoop git || set "OK=0"
)
if "%OK%"=="0" (
    call :die %EC_GIT% "Failed to install Git."
)

call :RefreshEnvironment

where git >nul 2>&1
if not errorlevel 1 (
    for /f "usebackq delims=" %%V in (`git --version 2^>nul`) do call :log INFO "Git installed: %%V"
    exit /b 0
)
call :GetGitExe
if defined GITEXE (
    set "GITDIR=%~dp0"
    set "GITDIR=%GITEXE%"
    for %%D in ("%GITEXE%") do set "GITDIR=%%~dpD"
    set "PATH=%GITDIR%;%PATH%"
    for /f "usebackq delims=" %%V in (`"%GITEXE%" --version 2^>nul`) do call :log INFO "Git installed: %%V"
) else (
    call :die %EC_GIT% "Git installation completed, but executable not found in PATH or known locations."
)
exit /b 0

:: -----------------------------
:: 1Password helpers
:: -----------------------------
:GetOpExe
set "OPEXE="
for %%P in (
    "%ProgramFiles%\1Password CLI\op.exe"
    "%LOCALAPPDATA%\Programs\1Password CLI\op.exe"
    "%LOCALAPPDATA%\1Password\op.exe"
    "%ProgramData%\chocolatey\bin\op.exe"
    "%USERPROFILE%\scoop\apps\1password-cli\current\op.exe"
    "%USERPROFILE%\scoop\apps\op\current\op.exe"
) do (
    if exist "%%~fP" set "OPEXE=%%~fP"
)
if not defined OPEXE (
    where op >nul 2>&1 && for /f "usebackq delims=" %%X in (`where op 2^>nul`) do set "OPEXE=%%X"
)
exit /b 0

:Test1PasswordInstalled
set "ONEP_OK=0"
for %%P in (
    "%ProgramFiles%\1Password\1Password.exe"
    "%ProgramFiles%\1Password 8\1Password.exe"
    "%LOCALAPPDATA%\1Password\app\1Password.exe"
    "%LOCALAPPDATA%\Programs\1Password\1Password.exe"
) do (
    if exist "%%~fP" set "ONEP_OK=1"
)
if "%ONEP_OK%"=="0" (
    :: Try winget list heuristic
    winget list 1Password >"%TEMP%\_winget_list.txt" 2>&1
    findstr /I "1Password" "%TEMP%\_winget_list.txt" >nul 2>&1 && set "ONEP_OK=1"
    del /q "%TEMP%\_winget_list.txt" >nul 2>&1
)
exit /b %ONEP_OK%

:Install1Password
call :Test1PasswordInstalled
if "%ERRORLEVEL%"=="1" (
    call :log INFO "1Password already installed."
    exit /b 0
)
call :log INFO "Installing 1Password (desktop)..."
if "%NOUPDATE%"=="0" (
    call :UpdateSystemPackages
) else (
    call :log INFO "Skipping system package update (--no-update flag)."
)

set "OK=1"
if /I "%PM%"=="winget" (
    call :TryWingetInstall "AgileBits.1Password" "1Password" || call :TryWingetInstall "1Password.1Password" "1Password" || set "OK=0"
) else if /I "%PM%"=="choco" (
    call :InstallWithChoco 1password || call :InstallWithChoco onepassword || set "OK=0"
) else if /I "%PM%"=="scoop" (
    call :log WARN "Scoop may not provide 1Password desktop; consider winget/choco."
    set "OK=0"
)
if "%OK%"=="0" (
    call :Test1PasswordInstalled
    if not "%ERRORLEVEL%"=="1" (
        call :die %EC_1PASSWORD% "1Password installation failed or package not found."
    )
)

call :Test1PasswordInstalled
if "%ERRORLEVEL%"=="1" (
    call :log INFO "1Password installed successfully."
) else (
    call :die %EC_1PASSWORD% "1Password installation did not produce the desktop executable."
)
exit /b 0

:Test1PasswordCLIInstalled
call :GetOpExe
if defined OPEXE exit /b 1
exit /b 0

:Install1PasswordCLI
call :Test1PasswordCLIInstalled
if "%ERRORLEVEL%"=="1" (
    call :log INFO "1Password CLI already installed."
    exit /b 0
)
call :log INFO "Installing 1Password CLI..."
if "%NOUPDATE%"=="0" (
    call :UpdateSystemPackages
) else (
    call :log INFO "Skipping system package update (--no-update flag)."
)
set "OK=1"
if /I "%PM%"=="winget" (
    call :TryWingetInstall "AgileBits.1Password.CLI" "1Password CLI" || call :TryWingetInstall "1Password.1PasswordCLI" "1Password CLI" || set "OK=0"
) else if /I "%PM%"=="choco" (
    call :InstallWithChoco 1password-cli || call :InstallWithChoco op || set "OK=0"
) else if /I "%PM%"=="scoop" (
    scoop bucket add extras >nul 2>&1
    call :InstallWithScoop 1password-cli || call :InstallWithScoop op || set "OK=0"
)
if "%OK%"=="0" (
    call :Test1PasswordCLIInstalled
    if not "%ERRORLEVEL%"=="1" (
        call :die %EC_1PASSWORD% "1Password CLI installation failed or package not found."
    )
)

call :RefreshEnvironment

where op >nul 2>&1
if not errorlevel 1 (
    for /f "usebackq delims=" %%V in (`op --version 2^>nul`) do call :log INFO "1Password CLI installed: %%V"
    exit /b 0
)
call :GetOpExe
if defined OPEXE (
    for /f "usebackq delims=" %%V in (`"%OPEXE%" --version 2^>nul`) do call :log INFO "1Password CLI installed: %%V"
)
exit /b 0

:: -----------------------------
:: Post-init helpers
:: -----------------------------
:EnsureGithubSSHNoHostKeyCheck
set "SSH_DIR=%USERPROFILE%\.ssh"
set "SSH_CONFIG=%SSH_DIR%\config"
if not exist "%SSH_DIR%" mkdir "%SSH_DIR%" >nul 2>&1
if not exist "%SSH_CONFIG%" type nul > "%SSH_CONFIG%"
findstr /I "github.com" "%SSH_CONFIG%" >nul 2>&1
if errorlevel 1 (
    (
        echo Host github.com
        echo ^    StrictHostKeyChecking no
        echo ^    UserKnownHostsFile NUL
    )>>"%SSH_CONFIG%"
    call :log INFO "Appended GitHub SSH host key override to %SSH_CONFIG%"
) else (
    call :log INFO "SSH config already contains a block for github.com"
)
exit /b 0

:InvokePostInit
:: Copy SSH private_key.value to ~/.ssh/id_ed25519 via 1Password CLI JSON
call :GetOpExe
if defined OPEXE (
    call :log INFO "Post-init: Copying SSH private_key.value to ~/.ssh/id_ed25519"
    set "SSH_DIR=%USERPROFILE%\.ssh"
    if not exist "%SSH_DIR%" mkdir "%SSH_DIR%" >nul 2>&1
    set "TMP_JSON=%TEMP%\op_item.json"
    "%OPEXE%" item get xs3o5lfiqqs55qkeqz5jwji5iy --reveal --vault Service --format json --fields private_key > "%TMP_JSON%" 2>nul
    for /f "usebackq delims=" %%K in (`powershell -NoProfile -Command ^
        "$j=Get-Content -LiteralPath '%TMP_JSON%' -ErrorAction SilentlyContinue | ConvertFrom-Json;" ^
        "if($j -and $j.ssh_formats -and $j.ssh_formats.openssh -and $j.ssh_formats.openssh.value){$j.ssh_formats.openssh.value} elseif($j -and $j.value){$j.value} else {''}"`) do (
        set "KEY_CONTENT=%%K"
    )
    if defined KEY_CONTENT (
        >"%SSH_DIR%\id_ed25519" echo %KEY_CONTENT%
        :: Restrictive ACL
        icacls "%SSH_DIR%\id_ed25519" /inheritance:r /grant:r "%USERNAME%:R" >nul 2>&1
        call :log INFO "Wrote SSH private key to %SSH_DIR%\id_ed25519"
    ) else (
        call :log WARN "Unable to extract private key from 1Password JSON; ensure you are signed in ('op signin')."
    )
    del /q "%TMP_JSON%" >nul 2>&1
) else (
    call :log WARN "1Password CLI ('op') not found; skipping SSH key copy."
)

:: Create WORKSPACE (default: ~/workspace)
set "WORKSPACE=%WORKSPACE%"
if not defined WORKSPACE set "WORKSPACE=%USERPROFILE%\workspace"
if not exist "%WORKSPACE%" (
    mkdir "%WORKSPACE%" >nul 2>&1
    call :log INFO "Post-init: Creating %WORKSPACE% directory"
)

:: Ensure SSH config host key override for GitHub
call :EnsureGithubSSHNoHostKeyCheck

:: Clone or pull repo
set "REPO=git@github.com:yuxiaoli/app-manager.git"
set "REPO_NAME=app-manager"
set "REPO_PATH=%WORKSPACE%\python\%REPO_NAME%"
call :log INFO "Post-init: Cloning setup repository to %REPO_PATH%"
where git >nul 2>&1
if errorlevel 1 (
    call :log WARN "Git not found; skipping repository clone/pull."
) else (
    if exist "%REPO_PATH%\.git" (
        call :log INFO "Post-init: Repository exists; pulling latest changes"
        git -C "%REPO_PATH%" pull --ff-only >nul 2>&1
    ) else (
        git clone "%REPO%" "%REPO_PATH%" >nul 2>&1
    )
)

:: Run Windows setup script using Python
set "PY_CMD="
where python >nul 2>&1 && set "PY_CMD=python"
if "%PY_CMD%"=="" where py >nul 2>&1 && set "PY_CMD=py"
if "%PY_CMD%"=="" where python3 >nul 2>&1 && set "PY_CMD=python3"
if "%PY_CMD%"=="" (
    call :log WARN "No Python interpreter found in PATH; skipping setup script run."
) else (
    set "SETUP_DIR=%REPO_PATH%"
    set "SETUP_SCRIPT=%SETUP_DIR%\windows_init.py"
    if exist "%SETUP_SCRIPT%" (
        call :log INFO "Post-init: Running setup script windows_init.py"
        if /I "%PY_CMD%"=="py" (
            py -3.11 "%SETUP_SCRIPT%"
        ) else (
            "%PY_CMD%" "%SETUP_SCRIPT%"
        )
    ) else (
        call :log WARN "Setup script not found at %SETUP_SCRIPT%"
    )
)

call :log INFO "Post-init verification complete. If new tools were added to PATH, restart your shell."
exit /b 0

:: -----------------------------
:: Python installer
:: -----------------------------
:InstallPython311
call :GetPython311Exe
if defined PY311 (
    call :log INFO "Python 3.11 already installed: %PY311%"
    call :EnsurePip311 "%PY311%"
    call :SetPyLauncherDefaultTo311
    call :AddPython3Shim "%PY311%"
    exit /b 0
)

call :log INFO "Installing Python 3.11..."
if "%NOUPDATE%"=="0" (
    call :UpdateSystemPackages
) else (
    call :log INFO "Skipping system package update (--no-update flag)."
)

set "OK=1"
if /I "%PM%"=="winget" (
    call :TryWingetInstall "Python.Python.3.11" "Python 3.11" || ^
    call :TryWingetInstall "Python.Python.3.11-x64" "Python 3.11" || ^
    call :TryWingetInstall "Python.Python.3.11-arm64" "Python 3.11" || ^
    call :TryWingetInstall "Python.Python.3.11-x86" "Python 3.11" || set "OK=0"
) else if /I "%PM%"=="choco" (
    call :InstallWithChoco python --version 3.11.* || set "OK=0"
) else if /I "%PM%"=="scoop" (
    scoop bucket add versions >nul 2>&1
    call :InstallWithScoop python@3.11 || call :InstallWithScoop python || set "OK=0"
)
if "%OK%"=="0" (
    call :die %EC_PYTHON% "python3.11 not available via the detected package manager."
)

call :GetPython311Exe
if not defined PY311 (
    call :die %EC_PYTHON% "Python 3.11 installation reported success, but executable not found."
)

for /f "usebackq delims=" %%V in (`"%PY311%" --version 2^>nul`) do call :log INFO "Installed: %%V"

call :EnsurePip311 "%PY311%"
call :SetPyLauncherDefaultTo311
call :AddPython3Shim "%PY311%"
exit /b 0

:: -----------------------------
:: Verification helpers
:: -----------------------------
:InvokeValidation
:: Verify python3 shim
set "USER_BIN=%USERPROFILE%\bin"
set "PY3_SHIM=%USER_BIN%\python3.cmd"
if exist "%PY3_SHIM%" (
    call :log INFO "python3 shim present: %PY3_SHIM%"
) else (
    call :log WARN "python3 shim not found at: %PY3_SHIM%"
)

:: Verify Git
where git >nul 2>&1
if not errorlevel 1 (
    for /f "usebackq delims=" %%V in (`git --version 2^>nul`) do call :log INFO "Git detected: %%V"
) else (
    call :GetGitExe
    if defined GITEXE (
        for /f "usebackq delims=" %%V in (`"%GITEXE%" --version 2^>nul`) do call :log INFO "Git detected: %%V"
    ) else (
        call :log WARN "Git not found after install."
    )
)

:: Verify 1Password Desktop
call :Test1PasswordInstalled
if "%ERRORLEVEL%"=="1" (
    call :log INFO "1Password Desktop present."
) else (
    call :log WARN "1Password Desktop not detected."
)

:: Verify 1Password CLI
where op >nul 2>&1
if not errorlevel 1 (
    for /f "usebackq delims=" %%V in (`op --version 2^>nul`) do call :log INFO "1Password CLI detected: %%V"
) else (
    call :GetOpExe
    if defined OPEXE (
        for /f "usebackq delims=" %%V in (`"%OPEXE%" --version 2^>nul`) do call :log INFO "1Password CLI detected: %%V"
    ) else (
        call :log WARN "1Password CLI ('op') not detected."
    )
)
exit /b 0

:: -----------------------------
:: Entry flow
:: -----------------------------
call :log INFO "Log file: %LOG_FILE%"
call :TestNetwork

if "%NOUPDATE%"=="0" (
    call :log INFO "Pre-flight: Updating system packages"
    call :UpdateSystemPackages
) else (
    call :log INFO "Pre-flight: Skipping system package update (--no-update flag)."
)

call :log INFO "Step 1/4: Installing Python 3.11 + pip"
call :InstallPython311

call :log INFO "Step 2/4: Installing Git"
call :InstallGit

call :log INFO "Step 3/4: Installing 1Password (Desktop)"
call :Install1Password

call :log INFO "Step 4/4: Installing 1Password CLI"
call :Install1PasswordCLI

call :log INFO "Post-init: Validating environment and configuration"
call :InvokeValidation

call :InvokePostInit

call :log INFO "Script completed successfully."
exit /b 0