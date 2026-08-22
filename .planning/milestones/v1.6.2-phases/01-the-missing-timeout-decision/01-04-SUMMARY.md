---
phase: 01-the-missing-timeout-decision
plan: 04
subsystem: docs
tags: [bash, coreutils, timeout, run_bounded, documentation]

requires:
  - phase: 01-the-missing-timeout-decision
    provides: "run_bounded in both scripts (plans 01-01 through 01-03) — the shipped behaviour this plan writes down"
provides:
  - "README section stating both entry points' missing-binary behaviour together, with the reason they no longer differ"
  - "README troubleshooting row keyed on the warning the scripts actually emit, replacing one keyed on a deleted fatal"
  - "PROJECT.md Key Decisions row recording *always bounded*, superseding the shim-degrades/bridge-fails row"
  - "REQUIREMENTS.md R11 acceptance restated as the tightened invariant with no permitted-fallback clause"
  - "resolution note on delegate-agy-cy5 recording that none of its three candidate designs was selected"
affects: [01-05, 01-06, phase-3-exit-codes, phase-6-ship]

actuals:
  tokens: 3400
  tasks: 3
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Documented literals are copied out of the script that defines them, never retyped — plan 01-05's RB03 diffs them"

key-files:
  created: []
  modified:
    - .worktrees/agy-1.6.2/README.md
    - .planning/PROJECT.md
    - .planning/REQUIREMENTS.md

key-decisions:
  - "Recorded decision is *always bounded* — none of delegate-agy-cy5's three candidate designs; the premise that a missing binary forces a tradeoff was rejected"
  - "coreutils demoted from dependency to recommendation in README and PROJECT.md Constraints; what it buys is process-group kill, not the bound"
  - "PROJECT.md Out of Scope restated around the ceiling that actually remains (direct-process kill where job control cannot isolate the child) rather than deleted"
  - "R11's acceptance and coverage cell rewritten here, not deferred to 01-05 — 01-05 keeps only RB01/RB03 test work"

patterns-established:
  - "Ceiling labelling: a documented simplification names the guarantee it trades away (watchdog vs process-group kill) rather than leaving it silent"

requirements-completed: []

coverage:
  - id: D1
    description: "README states both entry points' behaviour on a host with no bounding binary, together and with the reason"
    requirement: R11
    verification:
      - kind: manual_procedural
        ref: "01-VALIDATION.md § Manual-Only Verifications — criterion-3 reading check"
        status: unknown
    human_judgment: true
    rationale: "Phase criterion 3 is a reading check: whether a reader finds both behaviours side by side is judgment, not a grep."
  - id: D2
    description: "Both script literals quoted verbatim in README; the unreachable ERROR row replaced by the warning now emitted"
    requirement: R11
    verification:
      - kind: unit
        ref: "tests/run-tests.sh RB03 (plan 01-05, not yet written)"
        status: unknown
      - kind: other
        ref: "sed-extracted literals from both scripts diffed against README lines (grep -x -F -f) — matched"
        status: pass
    human_judgment: false
  - id: D3
    description: "PROJECT.md Key Decisions records *always bounded* with rationale; superseded rows resolved"
    requirement: R11
    verification:
      - kind: other
        ref: "plan 01-04 Task 2 <verify> automated block — PLANNING_DOCS_OK"
        status: pass
    human_judgment: true
    rationale: "Phase criterion 1 asks whether the rationale is adequate, which no grep decides."
  - id: D4
    description: "delegate-agy-cy5 carries a resolution note saying none of its three designs was chosen, and stays open"
    verification:
      - kind: other
        ref: "bd show delegate-agy-cy5 | grep -iE 'none of the (three|3)' — TICKET_NOTE_RECORDED"
        status: pass
    human_judgment: false

duration: 18min
completed: 2026-08-19
status: complete
---

# Phase 01 Plan 04: Record the decision Summary

**The always-bounded decision is now written down where it is read: README states both entry points' missing-binary behaviour together with the two literals the scripts print, PROJECT.md's Key Decisions carries the decision and supersedes the divergence row, and R11 no longer asserts the opposite of what shipped.**

## Performance

- **Duration:** ~18 min
- **Started:** 2026-08-19T10:00Z (approx.)
- **Completed:** 2026-08-19T10:18Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments

- README's three `… unbounded regardless of this value` sentences are gone; the word `unbounded` no longer occurs in the file at all. Each row now says the bound holds either way and points at one place that explains which mechanism enforces it.
- New `#### Bounding without timeout/gtimeout` section directly under the environment-variable table: a two-row table giving `agy-bridge` and the `gemini` shim side by side (identical in both columns), the reason they no longer differ (a refusal to start is the same failure as a hang, moved one step earlier), and both script literals in fenced blocks.
- The troubleshooting row keyed on `ERROR: timeout/gtimeout not found in PATH` — a string neither script can emit any more — is replaced by one keyed on the warning they do emit, whose remedy is the same coreutils advice and whose explanation says the call is still bounded.
- `timeout`/`gtimeout` demoted from Requirements to a recommendation in README and from Dependencies to optional in PROJECT.md Constraints, both naming what it buys.
- PROJECT.md: new Key Decisions row for *always bounded*; the shim-degrades/bridge-fails row marked `✗ Superseded` rather than left at `⚠️ Revisit`; the Out of Scope entry restated around the real remaining ceiling.
- REQUIREMENTS.md R11: acceptance tightened to "every `"$AGY_BIN"` occurrence is an argument to `run_bounded` — no permitted-fallback clause and no exceptions", plus the runtime proof; the open-question line replaced by the decision with a pointer to PROJECT.md.
- `delegate-agy-cy5` carries the resolution note and remains open, as the plan requires.

## Task Commits

1. **Task 1: Rewrite README** — `6cf6f57` (docs) — on `fix/agy-bridge-resilience`, in `/home/dd/Gemini/delegate-agy/.worktrees/agy-1.6.2`
2. **Task 2: PROJECT.md + REQUIREMENTS.md** — `9c5bd8a` (docs) — on `master`, in `/home/dd/Gemini/delegate-agy`
3. **Task 3: ticket resolution** — no commit; the artifact is a `bd comments add` on `delegate-agy-cy5`

## Files Created/Modified

- `.worktrees/agy-1.6.2/README.md` — env-var rows, new bounding section, troubleshooting row, Requirements/Installation, one changelog clause (+33 −7)
- `.planning/PROJECT.md` — Key Decisions (2 rows), Out of Scope, Constraints, R11's Active bullet (+5 −4)
- `.planning/REQUIREMENTS.md` — R11 statement, acceptance, decision line, traceability cell (+4 −4)

## Decisions Made

- **The recorded decision is `always bounded`, not one of the three candidates.** Written in PROJECT.md's own compressed voice: each of (a) hard-fail, (b) degrade-with-warning, (c) refuse-delegation-only accepts either a call with no bound or a caller broken at startup, and the core value forbids both — for a binary shadowing `gemini` box-wide, a refusal to start is the same failure as a hang, one step earlier. Bash bounds natively, so the premise was rejected rather than one of the answers chosen.
- **Out of Scope restated, not deleted.** The bullet now names the ceiling that genuinely remains: the watchdog reaps through job control, and where job control cannot give the child its own group it kills the direct process only, so something agy forked can survive. Deleting the bullet would have left that ceiling unrecorded in the project's own scope statement.
- **The word `unbounded` avoided even counterfactually in PROJECT.md/REQUIREMENTS.md.** Phrased as "a call with no bound" where a rejected alternative had to be described, so no grep over a planning doc can surface an apparent claim.
- **R11's prose rewritten here rather than deferred.** See the handoff note below.

## Handoff to plan 01-05 — what I rewrote vs what I left

Rewritten by this plan (01-05 must **not** re-edit these):

- `REQUIREMENTS.md` R11's opening statement (was "wrapped in `timeout` **with `-k`**").
- R11's acceptance line — the `"$TIMEOUT_BIN" -k …`-or-permitted-fallback formulation and its "unbounded **by documented decision**" clause are both gone, replaced by the `run_bounded`-argument invariant plus the runtime-proof clause.
- R11's open-question line ("Open question, not yet decided: the bridge treats a missing `timeout` binary as fatal while the shim degrades") — replaced by the decision and a pointer to PROJECT.md §Key Decisions.
- R11's Traceability cell, which previously said in so many words that *plan 01-05 owns rewording them*. That sentence is removed; the cell now attributes the rewording to 01-04 and scopes 01-05 to case RB01 and 01-06 to the runtime proof.

Deliberately left for 01-05:

- R11's `Evidence:` line still cites `tests/run-tests.sh R5/R6/R7, T4/T5, SH4/SH5/SH6`. The RB01–RB14 cases do not exist yet, so adding them would cite tests that cannot be run. 01-05 should add its own case ids there when they land.
- Reserved case ids `RB01`–`RB14` are untouched; this plan wrote no test.
- ROADMAP criterion 4's own wording (the "or sits in a `TIMEOUT_BIN`-empty fallback branch" clause) is left as-is. 01-CONTEXT.md line 127 already records that the criterion is satisfied *more strictly* than written, and my plan scoped me to PROJECT.md and REQUIREMENTS.md. If a later reader quotes criterion 4's fallback clause as licence for an exception, R11's acceptance now contradicts it in the stricter direction — flagged here rather than silently edited.

## Downstream pins for each claim written (TDD note)

`tdd_mode` is on but this plan ships documentation; no test was invented to satisfy the letter of TDD. Which downstream case pins what:

| Claim written | Pinned by |
|---|---|
| Both literals quoted byte-exactly in README | RB03 (plan 01-05) — compares README's quoted text against both scripts' constants |
| Both scripts define those constants identically | RB02 (plan 01-05) — block identity |
| Every `"$AGY_BIN"` is a `run_bounded` argument (R11 acceptance) | RB01 (plan 01-05) — static scan, zero exceptions |
| Nothing outlives its bound, per entry point, on both mechanisms | plan 01-06 runtime proof |

**Coverage gaps — claims nothing downstream pins:**

1. **The absence claim.** No planned case asserts that `unbounded` does *not* appear in README, nor that `ERROR: timeout/gtimeout not found in PATH` is absent from both scripts and the docs. RB03 pins presence of the new strings; a future edit could reintroduce a stale sentence beside them and the suite would stay green. A one-line negative grep would close this; 01-05 is the natural home.
2. **The side-by-side reading (phase criterion 3).** Genuinely judgment — 01-VALIDATION.md already lists it as a manual-only verification, so this is a known gap, not a new one.
3. **PROJECT.md / REQUIREMENTS.md content.** Nothing in the suite reads planning documents; the phase gate is a human reading them. Correct — a test asserting the prose of a decision record would pin wording, not behaviour.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 — Missing Critical] PROJECT.md Constraints still listed coreutils as a hard dependency**

- **Found during:** Task 2
- **Issue:** Line 69, `**Dependencies**: bash 4+, coreutils (`timeout`/`gtimeout`), `python3` 3.6+`, is a surviving document asserting pre-decision behaviour. The plan named only §Key Decisions and §Out of Scope, but the phase criterion is "no surviving document asserts the opposite", and PROJECT.md is read as authority by later phases.
- **Fix:** coreutils restated as optional, naming what it buys.
- **Files modified:** `.planning/PROJECT.md`
- **Verification:** `grep -n coreutils .planning/PROJECT.md` — the remaining mentions are the new decision row, the restated Out of Scope entry, and this line.
- **Committed in:** `9c5bd8a`

**2. [Rule 2 — Missing Critical] PROJECT.md's R11 Active bullet named `timeout -k` as the mechanism**

- **Found during:** Task 2
- **Issue:** `R11 — every `agy` invocation bounded with `timeout -k`` describes the pre-D-01 mechanism; on a coreutils-less host it is false.
- **Fix:** restated as bounded through `run_bounded` with or without a coreutils binary. Left unchecked — R11 is not complete until 01-05/01-06 land.
- **Files modified:** `.planning/PROJECT.md`
- **Verification:** part of the Task 2 verify block (`PLANNING_DOCS_OK`).
- **Committed in:** `9c5bd8a`

**3. [Rule 1 — Bug] README's 1.6.2 changelog asserted a mechanism that is now only half true**

- **Found during:** Task 1
- **Issue:** `Both agy invocations now escalate to SIGKILL: the model fetch via `timeout -k 3 $AGY_MODELS_TIMEOUT` … and the delegation call via `timeout -k 5 $TIMEOUT`` names coreutils as *the* mechanism. On a host with no bounding binary that sentence describes something that does not happen, in the changelog for the very release this phase ships.
- **Fix:** one clause rewritten — the bounds are stated by their numbers, and one added sentence names the shared helper and its two mechanisms. No new changelog bullet; the existing one was rewritten in place.
- **Files modified:** `.worktrees/agy-1.6.2/README.md`
- **Verification:** suite still `PASS=97 FAIL=0`; no exit-code row touched.
- **Committed in:** `6cf6f57`

---

**Total deviations:** 3 auto-fixed (2 missing-critical, 1 bug)
**Impact on plan:** All three are the same defect class the plan exists to remove — a surviving sentence asserting pre-decision behaviour — found one section over from where the plan pointed. No scope creep: no new sections, no new files, every fix a rewrite of an existing line.

## Issues Encountered

- **The plan's line numbers had drifted.** `README.md:233`, `:269-271` and `:43` were all still correct, but PROJECT.md's Out of Scope entry and REQUIREMENTS.md's R11 had been edited by 01-03's status-row update. Located by content, not by number.
- **Byte-exactness of the quoted literals was verified mechanically, not by eye:** both constants were `sed`-extracted from each script, `diff`ed between the two scripts (`SCRIPTS_AGREE`), then matched against README with `grep -x -F -f`. Each appears as an exact standalone line in a fenced block, and the warning also inside the troubleshooting row.

## Verification

- `bash tests/run-tests.sh` in the worktree: **`PASS=97 FAIL=0`** — baseline held.
- Task 1 verify block: `README_OK` (no `unbounded`; both literals present; old `ERROR:` string absent).
- Task 2 verify block: `PLANNING_DOCS_OK`.
- Task 3 verify: `TICKET_NOTE_RECORDED`; `bd show delegate-agy-cy5` still shows `OPEN`.
- No file under the main tree's `scripts/`, `tests/`, `docs/` or root `README.md` was touched — `git show --numstat 9c5bd8a` lists only the two planning documents.

## Self-Check: PASSED

- `.worktrees/agy-1.6.2/README.md` — FOUND, modified in `6cf6f57`
- `.planning/PROJECT.md` — FOUND, modified in `9c5bd8a`
- `.planning/REQUIREMENTS.md` — FOUND, modified in `9c5bd8a`
- Commit `6cf6f57` — FOUND on `fix/agy-bridge-resilience`
- Commit `9c5bd8a` — FOUND on `master`

## User Setup Required

None.

## Next Phase Readiness

- Wave 2 is complete. Plan 01-05 (Wave 3) is unblocked: the static scan RB01, block identity RB02 and the README literal comparison RB03 all now have their documentation counterpart in place to compare against.
- `delegate-agy-cy5` stays open by design until 01-05 and 01-06 prove the invariant; Phase 6's release gate checks it.
- Phase 3 note carried forward unchanged: exit 2 has lost its missing-binary cause, so its reachable-2 provocation list must not include `timeout/gtimeout not found`.

---
*Phase: 01-the-missing-timeout-decision*
*Completed: 2026-08-19*
