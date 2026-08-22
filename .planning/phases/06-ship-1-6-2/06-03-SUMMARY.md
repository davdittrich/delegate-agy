---
phase: 06-ship-1-6-2
plan: 03
subsystem: cli-flag-parsing-and-model-fetch
tags: [bash, gemini-shim, agy-bridge, tdd, fake-agy]

# Dependency graph
requires:
  - phase: 06-ship-1-6-2
    plan: 01
    provides: trap-restore-window fix (RB30) and reordered watchdog arm this plan's full-suite runs verify against
provides:
  - "D-04 fix: gemini_shim.sh's unrecognized-long-flag catch-all shifts exactly once (SH16)"
  - "D-07 fix: agy_bridge.sh reports the degraded/unauthenticated diagnostic on a zero-byte no-cache fetch, not the generic fetch-failure message (R9f)"
  - "FAKE_AGY_MODELS_EMPTY mode in tests/fake-agy.sh — the fixture that reproduces a truly empty (zero-byte) agy models reply"
affects: [06-06-release-gate]

# Actuals (#2632) — chars/4 over the realized diff (git diff bd30e06..406114a)
actuals:
  tokens: 3430
  tasks: 2
  commits: 5

# Tech tracking
tech-stack:
  added: []
  patterns: ["reuse an existing verbatim diagnostic message at a second call site rather than inventing a third message for a closely-related failure mode"]

key-files:
  created: []
  modified:
    - scripts/gemini_shim.sh
    - scripts/agy_bridge.sh
    - tests/run-tests.sh
    - tests/fake-agy.sh

key-decisions:
  - "D-04's allowlist carve-out has zero members: every value-taking flag (-m/--model, -o/--output-format, --approval-mode, --include-directories, -p) already has its own explicit case arm before the catch-all, and bash's first-match case semantics mean none of them can ever reach it. Re-verified against the current file before shipping the bare single shift — no allowlist array was built."
  - "D-07's exit stays deferred to the pre-existing choke point (the VALID_MODELS-empty bail) rather than raised inside the fetch block, because an exit there would skip the unconditional agy-stderr passthrough two lines below it."
  - "D-07 reuses R9's exact degraded-message text verbatim at the new no-cache call site rather than inventing a third message, per the plan's explicit instruction — this is a deliberate two-site duplication, not an oversight."
  - "FAKE_AGY_MODELS_GARBAGE (pre-existing) writes non-empty garbage text and cannot reproduce D-07: it already reaches the bridge's downstream gemini--less check further down the file. FAKE_AGY_MODELS_EMPTY is a new, distinct fixture mode because the bug only fires on a genuinely empty ($_agy_models=\"\") reply."
  - "EC06 (Phase 3's pinned literal-count regression test) hard-coded 'exactly once' for the degraded-list message in agy_bridge.sh. D-07's verbatim reuse legitimately makes that two. Fixed EC06's expected count from 1 to 2 rather than inventing a distinct message to keep EC06 unmodified — the plan's own acceptance criteria already specified the verbatim-reuse design, so EC06's invariant was the stale side of the conflict, not the production code."

patterns-established:
  - "When a pre-existing pinned literal-count test conflicts with a plan's explicit, reviewed design decision to reuse a message verbatim at a new call site, update the stale test invariant rather than fork the message text."

requirements-completed: [S3, R6, S1]

coverage:
  - id: D-04
    description: "SH16: an unrecognized long flag (e.g. --froboz) no longer eats the prompt token that follows it; a genuinely value-taking flag in long form is unaffected; the inline --flag=value form for an unknown flag is still consumed as one token"
    requirement: "S3"
    verification:
      - kind: unit
        ref: "tests/run-tests.sh SH16 (pre-fix: FAIL, rc=2, prompt token missing; post-fix: PASS)"
        status: pass
    human_judgment: false
  - id: D-07
    description: "R9f: a successful zero-byte agy models fetch with no cache reports the degraded/unauthenticated diagnostic instead of the generic fetch-failure message; exit code stays 2; agy's own stderr still reaches the user via the passthrough; the cache file stays untouched; a good stale cache still falls back and succeeds (regression guard)"
    requirement: "S1, R6"
    verification:
      - kind: unit
        ref: "tests/run-tests.sh R9f (pre-fix: FAIL, generic message shown, sentinel confirmed present proving the fixture wiring was already reaching the code path; post-fix: PASS)"
        status: pass
    human_judgment: false

# Metrics
duration: ~50min
completed: 2026-08-22
status: complete
---

# Phase 06 Plan 03: Flag-eating and zero-byte-fetch fixes Summary

**Two one-branch behavioral fixes, each proven test-first: `gemini --froboz "prompt"` no longer silently drops the prompt (D-04), and a successful-but-empty `agy models` fetch with no cache now reports the degraded/unauthenticated diagnostic instead of a generic, less-actionable failure message (D-07) — plus one incidental fix to a Phase 3 regression test whose "exactly once" literal-count assumption D-07's design intentionally breaks.**

## Performance

- **Duration:** ~50 min
- **Tasks completed:** 2/2
- **Files changed:** 4
- **Commits:** 5

## Accomplishments

- **D-04 (`delegate-agy-ltf`, `scripts/gemini_shim.sh`):** the unrecognized-long-flag catch-all arm (`--[a-z]*)`) conditionally shifted twice whenever the token following an unknown flag did not itself look like a flag, silently consuming a user's own prompt (`gemini --froboz "write me a haiku"` lost the prompt entirely). Changed to a bare single shift, matching its `--no-*` and `-*` sibling arms exactly. Re-verified the zero-member allowlist claim against the current file: every value-taking flag (`-m`/`--model`, `-o`/`--output-format`, `--approval-mode`, `--include-directories`, `-p`) already has its own explicit `case` arm earlier in the statement, so bash's first-match semantics mean none can ever reach the catch-all — no allowlist array was built. New `SH16` case (three assertions in one `ok`/`bad` pair): the prompt survives an unrecognized long flag (verified via `FAKE_AGY_ECHO_PROMPT`, since the prompt is embedded in `GEMINI.md`, never passed as agy argv); `--model pro` in long form is unaffected (verified via `FAKE_AGY_DUMP_ARGV`, resolving deterministically to `gemini-3.1-pro-high`); the inline `--flag=value` form for an unknown flag is consumed as one token and does not leak into the prompt.
- **D-07 (`delegate-agy-b7g`, `scripts/agy_bridge.sh`):** a fetch that succeeds (`rc=0`) but returns zero bytes, with no cache file present, matched neither the write arm nor the stale-cache-fallback arm of the fetch `if/elif` and fell through untouched, leaving `VALID_MODELS` empty and hitting the generic `"failed to retrieve model list from agy"` bail instead of the far more actionable degraded-list message. Added a new `else` arm that sets `_agy_degraded_no_cache=1` (no exit inside the fetch block, so the unconditional agy-stderr passthrough two lines below still runs), then rewrote the single-line bail into a block that branches on that flag (read via the `set -u`-safe `${_agy_degraded_no_cache:-0}` form) to choose between R9's exact degraded-message text, reused verbatim, and the pre-existing generic message. Same exit code (2), cache file still untouched on this path.
- New `FAKE_AGY_MODELS_EMPTY` mode in `tests/fake-agy.sh`: exits 0 having written zero bytes to stdout, while honoring `FAKE_AGY_STDERR` (the same guarded one-liner already used at the two pre-existing delegation-path emission sites). This is deliberately a new, distinct fixture from `FAKE_AGY_MODELS_GARBAGE`: the garbage mode writes non-empty text that already reaches the bridge's *downstream* gemini-less check further into the file, so it cannot reproduce D-07 — only a genuinely empty `$_agy_models` falls through the fetch block's `if/elif` untouched. Because the bridge's zero-byte-fetch exit happens during model discovery, before any delegation ever runs, this is the only place that can put agy's own stderr on that code path; without this extension R9f's stderr-passthrough assertion would have been vacuous.
- New `R9f` case: absent-cache half asserts exit 2, the degraded message present, the generic message absent, agy's own stderr reaching the user through the `       agy: ` passthrough marker (proven non-vacuous — the RED run already showed the sentinel, confirming the fixture wiring reaches this path unaided by any production change), and the cache file still not created. A same-case regression guard confirms a good stale cache still lets a zero-byte reply fall back and succeed (this half was already green before the fix, proving the new `else` arm did not steal the pre-existing cache-fallback path).
- **Incidental fix, in scope:** `EC06` (a Phase 3 regression test) pinned the degraded-list message literal to occur exactly once in `scripts/agy_bridge.sh`. D-07's design — explicitly specified in this plan's own acceptance criteria — reuses that exact text verbatim at the new no-cache call site, legitimately making the count two. Updated EC06's expectation from 1 to 2 rather than inventing a third message to preserve EC06 unmodified; the plan's acceptance criteria, not EC06, reflected the intended design.

## TDD Gate Compliance

Both tasks used task-level TDD (`tdd="true"`), each with its own RED→GREEN cycle in the single shared `tests/run-tests.sh` harness:

- **Task 1 (SH16/D-04):** RED commit `c6b3d68` (quoted failing line: `rc=2 (want 0) for --froboz TOKEN; prompt token missing after unrecognized flag, out=;`), GREEN commit `6e79225`.
- **Task 2 (R9f/D-07):** RED commit `cbe80f1` (quoted failing detail, including the `agy: ` sentinel proving the fixture wiring was already reaching the code path pre-fix), GREEN commit `aecc234`.
- Incidental EC06 fix commit `406114a` (not part of either task's TDD cycle — a stale pre-existing test invariant, fixed after the full suite surfaced it).

No REFACTOR commits were needed for either task — both fixes were minimal, single-branch changes with no follow-up cleanup.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - stale test invariant] EC06's "exactly once" degraded-literal count needed updating to "exactly two"**
- **Found during:** full-suite verification after Task 2's GREEN commit (first full run: `PASS=163 FAIL=1`, sole failure `EC06`).
- **Issue:** `EC06` (introduced in Phase 3, `delegate-agy-6q1`) statically pinned the count of the degraded-list message literal (`"agy model list contains no 'gemini-' ids; agy may be unauthenticated"`) in `scripts/agy_bridge.sh` to exactly 1, comment-filtered. D-07's fix — per this plan's own acceptance criteria (`grep -cF "..." scripts/agy_bridge.sh` outputs `2`) — deliberately reuses that exact text verbatim at the new no-cache bail, making the true count 2. EC06's assumption predates and conflicts with this plan's explicitly reviewed design; it was the stale side of the conflict, not the production code.
- **Fix:** Changed EC06's expected count from `1` to `2` for the bridge, with a comment explaining both legitimate call sites.
- **Files modified:** `tests/run-tests.sh`.
- **Commit:** `406114a`.

No other deviations — both tasks executed exactly as specified.

## Issues Encountered

None outstanding. Full suite: `PASS=164 FAIL=0` (confirmed on a full run after the EC06 fix).

## Next Phase Readiness

- `delegate-agy-ltf` (D-04) and `delegate-agy-b7g` (D-07) remain open by design — per this plan's own success criteria, final ticket closure is deferred to plan 06-06's release-gate dossier, which assembles the full v1.6.2 sign-off across all six plans in this phase.
- Task-level tickets `delegate-agy-tmm.5` and `delegate-agy-tmm.6` are closed, each with a comment recording the RED/GREEN commit hashes.
- Ready to proceed to plan 06-04.

---
*Phase: 06-ship-1-6-2*
*Plan: 03*
*Completed: 2026-08-22*

## Self-Check: PASSED

All 4 claimed modified files found on disk. All 5 claimed commit hashes (c6b3d68, 6e79225, cbe80f1, aecc234, 406114a) found in git log. Full suite re-run confirmed PASS=164 FAIL=0.
