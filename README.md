# delegate-agy

A Claude Code plugin that routes tasks to [agy](https://github.com/google/agy) (Google Antigravity CLI), giving your Claude sessions access to Gemini 3.1/3.5, GPT-OSS 120B, and grounded web search with source citations.

## The problem

Three things Claude Code alone can't do well:

**Independent review.** The same model that wrote code can't audit it credibly. You need a second model with no memory of the original prompt.

**Current information with sources.** Training data has a cutoff. When you need today's release notes, a pricing page, or a changelog with actual URLs, you need live web search — not a model's best guess.

**Huge files.** When a codebase overflows Claude's context, analysis stops. Gemini 3.1 Pro's extended context handles files that would otherwise require chunking and stitching.

## How it works

The plugin has two parts.

**`agy-bridge`** is a shell script that wraps `agy` with type routing, per-type tool restrictions, prompt sanitization, and consistent exit codes. Each `--type` gets its own `GEMINI.md` written to a temp working directory; agy reads it via `--add-dir` and treats those restrictions as binding. A `search` call can only use web tools. A `review` call can only read files. An `implement` call can read and write files but can't run shell commands. Prompts travel through stdin, not command-line arguments, so they don't appear in `ps` or `/proc/cmdline`.

**`agy-delegate`** is a Claude Code skill that tells Claude when to reach for the bridge. It triggers on phrases like "search for", "latest", "ask Gemini", "second opinion". Claude picks the right `--type`, constructs the prompt, and pipes it through — you don't have to intervene.

```bash
# How Claude calls it internally (you can run these directly too)
echo "dplyr 1.1.0 release notes" | agy-bridge --type search
echo "Review /path/to/api.py for correctness" | agy-bridge --type review
```

## Types

| `--type` | Model | What it can do |
|----------|-------|----------------|
| `search` | Gemini 3.5 Flash (High) | Web search only; `search_web` prefix added automatically |
| `code` | Gemini 3.1 Pro (High) | Read files; return generated code as text, no writes |
| `analysis` | Gemini 3.1 Pro (High) | Read files; handles large codebases |
| `review` | Gemini 3.1 Pro (High) | Read files; adversarial framing |
| `implement` | Gemini 3.1 Pro (High) | Read and write files; no shell execution |

Omit `--type` to default to `code`. Override the model with `--model "Gemini 3.5 Flash (Low)"`. Run `agy models` for current names — the table above may lag agy releases.

## Requirements

- [agy](https://github.com/google/agy) installed and authenticated via OAuth
- `jq` 1.6 or later (required for `--json` output mode only)
- `timeout` or `gtimeout` — Linux ships `timeout`; macOS needs `brew install coreutils`

## Installation

**1. Install and authenticate agy.**

Follow the agy project's installation instructions. After installing, run `agy` once interactively to complete the OAuth flow. Credentials land in `~/.gemini/antigravity-cli/`.

**2. Install dependencies.**

```bash
# macOS
brew install jq coreutils

# Debian/Ubuntu
sudo apt install jq
# timeout is included in coreutils, already present on most Linux systems
```

**3. Install this plugin.**

Directly from GitHub:

```bash
claude plugin marketplace add https://github.com/davdittrich/delegate-agy
claude plugin install agy-delegate
```

Or from a local clone:

```bash
git clone https://github.com/davdittrich/delegate-agy
claude plugin install ./delegate-agy
```

**4. Create the bridge symlink.**

Run once after install — creates `~/.local/bin/agy-bridge`:

```
/agy-setup
```

**5. Verify.**

```bash
agy-bridge --types
```

Expected:

```
type         model                          timeout
search       Gemini 3.5 Flash (High)        300s
code         Gemini 3.1 Pro (High)          600s
analysis     Gemini 3.1 Pro (High)          600s
review       Gemini 3.1 Pro (High)          600s
implement    Gemini 3.1 Pro (High)          600s
```

## Usage

The skill triggers automatically inside Claude sessions. For direct use:

```bash
# Web search with citations
echo "Claude API pricing June 2026" | agy-bridge --type search

# Code review — agy reads the file itself
echo "Review scripts/deploy.sh for correctness" | agy-bridge --type review

# Inline prompt, no stdin
agy-bridge --type search -- "latest numpy release"

# JSON output envelope
echo "query" | agy-bridge --type search --json
```

JSON output:

```json
{
  "success": true,
  "model_used": "Gemini 3.5 Flash (High)",
  "type": "search",
  "duration_seconds": 9,
  "response": "..."
}
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `agy-bridge: command not found` | Run `/agy-setup` to create the symlink |
| `agy: command not found` | Add `~/.local/bin` to `$PATH` |
| Response missing source URLs | Use `--type search` |
| Model name rejected | Run `agy models`; exact string required |
| Exit code 124 | Timeout — simplify query or pass `--timeout 600` |
| `ERROR: timeout/gtimeout not found in PATH` | `brew install coreutils` (macOS) |

## Security

Don't pipe credentials, API keys, or PII through the bridge. Prompts use stdin to stay out of process listings. Per-type tool restrictions prevent agy from running shell commands in any mode. Model names are validated at startup against a list fetched from agy and cached for 60 minutes at `~/.cache/agy-bridge-models`.

## Drop-in gemini CLI replacement

`scripts/gemini_shim.sh` is a transparent `gemini` CLI shim backed by agy. Install it as
`gemini` on your PATH so that frameworks that call `gemini` automatically use agy instead —
no config changes in those frameworks required.

### Frameworks supported

| Framework | How it calls gemini | Shim handles |
|-----------|---------------------|--------------|
| [Claude Octopus](https://github.com/nyldn/claude-octopus) | `gemini -m <model> -o text --approval-mode yolo` via stdin | ✓ flag mapping, model mapping, plain text output |
| [Metaswarm](https://github.com/dsifry/metaswarm) | `gemini --yolo --output-format json --model pro --include-directories <dir> <prompt>` | ✓ flag mapping, model mapping, JSON envelope with usageMetadata |

### Flag translation

| gemini flag | agy equivalent |
|-------------|----------------|
| `-m` / `--model <name>` | `--model <name>` (with name mapping) |
| `-o text` / `--output-format text` | (default — no flag needed) |
| `--output-format json` | wraps text output in `{"response":…,"usageMetadata":{…}}` envelope |
| `--approval-mode yolo` | `--dangerously-skip-permissions` |
| `--yolo` | `--dangerously-skip-permissions` |
| `--sandbox` | (omitted — read-only is enforced via GEMINI.md tool restrictions) |
| `--include-directories <dir>` | `--add-dir <dir>` |
| `--version` | `agy --version` |

### Model name mapping

| gemini name | agy name |
|-------------|----------|
| `pro` (metaswarm default) | `Gemini 3.1 Pro (High)` |
| `flash` | `Gemini 3.5 Flash (High)` |
| `gemini-2.5-pro*` / `gemini-3.1-pro*` | `Gemini 3.1 Pro (High)` |
| `gemini-2.5-flash*` / `gemini-3.5-flash*` | `Gemini 3.5 Flash (High)` |
| already an agy model name | pass through |

### Install as drop-in

```bash
# Symlink shim as 'gemini' in a directory that precedes the real gemini on PATH
mkdir -p ~/.local/bin
ln -sf /path/to/delegate-agy/scripts/gemini_shim.sh ~/.local/bin/gemini
# Verify:
gemini --version   # should print agy version
```

Or use `/agy-setup` (sets up both `agy-bridge` and `gemini` symlinks):

```bash
/agy-setup
```

### Octopus configuration

No changes needed. Octopus detects `command -v gemini`; the shim satisfies that check.
To override the model, set `OCTOPUS_GEMINI_MODEL` as usual:

```bash
export OCTOPUS_GEMINI_MODEL="gemini-2.5-flash"
```

### Metaswarm configuration

No changes needed. Metaswarm's `gemini.sh` adapter calls `command -v gemini`; the shim
satisfies the health check. `agy --version` output is returned as the version string.

## Files

```
scripts/agy_bridge.sh          — typed bridge (symlinked to ~/.local/bin/agy-bridge)
scripts/gemini_shim.sh         — drop-in gemini CLI shim (symlinked to ~/.local/bin/gemini)
skills/agy-delegate/SKILL.md   — skill definition
config/provider.md             — provider details, auth, timeout guidance
```
