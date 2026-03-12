# PM Market Intelligence

A daily market intelligence pipeline for Product Managers, powered by Claude Code.

Every morning, this system scans Reddit, LinkedIn, Hacker News, GitHub Trending, Product Hunt, and Dev.to for signals relevant to your products and competitors — then delivers a prioritized strategic brief to your Zoho Cliq channel.

## What It Does

1. **Gathers signals** from developer communities (Reddit, LinkedIn) and the open web (HN, GitHub, Product Hunt, Dev.to/Medium)
2. **Validates and classifies** each signal by evidence quality and urgency (ESCALATE / FLAG / WATCH / DISCARD)
3. **Writes a strategic brief** with product-specific implications and recommended actions
4. **Sends a Cliq notification** with the highlights

## Prerequisites

- macOS or Linux
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed (`npm install -g @anthropic-ai/claude-code`)
- An Anthropic API key (Claude Code handles this via its own auth)
- Optional: [xAI API key](https://console.x.ai) for X/Twitter intelligence
- Optional: Zoho Cliq bot webhook for notifications ([setup guide](https://www.zoho.com/cliq/help/platform/incoming-webhook-bots.html))

## Quick Start

```bash
# Clone the repo
git clone https://github.com/srinathpasupathi/pm-market-intel.git
cd pm-market-intel

# Run the setup wizard (5 minutes)
bash setup-new-pm.sh

# Run your first intelligence scan
bash run-market-intelligence.sh

# (Optional) Schedule it daily with cron
crontab -e
# Add: 0 7 * * * cd /path/to/pm-market-intel && bash run-market-intelligence.sh >> logs/cron.log 2>&1

# Submit a manual signal (article, observation, etc.)
bash submit-signal.sh "https://reddit.com/r/..." "Why this matters for us"
```

## Setup

The setup wizard (`setup-new-pm.sh`) will ask you about:
- Your role and company
- Your products (names and short labels)
- Brand monitoring terms
- Your competitors (primary and extended)
- Your domain and community sources to monitor
- Zoho Cliq bot credentials for notifications

It generates:
- `config.yaml` — your personalized configuration
- `.env` — your API keys and Cliq credentials (gitignored, never committed)
- `CLAUDE.md` — your project context file
- Directory structure for outputs

## Daily Output

Each run produces:
- **Signal files** in `outputs/signals/` — raw gathered signals from each source
- **Strategic brief** in `outputs/briefs/` — the prioritized intelligence report
- **Cliq notification** with the highlights and source links

## Agents

The `agents/` directory contains instruction files for common PM tasks. These are not part of the daily pipeline but can be used with Claude Code interactively:

| Agent | Purpose |
|-------|---------|
| `market-intelligence` | Trends, category shifts, timing signals |
| `competitor-pattern-predictor` | Predict competitor next moves |
| `customer-segment-analysis` | Personas, ICPs, segment prioritization |
| `feature-evaluator` | Build / defer / kill / reshape decisions |
| `marketing-recommendations` | Product-to-marketing translation |
| `meeting-transcript-analyzer` | Extract decisions and action items |
| `prd-generator` | Generate PRDs from feature evaluations |
| `product-strategy` | Strategic opportunities and sequencing |
| `roadmap-review` | Stack-rank and gap analysis |
| `signal-intake` | Process manually submitted signals (articles, observations) |
| `ux-audit-reviewer` | Friction points and usability gaps |

Use them interactively: open the project in Claude Code and ask it to use an agent, or reference the agent file directly.

## Manual Signal Intake

The daily pipeline catches broad signals automatically. But when **you** find something important — an article, a Reddit post, a customer observation — use the signal intake system:

```bash
# Submit a URL with optional context
bash submit-signal.sh "https://reddit.com/r/mcp/comments/..." "Tool overload is a real problem for us"

# Submit a URL only (Claude analyzes it against your products)
bash submit-signal.sh "https://news.ycombinator.com/item?id=123"

# Submit a pure observation (no URL)
bash submit-signal.sh "" "Customer X mentioned they're evaluating competitor Y"
```

What happens:
1. Claude fetches the URL and reads the full content
2. Maps the signal to your products (from `config.yaml`)
3. Classifies it by tier (TIER 1 = immediate, TIER 2 = track, TIER 3 = background)
4. Writes a structured signal file to `inbox/signals/`
5. **Extracts the underlying pattern** and stores it in a SQLite database
6. Regenerates the watch list so future daily scans look for similar signals
7. Sends a Cliq notification if configured

### Pattern Learning

The system doesn't just file one article — it **learns the pattern class.** For example, submitting an article about "MCP servers with 100+ tools causing LLM hallucination" teaches the system the pattern "MCP tool scaling and LLM degradation." Every future daily scan then watches for discussions, articles, or launches that match this pattern — even from sources the original article never mentioned.

Patterns are stored in a SQLite database (`data/patterns.db`) and exported to `data/active-watch-patterns.md` for pipeline prompts.

```bash
# View all learned patterns
bash submit-signal.sh --patterns

# View learning stats
bash submit-signal.sh --stats

# Stop watching a pattern
bash submit-signal.sh --deactivate 3

# Manually regenerate the watch list
bash submit-signal.sh --regenerate
```

## File Structure

```
pm-market-intel/
├── setup-new-pm.sh           ← one-time setup wizard
├── run-market-intelligence.sh ← daily pipeline runner
├── submit-signal.sh          ← manual signal intake
├── config.yaml               ← your settings (generated by setup)
├── CLAUDE.md                 ← project context (generated by setup)
├── .env                      ← secrets (gitignored)
├── prompts/
│   ├── community.md          ← Reddit + LinkedIn gatherer
│   ├── web.md                ← HN, GitHub, PH, Dev.to gatherer
│   └── reviewer.md           ← validate, classify, brief, Cliq notify
├── agents/
│   ├── market-intelligence.md
│   ├── competitor-pattern-predictor.md
│   ├── customer-segment-analysis.md
│   ├── feature-evaluator.md
│   ├── marketing-recommendations.md
│   ├── meeting-transcript-analyzer.md
│   ├── prd-generator.md
│   ├── product-strategy.md
│   ├── roadmap-review.md
│   ├── signal-intake.md       ← manual signal processing
│   └── ux-audit-reviewer.md
├── generate-watch-patterns.sh ← rebuild pattern watch list
├── lib/
│   ├── notify.sh             ← Zoho Cliq notification
│   └── patterns.sh           ← SQLite pattern learning functions
├── data/
│   ├── patterns.db           ← learned signal patterns (SQLite)
│   └── active-watch-patterns.md ← exported watch list for pipeline
├── context/
│   └── products/             ← your product context files
├── inbox/
│   └── signals/              ← manually submitted signals
├── outputs/                  ← daily outputs (gitignored)
│   ├── signals/
│   └── briefs/
└── logs/                     ← execution logs (gitignored)
```

## Customization

- Edit `config.yaml` to change products, competitors, or search terms
- Add product context files in `context/products/` for better signal classification
- Edit `CLAUDE.md` to refine your professional identity and priorities
- Adjust prompts in `prompts/` to tune signal quality
- Add or modify agents in `agents/` for your PM workflows

## Cost

Each daily run uses approximately 2-4 Claude Code sessions (one per pipeline stage). Actual cost depends on your Anthropic plan. The pipeline uses `--print` mode for minimal token usage.

## License

MIT