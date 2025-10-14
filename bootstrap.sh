#!/usr/bin/env bash

set -Eeuo pipefail

# #############################################################################
# GG_Homelab Bootstrap Script
# File & Path: GG_homelab/bootstrap.sh 
# Description:
# This script bootstraps the GG_Homelab project by:
# - Fetches the specified version of the repo from GitHub
# - Installs prerequisites (Terraform, Ansible, Python venv)
# - Runs Terraform to provision infrastructure
# - Runs Ansible to configure the provisioned hosts
# Supported OS: Debian/Ubuntu (apt-based)
# #############################################################################

# ── Config ────────────────────────────────────────────────────────────────────
# Configuration (can be overridden via env vars or script args)
# Usage: ./bootstrap.sh [plan|apply|destroy|check]
# Example: ENVIRONMENT=prod ./bootstrap.sh apply
MODE="${1:-plan}"                         # plan | apply | destroy | check
ENVIRONMENT="${ENVIRONMENT:-dev}"
LOG_DIR="${LOG_DIR:-$HOME/log/gg_homelab}"
LOG_FILE="$LOG_DIR/bootstrap.$(date +%Y%m%d-%H%M%S).log"                          # log file
REPO="${REPO:-GertGerber/GG_Homelab}"
REF="${REF:-v0.1.0}"                      # tag or commit SHA
WORKDIR="${WORKDIR:-$HOME/gg_homelab}"
TF_DIR="${TF_DIR:-terraform/envs/$ENVIRONMENT}"
ANSIBLE_PLAYBOOK="${ANSIBLE_PLAYBOOK:-ansible/site.yml}"
ANSIBLE_INVENTORY="${ANSIBLE_INVENTORY:-ansible/inventories/$ENVIRONMENT}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"          # optional, for private repo / rate limit

# Treat config as read-only after initialization
readonly MODE ENVIRONMENT LOG_DIR REPO REF WORKDIR TF_DIR ANSIBLE_PLAYBOOK ANSIBLE_INVENTORY GITHUB_TOKEN

# ── Script Setup ──────────────────────────────────────────────────────────────
# Change to script dir for relative paths (if needed)
# cd "$(dirname "$0")"

# Check if a command exists
# Usage: if have_cmd git; then echo "Git is installed"; fi  
have_cmd()   { command -v "$1" >/dev/null 2>&1; }

# Absolute path of the current script
# Usage: script_abs
script_abs() {
  if have_cmd readlink; then readlink -f "$0"; elif have_cmd realpath; then realpath "$0"; else
    # Fallback (works in typical Linux shells)
    python3 - <<'PY' 2>/dev/null || printf '%s' "$0"
import os,sys
print(os.path.abspath(sys.argv[1]))
PY
  fi
}
script_abs
readonly SCRIPT_ABS

# ── Error Handling ─────────────────────────────────────────────────────────────
# Safety rails


print_stack() {
  # Skip frame 0 (this function) and 1 (err_trap)
  local i
  for (( i=2; i<${#FUNCNAME[@]}; i++ )); do
    local func="${FUNCNAME[$i]:-MAIN}"
    local src="${BASH_SOURCE[$i]:-?}"
    local line="${BASH_LINENO[$((i-1))]:-?}"
    printf '    at %s (%s:%s)\n' "$func" "$src" "$line"
  done
}

err_trap() {
  local rc=$?
  local cmd=${BASH_COMMAND:-?}
  local src="${BASH_SOURCE[1]:-?}"
  local line="${BASH_LINENO[0]:-?}"

  print_stack

  # Optional: exit non-zero to stop the pipeline/script decisively.
  exit "$rc"
}


cleanup() {
  # Runs on normal and error exits (after err_trap if we exited there)
  # Put idempotent tidy-ups here; avoid failing.
  :
}

trap err_trap  ERR
trap cleanup   EXIT

# ── Logging ────────────────────────────────────────────────────────────────────
# Prepare logging and working dirs
mkdir -p "$LOG_DIR" "$WORKDIR"
readonly LOG_DIR WORKDIR

# Simple logging functions with colours
log_msg() {
  local colour="$1" label="$2"; shift 2
  if [ -n "${NO_COLOR:-}" ] || [ "$(type -t fg)" != "function" ]; then
    printf "[%s] %s\n" "$label" "$*"
  else
    printf "%b[%s]%b %b%s%b\n" "$(fg "$colour")" "$label" "$RESET" "$(fg "$colour")" "$*" "$RESET"
  fi
}
info()     { log_msg BLUE   "INFO" "$@"; }
warn()     { log_msg YELLOW "WARN" "$@"; }
error()    { log_msg RED    "ERROR" "$@"; }
success () { log_msg GREEN  " SUCCESS  " "$@"; }
die()      { err "$*"; exit 1; }
is_tty()   { [[ -t 0 ]]; }


# ── Utilities & Styling ────────────────────────────────────────────────────────────────────
# Colors and text styles for terminal output
# Usage: fg RED; echo "This is red text"; echo "$RESET"
# Note: tput may fail in non-interactive shells; we ignore such errors. 


# # The RESET variable ensures we can reset styles after changing them.
RESET="$(tput sgr0 || true)"

# fg sets the foreground color based on the provided color name.
# Supported colors: BLACK, RED, GREEN, YELLOW, BLUE, MAGENTA (or MAUVE), CYAN (or PEACH), WHITE
# Usage: fg RED; echo "This is red text"; echo "$RESET"
# If the terminal does not support colors, no changes are made.
fg() {
  local name="${1^^}"
  case "$name" in
    BLACK)  tput setaf 0 2>/dev/null || true ;;
    RED)    tput setaf 1 2>/dev/null || true ;;
    GREEN)  tput setaf 2 2>/dev/null || true ;;
    YELLOW) tput setaf 3 2>/dev/null || true ;;
    BLUE)   tput setaf 4 2>/dev/null || true ;;
    MAGENTA|MAUVE) tput setaf 5 2>/dev/null || true ;;
    CYAN|PEACH)    tput setaf 6 2>/dev/null || true ;;
    WHITE)  tput setaf 7 2>/dev/null || true ;;
    *)      printf '' ;;
  esac
}

# Check if a command exists
# Usage: if have_cmd git; then echo "Git is installed"; fi  
have_cmd()   { command -v "$1" >/dev/null 2>&1; }


# JSON escaping helper
# Usage: echo 'Some "text" with special chars\n' | json_escape
# Outputs: "Some \"text\" with special chars\n"
# Requires Python 3
json_escape() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'; }

# ── Devider ────────────────────────────────────────────────────────────────────
# Divider line for better readability in logs
# Usage: divider
#   Outputs a line of dashes to separate sections in the log.
#   Example:
#   divider
#   echo "Starting section..."
#   divider # Outputs: ----------------------------------------
devider() {
  printf '\n'
  printf '%b ────────────────────────────────────────────────────────────────────  %b\n' "$(fg RED)" "$RESET"
  printf '\n'
}


# ── Banners ────────────────────────────────────────────────────────────────────
# Prints a colorful ASCII art banner to the terminal.
# Usage: print_banner
# Note: Colors may not display correctly in all terminal emulators.
#       Designed for typical 80-column terminals.
#       Adjust the ASCII art as needed for different widths.
print_banner() {
  printf '\n'
  printf '%b  ██████╗ ███████╗██████╗ ████████╗     ██████╗ ███████╗██████╗ ██████╗ ███████╗██████╗ %b Infrastructure Installer %b\n' "$(fg RED)" "$(fg PEACH)" "$RESET"
  printf '%b ██╔════╝ ██╔════╝██╔══██╗╚══██╔══╝    ██╔════╝ ██╔════╝██╔══██╗██╔══██╗██╔════╝██╔══██╗%b by GertGerber %b\n' "$(fg RED)" "$(fg BLUE)" "$RESET"
  printf '%b ██║  ███╗█████╗  ██████╔╝   ██║       ██║  ███╗█████╗  ██████╔╝██████╔╝█████╗  ██████╔╝%b Setup your proxmox environment %b\n' "$(fg RED)" "$(fg MAUVE)" "$RESET"
  printf '%b ██║   ██║██╔══╝  ██╔══██╗   ██║       ██║   ██║██╔══╝  ██╔══██╗██╔══██╗██╔══╝  ██╔══██╗%b Enjoy homelab! 🚀%b\n' "$(fg RED)" "$(fg YELLOW)" "$RESET"
  printf '%b ╚██████╔╝███████╗██║  ██║   ██║       ╚██████╔╝███████╗██║  ██║██████╔╝███████╗██║  ██║%b Have fun with roles! 🎉%b\n' "$(fg RED)" "$(fg GREEN)" "$RESET"
  printf '%b  ╚═════╝ ╚══════╝╚═╝  ╚═╝   ╚═╝        ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝%b\n' "$(fg RED)" "$RESET"
  printf '\n'
}

 



# ── Pre-flight / OS check ─────────────────────────────────────────────────────
# Function to check for required commands
require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 2; }; }

# Basic sanity checks
info "Sanity checks"
require curl
require bash
require tar
if ! have_cmd sha256sum; then
  warn "sha256sum not found; skipping tarball verification"
fi

# ── Sudo detection ────────────────────────────────────────────────────────────────────
# Check for root or sudo access
if [[ $EUID -ne 0 ]]; then
  warn "Not running as root. Using sudo where required."
  SUDO="sudo"
else
  SUDO=""
fi
export SUDO

# ── OS detection and apt guard ────────────────────────────────────────────────────────────────────
# Optional: verify host OS if you strictly support Ubuntu
if [[ -f /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  info "Detected: $PRETTY_NAME"
fi
if ! have_cmd apt-get; then
  error "This bootstrap currently supports apt-based systems only (Debian/Ubuntu)."
  exit 1
fi

# ── Fetch Repo Bundle ─────────────────────────────────────────────────────────
fetch_repo() {
  local bundle_url="https://codeload.github.com/$REPO/tar.gz/$REF"
  local auth_header=()
  [[ -n "$GITHUB_TOKEN" ]] && auth_header=(-H "Authorization: Bearer $GITHUB_TOKEN")

  mkdir -p "$WORKDIR"
cd "$WORKDIR"

  info "Fetching bundle @ $REF from $REPO"
  curl -fsSLo repo.tar.gz "${auth_header[@]}" "$bundle_url"

  if have_cmd sha256sum && [[ -f repo.tar.gz.sha256 ]]; then
    info "Verifying tarball checksum"
    sha256sum -c repo.tar.gz.sha256
  else
    warn "No checksum file found; continuing without verification"
  fi

  # Get top-level dir name reliably, then extract and cd
  local top_dir
  top_dir="$(tar -tzf repo.tar.gz | head -1 | cut -f1 -d/)"
tar -xzf repo.tar.gz
  cd "$top_dir"
  success "Repository extracted to: $(pwd)"
}


# ── Main Script Execution ──────────────────────────────────────────────────────
print_banner

devider

fetch_repo