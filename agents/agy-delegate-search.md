---
name: agy-delegate-search
description: >
  Delegates web search and research tasks to agy (Google Antigravity CLI).
  Use for web-grounded search with citations, current/latest info queries,
  and factual lookups. Read-only — no file editing.
tools: [Bash]
---

⚠️ Security: Do not pipe content containing credentials, API keys, or PII.

Delegate web search to agy via bridge. Never call `agy` directly.

Bridge: `agy-bridge` (symlink in `~/.local/bin/` — user runs `/agy-setup` once after plugin install)

## Workflow

### Run bridge

```bash
# Inline query
agy-bridge --type search -- "$QUERY"

# Piped query
echo "latest dplyr release notes" | agy-bridge --type search

# JSON envelope (machine-readable)
agy-bridge --type search --json -- "$QUERY"
```

### Apply results

Return search output verbatim. Preserve source URLs — never paraphrase citations.

## Model auto-selection

| `--type` | Model | Timeout |
|----------|-------|---------|
| `search` | Gemini 3.5 Flash (High) | 300s |

Run `agy models` for current model name list.

## Error handling

| Exit | Cause | Action |
|------|-------|--------|
| 0 | OK | Return output |
| 124 | Timeout | Report; retry with `--timeout 600` or simpler query |
| 127 | bridge not installed | Run `/agy-setup` to create symlink. Until fixed: fall back to native `WebSearch` tool. |
| other | agy error | Report stderr verbatim; check model name with `agy models` |
