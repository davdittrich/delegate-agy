---
phase: 05-the-shim-s-failure-mode-contract
plan: 01
subsystem: testing
tags: [bash, grep, contract-testing, readme-provenance]

requires:
  - phase: 03-the-exit-code-contract
    provides: "RB03/EC05/EC06 literal-pinning convention (expected bytes written verbatim in the test, counted inside a delimited window) that FM01 copies"
  - phase: 04-installer-and-launcher-surface
    provides: "I16 stale-pin fixture (shared write_wrapper() call sites for agy-bridge and gemini) that FM01's PIN anchor cites"
provides:
  - "FM01 test block in tests/run-tests.sh: table-scoped uniqueness + whole-file total counts for two failure-mode literals, per-row agy-bridge/gemini/because-or-identical shape checks, and a DATA-driven row-to-proof mapping (_FM_PAIRS) that fails if a row, its cited proof's ok/bad label, or the pair entry itself disappears"
  - "README's missing-dependency and superseded-pin Troubleshooting rows rewritten in place to name both agy-bridge and the gemini shim and state they behave identically, with a real reason"
affects: ["05-02 (extends FM01 with three more anchors and _FM_PAIRS entries)"]

actuals:
  tokens: 2879
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "FM01 follows RB03/EC05/EC06's literal-pinning shape: expected bytes written as literals in the test, never extracted from the file under assertion"
    - "Table-scoped counting via sed window + grep '^|' makes row-uniqueness satisfiable when the same literal legitimately appears a second time outside the table (README:308's fenced example)"
    - "Row-to-proof citation as DATA (_FM_PAIRS array of anchor_key:PROOF_ID) rather than a comment, with quote-agnostic label matching (^[[:space:]]*(ok|bad)[[:space:]]+[\"']ID[[:space:]])"

key-files:
  created: []
  modified:
    - "tests/run-tests.sh — FM01 block added after EC06, before EC07"
    - "README.md — missing-dependency row (:234) and superseded-pin row (:226) rewritten in place"

key-decisions:
  - "FM01 counts row occurrences inside a Troubleshooting-table window (sed between '## Troubleshooting' and '### Running the tests', then grep '^|'), not over the whole file, because the missing-dependency literal legitimately appears a second time in README's fenced example at :308 and must survive"
  - "Row-to-proof mapping is machine-checked data (_FM_PAIRS), not a comment, so deleting a row, its proof's label, or the pair entry itself each fail the suite instead of silently unbinding a claim from its evidence"
  - "S3 is not marked complete in this plan's state update: the plan's own Multi-Source Coverage Audit states S3 'closed in 05-02 T3', so requirements mark-complete was NOT run for S3 here — it stays open until 05-02 lands the remaining three rows"

patterns-established:
  - "FM01's ceiling is stated in its own leading comment: the agy-bridge/gemini/because-or-identical row check proves a rationale clause is PRESENT, never that it is TRUE. Truth is judged by a <human-check> or a human read-through, never by grep."

requirements-completed: []

coverage:
  - id: D1
    description: "FM01 pins the missing-dependency Troubleshooting row's shape (table-scoped uniqueness=1, whole-file total=2, agy-bridge+gemini+because/identical present) and the row is rewritten to state agy-bridge and the gemini shim behave identically because both carry byte-identical copies of run_bounded (RB02)"
    requirement: S3
    verification:
      - kind: unit
        ref: "tests/run-tests.sh FM01 (DEP anchor) — bash tests/run-tests.sh, PASS=161 FAIL=0"
        status: pass
    human_judgment: true
    rationale: "FM01 proves row SHAPE only — it cannot judge whether the stated reason is true. Truth was judged by the plan's <human-check>: verdict recorded below."
  - id: D2
    description: "FM01 extended with the superseded-pin anchor pinned against scripts/install.sh, plus a DATA-driven row-to-proof mapping (_FM_PAIRS: DEP:RB03, DEP:RB02, PIN:I16) that fails on a deleted row, a deleted proof label, or a deleted pair entry; the superseded-pin row is rewritten to cite the shared write_wrapper() implementation (I16)"
    requirement: S3
    verification:
      - kind: unit
        ref: "tests/run-tests.sh FM01 (PIN anchor + _FM_PAIRS) — bash tests/run-tests.sh, PASS=161 FAIL=0"
        status: pass
    human_judgment: true
    rationale: "Same shape-only ceiling as D1. The write_wrapper() rationale's truth is deferred to 05-02 Task 3's read-through per the plan's stated ceiling, since Task 2 carries no separate <human-check> of its own."

duration: 68min
completed: 2026-08-21
status: complete
---

# Phase 5 Plan 01: Failure-mode contract shape for the two identical rows Summary

**A new `FM01` test block pins README's missing-dependency and superseded-pin Troubleshooting rows to a machine-checked shape (both entry points named, a real reason stated) and to their proofs (RB02, RB03, I16) via a data-driven citation array, so neither row can drift silently.**

## Performance

- **Duration:** ~68 min (dominated by full-suite runs: baseline + 2 RED/GREEN cycles + 3 mutation demonstrations, each a ~2.5 min, 161-test run)
- **Completed:** 2026-08-21T19:48:54+02:00
- **Tasks:** 2/2 completed
- **Files modified:** 2 (`tests/run-tests.sh`, `README.md`)

## Accomplishments

- Added `FM01` to `tests/run-tests.sh`, pinning the missing-dependency row's shape end-to-end (RED observed before the README edit, GREEN after)
- Extended `FM01` with the superseded-pin anchor, a static pin against `scripts/install.sh`'s refusal message, and a `_FM_PAIRS` array that turns the row-to-proof mapping from a comment into asserted data
- Rewrote both README rows in place, naming `agy-bridge` and the `gemini` shim explicitly and stating a real reason for their sameness (byte-identical `run_bounded` copies; shared `write_wrapper()` implementation)
- Demonstrated and reverted three deliberate mutations to prove the guard actually bites: deleting a cited proof's label, deleting a `_FM_PAIRS` entry, and single-quoting a label (to prove the matcher is quote-agnostic)

## Task Commits

1. **Task 1: End-to-end — one failure-mode row (missing dependency) is contract-pinned** - `d6cfd1c` (feat)
2. **Task 2: Fold the superseded-pin row into the same table and pin its literal to the installer** - `d077f3e` (feat)

_Both tasks carried `tdd="true"`; each commit bundles its own RED-observed-then-fixed cycle rather than splitting into separate test/feat commits, per the tracer-task shape this plan specifies (write the RED, run the suite, then make it pass before committing)._

## Files Created/Modified

- `tests/run-tests.sh` — new `FM01` block (after `EC06`, before `EC07`): table-scoped window (`_FM_TABLE`), two anchors (`_FM_ANCHOR_DEP`, `_FM_ANCHOR_PIN`), per-row shape checks, and `_FM_PAIRS` citation-rot guard
- `README.md` — missing-dependency row (`:234`) and superseded-pin row (`:226`) rewritten in place; no new section, no second table, no row reordering; `scripts/` untouched (`git diff --name-only -- scripts/` empty both commits)

## Decisions Made

- **Table-scoped counting, not whole-file:** the missing-dependency literal legitimately appears twice in README (the contract row and the fenced example at `:308`). FM01 counts uniqueness inside the Troubleshooting-table window only, and separately asserts the whole-file total is `2`, so the fenced copy is required to survive rather than merely tolerated.
- **Row-to-proof mapping as data:** `_FM_PAIRS` (bash array of `key:PROOF_ID`) replaces a comment-only citation. This closes the gap where a citation could rot silently — deleting a row, deleting its proof's `ok`/`bad` label, or deleting the pair entry itself now each fail the suite. Demonstrated live (see Deviations/RED observations below) and reverted.
- **S3 left open:** the plan's own Multi-Source Coverage Audit states S3 is "closed in 05-02 T3." Although the plan frontmatter lists `requirements: [S3]`, this plan only lands two of the four contract rows the closure needs. `requirements mark-complete S3` was deliberately NOT run in this plan's state update — S3 stays open until 05-02 closes it.

## RED/GREEN observations (recorded verbatim per plan's `<output>` instruction)

- **Task 1 RED** (before the missing-dependency README edit): `detail= readme:dep_missing_bridge_name readme:dep_missing_shim_name readme:dep_missing_reason`
- **Task 1 GREEN:** `ok - FM01 failure-mode contract table names both entry points per row and states sameness or a reason`
- **Task 2 RED** (before the superseded-pin README edit): `detail= readme:pin_missing_bridge_name readme:pin_missing_shim_name readme:pin_missing_reason`
- **Task 2 GREEN:** `ok - FM01 failure-mode contract table names both entry points per row and states sameness or a reason`

## Mutation-proof demonstrations (Task 2 acceptance criteria)

Each mutation was applied, the full suite run to observe the result, then the exact original line retyped back (never `git checkout`/`restore`/`reset`/`stash`). `git status --porcelain` was snapshotted before the first mutation and diffed against the state after the third revert — identical.

1. **Deleted RB03's `ok`/`bad` label** (renamed `RB03` → `RB03X` in both the `ok` and `bad` calls): FM01 → `FAIL ... detail= proof:RB03_missing`. Reverted; suite returned to `PASS=161 FAIL=0`.
2. **Deleted the `PIN:I16` entry from `_FM_PAIRS`**: FM01 → `FAIL ... detail= pairs:count_2`. Reverted; suite returned to `PASS=161 FAIL=0`.
3. **Single-quoted RB02's label** (`ok "RB02 ..."` → `ok 'RB02 ...'`, both `ok` and `bad` lines): FM01 still `ok` — proves the `["']` character class in `_FM_PAIRS`'s label matcher is genuinely quote-agnostic, not merely claimed to be. Reverted to double-quoted form.

**Note on plan-vs-acceptance-criteria mismatch:** Task 2's acceptance criteria named `SH14` as the ID to use for demonstration #1 above, but this plan's `_FM_PAIRS` lands only `DEP:RB03`, `DEP:RB02`, `PIN:I16` — the task's own action text states "This plan lands the first three" and that `SH14` is added by 05-02 (`LIST:SH14`). `SH14` is not yet a member of `_FM_PAIRS` and could not be used to demonstrate a `_FM_PAIRS`-cited-proof deletion. Substituted `RB03` (demonstration #1) and `RB02` (demonstration #3), both of which this plan's `_FM_PAIRS` actually contains, preserving the intent (prove a cited-proof-ID deletion and a quote-style change each behave as specified) against work this plan actually landed.

## Task 1 `<human-check>` verdict (operator's own words)

Read as an operator who has never heard of agy: the missing-dependency row now says the watchdog warning is "not a failure... `agy-bridge` and the `gemini` shim behave identically here because both carry byte-identical copies of `run_bounded`, so a host without coreutils changes which kill you get, never whether the call is bounded." That reads as a real, checkable claim rather than filler inserted to satisfy a grep: `scripts/agy_bridge.sh:224` and `scripts/gemini_shim.sh:243` each define `run_bounded()`, and `RB02` (`tests/run-tests.sh`) independently asserts those two copies (plus the `tests/contract-check.sh` copy) are byte-identical. An operator reading this row gets the correct mental model — "if I don't have coreutils, both entry points still bound the call, just with a slightly weaker kill" — which matches what `README:292-315`'s own Bounding section already argues in prose. Verdict: accepted as true, not merely shape-satisfying.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — plan-internal inconsistency] Task 2 acceptance criteria named `SH14` for a demonstration that this plan's own `_FM_PAIRS` cannot support**
- **Found during:** Task 2, mutation-demonstration acceptance criteria
- **Issue:** The acceptance criteria say "demonstrate this once on `SH14`" for the delete-a-cited-proof-label check, but the same task's action text explicitly scopes `_FM_PAIRS` to `DEP:RB03, DEP:RB02, PIN:I16` for this plan, deferring `LIST:SH14` (and `HANG:EC06`, `NAME:SH9`) to 05-02. `SH14` is not a member of this plan's `_FM_PAIRS`, so deleting its label would not exercise the `_FM_PAIRS`/`proof:` guard this criterion is testing.
- **Fix:** Substituted `RB03` for the label-deletion demonstration and `RB02` for the quote-agnostic demonstration — both are IDs this plan's `_FM_PAIRS` actually cites. Recorded the resulting detail strings above.
- **Files modified:** None beyond the already-planned `tests/run-tests.sh` (mutations applied and reverted within the same working session; final diff is unchanged by this substitution).
- **Verification:** `git status --porcelain` before the first mutation matched `git status --porcelain` after the third revert, byte for byte.
- **Committed in:** N/A — mutation-and-revert cycle left no residual diff; documented here rather than as a commit.

---

**Total deviations:** 1 auto-fixed (Rule 1, plan-internal wording inconsistency, no code impact).
**Impact on plan:** None on shipped behavior — the substitution only affects which existing ID was used to demonstrate an already-implemented guard.

## Issues Encountered

None beyond the deviation above. `bash tests/run-tests.sh` ran to completion cleanly on every invocation (baseline, both RED/GREEN cycles, and all three mutation demonstrations); no flaky or environment-dependent failures observed.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

`FM01`'s structure (table-scoped window, per-anchor row checks, `_FM_PAIRS` citation array) is in place for 05-02 to extend with three more anchors (`HANG`, `LIST` ×2, `NAME`) and four more `_FM_PAIRS` entries (`HANG:EC06`, `LIST:SH14`, `LIST:EC06`, `NAME:SH9`), bringing the array to 7 total as this plan's comment already anticipates. No blockers.

---
*Phase: 05-the-shim-s-failure-mode-contract*
*Completed: 2026-08-21*

## Self-Check: PASSED
