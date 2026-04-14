#!/bin/bash

# ============================================================
# shutdown-proxmox.sh (v0.7.2)
# ------------------------------------------------------------
# Gracefully shuts down Proxmox host, VMs, and LXCs
#
# 🔐 Dependencies:
# - /usr/local/bin/send_telegram.sh
#
# 📜 Logs:
#   /var/log/proxmox_shutdown/shutdown_YYYY-MM-DD.log
#
# 🧠 Features:
# - Prevents shutdown shortly after boot
# - Sequential shutdown with verification
# - Reusable wait function (state-aware)
# - Telegram notifications (start + final)
# - Log rotation (2 days)
# - Safe fallback (force stop)
# ============================================================

set -o pipefail

# ==== settings ====
NODE_NAME=$(hostname -s)
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# ==== logging ====
LOG_DIR="/var/log/proxmox_shutdown"
LOG_FILE="$LOG_DIR/shutdown_$(date '+%Y-%m-%d').log"
mkdir -p "$LOG_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] $1" >> "$LOG_FILE"
}

# ============================================================
# Reusable wait function
# ============================================================

wait_for_shutdown() {
  local TYPE="$1"   # vm | lxc
  local ID="$2"
  local TIMEOUT=120
  local INTERVAL=5
  local ELAPSED=0
  local STATUS

  while [ $ELAPSED -lt $TIMEOUT ]; do
    if [ "$TYPE" = "vm" ]; then
      STATUS=$(qm status "$ID" 2>/dev/null | awk '{print $2}')
    else
      STATUS=$(pct status "$ID" 2>/dev/null | awk '{print $2}')
    fi

    if [ "$STATUS" != "running" ]; then
      log "$TYPE $ID stopped successfully"
      return 0
    fi

    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
  done

  # fallback
  log "WARNING: $TYPE $ID did not stop, forcing stop"

  if [ "$TYPE" = "vm" ]; then
    qm stop "$ID" >> "$LOG_FILE" 2>&1
  else
    pct stop "$ID" >> "$LOG_FILE" 2>&1
  fi

  return 1
}

# ============================================================
# Boot protection
# ============================================================

uptime_secs=$(cut -d. -f1 /proc/uptime)
if [ "$uptime_secs" -lt 900 ]; then
  log "Skipping shutdown: system booted recently ($uptime_secs sec)"
  logger "Proxmox shutdown skipped: $NODE_NAME booted recently"
  exit 0
fi

# ============================================================
# Log rotation
# ============================================================

find "$LOG_DIR" -type f -name "shutdown_*.log" -mtime +2 -exec rm -f {} \;

# ============================================================
# Start shutdown
# ============================================================

START_TS=$(date '+%Y-%m-%d %H:%M:%S %Z')

log "==== $NODE_NAME Shutdown started at $START_TS ===="
logger "Proxmox $NODE_NAME shutdown initiated"

/usr/local/bin/send_telegram.sh "⚠️ Proxmox $NODE_NAME shutdown started at <b>$START_TS</b>"

# ============================================================
# Shutdown VMs
# ============================================================

log "Shutting down VMs..."

for vmid in $(qm list | awk 'NR>1 {print $1}'); do
  STATUS=$(qm status "$vmid" 2>/dev/null | awk '{print $2}')

  if [ "$STATUS" = "running" ]; then
    log "Shutting down VM $vmid"
    qm shutdown "$vmid" --timeout 90 >> "$LOG_FILE" 2>&1
    wait_for_shutdown "vm" "$vmid"
  else
    log "VM $vmid already stopped"
  fi
done

# ============================================================
# Shutdown LXCs
# ============================================================

log "Shutting down LXCs..."

for lxcid in $(pct list | awk 'NR>1 {print $1}'); do
  STATUS=$(pct status "$lxcid" 2>/dev/null | awk '{print $2}')

  if [ "$STATUS" = "running" ]; then
    log "Shutting down LXC $lxcid"
    pct shutdown "$lxcid" >> "$LOG_FILE" 2>&1
    wait_for_shutdown "lxc" "$lxcid"
  else
    log "LXC $lxcid already stopped"
  fi
done

# ============================================================
# Final delay
# ============================================================

log "Waiting 10 seconds before host shutdown..."
sleep 10

# ============================================================
# Final shutdown
# ============================================================

FINAL_TS=$(date '+%Y-%m-%d %H:%M:%S %Z')

log "Shutting down host now"
logger "Proxmox $NODE_NAME shutting down"

/usr/local/bin/send_telegram.sh "🛑 Proxmox host <b>$NODE_NAME</b> shutting down at <b>$FINAL_TS</b>"

/sbin/shutdown -h now
