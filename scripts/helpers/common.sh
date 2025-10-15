#!/usr/bin/env bash
set -euo pipefail

# ── Colors & logging ───────────────────────────────────────────
RESET="$(tput sgr0 || true)"
fg() { local name="${1^^}"; case "$name" in
  BLACK) tput setaf 0 2>/dev/null || true ;;
  RED) tput setaf 1 2>/dev/null || true ;;
  GREEN) tput setaf 2 2>/dev/null || true ;;
  YELLOW) tput setaf 3 2>/dev/null || true ;;
  BLUE) tput setaf 4 2>/dev/null || true ;;
  MAGENTA|MAUVE) tput setaf 5 2>/dev/null || true ;;
  CYAN|PEACH) tput setaf 6 2>/dev/null || true ;;
  WHITE) tput setaf 7 2>/dev/null || true ;;
esac; }
info() { printf '%s[+] %s%s\n' "$(fg GREEN)" "$*" "$RESET"; }
warn() { printf '%s[!] %s%s\n' "$(fg YELLOW)" "$*" "$RESET" >&2; }
err()  { printf '%s[✗] %s%s\n' "$(fg RED)" "$*" "$RESET" >&2; }
die()  { err "$*"; exit 1; }
divider() { echo "----------------------------------------"; }
is_tty() { [[ -t 0 ]]; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }
script_abs() {
  if have_cmd readlink; then readlink -f "$0"
  elif have_cmd realpath; then realpath "$0"
  else python3 - <<'PY' 2>/dev/null || printf '%s' "$0"
import os,sys; print(os.path.abspath(sys.argv[1]))
PY
  fi
}
json_escape() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'; }

# ── OS detection & admin group ─────────────────────────────────
detect_os() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    case "${ID:-}" in debian|ubuntu|linuxmint) echo debian ;;
      rhel|centos|rocky|almalinux|fedora) echo rhel ;;
      *) echo debian ;; esac
  else echo debian; fi
}
PKG_FAMILY="${PKG_FAMILY:-$(detect_os)}"
require_debian() { [[ "$PKG_FAMILY" == debian ]] || die "Debian/Ubuntu only (got $PKG_FAMILY)."; }
detect_admin_group() { [[ "$PKG_FAMILY" == debian ]] && echo sudo || echo wheel; }

# ── Privilege & user helpers ──────────────────────────────────
_sudo() { if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi }

ensure_sudo_installed() {
  have_cmd sudo && return 0
  require_debian
  info "Installing sudo…"
  apt-get -o Acquire::Retries=3 update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y sudo
}
validate_username() { local u="$1"; [[ "$u" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; }

# ── Package management ────────────────────────────────────────
# Check if a command exists
# Usage: if have_cmd git; then echo "Git is installed"; fi  
have_cmd()   { command -v "$1" >/dev/null 2>&1; }


# ── Divider ─────────────────────────────────────────────
# Divider line for better readability in logs
# Usage: divider
#   Outputs a line of dashes to separate sections in the log.
#   Example:
#   divider
#   echo "Starting section..."
#   divider # Outputs: ----------------------------------------
divider() { echo "─────────────────────────────────────────────"; }