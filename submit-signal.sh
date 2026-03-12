#!/bin/bash
# PM Market Intelligence — Submit a Manual Signal
# ─────────────────────────────────────────────────────────────────────────────
# Use this when you find a high-signal article, post, or observation and want
# to log it into the intelligence system immediately.
#
# What happens:
#   1. Claude reads the URL (if provided) and your note
#   2. Classifies the signal by tier and maps it to your products
#   3. Writes a structured signal file to inbox/signals/
#   4. LEARNS THE PATTERN — extracts the underlying problem/trend and stores
#      it in the patterns database so future daily scans watch for it
#   5. Regenerates the active watch list for the daily pipeline
#   6. Sends a Cliq notification (if configured)
#
# Usage:
#   bash submit-signal.sh "https://reddit.com/r/..." "MCP tool overload is a real problem for us"
#   bash submit-signal.sh "https://news.ycombinator.com/item?id=..."
#   bash submit-signal.sh "" "Heard from a customer that they're evaluating competitor X"
#
# Manage learned patterns:
#   bash submit-signal.sh --patterns          # list all learned patterns
#   bash submit-signal.sh --stats             # show pattern learning stats
#   bash submit-signal.sh --deactivate 3      # stop watching pattern #3
# ─────────────────────────────────────────────────────────────────────────────

set -o pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATE=$(date +%Y-%m-%d)

# ─── Colors ──────────────────────────────────────────────────────────────────
BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
RESET="\033[0m"

# ─── Load pattern library ───────────────────────────────────────────────────
source "$REPO_DIR/lib/patterns.sh"

# Initialize DB if needed
if [ ! -f "$PATTERNS_DB" ]; then
  init_patterns_db
fi

# ─── Handle management commands ─────────────────────────────────────────────
case "${1:-}" in
  --patterns)
    echo ""
    echo -e "${BOLD}Learned Signal Patterns${RESET}"
    echo "────────────────────────────────────────────────────────────────"
    list_patterns
    exit 0
    ;;
  --stats)
    echo ""
    pattern_stats
    exit 0
    ;;
  --deactivate)
    if [ -z "${2:-}" ]; then
      echo "Usage: bash submit-signal.sh --deactivate <pattern_id>"
      exit 1
    fi
    deactivate_pattern "$2"
    generate_watch_list
    exit 0
    ;;
  --regenerate)
    generate_watch_list
    exit 0
    ;;
esac

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
  echo "Management:"
  echo "  bash submit-signal.sh --patterns          # list learned patterns"
  echo "  bash submit-signal.sh --stats             # show stats"
  echo "  bash submit-signal.sh --deactivate <id>   # stop watching a pattern"
  echo "  bash submit-signal.sh --regenerate        # rebuild watch list"
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

# ─── Create directories ─────────────────────────────────────────────────────
mkdir -p "$REPO_DIR/inbox/signals" "$REPO_DIR/data"

# ─── Load existing patterns for context ──────────────────────────────────────
EXISTING_PATTERNS=""
if [ -f "$REPO_DIR/data/active-watch-patterns.md" ]; then
  EXISTING_PATTERNS=$(cat "$REPO_DIR/data/active-watch-patterns.md")
fi

# ─── Build the prompt ────────────────────────────────────────────────────────
PROMPT="You are a signal intake analyst with a LEARNING system. A PM has manually submitted a signal they consider important.

You have TWO jobs:
1. Process the signal (classify, map to products, write signal file)
2. EXTRACT THE UNDERLYING PATTERN and store it so the system watches for similar signals in future

## Job 1: Process the Signal

1. If a URL is provided, fetch it and read the full content. Extract the key claims, pain points, and community discussion.
2. Read config.yaml and CLAUDE.md to understand the PM's products and competitors.
3. Classify the signal (TIER 1 = immediate attention, TIER 2 = track, TIER 3 = background).
4. Map it to specific products with impact levels.
5. Write a structured signal file to inbox/signals/${DATE}-{short-slug}.md using the format from agents/signal-intake.md.

## Job 2: Extract and Store the Pattern

The specific article/post is just ONE instance. Extract the UNDERLYING PATTERN — the class of problem, trend, or shift that this signal represents.

After writing the signal file, run these bash commands to store the learned pattern:

\`\`\`bash
source lib/patterns.sh

# Store the pattern (all 8 arguments required)
add_pattern \\
  \"<pattern_name>\" \\
  \"<1-2 sentence description of the pattern class>\" \\
  \"<comma-separated search keywords that would find similar signals>\" \\
  \"<what to watch for: specific things that indicate this pattern is appearing>\" \\
  \"<comma-separated product names affected>\" \\
  \"<why this pattern matters strategically>\" \\
  \"${URL:-observation}\" \\
  \"<TIER 1 or TIER 2 or TIER 3>\"

# Log this signal
log_signal \"${DATE}\" \"${URL:-}\" \"<signal title>\" \"<tier>\" \"<pattern_id if matched>\" \"inbox/signals/${DATE}-{slug}.md\" \"manual\"

# Regenerate the watch list for future pipeline runs
generate_watch_list
\`\`\`

### Pattern extraction rules:
- The pattern name should be GENERAL, not specific to this one article
  GOOD: \"MCP tool scaling and LLM degradation\"
  BAD: \"Blender MCP Pro 100 tools article\"
- Keywords should include terms that would catch SIMILAR future signals
  GOOD: \"mcp,tool count,tool overload,llm hallucination,tool selection,context window\"
  BAD: \"blender,3d,mcp pro\"
- Watch-for should describe OBSERVABLE indicators, not the specific event
  GOOD: \"MCP servers advertising 50+ tools, discussions about LLM tool confusion, requests for tool grouping or namespacing\"
  BAD: \"Blender MCP Pro updates\"
- Connect to the PM's actual products from config.yaml

## Existing Learned Patterns

Check if this signal matches or extends an existing pattern before creating a new one:

${EXISTING_PATTERNS:-"No patterns learned yet."}

## Signal Details

- URL: ${URL:-"(none — PM observation only)"}
- PM's note: ${NOTE:-"(no additional note)"}
- Date: ${DATE}

Read agents/signal-intake.md for the signal file format. Follow it precisely.

## Final Output

After both jobs are done, print:
1. A one-paragraph signal summary
2. The pattern that was learned (name + what the system will now watch for)
3. Total active patterns count"

# ─── Run ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Submitting signal...${RESET}"
[ -n "$URL" ] && echo -e "  URL:  ${URL}"
[ -n "$NOTE" ] && echo -e "  Note: ${NOTE}"
echo ""
echo -e "${CYAN}Processing signal and extracting pattern...${RESET}"
echo ""

"$CLAUDE_BIN" \
  --print \
  --dangerously-skip-permissions \
  -p "$PROMPT"

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  echo ""
  echo "────────────────────────────────────────────────────────────────"
  echo -e "${GREEN}[OK]${RESET} Signal processed and pattern learned."
  echo ""

  # Show current patterns
  echo -e "${BOLD}Active watch patterns:${RESET}"
  list_patterns 2>/dev/null || echo "  (run 'bash submit-signal.sh --patterns' to view)"
  echo ""
  echo -e "Signal file: ${CYAN}inbox/signals/${RESET}"
  echo -e "Watch list:  ${CYAN}data/active-watch-patterns.md${RESET}"
else
  echo ""
  echo -e "${YELLOW}[WARN]${RESET} Claude exited with code $EXIT_CODE. Check if signal and pattern were saved."
fi