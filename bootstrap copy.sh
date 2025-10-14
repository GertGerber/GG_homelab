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

# ── Helpers ───────────────────────────────────────────────────────────────────
to_upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }
has_cmd()  { command -v "$1" >/dev/null 2>&1; }
require()  { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 2; }; }

# ── Color Setup (robust detection + fallbacks) ────────────────────────────────
# Controls:
#   NO_COLOR=1      -> force no color
#   FORCE_COLOR=1   -> force truecolor
#   COLOR_MODE=...  -> one of: truecolor|ansi256|ansi16|none (overrides auto)

to_upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

FLAVOUR="${CATPPUCCIN_FLAVOUR:-LATTE}"; FLAVOUR="$(to_upper "$FLAVOUR")"
case "$FLAVOUR" in LATTE|FRAPPE|MACCHIATO|MOCHA) : ;; *) FLAVOUR="LATTE";; esac
readonly FLAVOUR

# Get RGB values for Catppuccin colours
# Usage: get_rgb COLOR_NAME
# Example: get_rgb RED
get_rgb() {
  local colour_key flavour
  colour_key="$(to_upper "$1")"; flavour="$FLAVOUR"
  case "${flavour}:${colour_key}" in
    LATTE:ROSEWATER) echo "220;138;120" ;;  LATTE:FLAMINGO)  echo "221;120;120" ;;
    LATTE:PINK)      echo "234;118;203" ;;  LATTE:MAUVE)     echo "136;57;239"  ;;
    LATTE:RED)       echo "210;15;57"   ;;  LATTE:MAROON)    echo "230;69;83"   ;;
    LATTE:PEACH)     echo "254;100;11"  ;;  LATTE:YELLOW)    echo "223;142;29"  ;;
    LATTE:GREEN)     echo "64;160;43"   ;;  LATTE:TEAL)      echo "23;146;153"  ;;
    LATTE:SKY)       echo "4;165;229"   ;;  LATTE:SAPPHIRE)  echo "32;159;181"  ;;
    LATTE:BLUE)      echo "30;102;245"  ;;  LATTE:LAVENDER)  echo "114;135;253" ;;
    LATTE:TEXT)      echo "76;79;105"   ;;  LATTE:SUBTEXT1)  echo "92;95;119"   ;;
    LATTE:SUBTEXT0)  echo "108;111;133" ;;  LATTE:OVERLAY2)  echo "124;127;147" ;;
    LATTE:OVERLAY1)  echo "140;143;161" ;;  LATTE:OVERLAY0)  echo "156;160;176" ;;
    LATTE:SURFACE2)  echo "172;176;190" ;;  LATTE:SURFACE1)  echo "188;192;204" ;;
    LATTE:SURFACE0)  echo "204;208;218" ;;  LATTE:BASE)      echo "239;241;245" ;;
    LATTE:MANTLE)    echo "230;233;239" ;;  LATTE:CRUST)     echo "220;224;232" ;;
    FRAPPE:ROSEWATER) echo "242;213;207" ;; FRAPPE:FLAMINGO)  echo "238;190;190" ;;
    FRAPPE:PINK)      echo "244;184;228" ;; FRAPPE:MAUVE)     echo "202;158;230" ;;
    FRAPPE:RED)       echo "231;130;132" ;; FRAPPE:MAROON)    echo "234;153;156" ;;
    FRAPPE:PEACH)     echo "239;159;118" ;; FRAPPE:YELLOW)    echo "229;200;144" ;;
    FRAPPE:GREEN)     echo "166;209;137" ;; FRAPPE:TEAL)      echo "129;200;190" ;;
    FRAPPE:SKY)       echo "153;209;219" ;; FRAPPE:SAPPHIRE)  echo "133;193;220" ;;
    FRAPPE:BLUE)      echo "140;170;238" ;; FRAPPE:LAVENDER)  echo "186;187;241" ;;
    FRAPPE:TEXT)      echo "198;208;245" ;; FRAPPE:SUBTEXT1)  echo "181;191;226" ;;
    FRAPPE:SUBTEXT0)  echo "165;173;206" ;; FRAPPE:OVERLAY2)  echo "148;156;187" ;;
    FRAPPE:OVERLAY1)  echo "131;139;167" ;; FRAPPE:OVERLAY0)  echo "115;121;148" ;;
    FRAPPE:SURFACE2)  echo "98;104;128"  ;; FRAPPE:SURFACE1)  echo "81;87;109"   ;;
    FRAPPE:SURFACE0)  echo "65;69;89"    ;; FRAPPE:BASE)      echo "48;52;70"    ;;
    FRAPPE:MANTLE)    echo "41;44;60"    ;; FRAPPE:CRUST)     echo "35;38;52"    ;;
    MACCHIATO:ROSEWATER) echo "244;219;214" ;; MACCHIATO:FLAMINGO)  echo "240;198;198" ;;
    MACCHIATO:PINK)      echo "245;189;230" ;; MACCHIATO:MAUVE)     echo "198;160;246" ;;
    MACCHIATO:RED)       echo "237;135;150" ;; MACCHIATO:MAROON)    echo "238;153;160" ;;
    MACCHIATO:PEACH)     echo "245;169;127" ;; MACCHIATO:YELLOW)    echo "238;212;159" ;;
    MACCHIATO:GREEN)     echo "166;218;149" ;; MACCHIATO:TEAL)      echo "139;213;202" ;;
    MACCHIATO:SKY)       echo "145;215;227" ;; MACCHIATO:SAPPHIRE)  echo "125;196;228" ;;
    MACCHIATO:BLUE)      echo "138;173;244" ;; MACCHIATO:LAVENDER)  echo "183;189;248" ;;
    MACCHIATO:TEXT)      echo "202;211;245" ;; MACCHIATO:SUBTEXT1)  echo "184;192;224" ;;
    MACCHIATO:SUBTEXT0)  echo "165;173;203" ;; MACCHIATO:OVERLAY2)  echo "147;154;183" ;;
    MACCHIATO:OVERLAY1)  echo "128;135;162" ;; MACCHIATO:OVERLAY0)  echo "110;115;141" ;;
    MACCHIATO:SURFACE2)  echo "91;96;120"   ;; MACCHIATO:SURFACE1)  echo "73;77;100"   ;;
    MACCHIATO:SURFACE0)  echo "54;58;79"    ;; MACCHIATO:BASE)      echo "36;39;58"    ;;
    MACCHIATO:MANTLE)    echo "30;32;48"    ;; MACCHIATO:CRUST)     echo "24;25;38"    ;;
    MOCHA:ROSEWATER) echo "245;224;220" ;;  MOCHA:FLAMINGO)  echo "242;205;205" ;;
    MOCHA:PINK)      echo "245;194;231" ;;  MOCHA:MAUVE)     echo "203;166;247" ;;
    MOCHA:RED)       echo "243;139;168" ;;  MOCHA:MAROON)    echo "235;160;172" ;;
    MOCHA:PEACH)     echo "250;179;135" ;;  MOCHA:YELLOW)    echo "249;226;175" ;;
    MOCHA:GREEN)     echo "166;227;161" ;;  MOCHA:TEAL)      echo "148;226;213" ;;
    MOCHA:SKY)       echo "137;220;235" ;;  MOCHA:SAPPHIRE)  echo "116;199;236" ;;
    MOCHA:BLUE)      echo "137;180;250" ;;  MOCHA:LAVENDER)  echo "180;190;254" ;;
    MOCHA:TEXT)      echo "205;214;244" ;;  MOCHA:SUBTEXT1)  echo "186;194;222" ;;
    MOCHA:SUBTEXT0)  echo "166;173;200" ;;  MOCHA:OVERLAY2)  echo "147;153;178" ;;
    MOCHA:OVERLAY1)  echo "127;132;156" ;;  MOCHA:OVERLAY0)  echo "108;112;134" ;;
    MOCHA:SURFACE2)  echo "88;91;112"   ;;  MOCHA:SURFACE1)  echo "69;71;90"    ;;
    MOCHA:SURFACE0)  echo "49;50;68"    ;;  MOCHA:BASE)      echo "30;30;46"    ;;
    MOCHA:MANTLE)    echo "24;24;37"    ;;  MOCHA:CRUST)     echo "17;17;27"    ;;
    *) echo "128;128;128" ;;
  esac
}

detect_color_mode() {
  # Manual overrides
  if [[ -n "${NO_COLOR:-}" ]]; then echo "none"; return; fi
  if [[ -n "${COLOR_MODE:-}" ]]; then echo "$COLOR_MODE"; return; fi
  if [[ "${FORCE_COLOR:-}" = "1" ]]; then echo "truecolor"; return; fi
  # Must be a TTY to bother
  if [[ ! -t 1 ]]; then echo "none"; return; fi
  # Strong signals for truecolor
  if [[ "${COLORTERM:-}" =~ (truecolor|24bit) ]] ||
     [[ "${TERM:-}" =~ (truecolor|24bit|direct|kitty) ]]; then
    echo "truecolor"; return
  fi
  # Degrade based on capabilities
  if command -v tput >/dev/null 2>&1; then
    local ncolors; ncolors="$(tput colors 2>/dev/null || echo 0)"
    if [[ "$ncolors" -ge 256 ]]; then echo "ansi256"; return; fi
    if [[ "$ncolors" -ge 8 ]];   then echo "ansi16";  return; fi
  fi
  echo "none"
}

set_color_functions() {
  local mode="$1"
  case "$mode" in
    truecolor)
  RESET=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; ITALIC=$'\033[3m'; UNDERLINE=$'\033[4m'
  fg() { printf "\033[38;2;%sm" "$(get_rgb "$1")"; }
  bg() { printf "\033[48;2;%sm" "$(get_rgb "$1")"; }
  off(){ printf "%b" "$RESET"; }
      ;;
    ansi256|ansi16)
      # Basic named-color mapping for banner/logs (subset is enough)
      RESET=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; ITALIC=$'\033[3m'; UNDERLINE=$'\033[4m'
      _ansi_code() {
        case "$(to_upper "$1")" in
          RED) echo 1 ;;
          BLUE) echo 4 ;;
          GREEN) echo 2 ;;
          YELLOW|PEACH) echo 3 ;;
          MAGENTA|MAUVE|PINK|LAVENDER) echo 5 ;;
          CYAN|TEAL|SKY|SAPPHIRE) echo 6 ;;
          TEXT|BASE|SURFACE*|OVERLAY*|SUBTEXT*|MANTLE|CRUST) echo 7 ;;
          *) echo 7 ;;
        esac
      }
      fg() { printf "\033[3%sm" "$(_ansi_code "$1")"; }
      bg() { printf "\033[4%sm" "$(_ansi_code "$1")"; }
      off(){ printf "%b" "$RESET"; }
      ;;
    *)
  RESET=""; BOLD=""; DIM=""; ITALIC=""; UNDERLINE=""
  fg(){ :; }; bg(){ :; }; off(){ :; }
      ;;
  esac
}

COLOR_MODE="$(detect_color_mode)"
set_color_functions "$COLOR_MODE"

# Export for subshells
export COLOR_MODE RESET BOLD DIM ITALIC UNDERLINE
export -f fg bg off get_rgb detect_color_mode set_color_functions to_upper || true

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
info()  { log_msg BLUE   "INFO" "$@"; }
warn()  { log_msg YELLOW "WARN" "$@"; }
error() { log_msg RED    "ERROR" "$@"; }
success ()    { log_msg GREEN  " SUCCESS  " "$@"; }

# ── Error Handling ─────────────────────────────────────────────────────────────
# Safety rails
set -Eeuo pipefail
shopt -s extdebug           # improves FUNCNAME/BASH_LINENO fidelity
set -o errtrace             # make ERR trap fire in functions/subshells

# Central log file
log() { printf '%s %s\n' "$(date -Is)" "$*" | tee -a "$LOG_FILE" >&2; }

# Stack trace printer
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

# Trap handlers
err_trap() {
  local rc=$? cmd=${BASH_COMMAND:-?} src="${BASH_SOURCE[1]:-?}" line="${BASH_LINENO[0]:-?}"
  error "ERROR: command failed
  status : $rc
  command: $cmd
  location: $src:$line"
  print_stack | tee -a "$LOG_FILE" >&2
  exit "$rc"
}

# Optional: cleanup on exit
cleanup() { :; }

# Set traps
trap err_trap ERR
trap cleanup  EXIT
trap 'warn "Interrupted"; exit 130' INT

# ── Banner ────────────────────────────────────────────────────────────────────
# Print a colorful banner
print_banner() {
  printf '\n'
  printf '%b  ██████╗ ███████╗██████╗ ████████╗     ██████╗ ███████╗██████╗ ██████╗ ███████╗██████╗ %b Infrastructure Installer %b\n' "$(fg RED)" "$(fg PEACH)" "$RESET"
  printf '%b ██╔════╝ ██╔════╝██╔══██╗╚══██╔══╝    ██╔════╝ ██╔════╝██╔══██╗██╔══██╗██╔════╝██╔══██╗%b by GertGerber %b\n' "$(fg RED)" "$(fg BLUE)" "$RESET"
  printf '%b ██║  ███╗█████╗  ██████╔╝   ██║       ██║  ███╗█████╗  ██████╔╝██████╔╝█████╗  ██████╔╝%b Setup your proxmox environment %b\n' "$(fg RED)" "$(fg MAUVE)" "$RESET"
  printf '%b ██║   ██║██╔══╝  ██╔══██╗   ██║       ██║   ██║██╔══╝  ██╔══██╗██╔══██╗██╔══╝  ██╔══██╗%b Enjoy homelab! 🚀%b\n' "$(fg RED)" "$(fg YELLOW)" "$RESET"
  printf '%b ╚██████╔╝███████╗██║  ██║   ██║       ╚██████╔╝███████╗██║  ██║██████╔╝███████╗██║  ██║%b Have fun with roles! 🎉%b\n' "$(fg RED)" "$(fg GREEN)" "$RESET"
  printf '%b  ╚═════╝ ╚══════╝╚═╝  ╚═╝   ╚═╝        ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═════╝ ╚══════╝╚═╝  ╚═╝%b\n' "$(fg RED)" "$RESET"
  printf '\n'
}
print_banner

# ── Pre-flight / OS check ─────────────────────────────────────────────────────
# Function to check for required commands
require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 2; }; }

# Basic sanity checks
info "Sanity checks"
require curl
require bash
require tar
if ! has_cmd sha256sum; then
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
if ! has_cmd apt-get; then
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

  if has_cmd sha256sum && [[ -f repo.tar.gz.sha256 ]]; then
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

# ── Prerequisites (Terraform / Python venv / Ansible) ────────────────────────
install_prereqs() {
  info "Installing prerequisites (Terraform, Python venv, Ansible)"

  # Terraform (HashiCorp repo)
  if ! has_cmd terraform; then
    info "Installing Terraform via apt"
  $SUDO apt-get update -y
$SUDO apt-get install -y gnupg software-properties-common curl
  curl -fsSL https://apt.releases.hashicorp.com/gpg | $SUDO gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release; echo "$VERSION_CODENAME") main" | \
    $SUDO tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  $SUDO apt-get update -y && $SUDO apt-get install -y terraform
fi

  # Python + venv + pip + Ansible in venv
  if ! has_cmd python3; then
    $SUDO apt-get install -y python3
  fi
  if ! python3 -m venv -h >/dev/null 2>&1; then
    $SUDO apt-get install -y python3-venv
  fi
  if ! has_cmd pip3; then
    $SUDO apt-get install -y python3-pip
  fi

  python3 -m venv .venv
  # shellcheck disable=SC1091
  . .venv/bin/activate
  pip install --upgrade pip
  pip install ansible
  success "Prerequisites ready"
}

# ── Terraform ────────────────────────────────────────────────────────────────
run_terraform() {
if [[ ! -d "$TF_DIR" ]]; then
    error "TF_DIR not found: $TF_DIR"
    exit 1
  fi

  info "Terraform @ $TF_DIR"
  pushd "$TF_DIR" >/dev/null || { error "Cannot enter TF_DIR=$TF_DIR"; exit 1; }

  # Optional: workspaces mapped to ENVIRONMENT
  if terraform workspace list >/dev/null 2>&1; then
    terraform workspace select "$ENVIRONMENT" 2>/dev/null || terraform workspace new "$ENVIRONMENT"
  fi

terraform init -input=false
terraform validate

case "$MODE" in
  plan)
    terraform plan -input=false -out=tfplan
    ;;
  apply)
    terraform plan -input=false -out=tfplan
    terraform apply -input=false -auto-approve tfplan
    ;;
  destroy)
    terraform destroy -input=false -auto-approve
    ;;
  check)
    terraform fmt -check && terraform validate
    ;;
  *)
      error "Unknown MODE: $MODE"; exit 1;;
esac

popd >/dev/null
  success "Terraform $MODE complete"
}

# ── Ansible ───────────────────────────────────────────────────────────────────
run_ansible() {
  [[ "$MODE" == "apply" ]] || return 0

  info "Ansible: configure hosts"
  # shellcheck disable=SC1091
  . .venv/bin/activate 2>/dev/null || true

  if [[ -f ansible/requirements.yml ]]; then
  ansible-galaxy install -r ansible/requirements.yml 2>/dev/null || true
  else
    warn "ansible/requirements.yml not found; continuing"
  fi

  [[ -e "$ANSIBLE_INVENTORY" ]] || { error "Inventory not found: $ANSIBLE_INVENTORY"; exit 1; }
  [[ -f "$ANSIBLE_PLAYBOOK"  ]] || { error "Playbook not found: $ANSIBLE_PLAYBOOK"; exit 1; }

  ansible-playbook -i "$ANSIBLE_INVENTORY" "$ANSIBLE_PLAYBOOK" --diff --forks 20
  success "Ansible run complete"
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
  fetch_repo
  install_prereqs
  run_terraform
  run_ansible
  success "Done ($MODE) for environment: $ENVIRONMENT"
}

main "$@"
