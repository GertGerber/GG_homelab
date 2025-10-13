#!/usr/bin/env bash
set -Eeuo pipefail

MODE="${1:-plan}"          # plan | apply | destroy | check
ENVIRONMENT="${ENVIRONMENT:-dev}"
LOG_DIR="${LOG_DIR:-/$HOME/log/gg_homelab}"
REPO="${REPO:-GertGerber/GG_Homelab}"
REF="${REF:-v0.1.0}"       # tag or commit SHA
WORKDIR="${WORKDIR:-/HOME/gg_homelab}"
TF_DIR="${TF_DIR:-terraform/envs/$ENVIRONMENT}"
ANSIBLE_PLAYBOOK="${ANSIBLE_PLAYBOOK:-ansible/site.yml}"

mkdir -p "$LOG_DIR" "$WORKDIR"
exec > >(tee -a "$LOG_DIR/bootstrap.$(date +%Y%m%d-%H%M%S).log") 2>&1

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 2; }; }

echo "[*] Sanity checks"
require curl
require bash
require tar
require sha256sum || true   # if you publish checksums, make this mandatory

if [[ $EUID -ne 0 ]]; then
  echo "[-] Not running as root. Will use sudo where required."
  SUDO="sudo"
else
  SUDO=""
fi

# Optional: verify host OS if you strictly support Ubuntu
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  echo "[*] Detected: $PRETTY_NAME"
fi

echo "[*] Fetching bundle @ $REF"
BUNDLE_URL="https://codeload.github.com/$REPO/tar.gz/$REF"
cd "$WORKDIR"
curl -fsSLo repo.tar.gz "$BUNDLE_URL"
# Optional checksum verification (publish repo.tar.gz.sha256 alongside)
# curl -fsSLo repo.tar.gz.sha256 "$BUNDLE_URL.sha256"
# sha256sum -c repo.tar.gz.sha256

tar -xzf repo.tar.gz
REPO_DIR="$(find . -maxdepth 1 -type d -name '*GG_Homelab*' | head -n1)"
cd "$REPO_DIR"

echo "[*] Installing prerequisites"
if ! command -v terraform >/dev/null 2>&1; then
  echo "[*] Installing terraform (apt-based quick path)"
  $SUDO apt-get update -y && $SUDO apt-get install -y gnupg software-properties-common
  curl -fsSL https://apt.releases.hashicorp.com/gpg | $SUDO gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release; echo $VERSION_CODENAME) main" | \
    $SUDO tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  $SUDO apt-get update -y && $SUDO apt-get install -y terraform
fi

if ! command -v ansible-playbook >/dev/null 2>&1; then
  $SUDO apt-get install -y python3 python3-venv python3-pip
  python3 -m venv .venv
  . .venv/bin/activate
  pip install --upgrade pip
  pip install ansible
else
  # still create venv for python helpers if you like
  python3 -m venv .venv || true
fi
. .venv/bin/activate 2>/dev/null || true

echo "[*] Terraform: init/validate/plan"
pushd "$TF_DIR" >/dev/null
terraform -install-autocomplete >/dev/null 2>&1 || true
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
    echo "Unknown MODE: $MODE"; exit 1;;
esac
popd >/dev/null

if [[ "$MODE" == "apply" ]]; then
  echo "[*] Ansible: configure hosts"
  # Ensure inventory exists; adjust to your inventory strategy
  ansible-galaxy install -r ansible/requirements.yml 2>/dev/null || true
  ansible-playbook -i ansible/inventories/$ENVIRONMENT ansible/site.yml \
    --diff --forks 20
fi

echo "[✓] Done ($MODE) for environment: $ENVIRONMENT"
