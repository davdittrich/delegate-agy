---
phase: 06-ship-1-6-2
plan: 05
subsystem: docs
tags: [changelog, release-gate, verification, bash]

requires:
  - phase: 06-ship-1-6-2 (plans 01, 03, 04)
    provides: RB30 trap-restore fix, D-04/D-07 flag-eating and zero-byte-fetch fixes, IN02/CC03-widening structural test guards — all on master before this plan ran
provides:
  - Content proof that a001d0e's revert of fix/agy-bridge-resilience is fully undone on master, verified by grep, not by git log
  - Finished ### 1.6.2 README changelog: re-run notice plus six new bullets (five fixes, one investigation-closure note) closing D-09
affects: [06-06-ship-gate]

actuals:
  tokens: 1030
  tasks: 2
  commits: 1

tech-stack:
  added: []
  patterns: []

key-files:
  created:
    - .planning/phases/06-ship-1-6-2/deferred-items.md
  modified:
    - README.md

key-decisions:
  - "D-09's ambiguous 'six newly-fixed items' (parenthetical names only four) resolved as five fix bullets (ltf/SH16, u1z/R9f, d4t/trap-preservation, b7g/contract-check-scan-coverage, plus the SIGPIPE herestring guard) plus one closure-note bullet (xfa/i43), matching the locked count of six exactly."
  - "CC03/CC03m's pre-existing FAIL=2 is documented and blocker-tracked (delegate-agy-nko), not fixed in this plan — tests/run-tests.sh is outside 06-05's files_modified (README.md only), and the regression predates this plan (confirmed at 06-04's completion commit via git-worktree bisection)."

requirements-completed: []

coverage:
  - id: D1
    description: "Criterion 2 (a001d0e content-revert is undone) proven by content grep over the working tree, not git log"
    verification:
      - kind: other
        ref: "self-contained bash script, Task 1 — full output below"
        status: pass
    human_judgment: false
  - id: D2
    description: "### 1.6.2 changelog finished: re-run notice + six new bullets, D-09's ambiguous count resolved"
    verification:
      - kind: unit
        ref: "sed -n '/^### 1\\.6\\.2$/,/^### 1\\.6\\.1$/p' README.md | grep -c '^- ' == 12"
        status: pass
      - kind: unit
        ref: "tests/run-tests.sh CC05 (README's dated --model fact matches captured fixture)"
        status: pass
    human_judgment: false

duration: 40min
completed: 2026-08-22
status: complete
---

# Phase 06 Plan 05: Criterion-2 verification and 1.6.2 changelog completion Summary

**Proved by content grep (not git log) that `a001d0e`'s revert is fully undone on `master`, and finished the `### 1.6.2` changelog with a re-run notice and six new bullets — surfaced a pre-existing, out-of-scope test regression (CC03/CC03m) in the process, now blocker-tracked for plan 06-06.**

## Performance

- **Duration:** ~40 min (includes two full `tests/run-tests.sh` runs, ~3.5 min each, and a git-worktree bisection run)
- **Started:** 2026-08-22T00:26:00Z (approx.)
- **Completed:** 2026-08-22T00:46:41Z
- **Tasks:** 2/2 completed
- **Files modified:** 1 (`README.md`)

## Accomplishments

- Task 1: ran the full seven-item criterion-2 verification script; all seven pieces `a001d0e` removed are proven present on `master` by content (not line number), ancestry confirmed, no file changed.
- Task 2: extended `### 1.6.2` with a re-run-the-installer notice and six new bullets (five fixes + one investigation-closure note), resolving D-09's ambiguous "six" count on the record; bullet count verified at exactly 12; no ticket identifiers leaked into the public changelog.
- Surfaced (did not fix, per scope boundary): `tests/run-tests.sh`'s `CC03`/`CC03m` cases fail on `master`, pre-existing since 06-04's completion commit — confirmed via `git worktree` bisection, documented, ticketed (`delegate-agy-nko`), and recorded as a blocker for plan 06-06.

## Task Commits

1. **Task 1: Prove the a001d0e content revert is undone by reading files, not history** — read-only verification, no file changed, no commit (per the task's own reversibility note: "no file is written outside this plan's SUMMARY").
2. **Task 2: D-09 — finish the 1.6.2 release notes** - `d22083e` (docs)

**Plan metadata:** (this commit, made alongside STATE.md/ROADMAP.md below)

## Files Created/Modified

- `README.md` - Added a re-run-the-installer notice and six new bullets to the `### 1.6.2` changelog section (lines 407-422)
- `.planning/phases/06-ship-1-6-2/deferred-items.md` - New; records the CC03/CC03m pre-existing regression found during this plan's own verification step, out of scope to fix here

## Decisions Made

- D-09's "six newly-fixed items" resolved as five fix bullets plus one closure-note bullet (not four fixes as the parenthetical literally names) — the fifth fix is the trap-preservation race (`sup`), discussed under D-08 but omitted from D-09's own parenthetical list.
- README's `agy 1.1.13` version citation intentionally left un-bumped (a dated record of a specific verification run, not a claim about current agy version); flagged as deferred, not fixed, per the plan's own `<action>` guidance.

## Deviations from Plan

### Out-of-scope pre-existing regression documented, not fixed

**1. [Scope boundary — not a deviation rule 1-3 fix] CC03/CC03m fail on `master`**

- **Found during:** Plan-level `<verification>` item 4 (`bash tests/run-tests.sh 2>&1 | tail -3` must report `FAIL=0`). Actual: `PASS=163 FAIL=2`.
- **Root cause (hypothesis, not confirmed by editing the file):** `CC03`'s self-referential scan of `tests/run-tests.sh` flags any occurrence of `$CONTRACT_CHECK`/`contract-check.sh` outside three exemptions (`_run_sanitized` prefix, `_rb_extract` substring, full-replacement `PATH=`). Plan 06-04's RB01 widening added `"$CONTRACT_CHECK"` to the pre-existing `for _rb01_f in "$BRIDGE" "$SHIM" "$CONTRACT_CHECK"; do` loop at `tests/run-tests.sh:2494` — a static file-list, not an invocation — which matches none of the three exemptions. `CC03m`'s `commented:false_positive(1/4)` result additionally suggests one of its five self-test probes is not cleared by comment-stripping.
- **Confirmed pre-existing:** `git worktree add` at `1c114d3` (06-04's completion commit, parent of this plan's only commit) reproduced the identical `PASS=163 FAIL=2` with the same two failing case names, in isolation, before any of this plan's changes existed.
- **Why not fixed here:** `tests/run-tests.sh` is outside plan 06-05's `files_modified: [README.md]`. Plan 06-04, which introduced the regression, is already committed and summarized complete; fixing it here would be scope creep into another plan's territory (and would touch a file this plan's own acceptance criteria never asked to be touched).
- **Disposition:** Documented in `.planning/phases/06-ship-1-6-2/deferred-items.md`, recorded in `.planning/WINDOWS.md` (entry id 6, kind `deviation`), filed as beads issue `delegate-agy-nko` (P1), and added to `.planning/STATE.md`'s blockers. This blocks plan 06-06's ship gate, which requires `bash tests/run-tests.sh` to report `FAIL=0` against a clean clone — it must be fixed before 06-06 runs.
- **Files not modified:** `tests/run-tests.sh`
- **Commit:** N/A — no fix was made

---

**Total deviations:** 0 auto-fixed; 1 out-of-scope finding surfaced and documented per the scope-boundary rule.
**Impact on plan:** Both of this plan's own tasks completed and pass their own acceptance criteria in full. The plan-level `<verification>` item 4 (full-suite `FAIL=0`) does not hold, but for a reason confirmed unrelated to this plan's changes. This plan does not claim `<verification>` item 4 is satisfied — it is explicitly flagged as an open blocker for 06-06.

## Issues Encountered

`bash tests/run-tests.sh` took ~3.5 minutes per run (89+ test cases, several involving multi-second timeout/kill-after escalations) — ran twice on `master` plus once in the bisection worktree. No other issues.

## Criterion-2 Verification Evidence (Task 1)

### Ancestry check

```
$ git merge-base --is-ancestor fix/agy-bridge-resilience master; echo $?
0
```

### `a001d0e`'s touched files (must be exactly these three; `gemini_shim.sh` deliberately absent — its bounding was fixed independently in Phase 1 under R11 and was never on the reverted branch)

```
$ git show --stat a001d0e -- scripts/ README.md
commit a001d0e857c064ca8534bc6610417e6cdfcfa47e
Author: Dennis Alexis Valin Dittrich <dd+github@dr-dittrich.de>
Date:   Tue Aug 18 22:27:06 2026 +0200

    revert: hold 1.6.2 until the follow-up tickets are done

    Reverts the ten commits of the agy-bridge resilience branch from master.
    The work itself is sound -- both suites pass and the whole-branch review
    cleared it -- but it is being held so the follow-ups it surfaced land first.

    Chief among them: gemini_shim.sh still calls agy with no timeout at all, and
    that shim shadows the real `gemini` for every caller on PATH. Releasing a
    "no longer hangs" version while the wider-blast-radius call site still hangs
    would misrepresent what the release fixes.

    The branch fix/agy-bridge-resilience retains every commit; this revert is a
    hold, not a discard.

 README.md             | 36 ++++++---------------
 scripts/agy_bridge.sh | 69 ++++++---------------------------------
 scripts/install.sh    | 90 +++++++++++++++++----------------------------------
 3 files changed, 47 insertions(+), 148 deletions(-)
```

### Per-item content check (all seven pieces present on `master` — full script output)

```
1. AGY_MODELS_TIMEOUT default + positive-integer validation guard:  count=1  -> PASS
2. run_bounded "$AGY_MODELS_TIMEOUT" 3 --  (model-fetch kill-after 3):        count=1  -> PASS
3. run_bounded "$TIMEOUT" 5 --  (delegation kill-after 5):                    count=1  -> PASS
4. "AGY_MODELS_TIMEOUT must be a positive integer" text:                      count=1  -> PASS
5. degraded-list "no 'gemini-' ids" text (expect >=3: warning, R9 error, D-07 reuse): count=3  -> PASS
6. external-kill arm  "$EXIT_CODE" -eq 137 && "$DURATION" -lt "$TIMEOUT":     count=1  -> PASS
7. timeout-normalization arm  "$EXIT_CODE" -eq 124 || "$EXIT_CODE" -eq 137:   count=1  -> PASS
8. arm ordering: external-kill arm line < timeout-normalization arm line:     PASS (external-kill precedes normalization)
9. install.sh stale-pin exit 127 (expect >=2 sites):                         count=3  -> PASS
10. README installed_plugins.json two-step install prose (expect >=1):       count=2  -> PASS

VERDICT: PASS -- all seven pieces (items 1-10 above map onto them) confirmed present on master by content, not by git log.
```

Combined verify-block command run verbatim (exit 0, confirming the full chain):

```
$ git merge-base --is-ancestor fix/agy-bridge-resilience master && \
  grep -cE '^\[\[ "\$AGY_MODELS_TIMEOUT" =~|AGY_MODELS_TIMEOUT" =~' scripts/agy_bridge.sh && \
  grep -cF 'run_bounded "$AGY_MODELS_TIMEOUT" 3 --' scripts/agy_bridge.sh && \
  grep -cF 'run_bounded "$TIMEOUT" 5 --' scripts/agy_bridge.sh && \
  grep -cF "no 'gemini-' ids" scripts/agy_bridge.sh && \
  grep -cF '"$EXIT_CODE" -eq 137 && "$DURATION" -lt "$TIMEOUT"' scripts/agy_bridge.sh && \
  grep -cF '"$EXIT_CODE" -eq 124 || "$EXIT_CODE" -eq 137' scripts/agy_bridge.sh && \
  test "$(grep -nF '"$EXIT_CODE" -eq 137 && "$DURATION" -lt "$TIMEOUT"' scripts/agy_bridge.sh | cut -d: -f1)" -lt \
       "$(grep -nF '"$EXIT_CODE" -eq 124 || "$EXIT_CODE" -eq 137' scripts/agy_bridge.sh | cut -d: -f1)" && \
  grep -c 'exit 127' scripts/install.sh && \
  grep -cF 'installed_plugins.json' README.md
1
1
1
3
1
1
3
2
EXIT=0
```

## D-09 Bullet-Count Resolution (Task 2)

`### 1.6.2` bullet count verified: `sed -n '/^### 1\.6\.2$/,/^### 1\.6\.1$/p' README.md | grep -c '^- '` → `12` (six pre-existing + six new). Ticket-identifier check: `grep -c 'delegate-agy-'` over the same range → `0`. Required substrings each match at least once: `--flag=value`, `SIGPIPE`, `contract-check`, `TERM`, `unauthenticated` — all confirmed present.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Both of this plan's deliverables are complete and independently verified. Plan 06-06 (the release gate) is **not** clear to proceed yet: `tests/run-tests.sh` reports `FAIL=2` (`CC03`, `CC03m`) on `master`, a pre-existing regression from 06-04 unrelated to this plan's changes, tracked as beads issue `delegate-agy-nko` and recorded in `.planning/WINDOWS.md` (entry 6) and `.planning/STATE.md`'s blockers. This must be resolved (either fix the exemption gap in `tests/run-tests.sh`'s `CC03` scan or fix the underlying RB01 reference it flags) before 06-06's `FAIL=0` gate can pass.

---
*Phase: 06-ship-1-6-2*
*Completed: 2026-08-22*

## Self-Check: PASSED

- FOUND: `README.md`
- FOUND: `.planning/phases/06-ship-1-6-2/deferred-items.md`
- FOUND: commit `d22083e` in `git log --oneline --all`
