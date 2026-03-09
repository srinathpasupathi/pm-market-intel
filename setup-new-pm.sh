#!/bin/bash
# PM Market Intelligence — New PM Setup Wizard
# ─────────────────────────────────────────────────────────────────────────────
# Run this script to set up PM Market Intelligence for a new PM.
# It will:
#   1. Ask for your PM profile
#   2. Create config.yaml from your answers
#   3. Create .env with your secrets
#   4. Generate CLAUDE.md with your project context
#   5. Set up the directory structure
#
# Prerequisites:
#   - macOS or Linux
#   - Claude CLI installed: npm install -g @anthropic-ai/claude-code
#   - Zoho Cliq bot webhook for notifications (optional)
#   - xAI API key for X/Twitter intelligence (optional): https://console.x.ai
#
# Usage:
#   bash setup-new-pm.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Colors ──────────────────────────────────────────────────────────────────
BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
RESET="\033[0m"

header()  { echo -e "\n${BOLD}${CYAN}$1${RESET}"; }
success() { echo -e "${GREEN}[OK]${RESET} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $1"; }
prompt()  { echo -e -n "${BOLD}$1${RESET} "; }

# ─── Prevent re-running ─────────────────────────────────────────────────────
if [ -f "$REPO_DIR/config.yaml" ]; then
  echo ""
  echo "config.yaml already exists in $REPO_DIR"
  echo "This setup wizard is for fresh installs only."
  echo ""
  echo "Options:"
  echo "  - Edit config.yaml directly to change your settings"
  echo "  - Delete config.yaml and re-run this script to start fresh"
  echo ""
  exit 0
fi

echo ""
echo -e "${BOLD}PM Market Intelligence — Setup Wizard${RESET}"
echo "────────────────────────────────────────────────────────────────"
echo "This will take about 5 minutes."
echo "Your setup is private and local — nothing is sent anywhere."
echo ""

# ─── Step 1: PM Profile ─────────────────────────────────────────────────────
header "Step 1 — Your PM profile"

prompt "Your name or title (e.g. 'Senior PM', 'Head of Product'):"
read -r PM_NAME

prompt "Your company:"
read -r PM_COMPANY

prompt "Your domain (e.g. 'Developer Platforms', 'B2B SaaS / CRM', 'Mobile SDK'):"
read -r PM_DOMAIN

# ─── Step 2: Products ───────────────────────────────────────────────────────
header "Step 2 — Your products"
echo "List your main products. These will appear as signal relevance labels."
echo "Enter one per line. Press Enter on a blank line when done."
echo ""

OWN_PRODUCTS_YAML=""
PRODUCT_NAMES=()

i=1
while true; do
  prompt "  Product $i full name (or Enter to stop):"
  read -r PROD_NAME
  [ -z "$PROD_NAME" ] && break

  prompt "  Product $i short label (e.g. 'CRM', 'API', 'Mobile'):"
  read -r PROD_SHORT

  OWN_PRODUCTS_YAML+="    - name: \"$PROD_NAME\"\n"
  OWN_PRODUCTS_YAML+="      short: \"$PROD_SHORT\"\n"
  PRODUCT_NAMES+=("$PROD_SHORT")
  ((i++))
done

# ─── Step 3: Brand monitoring terms ─────────────────────────────────────────
header "Step 3 — Brand monitoring"
echo "Search terms to monitor YOUR OWN brand/products on the web."
echo "Include product names, company-specific terms, known aliases."
echo "Enter one per line. Press Enter on a blank line when done."
echo ""

OWN_BRAND_YAML=""
j=1
while true; do
  prompt "  Brand term $j (or Enter to stop):"
  read -r BRAND_TERM
  [ -z "$BRAND_TERM" ] && break
  OWN_BRAND_YAML+="    - \"$BRAND_TERM\"\n"
  ((j++))
done

# ─── Step 4: Competitors ────────────────────────────────────────────────────
header "Step 4 — Competitors"
echo "Primary competitors: direct competitors you track daily (6-12 names)."
echo "Extended competitors: broader ecosystem players."
echo "Enter one per line. Press Enter on a blank line when done."
echo ""

PRIMARY_YAML=""
COMPETITOR_LIST=""
echo -e "${BOLD}Primary competitors:${RESET}"
k=1
while true; do
  prompt "  Primary competitor $k (or Enter to stop):"
  read -r COMP
  [ -z "$COMP" ] && break
  PRIMARY_YAML+="    - \"$COMP\"\n"
  [ -n "$COMPETITOR_LIST" ] && COMPETITOR_LIST+=", "
  COMPETITOR_LIST+="$COMP"
  ((k++))
done

EXTENDED_YAML=""
echo ""
echo -e "${BOLD}Extended competitors (infrastructure, frameworks, ecosystem tools):${RESET}"
l=1
while true; do
  prompt "  Extended competitor $l (or Enter to stop):"
  read -r COMP
  [ -z "$COMP" ] && break
  EXTENDED_YAML+="    - \"$COMP\"\n"
  [ -n "$COMPETITOR_LIST" ] && COMPETITOR_LIST+=", "
  COMPETITOR_LIST+="$COMP"
  ((l++))
done

# ─── Step 5: Domain & search ────────────────────────────────────────────────
header "Step 5 — Domain and search topics"

prompt "Domain category label (e.g. 'B2B SaaS / CRM', 'API tooling / developer infrastructure'):"
read -r DOMAIN_CATEGORY

echo ""
echo "Community subreddits to monitor daily (general community, not competitor-owned)."
echo "e.g. r/programming, r/webdev, r/SaaS, r/devops"
echo ""
COMM_SUBS_YAML=""
n=1
while true; do
  prompt "  Community subreddit $n (or Enter to stop):"
  read -r SUB
  [ -z "$SUB" ] && break
  COMM_SUBS_YAML+="    - \"$SUB\"\n"
  ((n++))
done

echo ""
echo "Search query strings for web intelligence sources."
echo "These are exact search strings used in web queries."
echo ""
prompt "Hacker News search string (e.g. '\"your topic\" OR \"your keyword\"'):"
read -r SEARCH_HN
prompt "GitHub trending search (e.g. 'keyword OR \"product category\"'):"
read -r SEARCH_GITHUB
prompt "Product Hunt search (e.g. '\"your topic\" OR keyword'):"
read -r SEARCH_PH
prompt "Dev.to/Medium search (e.g. '\"your topic\" OR \"category\"'):"
read -r SEARCH_MEDIUM

# ─── Step 6: Zoho Cliq Notifications ────────────────────────────────────────
header "Step 6 — Zoho Cliq notifications"
echo "The pipeline sends daily intelligence briefs to a Zoho Cliq channel."
echo "You need a Cliq bot incoming webhook URL and token."
echo "See: https://www.zoho.com/cliq/help/platform/incoming-webhook-bots.html"
echo ""
echo "Press Enter to skip if you don't have Cliq set up yet."
echo ""

prompt "Cliq bot incoming URL (or Enter to skip):"
read -rs CLIQ_URL; echo ""

CLIQ_TOKEN=""
if [ -n "$CLIQ_URL" ]; then
  prompt "Cliq bot token:"
  read -rs CLIQ_TOKEN; echo ""
  NOTIFY_TYPE="cliq"
else
  NOTIFY_TYPE="none"
  warn "Notifications disabled. You can add Cliq credentials to .env later."
fi

# ─── Step 7: Write config.yaml ──────────────────────────────────────────────
header "Step 7 — Writing config.yaml"

cat > "$REPO_DIR/config.yaml" << EOF
# PM Market Intelligence — Personal Configuration
# Generated by setup-new-pm.sh — edit freely

pm:
  name: "$PM_NAME"
  company: "$PM_COMPANY"
  domain: "$PM_DOMAIN"

  own_products:
$(echo -e "$OWN_PRODUCTS_YAML")
  own_brand_search_terms:
$(echo -e "$OWN_BRAND_YAML")
competitors:
  primary:
$(echo -e "$PRIMARY_YAML")
  extended:
$(echo -e "$EXTENDED_YAML")
domain:
  category: "$DOMAIN_CATEGORY"

  community_subreddits:
$(echo -e "$COMM_SUBS_YAML")
  search_queries:
    hn: '$SEARCH_HN'
    github: '$SEARCH_GITHUB'
    producthunt: '$SEARCH_PH'
    medium_devto: '$SEARCH_MEDIUM'

notifications:
  type: "$NOTIFY_TYPE"
EOF

success "Created: config.yaml"

# ─── Step 8: Create .env ────────────────────────────────────────────────────
header "Step 8 — Setting up .env"

if [ -f "$REPO_DIR/.env" ]; then
  warn ".env already exists — skipping. Edit it manually if needed."
else
  echo ""
  prompt "xAI API key (optional, for X/Twitter intelligence — Enter to skip):"
  read -rs XAI_KEY; echo ""

  cat > "$REPO_DIR/.env" << ENVEOF
# PM Market Intelligence — Secrets
# Keep this file private. Never commit it.
XAI_API_KEY="$XAI_KEY"
CLIQ_BOT_INCOMING_URL="$CLIQ_URL"
CLIQ_BOT_TOKEN="$CLIQ_TOKEN"
ENVEOF

  chmod 600 "$REPO_DIR/.env"
  success "Created: .env"
fi

# ─── Step 9: Create directory structure ──────────────────────────────────────
header "Step 9 — Creating directory structure"

mkdir -p \
  "$REPO_DIR/context/products" \
  "$REPO_DIR/outputs/signals" \
  "$REPO_DIR/outputs/briefs" \
  "$REPO_DIR/logs"

success "Directory structure created"

# ─── Step 10: Generate CLAUDE.md ─────────────────────────────────────────────
header "Step 10 — Generating CLAUDE.md"

PRODUCT_LIST=""
for p in "${PRODUCT_NAMES[@]}"; do
  [ -n "$PRODUCT_LIST" ] && PRODUCT_LIST+=", "
  PRODUCT_LIST+="$p"
done

cat > "$REPO_DIR/CLAUDE.md" << CLAUDEEOF
# PM Market Intelligence — Project Context

## Who This Is For

**Role:** $PM_NAME at $PM_COMPANY
**Domain:** $PM_DOMAIN
**Products:** $PRODUCT_LIST

## What This System Does

This is a daily market intelligence pipeline. It gathers signals from developer communities and the open web, validates them against your product context, and delivers a prioritized strategic brief to Zoho Cliq.

## Products

$(echo -e "$OWN_PRODUCTS_YAML" | sed 's/^    - name: /- /; s/^      short: /  Short: /')

## Competitors

Known competitors (anything NOT on this list = potential new entrant):
$COMPETITOR_LIST

## Agents

Available agents in the \`agents/\` directory:
- **market-intelligence** — trends, category shifts, timing signals (used by daily pipeline)
- **competitor-pattern-predictor** — predict competitor next moves
- **customer-segment-analysis** — personas, ICPs, segment prioritization
- **feature-evaluator** — evaluate build/defer/kill/reshape decisions
- **marketing-recommendations** — product-to-marketing translation
- **meeting-transcript-analyzer** — extract decisions and action items
- **prd-generator** — generate PRDs from feature evaluations
- **product-strategy** — strategic opportunities and sequencing
- **roadmap-review** — stack-rank and gap analysis
- **ux-audit-reviewer** — friction points and usability gaps

## Operating Rules

- Lead with the signal and its implication, not background context
- Every signal must have a source URL
- Separate confirmed facts from inferences — label which is which
- Connect every signal to a specific product — not the company generically
- If evidence is weak, say so explicitly
- No generic industry commentary — everything must be relevant to these products
CLAUDEEOF

success "Created: CLAUDE.md"

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────────────────────────"
echo -e "${BOLD}${GREEN}Setup complete!${RESET}"
echo ""
echo "What's ready:"
echo "  - config.yaml     — your personal settings"
echo "  - .env            — your secrets (gitignored)"
echo "  - CLAUDE.md       — your project context"
echo ""
echo "Next steps:"
echo ""
echo "  1. ${BOLD}Add product context${RESET} (recommended)"
echo "     Create one .md file per product in context/products/"
echo "     Include: what it does, target users, current stage, open decisions"
echo ""
echo "  2. ${BOLD}Run your first scan${RESET}"
echo "     bash run-market-intelligence.sh"
echo ""
echo "  3. ${BOLD}Schedule it daily${RESET} (optional)"
echo "     crontab -e"
echo "     Add: 0 7 * * * cd $REPO_DIR && bash run-market-intelligence.sh >> logs/cron.log 2>&1"
echo ""