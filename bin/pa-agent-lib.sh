#!/bin/bash

set -o pipefail

PA_ENV_FILE_DEFAULT="/root/.pa-agent.env"
PA_ENV_FILE_LEGACY="/root/.backup-config.env"
PA_VERSION_FILE="/usr/local/bin/pa-agent-version"
PA_VERSION_FILE_LEGACY="/usr/local/bin/proxmox-agent-version"

pa_now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

pa_bool_true() {
  local v
  v="$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')"
  [[ "$v" == "1" || "$v" == "true" || "$v" == "yes" || "$v" == "on" ]]
}

pa_json_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

pa_load_version() {
  AGENT_VERSION="unknown"
  if [ -f "$PA_VERSION_FILE" ]; then
    # shellcheck disable=SC1090
    source "$PA_VERSION_FILE" || true
    return 0
  fi
  if [ -f "$PA_VERSION_FILE_LEGACY" ]; then
    # shellcheck disable=SC1090
    source "$PA_VERSION_FILE_LEGACY" || true
  fi
}

pa_load_env() {
  if [ -n "${ENV_FILE:-}" ]; then
    if [ -f "$ENV_FILE" ]; then
      # shellcheck disable=SC1090
      source "$ENV_FILE"
    fi
    return 0
  fi

  if [ -f "$PA_ENV_FILE_DEFAULT" ]; then
    ENV_FILE="$PA_ENV_FILE_DEFAULT"
  elif [ -f "$PA_ENV_FILE_LEGACY" ]; then
    ENV_FILE="$PA_ENV_FILE_LEGACY"
  else
    ENV_FILE="$PA_ENV_FILE_DEFAULT"
  fi

  if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
  fi
}

pa_log_retention_days() {
  local raw="${1:-${PA_LOG_RETENTION_DAYS:-14}}"
  if [[ "$raw" =~ ^[0-9]+$ ]] && [ "$raw" -ge 1 ]; then
    echo "$raw"
  else
    echo "14"
  fi
}

pa_rotate_log_family() {
  local log_file="$1"
  local retention_input="${2:-}"
  local retention_days
  local log_dir log_base

  retention_days="$(pa_log_retention_days "$retention_input")"
  log_dir="$(dirname "$log_file")"
  log_base="$(basename "$log_file")"

  mkdir -p "$log_dir"
  find "$log_dir" -type f -name "${log_base}*" -mtime +"$retention_days" -exec rm -f {} \; 2>/dev/null || true
}

pa_event_enabled() {
  local event="${1:-}"
  local configured list
  configured="${WEBHOOK_EVENTS:-install,doctor,backup,shutdown}"
  configured="$(echo "$configured" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
  [ -z "$configured" ] && return 1
  [ "$configured" = "*" ] && return 0
  IFS=',' read -r -a list <<< "$configured"
  for item in "${list[@]}"; do
    [ "$item" = "$event" ] && return 0
  done
  return 1
}

pa_send_webhook() {
  local event status summary details node ts enabled url token timeout retries payload try delay auth_header
  event="${1:-}"
  status="${2:-unknown}"
  summary="${3:-}"
  details="${4:-}"
  node="${5:-$(hostname -s 2>/dev/null || hostname)}"
  ts="$(pa_now_utc)"

  enabled="${WEBHOOK_ENABLED:-false}"
  url="${WEBHOOK_URL:-}"
  token="${WEBHOOK_BEARER_TOKEN:-}"
  timeout="${WEBHOOK_TIMEOUT_SECONDS:-10}"
  retries="${WEBHOOK_MAX_RETRIES:-3}"

  pa_bool_true "$enabled" || return 0
  [ -n "$url" ] || return 0
  pa_event_enabled "$event" || return 0

  payload=$(
    cat <<EOF
{"schema_version":"1","event_type":"$(pa_json_escape "$event")","timestamp":"$ts","node":"$(pa_json_escape "$node")","status":"$(pa_json_escape "$status")","summary":"$(pa_json_escape "$summary")","details":"$(pa_json_escape "$details")","agent_version":"$(pa_json_escape "${AGENT_VERSION:-unknown}")"}
EOF
  )

  try=1
  delay=1
  while [ "$try" -le "$retries" ]; do
    auth_header=()
    if [ -n "$token" ]; then
      auth_header=(-H "Authorization: Bearer $token")
    fi

    if curl -fsS --max-time "$timeout" -X POST "$url" \
      -H "Content-Type: application/json" \
      "${auth_header[@]}" \
      --data "$payload" >/dev/null 2>&1; then
      return 0
    fi

    [ "$try" -eq "$retries" ] && break
    sleep "$delay"
    delay=$((delay * 2))
    try=$((try + 1))
  done

  return 1
}
