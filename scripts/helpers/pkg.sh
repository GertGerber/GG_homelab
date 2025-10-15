#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

PKG_TOOL="${PKG_TOOL:-apt}"
USE_NALA="${USE_NALA:-false}"

install_nala_if_missing() {
  [[ "$PKG_FAMILY" == debian ]] || { warn "Non-Debian OS; skipping nala."; return 0; }
  if have_cmd nala; then USE_NALA=true; PKG_TOOL="nala"; return; fi
  info "Installing nala…"
  _sudo apt-get -o Acquire::Retries=3 update -y
  if DEBIAN_FRONTEND=noninteractive _sudo apt-get install -y nala; then
    USE_NALA=true; PKG_TOOL="nala"; info "nala installed."
  else
    warn "nala install failed; using apt."; USE_NALA=false; PKG_TOOL="apt"
  fi
}

pkg_update_upgrade() {
  require_debian
  if "$USE_NALA"; then
    info "Updating via nala…"
    _sudo nala update
    DEBIAN_FRONTEND=noninteractive _sudo nala upgrade -y
  else
    info "Updating via apt…"
    _sudo apt-get -o Acquire::Retries=3 update -y
    DEBIAN_FRONTEND=noninteractive _sudo apt-get upgrade -y
  fi
}

pkg_install() {
  require_debian
  if "$USE_NALA"; then
    DEBIAN_FRONTEND=noninteractive _sudo nala install -y "$@" || {
      warn "nala failed; retrying apt…"
      DEBIAN_FRONTEND=noninteractive _sudo apt-get install -y "$@"
    }
  else
    DEBIAN_FRONTEND=noninteractive _sudo apt-get install -y "$@"
  fi
}
pkg_remove() {
  require_debian
  if "$USE_NALA"; then
    DEBIAN_FRONTEND=noninteractive _sudo nala remove -y "$@" || {
      warn "nala failed; retrying apt…"
      DEBIAN_FRONTEND=noninteractive _sudo apt-get remove -y "$@"
    }
  else
    DEBIAN_FRONTEND=noninteractive _sudo apt-get remove -y "$@"
  fi
}
pkg_purge() {
  require_debian
  if "$USE_NALA"; then
    DEBIAN_FRONTEND=noninteractive _sudo nala purge -y "$@" || {
      warn "nala failed; retrying apt…"
      DEBIAN_FRONTEND=noninteractive _sudo apt-get purge -y "$@"
    }
  else
    DEBIAN_FRONTEND=noninteractive _sudo apt-get purge -y "$@"
  fi
}
pkg_autoremove() {
    require_debian  
    if "$USE_NALA"; then
      DEBIAN_FRONTEND=noninteractive _sudo nala autoremove -y || {
        warn "nala failed; retrying apt…"
        DEBIAN_FRONTEND=noninteractive _sudo apt-get autoremove -y
      }
    else
      DEBIAN_FRONTEND=noninteractive _sudo apt-get autoremove -y
    fi
}
pkg_is_installed() {
  require_debian
  dpkg -s "$1" >/dev/null 2>&1
}   

pkg_list_installed() {
  require_debian
  dpkg -l | awk '/^ii/ {print $2}'
}

pkg_clean_cache() {
  require_debian
  if "$USE_NALA"; then
    _sudo nala clean
  else
    _sudo apt-get clean
  fi
}       

