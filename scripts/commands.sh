# Command reference. Copy only individually reviewed examples from this checkout.
# NEVER execute/source this file. ALL initializer invocations are commented:
# they are hazardous system provisioning, not safe one-shot setup defaults.
# No installer, credential retrieval, SSH modification, elevation, package update
# or application execution was performed while preparing this reference.
#
# Source inventory: init.sh (POSIX shell), init.ps1 (Windows PowerShell),
# init.bat (Windows CMD). No package manifest, tests, build or release workflow.

# === Critical side effects and prerequisites ===
# Normal runs require OP_SERVICE_ACCOUNT_TOKEN already supplied privately.
# Do not paste a real token into this file, shell history, logs or repository.
# This token is used by 1Password CLI to retrieve a hardcoded vault item's SSH
# private key. Scripts can overwrite ~/.ssh/id_ed25519 without a backup.
# init.sh additionally copies it into root's home; credentials and access scope
# must be reviewed independently. No credential-copy opt-out is implemented.
# Post-init weakens github.com SSH host-key checking, changes SSH permissions,
# clones/pulls unpinned app-manager code, then runs its platform initializer.
# That downstream initializer is not a pinned dependency or a safe dry run.
# Also installs Python 3.11/pip, Git, uv and 1Password tools, updates packages,
# modifies Python defaults/shims/PATH/profiles and downloads bootstrap scripts.
# Platform/distro availability is unverified. Elevation can alter the whole OS.
# Never copy README curl|sh, sudo -E or ExecutionPolicy Bypass recipes blindly.
# No safe selective-install/security-preserving mode exists at this revision.

# === POSIX shell: Linux/macOS source-defined options ===
# Help is parsed before the token preflight, but EXIT trap appends a log;
# even help is not strictly filesystem-read-only.
# sh ./init.sh --help
# Interactive/default initializer (still has automatic system/security changes):
# sh ./init.sh
# Noninteractive equivalent, not a preview:
# sh ./init.sh --yes
# -y aliases --yes; -h aliases --help. No --no-update or --dry-run in init.sh.
# ASSUME_YES=1 or NON_INTERACTIVE=1 also selects unattended operation.
# LOG_FILE controls append log destination; WORKSPACE defaults to ~/workspace.
# Environment combination, ONLY after separate review/authorization:
# LOG_FILE="YOUR_EXISTING_DIRECTORY/system-init.log" WORKSPACE="YOUR_WORKSPACE" sh ./init.sh --yes
# DEBUG=1 enables shell xtrace and can expose token/key material: do not use it
# with credentials. No example setting a secret or enabling trace is supplied.
# Supported detection branches: apt/dnf/yum/zypper/pacman/apk/brew; this does not
# guarantee every branch works. Alpine ultimately has no official op package.
# Package index/full upgrades occur before install; Python3 links/alternatives
# may replace the system default. Root and user SSH configuration can be changed.
# Observed source defects: dnf check-update's nonzero "updates available" result
# is chained with && install; Darwin later falls through the linux_init.py
# selector (selector expects macos). Runtime/platform behavior is unverified.

# === Windows PowerShell (comments are NOT Bash commands) ===
# Declared switches: -Yes, -NoUpdate, -Help; GNU aliases also inspected in $args.
# .\init.ps1 -Help
# .\init.ps1
# .\init.ps1 -NoUpdate
# .\init.ps1 -Yes
# .\init.ps1 -Yes -NoUpdate
# -NoUpdate skips package-wide pre-updates ONLY: it does NOT skip installation,
# credential copying, SSH changes, profile/PATH writes or downstream execution.
# Admin context may be needed for system package operations/ProgramData py.ini.
# No automatic elevation/bypass command is recommended by this catalogue.
# SupportsShouldProcess is declared, but no actual ShouldProcess guard surrounds
# operations: -WhatIf is NOT a reliable no-write safety mode.
# Configures a python3 shim, PowerShell profile helpers and registry-backed PATH.
# Partial failures may be logged/caught; success text is not end-to-end acceptance.

# === Windows CMD: historical interface, known control-flow defects ===
# These are parsed/intended forms, NOT verified functioning initializer recipes.
# init.bat --help
# init.bat --yes
# init.bat --no-update
# init.bat --yes --no-update
# -y/-h are intended aliases. Ungrouped IF ... & shift & goto statements allow
# unconditional shift/goto; later flags can be bypassed. After parsing, execution
# also falls into :timestamp then exit /b; no jump reaches the bottom main flow.
# Do not treat an early exit as installation success or repair it by executing
# arbitrary labels. No source fixes are part of this command-reference change.

# Declared failure categories: 10 unsupported platform/manager; 20 Python;
# 21 pip; 30 Git; 40 1Password. Other errors can exit 1/nonzero or only warn.
# Logs default to system-init.log beside scripts; protect them as sensitive.
# Pin/review all downstream code and remove/rework unwanted effects separately
# before considering use. Main and external pinned reference snapshots unchanged.

