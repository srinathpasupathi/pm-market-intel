#!/bin/bash
# PM Market Intelligence — Pattern Learning Database
# ─────────────────────────────────────────────────────────────────────────────
# SQLite-backed pattern storage. The system learns what to watch for based on
# signals the PM manually submits.
#
# Usage:
#   source lib/patterns.sh
#   init_patterns_db
#   add_pattern "MCP tool scaling" "LLMs degrade when..." "mcp,tools,scaling,llm" ...
#   list_patterns
#   record_match 3
#   generate_watch_list
# ─────────────────────────────────────────────────────────────────────────────

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PATTERNS_DB="$REPO_DIR/data/patterns.db"

# ─── Initialize the database ────────────────────────────────────────────────
init_patterns_db() {
  mkdir -p "$REPO_DIR/data"

  sqlite3 "$PATTERNS_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS signal_patterns (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    pattern_name    TEXT    NOT NULL,
    description     TEXT    NOT NULL,
    keywords        TEXT    NOT NULL,
    watch_for       TEXT    NOT NULL,
    products        TEXT    NOT NULL,
    why_it_matters  TEXT    NOT NULL,
    example_sources TEXT    DEFAULT '',
    default_tier    TEXT    DEFAULT 'TIER 2',
    created_date    TEXT    NOT NULL,
    last_matched    TEXT    DEFAULT '',
    match_count     INTEGER DEFAULT 0,
    active          INTEGER DEFAULT 1
);

CREATE TABLE IF NOT EXISTS signal_log (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    date              TEXT    NOT NULL,
    source_url        TEXT    DEFAULT '',
    title             TEXT    NOT NULL,
    tier              TEXT    NOT NULL,
    matched_patterns  TEXT    DEFAULT '',
    file_path         TEXT    DEFAULT '',
    source_type       TEXT    DEFAULT 'manual'
);

CREATE TABLE IF NOT EXISTS pattern_feedback (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    pattern_id      INTEGER NOT NULL,
    signal_id       INTEGER,
    feedback        TEXT    NOT NULL,
    date            TEXT    NOT NULL,
    FOREIGN KEY (pattern_id) REFERENCES signal_patterns(id),
    FOREIGN KEY (signal_id) REFERENCES signal_log(id)
);
SQL
}

# ─── Add a new pattern ──────────────────────────────────────────────────────
# Args: pattern_name, description, keywords (comma-sep), watch_for,
#       products (comma-sep), why_it_matters, example_url, default_tier
add_pattern() {
  local name="$1"
  local description="$2"
  local keywords="$3"
  local watch_for="$4"
  local products="$5"
  local why="$6"
  local example="${7:-}"
  local tier="${8:-TIER 2}"
  local date
  date=$(date +%Y-%m-%d)

  # Check for duplicate by name
  local existing
  existing=$(sqlite3 "$PATTERNS_DB" \
    "SELECT id FROM signal_patterns WHERE pattern_name = '$name' AND active = 1 LIMIT 1;")

  if [ -n "$existing" ]; then
    echo "[patterns] Pattern '$name' already exists (id=$existing). Updating keywords."
    sqlite3 "$PATTERNS_DB" \
      "UPDATE signal_patterns SET keywords = keywords || ',$keywords', last_matched = '$date' WHERE id = $existing;"
    echo "$existing"
    return 0
  fi

  sqlite3 "$PATTERNS_DB" <<SQL
INSERT INTO signal_patterns (pattern_name, description, keywords, watch_for, products, why_it_matters, example_sources, default_tier, created_date)
VALUES ('$(echo "$name" | sed "s/'/''/g")',
        '$(echo "$description" | sed "s/'/''/g")',
        '$(echo "$keywords" | sed "s/'/''/g")',
        '$(echo "$watch_for" | sed "s/'/''/g")',
        '$(echo "$products" | sed "s/'/''/g")',
        '$(echo "$why" | sed "s/'/''/g")',
        '$(echo "$example" | sed "s/'/''/g")',
        '$tier',
        '$date');
SQL

  local new_id
  new_id=$(sqlite3 "$PATTERNS_DB" "SELECT last_insert_rowid();")
  echo "[patterns] Learned pattern #$new_id: $name"
  echo "$new_id"
}

# ─── Log a signal ───────────────────────────────────────────────────────────
log_signal() {
  local date="$1"
  local url="$2"
  local title="$3"
  local tier="$4"
  local matched_patterns="${5:-}"
  local file_path="${6:-}"
  local source_type="${7:-manual}"

  sqlite3 "$PATTERNS_DB" <<SQL
INSERT INTO signal_log (date, source_url, title, tier, matched_patterns, file_path, source_type)
VALUES ('$date',
        '$(echo "$url" | sed "s/'/''/g")',
        '$(echo "$title" | sed "s/'/''/g")',
        '$tier',
        '$matched_patterns',
        '$(echo "$file_path" | sed "s/'/''/g")',
        '$source_type');
SQL
}

# ─── Record a pattern match (increment counter) ─────────────────────────────
record_match() {
  local pattern_id="$1"
  local date
  date=$(date +%Y-%m-%d)

  sqlite3 "$PATTERNS_DB" \
    "UPDATE signal_patterns SET match_count = match_count + 1, last_matched = '$date' WHERE id = $pattern_id;"
}

# ─── List all active patterns ───────────────────────────────────────────────
list_patterns() {
  sqlite3 -header -column "$PATTERNS_DB" \
    "SELECT id, pattern_name, default_tier, match_count, created_date, last_matched FROM signal_patterns WHERE active = 1 ORDER BY match_count DESC;"
}

# ─── Get pattern keywords for search ────────────────────────────────────────
get_pattern_keywords() {
  sqlite3 "$PATTERNS_DB" \
    "SELECT keywords FROM signal_patterns WHERE active = 1;" | tr ',' '\n' | sort -u | tr '\n' ','
}

# ─── Deactivate a pattern ───────────────────────────────────────────────────
deactivate_pattern() {
  local pattern_id="$1"
  sqlite3 "$PATTERNS_DB" "UPDATE signal_patterns SET active = 0 WHERE id = $pattern_id;"
  echo "[patterns] Pattern #$pattern_id deactivated."
}

# ─── Generate the watch list file for pipeline prompts ───────────────────────
# This is the key function: exports active patterns to a markdown file that
# the daily pipeline prompts include as context.
generate_watch_list() {
  local output_file="$REPO_DIR/data/active-watch-patterns.md"
  local date
  date=$(date +%Y-%m-%d)

  local count
  count=$(sqlite3 "$PATTERNS_DB" "SELECT COUNT(*) FROM signal_patterns WHERE active = 1;")

  if [ "$count" -eq 0 ]; then
    cat > "$output_file" <<EOF
# Learned Watch Patterns
Generated: $date | Active patterns: 0

No learned patterns yet. Submit signals with \`bash submit-signal.sh\` to teach the system.
EOF
    return 0
  fi

  # Header
  cat > "$output_file" <<EOF
# Learned Watch Patterns
Generated: $date | Active patterns: $count

These patterns were learned from signals the PM manually flagged as important.
When you find content matching these patterns, classify it at the indicated tier or higher.

---

EOF

  # Export each active pattern
  sqlite3 -separator '|' "$PATTERNS_DB" \
    "SELECT id, pattern_name, description, keywords, watch_for, products, why_it_matters, default_tier, match_count FROM signal_patterns WHERE active = 1 ORDER BY match_count DESC;" \
  | while IFS='|' read -r id name desc keywords watch products why tier matches; do
    cat >> "$output_file" <<EOF
## Pattern #$id: $name
**Default tier:** $tier | **Times matched:** $matches
**Keywords:** $keywords
**Watch for:** $watch
**Products affected:** $products
**Why it matters:** $why

EOF
  done

  echo "[patterns] Watch list written: $output_file ($count active patterns)"
}

# ─── Get full pattern details as JSON (for Claude to read) ───────────────────
get_patterns_json() {
  sqlite3 -json "$PATTERNS_DB" \
    "SELECT * FROM signal_patterns WHERE active = 1 ORDER BY match_count DESC;"
}

# ─── Stats ──────────────────────────────────────────────────────────────────
pattern_stats() {
  echo "=== Pattern Learning Stats ==="
  echo "Active patterns: $(sqlite3 "$PATTERNS_DB" "SELECT COUNT(*) FROM signal_patterns WHERE active = 1;")"
  echo "Total signals logged: $(sqlite3 "$PATTERNS_DB" "SELECT COUNT(*) FROM signal_log;")"
  echo "Signals this week: $(sqlite3 "$PATTERNS_DB" "SELECT COUNT(*) FROM signal_log WHERE date >= date('now', '-7 days');")"
  echo ""
  echo "Top patterns by match count:"
  sqlite3 -header -column "$PATTERNS_DB" \
    "SELECT id, pattern_name, match_count, last_matched FROM signal_patterns WHERE active = 1 ORDER BY match_count DESC LIMIT 10;"
}