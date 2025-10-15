#!/usr/bin/env bash
# Safety rails
set -Eeuo pipefail
shopt -s extdebug           # improves FUNCNAME/BASH_LINENO fidelity
set -o errtrace             # make ERR trap fire in functions/subshells

# Optional: central log file
: "${DOTS_LOG:=/tmp/dotfilez-setup.log}"

log() { printf '%s %s\n' "$(date -Is)" "$*" | tee -a "$DOTS_LOG" >&2; }

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

  log "ERROR: command failed
  status : $rc
  command: $cmd
  location: $src:$line"
  print_stack | tee -a "$DOTS_LOG" >&2

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
