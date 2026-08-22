---
phase: 02-model-list-handling-end-to-end
plan: 03-fixround
subsystem: agy_bridge.sh / gemini_shim.sh model-list fetch/cache path (code-review follow-up)
tags: [bash, sigpipe, pipefail, tdd, security, code-review-followup]
status: complete
dependency-graph:
  requires:
    - "Plan 02-01: D-03/D-04/D-05/D-07/D-08 on scripts/agy_bridge.sh"
    - "Plan 02-02: D-03/D-04/D-05/D-08 mirrored onto scripts/gemini_shim.sh"
    - "02-REVIEW.md: CR-01, WR-01, WR-02, IN-01 (this round's 4 fixes)"
  provides:
    - "CR-01 closed: agy_bridge.sh's --model validation uses the herestring form, closing the last un-hardened grep -qxF SIGPIPE/pipefail site on the bridge"
    - "WR-01 closed: gemini_shim.sh's map_model live-id check uses the herestring form, same class as CR-01 on the shim"
    - "WR-02 closed: agy_bridge.sh's stderr-capture mktemp assignment and its 3 downstream uses degrade gracefully instead of aborting the script under set -e"
    - "IN-01 closed: the cache-file write in both scripts is umask-guarded, closing the world/group-readable window between mv and chmod"
  affects:
    - "02-REVIEW.md's critical/warning/info findings for this phase are now all resolved except the two deliberately-deferred tickets (WR-03, IN-02)"
tech-stack:
  added: []
  patterns:
    - "Herestring (grep -qxF ... <<< \"$var\") over printf | grep -q, for every site reading an untrusted, externally-sized list -- not just the two D-08 originally converted, mirrored identically on both scripts"
    - "Guard a bare command-substitution assignment under set -e with || fallback, and thread the fallback through every downstream consumer with -n checks, rather than letting a rare external-tool failure abort the whole script"
    - "Scope a stricter umask to a single write via a ( umask 077; ... ) subshell, not a script-wide umask call, so the safety property never leaks past the one write it protects"
key-files:
  created:
    - /home/dd/Gemini/delegate-agy/.planning/phases/02-model-list-handling-end-to-end/deferred-items.md
  modified:
    - /home/dd/Gemini/delegate-agy/.worktrees/agy-1.6.2/scripts/agy_bridge.sh
    - /home/dd/Gemini/delegate-agy/.worktrees/agy-1.6.2/scripts/gemini_shim.sh
    - /home/dd/Gemini/delegate-agy/.worktrees/agy-1.6.2/tests/run-tests.sh
decisions:
  - "CR-01/WR-01: mirrored the exact conversion 02-01/02-02 already applied at the other pipefail-hazard sites (grep -qxF \"$X\" <<< \"$var\"), rather than reintroducing pipefail-safety as a new helper -- keeps the fix a one-line diff per site, matching the plan's own prior precedent."
  - "WR-02: guarded the mktemp assignment with || _agy_err=\"\", the redirect with \"${_agy_err:-/dev/null}\", and both downstream uses with -n \"$_agy_err\" checks -- the redirect guard specifically avoids degrading to a fetch-failure (an empty-string redirect target would itself fail and cascade into the enclosing command substitution's failure branch); the guard keeps the failure mode scoped to \"no stderr capture this run\", per the review's literal fix text."
  - "IN-01: wrapped only the printf > tmp write in a ( umask 077; ... ) subshell, not the whole write block or a script-wide umask -- avoids changing the cache directory's permissions (created by the adjacent mkdir -p, unaffected) and avoids leaking the stricter umask onto anything the script does afterward."
  - "RB24 (tests/run-tests.sh, a run_bounded trap-preservation test) surfaced as an intermittent flake during verification. Confirmed pre-existing and unrelated by reproducing the same failure on a7ab6bd (02-02's tip, before any of this round's changes) via a scratch git-archive checkout. Out of this round's explicit 4-fix scope; not fixed. Logged to deferred-items.md and filed as delegate-agy-sup (P3, open) rather than silently dropped."
metrics:
  duration: "~1h"
  completed: 2026-08-20
actuals:
  tokens: 2576
  tasks: 4
  commits: 8
---

# Phase 02 Plan 03 (Fix Round): Four code-review follow-ups from 02-REVIEW.md Summary

Folded the phase's own code-review findings (`02-REVIEW.md`, one critical + two
warnings + one info) back into the phase before marking it complete, per this
project's standing rule that follow-ups discovered during work are blockers,
not deferred. All 4 fixes applied on `fix/agy-bridge-resilience` in the
`agy-1.6.2` worktree, each with its own RED/GREEN commit pair; the two other
review findings (WR-03's flag-parser bug, IN-02's standing structural-guard
suggestion) were deliberately left untouched, per the user's explicit scope.

## What Was Built

**CR-01 (`delegate-agy-28k`)** — `agy_bridge.sh:549`'s explicit `--model`
validation was the one `grep -qxF` site the phase's own D-08 hardening pass
left as a `printf '%s\n' "$VALID_MODELS" | grep -qxF "$MODEL"` pipe, two lines
from the sites D-08 did convert. `grep -q` (regardless of `-x`/`-F`) exits on
first match, so a large enough `$VALID_MODELS` can SIGPIPE the upstream
`printf`; under `set -o pipefail` (line 8) the pipeline reports the
SIGPIPE'd `printf`'s 141, not `grep`'s 0, falsely rejecting a valid,
live `--model` value with `exit 2`. Converted to the herestring form,
mirroring D-08's sibling conversions exactly:
```bash
if ! grep -qxF "$MODEL" <<< "$VALID_MODELS"; then
```

**RED (R9d):**
```
FAIL - R9d --model validation uses the SIGPIPE-safe herestring form, not printf|grep (CR-01)
```
Structural, not a live SIGPIPE reproduction — the fixture's fetch reply is too
small to trigger the race reliably in a regression suite; the assertion pins
the code shape instead (`grep -cF` counts of the pipe form vs. the herestring
form), same convention the phase's own `02-01-SUMMARY.md`/`02-02-SUMMARY.md`
already used to verify D-08's conversions.

**WR-01 (`delegate-agy-bg4`)** — `gemini_shim.sh:457`'s `map_model` "is `$m`
already a live id" check had the identical hazard on the shim side. Unlike
CR-01 this doesn't hard-fail (a SIGPIPE'd check falls through to class
mapping, which passes the name through unchanged at the end — same final
output), but it prints a spurious `WARNING: ... did not resolve` for a model
that in fact resolved, landing in every PATH caller's log since this shim
shadows `gemini` box-wide. Same herestring conversion:
```bash
if [[ -n "$LIVE_MODELS" ]] && grep -qxF "$m" <<< "$LIVE_MODELS"; then
```

**RED (SH15d):** same structural shape as R9d, on the shim's file.

**WR-02 (`delegate-agy-hrt`)** — `agy_bridge.sh:474`'s
`_agy_err="$(mktemp -t agy-models-err.XXXXXX)"` was a bare assignment under
`set -euo pipefail`; if `mktemp` ever fails (unwritable `/tmp`, misconfigured
`TMPDIR`, disk full — plausible in the locked-down containers/CI runners this
script's own comments say it must survive), the assignment's non-zero exit
terminates the whole script with no diagnostic, unlike every adjacent line in
this block, which is careful to degrade gracefully (`mkdir -p ... || true`,
the tmp-then-`mv` write, `chmod`). Guarded the assignment, the redirect
target, and both downstream uses:
```bash
_agy_err="$(mktemp -t agy-models-err.XXXXXX)" || _agy_err=""
...
"$AGY_BIN" models </dev/null 2>"${_agy_err:-/dev/null}"); then
...
[[ -n "$_agy_err" && -s "$_agy_err" ]] && sed 's/^/       agy: /' "$_agy_err" >&2
[[ -n "$_agy_err" ]] && rm -f "$_agy_err"
```
The sibling `WORK_DIR=$(mktemp -d ...)` patterns in both scripts (flagged by
the review as "same class, out of scope") were explicitly left untouched, per
the fix instructions.

**RED (R9e):** structural — pins all 4 guarded call shapes by literal text
(the assignment's `|| _agy_err=""` fallback, the redirect's
`${_agy_err:-/dev/null}`, and the two `-n "$_agy_err"`-guarded downstream
uses), since reproducing a real `mktemp` failure needs a faked-out `PATH` that
would add more test-harness surface than the fix warrants.

**IN-01 (`delegate-agy-ke6`)** — the tmp-then-`mv` cache write in both
scripts left the new file at process-umask permissions (typically `644`)
until the `chmod 600` two lines later ran; a process killed between `mv` and
`chmod`, or a concurrent reader, would briefly see the file world/group-
readable. Low impact (cached content is public model IDs, not a secret), so
wrapped only the write in a scoped subshell rather than a script-wide umask
call:
```bash
{ ( umask 077; printf '%s' "$_agy_models" > "$CACHE_FILE.tmp.$$" ) \
    && mv "$CACHE_FILE.tmp.$$" "$CACHE_FILE"; } 2>/dev/null || true
```
(and the mirror on `gemini_shim.sh` with `$raw`/`$MODELS_CACHE`). The
subshell keeps the stricter umask from leaking onto anything else the script
does; `mv` preserves the tmp file's already-restricted mode across the
rename, so the window is closed before the existing `chmod 600` ever runs.

**RED (IN01):** structural — `grep -cF` for the exact `( umask 077; printf
'%s' ... )` shape in both files. Per the review's own "low-impact" framing,
no behavioral race test was added; final permissions are unchanged (`600` via
the existing `chmod`), only the transient window closes.

## Verification (run after all 4 fixes)

- `bash tests/run-tests.sh` → **PASS=144 FAIL=1** (up from the pre-round
  baseline `PASS=141 FAIL=0`; the +4 came from R9d/SH15d/R9e/IN01, all green)
- The one `FAIL` is `RB24` (a `run_bounded` trap-preservation test),
  intermittent and confirmed pre-existing: reproduced on `a7ab6bd` (02-02's
  tip, before this round) via a scratch `git archive` checkout, same failure,
  unrelated to any of the 4 reviewed sites. Logged to `deferred-items.md` and
  `delegate-agy-sup` (P3, open), not fixed here (out of this round's explicit
  scope).
- `bash -n scripts/agy_bridge.sh` and `bash -n scripts/gemini_shim.sh` → both
  exit 0
- `git diff --stat a7ab6bd HEAD` names exactly 3 files:
  `scripts/agy_bridge.sh` (16 changed lines), `scripts/gemini_shim.sh` (9
  changed lines), `tests/run-tests.sh` (70 changed lines)
- Confirmed via diff inspection that WR-03's flag parser (`gemini_shim.sh:556`
  area) and the two `sort -V | tail -1` auto-select sites in both scripts are
  byte-identical to their pre-round state — no changes leaked beyond the 4
  named sites

## Deviations from Plan

None of the 4 fixes deviated from the review's literal fix text. One
out-of-scope discovery (RB24's intermittent flake) surfaced during
verification; per the SCOPE BOUNDARY rule (only auto-fix issues directly
caused by the current task's changes) it was not fixed, only logged
(`deferred-items.md`) and ticketed (`delegate-agy-sup`, P3, open) rather than
silently dropped.

## Known Stubs

None.

## Threat Flags

None — all 4 fixes close existing threat-surface gaps the phase's own review
found; no new surface was introduced.

## Commits (all on `fix/agy-bridge-resilience`, worktree `agy-1.6.2`)

- `a24340c` test(02-03): R9d pins the SIGPIPE-safe herestring form for --model validation (RED)
- `f47ff6b` fix(02-03): use herestring form for --model validation to avoid SIGPIPE hazard (CR-01)
- `465057c` test(02-03): SH15d pins the SIGPIPE-safe herestring form for map_model's live-id check (RED)
- `5272b90` fix(02-03): use herestring form for map_model's live-id check to avoid SIGPIPE hazard (WR-01)
- `d90bfc6` test(02-03): R9e pins the guarded mktemp assignment for stderr capture (RED)
- `3c5fb09` fix(02-03): guard mktemp assignment and downstream uses against mktemp failure (WR-02)
- `ab352e2` test(02-03): IN01 pins the umask-guarded cache write in both scripts (RED)
- `dbbd81f` fix(02-03): close the cache-file permission window with umask 077 (IN-01)

## Beads

- `delegate-agy-28k` (CR-01) — closed, ref `f47ff6b`
- `delegate-agy-bg4` (WR-01) — closed, ref `5272b90`
- `delegate-agy-hrt` (WR-02) — closed, ref `3c5fb09`
- `delegate-agy-ke6` (IN-01) — closed, ref `dbbd81f`
- `delegate-agy-sup` (RB24 flake, follow-up) — filed, open, P3
- `delegate-agy-ltf` (WR-03) — left untouched, open (deliberately deferred)
- `delegate-agy-u1z` (IN-02) — left untouched, open (deliberately deferred)

## Self-Check

- `scripts/agy_bridge.sh` — FOUND, modified (16 changed lines vs. `a7ab6bd`)
- `scripts/gemini_shim.sh` — FOUND, modified (9 changed lines vs. `a7ab6bd`)
- `tests/run-tests.sh` — FOUND, modified (70 changed lines vs. `a7ab6bd`)
- `.planning/phases/02-model-list-handling-end-to-end/deferred-items.md` — FOUND, created
- Commit `a24340c` — FOUND in `git log --oneline --all`
- Commit `f47ff6b` — FOUND in `git log --oneline --all`
- Commit `465057c` — FOUND in `git log --oneline --all`
- Commit `5272b90` — FOUND in `git log --oneline --all`
- Commit `d90bfc6` — FOUND in `git log --oneline --all`
- Commit `3c5fb09` — FOUND in `git log --oneline --all`
- Commit `ab352e2` — FOUND in `git log --oneline --all`
- Commit `dbbd81f` — FOUND in `git log --oneline --all`

## Self-Check: PASSED
