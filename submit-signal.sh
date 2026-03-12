#!/bin/bash
# PM Market Intelligence — Submit a Manual Signal
# ─────────────────────────────────────────────────────────────────────────────
# Use this when you find a high-signal article, post, or observation and want
# to log it into the intelligence system immediately.
#
# Usage:
#   bash submit-signal.sh "https://reddit.com/r/..." "MCP tool overload is a real problem for us"
#   bash submit-signal.sh "https://news.ycombinator.com/item?id=..."
#   bash submit-signal.sh "" "Heard from a customer that they're evaluating competitor X"
#
# What happens:
#   1. Claude reads the URL (if provided) and your note
#   2. Classifies the signal by tier and maps it to your products
#   3. Writes a structured signal file to inbox/signals/
#   4. Sends a Cliq notification (if configured)
# ─────────────────────────────────────────────────────────────────────────────

set -o pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATE=$(date +%Y-%m-%d)

# ─── Colors ──────────────────────────────────────────────────────────────────
BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"

# ─── Parse arguments ────────────────────────────────────────────────────────
URL="${1:-}"
NOTE="${2:-}"

if [ -z "$URL" ] && [ -z "$NOTE" ]; then
  echo ""
  echo -e "${BOLD}Submit a manual signal${RESET}"
  echo "────────────────────────────────────────────────────────────────"
  echo ""
  echo "Usage:"
  echo "  bash submit-signal.sh <url> [note]"
  echo "  bash submit-signal.sh \"\" \"Your observation here\""
  echo ""
  echo "Examples:"
  echo "  bash submit-signal.sh \"https://reddit.com/r/mcp/...\" \"Tool overload problem\""
  echo "  bash submit-signal.sh \"https://news.ycombinator.com/item?id=123\""
  echo "  bash submit-signal.sh \"\" \"Customer mentioned switching to competitor X\""
  echo ""
  exit 0
fi

# ─── Pre-flight ──────────────────────────────────────────────────────────────
if [ ! -f "$REPO_DIR/config.yaml" ]; then
  echo -e "${RED}[ERROR]${RESET} config.yaml not found. Run 'bash setup-new-pm.sh' first."
  exit 1
fi

# Load .env
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
  echo -e "${RED}[ERROR]${RESET} Claude Code binary not found."
  exit 1
fi

export PATH="$(dirname "$CLAUDE_BIN"):$PATH"
unset CLAUDECODE

# ─── Create inbox/signals directory ──────────────────────────────────────────
mkdir -p "$REPO_DIR/inbox/signals"

# ─── Build the prompt ────────────────────────────────────────────────────────
PROMPT="You are a signal intake analyst. A PM has manually submitted a signal they consider important.

Your task:
1. If a URL is provided, fetch it and read the full content. Extract the key claims, pain points, and community discussion.
2. Read config.yaml and CLAUDE.md to understand the PM's products and competitors.
3. Classify the signal (TIER 1 = immediate attention, TIER 2 = track, TIER 3 = background).
4. Map it to specific products with impact levels.
5. Write a structured signal file to inbox/signals/${DATE}-{short-slug}.md using the format from agents/signal-intake.md.
6. Print a one-paragraph summary at the end.

Signal details:
- URL: ${URL:-"(none — PM observation only)"}
- PM's note: ${NOTE:-"(no additional note)"}
- Date: ${DATE}

Read agents/signal-intake.md for the exact output format and rules. Follow them precisely."

# ─── Run ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Submitting signal...${RESET}"
[ -n "$URL" ] && echo -e "  URL:  ${URL}"
[ -n "$NOTE" ] && echo -e "  Note: ${NOTE}"
echo ""

"$CLAUDE_BIN" \
  --print \
  --dangerously-skip-permissions \
  -p "$PROMPT"

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  echo ""
  echo -e "${GREEN}[OK]${RESET} Signal processed. Check inbox/signals/ for the output."
else
  echo ""
  echo -e "${YELLOW}[WARN]${RESET} Claude exited with code $EXIT_CODE. The signal may not have been saved."
fi