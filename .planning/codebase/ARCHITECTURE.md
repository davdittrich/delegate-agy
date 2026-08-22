<!-- refreshed: 2026-08-18 -->
# Architecture

**Analysis Date:** 2026-08-18

**Source mapped:** `.worktrees/agy-1.6.2` (branch `fix/agy-bridge-resilience`, 12 commits ahead of `master`). This is a pure-bash Claude Code plugin (`agy-delegate`, `.claude-plugin/plugin.json:2-3`) — no package manifest, no runtime other than bash + coreutils + python3 (for JSON only, never for logic). 32 tracked files.

## System Overview

```text
┌───────────────────────────────────────────────────────────────────────────┐
│                    Claude Code (skills, agents, hooks, users)             │
├───────────────────────────┬───────────────────┬───────────────────────────┤
│  Explicit delegation       │  Drop-in shim       │  Advisory injection      │
│  `agy-bridge --type X`     │  `gemini ...`       │  SubagentStart hook      │
│  `scripts/agy_bridge.sh`   │  `scripts/          │  `hooks/agy-             │
│                             │  gemini_shim.sh`    │  subagent-policy.sh`     │
└──────────────┬──────────────┴─────────┬───────────┴──────────┬────────────┘
               │                        │                      │
               │  writes GEMINI.md      │  writes GEMINI.md    │ emits fixed
               │  into a mktemp WORK_DIR│  into a mktemp        │ advisory JSON
               │  (policy + embedded    │  WORK_DIR (policy +   │ on stdout;
               │  prompt), invokes      │  embedded prompt),    │ no agy call
               │  `timeout -k`          │  invokes `timeout -k` │
               ▼                        ▼                      │
┌───────────────────────────────────────────────────────────────────────────┐
│                          `agy` (Antigravity CLI, external)                │
│  invoked as: agy --print <pointer> --sandbox --model <id> --add-dir ...   │
└──────────────────────────┬────────────────────────────────────────────────┘
                            │  `agy models` (id<TAB>display)
                            ▼
┌───────────────────────────────────────────────────────────────────────────┐
│         Shared 60-minute model-list cache: ~/.cache/agy-bridge-models      │
│         (read + written by BOTH agy_bridge.sh and gemini_shim.sh)          │
└───────────────────────────────────────────────────────────────────────────┘

Installer (one-time, run by the user, never by agy_bridge.sh/gemini_shim.sh):
scripts/install.sh generates two pinned launchers in ~/.local/bin:
  agy-bridge -> exec bash <plugin>/scripts/agy_bridge.sh "$@"
  gemini     -> exec bash <plugin>/scripts/gemini_shim.sh "$@"  (SHADOWS real gemini)
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| Bridge | Explicit `--type` delegation API for skills/agents/commands | `scripts/agy_bridge.sh` |
| Gemini shim | Drop-in `gemini` CLI replacement, flag-translates to `agy` | `scripts/gemini_shim.sh` |
| Subagent policy hook | Injects advisory context on `SubagentStart` when allowlisted | `hooks/agy-subagent-policy.sh` |
| Hook library | Shared guard/parsing functions, sourced-only | `hooks/agy-hooks-lib.sh` |
| Installer | Generates pinned wrapper launchers, MCP autodetect, alias patch | `scripts/install.sh` |
| Uninstaller | Removes wrappers, restores backups | `scripts/uninstall.sh` |
| Type policies | Per-`--type` tool restriction text embedded as `GEMINI.md` | `config/policies/{code,implement,review-analysis,search}.md` |
| Shim policies | Per-mode (`yolo`/`sandbox`/`default`) tool restriction text | `config/policies/shim-{yolo,sandbox,default}.md` |
| Model alias map | gemini-CLI alias → agy model **class** (never a pinned version) | `config/model-map.json` |
| Commands | User-facing slash commands wrapping the bridge | `.claude/commands/agy*.md` |
| Agents | Delegate-capable subagent definitions | `agents/agy-delegate-{code,search}.md` |
| Skills | Prompting guidance for agy delegation and Gemini 3 prompting | `skills/agy-delegate/SKILL.md`, `skills/gemini-3-prompting/SKILL.md` |
| Fake CLI | Test double standing in for the real `agy` binary | `tests/fake-agy.sh` |

## Pattern Overview

**Overall:** Three thin bash wrappers around one external, slow, misbehaving CLI (`agy`), unified by a shared cache file and a shared "prompt-via-file, not argv" convention. No framework, no OOP — every "abstraction" is a bash function or a static config file.

**Key Characteristics:**
- No process is long-running; every invocation is a single bounded `agy` subprocess.
- State that must survive across invocations lives in exactly two files under `~/.cache/`.
- Behavior differences between the two entry points (bridge vs. shim) are deliberate near-duplication, not shared library code — see Architectural Constraints.

## Layers

**Entry-point layer:**
- Purpose: parse CLI-style flags, resolve model, resolve policy, assemble the `agy` invocation.
- Location: `scripts/agy_bridge.sh`, `scripts/gemini_shim.sh`
- Depends on: `config/policies/*.md`, `config/model-map.json`, `agy` binary on PATH, shared cache files.
- Used by: skills (`skills/agy-delegate/SKILL.md`), agents (`agents/agy-delegate-*.md`), commands (`.claude/commands/agy*.md`), and — via the shim — any PATH caller of `gemini` (Claude Octopus, Metaswarm, interactive shells).

**Policy layer:**
- Purpose: declare per-mode tool allow/deny lists as plain markdown, consumed as `agy`'s auto-loaded `GEMINI.md`.
- Location: `config/policies/`
- Contains: prompt-level advisories only — not API-enforced (`config/policies/code.md:1` "prompt-level advisory, not API-enforced").
- Depends on: nothing (static text).
- Used by: both entry points' `case` statements selecting a policy file (`scripts/agy_bridge.sh:218-223`, `scripts/gemini_shim.sh:247-254`).

**Installer layer:**
- Purpose: one-shot, user-run setup that pins an absolute exec path into two generated launcher scripts.
- Location: `scripts/install.sh`, `scripts/uninstall.sh`
- Depends on: nothing at runtime after install (the generated wrapper only checks its own pinned path and, optionally, Claude Code's `installed_plugins.json` for staleness comparison).
- Used by: the user directly (`bash scripts/install.sh`), never invoked by the bridge/shim themselves.

**Hook layer:**
- Purpose: advisory-only `SubagentStart` context injection, fully independent of the bridge/shim runtime path (does not call `agy`).
- Location: `hooks/agy-subagent-policy.sh`, `hooks/agy-hooks-lib.sh`, `hooks/hooks.json`
- Depends on: `agy-hooks-lib.sh` (sourced, include-guarded, no side effects on source per `hooks/agy-hooks-lib.sh:1-14`).

## Data Flow

### Primary delegation path (`agy_bridge.sh`)

1. Parse `--type/--model/--timeout/--add-dir/...` flags (`scripts/agy_bridge.sh:44-126`).
2. Validate `--type` against a fixed alnum-stripped allowlist (`scripts/agy_bridge.sh:129-133`).
3. Refresh (if >60 min stale) or reuse `~/.cache/agy-bridge-models` via `timeout -k 3 "$AGY_MODELS_TIMEOUT" agy models` (`scripts/agy_bridge.sh:138-174`).
4. Auto-select a model by regex against the live list (`^gemini-[0-9.]+-(pro|flash)-high$`, newest via `sort -V | tail -1`) or validate an explicit `--model` (`scripts/agy_bridge.sh:186-196`).
5. Create `WORK_DIR=$(mktemp -d)`, copy the type's policy file into `$WORK_DIR/GEMINI.md`, then append the prompt under a `TASK:` heading and `chmod 600` it (`scripts/agy_bridge.sh:206-276`).
6. Optionally append an MCP tool-preference stanza, gated on a 60-min-cached `python3` probe of `~/.config/agy-delegate/config.json` or the live `~/.gemini/antigravity-cli/mcp_config.json` (`scripts/agy_bridge.sh:281-320`).
7. Run `agy --print <static pointer> --sandbox --model <id> [--add-dir ...] --add-dir "$WORK_DIR"` from inside `$WORK_DIR`, wrapped in `timeout -k 5 "$TIMEOUT"` (`scripts/agy_bridge.sh:328-346`).
8. Classify the exit code (external SIGKILL before the timeout bound vs. timeout-triggered SIGKILL vs. nonzero vs. empty-stdout-as-hidden-failure) and emit either raw stdout or a `--json` envelope (`scripts/agy_bridge.sh:351-430`).

### Shadow path (`gemini_shim.sh`, installed as `~/.local/bin/gemini`)

1. Translate gemini-CLI flags (`-m/--model`, `-o/--output-format`, `--approval-mode yolo`, `--yolo`, `--sandbox`, `--include-directories`, `-p`) to internal state (`scripts/gemini_shim.sh:145-226`).
2. If a model was requested, lazily load the **same** `~/.cache/agy-bridge-models` cache (`scripts/gemini_shim.sh:74,80-110`) and resolve it via `map_model()`: live-id-passthrough first, then `config/model-map.json` alias→class lookup re-resolved against the live list, else unresolved passthrough with a warning (`scripts/gemini_shim.sh:112-143`).
3. Select one of `shim-yolo.md` / `shim-sandbox.md` / `shim-default.md` as `GEMINI.md` based on yolo/sandbox flags (`scripts/gemini_shim.sh:247-256`).
4. Embed prompt into `GEMINI.md` exactly as the bridge does (`scripts/gemini_shim.sh:277-283`).
5. Run `agy --print <pointer> --add-dir "$WORK_DIR" [--sandbox --add-dir "$PWD" --add-dir "$WORK_DIR" | --dangerously-skip-permissions] [--model <id>] [--add-dir <included dirs>...]`, bounded by `timeout -k 5 "$SHIM_TIMEOUT"` (`scripts/gemini_shim.sh:286-329`).
6. Same error classification as the bridge; on success, either prints raw text or wraps it in a gemini-CLI-shaped `{"response":...,"usageMetadata":{...null...},"model":"agy",...}` JSON envelope for `-o json` callers (`scripts/gemini_shim.sh:375-388`).

**State Management:** All cross-invocation state is two flat cache files under `~/.cache/`: `agy-bridge-models` (model list, 60-min TTL, shared by both scripts) and `agy-bridge-mcp` (MCP-availability booleans, 60-min TTL, bridge-only). No database, no lockfile, no in-memory daemon.

## Key Abstractions

**Policy-as-GEMINI.md:**
- Purpose: encode per-invocation tool restrictions as plain text `agy` auto-loads from its CWD, instead of any API-level sandbox parameter.
- Examples: `config/policies/code.md`, `config/policies/search.md`, `config/policies/shim-yolo.md`
- Pattern: copy static file → append `\n---\nTASK:\n<prompt>` → `chmod 600` → run `agy` with CWD = that directory. Both entry points implement this identically but independently (see Architectural Constraints).

**Timeout-with-escalation:**
- Purpose: bound every `agy` subprocess call, because `agy` ignores SIGTERM (documented empirically at `scripts/agy_bridge.sh:139-140`, `scripts/gemini_shim.sh:36-40,84-87`).
- Examples: every one of the 5 `agy` call sites (bridge: models fetch `agy_bridge.sh:143`, main call `agy_bridge.sh:342`; shim: models fetch `gemini_shim.sh:89`, `--version` `gemini_shim.sh:190`, main call `gemini_shim.sh:317`).
- Pattern: `timeout -k <grace> <bound> agy ...`; exit 124 = own timeout fired, exit 137 landing *before* the bound elapsed = external kill (OOM/cgroup), distinguished by comparing `DURATION` to the configured bound (`scripts/agy_bridge.sh:352-366`, `scripts/gemini_shim.sh:332-339`).

## Entry Points

**`scripts/agy_bridge.sh`:**
- Location: `scripts/agy_bridge.sh`
- Triggers: invoked directly as `agy-bridge` (installed wrapper) by skills/agents/commands, or via `ctx_shell`/`Bash` per the hook advisory text (`hooks/agy-subagent-policy.sh:87`).
- Responsibilities: full delegation lifecycle described above.

**`scripts/gemini_shim.sh`:**
- Location: `scripts/gemini_shim.sh`
- Triggers: any PATH lookup of `gemini` once installed at `~/.local/bin/gemini` (installer places `~/.local/bin` ahead of any real `gemini` — see `scripts/install.sh:174-189` full-PATH shadow scan).
- Responsibilities: gemini-CLI-compatible flag translation + same `agy` delegation lifecycle.

**`hooks/agy-subagent-policy.sh`:**
- Location: `hooks/agy-subagent-policy.sh`, registered in `hooks/hooks.json:3-14` for the `SubagentStart` event.
- Triggers: every subagent spawn; six sequential guards (enabled flag, python3 usable, non-empty stdin, valid JSON, agent_type allowlisted, `agy-bridge` on PATH) gate whether it emits anything (`hooks/agy-subagent-policy.sh:30-78`).
- Responsibilities: emit a **fixed, non-interpolated** advisory string as `additionalContext` JSON; never echoes the incoming payload; never calls `agy`.

## Architectural Constraints

- **Threading:** None — strictly single-process, single-threaded bash; concurrency only arises from independent invocations racing on the shared cache files (see below).
- **Global state:** Two shared cache files under `~/.cache/`: `agy-bridge-models` (`agy_bridge.sh:136`, `gemini_shim.sh:74`) and `agy-bridge-mcp` (`agy_bridge.sh:283`, bridge-only). Both scripts write via `mktemp`-then-`mv` for atomicity (`agy_bridge.sh:146-147`, `gemini_shim.sh:99-100`) but there is no locking between the two processes racing a refresh — the `mv` is atomic per-write, so the failure mode is at most a wasted duplicate `agy models` call, not corruption.
- **Deliberate non-DRY duplication:** `gemini_shim.sh` re-implements bridge model-cache logic (`load_models()`, `AGY_MODELS_TIMEOUT` validation, timeout-escalation pattern) rather than sourcing a shared lib, because it installs as `~/.local/bin/gemini` and shadows the system `gemini` for every PATH caller — a missing/broken shared helper would break `gemini` box-wide (`scripts/gemini_shim.sh:58-61`). This is explicitly documented as an accepted tradeoff, not an oversight.
- **Prompt delivery is file-based, not argv-based, on purpose:** both entry points write the prompt into `$WORK_DIR/GEMINI.md` rather than passing it as an `agy` argument, to dodge `ARG_MAX` and keep `ps`/`/proc`/`cmdline` free of prompt content (`scripts/agy_bridge.sh:270-276`, `scripts/gemini_shim.sh:277-283`). Only a static pointer string (`AGY_POINTER`) is ever passed via `--print`.
- **agy ignores SIGTERM:** every `agy` invocation in this codebase MUST use `timeout -k <grace> <bound>`, never plain `timeout`. New call sites that omit `-k` will hang past their nominal timeout.

## Anti-Patterns

### Trusting `agy`'s exit code 0 as success

**What happens:** `agy` can exit 0 with completely empty stdout on quota exhaustion (`RESOURCE_EXHAUSTED`/429) or silent backend/lock errors.
**Why it's wrong:** A naive caller treating exit-0 as success would silently propagate an empty response as if the delegation succeeded.
**Do this instead:** Both entry points explicitly check `[[ ! -s "$STDOUT_FILE" ]]` after a 0 exit and fail loud with exit 3, classifying the reason from stderr into `quota`/`auth`/`empty_output` (`scripts/agy_bridge.sh:386-409`, `scripts/gemini_shim.sh:348-371`).

### Passing large prompts as CLI arguments

**What happens:** A prompt embedded directly in `argv` risks `ARG_MAX` truncation and leaks full prompt content into `ps`/`/proc`.
**Why it's wrong:** Silent truncation on long prompts, and a process-list-visible information leak.
**Do this instead:** Write the prompt into a `chmod 600` `GEMINI.md` under a per-invocation `mktemp -d` directory and pass only a fixed pointer string via `--print` (`scripts/agy_bridge.sh:270-276`).

## Error Handling

**Strategy:** Fail loud, classify by exit code and by output shape, never retry internally.

**Patterns:**
- `set -euo pipefail` at the top of every executable script (`scripts/agy_bridge.sh:8`, `scripts/gemini_shim.sh:18`, `scripts/install.sh:32`); hooks use `set -uo pipefail` (no `-e`) so a guard-driven `exit 0` path is explicit rather than incidental (`hooks/agy-subagent-policy.sh:16`).
- Exit code taxonomy is consistent across both entry points: `2` = usage/validation error, `3` = hidden failure (empty stdout despite exit 0), `124` = own timeout, `137` before the bound = external kill, `137`/other at/after the bound = timeout-driven SIGKILL.
- Every temp `WORK_DIR` is cleaned via `trap 'rm -rf "$WORK_DIR"' EXIT HUP INT QUIT TERM` (`scripts/agy_bridge.sh:211`, `scripts/gemini_shim.sh:241`).

## Cross-Cutting Concerns

**Logging:** `--verbose` writes a one-line metadata summary (`type=... model=... timeout=...`) to stderr or `--log-file`; never logs prompt content (`scripts/agy_bridge.sh:260-268`). Hook debug logging is opt-in via `AGY_HOOKS_DEBUG=1`, written to `AGY_HOOKS_DEBUG_FILE` or stderr, and explicitly never includes prompt/payload content (`hooks/agy-hooks-lib.sh:99-118`).
**Validation:** All numeric flags (`--timeout`, `--stdin-timeout`, `AGY_MODELS_TIMEOUT`, etc.) are validated with a `^[1-9][0-9]*$` regex before use; a non-positive-integer env override degrades to the default rather than hard-failing in the shim, since it shadows `gemini` for every caller (`scripts/gemini_shim.sh:62-69`).
**Authentication:** Delegated entirely to `agy` itself; the bridge only detects an unauthenticated/degraded `agy` by checking the live model list contains no `gemini-` prefixed ids (`scripts/agy_bridge.sh:176-183`).

---

*Architecture analysis: 2026-08-18*
</content>
