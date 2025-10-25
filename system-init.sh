#!/usr/bin/env bash
#
# Universal system init script for bash/zsh:
# - Detects package manager (apt, dnf, yum, pacman, zypper, apk, brew)
# - Installs Python 3.11 (+ pip), Git, and 1Password (official repo/package)
# - Securely prompts for master password with timeout + complexity
# - Idempotent, supports interactive/non-interactive modes, logging, exit codes
#
# Usage:
#   system-init.sh [options]
#
# Options:
#   -y, --non-interactive      Run without prompts (assume yes / defaults)
#       --timeout <seconds>    Password input timeout per attempt (default: 60)
#       --log-file <path>      Write logs to given file (default: ./system-init.log)
#       --skip-python          Skip Python installation
#       --skip-git             Skip Git installation
#       --skip-1password       Skip 1Password installation
#   -h, --help                 Show this help and exit
#
# Environment Variables:
#   OP_MASTER_PASSWORD         For non-interactive mode, master password source
#   DEBIAN_FRONTEND=noninteractive (auto-set when non-interactive and apt)
#
# Exit Codes:
#   0  success
#   1  general error
#   2  invalid arguments
#   10 unsupported OS
#   11 no supported package manager found
#   20 python install failure
#   21 python 3.11 unavailable on this manager
#   30 git install failure
#   40 1Password install failure or unsupported on this manager
#   50 password prompt timeout
#   51 password complexity failure
#   52 non-interactive missing password
#   60 insufficient privileges (sudo missing for package manager)
#

# Shell safety for bash/zsh
if [ -n "${BASH_VERSION:-}" ]; then
  set -euo pipefail
elif [ -n "${ZSH_VERSION:-}" ]; then
  set -euo
  setopt pipefail
else
  set -euo
fi
IFS=$'\n\t'

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$SCRIPT_DIR/system-init.log"
NON_INTERACTIVE=0
TIMEOUT=60
PASSWORD_ATTEMPTS=3
SKIP_PYTHON=0
SKIP_GIT=0
SKIP_1PASSWORD=0
PKG_MANAGER=""
OS_TYPE="$(uname -s)"
SUDO=""

# --- Logging helpers ---
timestamp() { date +"%Y-%m-%d %H:%M:%S"; }
log() { # level, msg...
  level="$1"; shift
  msg="$*"
  printf "[%s] [%s] %s\n" "$(timestamp)" "$level" "$msg" | tee -a "$LOG_FILE"
}
log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# Progress helpers
start_step() { printf "==> %s ...\n" "$1" | tee -a "$LOG_FILE"; }
end_step_ok() { printf "    [OK] %s\n" "$1" | tee -a "$LOG_FILE"; }
end_step_skip() { printf "    [SKIP] %s\n" "$1" | tee -a "$LOG_FILE"; }
end_step_fail() { printf "    [FAIL] %s\n" "$1" | tee -a "$LOG_FILE"; }

# Error/exit
die() { code="$1"; shift; log_error "$*"; exit "$code"; }

# Cleanup: clear password from memory
MASTER_PASSWORD=""
cleanup() {
  unset MASTER_PASSWORD
}
on_error() {
  line="${1:-unknown}"
  log_error "Error encountered at line $line"
}
trap 'on_error $LINENO' ERR
trap cleanup EXIT

usage() {
  sed -n '1,120p' "$0" | sed -n 's/^# //p' | sed -n '1,40p'
}

# --- Arg parsing ---
while [ "$#" -gt 0 ]; do
  case "$1" in
    -y|--non-interactive) NON_INTERACTIVE=1 ;;
    --timeout)
      [ "${2:-}" ] || die 2 "Missing value for --timeout"
      TIMEOUT="$2"; shift ;;
    --log-file)
      [ "${2:-}" ] || die 2 "Missing value for --log-file"
      LOG_FILE="$2"; shift ;;
    --skip-python) SKIP_PYTHON=1 ;;
    --skip-git) SKIP_GIT=1 ;;
    --skip-1password) SKIP_1PASSWORD=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die 2 "Unknown option: $1" ;;
  esac
  shift
done

# --- Basic compatibility checks ---
check_os_support() {
  case "$OS_TYPE" in
    Linux|Darwin) return 0 ;;
    *) die 10 "Unsupported OS: $OS_TYPE (expected Linux or macOS/Darwin)" ;;
  esac
}

# --- Package manager detection ---
detect_package_manager() {
  # Prefer apt/dnf/yum on Linux, brew on macOS, handle others
  if [ "$OS_TYPE" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
    PKG_MANAGER="brew"
  elif command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt"
  elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"
  elif command -v yum >/dev/null 2>&1; then
    PKG_MANAGER="yum"
  elif command -v pacman >/dev/null 2>&1; then
    PKG_MANAGER="pacman"
  elif command -v zypper >/dev/null 2>&1; then
    PKG_MANAGER="zypper"
  elif command -v apk >/dev/null 2>&1; then
    PKG_MANAGER="apk"
  elif [ "$OS_TYPE" = "Darwin" ]; then
    PKG_MANAGER="brew" # try brew later (may need install)
  else
    PKG_MANAGER=""
  fi

  if [ -n "$PKG_MANAGER" ]; then
    log_info "Detected package manager: $PKG_MANAGER"
  else
    die 11 "No supported package manager found (apt, dnf, yum, pacman, zypper, apk, brew)"
  fi
}

# --- Privilege check ---
ensure_privileges() {
  case "$PKG_MANAGER" in
    brew) SUDO="" ;; # brew shouldn't be run with sudo
    *)
      if [ "$(id -u)" -eq 0 ]; then
        SUDO=""
      else
        if command -v sudo >/dev/null 2>&1; then
          SUDO="sudo"
        else
          die 60 "This script requires elevated privileges (sudo) for $PKG_MANAGER"
        fi
      fi
      ;;
  esac
}

# --- Repo update ---
update_repos() {
  start_step "Refreshing package repositories"
  case "$PKG_MANAGER" in
    apt)
      if [ "$NON_INTERACTIVE" -eq 1 ]; then export DEBIAN_FRONTEND=noninteractive; fi
      $SUDO apt-get update -y >> "$LOG_FILE" 2>&1 || { end_step_fail "apt-get update"; return 1; }
      ;;
    dnf) $SUDO dnf makecache -y >> "$LOG_FILE" 2>&1 || { end_step_fail "dnf makecache"; return 1; } ;;
    yum) $SUDO yum makecache -y >> "$LOG_FILE" 2>&1 || { end_step_fail "yum makecache"; return 1; } ;;
    pacman) $SUDO pacman -Sy --noconfirm >> "$LOG_FILE" 2>&1 || { end_step_fail "pacman -Sy"; return 1; } ;;
    zypper) $SUDO zypper refresh -y >> "$LOG_FILE" 2>&1 || { end_step_fail "zypper refresh"; return 1; } ;;
    apk) $SUDO apk update >> "$LOG_FILE" 2>&1 || { end_step_fail "apk update"; return 1; } ;;
    brew) brew update >> "$LOG_FILE" 2>&1 || { end_step_fail "brew update"; return 1; } ;;
  esac
  end_step_ok "Repositories refreshed"
  return 0
}

# --- Install helper ---
pkg_install() {
  # Usage: pkg_install pkg1 pkg2 ...
  case "$PKG_MANAGER" in
    apt)
      if [ "$NON_INTERACTIVE" -eq 1 ]; then export DEBIAN_FRONTEND=noninteractive; fi
      $SUDO apt-get install -y "$@" >> "$LOG_FILE" 2>&1
      ;;
    dnf) $SUDO dnf install -y "$@" >> "$LOG_FILE" 2>&1 ;;
    yum) $SUDO yum install -y "$@" >> "$LOG_FILE" 2>&1 ;;
    pacman) $SUDO pacman -S --needed --noconfirm "$@" >> "$LOG_FILE" 2>&1 ;;
    zypper) $SUDO zypper install -y "$@" >> "$LOG_FILE" 2>&1 ;;
    apk) $SUDO apk add --no-cache "$@" >> "$LOG_FILE" 2>&1 ;;
    brew) brew install "$@" >> "$LOG_FILE" 2>&1 ;;
  esac
}

# --- Dependency ensure (curl, gpg, lsb-release when needed) ---
ensure_tool() {
  tool="$1"
  if command -v "$tool" >/dev/null 2>&1; then
    return 0
  fi
  log_info "Installing prerequisite tool: $tool"
  case "$tool" in
    curl)
      case "$PKG_MANAGER" in
        brew) pkg_install curl ;;
        *) pkg_install curl ;;
      esac
      ;;
    gpg|gpg2|gnupg)
      case "$PKG_MANAGER" in
        brew) pkg_install gnupg ;;
        apt) pkg_install gnupg ;;
        dnf|yum) pkg_install gnupg ;;
        pacman) pkg_install gnupg ;;
        zypper) pkg_install gpg2 || pkg_install gnupg ;;
        apk) pkg_install gnupg ;;
      esac
      ;;
    lsb_release)
      case "$PKG_MANAGER" in
        apt) pkg_install lsb-release ;;
        dnf|yum) pkg_install redhat-lsb-core || pkg_install redhat-lsb ;;
        pacman) pkg_install lsb-release ;;
        zypper) pkg_install lsb-release ;;
        apk) pkg_install lsb-release ;;
        brew) true ;; # not needed
      esac
      ;;
  esac
}

# --- Python 3.11 install ---
python311_installed() {
  command -v python3.11 >/dev/null 2>&1
}
ensure_pip_for_python311() {
  if python3.11 -m pip --version >/dev/null 2>&1; then
    return 0
  fi
  ensure_tool curl
  tmp="$(mktemp)"
  start_step "Bootstrapping pip for Python 3.11"
  if curl -fsSL https://bootstrap.pypa.io/get-pip.py -o "$tmp"; then
    if python3.11 "$tmp" >> "$LOG_FILE" 2>&1; then
      rm -f "$tmp"
      end_step_ok "pip installed for Python 3.11"
      return 0
    fi
  fi
  rm -f "$tmp"
  end_step_fail "pip bootstrap for Python 3.11"
  return 1
}
install_python311() {
  if python311_installed; then
    end_step_skip "Python 3.11 already present"
    ensure_pip_for_python311 || die 20 "Failed to ensure pip for Python 3.11"
    return 0
  fi

  start_step "Installing Python 3.11"
  case "$PKG_MANAGER" in
    apt)
      update_repos || true
      # Try native first
      if pkg_install python3.11 python3.11-venv python3.11-distutils; then
        ensure_pip_for_python311 || die 20 "pip setup failed for Python 3.11"
        end_step_ok "Python 3.11 installed (apt)"
        return 0
      fi
      # Ubuntu: add deadsnakes PPA
      if command -v lsb_release >/dev/null 2>&1; then
        distro="$(lsb_release -is || echo "")"
      else
        distro=""
      fi
      if [ "$distro" = "Ubuntu" ]; then
        ensure_tool curl
        pkg_install software-properties-common || true
        $SUDO add-apt-repository -y ppa:deadsnakes/ppa >> "$LOG_FILE" 2>&1 || true
        update_repos || true
        if pkg_install python3.11 python3.11-venv python3.11-distutils; then
          ensure_pip_for_python311 || die 20 "pip setup failed for Python 3.11"
          end_step_ok "Python 3.11 installed via deadsnakes"
          return 0
        fi
      fi
      end_step_fail "Python 3.11 not available via apt"
      die 21 "Python 3.11 unavailable via apt on this system"
      ;;
    dnf)
      update_repos || true
      if pkg_install python3.11; then
        ensure_pip_for_python311 || die 20 "pip setup failed for Python 3.11"
        end_step_ok "Python 3.11 installed (dnf)"
        return 0
      fi
      # Fallback check
      end_step_fail "Python 3.11 not available via dnf"
      die 21 "Python 3.11 unavailable via dnf on this system"
      ;;
    yum)
      update_repos || true
      if pkg_install python3.11; then
        ensure_pip_for_python311 || die 20 "pip setup failed for Python 3.11"
        end_step_ok "Python 3.11 installed (yum)"
        return 0
      fi
      end_step_fail "Python 3.11 not available via yum"
      die 21 "Python 3.11 unavailable via yum on this system"
      ;;
    pacman)
      update_repos || true
      if pkg_install python; then
        if python3 --version 2>/dev/null | grep -q '3\.11\.'; then
          ln -sf "$(command -v python3)" /usr/local/bin/python3.11 2>/dev/null || true
          ensure_pip_for_python311 || die 20 "pip setup failed for Python 3.11"
          end_step_ok "Python 3.11 satisfied via system python (pacman)"
          return 0
        fi
      fi
      end_step_fail "Python 3.11 exact version not available via pacman"
      die 21 "Python 3.11 unavailable via pacman on this system"
      ;;
    zypper)
      update_repos || true
      if pkg_install python311 python311-pip || pkg_install python3 python3-pip; then
        if command -v python3.11 >/dev/null 2>&1; then
          end_step_ok "Python 3.11 installed (zypper)"
          return 0
        fi
        if python3 --version 2>/dev/null | grep -q '3\.11\.'; then
          ln -sf "$(command -v python3)" /usr/local/bin/python3.11 2>/dev/null || true
          end_step_ok "Python 3.11 satisfied via system python (zypper)"
          return 0
        fi
      fi
      end_step_fail "Python 3.11 not available via zypper"
      die 21 "Python 3.11 unavailable via zypper on this system"
      ;;
    apk)
      update_repos || true
      if pkg_install python3 py3-pip; then
        if python3 --version 2>/dev/null | grep -q '3\.11\.'; then
          ln -sf "$(command -v python3)" /usr/local/bin/python3.11 2>/dev/null || true
          end_step_ok "Python 3.11 satisfied via system python (apk)"
          return 0
        fi
      fi
      end_step_fail "Python 3.11 not available via apk"
      die 21 "Python 3.11 unavailable via apk on this system"
      ;;
    brew)
      update_repos || true
      if brew list --versions python@3.11 >/dev/null 2>&1 || brew install python@3.11; then
        brew link --overwrite --force python@3.11 >> "$LOG_FILE" 2>&1 || true
        if command -v python3.11 >/dev/null 2>&1; then
          end_step_ok "Python 3.11 installed (brew)"
          return 0
        fi
      fi
      end_step_fail "Python 3.11 install via brew"
      die 21 "Python 3.11 unavailable via brew on this system"
      ;;
  esac
}

# --- Git install ---
git_installed() {
  command -v git >/dev/null 2>&1
}
install_git() {
  if git_installed; then
    end_step_skip "Git already present"
    return 0
  fi
  start_step "Installing Git"
  update_repos || true
  if [ "$PKG_MANAGER" = "brew" ]; then
    if pkg_install git; then end_step_ok "Git installed (brew)"; return 0; fi
  else
    if pkg_install git; then end_step_ok "Git installed ($PKG_MANAGER)"; return 0; fi
  fi
  end_step_fail "Git installation"
  die 30 "Failed to install Git via $PKG_MANAGER"
}

# --- 1Password install (official) ---
onepassword_installed() {
  command -v 1password >/dev/null 2>&1 || command -v 1password-cli >/dev/null 2>&1 || command -v op >/dev/null 2>&1
}
install_1password_apt() {
  if [ -f /etc/apt/sources.list.d/1password.list ]; then
    log_info "1Password APT repo already configured"
  else
    ensure_tool curl
    ensure_tool gpg
    $SUDO sh -c 'curl -fsSL https://downloads.1password.com/linux/keys/1password.asc | gpg --dearmor -o /usr/share/keyrings/1password-archive-keyring.gpg' >> "$LOG_FILE" 2>&1
    arch="$(dpkg --print-architecture)"
    echo "deb [signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/${arch} stable main" | $SUDO tee /etc/apt/sources.list.d/1password.list >/dev/null
    $SUDO mkdir -p /etc/debsig/usersettings/AC2D627F /usr/share/debsig/keyrings/AC2D627F
    $SUDO sh -c 'curl -fsSL https://downloads.1password.com/linux/debian/debsig/1password.pol > /etc/debsig/usersettings/AC2D627F/1password.pol'
    $SUDO sh -c 'curl -fsSL https://downloads.1password.com/linux/keys/1password.asc | gpg --dearmor > /usr/share/debsig/keyrings/AC2D627F/pubring.gpg'
  fi
  update_repos || true
  if pkg_install 1password; then return 0; fi
  return 1
}
install_1password_dnf_yum() {
  repo_file="/etc/yum.repos.d/1password.repo"
  if [ -f "$repo_file" ]; then
    log_info "1Password RPM repo already configured"
  else
    ensure_tool curl
    $SUDO rpm --import https://downloads.1password.com/linux/keys/1password.asc >> "$LOG_FILE" 2>&1 || true
    $SUDO sh -c "cat > $repo_file <<'EOF'
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF" >> "$LOG_FILE" 2>&1
  fi
  update_repos || true
  if [ "$PKG_MANAGER" = "dnf" ]; then
    if pkg_install 1password; then return 0; fi
  else
    if pkg_install 1password; then return 0; fi
  fi
  return 1
}
install_1password_zypper() {
  # Use RPM repo similar to dnf/yum
  repo_alias="1password"
  if zypper lr | grep -q "$repo_alias"; then
    log_info "1Password zypper repo already configured"
  else
    ensure_tool curl
    $SUDO zypper ar -f "https://downloads.1password.com/linux/rpm/stable/\$basearch" "$repo_alias" >> "$LOG_FILE" 2>&1 || true
    $SUDO rpm --import https://downloads.1password.com/linux/keys/1password.asc >> "$LOG_FILE" 2>&1 || true
  fi
  update_repos || true
  if pkg_install 1password; then return 0; fi
  return 1
}
install_1password_brew() {
  # Desktop app
  if brew list --cask 1password >/dev/null 2>&1 || brew install --cask 1password >> "$LOG_FILE" 2>&1; then
    return 0
  fi
  return 1
}
install_1password() {
  if onepassword_installed; then
    end_step_skip "1Password already present"
    return 0
  fi
  start_step "Installing 1Password (official)"
  case "$PKG_MANAGER" in
    apt)
      if install_1password_apt; then end_step_ok "1Password installed (apt)"; return 0; fi
      ;;
    dnf|yum)
      if install_1password_dnf_yum; then end_step_ok "1Password installed ($PKG_MANAGER)"; return 0; fi
      ;;
    zypper)
      if install_1password_zypper; then end_step_ok "1Password installed (zypper)"; return 0; fi
      ;;
    brew)
      if install_1password_brew; then end_step_ok "1Password installed (brew cask)"; return 0; fi
      ;;
    pacman|apk)
      end_step_fail "1Password official package not available via $PKG_MANAGER"
      die 40 "1Password official package unsupported on $PKG_MANAGER"
      ;;
  esac
  end_step_fail "1Password installation"
  die 40 "Failed to install 1Password via $PKG_MANAGER"
}

# --- Secure password prompt ---
has_upper() { echo "$1" | grep -q '[A-Z]'; }
has_lower() { echo "$1" | grep -q '[a-z]'; }
has_digit() { echo "$1" | grep -q '[0-9]'; }
has_special() { echo "$1" | grep -q '[^A-Za-z0-9]'; }
validate_password() {
  pw="$1"
  [ "${#pw}" -ge 12 ] && has_upper "$pw" && has_lower "$pw" && has_digit "$pw" && has_special "$pw"
}
prompt_password_interactive() {
  attempts=0
  while [ "$attempts" -lt "$PASSWORD_ATTEMPTS" ]; do
    attempts=$((attempts + 1))
    printf "Enter master password (attempt %d/%d): " "$attempts" "$PASSWORD_ATTEMPTS" 1>&2
    # suppress echo, with timeout
    if read -r -s -t "$TIMEOUT" pw; then
      printf "\n" 1>&2
      if validate_password "$pw"; then
        MASTER_PASSWORD="$pw"
        return 0
      else
        log_warn "Password does not meet complexity requirements: min 12 chars, upper, lower, digit, special"
      fi
    else
      printf "\n" 1>&2
      log_warn "Password entry timed out after ${TIMEOUT}s"
    fi
  done
  return 1
}
obtain_master_password() {
  start_step "Collecting master password"
  if [ "$NON_INTERACTIVE" -eq 1 ]; then
    if [ -n "${OP_MASTER_PASSWORD:-}" ]; then
      if validate_password "$OP_MASTER_PASSWORD"; then
        MASTER_PASSWORD="$OP_MASTER_PASSWORD"
        end_step_ok "Master password captured (non-interactive)"
        return 0
      else
        end_step_fail "Master password complexity invalid (non-interactive)"
        die 51 "Master password fails complexity requirements"
      fi
    else
      end_step_fail "Missing OP_MASTER_PASSWORD env var (non-interactive)"
      die 52 "OP_MASTER_PASSWORD not set in non-interactive mode"
    fi
  else
    if prompt_password_interactive; then
      end_step_ok "Master password captured"
      return 0
    else
      end_step_fail "Password input timed out or invalid"
      die 50 "Password input timed out or invalid"
    fi
  fi
}

# --- Main ---
main() {
  log_info "Starting $SCRIPT_NAME (log: $LOG_FILE)"
  check_os_support
  detect_package_manager
  ensure_privileges

  # Optional system prep
  update_repos || log_warn "Repo refresh failed; proceeding"

  # Securely obtain master password early
  obtain_master_password

  # Install Python 3.11 (+ pip)
  if [ "$SKIP_PYTHON" -eq 1 ]; then
    end_step_skip "Python installation skipped by flag"
  else
    install_python311
  fi

  # Install Git
  if [ "$SKIP_GIT" -eq 1 ]; then
    end_step_skip "Git installation skipped by flag"
  else
    install_git
  fi

  # Install 1Password (official)
  if [ "$SKIP_1PASSWORD" -eq 1 ]; then
    end_step_skip "1Password installation skipped by flag"
  else
    install_1password
  fi

  log_info "All requested operations completed successfully."
  exit 0
}

main "$@"