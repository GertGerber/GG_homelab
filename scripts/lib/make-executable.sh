#!/usr/bin/env bash
set -euo pipefail

# ── Load project helpers ─────────────────────────────────────────────
# ---------------- Get sources Start ----------------
# Resolve project root if DOTS isn't set
DOTS="${DOTS:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"

# Load helper libraries (logging, divider, have_cmd, _sudo, etc.)
# shellcheck disable=SC1091
source "$DOTS/scripts/helpers/common.sh"
# shellcheck disable=SC1091
source "$DOTS/scripts/helpers/pkg.sh"
# shellcheck disable=SC1091
source "$DOTS/scripts/helpers/error_handling.sh"
export DOTS_LOG="$HOME/.local/share/dotfilez/postdeploy.log"
# ---------------- Get sources End ------------------

# ── Determine log path (use invoking user if sudo) ───────────────────
_resolve_user_home() {
  if [[ ${EUID:-$(id -u)} -eq 0 && -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    eval echo "~${SUDO_USER}"
  else
    printf "%s\n" "${HOME}"
  fi
}
USER_HOME="$(_resolve_user_home)"
LOG_DIR="${DOTFILEZ_LOG_DIR:-$USER_HOME/.local/share/dotfilez}"
mkdir -p "$LOG_DIR" || true
LOG_FILE="$LOG_DIR/make_executable.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# ── Main logic ───────────────────────────────────────────────────────
make_exec() {
  local target="${1:-}"
  [[ -n "$target" ]] || die "Usage: $0 <file-or-directory>"

  if [[ -d "$target" ]]; then
    info "Directory selected: $target"
    mapfile -d '' files < <(find "$target" -type f -name '*.sh' -print0)
    if (( ${#files[@]} == 0 )); then
      warn "No *.sh files found under: $target"
      return 0
    fi
    printf '%s\0' "${files[@]}" | xargs -0 chmod +x
    info "Marked ${#files[@]} shell script(s) executable."
  elif [[ -f "$target" ]]; then
    info "File selected: $target"
    chmod +x -- "$target"
    [[ "$target" == *.sh ]] || warn "File does not end with .sh; made it executable anyway."
    info "Marked 1 file executable."
  else
    die "Selection is neither a regular file nor a directory: $target"
  fi
}

main() {
  local selection="${1:-${DOTS:-$PWD}}"
  make_exec "$selection"
}
main "$@"
