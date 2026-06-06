---
command: agy
description: Delegate any task to agy (Google Antigravity CLI) — auto-selects model by task type
version: 1.0.0
category: ai-delegation
tags: [agy, antigravity, gemini, gpt, delegate, multi-model]
---

Delegate the following task to agy via `agy-bridge` (installed to `~/.local/bin/` by plugin).

Task: $ARGUMENTS

## Steps

1. Classify task type from the request:
   - `search` — web lookup, current info, citations needed
   - `code` — code analysis, debugging, implementation
   - `analysis` — large file analysis (>300 lines)
   - `review` — adversarial critique of code, plan, or argument

2. For `code`, `analysis`, `review`: read relevant files with the `Read` tool first. agy only sees what you pipe to it.

3. Run the bridge via `Bash` tool:

```bash
# search (no file context needed)
agy-bridge --type search -- "$ARGUMENTS"

# code/analysis/review (pipe file content)
{ echo "$ARGUMENTS"; echo "---"; cat <file>; } | agy-bridge --type <type>
```

4. Return result. For search: preserve source URLs verbatim. For code suggestions: apply with `Edit` tool and report what changed.
