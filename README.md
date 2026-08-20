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

The Model column is a rule, not a pin: the bridge resolves each `--type` to the **latest** matching Gemini id from your live `agy models` list at runtime, so it tracks agy version bumps with no plugin update. Omit `--type` to default to `code`. Override the model with `--model MODEL_ID` — verified against `agy` 1.1.13 (captured 2026-08-20): `--model` accepts both a bare id (e.g. `gemini-3.1-pro-high`) and a display name (e.g. `Gemini 3.7 Flash (High)`); run `agy models` for the current list of both forms.

## Requirements

- [agy](https://github.com/google/agy) installed and authenticated via OAuth
- `python3` 3.6 or later (standard on all modern systems)

Recommended, not required: `timeout` or `gtimeout` (coreutils). Every agy call is bounded with or without one — see [Bounding without `timeout`/`gtimeout`](#bounding-without-timeoutgtimeout). What coreutils buys is the *kind* of kill: `timeout` isolates its child in its own process group and signals the group, so it reaps whatever agy forked, while the built-in bash watchdog does the same through job control and degrades to killing the direct process only where job control cannot isolate the child. Linux ships `timeout`; on macOS `brew install coreutils` provides `gtimeout`.

## Installation

**1. Install and authenticate agy.**

Follow the agy project's installation instructions. After installing, run `agy` once interactively to complete the OAuth flow. Credentials land in `~/.gemini/antigravity-cli/`.

**2. Install dependencies.**

```bash
# macOS — python3 ships with macOS; coreutils is recommended, not required
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
prints the shadow notice plus two commands to copy-paste: a `grep` command
that reads the plugin's install path straight from
`~/.claude/plugins/installed_plugins.json` (so you read the path yourself
before anything runs), and the `scripts/install.sh` command to run against
it. If that registry file is missing, it falls back to a command that
resolves the path from `claude plugin list --json` instead and validates the
result before running it, since that path comes from command output rather
than your own eyes.

```
/agy-setup
```

`scripts/install.sh` writes two hardened launcher wrappers to `~/.local/bin`:

- `agy-bridge` → execs `scripts/agy_bridge.sh`
- `gemini` → execs `scripts/gemini_shim.sh` (drop-in shim)

Each wrapper execs a **pinned absolute path recorded at install time** — the
**exec target** is never a plugin-cache glob and never comes from `claude
plugin list` (both are attack/latency surfaces); it is only ever that
install-time literal. If the plugin is later **moved**, the pinned
path disappears and the wrapper **fails loud** with a "re-run the install"
message and a non-zero exit. If instead the plugin is **updated** and Claude
Code's cache leaves the old version directory in place alongside the new one
(observed behavior — the stale copy is not deleted), the pinned path still
resolves, so the wrapper compares its pinned version against the version Claude
Code reports as installed and **refuses to run**: it exits `127` naming both
versions and — when the active version is numeric and the constructed
installer path exists on disk — the exact command to repin (otherwise a
generic pointer to `/agy-setup`), rather than silently executing the
stale copy. **Re-run `/agy-setup`'s install command after any plugin update**
to repin the wrappers either way.

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
| `agy-delegate moved or was updated` (wrapper fails loud) | The plugin was moved, or updated in a way that removed the pinned version dir — re-run `/agy-setup`'s install command to repin the wrappers |
| `ERROR: agy-delegate ... is installed, but this launcher is pinned to ...` | The plugin was updated but the wrapper is still pinned to the old version; it refuses to run the stale copy (exit `127`) until you repin — run the command it prints, or re-run `/agy-setup`'s install command |
| `agy: command not found` | Add `~/.local/bin` to `$PATH`: bash/zsh: `export PATH="$HOME/.local/bin:$PATH"` · fish: `fish_add_path ~/.local/bin` |
| Response missing source URLs | Use `--type search` |
| Model name rejected | agy rejects an unrecognized id or display name with `Error: invalid model selection (--model "NAME" --effort ""): model NAME is not recognized as a known model or custom model in settings`, followed by an `Available models:` list. Run `agy models` for the current ids and display names. |
| Exit code 2 (`agy model list contains no 'gemini-' ids; agy may be unauthenticated`) | The fetched (or cached) model list has no `gemini-`-prefixed ids — agy is degraded or unauthenticated, not a bad `--type`. Run `agy models` directly to see its raw output, and re-authenticate if needed. |
| Exit code 124 | Timeout — simplify the query or pass `--timeout 600` |
| Exit code 137 (`agy killed (signal 9) after Ns, before its Ms bound -- possible OOM or external kill`, followed by `: <agy's stderr>` when agy wrote to stderr — nothing is appended when it didn't) | An external kill (OOM killer, `kill -9`, container preemption) landed before the bound elapsed, so it isn't the entry point's own `-k` escalation. `agy-bridge` and the `gemini` shim word this identically. Check the host/container for memory pressure — raising the timeout won't help. |
| Exit code 3 (`agy returned empty output`) | agy exited 0 with no output — usually quota `RESOURCE_EXHAUSTED (429)`. The reason (full agy stderr) is surfaced; wait for quota reset or re-auth. Both `agy-bridge` and the `gemini` shim fail loud here rather than reporting empty success. |
| `WARNING: timeout/gtimeout not found -- bounding agy with the bash watchdog fallback; install coreutils for process-group kill` | Not a failure, and not fatal to either entry point: the call is still bounded, by the bash watchdog. `brew install coreutils` (macOS) upgrades the kill from the direct process to its whole process group, so anything agy forked cannot outlive the bound either. |

### Running the tests

`bash tests/run-tests.sh` runs this project's actual regression suite — the mocked, fast, CI-safe entry point — against `tests/fake-agy.sh`, a stand-in `agy`. No real agy, no network calls, no spend. See [Contract check](#contract-check) below for the separate real-`agy`, quota-spending operator tool.

### Contract check

`tests/contract-check.sh` is a repo-only operator tool — run `bash tests/contract-check.sh` from a clone. It is not part of the unit suite and not a release gate: it interrogates the real `agy` binary rather than the fake, so an agy outage never blocks a tag. Running it spends real quota — up to 3 billed delegations per full run — with the actual count printed in the ledger's closing summary line.

Its exit codes are disjoint from the bridge's codes in the table above — a check verdict is never a bridge exit:

| Exit | Meaning |
|------|---------|
| `0` | Every assumption in the ledger reports `verified` |
| `10` | At least one assumption reports `unverified`, none `contradicted` |
| `11` | At least one assumption reports `contradicted` (outranks `10`) |

## Security

Don't pipe credentials, API keys, or PII through the bridge. The prompt is written to a 0600 per-run `GEMINI.md` (not passed on the command line), so it stays out of process listings. Per-type tool restrictions are prompt-advisory (not API-enforced) instructing agy not to run shell commands; the API-level floor is `--sandbox`, which confines reads/writes to the granted `--add-dir` paths — a directory granted via `--add-dir` is exposed to the provider and is writable under `--type implement`. Model names are validated at startup against a list fetched from agy and cached for 60 minutes at `~/.cache/agy-bridge-models`. `--add-dir` refuses `/` and `$HOME` (exact resolved match) with exit 2 by default, overridable with `AGY_ALLOW_BROAD_GRANT=1`; this is a speed bump against the two broadest accidental grants, not a containment boundary — it does not stop, for example, a symlink under a granted subdirectory that points back at `$HOME`.

The installer (`scripts/install.sh`) and uninstaller run with `set -euo pipefail`, refuse to run as root, write only under `~/.local/bin`, `~` (rc backups), `~/.config/agy-delegate`, and `~/.gemini`, and never touch the repo. The generated launcher wrappers exec a **pinned absolute path**: that exec target is never a user-writable cache glob and never a per-invocation `claude plugin list`. Wrappers fail loud if that path is missing. They also compare their pinned version against the version Claude Code records in `~/.claude/plugins/installed_plugins.json` (honouring `CLAUDE_CONFIG_DIR`) and exit `127` rather than run a superseded copy; an absent or unparseable registry is silence, so dev installs keep working. That read is **comparison-only**: the registry contributes a version string and nothing else — the exec target is never derived from it, the registry key is matched exactly so a lookalike plugin from another marketplace cannot match, and the repin command printed is constructed from install-time literals, never from a registry-supplied path.

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

### Environment variables

| Variable | Default | Notes |
|----------|---------|-------|
| `GEMINI_SHIM_STDIN_TIMEOUT` | `30` | Seconds to wait for stdin before failing (exit 2). Must match `^[1-9][0-9]*$`; anything else is rejected at startup. The read is bounded whether or not a `timeout`/`gtimeout` binary is on PATH (see below). |
| `GEMINI_SHIM_TIMEOUT` | `600` | Seconds to wait for the agy delegation call, escalated to `SIGKILL` 5s after `SIGTERM` (agy ignores `SIGTERM`). Exceeding it exits 124. Must match `^[1-9][0-9]*$`; anything else is rejected at startup. The call is bounded whether or not a `timeout`/`gtimeout` binary is on PATH (see below). |
| `AGY_MODELS_TIMEOUT` | `20` | Seconds to wait for the `agy models` fetch that resolves model names, escalated to `SIGKILL` after 3s. Shared with `agy_bridge.sh`. Anything not matching `^[1-9][0-9]*$` — including `0`, which coreutils `timeout` treats as "no timeout" — is **corrected to 20 rather than rejected**: an optional knob must not stop a `gemini` that shadows the system binary. Exceeding it is not fatal; the shim falls back to the cache and then to passing the name through. The fetch is bounded whether or not a `timeout`/`gtimeout` binary is on PATH (see below). |

#### Bounding without `timeout`/`gtimeout`

Both entry points do the same thing here, and that sameness is the decision rather than a coincidence. `agy-bridge` and the `gemini` shim each route **every** agy call through one shared `run_bounded` helper, so no call from either script is left without a bound on any host. Earlier releases diverged: the bridge refused to start at all without a coreutils binary, while the shim ran the delegation call with no bound. Those were two ways of paying the same price — the shim's caller got the hang this plugin exists to prevent, and the bridge's caller got that same broken `gemini` moved one step earlier, at startup, which is worse for a binary that shadows the system `gemini` for every PATH caller. Bash can enforce a bound with no external binary, so neither price has to be paid, and neither is.

What a missing coreutils changes is *which* kill you get, not whether you get one:

| | `timeout`/`gtimeout` on PATH | no bounding binary |
|-|------------------------------|--------------------|
| `agy-bridge` | coreutils enforces the bound | warns once at startup, then bounds with the bash watchdog |
| `gemini` shim | coreutils enforces the bound | warns once at startup, then bounds with the bash watchdog |

Coreutils `timeout` isolates its child in a new process group and signals the *group*, so it reaps whatever agy forked. The bash watchdog enforces the same seconds, the same `SIGTERM`-then-`SIGKILL` escalation and the same exit `124`, and reaps the child's process group through job control — but where job control cannot give the child a group of its own it degrades to killing the direct process only, so a descendant agy forked can survive. That single difference is what installing coreutils buys.

Each script prints this once per run, before any agy call, when it finds no bounding binary:

```
WARNING: timeout/gtimeout not found -- bounding agy with the bash watchdog fallback; install coreutils for process-group kill
```

and this when the watchdog is the mechanism that killed a call:

```
NOTICE: bash watchdog fallback killed the bounded call after its bound (exit 124)
```

### Model name mapping

Model names are resolved against the **live `agy models` list**, never against a
hardcoded version. `config/model-map.json` maps a gemini name to a model *class*;
the shim then picks the newest live id matching `gemini-<version>-<class>` — the
same `sort -V | tail -1` rule `agy_bridge.sh` uses for `--type`. A new agy model
generation is picked up automatically, with no edit to this repo.

| gemini name | agy class | resolves to |
|-------------|-----------|-------------|
| `pro` (Metaswarm default) | `pro-high` | newest `gemini-*-pro-high` |
| `gemini-pro` / `gemini-3.1-pro` / `gemini-3.1-pro-high` | `pro-high` | newest `gemini-*-pro-high` |
| `gemini-3.1-pro-low` | `pro-low` | newest `gemini-*-pro-low` |
| `flash` / `gemini-flash` | `flash-high` | newest `gemini-*-flash-high` |
| `gemini-3.6-flash` / `gemini-3.6-flash-high` | `flash-high` | newest `gemini-*-flash-high` |
| `gemini-3.6-flash-medium` / `gemini-3.5-flash-medium` | `flash-medium` | newest `gemini-*-flash-medium` |
| `gemini-3.6-flash-low` / `gemini-3.5-flash-low` | `flash-low` | newest `gemini-*-flash-low` |
| `gemini-3.5-flash` / `gemini-3.5-flash-high` | `flash-high` | newest `gemini-*-flash-high` |
| `gemini-2.5-pro` / `gemini-2.5-flash` (legacy) | `pro-high` / `flash-high` | newest of that class |
| a name that is a live agy id | — | itself, unchanged (an explicit pin is never upgraded) |
| any other string | — | pass through unchanged, with a warning on stderr |

Aliases are in `config/model-map.json` — add them there without touching scripts.
Values must be classes, never ids or display names: a pinned name goes stale the
day agy ships a new model.

The live list is cached for 60 minutes in `~/.cache/agy-bridge-models`, shared
with `agy_bridge.sh`, and fetched only when a model is actually requested
(`--help`, `--version` and model-less calls never fetch). The fetch is bounded by
`AGY_MODELS_TIMEOUT` (see the table above). If agy is unreachable and no cache
exists — or `HOME` is unset, or agy returns a list with no `gemini-` ids — names
pass through untouched rather than failing, and no warning is emitted: this shim
shadows the system `gemini` for every caller on `PATH`.

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
config/model-map.json          — gemini alias → agy model class (resolved live, never pinned)
config/policies/               — GEMINI.md tool restriction policies (one file per mode)
  search.md                    — web search only
  code.md                      — read + grep, no writes
  review-analysis.md           — read + grep, no writes
  implement.md                 — read + write, no shell
  shim-yolo.md                 — gemini shim --yolo (read + write, no shell)
  shim-sandbox.md              — gemini shim --sandbox (read only)
  shim-default.md              — gemini shim default (read only)
tests/contract-check.sh        — real-agy contract check (repo-only, spends quota, see Contract check above)
tests/run-tests.sh             — mocked regression suite, this project's actual unit tests (see Running the tests, above)
tests/fake-agy.sh              — mock agy the regression suite drives; the real agy is never reached by this suite
tests/fixtures/                — captured real-agy output the fake and CC05 are pinned against
```

## Changelog

### 1.6.2

- `agy-bridge` no longer hangs when agy does. Both agy invocations now escalate to `SIGKILL`: the model fetch 3s after `$AGY_MODELS_TIMEOUT` (default 20s), the delegation call 5s after `$TIMEOUT`. agy ignores `SIGTERM`, so plain `timeout` sent the signal and then blocked forever — the delegation call outlived even its own 600s bound. Both entry points enforce every bound through one shared helper, using coreutils `timeout -k` where it exists and a bash watchdog where it does not, so a host without coreutils no longer costs the bridge its startup or the shim its bound. A failed fetch now falls back to the stale cached list with a warning instead of hard-failing while a usable list sits on disk.
- A failed `agy models` surfaces agy's own stderr instead of discarding it. That text is the only diagnostic when the real fault is auth or the network.
- A model list carrying no `gemini-` ids reports a degraded/unauthenticated agy rather than blaming the `--type` the user picked.
- An agy killed by something other than its own timeout — an OOM killer, an external `kill -9`, a container preemption — is now named as such rather than surfacing as a bare `agy exit 137`. A 137 arriving before the bound elapsed cannot be the bridge's own `-k` escalation, so it is reported distinctly and the 137 exit status is preserved.
- Both pinned launchers (`agy-bridge` and the `gemini` shim) refuse to run (exit 127) when Claude Code's install registry reports a different active version, naming both versions; each prints the exact repin command when the active version is numeric and the constructed installer path exists on disk, otherwise a generic pointer to `/agy-setup`. Previously a superseded pin only warned on stderr and kept running the stale copy, so a shipped fix could sit installed-but-never-executed. Replaces the newer-sibling directory scan.
- `/agy-setup` leads with a readable two-step install (print the path, run it) instead of the 9-line resolve-and-validate pipeline; the pipeline remains as a fallback where no registry file exists.

### 1.6.1

- Fixed every bridge delegation failing on current agy: `agy models` now emits `id<TAB>display name` per line, so the bridge's `$`-anchored matchers found nothing — auto-select died with `no gemini model for --type`, and explicit `--model` died with `unknown --model`. The fetched list (and any stale cache written in the tabbed form) is now reduced to its id column before matching; the anchored patterns and the unknown-model rejection are unchanged.
- `tests/fake-agy.sh` emits the real tab-separated `agy models` format, so the suite reproduces this class of drift instead of passing against a shape agy no longer produces.

### 1.6.0

- `agy-bridge` gains repeatable `--add-dir PATH` passthrough, granting the delegated model read access to caller-chosen directories without inlining file bodies into the prompt.
- `--add-dir` refuses the two broadest grants — `/` and `$HOME` (exact resolved match) — with exit 2, overridable via `AGY_ALLOW_BROAD_GRANT=1`; a trailing-slash bypass on `$HOME` and unguarded `cd` option/CDPATH injection on `-`-leading directory names are both closed.
- `gemini_shim.sh`'s stdin prompt read is now timeout-bounded (`GEMINI_SHIM_STDIN_TIMEOUT`, default 30s, validated against `^[1-9][0-9]*$`), mirroring the bridge and preventing a never-EOF pipe from hanging every agent session that shells out to `gemini`.
- Both wrappers reject whitespace-only prompts with exit 2 before search-prefix/digest augmentation, instead of silently forwarding an effectively empty prompt to agy and burning a paid call.
- Fixed an inherited-stdin hang: both wrappers now redirect agy's stdin from `/dev/null` since the prompt is already consumed into `GEMINI.md` before agy runs.
- Corrected the README/SKILL.md `--sandbox` scope claim: it is the API-level floor bounding reads/writes to granted `--add-dir` paths, not a read-only/no-shell-exec guarantee — that expectation is prompt-advisory only and does not hold under `--type implement`.

### 1.5.1

- Bridge resolves each `--type` to the **latest** matching Gemini id from the live `agy models` list at runtime, replacing a pinned model name that drifted from agy's output. Fixes `agy-bridge --type search` (and all types) failing with `unknown --model` on agy 1.5.0.
- Empty resolution (no matching Gemini id in `agy models`) now exits 2 with a clear message.
- Gemini-only: dropped non-Gemini (Claude/GPT-OSS) entries from the model map, docs, and plugin manifests.
