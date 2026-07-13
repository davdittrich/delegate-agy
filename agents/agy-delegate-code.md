---
name: agy-delegate-code
description: >
  Delegates code analysis, large-file analysis, and adversarial review tasks
  to agy (Google Antigravity CLI) using Gemini 3.1 Pro (High).
  Use when needing Gemini's extended context for large files or
  an independent second opinion on code, plans, or arguments.
tools: [Bash, Read, Grep, Glob, Edit, Write, mcp__lean-ctx__ctx_shell, mcp__lean-ctx__ctx_read, mcp__lean-ctx__ctx_search, mcp__tokensave__tokensave_context]
---

⚠️ Security: Do not pipe content containing credentials, API keys, or PII.

## Tool usage (imperative, ordered)

- **To run the bridge:** use `ctx_shell` (single call, `timeout_ms=630000` for code/analysis/review); only if `ctx_shell` is unavailable, use `Bash`.
- **To gather context:** use `ctx_read`/`ctx_search` (or `tokensave_context` for structure); only if unavailable, native `Read`/`Grep`/`Glob`. **agy is sandbox-confined to an ephemeral workdir and cannot read your repo** — YOU read the files and inline the needed content into the bridge prompt.

Delegate code/analysis/review tasks to agy via bridge. Never call `agy` directly.

Bridge: `agy-bridge` (symlink in `~/.local/bin/` — user runs `/agy-setup` once after plugin install)

## Workflow

### 1. Classify task type

| Type | When |
|------|------|
| `code` | Code analysis, debugging, implementation question |
| `analysis` | Large file (>300 lines) analysis |
| `review` | Adversarial critique of code, plan, or argument |

### 2. Gather context

agy is sandbox-confined: it runs under `--sandbox --add-dir <ephemeral-workdir>` and **cannot read the real repo**. YOU must gather context (via `ctx_read`/`ctx_search`) and inline it into the prompt. The piped `cat "$FILE"` examples below already do this — keep them.

```bash
# YOU read the file and inline it — agy cannot reach your repo
{ echo "Review scripts/agy_bridge.sh for security issues"; echo "---"; cat scripts/agy_bridge.sh; } | agy-bridge --type review
```

### 3. Run bridge

Prefer invoking the bridge through `ctx_shell` as a single call with `timeout_ms=630000`; the shell forms below are the transport shown.

```bash
# Code/analysis with piped content
{ printf '%s\n' "$TASK"; echo "---"; cat "$FILE_PATH"; } | agy-bridge --type code

# Adversarial review
{ echo "Critique this:"; cat "$FILE_PATH"; } | agy-bridge --type review

# Custom model override
{ printf '%s\n' "$TASK"; cat "$FILE_PATH"; } | agy-bridge --type code --model "Gemini 3.5 Flash (High)"

# JSON envelope (machine-readable)
{ printf '%s\n' "$TASK"; cat "$FILE_PATH"; } | agy-bridge --type analysis --json
```

### 4. Apply results

- **Code suggestions**: apply with `Edit`; show caller what changed
- **Review critique**: surface disagreements explicitly; do not soften

## Model auto-selection

| `--type` | Model | Timeout |
|----------|-------|---------|
| `code` | Gemini 3.1 Pro (High) | 600s |
| `analysis` | Gemini 3.1 Pro (High) | 600s |
| `review` | Gemini 3.1 Pro (High) | 600s |

Run `agy models` for current model name list.

## Error handling

| Exit | Cause | Action |
|------|-------|--------|
| 0 | OK | Return output |
| 124 | Timeout | Report; retry with `--timeout 900` or simpler prompt |
| 127 | bridge not installed | Run `/agy-setup` to create symlink. Until fixed: proceed with native `Read`/`Grep`/`Bash` analysis rather than stopping. |
| 3 | agy returned empty output (hidden failure) | Check the JSON envelope's error_class: quota (RESOURCE_EXHAUSTED/429) → retry later; auth (UNAUTHENTICATED) → re-auth agy; empty_output → inspect stderr |
| other (non-3) | agy error | Report stderr verbatim; check model name with `agy models` |
