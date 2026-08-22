# Technology Stack

**Analysis Date:** 2026-08-18

## Languages

**Primary:**
- Bash — all 9 executable scripts under `scripts/` and `tests/`, plus `hooks/*.sh`. `set -euo pipefail` at the top of every script (`scripts/agy_bridge.sh:8`, `scripts/gemini_shim.sh:18`, `scripts/install.sh:32`).

**Secondary:**
- Python 3 — invoked only as inline `python3 -c "..."` / heredoc snippets from within bash, never as standalone `.py` files. No script in this repo is itself Python.
- Markdown — plugin commands (`.claude/commands/*.md`), agent prompts (`agents/*.md`), skill docs (`skills/agy-delegate/SKILL.md`), and policy files (`config/policies/*.md`) that double as `GEMINI.md` context injected into `agy` runs.
- JSON — `config/model-map.json` (alias → model class map) and the plugin manifests.

There is no compiled language, no transpilation step, and no package manifest of any kind (no `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`). Confirmed by directory listing of the worktree root — only shell, markdown, and JSON files exist outside `.git`/`.serena`.

## Runtime

**Environment:**
- Bash. Scripts use indexed arrays (`ADD_DIRS+=(...)` at `scripts/agy_bridge.sh:73`), `[[ ]]` conditionals, and `IFS=':' read -r -a` (`scripts/install.sh:168`) — all compatible with bash 3.2+, but the project's own comments describe "bash 4+" style guarantees are not required; no associative arrays (`declare -A`), no `mapfile`/`readarray`, no `${var,,}` case-conversion appear anywhere in `scripts/*.sh` or `hooks/*.sh` (grep confirmed empty). Treat bash 3.2+ (macOS default) as the practical floor; nothing forces bash 4.
- Python 3 — required only where scripts shell out to it (see below). No `venv`, no `requirements.txt`; relies on Python's stdlib only (`json`, `sys`, `os`, `re`, `hashlib`, `tempfile`, `time`).

**Package Manager:**
- None. No lockfile of any kind exists.

## Frameworks

**Core:**
- None — pure POSIX-ish shell scripting invoking one external binary (`agy`).

**Testing:**
- Hand-rolled bash test runners: `tests/run-tests.sh` and `tests/hooks/run-hook-tests.sh`. No BATS, no shunit2, no pytest. `tests/fake-agy.sh` is a stub `agy` binary used to test `scripts/agy_bridge.sh` / `scripts/gemini_shim.sh` without invoking the real, hanging CLI.

**Build/Dev:**
- None — nothing is compiled or bundled. `scripts/install.sh` is the only "build-like" step, and it only writes wrapper scripts to `~/.local/bin`.

## Key Dependencies

**Critical (must be present at runtime):**
- `agy` — Google Antigravity CLI binary, expected on PATH at `~/.local/bin/agy`. Checked via `command -v agy` in every entry script (`scripts/agy_bridge.sh:11`, `scripts/gemini_shim.sh:20`, `scripts/install.sh` wrapper template at `scripts/install.sh:118`).
- `timeout` (GNU coreutils) or `gtimeout` (macOS via `brew install coreutils`) — every `agy` invocation is wrapped in `timeout -k N T ... agy ...` because `agy` ignores SIGTERM (`scripts/agy_bridge.sh:139-143`, `:340-342`; `scripts/gemini_shim.sh:36-40`, `:88-89`, `:189-190`, `:316-317`). Absence is a hard error in `agy_bridge.sh` (`scripts/agy_bridge.sh:15-21`) but only a soft degrade in `gemini_shim.sh` (`TIMEOUT_BIN=""` at `scripts/gemini_shim.sh:29`, falls back to running `agy` unbounded — see Concerns).
- `python3` — **load-bearing, not incidental**, in two distinct roles:
  1. JSON envelope construction/parsing — `agy_bridge.sh`'s `--json` output and error paths (`scripts/agy_bridge.sh:358-427`), and `gemini_shim.sh`'s `-o json` envelope (`scripts/gemini_shim.sh:363-388`). Comment at `scripts/gemini_shim.sh:376-377` explains jq was deliberately dropped in favor of `python3 -c` because a limited/shimmed `jq` on PATH could silently misbehave.
  2. Model-alias resolution — `gemini_shim.sh`'s `map_model()` reads `config/model-map.json` via `python3 -c "import json..."` (`scripts/gemini_shim.sh:122-125`) to translate a gemini-CLI alias (e.g. `"pro"`) to a model class (e.g. `"pro-high"`), which is then resolved against the *live* `agy models` list.
  3. `install.sh` uses `python3` for: MCP-config detection/mutation (`scripts/install.sh:244-254`, `:268-304`), the rc-alias patch (`scripts/install.sh:218-224`), and writing the MCP-availability hint file (`scripts/install.sh:332-338`).
  - Where `python3` is *not* load-bearing: `agy_bridge.sh`'s MCP-server autodetect block guards its whole block with `if command -v python3 >/dev/null 2>&1` (`scripts/agy_bridge.sh:282`) and degrades to `_MCP_LEANCTX=0; _MCP_TOKENSAVE=0` if absent — a soft feature, not a hard dependency, for that one code path.
  - `install.sh`'s tokensave registration also fail-opens without python3 (`scripts/install.sh:259-261`), but the rc-alias patch (`scripts/install.sh:218`) assumes python3 exists once inside its `AGY_SETUP_PATCH_ALIASES=1` branch — no guard there, so that specific opt-in path would hard-fail (unhandled `python3: command not found` under `set -e`) if python3 is missing.
- coreutils: `cut` (`scripts/agy_bridge.sh:174`, `scripts/gemini_shim.sh:108`), `sed` (`scripts/agy_bridge.sh:162`, `scripts/install.sh:106`, `:137-138`), `grep` (pervasive, e.g. `scripts/agy_bridge.sh:179`), `sort -V` (`scripts/agy_bridge.sh:188-190`, `scripts/gemini_shim.sh:127`) for "newest wins" version-string sort of model ids, `mktemp` (`scripts/agy_bridge.sh:142`, `:207`; `scripts/gemini_shim.sh:237`; `scripts/install.sh:108`), `find ... -mmin` (`scripts/agy_bridge.sh:138`, `:284`; `scripts/gemini_shim.sh:82`) for the 60-minute cache-freshness checks.
- `readlink -f` — used for self-locating the script's own real path (`scripts/agy_bridge.sh:217`, `scripts/gemini_shim.sh:121`, `:247`, `scripts/install.sh:46`), so scripts must run on a platform where `readlink -f` exists (GNU coreutils; macOS needs `coreutils`/`gtimeout` parity or the `greadlink`/`readlink` in newer macOS 12.3+).

**Infrastructure:**
- None beyond the above — no database, no message queue, no server process. Everything is a synchronous CLI invocation.

## Configuration

**Environment:**
- No `.env` file mechanism. Behavior is tuned entirely by exported environment variables read directly by scripts, e.g. `AGY_MODELS_TIMEOUT` (`scripts/agy_bridge.sh:25`, `scripts/gemini_shim.sh:68`), `AGY_ALLOW_BROAD_GRANT` (`scripts/agy_bridge.sh:68`), `AGY_SKIP_PERMISSIONS` (`scripts/agy_bridge.sh:336`), `GEMINI_SHIM_STDIN_TIMEOUT` / `GEMINI_SHIM_TIMEOUT` (`scripts/gemini_shim.sh:31`, `:41`), `AGY_PLUGIN_DIR`, `AGY_SETUP_REGISTER_TOKENSAVE`, `AGY_SETUP_PATCH_ALIASES` (`scripts/install.sh:43`, `:26-27`), `CLAUDE_CONFIG_DIR` (`scripts/install.sh:135`).
- A JSON config hint at `~/.config/agy-delegate/config.json` (written by `install.sh`, read by `agy_bridge.sh`) carries `{"lean_ctx":bool,"tokensave":bool}` (`scripts/agy_bridge.sh:117`, `:288-289`; `scripts/install.sh:234`, `:332-338`).

**Build:**
- No build config files exist (no `tsconfig.json`, `webpack.config.js`, etc.) — none apply to this stack.

## Plugin Packaging Surface (this project's real "manifest" format)

Since there is no `package.json`, the actual packaging/distribution surface is Claude Code's plugin format:

- `.claude-plugin/plugin.json` — the plugin manifest: `name: agy-delegate`, `version: 1.6.2`, lists 5 commands under `.claude/commands/*.md` and 1 skill directory (`./skills/agy-delegate`).
- `.claude-plugin/marketplace.json` — marketplace entry pointing `source: "./"` back at this same repo, `category: productivity`.
- `.claude/commands/*.md` — five slash commands (`agy.md`, `agy-search.md`, `agy-review.md`, `agy-setup.md`, `agy-uninstall.md`), each with YAML frontmatter (`command`, `description`, `version`, `category`, `tags`) followed by the prompt body, e.g. `.claude/commands/agy.md:1-6`.
- `agents/*.md` — two subagent definitions (`agy-delegate-code.md`, `agy-delegate-search.md`).
- `skills/agy-delegate/SKILL.md` and `skills/gemini-3-prompting/SKILL.md` — skill docs bundled with the plugin.
- `hooks/hooks.json` — registers `hooks/agy-subagent-policy.sh` on the `SubagentStart` lifecycle event, referencing the script via `${CLAUDE_PLUGIN_ROOT}`.
- Versioning is manual and duplicated: `.claude-plugin/plugin.json`'s top-level `version` (`1.6.2`) is the plugin version; individual command frontmatter carries its own independent `version` (e.g. `1.0.2` in `.claude/commands/agy.md:4`) that is not kept in lockstep with the plugin version.

## Platform Requirements

**Development:**
- Any POSIX-like system with bash, GNU coreutils (or `gtimeout`/`greadlink` equivalents on macOS via `coreutils`), python3, and `agy` itself installed and authenticated.
- Tests run via `tests/run-tests.sh` / `tests/hooks/run-hook-tests.sh` against `tests/fake-agy.sh`, so the real `agy` binary is not required to run the test suite.

**Production:**
- Not a deployed service. "Production" is the end user's local machine / CI runner where `~/.local/bin/agy-bridge` and `~/.local/bin/gemini` wrapper scripts are installed by `scripts/install.sh` and then invoked ad hoc by Claude Code commands, subagents, or third-party tools (Claude Octopus, Metaswarm) that shell out to `gemini`.

---

*Stack analysis: 2026-08-18*
