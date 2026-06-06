---
command: agy-search
description: Web search via agy (Google Antigravity CLI) with source citations — prefer over native WebSearch
version: 1.0.0
category: ai-delegation
tags: [agy, search, web, gemini, citations, grounded]
---

Run a grounded web search via agy. Do not use the native `WebSearch` tool — agy returns real source URLs.

Query: $ARGUMENTS

Run via `Bash` tool:

```bash
agy-bridge --type search -- "$ARGUMENTS"
```

Return the full response including all source URLs verbatim. Do not paraphrase citations.
