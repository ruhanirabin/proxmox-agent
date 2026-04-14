#!/bin/bash

set -euo pipefail

LIB_FILE="${LIB_FILE:-/usr/local/bin/pa-agent-lib.sh}"
[ -f "$LIB_FILE" ] || LIB_FILE="$(cd "$(dirname "$0")" && pwd)/pa-agent-lib.sh"
# shellcheck disable=SC1090
source "$LIB_FILE"

pa_load_version
pa_load_env

EVENT="${1:-}"
STATUS="${2:-}"
SUMMARY="${3:-}"
DETAILS="${4:-}"

if [ -z "$EVENT" ]; then
  echo "Usage: pa-send-webhook.sh <event> [status] [summary] [details]"
  exit 1
fi

if pa_send_webhook "$EVENT" "${STATUS:-info}" "$SUMMARY" "$DETAILS"; then
  exit 0
fi

exit 1
