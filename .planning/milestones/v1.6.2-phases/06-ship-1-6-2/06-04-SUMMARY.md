---
phase: 06-ship-1-6-2
plan: 04
subsystem: testing
tags: [bash, tdd, structural-guard, static-scan]
status: complete

# Dependency graph
requires:
  - phase: 06-ship-1-6-2
    provides: "06-01's RB30 trap-restore fix and 06-03's D-04/D-07 fixes, already on disk/HEAD"
provides:
  - "IN02: joint invariant guarding the twin model-validation herestring sites in agy_bridge.sh and gemini_shim.sh"
  - "RB01 widened to scan tests/contract-check.sh (the harness's own agy invocations), not just the two shipped scripts"
  - "_CC_NO_AGY flag in contract-check.sh removing seven false-positive $AGY_BIN mentions from RB01's scan"
affects: [06-06-release-gate]

# Actuals (#2632) — chars/4 over the realized diff (git diff ea3dd79~2..ea3dd79)
actuals:
  tokens: 1633
  tasks: 2
  commits: 2

# Tech tracking
tech-stack:
  added: []
  patterns: ["joint invariant asserted as one test case over a matched pair of sites, rather than two independent single-file guards", "flag computed once from a command's own exit status instead of re-testing a variable's emptiness, to keep a static text-scanner's false-positive surface at zero"]

key-files:
  created: []
  modified:
    - tests/run-tests.sh
    - tests/contract-check.sh

key-decisions:
  - "IN02 states the bridge/shim model-validation pair as one joint assertion (one failure message naming both counts) rather than two more single-file guards like R9d/SH15d — neither existing guard catches a one-sided edit to the pair."
  - "RB01's floor (RB01_TOTAL >= 1) stays a total across all three scanned files, not per-file, per the plan's stated known ceiling — a future rename emptying contract-check.sh's own contribution still clears the floor on the other two files' occurrences."
  - "_CC_NO_AGY is set from command -v agy's own if/else exit status, not from a second \"-z \\\"\\$AGY_BIN\\\"\" test — a standalone emptiness guard would itself be a $AGY_BIN mention RB01's scanner flags as a false-positive unbounded call. This was verified necessary: a first attempt using \"[[ -z \\\"\\$AGY_BIN\\\" ]] && _CC_NO_AGY=1\" still scored 1 violation under the real scan functions before being replaced with the exit-status form."
  - "RB01's scanner regex itself is untouched — per its own comment (\"fixing this in the scanner is a self-inflicted evasion\"), the fix rewrites the scanned file, never the scan."

patterns-established:
  - "Joint invariant over a matched pair: one test case, one failure message with both sides' counts, when two sites must change together and neither side alone is a complete guard."
  - "Keep a static scanner's false-positive surface at zero by removing the variable mention entirely (branch on the resolving command's exit status) rather than special-casing the scanner around a non-invocation mention."

requirements-completed: [S1, S4, R11, S5]
---

# Phase 06 Plan 04: Structural test guards (IN02, RB01 widen) Summary

Added one joint invariant (IN02) over the twin model-validation SIGPIPE-safe-herestring sites in `agy_bridge.sh`/`gemini_shim.sh`, and widened RB01's unbounded-`agy`-call scan to include the test harness's own `tests/contract-check.sh`, fixing the seven false-positive guard-clause mentions that widening surfaced.

## What Was Built

**Task 1 — IN02 (D-05, delegate-agy-u1z).** `agy_bridge.sh:579` (`grep -qxF "$MODEL" <<< "$VALID_MODELS"`) and `gemini_shim.sh:475` (`grep -qxF "$m" <<< "$LIVE_MODELS"`) are a matched pair: both must stay in the SIGPIPE-safe herestring form. R9d and SH15d already guard each site individually, but neither catches a one-sided edit to the pair — a future patch could revert one side back to `printf|grep` and still pass both existing single-file checks. IN02 asserts the pair jointly, counting occurrences of each exact pattern string in each file and failing with both counts (`bridge_count=... shim_count=...`) if either drifts. Verified green immediately since both sites are already correct on disk (this plan changes nothing under `scripts/`).

**Task 2 — RB01 widen + contract-check.sh fix (D-06, delegate-agy-d4t).** RB01's `run_bounded`-invariant scan previously covered only the two shipped scripts. The test harness invokes the real `agy` binary too (contract-check.sh's `run_bounded` calls at lines 548, 561, 755, 1072), and an unbounded call there hangs the suite exactly as an unbounded call in a shipped script hangs the box — so RB01 now scans `tests/contract-check.sh` as a third file.

Widening the loop alone turned RB01 red, as predicted: contract-check.sh's seven `[[ -z "$AGY_BIN" ]]` preflight guards (lines 540, 578, 613, 657, 711, 842, 1021) each mention `$AGY_BIN` without invoking it, and RB01's scanner flags any expansion of the variable as an occurrence, counting a non-`run_bounded`-prefixed one as a violation. Fixed by computing `_CC_NO_AGY` once, right after `AGY_BIN` resolves, from `command -v agy`'s own if/else exit status (not a second `-z` test on `$AGY_BIN` — see Key Decisions for why that form was tried and rejected), and routing all seven guards through the flag instead of the variable. The four real `run_bounded` call sites are untouched.

## Verification (RED then GREEN, not just final state)

Reproduced via the real `_rb_agy_scan`/`_rb_agy_segments` functions extracted verbatim from `tests/run-tests.sh` and run standalone against both the pre-fix (`git show HEAD~2:tests/contract-check.sh`, before this plan's commits) and post-fix file:

| State | Result (`violations occurrences`) |
|---|---|
| Pre-fix contract-check.sh | `7 11` |
| Post-fix contract-check.sh | `0 4` |
| agy_bridge.sh (unaffected) | `0 2` |
| gemini_shim.sh (unaffected) | `0 3` |

Live full-suite runs confirmed both ends: a run started immediately after widening the loop (before the contract-check.sh guard rewrite) recorded `FAIL - RB01 every agy invocation in both scripts is a run_bounded argument, no exceptions`; the same command after the guard rewrite recorded `ok` for `RB01`, `RB01m`, `RB02`, `RB02m`, `RB30`, and `IN02`. The exact RED detail string (`occurrences=16 detail= contract-check.sh:7_unbounded_of_11[...]`) is reconstructed above from the real scan functions against the exact pre-fix file content, since the live capture used a grep filter that (unintentionally) excluded the indented detail line before the second live run already showed GREEN — the reconstruction uses the identical `_rb_agy_scan`/`_rb_agy_segments` source, not an approximation, so the numbers are exact, not inferred.

## Deviations from Plan

None — plan executed exactly as written. One implementation detail not fully specified by the plan: the `_CC_NO_AGY` computation form. The plan's action text named the flag but not its exact derivation; a first draft (`_CC_NO_AGY=0; [[ -z "$AGY_BIN" ]] && _CC_NO_AGY=1`) was checked against the real scan functions before committing and found to still register as 1 violation (the guard line itself is an uninvoked `$AGY_BIN` mention). Replaced with the `if AGY_BIN="$(command -v agy 2>/dev/null)"; then ... else ...; fi` form, whose only `AGY_BIN` mention is an assignment (which the scanner's own comment states is not a scanned occurrence). This is folded into Task 2's single commit, not a separate deviation-tracked fix, since it was caught during the same task's verification loop before any commit landed.

## Self-Check: PASSED

- `tests/run-tests.sh` and `tests/contract-check.sh` modified as declared: confirmed via `git diff --stat`.
- Commit `875834b` (IN02) and `ea3dd79` (RB01 widen + fix) both present: confirmed via `git log --oneline`.
- `_rb_agy_scan` reports `0 4` for post-fix `tests/contract-check.sh`: confirmed via standalone extraction and direct invocation.
- Live suite: `ok` recorded for RB01, RB01m, RB02, RB02m, RB30, IN02 after both commits.
