#!/bin/bash
# PM Market Intelligence — Generate Watch Patterns
# ─────────────────────────────────────────────────────────────────────────────
# Exports all active learned patterns from the SQLite database into a markdown
# file that the daily pipeline prompts include as context.
#
# Run this:
#   - Automatically after each submit-signal.sh
#   - Before each daily pipeline run (run-market-intelligence.sh calls this)
#   - Manually anytime: bash generate-watch-patterns.sh
#
# Output: data/active-watch-patterns.md
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO_DIR/lib/patterns.sh"

# Initialize DB if it doesn't exist
if [ ! -f "$PATTERNS_DB" ]; then
  init_patterns_db
  echo "[generate] Initialized patterns database."
fi

# Generate the watch list
generate_watch_list

# Also show stats
echo ""
pattern_stats