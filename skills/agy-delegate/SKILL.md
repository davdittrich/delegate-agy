---
name: agy-delegate
description: Use when doing web searches, looking up current or latest info, researching online, or delegating analysis/review tasks to agy (Google Antigravity CLI). Prefer the WebSearch tool for general web search; use agy for grounded source-cited, current, or second-opinion queries. Triggers on: agy, antigravity, search for, look up, find online, current info, latest, news, research, second opinion from Gemini or GPT.
---

# AGY Delegate

agy (Google Antigravity CLI) provides grounded web search with source citations plus access to Gemini 3.1/3.5 and GPT-OSS 120B — all from one subprocess call. For general web search prefer the `WebSearch` tool; reach for agy when you need real source URLs / a second model / info past Claude's cutoff.

⚠️ Security: Do not pipe content containing credentials, API keys, or PII.

## When to Use

**Web search — use agy for grounded/cited results (general search: prefer `WebSearch`):**
- "What is the current...", "latest version of...", "search for..."
- Factual claims that need source citations
- Pricing, changelogs, release notes, documentation

**On request:**
- Adversarial review of code or plans from an independent model (`--type review`)
- Large-file analysis via Gemini's extended context (`--type analysis`)
- "Use agy to...", "Ask Gemini...", "Check with GPT..."

## Usage

Bridge: `agy-bridge` (symlink in `~/.local/bin/` — run `/agy-setup` once after plugin install). Wraps `agy` with shell-safe prompt delivery (embedded in a 0600 per-run GEMINI.md — off argv/ps), type routing, and consistent exit-code handling. Set `AGY_SKIP_PERMISSIONS=1` to pass `--dangerously-skip-permissions` when required.

### Web search

```bash
echo "Claude API pricing June 2026" | agy-bridge --type search
```

### Code / task delegation

agy is sandbox-confined — it runs in an ephemeral workdir and cannot read the repo. Inline the needed file content into the piped prompt (as the `echo "$QUESTION" | agy-bridge` example shows):

```bash
echo "$QUESTION" | agy-bridge --type code
```

### Adversarial review

```bash
echo "$TASK" | agy-bridge --type review
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
| `search` | Gemini 3.6 Flash (High) | Fast, web-grounded |
| `code` | Gemini 3.1 Pro (High) | Extended context |
| `analysis` | Gemini 3.1 Pro (High) | Large file analysis |
| `review` | Gemini 3.1 Pro (High) | Second-pass critique, adversarial prompt framing |
| `implement` | Gemini 3.1 Pro (High) | File read+write, no shell exec — use when agy must write output files |

Omitting `--type` defaults to `code`. Override: `--model "Gemini 3.5 Flash (Low)"`.

Run `agy models` for current model names — values above match bridge defaults and may lag agy updates.

## Common Mistakes

| Symptom | Fix |
|---------|-----|
| Response lacks source URLs | Re-run with `--type search` (prefix prompts agy to call `search_web`) |
| Exit 124 | Timeout — simplify query or pass `--timeout 600` |
| Model name rejected | Exact string required — run `agy models` for current names |
| `agy: command not found` | Binary at `~/.local/bin/agy` — check PATH |
| `agy-bridge: command not found` | Symlink not created — run `/agy-setup` once. Until fixed: WebSearch for search tasks; native tools for code/review. |
| Calling `agy` directly | Use bridge — direct calls miss type routing and exit-code normalization |
| Empty response / hidden failure (exit 3) | Quota or auth — check error_class (quota=429/RESOURCE_EXHAUSTED → retry later; auth=UNAUTHENTICATED → re-auth agy; else empty_output → inspect stderr) |
| Reaching for agy on a simple web search | Prefer the WebSearch tool (cc-websearch when installed); use agy --type search only for grounded/cited results or a second model |

## Writing effective agy prompts

Print mode is one-shot — agy can't ask a clarifying question, so the prompt is the whole brief. For how to write one (data-first, negative-constraints-last, the 5-part brief), see the [`gemini-3-prompting`](../gemini-3-prompting/SKILL.md) skill.

## Reference

Provider details, auth, timeout guidance: `config/provider.md`
