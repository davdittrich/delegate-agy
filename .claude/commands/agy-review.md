---
command: agy-review
description: Adversarial critique via agy using Claude Opus 4.6 (Thinking) — independent second opinion on code, plans, or arguments
version: 1.0.2
category: ai-delegation
tags: [agy, review, critique, adversarial, opus, second-opinion]
---

Run an adversarial review via agy using Claude Opus 4.6 (Thinking) for an independent perspective.

Target: $ARGUMENTS

## Steps

1. If `$ARGUMENTS` is a file path: read it with the `Read` tool and pipe content to bridge.
   If `$ARGUMENTS` is inline content: pipe directly.

2. Run via `Bash` tool:

If `$ARGUMENTS` is a file path, use the `Read` tool first and pipe the file content:

```bash
# Inline content — arguments are the content to review
{
  echo "Critique this critically. Identify all flaws, risks, assumptions, and weaknesses:"
  echo ""
  echo "$ARGUMENTS"
} | agy-bridge --type review

# File path — Read the file first, then pipe it
{
  echo "Critique this critically. Identify all flaws, risks, assumptions, and weaknesses:"
  echo ""
  cat "$ARGUMENTS"
} | agy-bridge --type review
```

3. Return the critique verbatim. Surface every disagreement explicitly. Do not soften or filter findings.
