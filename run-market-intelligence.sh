#!/bin/bash
# PM Market Intelligence — Daily Runner
# ─────────────────────────────────────────────────────────────────────────────
# Runs the 3-stage pipeline:
#   Stage 1: Community Gatherer  → Reddit + LinkedIn signals
#   Stage 2: Web Gatherer        → HN, GitHub, Product Hunt, Dev.to signals
#   Stage 3: Reviewer            → validate, classify, write brief, send Cliq
#
# Usage:
#   bash run-market-intelligence.sh
#
# Schedule with cron:
#   crontab -e
#   0 7 * * * cd /path/to/pm-market-intel && bash run-market-intelligence.sh >> logs/cron.log 2>&1
# ─────────────────────────────────────────────────────────────────────────────

set -o pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATE=$(date +%Y-%m-%d)
LOG_FILE="$REPO_DIR/logs/market-intelligence-${DATE}.log"

# ─── Colors ──────────────────────────────────────────────────────────────────
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
BOLD="\033[1m"
RESET="\033[0m"

log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
ok()  { echo -e "[$(date '+%H:%M:%S')] ${GREEN}[OK]${RESET} $1" | tee -a "$LOG_FILE"; }
warn(){ echo -e "[$(date '+%H:%M:%S')] ${YELLOW}[WARN]${RESET} $1" | tee -a "$LOG_FILE"; }
err() { echo -e "[$(date '+%H:%M:%S')] ${RED}[ERROR]${RESET} $1" | tee -a "$LOG_FILE"; }

# ─── Pre-flight checks ──────────────────────────────────────────────────────
mkdir -p "$REPO_DIR/outputs/signals" "$REPO_DIR/outputs/briefs" "$REPO_DIR/logs"

if [ ! -f "$REPO_DIR/config.yaml" ]; then
  err "config.yaml not found. Run 'bash setup-new-pm.sh' first."
  exit 1
fi

# Load .env if it exists
if [ -f "$REPO_DIR/.env" ]; then
  set -a
  source "$REPO_DIR/.env"
  set +a
fi

# Find Claude binary
CLAUDE_BIN=""
CANDIDATE_PATHS=(
  "/usr/local/bin/claude"
  "$HOME/.claude/local/claude"
  "$HOME/.nvm/versions/node/v20.19.0/bin/claude"
  "$HOME/.nvm/versions/node/v22.0.0/bin/claude"
)

for p in "${CANDIDATE_PATHS[@]}"; do
  if [ -f "$p" ]; then
    CLAUDE_BIN="$p"
    break
  fi
done

if [ -z "$CLAUDE_BIN" ]; then
  CLAUDE_BIN=$(command -v claude 2>/dev/null || echo "")
fi

if [ -z "$CLAUDE_BIN" ]; then
  err "Claude Code binary not found. Install it: npm install -g @anthropic-ai/claude-code"
  exit 1
fi

# Ensure Claude can find Node
export PATH="$(dirname "$CLAUDE_BIN"):$PATH"

# Unset CLAUDECODE to allow nested sessions
unset CLAUDECODE

# ─── Already ran today? ─────────────────────────────────────────────────────
BRIEF_FILE="$REPO_DIR/outputs/briefs/${DATE}-strategic-brief.md"
if [ -f "$BRIEF_FILE" ]; then
  log "Brief already exists for today ($DATE). Skipping."
  exit 0
fi

# ─── Initialize patterns DB and regenerate watch list ────────────────────────
source "$REPO_DIR/lib/patterns.sh"
if [ ! -f "$PATTERNS_DB" ]; then
  init_patterns_db
  log "Initialized patterns database."
fi
generate_watch_list >> "$LOG_FILE" 2>&1
ok "Watch patterns loaded."

log "═══════════════════════════════════════════════"
log "Starting daily market intelligence — $DATE"

# ─── Helper: run a Claude prompt ─────────────────────────────────────────────
run_stage() {
  local name="$1"
  local prompt_file="$2"

  log "── $name ──"

  "$CLAUDE_BIN" \
    --print \
    --dangerously-skip-permissions \
    -p "$(cat "$prompt_file")" \
    >> "$LOG_FILE" 2>&1

  local exit_code=$?
  if [ $exit_code -eq 0 ]; then
    ok "$name completed."
  else
    warn "$name exited with code $exit_code."
  fi
  return $exit_code
}

# ─── Stage 1: Community Gatherer ─────────────────────────────────────────────
COMMUNITY_SIGNALS="$REPO_DIR/outputs/signals/${DATE}-community-signals.md"
if [ -f "$COMMUNITY_SIGNALS" ]; then
  log "Community signals already exist — skipping Stage 1."
else
  run_stage "Community Gatherer" "$REPO_DIR/prompts/community.md"
fi

# ─── Stage 2: Web Gatherer ──────────────────────────────────────────────────
WEB_SIGNALS="$REPO_DIR/outputs/signals/${DATE}-web-signals.md"
if [ -f "$WEB_SIGNALS" ]; then
  log "Web signals already exist — skipping Stage 2."
else
  run_stage "Web Gatherer" "$REPO_DIR/prompts/web.md"
fi

# ─── Check we have at least one signal file ──────────────────────────────────
if [ ! -f "$COMMUNITY_SIGNALS" ] && [ ! -f "$WEB_SIGNALS" ]; then
  err "No signal files produced by either gatherer. Aborting."
  exit 1
fi

# ─── Stage 3: Reviewer & Brief Writer ───────────────────────────────────────
run_stage "Signal Reviewer & Brief Writer" "$REPO_DIR/prompts/reviewer.md"

# ─── Done ────────────────────────────────────────────────────────────────────
if [ -f "$BRIEF_FILE" ]; then
  ok "Strategic brief written: outputs/briefs/${DATE}-strategic-brief.md"
else
  warn "Brief file not found after run — check the log at $LOG_FILE"
fi

log "══ Pipeline complete ══"