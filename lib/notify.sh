#!/bin/bash
# PM Market Intel — Notification Abstraction Layer
# Usage:
#   source lib/notify.sh
#   send_notification "Your message here"
#
# Supported types (set in config.yaml → notifications.type):
#   slack   — Slack via incoming webhook (needs SLACK_WEBHOOK_URL in .env)
#   discord — Discord via webhook (needs DISCORD_WEBHOOK_URL in .env)
#   cliq    — Zoho Cliq via bot webhook (needs CLIQ_BOT_INCOMING_URL + CLIQ_BOT_TOKEN in .env)
#   none    — no notifications sent

# Detect notification type from config.yaml
_get_notify_type() {
  local config_file="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/config.yaml"
  if [ -f "$config_file" ]; then
    grep -E '^\s*type:\s*' "$config_file" | tail -1 | sed 's/.*type:\s*["'\'']\?\([a-z]*\)["'\'']\?.*/\1/'
  else
    echo "none"
  fi
}

NOTIFY_TYPE="${NOTIFY_TYPE:-$(_get_notify_type)}"

send_notification() {
  local message="$1"
  [ -z "$message" ] && return 1

  case "$NOTIFY_TYPE" in
    cliq)
      if [ -z "$CLIQ_BOT_INCOMING_URL" ] || [ -z "$CLIQ_BOT_TOKEN" ]; then
        echo "[notify] Cliq credentials not set" >&2; return 1
      fi
      jq -n --arg text "$message" '{"text": $text}' | \
        curl -s -X POST "${CLIQ_BOT_INCOMING_URL}?zapikey=${CLIQ_BOT_TOKEN}" \
        -H "Content-Type: application/json" -d @- 2>&1
      ;;
    slack)
      if [ -z "$SLACK_WEBHOOK_URL" ]; then
        echo "[notify] Slack webhook not set" >&2; return 1
      fi
      jq -n --arg text "$message" '{"text": $text}' | \
        curl -s -X POST "$SLACK_WEBHOOK_URL" \
        -H "Content-Type: application/json" -d @- 2>&1
      ;;
    discord)
      if [ -z "$DISCORD_WEBHOOK_URL" ]; then
        echo "[notify] Discord webhook not set" >&2; return 1
      fi
      jq -n --arg content "$message" '{"content": $content}' | \
        curl -s -X POST "$DISCORD_WEBHOOK_URL" \
        -H "Content-Type: application/json" -d @- 2>&1
      ;;
    none|"")
      echo "[notify] Notifications disabled (type=none)"
      return 2
      ;;
    *)
      echo "[notify] Unknown type: $NOTIFY_TYPE" >&2; return 1
      ;;
  esac
}