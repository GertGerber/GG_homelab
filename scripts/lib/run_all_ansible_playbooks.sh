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

# ── Run All Ansible Playbooks ─────────────────────────────────────────────
# Default locations; can be overridden via env vars
: "${PLAYBOOK_DIR:=${DOTS}/ansible/playbooks/enable}"
: "${INVENTORY:=${DOTS}/ansible/inventories/production/hosts.ini}"
: "${ANSIBLE_LIMIT:=}"
: "${ANSIBLE_TAGS:=}"
: "${ANSIBLE_EXTRA_OPTS:=}"

if [[ ! -d "${PLAYBOOK_DIR}" ]]; then
  echo "ERROR: PLAYBOOK_DIR not found: ${PLAYBOOK_DIR}" >&2
  exit 1
fi

if [[ ! -f "${INVENTORY}" ]]; then
  echo "ERROR: inventory file not found: ${INVENTORY}" >&2
  exit 1
fi

# Ensure ansible-playbook is available
if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "ERROR: ansible-playbook not found in PATH" >&2
  exit 1
fi

echo "Using inventory: ${INVENTORY}"
echo "Scanning playbooks in: ${PLAYBOOK_DIR}"

# Build base args
BASE_ARGS=(-i "${INVENTORY}")
if [[ -n "${ANSIBLE_LIMIT}" ]]; then
  BASE_ARGS+=(--limit "${ANSIBLE_LIMIT}")
fi
if [[ -n "${ANSIBLE_TAGS}" ]]; then
  BASE_ARGS+=(--tags "${ANSIBLE_TAGS}")
fi

# Run each playbook in natural sort order
mapfile -t playbooks < <(find "${PLAYBOOK_DIR}" -maxdepth 1 -type f \( -name "*.yml" -o -name "*.yaml" \) | sort -V)

if (( ${#playbooks[@]} == 0 )); then
  echo "No playbooks found in ${PLAYBOOK_DIR}" >&2
  exit 1
fi

rc=0
for pb in "${playbooks[@]}"; do
  echo "================================================================"
  echo "Running: ${pb}"
  echo "----------------------------------------------------------------"
  if ! ansible-playbook "${BASE_ARGS[@]}" ${ANSIBLE_EXTRA_OPTS} "${pb}"; then
    echo "Playbook failed: ${pb}" >&2
    rc=1
    break
  fi
  echo
done

exit "${rc}"
