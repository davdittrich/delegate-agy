---
command: agy
description: Delegate any task to agy (Google Antigravity CLI) — auto-selects model by task type
version: 1.0.2
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

3. Run the bridge via `Bash` tool. Use the `Read` tool first to load any target files (agy only sees what you pipe):

```bash
# search — no file context needed
agy-bridge --type search -- "$ARGUMENTS"

# code or analysis — Read the target file, then pipe its content
{ echo "$ARGUMENTS"; echo "---"; cat "$FILE_PATH"; } | agy-bridge --type code

# review — pipe inline content or a Read-loaded file
{ echo "Critique this:"; echo "---"; cat "$FILE_PATH"; } | agy-bridge --type review
```

4. Return result. For search: preserve source URLs verbatim. For code suggestions: apply with `Edit` tool and report what changed.
