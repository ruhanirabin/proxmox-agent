#!/bin/bash

# ============================================================
# proxmox-boot-notify.sh (v0.6.3)
# ------------------------------------------------------------
# Sends a Telegram notification when Proxmox host boots
#
# 🔐 Dependencies:
# - /usr/local/bin/send_telegram.sh
# - /root/.backup-config.env (via send_telegram.sh)
#
# 📜 Log File:
#   /var/log/proxmox-boot.log
#
# 🧠 Features:
# - Duplicate protection (lock file)
# - Safe message generation
# - Network stabilization delay
# - Clean logging (no double logging)
#
# ⚠️ Notes:
# - Lock file stored in /tmp (cleared on reboot)
# - Will skip execution if duplicate detected
# ============================================================

set -o pipefail

# ==== basics ====
NODE_NAME=$(hostname -s)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')
BOOT_TIME=$(uptime -s 2>/dev/null || echo "unknown")

# ==== logging ====
LOG_FILE="/var/log/proxmox-boot.log"
mkdir -p "$(dirname "$LOG_FILE")"

# ==== duplicate protection ====
LOCK_FILE="/tmp/proxmox_boot_notify.lock"

if [ -f "$LOCK_FILE" ]; then
  echo "[$TIMESTAMP] INFO: Duplicate boot notification skipped for $NODE_NAME" >> "$LOG_FILE"
  exit 0
fi

touch "$LOCK_FILE"

# ==== wait for network stability ====
sleep 5

# ==== message ====
MESSAGE=$(cat <<EOF
✅ <b>Proxmox host $NODE_NAME</b> booted

• Time: <b>$TIMESTAMP</b>
• Boot time: <b>$BOOT_TIME</b>
EOF
)

# ==== validate message ====
if [ -z "$MESSAGE" ] || [[ "$MESSAGE" =~ ^[[:space:]]*$ ]]; then
  echo "[$TIMESTAMP] ERROR: Boot message empty, skipping send" >> "$LOG_FILE"
  exit 0
fi

# ==== send ====
/usr/local/bin/send_telegram.sh "$MESSAGE"
SEND_STATUS=$?

# ==== result logging ====
if [ $SEND_STATUS -eq 0 ]; then
  echo "[$TIMESTAMP] OK: Boot notification sent for $NODE_NAME" >> "$LOG_FILE"
else
  echo "[$TIMESTAMP] ERROR: Failed to send boot notification for $NODE_NAME" >> "$LOG_FILE"
fi
