#!/bin/bash

set -euo pipefail

PA_WORK_DIR="/tmp/proxmox-agent-install"
PA_BRANCH="${PA_BRANCH:-main}"
PA_REPO_SLUG="${PA_REPO_SLUG:-}"
PA_INSTALL_MODE="${PA_INSTALL_MODE:-auto}"

log() { echo "[proxmox-agent-installer] $*"; }
warn() { echo "[proxmox-agent-installer] WARNING: $*" >&2; }
die() { echo "[proxmox-agent-installer] ERROR: $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

prompt() {
  local p="$1"
  local default="${2:-}"
  local answer
  if [ -n "$default" ]; then
    read -r -p "$p [$default]: " answer
    echo "${answer:-$default}"
  else
    read -r -p "$p: " answer
    echo "$answer"
  fi
}

print_intro() {
  cat <<'EOF'
Proxmox Agent guided installer
This installer will:
1) run preflight checks
2) detect existing/legacy installs
3) fetch installer source
4) run `proxmox-agent install`
EOF
}

preflight() {
  [ "$(id -u)" -eq 0 ] || die "Run as root."
  need_cmd bash
  need_cmd curl
  need_cmd tar
  need_cmd git
  need_cmd systemctl
  need_cmd ssh
  need_cmd ssh-keygen
  log "Preflight checks passed."
}

detect_existing() {
  if [ -f /usr/local/bin/pa-agent-version ]; then
    # shellcheck disable=SC1091
    source /usr/local/bin/pa-agent-version || true
    log "Detected existing canonical install: v${AGENT_VERSION:-unknown}"
  elif [ -f /usr/local/bin/proxmox-agent-version ]; then
    # shellcheck disable=SC1091
    source /usr/local/bin/proxmox-agent-version || true
    log "Detected existing legacy install: v${AGENT_VERSION:-unknown}"
  else
    log "No existing installed version file detected."
  fi

  if compgen -G "/etc/systemd/system/backup-config.*" >/dev/null || \
     [ -f /etc/systemd/system/proxmox-bootup-telegram.service ] || \
     [ -f /etc/systemd/system/shutdown-proxmox.service ]; then
    log "Legacy unit names detected; migration will run automatically."
  fi
}

fetch_source() {
  rm -rf "$PA_WORK_DIR"
  mkdir -p "$PA_WORK_DIR"

  if [ -x "./bin/proxmox-agent" ] && [ -f "./VERSION" ] && [ "$PA_INSTALL_MODE" != "remote" ]; then
    log "Using local repository source."
    echo "$(pwd)"
    return 0
  fi

  if [ -z "$PA_REPO_SLUG" ]; then
    PA_REPO_SLUG="$(prompt "Enter GitHub repo slug (owner/repo)")"
  fi
  [ -n "$PA_REPO_SLUG" ] || die "Repo slug is required."

  local archive="$PA_WORK_DIR/src.tgz"
  local url="https://codeload.github.com/${PA_REPO_SLUG}/tar.gz/refs/heads/${PA_BRANCH}"
  log "Downloading source: $url"
  curl -fsSL "$url" -o "$archive" || die "Failed to download repository archive."

  tar -xzf "$archive" -C "$PA_WORK_DIR" || die "Failed to extract archive."
  local srcdir
  srcdir="$(find "$PA_WORK_DIR" -maxdepth 2 -type f -name proxmox-agent | head -n 1 | xargs dirname)"
  [ -n "$srcdir" ] || die "Could not locate bin/proxmox-agent in extracted archive."
  echo "$(cd "$srcdir/.." && pwd)"
}

main() {
  print_intro
  preflight
  detect_existing

  local src_root
  src_root="$(fetch_source)"
  log "Source root: $src_root"

  [ -x "$src_root/bin/proxmox-agent" ] || chmod +x "$src_root/bin/proxmox-agent"
  log "Starting guided proxmox-agent install..."
  (cd "$src_root" && ./bin/proxmox-agent install)
  log "Installer finished."
}

main "$@"
