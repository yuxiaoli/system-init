#!/usr/bin/env sh
# Universal installer for Python 3.11 (with pip), Git, and 1Password
# Compatible with bash and zsh (POSIX sh used)

set -eu

# -----------------------------
# Config and defaults
# -----------------------------
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
LOG_FILE="${LOG_FILE:-$SCRIPT_DIR/system-init.log}"
ASSUME_YES="${ASSUME_YES:-0}"              # 1 => non-interactive
if [ "${NON_INTERACTIVE:-0}" = "1" ]; then
  ASSUME_YES=1
fi

# Exit codes
EC_UNSUPPORTED=10
EC_PYTHON=20
EC_PIP=21
EC_GIT=30
EC_1PASSWORD=40

PYTHON_BIN="python3.11"
PIP_BIN="pip3.11"

# -----------------------------
# Logging helpers
# -----------------------------
ts() { date +"%Y-%m-%d %H:%M:%S"; }
log() { printf "%s %s\n" "$(ts)" "$*" | tee -a "$LOG_FILE"; }
info() { log "INFO  $*"; }
warn() { log "WARN  $*"; }
error() { log "ERROR $*"; }

die() {
  error "$2"
  exit "$1"
}

# -----------------------------
# Usage
# -----------------------------
usage() {
  cat <<EOF
$SCRIPT_NAME - Install Python 3.11 (with pip), Git, and 1Password

Usage: $SCRIPT_NAME [options]

Options:
  -y, --yes          Non-interactive mode (assume yes)
  -h, --help         Show this help

Behavior:
  - Detects supported package manager (apt, dnf, yum, zypper, pacman, apk, brew)
  - Performs system compatibility checks before running
  - Installs:
      * Python 3.11 (and ensures pip for 3.11)
      * Git (latest stable from manager)
      * 1Password (official package via repo, or AUR on Arch)
  - Idempotent; safe to re-run
  - Logs to: $LOG_FILE

Exit codes:
  0  success
  $EC_UNSUPPORTED  unsupported OS or package manager
  $EC_PYTHON       Python 3.11 install failed
  $EC_PIP          pip for Python 3.11 install failed
  $EC_GIT          Git install failed
  $EC_1PASSWORD    1Password install failed
EOF
}

# -----------------------------
# Arg parsing
# -----------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) warn "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

# -----------------------------
# Privilege handling
# -----------------------------
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    die "$EC_UNSUPPORTED" "sudo is required when not running as root."
  fi
fi

# -----------------------------
# OS and PM detection
# -----------------------------
OS="$(uname -s || echo unknown)"
detect_pm() {
  # Prefer more modern managers where overlaps exist
  if command -v apt-get >/dev/null 2>&1; then echo "apt"; return; fi
  if command -v yum >/dev/null 2>&1; then echo "yum"; return; fi
  if command -v dnf >/dev/null 2>&1; then echo "dnf"; return; fi
  if command -v zypper >/dev/null 2>&1; then echo "zypper"; return; fi
  if command -v pacman >/dev/null 2>&1; then echo "pacman"; return; fi
  if command -v apk >/dev/null 2>&1; then echo "apk"; return; fi
  if command -v brew >/dev/null 2>&1; then echo "brew"; return; fi
  echo "none"
}
PM="$(detect_pm)"

info "Detected OS: $OS"
info "Detected package manager: $PM"

if [ "$PM" = "none" ]; then
  die "$EC_UNSUPPORTED" "No supported package manager found (apt/dnf/yum/zypper/pacman/apk/brew)."
fi

# -----------------------------
# Compatibility checks
# -----------------------------
require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    warn "Missing command '$1'. Attempting to install..."
    case "$PM" in
      apt) $SUDO apt-get update -y >/dev/null 2>&1 || true; $SUDO apt-get install -y "$1" || true ;;
      dnf) $SUDO dnf -y install "$1" || true ;;
      yum) $SUDO yum -y install "$1" || true ;;
      zypper) $SUDO zypper -n install "$1" || true ;;
      pacman) $SUDO pacman -Sy --noconfirm "$1" || true ;;
      apk) $SUDO apk add "$1" || true ;;
      brew) brew install "$1" || true ;;
      *) ;;
    esac
  fi
}

require_cmd curl || warn "curl unavailable; some steps may fail."
require_cmd gpg || warn "gpg unavailable; repo key steps may fail."

# Network quick check
if ! curl -Is https://example.com >/dev/null 2>&1; then
  warn "Network check failed or curl not functioning. Proceeding, but downloads may fail."
fi

# YES flag mapping per PM
YES_FLAG=""
case "$PM" in
  apt|dnf|yum|zypper|apk) [ "$ASSUME_YES" = "1" ] && YES_FLAG="-y" ;;
  pacman) [ "$ASSUME_YES" = "1" ] && YES_FLAG="--noconfirm" ;;
  brew) YES_FLAG="" ;; # brew doesn't need -y
esac

# -----------------------------
# PM helpers
# -----------------------------
pm_update() {
  info "Updating package index..."
  case "$PM" in
    apt) $SUDO apt-get update $YES_FLAG ;;
    dnf) $SUDO dnf -y makecache ;;
    yum) $SUDO yum -y makecache ;;
    zypper) $SUDO zypper -n refresh ;;
    pacman) $SUDO pacman -Sy $YES_FLAG ;;
    apk) $SUDO apk update ;;
    brew) brew update ;;
  esac
}

pm_install() {
  # Installs passed packages, idempotently where possible
  case "$PM" in
    apt) $SUDO apt-get install $YES_FLAG "$@" ;;
    dnf) $SUDO dnf install -y "$@" ;;
    yum) $SUDO yum install -y "$@" ;;
    zypper) $SUDO zypper -n install "$@" ;;
    pacman) $SUDO pacman -S --needed $YES_FLAG "$@" ;;
    apk) $SUDO apk add "$@" ;;
    brew) brew install "$@" ;;
  esac
}

# -----------------------------
# Python 3.11 + pip
# -----------------------------
# ensure_pip311(), set_python3_default_to_311(), install_python311()
ensure_pip311() {
  if "$PYTHON_BIN" -m pip --version >/dev/null 2>&1; then
    info "pip for Python 3.11 already present."
    return 0
  fi

  info "Bootstrapping pip for Python 3.11..."
  # Prefer ensurepip, fall back to get-pip
  if "$PYTHON_BIN" -m ensurepip --upgrade >/dev/null 2>&1; then
    info "pip (ensurepip) installed for Python 3.11."
    return 0
  fi

  if curl -fsSL https://bootstrap.pypa.io/get-pip.py | "$PYTHON_BIN" >/dev/null 2>&1; then
    info "pip (get-pip.py) installed for Python 3.11."
    return 0
  fi

  die "$EC_PIP" "Failed to install pip for Python 3.11."
}

# New: set python3 to Python 3.11 as default (idempotent)
set_python3_default_to_311() {
  target_bin="${PYTHON_BIN:-$(command -v python3.11 || true)}"
  if [ -z "$target_bin" ]; then
    warn "python3.11 not found; cannot set python3 default."
    return 0
  fi

  current_ver="$(python3 --version 2>/dev/null | awk '{print $2}' || true)"
  if [ -n "$current_ver" ] && [ "${current_ver%%.*}" -eq 3 ] && [ "$(echo "$current_ver" | cut -d. -f2)" -eq 11 ]; then
    info "python3 already points to Python $current_ver"
    return 0
  fi

  if command -v update-alternatives >/dev/null 2>&1; then
    info "Setting python3 via update-alternatives -> $target_bin"
    $SUDO update-alternatives --install /usr/bin/python3 python3 "$target_bin" 1 || true
    $SUDO update-alternatives --set python3 "$target_bin" || true
  elif command -v alternatives >/dev/null 2>&1; then
    info "Setting python3 via alternatives -> $target_bin"
    $SUDO alternatives --install /usr/bin/python3 python3 "$target_bin" 1 || true
    $SUDO alternatives --set python3 "$target_bin" || true
  else
    info "Setting python3 via symlink in /usr/local/bin -> $target_bin"
    $SUDO install -d /usr/local/bin
    $SUDO ln -sf "$target_bin" /usr/local/bin/python3
  fi

  new_ver="$(python3 --version 2>/dev/null | awk '{print $2}' || true)"
  if [ -n "$new_ver" ] && [ "${new_ver%%.*}" -eq 3 ] && [ "$(echo "$new_ver" | cut -d. -f2)" -eq 11 ]; then
    info "python3 now points to Python $new_ver"
  else
    warn "Unable to confirm python3 pointing to Python 3.11; current: ${new_ver:-unknown}"
  fi
}

install_python311() {
  if command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    info "Python 3.11 already installed: $("$PYTHON_BIN" --version 2>/dev/null || echo 'unknown version')"
    ensure_pip311
    return 0
  fi

  info "Installing Python 3.11..."
  pm_update

  case "$PM" in
    apt)
      # Try native packages
      set +e
      pm_install python3.11 python3.11-venv python3.11-distutils
      rc=$?
      set -e
      if [ $rc -ne 0 ]; then
        die "$EC_PYTHON" "python3.11 not available via apt on this system."
      fi
      ;;
    dnf)
      set +e
      pm_install python3.11
      rc=$?
      set -e
      [ $rc -ne 0 ] && die "$EC_PYTHON" "python3.11 not available via dnf on this system."
      ;;
    yum)
      set +e
      pm_install python3.11
      rc=$?
      set -e
      [ $rc -ne 0 ] && die "$EC_PYTHON" "python3.11 not available via yum on this system."
      ;;
    zypper)
      set +e
      pm_install python311
      rc=$?
      set -e
      [ $rc -ne 0 ] && die "$EC_PYTHON" "python311 not available via zypper on this system."
      PYTHON_BIN="python3.11"
      ;;
    pacman)
      # Arch 'python' is latest; may not be 3.11 anymore
      pm_install python
      if ! command -v python3 >/dev/null 2>&1; then
        die "$EC_PYTHON" "python package installed but python3 not found."
      fi
      # Check version equality
      ver="$(python3 --version 2>/dev/null | awk '{print $2}')"
      if [ "${ver%%.*}" -ne 3 ] || [ "$(echo "$ver" | cut -d. -f2)" -ne 11 ]; then
        die "$EC_PYTHON" "Arch provides Python $ver; required is 3.11. Consider pyenv or a 3.11 package."
      fi
      PYTHON_BIN="python3"
      ;;
    apk)
      pm_install python3 py3-pip
      ver="$(python3 --version 2>/dev/null | awk '{print $2}')"
      if [ "${ver%%.*}" -ne 3 ] || [ "$(echo "$ver" | cut -d. -f2)" -ne 11 ]; then
        die "$EC_PYTHON" "Alpine provides Python $ver; required is 3.11."
      fi
      PYTHON_BIN="python3"
      ;;
    brew)
      # Homebrew has versioned formula
      brew list --versions python@3.11 >/dev/null 2>&1 || brew install python@3.11
      PYTHON_BIN="$(brew --prefix)/opt/python@3.11/bin/python3.11"
      PIP_BIN="$(brew --prefix)/opt/python@3.11/bin/pip3.11"
      ;;
    *)
      die "$EC_UNSUPPORTED" "Unsupported package manager for Python installation."
      ;;
  esac

  info "Installed: $("$PYTHON_BIN" --version 2>/dev/null || echo 'unknown')"
  ensure_pip311
  # Set python3 default to 3.11 after successful install
  set_python3_default_to_311
}

# -----------------------------
# Git
# -----------------------------
install_git() {
  if command -v git >/dev/null 2>&1; then
    info "Git already installed: $(git --version)"
    return 0
  fi

  info "Installing Git..."
  pm_update
  set +e
  pm_install git
  rc=$?
  set -e
  [ $rc -ne 0 ] && die "$EC_GIT" "Failed to install Git."
  info "Git installed: $(git --version)"
}

# -----------------------------
# 1Password (official)
# -----------------------------
install_1password_apt() {
  info "Configuring 1Password apt repository..."
  $SUDO install -d /usr/share/keyrings /etc/apt/sources.list.d /etc/debsig/policies/AC2D62742012EA22 /usr/share/debsig/keyrings/AC2D62742012EA22
  curl -fsSL https://downloads.1password.com/linux/keys/1password.asc | $SUDO gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main" | $SUDO tee /etc/apt/sources.list.d/1password.list >/dev/null
  curl -fsSL https://downloads.1password.com/linux/debian/debsig/1password.pol | $SUDO tee /etc/debsig/policies/AC2D62742012EA22/1password.pol >/dev/null
  curl -fsSL https://downloads.1password.com/linux/keys/1password.asc | $SUDO gpg --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg
  $SUDO apt-get update
  $SUDO apt-get install $YES_FLAG 1password
}

install_1password_dnf() {
  info "Configuring 1Password dnf/yum repository..."
  $SUDO rpm --import https://downloads.1password.com/linux/keys/1password.asc
  $SUDO sh -c 'echo -e "[1password]\nname=1Password Stable Channel\nbaseurl=https://downloads.1password.com/linux/rpm/stable/$basearch\nenabled=1\ngpgcheck=1\nrepo_gpg_check=1\ngpgkey=\"https://downloads.1password.com/linux/keys/1password.asc\"" > /etc/yum.repos.d/1password.repo'
  $SUDO dnf install -y 1password
}

install_1password_zypper() {
  info "Configuring 1Password zypper repository..."
  $SUDO rpm --import https://downloads.1password.com/linux/keys/1password.asc
  $SUDO zypper addrepo https://downloads.1password.com/linux/rpm/stable/x86_64 1password || true
  $SUDO zypper -n install 1password
}

install_1password_pacman_aur() {
  # Official AUR package maintained by 1Password (build needs non-root user)
  if pacman -Qi 1password >/dev/null 2>&1; then
    info "1Password already installed (pacman)."
    return 0
  fi

  info "Installing 1Password via AUR (Arch)"
  pm_update
  pm_install base-devel
  # Ensure git is present (script also installs git earlier)
  command -v git >/dev/null 2>&1 || pm_install git

  TMPDIR="$(mktemp -d)"
  info "Using temp build dir: $TMPDIR"

  # Determine user to build as (avoid building as root)
  BUILD_USER="${SUDO_USER:-$(id -un)}"
  if [ "$(id -u)" -eq 0 ]; then
    info "Building AUR package as user: $BUILD_USER"
    $SUDO -u "$BUILD_USER" sh -c "git clone https://aur.archlinux.org/1password.git '$TMPDIR/1password' && cd '$TMPDIR/1password' && makepkg -si $YES_FLAG"
  else
    git clone https://aur.archlinux.org/1password.git "$TMPDIR/1password"
    cd "$TMPDIR/1password"
    makepkg -si $YES_FLAG
  fi
}

install_1password_brew() {
  if command -v 1password >/dev/null 2>&1; then
    info "1Password already installed (macOS)."
    return 0
  fi
  info "Installing 1Password via Homebrew cask..."
  brew install --cask 1password
}

install_1password() {
  # Idempotency checks
  if command -v 1password >/dev/null 2>&1; then
    info "1Password already installed."
    return 0
  fi

  info "Installing 1Password (official)..."
  case "$PM" in
    apt) install_1password_apt ;;
    dnf) install_1password_dnf ;;
    yum) install_1password_dnf ;; # yum uses same repo file
    zypper) install_1password_zypper ;;
    pacman) install_1password_pacman_aur ;;
    apk) die "$EC_1PASSWORD" "1Password official package not available via apk. Consider tar or snap." ;;
    brew) install_1password_brew ;;
    *) die "$EC_UNSUPPORTED" "Unsupported package manager for 1Password." ;;
  esac

  if ! command -v 1password >/dev/null 2>&1; then
    die "$EC_1PASSWORD" "1Password installation did not produce '1password' executable."
  fi

  info "1Password installed successfully."
}

# -----------------------------
# Main
# -----------------------------
info "Log file: $LOG_FILE"

info "Step 1/3: Installing Python 3.11 + pip"
install_python311

info "Step 2/3: Installing Git"
install_git

info "Step 3/3: Installing 1Password"
install_1password

info "All done. ✅"
exit 0