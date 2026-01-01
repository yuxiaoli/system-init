# System Initialization Scripts Summary

This document summarizes the workflow of `init.bat`, `init.ps1`, and `init.sh`. These scripts are designed to bootstrap a development environment on Windows, Linux, and macOS.

## Workflow Steps

1.  **Pre-flight Validation**
    *   **Token Check**: Verify `OP_SERVICE_ACCOUNT_TOKEN` is set.
    *   **Environment Detection**: Identify OS and available package manager (winget, choco, scoop, apt, brew, etc.).
    *   **Privileges**: Check for Administrator/Root access where required.

2.  **System Update**
    *   Update package manager indexes.
    *   Upgrade existing system packages (skippable via `--no-update`).

3.  **Python 3.11 Environment**
    *   **uv**: Install `uv` (fast Python package installer) via package manager or official script.
    *   **Python**: Install Python 3.11 (preferring `uv python install 3.11`, falling back to system packages).
    *   **Pip**: Ensure `pip` is installed and upgraded for Python 3.11.
    *   **Configuration (Windows)**: Set `py` launcher default to 3.11 and create a `python3` shim/alias.

4.  **Core Tools Installation**
    *   **Git**: Install latest stable version.
    *   **1Password**: Install Desktop application and CLI (`op`).
5.  **Validation**
    *   **Verification**: The script verifies that all installed components (Python, Pip, Git, 1Password CLI, `uv`) are correctly installed and accessible in the PATH.
    *   **uv Check**: Explicitly verifies `uv run -- python --version` to ensure the `uv` environment is functional.

6.  **Post-Initialization**
    *   **SSH Setup**: 
        *   Retrieve private key from 1Password (Vault: Service, Item ID: `xs3o5lfiqqs55qkeqz5jwji5iy`).
        *   Save to `~/.ssh/id_ed25519` with secure permissions (600).
        *   Configure `~/.ssh/config` to disable `StrictHostKeyChecking` for `github.com`.
    *   **Workspace**: Ensure `~/workspace` directory exists.
    *   **Repo Setup**: Clone or pull `git@github.com:yuxiaoli/app-manager.git` into `~/workspace/python/app-manager`.
    *   **Handover**: Execute the OS-specific setup script (`windows_init.py`, `linux_init.py`, or `macos_init.py`) from the cloned repository using Python 3.11.
