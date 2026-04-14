#!/bin/bash

# =========================================================
# Proxmox Config Backup Script (Git + Telegram Alerts)
# =========================================================
#
# 📁 Script Location:
#   /root/backup-config.sh
#
# ⚙️ Systemd Service:
#   /etc/systemd/system/backup-config.service
#
# ⏱️ Systemd Timer:
#   /etc/systemd/system/backup-config.timer
#
# 🔐 Environment File:
#   /root/.backup-config.env
#
#   Required variables inside:
#     BOT_TOKEN=xxxxx
#     CHAT_ID=xxxxx
#
# 📜 Log File:
#   /var/log/backup-config.log
#
# 🧠 Purpose:
#   - Backup Proxmox configs into Git
#   - Multi-node safe (uses hostname)
#   - Runs via timer + shutdown fallback
#   - Alerts only on critical infra changes
#
# =========================================================

set -euo pipefail

# === Logging ===
exec > >(tee -a /var/log/backup-config.log) 2>&1

# === Load environment variables ===
ENV_FILE="${ENV_FILE:-/root/.backup-config.env}"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

# === Settings ===
REPO_DIR="/root/pve-config"
NODE_NAME=$(hostname)
TARGET_DIR="$REPO_DIR/$NODE_NAME"
DATE_TAG=$(date '+%Y-%m-%d %H:%M')

# === Telegram ===
TG_TOKEN="${BOT_TOKEN:-}"
TG_CHAT="${CHAT_ID:-}"

send_telegram() {
  local msg="$1"
  [[ -z "$TG_TOKEN" || -z "$TG_CHAT" ]] && return 0

  curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
    -d chat_id="$TG_CHAT" \
    -d text="$msg" \
    -d parse_mode="Markdown" >/dev/null || true
}

echo "=== Backup start: $NODE_NAME at $DATE_TAG ==="

# === Safety Check ===
if [[ "$PWD" == "$REPO_DIR" || "$PWD" == "$REPO_DIR/"* ]]; then
  echo "❌ Do not run this script from inside the Git repo folder."
  exit 1
fi

# === Ensure folders ===
mkdir -p "$TARGET_DIR"/{systemd,scripts,network,etc-pve,root,lxc-hooks,firewall}

# === Collect configs ===
echo "Collecting configs..."

find /etc/systemd/system/ -type f \( -name "*.service" -o -name "*.timer" \) \
  ! -path "*/wanted/*" \
  -exec cp --parents {} "$TARGET_DIR/systemd/" \;

cp /usr/local/bin/*.sh "$TARGET_DIR/scripts/" 2>/dev/null || true
cp /etc/network/interfaces "$TARGET_DIR/network/" 2>/dev/null || true

cp /etc/pve/datacenter.cfg "$TARGET_DIR/etc-pve/" 2>/dev/null || true
cp /etc/pve/storage.cfg "$TARGET_DIR/etc-pve/" 2>/dev/null || true

cp /root/*.sh "$TARGET_DIR/root/" 2>/dev/null || true
cp /root/*.conf "$TARGET_DIR/root/" 2>/dev/null || true
cp /root/*.creds "$TARGET_DIR/root/" 2>/dev/null || true

cp /root/.bashrc "$TARGET_DIR/root/" 2>/dev/null || true
cp /root/.zshrc "$TARGET_DIR/root/" 2>/dev/null || true
cp /root/.profile "$TARGET_DIR/root/" 2>/dev/null || true

cp -r /root/.config "$TARGET_DIR/root/.config" 2>/dev/null || true
cp -r /root/.ssh "$TARGET_DIR/root/.ssh" 2>/dev/null || true

crontab -l -u root > "$TARGET_DIR/root/crontab.txt" 2>/dev/null || true

cp /etc/pve/lxc/*.conf "$TARGET_DIR/lxc-hooks/" 2>/dev/null || true
cp /etc/pve/firewall/* "$TARGET_DIR/firewall/" 2>/dev/null || true

# === Git ===
echo "Processing git..."
cd "$REPO_DIR"

git add -A

if git diff --cached --quiet; then
  echo "No changes detected."
else
  echo "Changes detected."

  FULL_DIFF=$(git diff --cached --stat)
  CRITICAL=$(git diff --cached --name-only | grep -E "storage.cfg|lxc/|qemu-server/" || true)

  echo "=== Full diff ==="
  echo "$FULL_DIFF"

  echo "=== Critical changes ==="
  echo "$CRITICAL"

  CHANGES=$(git diff --cached --name-only | wc -l)
  COMMIT_MSG="[$NODE_NAME] $CHANGES files changed - $DATE_TAG"

  git commit -m "$COMMIT_MSG"

  git pull --rebase origin main || {
    echo "❌ Git pull failed"
    exit 1
  }

  git push origin main || {
    echo "❌ Git push failed"
    exit 1
  }

  TAG_NAME="$NODE_NAME-backup-$(date '+%Y-%m-%d-%H%M')"
  git tag "$TAG_NAME"
  git push origin "$TAG_NAME"

  # === Telegram Alert ===
  if [[ -n "$CRITICAL" ]]; then
    MSG="🚨 *Proxmox Critical Change*\nNode: \`$NODE_NAME\`\nTime: $DATE_TAG\n\nChanges:\n\`\`\`\n$CRITICAL\n\`\`\`"
    send_telegram "$MSG"
  fi
fi

# === Summary ===
echo -e "\n📦 Backup Summary for $NODE_NAME"
echo "----------------------------------------"
echo "Systemd files   : $(find "$TARGET_DIR/systemd" -type f | wc -l)"
echo "Scripts         : $(find "$TARGET_DIR/scripts" -type f | wc -l)"
echo "Network config  : $(find "$TARGET_DIR/network" -type f | wc -l)"
echo "PVE configs     : $(find "$TARGET_DIR/etc-pve" -type f | wc -l)"
echo "Root files      : $(find "$TARGET_DIR/root" -type f | wc -l)"
echo "LXC hooks       : $(find "$TARGET_DIR/lxc-hooks" -type f | wc -l)"
echo "Firewall rules  : $(find "$TARGET_DIR/firewall" -type f | wc -l)"
echo "----------------------------------------"

echo "=== Backup complete: $NODE_NAME ==="

