---
phase: 06-ship-1-6-2
plan: 01
subsystem: testing
tags: [bash, run_bounded, signal-handling, trap, tdd]

# Dependency graph
requires:
  - phase: 05-the-shim-s-failure-mode-contract
    provides: RB24's trap-preservation test and the run_bounded watchdog-arm block this plan reorders
provides:
  - RB30 test case forcing the trap-restore window deterministically (not scheduler-timed)
  - Reordered watchdog arm in agy_bridge.sh, gemini_shim.sh, contract-check.sh — restore before teardown
affects: [06-06-release-gate]

# Actuals (#2632) — chars/4 over the realized diff (git diff 776dbfd~1..d887a8f)
actuals:
  tokens: 1937
  tasks: 2
  commits: 2

# Tech tracking
tech-stack:
  added: []
  patterns: ["one-shot function-shadow injection to force a race deterministically instead of waiting on scheduler timing"]

key-files:
  created: []
  modified:
    - tests/run-tests.sh
    - scripts/agy_bridge.sh
    - scripts/gemini_shim.sh
    - tests/contract-check.sh

key-decisions:
  - "RB30 shadows _rb_cancel_timer with a guard-then-kill-then-delegate wrapper rather than re-running RB24 more times — the window is real but scheduler-timed, so a timing-based case could stay green on the unfixed helper indefinitely."
  - "Fix is a pure statement reorder (move the teardown _rb_cancel_timer call to after the trap restore), applied byte-identically to all three copies of the run_bounded block; RB02 enforces the byte-identity mechanically rather than by eyeballing three diffs."
  - "RESEARCH.md's hypothesis A2 ($_rb_pgid_of possibly returning a stale pgid) is out of scope — RB30 going green does not touch it, and the plan's HALT rule (no pivoting into A2 if the reorder alone doesn't turn RB30 green) was not triggered since the reorder was sufficient."
  - "delegate-agy-sup (the D-08 bug ticket) and the tmm epic stay open; per-plan closure is deferred to 06-06's release-gate dossier. This plan's own two task tickets (tmm.1, tmm.2) were closed individually since their scoped work is complete."

patterns-established:
  - "Deterministic forcing case for a race window: shadow the specific function call that opens the window with a one-shot wrapper that self-signals, rather than relying on repeated runs to hit a timing-dependent race."

requirements-completed: [R11, S3]

coverage:
  - id: D1
    description: "RB30 deterministically forces a TERM into the window between the watchdog arm's timer teardown and its host-trap restore, proving RED against the unmodified helper"
    requirement: "R11"
    verification:
      - kind: unit
        ref: "tests/run-tests.sh RB30 (pre-fix: FAIL, confirmed 3x consecutive)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Watchdog arm's teardown _rb_cancel_timer call moved to run after trap restore in all three byte-identical copies (agy_bridge.sh, gemini_shim.sh, contract-check.sh), closing the D-08 window"
    requirement: "S3"
    verification:
      - kind: unit
        ref: "tests/run-tests.sh RB30, RB24, RB02, RB02m (post-fix: FAIL=0 full suite, 2 consecutive runs)"
        status: pass
    human_judgment: false

# Metrics
duration: 35min
completed: 2026-08-22
status: complete
---

# Phase 06 Plan 01: RB30 trap-restore window fix Summary

**Closed delegate-agy-sup's D-08 window — the watchdog arm's timer teardown ran before host TERM/INT/HUP traps were restored, so a signal landing in that gap was still caught by the still-armed `_rb_relay` trap, which unconditionally exits and skips the restore; fix is a 5-line statement reorder applied byte-identically to all three copies of the run_bounded block, proven by a new deterministic forcing case (RB30) rather than a re-run of the scheduler-timed RB24 flake.**

## Performance

- **Duration:** 35 min
- **Tasks completed:** 2/2
- **Files changed:** 4
- **Commits:** 2

## Accomplishments

- Added RB30 to `tests/run-tests.sh`: a deterministic forcing case that shadows `_rb_cancel_timer` with a one-shot guard-then-kill-then-delegate wrapper, sending the running shell a `TERM` on the exact call that tears down the timer inside `run_bounded`'s watchdog arm. Confirmed RED 3x consecutive against the unmodified helper (the after-dump never printed — the shell exited 143 via `_rb_relay` before reaching the restore lines).
- Moved the single `_rb_cancel_timer "$timer" "$timer_pgid"` teardown call in the watchdog arm to run *after* `trap - TERM INT HUP` and the three `eval "${rb_trap_*:-}"` restores, in `scripts/agy_bridge.sh`, `scripts/gemini_shim.sh`, and `tests/contract-check.sh` — the same 4-comment-line, statement-reorder edit in all three, confirmed byte-identical by direct diff of the extracted `run_bounded` block and by RB02.
- Full suite green (`PASS=162 FAIL=0`) on 2 consecutive runs post-fix; RB30, RB24, RB02, and RB02m all pass explicitly.

## Task Commits

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | RB30 — deterministic forcing case, proven RED | 776dbfd | tests/run-tests.sh |
| 2 | Restore host traps before timer teardown, all three copies | d887a8f | scripts/agy_bridge.sh, scripts/gemini_shim.sh, tests/contract-check.sh |

## TDD Gate Compliance

Task 1 was `type="tracer"` with `tdd="true"`: RED gate confirmed (commit 776dbfd, suite `PASS=161 FAIL=1`, RB30 the sole failure, re-verified 3x consecutive against the pre-fix production files before Task 2 began). GREEN gate confirmed (commit d887a8f, suite `PASS=162 FAIL=0` on 2 consecutive runs). No REFACTOR commit was needed — the fix is a minimal statement reorder with no follow-up cleanup.

## Deviations from Plan

None — plan executed exactly as written. The only judgment call was verifying Task 1's "3 consecutive deterministic RED runs" criterion *after* Task 2 was already committed, by temporarily restoring the pre-fix `scripts/gemini_shim.sh` (the file `tests/run-tests.sh`'s `$SHIM` variable points at, and the one RB30 extracts its `run_bounded` block from) from the Task 1 commit, running the suite 3x, then restoring the committed fixed version via `git checkout HEAD -- scripts/gemini_shim.sh` and re-confirming a clean diff against `HEAD`. No commit history was altered; this was read-only verification against already-committed states.

## Issues Encountered

None.

## Next Phase Readiness

- delegate-agy-sup (D-08) and the `delegate-agy-tmm` epic remain open by design — final closure is deferred to plan 06-06's release-gate dossier, which assembles the full v1.6.2 sign-off across all six plans in this phase.
- Task-level tickets `delegate-agy-tmm.1` and `delegate-agy-tmm.2` are closed with commit references.
- Ready to proceed to plan 06-02.

---
*Phase: 06-ship-1-6-2*
*Plan: 01*
*Completed: 2026-08-22*

## Self-Check: PASSED
