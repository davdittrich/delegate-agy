# AGY (Google Antigravity CLI) — Provider Configuration

## Provider Identity

- **Name**: Google Antigravity CLI
- **Command**: `agy`
- **Binary**: `~/.local/bin/agy`
- **Version**: 1.0.5 (Go-based, successor to Gemini CLI)
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

## Models (current)

| Model | Best For | Tier |
|-------|----------|------|
| Gemini 3.5 Flash (Low) | High-volume, cost-sensitive | Economy |
| Gemini 3.5 Flash (Medium) | General tasks | Standard |
| Gemini 3.5 Flash (High) | Web search, grounded tasks | Standard |
| Gemini 3.1 Pro (Low) | Code analysis | Pro |
| Gemini 3.1 Pro (High) | Complex reasoning, large context | Pro |
| Claude Sonnet 4.6 (Thinking) | Balanced reasoning | Premium |
| GPT-OSS 120B (Medium) | Alternative perspective | Premium |

## Strengths

1. **Web Search with Citations** — Native `search_web` tool with URL sources
2. **Extended Context** — Gemini 3.1 Pro handles large codebases
3. **MCP Integration** — lean-ctx MCP tools available inside agy sessions
4. **Multi-model Access** — Gemini, Claude, GPT-OSS in one CLI
5. **File Operations** — Native read/write/edit without Claude Code permission prompts

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
| `timeout: command not found` | GNU coreutils not installed | `brew install coreutils` (macOS) |
| Model name rejected | Exact string required | Run `agy models` for exact names |
| Empty output | Prompt too long for shell substitution | Write to file, use heredoc |

## Integration Notes

- agy uses `~/.gemini/antigravity-cli/settings.json` for global config
- Project-level instructions: `GEMINI.md` in project root
- MCP servers configured in `~/.gemini/antigravity-cli/mcp_config.json`
- Sessions stored in `~/.gemini/antigravity-cli/sessions/`
