@echo off
setlocal EnableExtensions EnableDelayedExpansion
goto :main

rem ============================================================
rem init.bat - Install Python 3.11 (with pip), Git, and 1Password on Windows
rem
rem Windows adaptations:
rem - Uses winget/choco/scoop instead of apt/dnf/yum/etc.
rem - Uses "py" launcher to target Python 3.11 instead of "python3".
rem - No need for sudo; admin may be required for installs.
rem - Logging and exit codes mirror the original shell script.
rem - Maintains --yes/-y and --help semantics; NON_INTERACTIVE=1 respected.
rem - Idempotent checks use PM-specific list commands and version checks.
rem - Optional package update control: --update (/U) to enable, --no-update (/NU) to skip.
rem   Default remains enabled for backward compatibility.
rem ============================================================

rem -----------------------------
rem Config and defaults
rem -----------------------------
set "SCRIPT_NAME=%~nx0"
set "SCRIPT_DIR=%~dp0"
if not defined LOG_FILE set "LOG_FILE=%SCRIPT_DIR%system-init.log"
set "ASSUME_YES=0"
if /I "%NON_INTERACTIVE%"=="1" set "ASSUME_YES=1"
rem Optional package update flag (default ON for backward compatibility)
if not defined UPDATE_PKGS set "UPDATE_PKGS=1"

rem Exit codes
set "EC_UNSUPPORTED=10"
set "EC_PYTHON=20"
set "EC_PIP=21"
set "EC_GIT=30"
set "EC_1PASSWORD=40"

set "PYTHON_BIN=py -3.11"
set "PIP_BIN=py -3.11 -m pip"

rem -----------------------------
rem Logging helpers
rem -----------------------------
:ts
set "TS=%DATE% %TIME%"
exit /b 0

:log
set "LEVEL=%~1"
shift
set "MSG=%*"
call :ts
echo %TS% %LEVEL% %MSG%
>>"%LOG_FILE%" echo %TS% %LEVEL% %MSG%
exit /b 0

:info
call :log "INFO " %*
exit /b 0

:warn
call :log "WARN " %*
exit /b 0

:error
call :log "ERROR" %*
exit /b 0

:die
set "EC=%~1"
shift
call :error %*
exit /b %EC%

rem -----------------------------
rem Usage
rem -----------------------------
:usage
echo %SCRIPT_NAME% - Install Python 3.11 (with pip), Git, and 1Password
echo.
echo Usage: %SCRIPT_NAME% [options]
echo.
echo Options:
echo   -y, --yes        Non-interactive mode (assume yes)
echo   -h, --help       Show this help
echo   --update, /U     Run pre-flight package upgrade (default: enabled)
echo   --no-update, /NU Skip pre-flight package upgrade
echo.
echo Behavior:
echo   - Detects supported package manager: winget, choco, scoop
echo   - Performs system compatibility checks before running
echo   - Installs:
echo       * Python 3.11 (and ensures pip for 3.11)
echo       * Git (latest stable from manager)
echo       * 1Password (official package via PM)
echo   - Idempotent; safe to re-run
echo   - Logs to: %LOG_FILE%
echo.
echo Exit codes:
echo   0   success
echo   %EC_UNSUPPORTED%   unsupported system or package manager
echo   %EC_PYTHON%        Python 3.11 install failed
echo   %EC_PIP%           pip for Python 3.11 install failed
echo   %EC_GIT%           Git install failed
echo   %EC_1PASSWORD%     1Password install failed
exit /b 0

rem -----------------------------
rem Arg parsing
rem -----------------------------
:parse_args
if "%~1"=="" goto after_parse_args
if /I "%~1"=="-y"        set "ASSUME_YES=1" & shift & goto parse_args
if /I "%~1"=="--yes"     set "ASSUME_YES=1" & shift & goto parse_args
if /I "%~1"=="--update"  set "UPDATE_PKGS=1" & shift & goto parse_args
if /I "%~1"=="/U"        set "UPDATE_PKGS=1" & shift & goto parse_args
if /I "%~1"=="--no-update" set "UPDATE_PKGS=0" & shift & goto parse_args
if /I "%~1"=="/NU"       set "UPDATE_PKGS=0" & shift & goto parse_args
if /I "%~1"=="-h"        call :usage & exit /b 0
if /I "%~1"=="--help"    call :usage & exit /b 0
call :warn Unknown option: %~1
call :usage
exit /b 1
:after_parse_args

rem -----------------------------
rem Privilege handling (Windows)
rem -----------------------------
:is_admin
rem Windows equivalent to sudo: check admin; some installers may require it.
net session >nul 2>&1
if %ERRORLEVEL% EQU 0 (
  set "IS_ADMIN=1"
  call :info Running with administrative privileges.
) else (
  set "IS_ADMIN=0"
  call :info Not running as admin; some installs may prompt for elevation.
)
rem No auto-elevation; we proceed and let PM prompt as needed.

rem -----------------------------
rem OS and PM detection
rem -----------------------------
set "OSNAME=%OS%"
call :info Detected OS: %OSNAME%

:detect_pm
set "PM=none"

where /Q winget
if %ERRORLEVEL% EQU 0 set "PM=winget"

if /I "%PM%"=="none" (
  where /Q choco
  if %ERRORLEVEL% EQU 0 set "PM=choco"
)

if /I "%PM%"=="none" (
  where /Q scoop
  if %ERRORLEVEL% EQU 0 set "PM=scoop"
)

call :info Detected package manager: %PM%
if /I "%PM%"=="none" (
  call :die %EC_UNSUPPORTED% "No supported package manager found (winget/choco/scoop)."
)

rem YES flag mapping per PM
set "WINGET_YES="
if "%ASSUME_YES%"=="1" set "WINGET_YES=--accept-source-agreements --accept-package-agreements"
set "CHOCO_YES="
if "%ASSUME_YES%"=="1" set "CHOCO_YES=-y"
set "SCOOP_FLAGS="

rem -----------------------------
rem PM helpers
rem -----------------------------
:pm_update
call :info Updating package index...
if /I "%PM%"=="winget" (
  winget source update
) else if /I "%PM%"=="choco" (
  choco outdated >nul 2>&1
) else if /I "%PM%"=="scoop" (
  scoop update
)
exit /b 0

:pm_system_update
call :info Running system package update via '%PM%'...
set "RC=0"
if /I "%PM%"=="winget" (
  winget upgrade --all %WINGET_YES%
  set "RC=%ERRORLEVEL%"
) else if /I "%PM%"=="choco" (
  choco upgrade all -y
  set "RC=%ERRORLEVEL%"
) else if /I "%PM%"=="scoop" (
  scoop update
  set "RC=%ERRORLEVEL%"
)
if not "%RC%"=="0" (
  call :error System update failed via '%PM%' (exit %RC%).
) else (
  call :info System update via '%PM%' completed successfully.
)
exit /b 0

rem -----------------------------
rem Python 3.11 + pip
rem -----------------------------
:ensure_pip311
rem Ensure pip for Python 3.11 exists; use ensurepip then fallback to get-pip.py
%PYTHON_BIN% -m pip --version >nul 2>&1
if %ERRORLEVEL% EQU 0 (
  call :info pip for Python 3.11 already present.
  exit /b 0
)

call :info Bootstrapping pip for Python 3.11...
%PYTHON_BIN% -m ensurepip --upgrade >nul 2>&1
if %ERRORLEVEL% EQU 0 (
  call :info pip (ensurepip) installed for Python 3.11.
  exit /b 0
)

rem Fallback: get-pip.py via PowerShell or curl
set "GETPIP=%TEMP%\get-pip.py"
where /Q curl
if %ERRORLEVEL% EQU 0 (
  curl -fsSL https://bootstrap.pypa.io/get-pip.py -o "%GETPIP%" 2>nul
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Invoke-WebRequest -UseBasicParsing 'https://bootstrap.pypa.io/get-pip.py' -OutFile '%GETPIP%'"
)
if exist "%GETPIP%" (
  %PYTHON_BIN% "%GETPIP%" >nul 2>&1
  if %ERRORLEVEL% EQU 0 (
    call :info pip (get-pip.py) installed for Python 3.11.
    del /Q "%GETPIP%" >nul 2>&1
    exit /b 0
  )
)

call :die %EC_PIP% "Failed to install pip for Python 3.11."

:install_python311
rem Check if Python 3.11 is available via py launcher or python.exe
rem Windows adaptation: prefer py launcher to target 3.11
py -0p 2>nul | findstr /R /C:"3\.11" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
  call :info Python 3.11 already installed: 
  %PYTHON_BIN% --version 2>nul
  call :ensure_pip311
  exit /b 0
)

rem If python.exe is 3.11, accept it as installed
for /f "tokens=2" %%V in ('python --version 2^>^&1') do set "PYVER=%%V"
echo %PYVER% | findstr /R /C:"^3\.11\." >nul 2>&1
if %ERRORLEVEL% EQU 0 (
  set "PYTHON_BIN=python"
  set "PIP_BIN=python -m pip"
  call :info Python 3.11 already installed: 
  %PYTHON_BIN% --version
  call :ensure_pip311
  exit /b 0
)

call :info Installing Python 3.11...
call :pm_update

if /I "%PM%"=="winget" (
  rem Winget package id for Python 3.11 (Windows Store manifest)
  winget install -e --id Python.Python.3.11 %WINGET_YES%
  if not %ERRORLEVEL% EQU 0 call :die %EC_PYTHON% "Python 3.11 not available via winget on this system."
) else if /I "%PM%"=="choco" (
  rem Try to install a Python package pinned to 3.11 if available; fallback to python and verify version.
  choco install python --version=3.11.9 %CHOCO_YES%
  if not %ERRORLEVEL% EQU 0 (
    choco install python %CHOCO_YES%
    if not %ERRORLEVEL% EQU 0 call :die %EC_PYTHON% "python package not available via choco on this system."
  )
) else if /I "%PM%"=="scoop" (
  rem Scoop versions bucket often hosts python311 explicitly
  scoop bucket add versions >nul 2>&1
  scoop install python311
  if not %ERRORLEVEL% EQU 0 (
    scoop install python
    if not %ERRORLEVEL% EQU 0 call :die %EC_PYTHON% "python package not available via scoop on this system."
  )
) else (
  call :die %EC_UNSUPPORTED% "Unsupported package manager for Python installation."
)

rem Validate Python 3.11 presence post-install
py -0p 2>nul | findstr /R /C:"3\.11" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
  set "PYTHON_BIN=py -3.11"
  set "PIP_BIN=py -3.11 -m pip"
) else (
  for /f "tokens=2" %%V in ('python --version 2^>^&1') do set "PYVER=%%V"
  echo %PYVER% | findstr /R /C:"^3\.11\." >nul 2>&1
  if %ERRORLEVEL% EQU 0 (
    set "PYTHON_BIN=python"
    set "PIP_BIN=python -m pip"
  ) else (
    call :die %EC_PYTHON% "Installed Python version is %PYVER% ; required is 3.11."
  )
)

call :info Installed: 
%PYTHON_BIN% --version
call :ensure_pip311

rem Note: Linux script sets python3 default to 3.11 via alternatives.
rem Windows adaptation: we rely on 'py -3.11' or 'python' reporting 3.11; no python3 alias set.

exit /b 0

rem -----------------------------
rem Git
rem -----------------------------
:install_git
git --version >nul 2>&1
if %ERRORLEVEL% EQU 0 (
  for /f "tokens=*" %%G in ('git --version') do set "GITV=%%G"
  call :info Git already installed: !GITV!
  exit /b 0
)

call :info Installing Git...
call :pm_update
if /I "%PM%"=="winget" (
  winget install -e --id Git.Git %WINGET_YES%
) else if /I "%PM%"=="choco" (
  choco install git %CHOCO_YES%
) else if /I "%PM%"=="scoop" (
  scoop install git
)

if not %ERRORLEVEL% EQU 0 call :die %EC_GIT% "Failed to install Git."
for /f "tokens=*" %%G in ('git --version') do set "GITV=%%G"
call :info Git installed: !GITV!
exit /b 0

rem -----------------------------
rem 1Password (official)
rem -----------------------------
:install_1password
call :info Installing 1Password (official)...
if /I "%PM%"=="winget" (
  call :install_1password_winget
) else if /I "%PM%"=="choco" (
  call :install_1password_choco
) else if /I "%PM%"=="scoop" (
  call :install_1password_scoop
) else (
  call :die %EC_UNSUPPORTED% "Unsupported package manager for 1Password."
)

rem Post-check best-effort: validate install presence via winget/choco/scoop
if /I "%PM%"=="winget" (
  winget list --id AgileBits.1Password >nul 2>&1 || call :die %EC_1PASSWORD% "1Password installation did not register with winget."
) else if /I "%PM%"=="choco" (
  choco list --local-only 1password >nul 2>&1 || call :die %EC_1PASSWORD% "1Password installation did not register with choco."
) else if /I "%PM%"=="scoop" (
  scoop list 1password >nul 2>&1 || call :die %EC_1PASSWORD% "1Password installation did not register with scoop."
)

call :info 1Password installed successfully.
exit /b 0

:main
call :parse_args %*
call :is_admin

set "OSNAME=%OS%"
call :info Detected OS: %OSNAME%

call :detect_pm

rem YES flag mapping per PM
set "WINGET_YES="
if "%ASSUME_YES%"=="1" set "WINGET_YES=--accept-source-agreements --accept-package-agreements"
set "CHOCO_YES="
if "%ASSUME_YES%"=="1" set "CHOCO_YES=-y"
set "SCOOP_FLAGS="

call :info Log file: %LOG_FILE%

rem Executable bit is not applicable on Windows; acknowledge parity with Linux script.
call :info Script executable permissions not required on Windows.

rem Pre-flight: update the system via detected package manager
call :info Pre-flight: Updating system packages
rem Optional package update control:
rem - Enabled by default for backward compatibility.
rem - Can be forced with --update (/U) or disabled with --no-update (/NU).
if "%UPDATE_PKGS%"=="1" (
  call :info Update flag ON; running package upgrade via '%PM%'.
  call :pm_system_update
  rem pm_system_update populates RC; perform additional error-aware logging here.
  if not "%RC%"=="0" (
    call :warn Package update encountered errors (rc=%RC%). Continuing installation.
  ) else (
    call :info Package update completed successfully.
  )
) else (
  call :info Update flag OFF; skipping pre-flight package upgrade.
)

call :info Step 1/3: Installing Python 3.11 + pip
call :install_python311

call :info Step 2/3: Installing Git
call :install_git

call :info Step 3/3: Installing 1Password
call :install_1password

call :info All done. ✅
exit /b 0