---
command: agy-search
description: Web search via agy (Google Antigravity CLI) — agy grounded web search with source citations (for general search prefer the WebSearch tool)
version: 1.0.2
category: ai-delegation
tags: [agy, search, web, gemini, citations, grounded]
---

Run a grounded agy search (real source URLs); for general web search prefer the `WebSearch` tool.

Query: $ARGUMENTS

Run via `ctx_shell` (or `Bash` if `ctx_shell` is unavailable):

```bash
agy-bridge --type search -- "$ARGUMENTS"
```

Return the full response including all source URLs verbatim. Do not paraphrase citations.
