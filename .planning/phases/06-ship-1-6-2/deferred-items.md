# Deferred Items — Phase 06 (Ship 1.6.2)

Out-of-scope findings surfaced during plan execution but not fixed by the
surfacing plan, per the SCOPE BOUNDARY rule (only auto-fix issues directly
caused by the current task's own changes).

## From plan 06-05

**CC03/CC03m fail on `master`, pre-existing since 06-04's completion commit.**

- **Found during:** Task 2's plan-level `<verification>` item 4 (`bash
  tests/run-tests.sh 2>&1 | tail -3` must report `FAIL=0`). Actual result:
  `PASS=163 FAIL=2`.
- **Failing cases:**
  - `CC03 no case in the suite reaches a real agy through the check (isolation
    scan)` — `violations=1 production_occurrences=4 (floor >=1; exempt region
    excluded)`
  - `CC03m scan reports every injected shape, including one smuggled inside
    the exempt bracket, ignores a comment` — `detail=commented:false_positive
    (1/4)`
- **Confirmed pre-existing, not caused by plan 06-05:** `git worktree add`
  checked out `1c114d3` (06-04's completion commit, the parent of 06-05's
  only commit `d22083e`) into an isolated directory and re-ran
  `tests/run-tests.sh` there. Same two failures, same `PASS=163 FAIL=2`.
  Plan 06-05 touched only `README.md`; `CC05` (the test that gates README
  content against the pinned agy fixture) still passes on both trees.
- **Root-cause hypothesis (read-only investigation, no file changed):**
  `CC03`'s self-referential scan of `tests/run-tests.sh` treats any
  occurrence of `$CONTRACT_CHECK`/`contract-check.sh` outside a narrow
  exemption list (a `_run_sanitized` prefix, an `_rb_extract` substring, or a
  full-replacement `PATH=` assignment) as a violation. Plan 06-04's RB01
  widening added `"$CONTRACT_CHECK"` to the pre-existing `for _rb01_f in
  "$BRIDGE" "$SHIM" "$CONTRACT_CHECK"; do` loop at `tests/run-tests.sh:2494`
  — a static-analysis file-list, not an invocation reaching real agy — but
  that segment matches none of CC03's exemptions, so it is counted as a
  violation. `CC03m`'s "commented:false_positive(1/4)" result additionally
  indicates the comment-stripping step CC03 relies on does not fully clear
  one of its five self-test probes. Neither claim was verified by editing
  `tests/run-tests.sh` — that file is outside plan 06-05's `files_modified`
  (`README.md` only) — so this is a hypothesis for whoever picks up the fix,
  not a confirmed diagnosis.
- **Why not fixed here:** `tests/run-tests.sh` is not in plan 06-05's
  declared file scope. Plan 06-04, which introduced the regression, is
  already committed and summarized as complete; re-opening it from within
  06-05 would be scope creep into another plan's territory.
- **Blocking status:** Plan 06-06 (the release gate) requires `bash
  tests/run-tests.sh` to exit 0 with `FAIL=0` against a clean clone
  (06-06-PLAN.md task with the automated check `bash tests/run-tests.sh
  2>&1 | tail -3 && bash tests/hooks/run-hook-tests.sh 2>&1 | tail -3`).
  This regression will block that gate until fixed. Recorded in
  `.planning/WINDOWS.md` (entry id 6, kind `deviation`) and flagged as a
  blocker in `.planning/STATE.md`.
