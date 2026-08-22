# Coding Conventions

**Analysis Date:** 2026-08-18

Source examined: git worktree `/home/dd/Gemini/delegate-agy/.worktrees/agy-1.6.2` (branch `fix/agy-bridge-resilience`, 12 commits ahead of `master`). Pure bash project, no linter/formatter config, no package manifest. Conventions below are inferred from the two production scripts (`scripts/agy_bridge.sh`, `scripts/gemini_shim.sh`), `scripts/install.sh`/`uninstall.sh`, and `hooks/agy-hooks-lib.sh`.

## Shell Strictness

**Production scripts run strict mode:**
- `scripts/agy_bridge.sh:7` — `set -euo pipefail`
- `scripts/gemini_shim.sh:18` — `set -euo pipefail`
- Both scripts locally suspend it around the `agy` subprocess call (`set +e` ... capture `$?` ... `set -e`) because a non-zero `agy` exit is expected and handled, not an script-level error — see `scripts/agy_bridge.sh:333-338` and `scripts/gemini_shim.sh:338-351`.

**Hook library is deliberately non-strict:**
- `hooks/agy-hooks-lib.sh:1-8` is a sourced-only file that explicitly must NOT set `-e`/`-u` or leak strict mode into the sourcing shell (a Claude Code hook host). It uses an include guard (`_AGY_HOOKS_LIB_SOURCED`) so double-sourcing is a cheap no-op.

**Tests run under `set -u` only, never `set -e`:**
- `tests/run-tests.sh:28` — `set -u`. The suite intentionally omits `-e` because most test bodies call a script expected to fail (non-zero exit) and must inspect `$RC` afterward; `-e` would abort the whole runner on the first such call.
- `tests/hooks/run-hook-tests.sh:29` — `set -uo pipefail` (no `-e`, same reasoning).

When adding a new script under `scripts/`, use `set -euo pipefail`. When adding a new sourced library, follow the `agy-hooks-lib.sh` guard pattern (no strict mode, include guard, no top-level side effects). When extending either test file, do not add `set -e`.

## Env-Var Knobs: Validated, Never Silently Trusted

Every numeric env-var override is validated against the same anchored regex, but the *failure mode differs by blast radius*:

- **`agy_bridge.sh` is a stand-alone CLI — invalid input hard-exits (exit 2):**
  - `AGY_MODELS_TIMEOUT` — `scripts/agy_bridge.sh:24-27`: `[[ "$AGY_MODELS_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: ..." >&2; exit 2; }`
  - `--timeout`, `--stdin-timeout`, `--digest-warn-chars` flags use the identical `^[1-9][0-9]*$` pattern inline in the arg-parse loop (`scripts/agy_bridge.sh:55-63`).

- **`gemini_shim.sh` shadows the system `gemini` for every caller on PATH — invalid input degrades quietly instead of hard-exiting**, except where the shim IS the entry point being called directly with a value only the direct caller controls:
  - `GEMINI_SHIM_STDIN_TIMEOUT` — `scripts/gemini_shim.sh:31-34`: same regex, still hard-exits (this only affects the immediate invocation, not every future PATH lookup of `gemini`).
  - `GEMINI_SHIM_TIMEOUT` — `scripts/gemini_shim.sh:39-42`: same, hard-exits.
  - `AGY_MODELS_TIMEOUT` inside the shim — `scripts/gemini_shim.sh:66-67`: `[[ ... ]] || AGY_MODELS_TIMEOUT=20` — **no exit**, falls back to the default. Comment at `scripts/gemini_shim.sh:61-65` states the rule explicitly: a shim that shadows `gemini` box-wide "must not hard-exit over an optional knob." Test SH13 (`tests/run-tests.sh:990-1006`) pins that `AGY_MODELS_TIMEOUT=0` does not disable the bound (coreutils `timeout` treats 0 as "disabled" — the fallback exists specifically to prevent reintroducing the unbounded-hang bug).

**Pattern to follow:** any new positive-integer env knob uses `^[1-9][0-9]*$`. Decide fail-open vs. fail-closed by asking "does this knob's script shadow a system binary for other callers?" — if yes, fail open with a safe default; if no (bridge, an explicit invocation), fail closed with exit 2 and a message prefixed `ERROR:`.

## `timeout -k` Discipline at Every `agy` Call Site

`agy` is documented (and tested, via `fake-agy.sh`'s hang modes) to ignore `SIGTERM`. Every invocation of `agy` in both production scripts therefore uses `timeout -k <grace> <bound> agy ...`, never plain `timeout`:

| Call site | File:line | Bound var | Kill grace |
|---|---|---|---|
| `agy models` (bridge) | `scripts/agy_bridge.sh:141-142` | `AGY_MODELS_TIMEOUT` (default 20s) | `-k 3` |
| `agy --print` (bridge delegation) | `scripts/agy_bridge.sh:329-332` | `TIMEOUT` (default 300s search / 600s other) | `-k 5` |
| `agy models` (shim) | `scripts/gemini_shim.sh:90-91` | `AGY_MODELS_TIMEOUT` (default 20s) | `-k 3` |
| `agy --version` (shim) | `scripts/gemini_shim.sh:194-196` | fixed 10s, non-configurable | `-k 5` |
| `agy --print` (shim main call) | `scripts/gemini_shim.sh:340-343` | `SHIM_TIMEOUT` (default 600s) | `-k 5` |

Comments at each site cross-reference the others (e.g. `scripts/gemini_shim.sh:86-89` calls itself "the third agy call site in this script, bounded like the other two"). **Any new call to the `agy` binary must be wrapped the same way** — a bare `agy` invocation, or a plain `timeout` without `-k`, reintroduces the exact hang class the test suite's T4/T5/R5/SH4/SH5/SH11 cases exist to catch.

Distinguish a `timeout -k` SIGKILL (exit 137 landing *at or after* the bound) from an *external* SIGKILL (exit 137 landing *before* the bound, e.g. OOM killer) — both scripts compare `$DURATION` against the configured bound to report these as different error classes (`scripts/agy_bridge.sh:355-368`, `scripts/gemini_shim.sh:369-376`). Do not fold both cases into one "timeout" message.

## Prompt Delivery: GEMINI.md, Never argv or stdin

Both scripts embed the user prompt into a `GEMINI.md` file (`TASK:` section, after a `---` separator) inside a per-run `mktemp -d` work directory, and pass only a static pointer string as `--print`'s value:

- `scripts/agy_bridge.sh:293-297` (embed) / `scripts/agy_bridge.sh:299` (`AGY_POINTER`)
- `scripts/gemini_shim.sh:290-294` (embed) / `scripts/gemini_shim.sh:295` (`AGY_POINTER`)

Reasons stated in-line: keeps the prompt off `argv`/`ps`/`/proc`, and removes any `ARG_MAX` cap on prompt size (`scripts/agy_bridge.sh:290-292`). `GEMINI.md` is `chmod 600`. The prompt-bearing work directory is *always* the last `--add-dir` passed to `agy` (`scripts/agy_bridge.sh:325`, `scripts/gemini_shim.sh:283-286`) — the tests (`AD1`, T1/T2/T3) exist specifically to pin that ordering, because `agy` resolves `GEMINI.md`/`TASK` from the last `--add-dir` seen. **Do not deliver a prompt via stdin or a CLI argument to `agy`** — that is the exact leak vector T1/S8 assert against.

## Anchored Model Matchers — Never Loosen, Normalize the Input Instead

Model class matching uses `^gemini-[0-9.]+-<class>$` anchored regexes, e.g.:
- `scripts/agy_bridge.sh:189` — `^gemini-[0-9.]+-flash-high$`
- `scripts/agy_bridge.sh:191` — `^gemini-[0-9.]+-pro-high$`
- `scripts/gemini_shim.sh:129` — `^gemini-[0-9.]+-${class}\$` (class interpolated)

Selection among matches is always `sort -V | tail -1` (newest wins) — never a hardcoded or frozen version string. The map at `config/model-map.json` maps aliases to **classes** (`pro-high`, `flash-high`, …), never to a frozen model id or display name — test S6 (`tests/run-tests.sh:151-178`) explicitly fails if any map value is not one of the 5 known classes, because a frozen id/display-name value is the exact drift bug (`delegate-agy-ovu`, `delegate-agy-62x`) this scheme exists to prevent.

`agy models` emits `id<TAB>display name` per line; both scripts normalize with `cut -f1` immediately after fetch *and* after reading from cache (`scripts/agy_bridge.sh:175-177`, `scripts/gemini_shim.sh:99` via `load_models`), so a stale cache written by an older bridge version still normalizes correctly (test R3c). **If a check ever needs to loosen** (e.g. a new model naming scheme), normalize the input value to match the existing anchor — do not widen the anchor itself, since the anchor is what stops an unknown/malformed model id from silently validating (test R3d/S9 pin the reject path).

## Degradation Philosophy: Shim Degrades Quietly, Bridge Fails Loud

This is the single most important behavioral split in the codebase, driven by blast radius:

- **`gemini_shim.sh` installs as `~/.local/bin/gemini` and shadows the real `gemini` for every PATH caller** (Octopus, Metaswarm, direct users). It must never break a caller over a knob that has a safe fallback:
  - Unresolvable env timeout → falls back to default, no exit (`scripts/gemini_shim.sh:66-67`).
  - Unknown `-m` model name → passed through **unchanged** to `agy`, with a `WARNING` on stderr only if the live list actually contains gemini ids (test SH9, SH14) — refusing an unrecognized name would break every caller using a model the map has never heard of.
  - `HOME` unset → cache path degrades to `/nonexistent/...`, all cache writes are `... 2>/dev/null || true`, script still runs (test SH12, `scripts/gemini_shim.sh:73-75`).
  - Failed/hung model fetch → silently falls back to the stale cache, **no warning** (test SH10/SH14): "a PATH-shadowing `gemini` degrading to its cache is normal operation, not an event every Octopus/Metaswarm log line needs to carry" (`tests/run-tests.sh:919-924`).

- **`agy_bridge.sh` is an explicit, opt-in CLI invocation.** It fails loud on the same class of fault:
  - Invalid `AGY_MODELS_TIMEOUT` → `exit 2` with `ERROR:` message.
  - Unknown `--model` → `exit 2` with `ERROR: unknown --model ...`.
  - Model fetch fails with no cache → `exit 2`, surfaces `agy`'s own stderr as the only diagnostic (test R7).
  - A model list with zero `gemini-` ids → `exit 2`, explicitly says the list is "degraded" rather than blaming `--type` (test R8).
  - Stale cache fallback on fetch failure → still WARNs on stderr (test R6), unlike the shim's silent equivalent — an explicit CLI call is expected to see diagnostics.

When adding new behavior to either script, ask "does this run as every PATH caller's `gemini`, or as an explicit CLI invocation?" and match the corresponding fail-open/fail-loud posture and warning verbosity above.

## Exit Codes Are a Contract

Both scripts use a consistent exit-code vocabulary, asserted by tests and documented in `agents/agy-delegate-code.md` / `agents/agy-delegate-search.md` (each carries a `| 3 |` row classifying `empty_output`/`quota`/`auth` — test ST4, `tests/run-tests.sh:684-697`):

- `0` — success
- `2` — usage/validation error (bad flag, bad `--add-dir`, bad `--model`, empty prompt, no `agy` on PATH)
- `3` — hidden failure: `agy` exited 0 with empty stdout (quota/auth/silent-backend-error), classified via stderr token match into `empty_output`/`quota`/`auth` (`scripts/agy_bridge.sh:396-406`, `scripts/gemini_shim.sh:378-388`)
- `124` — timeout (own `-k` escalation fired, or duration ≥ configured bound)
- `137` reported distinctly as **"killed"** (not "timeout") when duration is *below* the configured bound — an external SIGKILL, not the script's own escalation

## `--add-dir` Safety Guards

`agy_bridge.sh` refuses to grant `/` or `$HOME` via `--add-dir` unless `AGY_ALLOW_BROAD_GRANT=1` is set (`scripts/agy_bridge.sh:65-72`). The comparison strips a trailing slash from `$HOME` before comparing (test AD8 pins this — a raw compare would let a trailing-slash `$HOME` bypass the guard) and resolves the target via `CDPATH='' cd -- "$2"` (not a bare `cd "$2"`) so a directory literally named `-P` is granted as itself rather than parsed as a `cd` option (test AD3). Any new path-accepting flag should reuse this `CDPATH='' cd --` + exact-match-on-resolved-path pattern rather than a prefix or raw string compare.

## Naming

**Env vars:** `SCREAMING_SNAKE_CASE`, prefixed `AGY_` or `GEMINI_SHIM_` by which script owns them (`AGY_MODELS_TIMEOUT`, `AGY_ALLOW_BROAD_GRANT`, `AGY_SKIP_PERMISSIONS`, `GEMINI_SHIM_TIMEOUT`, `GEMINI_SHIM_STDIN_TIMEOUT`).

**Local shell vars:** `SCREAMING_SNAKE_CASE` for script-scoped state (`TYPE`, `MODEL`, `WORK_DIR`); leading-underscore `SCREAMING_SNAKE_CASE` or `_lower` for values whose scope is a single block (`_agy_err`, `_agy_rc`, `_reason`, `_class`).

**Functions (hook lib only, `hooks/agy-hooks-lib.sh`):** `agy_hooks_<verb>` — `agy_hooks_enabled`, `agy_hooks_agent_allowed`, `agy_hooks_parse_field`, `agy_hooks_debug`. Every public function is documented with a header comment stating its contract (return semantics, side effects) immediately above the definition — follow this when adding new hook-lib functions.

## JSON Handling: python3, Never `jq`

All JSON construction/parsing goes through `python3 -c "..."` (e.g. `scripts/agy_bridge.sh:359-361`, `scripts/gemini_shim.sh:381-384`, `hooks/agy-hooks-lib.sh:84-93`), never `jq`. `hooks/agy-hooks-lib.sh:86` states parsing "goes through python3's json module (never eval)". `install.sh`'s tokensave registration explicitly fails open (exit-0, skip) when `python3` is absent (test I10) rather than hard-failing the whole install.

## Git Conventions (from project `CLAUDE.md`)

- Conventional Commits, message states the *why*.
- No AI attribution, no emojis, no `Co-Authored-By:` trailer — enforced by a global `commit-msg` hook.
- Never bypass pre-commit hooks via `--no-verify`.
- Prefer new commits over `--amend`.

## Installer/Uninstaller Conventions (`scripts/install.sh`, `scripts/uninstall.sh`)

**Backup naming:** `_ts() { date +%Y%m%d%H%M%S; }` (`scripts/install.sh:65`) produces `<original>.bak-agy-<YYYYMMDDHHMMSS>`, used at every backup site: shadowed binary (`scripts/install.sh:83-85`), rc file before alias patch (`scripts/install.sh:242`), and agy MCP config before tokensave registration (Python `time.strftime`, `scripts/install.sh:281`). `uninstall.sh`'s `remove_wrapper` restores the newest `.bak-agy-*` by lexicographic (`>`) comparison (`scripts/uninstall.sh:41-48`), which works because the timestamp suffix is fixed-width. Any new backup site must reuse this exact suffix scheme or `uninstall.sh`'s restore breaks.

**`is_our_wrapper` marker:** `WRAPPER_MARKER='# agy-delegate-wrapper'` (`scripts/install.sh:29`, `scripts/uninstall.sh:12`), written literally into every generated wrapper (`scripts/install.sh:127`). `is_our_wrapper()` (`scripts/install.sh:71-74`, duplicated verbatim in `scripts/uninstall.sh:22-25`) does a `grep -qF` existence check against it — duplicated rather than sourced, since uninstall must work even if a shared lib were missing. `write_wrapper` backs up only if the existing file is NOT already one of ours; `remove_wrapper` touches a file only if it IS. Any new installed artifact needing safe re-install/uninstall must carry this same marker.

**Wrapper heredoc — install-time literals vs runtime references (load-bearing, easy to invert):** `write_wrapper()` (`scripts/install.sh:96-152`) writes via `cat > "$tmp" <<WRAP`. Unescaped `$name` inside the heredoc is substituted by the *outer* (install.sh) shell — an install-time literal, baked in once: `_AGY_TARGET='$target_sq'`, `_AGY_VERSION='$version_sq'`, `_AGY_VERSIONS_ROOT='$parent_dir_sq'` (`scripts/install.sh:132-134`), computed once from the resolved target path and never re-derived until the next install run. Escaped `\$name` leaves a literal `$` in the written file, expanded only when the *generated wrapper* runs — a runtime reference: `\$_AGY_TARGET`, `\$_AGY_REGISTRY`, `\$_agy_active` (`scripts/install.sh:135-171`), re-evaluated on every wrapper invocation. The exec line mixes both: `exec -a "$name" bash "\$_AGY_TARGET" "\$@"` (`scripts/install.sh:172`) — `$name` install-time literal, `\$_AGY_TARGET` a runtime reference to a variable defined earlier in the same generated file, `\$@` the wrapper's own runtime argv. Security property: the exec target is always the install-time literal, never re-derived from the registry at runtime — the registry is read only for a stale-pin *comparison*, and the printed repin hint is built from the install-time `\$_AGY_VERSIONS_ROOT` plus a regex-validated numeric version string, never an `installPath` value read back out of the registry (`scripts/install.sh:141-168` — comment states "No registry-supplied path is ever printed").

**`_sq()` quoting helper — uncommitted, in-flight.** `git status` in the worktree shows `M scripts/install.sh` (not committed). `_sq() { printf '%s' "${1//\'/\'\\\'\'}"; }` at `scripts/install.sh:69` escapes `'` for safe embedding in the heredoc's single-quoted values (`target_sq`, `version_sq`, `parent_dir_sq`, `reg_key_re_sq`), fixing an apostrophe-in-path quote-breakout. This is a fix mid-flight in this worktree, not yet established or merged practice — do not describe every install-time literal as routing through `_sq()` as if that were long-standing convention.

**Registry parsing:** the stale-pin sed range (`scripts/install.sh:154-157`) opens on a line ending `"<key>": [` and closes at that array's own `]` — bounded to one entry, not a fixed line count, so an empty array or a neighboring plugin's fields can't leak in. The version match is anchored at line start (`^[[:space:]]*"version"`) to stop a compact single-line registry entry from matching a later field. The key itself is matched as an exact string (not a prefix), so a same-named plugin from a different marketplace can't be confused for this install (`scripts/install.sh:104-110`).

**Refuse-root guard**, identical in both scripts, first thing each runs (`scripts/install.sh:31-34`, `scripts/uninstall.sh:14-17`):
```bash
if [[ "${EUID:-$(id -u)}" -eq 0 || -n "${SUDO_USER:-}" ]]; then
    echo "ERROR: refusing to run as root (or via sudo). Run as your normal user." >&2
    exit 1
fi
```
Checks direct root and root-via-sudo; exits `1` — distinct from the bridge's own `2`/`3`/`124` vocabulary. Any new installer entry point copies this verbatim before any other side effect.

## MCP Tool-Restriction Policy Files (`config/policies/*.md`)

Five plain-text advisory blocks embedded into a generated `GEMINI.md` (`scripts/agy_bridge.sh:222`, `scripts/gemini_shim.sh:257`). Never API-enforced — every file states this in its header, e.g. `config/policies/code.md:1`. Shape: `PERMITTED:` list, `FORBIDDEN:` list, refusal instruction.

`search.md`, `shim-default.md`, `shim-sandbox.md`, `shim-yolo.md` carry an identical (byte-for-byte, test ST1) catch-all forbidding every `ctx_*` tool, `ctx_call`, every `tokensave_*` tool, and any `mcp__*` tool. `code.md`, `implement.md`, `review-analysis.md` do NOT carry it — those three explicitly PERMIT `ctx_read, ctx_search, tokensave_context`, which would directly contradict the catch-all. New policy files: decide up front whether MCP-permitted (omit catch-all, whitelist the trio) or not (include catch-all verbatim).

`shim-yolo.md` adds: yolo runs agy under `--dangerously-skip-permissions`, so these restrictions are "best-effort prompt-advisory, NOT API-enforced" (`config/policies/shim-yolo.md:8`) — actual containment for shim modes is `--sandbox`/`--add-dir`, not this text.

## Model-Alias Map (`config/model-map.json`)

Flat JSON, alias string to **class** string (`"flash": "flash-high"`) — never a full model id or display name. Exactly 5 classes: `pro-high`, `pro-low`, `flash-high`, `flash-medium`, `flash-low`. `gemini_shim.sh`'s `map_model()` (`scripts/gemini_shim.sh:117-141`) reads the map via `python3 -c`, then resolves the class against the live `agy models` list with `grep -E "^gemini-[0-9.]+-${class}\$" | sort -V | tail -1` — the map supplies only the class, never a version, so a new model release needs zero edits here. Legacy pinned-name aliases (`gemini-2.5-flash-preview-04-17`, `gemini-2.5-pro-preview-06-05`) map forward to current classes rather than being deleted — when retiring a generation, repoint the alias, don't drop the key (test S6 pins no key may vanish).

## `hooks/agy-subagent-policy.sh` — Fail-Safe-Silence

Six ordered early-exit guards, each with its own `agy_hooks_debug "<reason> -> skip"` before `exit 0` — never non-zero, never stdout, on any guard-fail path: (1) `agy_hooks_enabled`, pure bash (`hooks/agy-subagent-policy.sh:24-27`); (2) `python3 -c 'import json'` usability probe (`:33-36`), deliberately separate from guard 4 so a broken python3 is reported as "no python3", not "malformed json"; (3) empty/whitespace stdin (`:42-45`); (4) malformed JSON (`:51-54`); (5) `agy_hooks_agent_allowed` (`:60-63`); (6) `agy-bridge` not on `PATH` (`:66-69`). Ordering is pinned: guard 1 before guard 2 so the default-off path never forks an interpreter; guard 2 before guard 4 so a broken-but-present python3 isn't misreported. Stdin is fully drained via `input="$(cat)"` before any guard runs. The one non-silent branch emits a fixed, hardcoded advisory via a `python3` heredoc — never shell-interpolated, never echoing any part of the incoming payload (`hooks/agy-subagent-policy.sh:71-88`).

---

*Convention analysis: 2026-08-18*
