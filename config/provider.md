# AGY (Google Antigravity CLI) — Provider Configuration

## Provider Identity

- **Name**: Google Antigravity CLI
- **Command**: `agy`
- **Binary**: `~/.local/bin/agy`
- **Version**: requires agy >= 1.1.1 (Go-based, successor to Gemini CLI; `--print` takes the prompt as its value)
- **Config dir**: `~/.gemini/antigravity-cli/`
- **MCP config**: `~/.gemini/antigravity-cli/mcp_config.json`

## Authentication

Authentication is handled by the Antigravity CLI itself. Run `agy` interactively once to complete OAuth flow. Credentials stored in `~/.gemini/antigravity-cli/`.

## CLI Interface (for automation)

```bash
# Non-interactive (primary bridge mode)
agy --print "prompt text" --model "model name" --sandbox

# Continue last conversation
agy --continue --print "follow-up"

# Resume specific session
agy --conversation <session-id> --print "follow-up"
```

The agy-bridge / `gemini` shim do NOT pass the prompt as the `--print` value or via stdin — they write it into a per-run 0600 `GEMINI.md` (`--- TASK:` section) that agy auto-loads via `--add-dir`, and pass only a static `--print` pointer. This keeps large or sensitive prompts off `argv`/`ps`.

## Models (current)

| Model | Best For | Tier |
|-------|----------|------|
| Gemini 3.5 Flash (Low) | High-volume, cost-sensitive | Economy |
| Gemini 3.5 Flash (Medium) | General tasks | Standard |
| Gemini 3.5 Flash (High) | Web search, grounded tasks | Standard |
| Gemini 3.1 Pro (Low) | Code analysis | Pro |
| Gemini 3.1 Pro (High) | Complex reasoning, large context | Pro |

## Strengths

1. **Web Search with Citations** — Native `search_web` tool with URL sources
2. **Extended Context** — Gemini 3.1 Pro handles large codebases
3. **MCP Integration** — lean-ctx MCP tools (`ctx_read`/`ctx_search`/… — autodetected) are available inside agy sessions
4. **Multi-model Access** — Gemini in one CLI
5. **File Operations** — agy’s file operations run under `--sandbox`, confined to the `--add-dir` granted directories (the per-run workdir on the bridge, plus any caller-supplied `--add-dir` paths)


## Enforcement model

agy's tool policy is enforced at two distinct layers — one prompt-advisory, one API-level:

- **Prompt-advisory (GEMINI.md).** The `PERMITTED`/`FORBIDDEN` lists plus the allowlist catch-all in the per-run `GEMINI.md` are *prompt-advisory*: agy is instructed to refuse non-permitted tools, but the policy file is not itself API-enforced. It relies on the model honoring the instruction.
- **API-level filesystem floor (`--sandbox`).** `--sandbox` is the real API-level floor — it confines every read/write to the `--add-dir` granted directories. The **bridge always** passes `--sandbox`; the **shim read-only modes** pass it (with `--add-dir "$PWD"`); **shim-yolo does NOT** (deliberately unrestricted — it runs `--dangerously-skip-permissions`).
- **Allowlist catch-all.** The catch-all forbids every `ctx_*`/`mcp__*` tool and the `ctx_call` gateway — relevant once lean-ctx is registered for agy.

**Tool-preference stanza (autodetect).** For MCP-permitted types (`code`/`review`/`analysis`/`implement`) the bridge appends a tool-preference stanza biasing agy toward `ctx_read`/`ctx_search` when lean-ctx is registered for agy. Availability is read from the shared config-hint `~/.config/agy-delegate/config.json` (`{"lean_ctx":bool}`, written by `/agy-setup`; live-probed if absent).

**Web search precedence.** General web search prefers the Claude-side `WebSearch` tool (cc-websearch-served when installed); use agy only for grounded citations or a second model.
## Timeout Guidance

| Query Type | Recommended Timeout |
|------------|-------------------|
| Web search | 300s (5 min) |
| Code analysis (<500 lines) | 300s |
| Code analysis (>500 lines) | 600s |
| Adversarial review | 600s |

## Error Patterns

| Error | Cause | Fix |
|-------|-------|-----|
| `ERROR: timeout/gtimeout not found in PATH` | `timeout` or `gtimeout` not in PATH | `brew install coreutils` (macOS) |
| Model name rejected | Exact string required | Run `agy models` for exact names |
| Empty output | Prompt too long for shell substitution | Write to file, use heredoc |

## Integration Notes

- agy uses `~/.gemini/antigravity-cli/settings.json` for global config
- Project-level instructions: `GEMINI.md` in project root
- MCP servers configured in `~/.gemini/antigravity-cli/mcp_config.json`
- Sessions stored in `~/.gemini/antigravity-cli/sessions/`
