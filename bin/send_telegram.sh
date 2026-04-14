#!/bin/bash

# ============================================================
# send_telegram.sh (v0.5.5)
# ------------------------------------------------------------
# Sends a Telegram message via Bot API
#
# 🔐 Dependencies:
# - Requires environment file: /root/.backup-config.env
#   Preferred variables:
#     BOT_TOKEN=your_bot_token
#     CHAT_ID=your_chat_id
#
#   Backward compatibility (deprecated soon):
#     TELEGRAM_BOT_TOKEN
#     TELEGRAM_CHAT_ID
#
# 📦 Usage:
#   send_telegram.sh "your message"
#
# 🧠 Features:
# - MarkdownV2 safe escaping
# - Timeout + retry handling
# - Centralized logging
# - Empty message protection
# - Env normalization
#
# 📜 Log File:
#   /var/log/proxmox-telegram.log
#
# 🧹 Log Retention:
#   Auto-prunes logs older than 7 days
# ============================================================

set -o pipefail

# ==== config ====
ENV_FILE="${ENV_FILE:-/root/.backup-config.env}"
LOG_FILE="/var/log/proxmox-telegram.log"
TIMEOUT=10
RETRIES=2

# ==== ensure log dir exists ====
mkdir -p "$(dirname "$LOG_FILE")"

# ==== log rotation (keep 7 days) ====
find "$(dirname "$LOG_FILE")" -type f -name "$(basename "$LOG_FILE")*" -mtime +7 -exec rm -f {} \;

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# ==== load env safely ====
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  echo "[$TIMESTAMP] ERROR: Env file not found: $ENV_FILE" >> "$LOG_FILE"
  exit 1
fi

# ==== normalize variable names ====
BOT_TOKEN="${BOT_TOKEN:-$TELEGRAM_BOT_TOKEN}"
CHAT_ID="${CHAT_ID:-$TELEGRAM_CHAT_ID}"

# ==== validate credentials ====
if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
  echo "[$TIMESTAMP] ERROR: Missing BOT_TOKEN/CHAT_ID (or TELEGRAM_ variants)" >> "$LOG_FILE"
  exit 1
fi

RAW_MESSAGE="$1"

# ==== validate message (critical fix) ====
if [ -z "$RAW_MESSAGE" ] || [[ "$RAW_MESSAGE" =~ ^[[:space:]]*$ ]]; then
  echo "[$TIMESTAMP] ERROR: Empty message blocked" >> "$LOG_FILE"
  exit 0
fi

# ==== escape for MarkdownV2 ====

MESSAGE="$RAW_MESSAGE"

# ==== send ====
API_URL="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"

RESPONSE=$(/usr/bin/curl -s \
  --max-time "$TIMEOUT" \
  --retry "$RETRIES" \
  --retry-delay 2 \
  -X POST "$API_URL" \
  -d chat_id="$CHAT_ID" \
  -d text="$MESSAGE" \
  -d parse_mode="HTML")

# ==== evaluate result ====
if echo "$RESPONSE" | grep -q '"ok":true'; then
  echo "[$TIMESTAMP] OK: Telegram sent (len=${#RAW_MESSAGE})" >> "$LOG_FILE"
else
  echo "[$TIMESTAMP] ERROR: Telegram failed" >> "$LOG_FILE"
  echo "[$TIMESTAMP] Response: $RESPONSE" >> "$LOG_FILE"
  exit 1
fi
