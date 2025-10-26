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

# Debug helpers and global traps
DEBUG="${DEBUG:-0}"
debug() { [ "$DEBUG" = "1" ] && log "DEBUG $*"; }

if [ "$DEBUG" = "1" ]; then
  info "DEBUG enabled; verbose execution will be shown."
  set -x
fi

# Trap exit to log success or failure
trap '
  rc=$?
  if [ "$rc" -ne 0 ]; then
    error "Script failed with exit code $rc"
  else
    info "Script completed successfully."
  fi
' EXIT

# Additional signal traps for better diagnostics
trap 'error "Interrupted (SIGINT)"; exit 130' INT
trap 'error "Terminated (SIGTERM)"; exit 143' TERM
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
# Ensure Homebrew is installed on macOS (Darwin)
if [ "$OS" = "Darwin" ] && ! command -v brew >/dev/null 2>&1; then
  info "Homebrew not detected; installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Update PATH for current session if brew was installed
  eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
  eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null || true
fi
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
# set_python3_default_to_311()
set_python3_default_to_311() {
  # Amazon Linux yum relies on the system python3 (3.9)
  return 0
  target_bin="${PYTHON_BIN:-python3.11}"
  abs_target="$(command -v "$target_bin" 2>/dev/null || true)"
  if [ -z "$abs_target" ]; then
    abs_target="$(command -v python3.11 2>/dev/null || true)"
  fi
  if [ -z "$abs_target" ]; then
    warn "python3.11 binary not found; cannot set python3 default."
    return 0
  fi

  current_ver="$(python3 --version 2>/dev/null | awk '{print $2}' || true)"
  if [ -n "$current_ver" ] && [ "${current_ver%%.*}" -eq 3 ] && [ "$(echo "$current_ver" | cut -d. -f2)" -eq 11 ]; then
    info "python3 already points to Python $current_ver"
    return 0
  fi

  configured=0

  if command -v update-alternatives >/dev/null 2>&1; then
    info "Setting python3 via update-alternatives -> $abs_target"
    set +e
    $SUDO update-alternatives --install /usr/bin/python3 python3 "$abs_target" 311
    rc1=$?
    $SUDO update-alternatives --set python3 "$abs_target"
    rc2=$?
    set -e
    if [ $rc1 -eq 0 ] && [ $rc2 -eq 0 ]; then
      configured=1
    else
      warn "update-alternatives failed (install rc=$rc1, set rc=$rc2); will try alternatives or symlink."
    fi
  fi

  if [ $configured -eq 0 ] && command -v alternatives >/dev/null 2>&1; then
    info "Setting python3 via alternatives -> $abs_target"
    set +e
    $SUDO alternatives --install /usr/bin/python3 python3 "$abs_target" 311
    rc1=$?
    $SUDO alternatives --set python3 "$abs_target"
    rc2=$?
    set -e
    if [ $rc1 -eq 0 ] && [ $rc2 -eq 0 ]; then
      configured=1
    else
      warn "alternatives failed (install rc=$rc1, set rc=$rc2); will use symlink fallback."
    fi
  fi

  if [ $configured -eq 0 ]; then
    # Fallback: symlink to ensure `python3` resolves to 3.11
    if printf "%s" "$PATH" | tr ':' '\n' | grep -q "^/usr/local/bin$"; then
      info "Setting python3 via symlink in /usr/local/bin -> $abs_target"
      $SUDO install -d /usr/local/bin
      $SUDO ln -sf "$abs_target" /usr/local/bin/python3
    else
      info "Setting python3 via symlink in /usr/bin -> $abs_target"
      $SUDO ln -sf "$abs_target" /usr/bin/python3
    fi
  fi

  new_ver="$(python3 --version 2>/dev/null | awk '{print $2}' || true)"
  new_path="$(command -v python3 2>/dev/null || true)"
  if [ -n "$new_ver" ] && [ "${new_ver%%.*}" -eq 3 ] && [ "$(echo "$new_ver" | cut -d. -f2)" -eq 11 ]; then
    info "python3 now points to Python $new_ver at $new_path"
  else
    warn "Unable to confirm python3 pointing to Python 3.11; current: ${new_ver:-unknown} at ${new_path:-unknown}"
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

verify_and_fix_python3_symlink_darwin() {
  info "Verifying python3 symlink on macOS (Darwin)..."
  cur_ver="$(python3 --version 2>/dev/null | awk '{print $2}' || true)"
  if [ -n "$cur_ver" ] && [ "${cur_ver%%.*}" -eq 3 ] && [ "$(echo "$cur_ver" | cut -d. -f2)" -eq 11 ]; then
    info "python3 already resolves to Python $cur_ver"
    return 0
  fi

  target="$PYTHON_BIN"
  if [ -z "$target" ] || [ ! -x "$target" ]; then
    prefix="$(command -v brew >/dev/null 2>&1 && brew --prefix || echo "/opt/homebrew")"
    alt="$prefix/opt/python@3.11/bin/python3.11"
    if [ -x "$alt" ]; then
      target="$alt"
    else
      warn "Python 3.11 binary not found at expected locations."
      return 1
    fi
  fi

  link_dir="/usr/local/bin"
  link_path="$link_dir/python3"

  if [ ! -d "$link_dir" ]; then
    info "Creating directory $link_dir"
    $SUDO install -d "$link_dir" 2>/dev/null || {
      warn "Failed to create $link_dir; cannot fix symlink automatically."
      return 1
    }
  fi

  info "Setting symlink $link_path -> $target"
  if $SUDO ln -sf "$target" "$link_path" 2>/dev/null; then
    info "Symlink updated: $link_path -> $target"
  else
    warn "Failed to set symlink at $link_path; attempting alternative locations."
    if command -v brew >/dev/null 2>&1; then
      prefix="$(brew --prefix)"
      link_path_alt="$prefix/bin/python3"
      if $SUDO ln -sf "$target" "$link_path_alt" 2>/dev/null; then
        info "Symlink updated: $link_path_alt -> $target"
      else
        warn "Failed to update symlink at $link_path_alt."
        return 1
      fi
    else
      return 1
    fi
  fi

  # Ensure /usr/local/bin is early in PATH for this session
  first_path_component="$(printf "%s" "$PATH" | tr ':' '\n' | awk 'NR==1')"
  if [ "$first_path_component" != "/usr/local/bin" ]; then
    if ! printf "%s" "$PATH" | tr ':' '\n' | grep -q "^/usr/local/bin$"; then
      info "Prepending /usr/local/bin to PATH for current session"
      export PATH="/usr/local/bin:$PATH"
    else
      info "Moving /usr/local/bin to front of PATH for current session"
      NEWPATH="/usr/local/bin"
      OLDIFS="$IFS"; IFS=':'
      for d in $PATH; do
        [ "$d" = "/usr/local/bin" ] && continue
        NEWPATH="$NEWPATH:$d"
      done
      IFS="$OLDIFS"
      export PATH="$NEWPATH"
    fi
  fi

  hash -r 2>/dev/null || true

  new_ver="$(python3 --version 2>/dev/null | awk '{print $2}' || true)"
  new_path="$(command -v python3 2>/dev/null || true)"
  if [ -n "$new_ver" ] && [ "${new_ver%%.*}" -eq 3 ] && [ "$(echo "$new_ver" | cut -d. -f2)" -eq 11 ]; then
    info "python3 now resolves to Python $new_ver at $new_path"
    return 0
  else
    warn "python3 still does not resolve to Python 3.11; current: ${new_ver:-unknown} at ${new_path:-unknown}"
    return 1
  fi
}

setup_brew_env_darwin() {
  # Configure Homebrew env, define refreshenv alias, persist to ~/.zshrc, and reload
  if [ "$OS" != "Darwin" ]; then
    return 0
  fi

  if ! command -v brew >/dev/null 2>&1; then
    warn "Homebrew not installed; skipping environment setup."
    return 0
  fi

  info "Configuring Homebrew environment for current session"
  rc=0
  set +e
  eval "$(/opt/homebrew/bin/brew shellenv)" >/dev/null 2>&1
  rc=$?
  if [ $rc -ne 0 ]; then
    eval "$(/usr/local/bin/brew shellenv)" >/dev/null 2>&1
    rc=$?
  fi
  set -e
  if [ $rc -eq 0 ]; then
    info "Homebrew environment loaded."
  else
    warn "Failed to load Homebrew environment."
  fi

  # Define alias in current session (ignore failure if shell doesn't support alias)
  set +e
  alias refreshenv='eval "$(/opt/homebrew/bin/brew shellenv)"'
  alias_rc=$?
  set -e
  if [ $alias_rc -eq 0 ]; then
    info "Alias 'refreshenv' defined for current session."
  else
    warn "Alias not supported in current shell; persisting to ~/.zshrc only."
  fi

  # Persist alias to user's ~/.zshrc idempotently
  TARGET_USER="${SUDO_USER:-$(id -un)}"
  TARGET_HOME="$(eval echo "~$TARGET_USER")"
  ZSHRC="$TARGET_HOME/.zshrc"
  if [ ! -e "$ZSHRC" ]; then
    info "Creating $ZSHRC"
    if touch "$ZSHRC" 2>/dev/null; then
      info "$ZSHRC created."
    else
      warn "Unable to create $ZSHRC; alias not persisted."
      return 0
    fi
  fi

  if grep -q "alias refreshenv='eval \"\$(/opt/homebrew/bin/brew shellenv)\"'" "$ZSHRC"; then
    info "Alias 'refreshenv' already present in $ZSHRC."
  else
    info "Persisting alias 'refreshenv' into $ZSHRC"
    printf "alias refreshenv='eval \"\$(/opt/homebrew/bin/brew shellenv)\"'\n" >> "$ZSHRC" 2>/dev/null || {
      warn "Failed to append alias to $ZSHRC."
    }
  fi

  # Reload shell configuration
  if command -v zsh >/dev/null 2>&1; then
    info "Reloading zsh configuration from $ZSHRC"
    set +e
    zsh -c "source \"$ZSHRC\"" >/dev/null 2>&1
    zsh_rc=$?
    set -e
    if [ $zsh_rc -eq 0 ]; then
      info "zsh configuration reloaded."
    else
      warn "Failed to source $ZSHRC with zsh; open a new shell."
    fi
  else
    info "zsh not found; attempting POSIX dot-sourcing"
    set +e
    . "$ZSHRC" >/dev/null 2>&1
    dot_rc=$?
    set -e
    if [ $dot_rc -eq 0 ]; then
      info "Configuration loaded via POSIX source."
    else
      warn "Failed to source $ZSHRC in current shell; open a new shell."
    fi
  fi
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
  # https://support.1password.com/install-linux/#fedora-or-red-hat-enterprise-linux
  info "Configuring 1Password dnf/yum repository..."
  # sudo rpm --import https://downloads.1password.com/linux/keys/1password.asc
  $SUDO rpm --import https://downloads.1password.com/linux/keys/1password.asc
  # sudo sh -c 'echo -e "[1password]\nname=1Password Stable Channel\nbaseurl=https://downloads.1password.com/linux/rpm/stable/\$basearch\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=\"https://downloads.1password.com/linux/keys/1password.asc\"" > /etc/yum.repos.d/1password.repo'
  $SUDO sh -c 'echo -e "[1password]\nname=1Password Stable Channel\nbaseurl=https://downloads.1password.com/linux/rpm/stable/\$basearch\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=\"https://downloads.1password.com/linux/keys/1password.asc\"" > /etc/yum.repos.d/1password.repo'
  # sudo dnf install 1password
  info "Installing 1Password via dnf..."
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

# Verify completion: check Python 3.11, pip, Git, and 1Password
verify_completion() {
  info "Verifying final installation state..."
  # Python 3.11
  py_ver="$(python3 --version 2>/dev/null | awk '{print $2}' || true)"
  if [ -z "$py_ver" ]; then
    error "python3 not found on PATH."
    return 1
  fi
  if [ "${py_ver%%.*}" -ne 3 ] || [ "$(echo "$py_ver" | cut -d. -f2)" -ne 11 ]; then
    error "python3 version check failed: got $py_ver, expected 3.11.x"
    return 1
  fi
  info "python3 version OK: $py_ver"

  # pip for 3.11
  if ! "$PYTHON_BIN" -m pip --version >/dev/null 2>&1; then
    error "pip for Python 3.11 not available."
    return 1
  fi
  info "pip for Python 3.11 OK."

  # Git
  if ! command -v git >/dev/null 2>&1; then
    error "git not found after installation."
    return 1
  fi
  info "git OK: $(git --version)"

  # 1Password
  if ! command -v 1password >/dev/null 2>&1; then
    error "1password CLI not found after installation."
    return 1
  fi
  info "1Password OK."
  info "Verification complete."
}

# Main
info "Log file: $LOG_FILE"

ensure_script_executable() {
  if [ ! -x "$0" ]; then
    info "Setting executable permission on $0"
    if chmod +x "$0" 2>/dev/null; then
      info "Executable permission set."
    else
      if [ -n "$SUDO" ]; then
        if $SUDO chmod +x "$0" 2>/dev/null; then
          info "Executable permission set via sudo."
        else
          warn "Failed to set executable permission via sudo."
        fi
      else
        warn "Failed to set executable permission; run: chmod +x '$0'"
      fi
    fi
  else
    info "Script already executable."
  fi
}
# Ensure script is executable for subsequent runs
ensure_script_executable

# -----------------------------
# PM helpers
# -----------------------------
# PM helpers
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

# New: Run full system update based on detected package manager
pm_system_update() {
  info "Running system package update via '$PM'..."
  rc=0
  case "$PM" in
    apt)
      set +e
      $SUDO apt-get update $YES_FLAG
      rc=$?
      # If non-interactive, also upgrade packages
      if [ $rc -eq 0 ] && [ "$ASSUME_YES" = "1" ]; then
        $SUDO apt-get upgrade -y
        rc=$?
      fi
      set -e
      ;;
    yum)
      set +e
      $SUDO yum update -y
      rc=$?
      set -e
      ;;
    dnf)
      set +e
      $SUDO dnf update -y
      rc=$?
      set -e
      ;;
    zypper)
      set +e
      $SUDO zypper -n refresh
      rc=$?
      if [ $rc -eq 0 ]; then
        $SUDO zypper -n update
        rc=$?
      fi
      set -e
      ;;
    pacman)
      set +e
      $SUDO pacman -Syu $YES_FLAG
      rc=$?
      set -e
      ;;
    apk)
      set +e
      $SUDO apk update
      rc=$?
      if [ $rc -eq 0 ]; then
        $SUDO apk upgrade
        rc=$?
      fi
      set -e
      ;;
    brew)
      set +e
      brew update
      rc=$?
      if [ $rc -eq 0 ]; then
        brew upgrade
        rc=$?
      fi
      set -e
      ;;
    *)
      die "$EC_UNSUPPORTED" "No supported package manager found for system update."
      ;;
  esac

  if [ $rc -ne 0 ]; then
    error "System update failed via '$PM' (exit $rc)."
  else
    info "System update via '$PM' completed successfully."
  fi
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

# Pre-flight: update the system via detected package manager
info "Pre-flight: Updating system packages"
pm_system_update

info "Step 1/3: Installing Python 3.11 + pip"
install_python311
# macOS post-install: brew env setup, alias persistence, and symlink verification
if [ "$OS" = "Darwin" ]; then
  info "macOS: Setting up Homebrew environment and alias"
  setup_brew_env_darwin
  verify_and_fix_python3_symlink_darwin || warn "macOS python3 symlink verification/correction encountered issues."
fi

info "Step 2/3: Installing Git"
install_git

info "Step 3/3: Installing 1Password"
install_1password

# Final verification
verify_completion

info "All done. ✅"
exit 0