---
name: agy-delegate
description: Use when doing web searches, looking up current or latest info, researching online, or delegating analysis/review tasks to agy (Google Antigravity CLI). Prefer agy over native WebSearch for any factual or time-sensitive query. Triggers on: agy, antigravity, search for, look up, find online, current info, latest, news, research, second opinion from Gemini or GPT.
---

# AGY Delegate

agy (Google Antigravity CLI) provides grounded web search with source citations plus access to Gemini 3.1/3.5, Claude Opus 4.6 (Thinking), and GPT-OSS 120B — all from one subprocess call. Use it instead of the native WebSearch tool so responses include real source URLs and aren't limited to training-data recency.

⚠️ Security: Do not pipe content containing credentials, API keys, or PII. The prompt is passed as a --print argument and appears in the system process list (ps).

## When to Use

**Web search (prefer over native WebSearch):**
- "What is the current...", "latest version of...", "search for..."
- Factual claims that need source citations
- Pricing, changelogs, release notes, documentation

**On request:**
- Adversarial review of code or plans from an independent model (`--type review`)
- Large-file analysis via Gemini's extended context (`--type analysis`)
- "Use agy to...", "Ask Gemini...", "Check with GPT..."

## Usage

Bridge: `agy-bridge` (symlink in `~/.local/bin/` — run `/agy-setup` once after plugin install). Wraps `agy` with `--dangerously-skip-permissions`, shell-safe prompt passing, and consistent exit-code handling.

### Web search

```bash
echo "Claude API pricing June 2026" | agy-bridge --type search
```

### Code / task delegation

Read target files first (agy only sees what you pipe — it has no filesystem access in bridge mode), then construct the prompt:

```bash
{
  echo "Question: <question>"
  echo "---"
  cat src/foo.R
} | agy-bridge --type code
```

### Adversarial review

```bash
echo "Critique this plan: <plan>" | agy-bridge --type review
```

### Inline prompt (no stdin)

```bash
agy-bridge --type search -- "latest dplyr release"
```

### JSON output envelope

```bash
echo "query" | agy-bridge --type search --json
# → {"success":true,"model_used":"...","type":"search","duration_seconds":9,"response":"..."}
```

## Model Routing

| `--type` | Auto-selected model | Why |
|----------|--------------------|----|
| `search` | Gemini 3.5 Flash (High) | Fast, web-grounded |
| `code` | Gemini 3.1 Pro (High) | Extended context |
| `analysis` | Gemini 3.1 Pro (High) | Large file analysis |
| `review` | Claude Opus 4.6 (Thinking) | Independent adversarial view |

Omitting `--type` defaults to `code`. Override: `--model "Gemini 3.5 Flash (Low)"`.

Run `agy models` for current model names — values above match bridge defaults and may lag agy updates.

## Common Mistakes

| Symptom | Fix |
|---------|-----|
| Response lacks source URLs | Re-run with `--type search` (prefix prompts agy to call `search_web`) |
| Exit 124 | Timeout — simplify query or pass `--timeout 600` |
| Model name rejected | Exact string required — run `agy models` for current names |
| `agy: command not found` | Binary at `~/.local/bin/agy` — check PATH |
| Calling `agy` directly | Use bridge — direct calls miss `--dangerously-skip-permissions` |

## Reference

Provider details, auth, timeout guidance: `config/provider.md`
