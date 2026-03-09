#!/bin/bash
# PM Market Intelligence — Zoho Cliq Notification
# ─────────────────────────────────────────────────────────────────────────────
# Source this file in any script that needs to send notifications.
#
# Usage:
#   source lib/notify.sh
#   send_notification "Your message here"
#
# Required env vars (set in .env):
#   CLIQ_BOT_INCOMING_URL — Zoho Cliq bot incoming webhook URL
#   CLIQ_BOT_TOKEN        — Zoho Cliq bot API token
#
# Setup guide: https://www.zoho.com/cliq/help/platform/incoming-webhook-bots.html
# ─────────────────────────────────────────────────────────────────────────────

# Detect if Cliq is configured from config.yaml
_get_notify_type() {
  local config_file="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/config.yaml"
  if [ -f "$config_file" ]; then
    grep -E '^\s*type:\s*' "$config_file" | tail -1 | sed 's/.*type:\s*["'\'']\?\([a-z]*\)["'\'']\?.*/\1/'
  else
    echo "none"
  fi
}

NOTIFY_TYPE="${NOTIFY_TYPE:-$(_get_notify_type)}"

# Send a notification to Zoho Cliq
# Args: $1 = message text
# Returns: 0 on success, 1 on failure, 2 if notifications disabled
send_notification() {
  local message="$1"
  [ -z "$message" ] && return 1

  case "$NOTIFY_TYPE" in
    cliq)
      if [ -z "$CLIQ_BOT_INCOMING_URL" ] || [ -z "$CLIQ_BOT_TOKEN" ]; then
        echo "[notify] Cliq credentials not set. Add CLIQ_BOT_INCOMING_URL and CLIQ_BOT_TOKEN to .env" >&2
        return 1
      fi
      jq -n --arg text "$message" '{"text": $text}' | \
        curl -s -X POST "${CLIQ_BOT_INCOMING_URL}?zapikey=${CLIQ_BOT_TOKEN}" \
        -H "Content-Type: application/json" \
        -d @- 2>&1
      ;;
    none|"")
      echo "[notify] Notifications disabled (type=none in config.yaml)"
      return 2
      ;;
    *)
      echo "[notify] Only Zoho Cliq is supported. Set notifications.type to 'cliq' in config.yaml" >&2
      return 1
      ;;
  esac
}