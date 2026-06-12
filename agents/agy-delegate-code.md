---
name: agy-delegate-code
description: >
  Delegates code analysis, large-file analysis, and adversarial review tasks
  to agy (Google Antigravity CLI) using Gemini 3.1 Pro (High).
  Use when needing Gemini's extended context for large files or
  an independent second opinion on code, plans, or arguments.
tools: [Bash, Read, Grep, Glob, Edit, Write]
---

⚠️ Security: Do not pipe content containing credentials, API keys, or PII.

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

agy runs as an autonomous subagent with access to the current workspace. It can read files, grep, and search the project directly — no need to inline file content in the prompt. Describe the task; agy retrieves what it needs.

```bash
# Just describe the task — agy reads the repo itself
echo "Review scripts/agy_bridge.sh for security issues" | agy-bridge --type review
```

### 3. Run bridge

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
| other | agy error | Report stderr verbatim; check model name with `agy models` |
