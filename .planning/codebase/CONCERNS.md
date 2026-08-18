# Codebase Concerns

**Analysis Date:** 2026-08-18

Source: `bd list --status open` / `bd show <id>` against the live tracker (authoritative, 7 open issues as of this analysis), cross-checked against `scripts/*.sh` in the worktree `/home/dd/Gemini/delegate-agy/.worktrees/agy-1.6.2` (branch `fix/agy-bridge-resilience`, 13 commits ahead of `master`, at commit `56be103`).

**Caveat on this snapshot:** this document describes `fix/agy-bridge-resilience` at `56be103`. `master` itself sits at a deliberately reverted pre-release state (per the task brief), so anyone comparing this document against mainline will see a different, older codebase — re-check file paths and line numbers against the branch, not `master`.

## Blast Radius (read this first)

`scripts/install.sh` installs `gemini` into `~/.local/bin`, shadowing the real Gemini CLI for **every** caller on PATH, not just this plugin — interactive shells, Claude Octopus, and Metaswarm all route through `scripts/gemini_shim.sh`. Any defect in the shim's failure paths is therefore not scoped to `agy-delegate`; it can break unrelated tooling box-wide. This is why every concern below involving `gemini_shim.sh` is weighted higher than an equivalent defect confined to `agy_bridge.sh` (which only runs when explicitly invoked as `agy-bridge`).

`agy` itself is currently unresponsive to SIGTERM and hangs (documented in-code at `scripts/agy_bridge.sh:141-143` and `scripts/gemini_shim.sh:38-41` as "observed"). This is an external dependency defect, not something this codebase can fix — every timeout in both scripts is `timeout -k N ...` specifically to work around it. Any new call site to `agy` that omits the `-k` escalation reintroduces the exact hang this release exists to close.

The highest-consequence instance of this is `delegate-agy-cy5` below: on a host with no `timeout`/`gtimeout` binary, the shim's degrade-and-continue behavior means the PATH-shadowing `gemini` reintroduces the unbounded hang for every caller on that box — interactive shells, Octopus, Metaswarm — while `agy-bridge`, reached only by explicit invocation, refuses to run under the same condition. Same missing dependency, opposite behavior, and the shim's failure mode is the one with box-wide reach.

## Open Tracker Issues (authoritative, verbatim from `bd`)

### P1 — `delegate-agy-30m`: unguarded `$HOME` crashes the bridge

`scripts/agy_bridge.sh:136` — `CACHE_FILE="$HOME/.cache/agy-bridge-models"` — has no `${HOME:-...}` fallback, under `set -euo pipefail` (`scripts/agy_bridge.sh:8`). Under any caller without `HOME` set (systemd units without `User=`, `env -i`, container entrypoints, CI runners), this is `HOME: unbound variable` and a non-zero exit before the bridge does anything. The identical class of bug was already fixed in `scripts/gemini_shim.sh:74` (`MODELS_CACHE="${HOME:-/nonexistent}/.cache/agy-bridge-models"`) — the bridge was never brought in line. The cache-write block at `scripts/agy_bridge.sh:145-147` also lacks the shim's block-level `2>/dev/null` (compare `scripts/gemini_shim.sh:99-100`), so an unwritable cache path leaks a redirect error the shim already suppresses.

Severity: a crash, not a degradation, and it fires on infra this plugin doesn't control (CI, containers).

### P1 — `delegate-agy-cy5`: missing `timeout` binary degrades the shim to an UNBOUNDED agy call

`scripts/gemini_shim.sh:29` sets `TIMEOUT_BIN=""` when neither `timeout` nor `gtimeout` is on PATH, then falls through to the plain `"$AGY_BIN"` branch with no bound at all. Since `agy` ignores SIGTERM and hangs, a coreutils-less host turns the PATH-shadowing `gemini` back into exactly the unbounded hang this release exists to fix — for every caller on that host, not just this plugin's own invocations. `scripts/agy_bridge.sh:15-21` treats the identical missing-binary condition as fatal (`exit 2`): the two scripts diverge on the same question with no documented rationale for the divergence. Filed against an explicit instruction to Task 1 to preserve the shim's degrade path — the design choice (hard-fail like the bridge vs. degrade-with-loud-warning vs. degrade only for non-agy paths) is still open, not just the implementation.

Severity: tied for highest with `delegate-agy-30m` — unlike it, this one's failure mode is the box-wide-shadowing one called out in Blast Radius above, so treat it as the more consequential of the two P1s in practice.

### P2 — `delegate-agy-8ph`: shared-cache poisoning across both scripts

`agy` can exit 0 with output containing no `gemini-` ids (unauthenticated, or an `agy models` output-format change). Both `scripts/agy_bridge.sh:145-147` and `scripts/gemini_shim.sh` write that reply into the **same** file, `$HOME/.cache/agy-bridge-models`, with a shared 60-minute TTL (`scripts/agy_bridge.sh:137`, `scripts/gemini_shim.sh:82`). The bridge already treats a `gemini`-less list as fatal at *use* time (`scripts/agy_bridge.sh:177-182`, `exit 2`) but still caches it at *fetch* time — so one bad `agy models` response degrades both tools for up to an hour. This is the clearest instance of the shared-mutable-state design: two independent writers, one cache, no coordination beyond the TTL.

### P3 (×4) — lower-severity, independently confirmed in code

- `delegate-agy-4vy` — the CLI fallback install one-liner in docs (`agy-setup.md`, `agy-uninstall.md`, `README.md`) pipes `python3 ... | head -1` into an unguarded `RESOLVED=` assignment; under `set -euo pipefail`, `head` closing the pipe early can hand `python3` SIGPIPE (141) and abort before the validating `case` runs. Pre-existing, mostly theoretical (interactive shells aren't `-e` by default).
- `delegate-agy-4xn` — `scripts/install.sh:234` (`python3 - "$RC" "$_real_gemini" <<'PY'`), inside the opt-in `AGY_SETUP_PATCH_ALIASES=1` rc-alias-patch branch, calls `python3` with no `command -v python3` guard. Every other `python3` call site in the same file is guarded (`scripts/install.sh:256`, `275-276`, `347`); this one is the exception. Under `set -euo pipefail`, an absent `python3` hard-fails mid-install, after the wrappers are already written. Reachable only behind the opt-in flag, hence P3.
- `delegate-agy-6q1` — `README.md`'s troubleshooting table (`README.md:231`) quotes the exit-137 row as the static template ending "...possible OOM or external kill", but `scripts/agy_bridge.sh:363` now appends `": %s"` with agy's own stderr (confirmed: `printf 'ERROR: agy killed (signal 9) after %ds, ... : %s\n' ... "$(cat "$STDERR_FILE" ...)"`). Docs are a truncated prefix of actual output.
- `delegate-agy-v5a` — `scripts/agy_bridge.sh:360-363` (external-kill branch) and the generic branch at `scripts/agy_bridge.sh:380-383` both append `': %s'`/`': ' + stderr` unconditionally; an empty `$STDERR_FILE` leaves a trailing `: ` in both plain-text and JSON error output. Confirmed at both sites: `"error": "...ERROR: agy exit %d: %s\n"` pattern reuses the same unconditional suffix. Cosmetic but present in a user-facing error path.

## Resolved (was on this list, now fixed and closed)

### `delegate-agy-b8x` — single-quote interpolation on an apostrophe in the install path

Fixed and committed in `56be103` ("fix(install): escape single-quote interpolation in generated wrapper"). Added `_sq()` at `scripts/install.sh:69` and routed `target`, `version`, `parent_dir`, and `reg_key_re` through it before each is baked into the wrapper heredoc's single-quoted contexts (`scripts/install.sh:118-122,131-133,153`). Covered by test `I18`: install into a plugin path containing an apostrophe. `bd show delegate-agy-b8x` → CLOSED.

## Not Yet Ticketed

### Unverified assumption: does `agy` accept model ids or display names?

`scripts/agy_bridge.sh:171` documents (as an established fact) "agy models emits 'id\tdisplay name'. Keep only the id..." and both scripts (`scripts/agy_bridge.sh:176`, shim's `cut -f1` at load time) discard everything after the tab, then pass the id-only value to `agy --model` (`scripts/agy_bridge.sh:331`: `AGY_FLAGS=(--print "$AGY_POINTER" --sandbox --model "$MODEL")`). Nothing in the two scripts or their comments demonstrates that `agy`'s `--model` flag actually *accepts* the id column rather than requiring the display-name column, or a third canonical form. This is inferred from behavior, not from `agy`'s own documentation or a test invocation (the task brief explicitly rules out invoking the real `agy` binary — it hangs). **Confidence: hypothesis.** What would confirm it: a captured, versioned sample of real `agy models` output plus one successful `agy --model <id> ...` run, checked into `tests/` fixtures rather than assumed.

### External-format coupling via `grep`/`sed`, not real parsers

Two upstream formats this project doesn't control are parsed with regex, not a parser:
- `agy models` output — parsed via `cut -f1` (`scripts/agy_bridge.sh:176`, shim equivalent) and `grep -E '^gemini-[0-9.]+-...-high$' | sort -V | tail -1` for auto-selection (`scripts/agy_bridge.sh:188-189`).
- Claude Code's `installed_plugins.json` — parsed via a `sed` address range keyed on an escaped-but-still-regex plugin identifier, then a second `sed -nE` to pull the `"version"` field (`scripts/install.sh:153-154`), inside the *generated wrapper*, not the installer itself.

Both formats already broke this codebase once: the comment at `scripts/agy_bridge.sh:171` and `scripts/gemini_shim.sh:59-60` records that `agy models` began emitting `id<TAB>display name` and every `$`-anchored matcher silently stopped matching — a real incident, not a hypothetical, evidenced by the in-code fix comments referencing it and by the shared `cut -f1` normalization added at both cache-read sites. Any future upstream format change (a third column, a reordered field, a JSON output mode) has the same silent-failure profile: `grep`/`cut`/`sed` degrade to empty matches, not parse errors, so the failure surfaces downstream as "no gemini- ids" or a wrong version match rather than at the parse site.

### Pinned-launcher design: deliberate hijack prevention, deliberate update friction

`scripts/install.sh` bakes an absolute exec path into `_AGY_TARGET` at install time and the generated wrapper refuses to run when Claude Code's install registry reports a different active version (`scripts/install.sh:139-163`, `exit 127`). This is explicitly a security tradeoff, documented at `scripts/install.sh:8-18` — it exists specifically to prevent a stale or hijacked wrapper from silently continuing to run. The accepted cost: **every plugin update hard-breaks `gemini` and `agy-bridge` until the installer is re-run**, because the pin only points forward. Do not "fix" this by making the wrapper self-heal — that reopens the hijack vector the design exists to close.

### Shared mutable cache: two writers, one file, TTL-only coordination

`scripts/agy_bridge.sh` and `scripts/gemini_shim.sh` independently read and write `~/.cache/agy-bridge-models` with a 60-minute mtime-based TTL (`find "$CACHE_FILE" -mmin +60`) and no locking — each writer does an atomic rename (`mv "$CACHE_FILE.tmp.$$" "$CACHE_FILE"`, `scripts/agy_bridge.sh:147`, shim equivalent) so a torn read is not possible, but there is no coordination beyond that: two processes racing past the staleness check within the same second can both re-fetch and both write, and (per `delegate-agy-8ph` above) a bad fetch from either writer poisons the other's reads for up to an hour. This is the single largest amount of implicit coupling between two otherwise-independent scripts in the codebase.

## Deliberately Accepted (do not "fix")

These are intentional design choices, documented in-code, not oversights — noted here so a future reader doesn't spend effort reverting them:

- **The shim degrades silently by design.** `scripts/gemini_shim.sh:104-107`: a failed or hung model-list fetch falls back to the stale cache with no warning, because a shadowing `gemini` running off cache "is normal operation, and a warning here would land in every Octopus/Metaswarm log line." `load_models()` never fails the script (`scripts/gemini_shim.sh:88-89`). (This is a separate degrade path from `delegate-agy-cy5` above — that one is the missing-`timeout`-binary case, which is filed as an open bug, not accepted.)
- **The bridge fails loud by design.** `scripts/agy_bridge.sh:177-182` treats a `gemini`-less model list as fatal (`exit 2`) rather than degrading, on the reasoning that a human running `agy-bridge` directly needs to know model selection failed, unlike the shim's box-wide callers.
- **`~/bin` duplication in the shim instead of a sourced library.** `scripts/gemini_shim.sh:63-68`: model-list fetch/cache logic is ~20 lines duplicated from the bridge rather than factored into a shared helper, explicitly because the shim installs as `~/.local/bin/gemini` and shadows the real `gemini` for every PATH caller — a missing/broken helper file would break `gemini` box-wide, so the duplication is judged the cheaper failure mode. Both copies are pinned by tests (referenced as R4, SH7-SH11 in-comment; not independently verified in this pass — the task brief excludes running the full suite).
- **`$name` is unescaped in the generated wrapper heredoc, by design.** `scripts/install.sh`'s `exec -a "$name" bash "\$_AGY_TARGET" "\$@"` does not route `$name` through `_sq()` like `target`, `version`, `parent_dir`, and `reg_key_re` are. This is a bounded exception, not a gap: `$name` is always one of the two hardcoded literals `agy-bridge` or `gemini` (never derived from an install path, a plugin cache directory, or any other user- or filesystem-controlled value), so it cannot carry an apostrophe or other quote-breaking character. Do not flag this as an inconsistency in a future escaping audit without first checking whether a call site has started passing a non-literal `$name`.
- **Test isolation uses one shared sandboxed `HOME` for the whole run, not a fresh sandbox per test.** `tests/run-tests.sh:38` traps `cleanup() { rm -rf "$SANDBOX"; }` once for the entire run, and `tests/run-tests.sh:46` sets `export HOME="$SANDBOX/home"` a single time up front — every test in the file shares that `$HOME`. State that would otherwise leak between tests (chiefly the models cache) is cleaned per-test with explicit `rm -f "$HOME/.cache/agy-bridge-models"` calls scattered through the file (e.g. `tests/run-tests.sh:269,291,305,328,332,342,352,364,373`), not by re-sandboxing. This is a real design tradeoff, not an oversight: a fresh `$SANDBOX`/`$HOME` per test would isolate automatically at the cost of one `mktemp -d` + rewrite per test; the current shape trades that isolation guarantee for fewer moving parts, and it depends on every test that touches the shared cache remembering to clean up after itself — a test added later that forgets the `rm -f` will leak cache state into subsequent tests.

---

*Concerns audit: 2026-08-18*
