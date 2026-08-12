A Claude Code plugin that routes tasks to [agy](https://github.com/google/agy) (Google Antigravity CLI), giving your Claude sessions access to Gemini and grounded web search with source citations. For general web search prefer your `WebSearch` tool; reach for agy when you need cited sources or a second model.

## Why

**Independent review.** A model reviewing its own output anchors on the reasoning it used to produce it. Gemini — a different company, different training — catches different things. Not because Claude can't review code, but because it tends to miss what it already decided was right.

**Current information with sources.** Claude's training has a cutoff. When you need today's release notes, a pricing page, or a changelog with actual URLs, you need live web search — not a model's best guess.

**A migration path off the Gemini CLI.** On June 18, 2026, [Google stops serving Gemini CLI requests](https://developers.googleblog.com/an-important-update-transitioning-gemini-cli-to-antigravity-cli/) for consumer tiers (AI Pro, Ultra, free Code Assist) and names the Antigravity CLI as the replacement. Frameworks like Claude Octopus and Metaswarm that shell out to a `gemini` binary break on that date. The included shim answers to the `gemini` name and routes the call through agy, so those tools keep working with no config changes.

## How it works

The plugin has two parts.

**`agy-bridge`** is a shell script that wraps `agy` with type routing, per-type tool restrictions, prompt sanitization, and consistent exit codes. Each `--type` gets its own `GEMINI.md` written to a temporary working directory; agy reads it via `--add-dir`; the GEMINI.md tool restrictions are prompt-advisory, while `--sandbox` is the API-level filesystem floor that confines agy to the granted directories. A `search` call can only use web tools. A `review` call can only read files. An `implement` call can read and write files but can't run shell commands. The prompt itself is embedded in the per-run 0600 `GEMINI.md` (the same file that carries the tool restrictions, auto-loaded via `--add-dir`); only a short static pointer is passed as the `--print` value, so the prompt still doesn't appear in `ps` or `/proc/cmdline`.

**`agy-delegate`** is a Claude Code skill that tells Claude when to reach for the bridge. It triggers on phrases like "search for", "latest", "ask Gemini", "second opinion". Claude picks the right `--type`, constructs the prompt, and pipes it through.

**A `SubagentStart` delegation hook** (opt-in, default off) injects a one-line advisory into allowlisted Task subagents so they know they can hand bulk, fan-out, or web-search work to `agy-bridge`. It is advisory-only and never changes routing; see [Configuration](#configuration) for the toggle, allowlist, and preconditions.

```bash
# How Claude calls it internally (you can run these directly too)
echo "dplyr 1.1.0 release notes" | agy-bridge --type search
echo "Review /path/to/api.py for correctness" | agy-bridge --type review
```

## Type routing

| `--type` | Model | What it can do |
|----------|-------|----------------|
| `search` | gemini-*-flash-high (latest) | Web search only; prepends `search_web` instruction automatically |
| `code` | gemini-*-pro-high (latest) | Read files; returns generated code as text, no writes |
| `analysis` | gemini-*-pro-high (latest) | Read files; handles large codebases |
| `review` | gemini-*-pro-high (latest) | Read files; adversarial framing |
| `implement` | gemini-*-pro-high (latest) | Read and write files; no shell execution |

The Model column is a rule, not a pin: the bridge resolves each `--type` to the **latest** matching Gemini id from your live `agy models` list at runtime, so it tracks agy version bumps with no plugin update. Omit `--type` to default to `code`. Override the model with `--model MODEL_ID` — run `agy models` for current CLI ids.

## Requirements

- [agy](https://github.com/google/agy) installed and authenticated via OAuth
- `python3` 3.6 or later (standard on all modern systems)
- `timeout` or `gtimeout` — Linux ships `timeout`; macOS needs `brew install coreutils`

## Installation

**1. Install and authenticate agy.**

Follow the agy project's installation instructions. After installing, run `agy` once interactively to complete the OAuth flow. Credentials land in `~/.gemini/antigravity-cli/`.

**2. Install dependencies.**

```bash
# macOS — timeout (coreutils); python3 ships with macOS
brew install coreutils

# Debian/Ubuntu — timeout is in coreutils, already present on most systems
# python3 is standard; install if missing:
sudo apt install python3
```

**3. Install this plugin.**

From GitHub:

```bash
claude plugin marketplace add https://github.com/davdittrich/delegate-agy
claude plugin install agy-delegate
```

Or from a local clone:

```bash
git clone https://github.com/davdittrich/delegate-agy
claude plugin install ./delegate-agy
```

**4. Run the installer.**

Run `/agy-setup` inside Claude Code. It does NOT install anything for you — it
prints the shadow notice plus one **validated, self-resolving** command you run
in your own terminal. That command resolves this plugin's `scripts/install.sh`
from `claude plugin list --json`, checks the resolved path matches
`*/agy-delegate/*/scripts/install.sh` and is a real file, then runs it.

```
/agy-setup
```

`scripts/install.sh` writes two hardened launcher wrappers to `~/.local/bin`:

- `agy-bridge` → execs `scripts/agy_bridge.sh`
- `gemini` → execs `scripts/gemini_shim.sh` (drop-in shim)

Each wrapper execs a **pinned absolute path recorded at install time** — it does
not glob the plugin cache and does not call `claude plugin list` per invocation
(both are attack/latency surfaces). If the plugin is later **updated or moved**,
the pinned path disappears and the wrapper **fails loud** with a "re-run the
install" message. **Re-run `/agy-setup`'s install command after any plugin
update** to repin the wrappers.

> **Shadow blast radius.** `~/.local/bin/gemini` shadows the real `gemini`
> command for every caller whose `PATH` has `~/.local/bin` first — your shell,
> Claude Octopus, Metaswarm. The installer prints this notice, backs up any
> pre-existing non-agy `gemini`/`agy-bridge` (to `<name>.bak-agy-<timestamp>`),
> and scans the full `$PATH` to warn which real `gemini` it shadows. Reverse
> everything with `scripts/uninstall.sh` (see below).

Opt-in flags (default off): `AGY_SETUP_REGISTER_TOKENSAVE=1` registers tokensave
as an agy MCP server; `AGY_SETUP_PATCH_ALIASES=1` applies the recursive-`gemini`
shell-rc alias patch (otherwise a dry-run advisory). `/agy-setup` prints the
exact variant commands.

**5. Verify.**

```bash
agy-bridge --types
```

Expected output:

```
type         model                          timeout
search       gemini-*-flash-high (latest)   300s
code         gemini-*-pro-high (latest)     600s
analysis     gemini-*-pro-high (latest)     600s
review       gemini-*-pro-high (latest)     600s
implement    gemini-*-pro-high (latest)     600s
```

**6. Uninstall.**

`scripts/uninstall.sh` removes the two wrappers only if they carry our signature
marker (restoring any shadowed original from its backup), and — with
`AGY_UNINSTALL_TOKENSAVE=1` — de-registers tokensave and removes the availability
hint. It is idempotent and refuses to run as root. `/agy-setup` prints the exact
command.

## Usage

The skill triggers automatically inside Claude sessions. For direct use:

`--add-dir` exposes everything under the granted directory to agy, not just the file(s) you care about — pass the narrowest sufficient path (a staging directory holding only the needed files keeps the grant auditable). `/` and `$HOME` (exact match) are refused with exit 2 unless `AGY_ALLOW_BROAD_GRANT=1` is set; subdirectories such as `$HOME/sub` are unaffected.

```bash
# Web search with citations
echo "Claude API pricing June 2026" | agy-bridge --type search

# Code review — grant read access to the directory holding the file
echo "Review scripts/deploy.sh for correctness" | agy-bridge --type review --add-dir scripts

# Inline prompt without stdin
agy-bridge --type search -- "latest numpy release"

# JSON output envelope
echo "query" | agy-bridge --type search --json

# Digest-only reply — biggest cost lever for bulk work: agy returns a compressed
# digest (findings + file:line) instead of a raw dump, keeping your context lean.
# Warns on stderr if the reply comes back dump-sized (tune with --digest-warn-chars).
echo "Map the auth flow end to end" | agy-bridge --type analysis --digest
```

JSON output:

```json
{
  "success": true,
  "model_used": "gemini-3.6-flash-high",
  "type": "search",
  "duration_seconds": 9,
  "response": "..."
}
```

## Configuration

### SubagentStart advisory hook

The plugin installs a `SubagentStart` hook (`hooks/agy-subagent-policy.sh`, wired via `hooks/hooks.json`) that can inject a one-line advisory into a matched subagent's context, pointing it at `agy-bridge` for bulk/fan-out/web-search work. **It is OFF by default.** With no environment variables set, the hook exits 0 and produces no output — a default install is completely inert.

| Variable | Purpose | Default |
|----------|---------|---------|
| `AGY_HOOKS_ENABLED` | Master toggle. Must be `1`, `true`, `on`, or `yes` (case-insensitive) to enable. Anything else, including unset, is disabled. | unset (disabled) |
| `AGY_HOOKS_AGENT_TYPES` | CSV allowlist of `agent_type` values that receive the advisory. | `general-purpose,Explore,metaswarm:researcher-agent,metaswarm:coder-agent,metaswarm:code-review-agent` |
| `AGY_HOOKS_DEBUG` | Set to `1` to log one line per skip/fire decision. | unset (off) |
| `AGY_HOOKS_DEBUG_FILE` | Path to append debug lines to. If unset while `AGY_HOOKS_DEBUG=1`, lines go to stderr. | unset (stderr) |

**Allowlist entry forms.** Each `AGY_HOOKS_AGENT_TYPES` entry is one of:

- **Namespaced** (`plugin:name`, e.g. `metaswarm:coder-agent`) — matches only that exact agent type string.
- **Bare** (`name`, e.g. `general-purpose`) — matches that exact agent type, AND wildcards the suffix after the last `:` of any namespaced type. A bare `coder-agent` entry would match `metaswarm:coder-agent`, `other:coder-agent`, and any other `*:coder-agent`.

**Discovering agent_type strings.** Set `AGY_HOOKS_DEBUG=1` (optionally `AGY_HOOKS_DEBUG_FILE=/path/to/log`), spawn the subagents you want to target, then read the debug log — it records the exact `agent_type` string for every skip/fire decision (`disabled`, `not allowlisted: '<agent_type>'`, `fired`, etc.). Add the observed strings to `AGY_HOOKS_AGENT_TYPES`.

**Preconditions** (all required before enabling):

- Run `/agy-setup` first, so `agy-bridge` exists on `PATH`.
- `python3` must be available — the hook uses it to parse the incoming payload and build its output; without it, the hook stays silent.
- The hook's `PATH` must include the `agy-bridge` directory (`~/.local/bin`); if `agy-bridge` isn't found on `PATH`, the hook stays silent.

**Warning.** Do not allowlist `*`, and do not indiscriminately allowlist built-in agent types. The advisory becomes system-prompt material for every subagent it matches — over-broad allowlisting can push agents toward a tool they don't need, or shouldn't use for a given task. Allowlist narrowly, to the specific agent types you've verified should see it.

**Interaction with metaswarm.** The hook is advisory-only and default-off; it does not change metaswarm's routing logic. Disabled (the default), there is zero interaction. Enabled, it only adds a delegation hint as `additionalContext` to matched subagents — metaswarm's own routing and gates are unaffected.

## Troubleshooting

| Error | Fix |
|-------|-----|
| `agy-bridge: command not found` | Run `/agy-setup` and its printed install command to create the wrapper |
| `agy-delegate moved or was updated` (wrapper fails loud) | The plugin was updated/moved — re-run `/agy-setup`'s install command to repin the wrappers |
| `agy: command not found` | Add `~/.local/bin` to `$PATH`: bash/zsh: `export PATH="$HOME/.local/bin:$PATH"` · fish: `fish_add_path ~/.local/bin` |
| Response missing source URLs | Use `--type search` |
| Model name rejected | Run `agy models`; exact string required |
| Exit code 124 | Timeout — simplify the query or pass `--timeout 600` |
| Exit code 3 (`agy returned empty output`) | agy exited 0 with no output — usually quota `RESOURCE_EXHAUSTED (429)`. The reason (full agy stderr) is surfaced; wait for quota reset or re-auth. Both `agy-bridge` and the `gemini` shim fail loud here rather than reporting empty success. |
| `ERROR: timeout/gtimeout not found in PATH` | `brew install coreutils` (macOS) |

## Security

Don't pipe credentials, API keys, or PII through the bridge. The prompt is written to a 0600 per-run `GEMINI.md` (not passed on the command line), so it stays out of process listings. Per-type tool restrictions are prompt-advisory (not API-enforced) instructing agy not to run shell commands; the API-level floor is `--sandbox`, which confines reads/writes to the granted `--add-dir` paths — a directory granted via `--add-dir` is exposed to the provider and is writable under `--type implement`. Model names are validated at startup against a list fetched from agy and cached for 60 minutes at `~/.cache/agy-bridge-models`. `--add-dir` refuses `/` and `$HOME` (exact resolved match) with exit 2 by default, overridable with `AGY_ALLOW_BROAD_GRANT=1`; this is a speed bump against the two broadest accidental grants, not a containment boundary — it does not stop, for example, a symlink under a granted subdirectory that points back at `$HOME`.

The installer (`scripts/install.sh`) and uninstaller run with `set -euo pipefail`, refuse to run as root, write only under `~/.local/bin`, `~` (rc backups), `~/.config/agy-delegate`, and `~/.gemini`, and never touch the repo. The generated launcher wrappers exec a **pinned absolute path** (no user-writable cache glob, no per-invocation `claude plugin list`) and fail loud if that path is missing.

## Drop-in gemini CLI replacement

`scripts/gemini_shim.sh` is a transparent `gemini` CLI shim backed by agy. `scripts/install.sh` installs it as a `gemini` wrapper on your PATH so that frameworks that call `gemini` automatically use agy instead — no configuration changes in those frameworks required.

### Frameworks supported

| Framework | How it calls gemini | Shim handles |
|-----------|--------------------|-|
| [Claude Octopus](https://github.com/nyldn/claude-octopus) | `gemini -m <model> -o text --approval-mode yolo` via stdin | ✓ flag mapping, model mapping, plain text output |
| [Metaswarm](https://github.com/dsifry/metaswarm) | `gemini --yolo --output-format json --model pro --include-directories <dir> <prompt>` | ✓ flag mapping, model mapping, JSON envelope with usageMetadata |

### Flag mapping

| gemini flag | agy equivalent |
|-------------|----------------|
| `-m` / `--model <name>` | `--model <name>` (with name mapping) |
| `-o text` / `--output-format text` | (default — no flag needed) |
| `--output-format json` | wraps output in `{"response":…,"usageMetadata":{…}}` envelope; token counts are `null` (agy does not expose usage) |
| `--approval-mode yolo` | `--dangerously-skip-permissions` |
| `--yolo` | `--dangerously-skip-permissions` |
| `--sandbox` | `--sandbox --add-dir "$PWD"` — API-level filesystem floor; read-only-ness is prompt-side via the shim policy |
| `--include-directories <dir>` | `--add-dir <dir>` |
| `--version` | `agy --version` |

### Model name mapping

| gemini name | agy model |
|-------------|-----------|
| `pro` (Metaswarm default) | `Gemini 3.1 Pro (High)` |
| `gemini-pro` / `gemini-3.1-pro` / `gemini-3.1-pro-high` | `Gemini 3.1 Pro (High)` |
| `gemini-3.1-pro-low` | `Gemini 3.1 Pro (Low)` |
| `flash` / `gemini-flash` | `Gemini 3.6 Flash (High)` |
| `gemini-3.6-flash` / `gemini-3.6-flash-high` | `Gemini 3.6 Flash (High)` |
| `gemini-3.6-flash-medium` | `Gemini 3.6 Flash (Medium)` |
| `gemini-3.6-flash-low` | `Gemini 3.6 Flash (Low)` |
| `gemini-3.5-flash` / `gemini-3.5-flash-high` | `Gemini 3.5 Flash (High)` |
| `gemini-3.5-flash-medium` | `Gemini 3.5 Flash (Medium)` |
| `gemini-3.5-flash-low` | `Gemini 3.5 Flash (Low)` |
| `gemini-2.5-pro` / `gemini-2.5-flash` (legacy) | `Gemini 3.1 Pro (High)` / `Gemini 3.6 Flash (High)` |
| any other string | pass through unchanged |

Mappings are in `config/model-map.json` — add aliases there without touching scripts.

### Manual installation

Prefer the installer (`/agy-setup`) — it writes a hardened, pinned wrapper with
non-clobber backup and a full-`$PATH` shadow scan. For a minimal manual setup:

```bash
# Symlink the shim as 'gemini' in a directory that precedes the real gemini on PATH
mkdir -p ~/.local/bin
ln -sf /path/to/delegate-agy/scripts/gemini_shim.sh ~/.local/bin/gemini
# Verify:
gemini --version   # should print agy version
```

A raw symlink has none of the installer's guards (no pinned-path fail-loud, no
backup, no shadow scan) — use `scripts/install.sh` for the hardened path.

### Octopus configuration

No changes needed. Octopus checks `command -v gemini`; the shim satisfies that check. To override the model:

```bash
export OCTOPUS_GEMINI_MODEL="gemini-3.6-flash"
```

### Metaswarm configuration

No changes needed. Metaswarm's gemini adapter checks `command -v gemini`; the shim satisfies the health check. `agy --version` output is returned as the version string.

> **Cost breakers do not gate agy usage.** Metaswarm's two USD circuit breakers — `per_task_usd` (default 2.00) and `per_session_usd` (default 20.00) — accumulate spend from the token counts that `extract_cost_gemini` reads out of `usageMetadata`. agy exposes no token usage, so the shim reports `promptTokenCount`/`candidatesTokenCount` as `null`, which metaswarm coerces to `0` (`// 0`). Every agy call therefore registers as $0 and neither breaker can trip, so runaway agy delegation is not cost-stopped. Bound agy usage another way — metaswarm's duration and attempt/iteration limits, or conservative task/subagent caps — and watch agy usage directly. Do not "fix" this by emitting fabricated token counts: that corrupts the metrics stream (see commit 73f931c).

## File layout

```
scripts/install.sh             — hardened installer (pinned wrappers, non-clobber, shadow scan)
scripts/uninstall.sh           — reverses install (signature-checked, idempotent)
scripts/agy_bridge.sh          — typed bridge (execed by the ~/.local/bin/agy-bridge wrapper)
scripts/gemini_shim.sh         — drop-in gemini CLI shim (execed by the ~/.local/bin/gemini wrapper)
skills/agy-delegate/SKILL.md   — skill definition
config/provider.md             — provider details, auth, timeout guidance
config/model-map.json          — gemini alias → agy model name mapping table
config/policies/               — GEMINI.md tool restriction policies (one file per mode)
  search.md                    — web search only
  code.md                      — read + grep, no writes
  review-analysis.md           — read + grep, no writes
  implement.md                 — read + write, no shell
  shim-yolo.md                 — gemini shim --yolo (read + write, no shell)
  shim-sandbox.md              — gemini shim --sandbox (read only)
  shim-default.md              — gemini shim default (read only)
```

## Changelog

### 1.5.1

- Bridge resolves each `--type` to the **latest** matching Gemini id from the live `agy models` list at runtime, replacing a pinned model name that drifted from agy's output. Fixes `agy-bridge --type search` (and all types) failing with `unknown --model` on agy 1.5.0.
- Empty resolution (no matching Gemini id in `agy models`) now exits 2 with a clear message.
- Gemini-only: dropped non-Gemini (Claude/GPT-OSS) entries from the model map, docs, and plugin manifests.
