---
phase: 05-the-shim-s-failure-mode-contract
plan: 02
subsystem: testing
tags: [bash, grep, contract-testing, readme-provenance]

requires:
  - phase: 05-the-shim-s-failure-mode-contract
    plan: 01
    provides: "FM01 block shape (table-scoped window, per-row bridge/gemini/because-or-identical checks) and the initial _FM_PAIRS (DEP:RB03, DEP:RB02, PIN:I16)"
provides:
  - "FM01 extended to 7 anchor pairs: DEP:RB03, DEP:RB02, PIN:I16, HANG:EC06, LIST:SH14, LIST:EC06, NAME:SH9"
  - "README's hung-agy (exit 124), unparseable-model-list (exit 2), and unrecognized-model-name Troubleshooting rows rewritten in place, each naming both agy-bridge and the gemini shim and stating a real, checkable divergence reason"
  - "REQUIREMENTS.md's S3 traceability row closed"
affects: []

actuals:
  tokens: 5619
  tasks: 3
  commits: 7

tech-stack:
  added: []
  patterns:
    - "FM01's per-row shape check (agy-bridge name + gemini name + because-or-identical) extended identically to three more anchors, following 05-01's established block shape"
    - "A row's proof citation can name more than one _FM_PAIRS entry (LIST:SH14, LIST:EC06) when two independent proofs (one per entry point) back a single row"
    - "Divergence reasons restated to reuse the plan's canonical one-line rationale (D-03: shim shadows PATH for every caller, so a stderr warning there is box-wide noise; bridge is explicit/watched, so a loud failure costs nothing) rather than inventing a new phrasing per row"

key-files:
  created: []
  modified:
    - "tests/run-tests.sh — FM01 gains _FM_ANCHOR_HANG, _FM_ANCHOR_LIST, _FM_ANCHOR_NAME (three new table-scoped row checks) and _FM_PAIRS grows from 3 to 7 entries"
    - "README.md — Troubleshooting rows for exit-124 (:231), exit-2 (:232), and 'Model name rejected' (:229) rewritten in place"
    - ".planning/REQUIREMENTS.md — S3's traceability row marked met"

key-decisions:
  - "_FM_ANCHOR_NAME is the load-bearing variable name for the NAME:SH9 pair, not _FM_ANCHOR_PASSTHRU as the plan's action text literally wrote — the existing per-pair loop resolves the anchor variable as _FM_ANCHOR_${key}, and the pair's key is NAME, so the variable MUST be _FM_ANCHOR_NAME for the anchor-existence check to find it. This is a plan-internal naming inconsistency (Rule 1 auto-fix), the same class 05-01 already logged for LIST:SH14. Detail-string tokens (readme:passthru_rows_N, shim:passthru_literal_missing) still use the plan's 'passthru' wording since those are free-form debug strings with no lookup dependency."
  - "Row reasons restated twice during execution: first draft used a locally-invented rationale (accurate but not the plan's specified D-03 one-liner); second draft aligned both rows to the same canonical PATH-caller/box-wide-noise reason the plan specifies, reusing it verbatim-ish across both rows as instructed."
  - "Fixed two directional errors in the 'Model name rejected' row during self-review: an incorrect '(the row above)' cross-reference (the degraded-list row is below it in table order, not above) and a dangling 'same reason as the row above' phrase (this row states that reason for the first time in the table; nothing above it says it yet)."

patterns-established: []

requirements-completed: [S3]

coverage:
  - id: D1
    description: "FM01 extended with _FM_ANCHOR_HANG, pinning the exit-124 row's shape; README's exit-124 row rewritten stating why the bridge's --json fork and the shim's envelope-free timeout arm diverge"
    requirement: S3
    verification:
      - kind: unit
        ref: "tests/run-tests.sh FM01 (HANG anchor + HANG:EC06 pair) — bash tests/run-tests.sh, PASS=161 FAIL=0"
        status: pass
    human_judgment: true
    rationale: "FM01 proves row SHAPE only. Truth judged by this plan's own human read-through of the finished table (recorded below)."
  - id: D2
    description: "FM01 extended with _FM_ANCHOR_LIST and _FM_ANCHOR_NAME, each with two proof pairs (LIST:SH14/LIST:EC06, NAME:SH9); README's exit-2 and 'Model name rejected' rows rewritten stating the shared PATH-caller design reason (D-03) for both divergences"
    requirement: S3
    verification:
      - kind: unit
        ref: "tests/run-tests.sh FM01 (LIST + NAME anchors, _FM_PAIRS at 7 entries) — bash tests/run-tests.sh, PASS=161 FAIL=0"
        status: pass
  - id: D3
    description: "REQUIREMENTS.md's S3 row closed: names all five failure-mode rows, both plans they landed in, FM01 as the gate, and all six proof IDs (RB02, RB03, EC06, SH14, SH9, I16); states FM01's shape-only ceiling and why cy5 stays open on R11's account"
    requirement: S3
    verification:
      - kind: manual
        ref: ".planning/REQUIREMENTS.md:91 — row no longer begins 'open', names FM01 and all six proof IDs"
        status: pass

human-checks:
  - task: "Task 3 — read-through of the finished five-row failure-mode contract"
    verdict: "PASS. Read README:220-236 fresh, as an operator who has never heard of agy. Every divergence row now states a real, independently checkable mechanism, not filler: hung-agy names exactly which arm forks on --json and which one doesn't; the model-list row and the model-name row both state the same underlying design reason (shim shadows PATH, must not refuse or warn loudly; bridge is explicit, can validate and fail loud) rather than two unrelated-sounding excuses, which makes the table read as one coherent policy instead of five unrelated exceptions. Two wording bugs were caught and fixed during this same read-through (see Deviations) before the verdict was recorded."

---

# Phase 5 Plan 02: Extend the failure-mode contract to hung-agy and model-list divergences, close S3 Summary

Extended FM01's contract table pin from 3 to 7 anchor/proof pairs, rewrote the three remaining Troubleshooting rows (hung agy, unparseable model list, unrecognized model name) to name both entry points and state a real divergence reason, and closed requirement S3.

## Performance

- **Duration:** ~55 min (three RED/GREEN cycles across the plan's three tasks, plus four self-review fixup rounds each re-running the full 161-test suite)
- **Completed:** 2026-08-21T19:13:55Z
- **Tasks:** 3/3 completed
- **Files modified:** 3 (`tests/run-tests.sh`, `README.md`, `.planning/REQUIREMENTS.md`)

## Accomplishments

- Extended `FM01` with `_FM_ANCHOR_HANG`, `_FM_ANCHOR_LIST`, `_FM_ANCHOR_NAME` — three more table-scoped row checks, each requiring both entry-point names and a because/identical clause, following 05-01's established shape exactly
- Grew `_FM_PAIRS` from 3 to 7 entries: `DEP:RB03`, `DEP:RB02`, `PIN:I16`, `HANG:EC06`, `LIST:SH14`, `LIST:EC06`, `NAME:SH9` — the model-list row is bound to two independent proofs (bridge-side EC06, shim-side SH14) since one row covers a divergence between two separately-tested behaviors
- Rewrote the exit-124 row: named the mechanism (bridge's timeout arm forks on `--json` and wraps the message in an envelope; the shim's timeout arm sits ahead of any output-format check and always writes plain text, so a shim caller that asked for `--output-format json` still gets no envelope on timeout)
- Rewrote the exit-2 (degraded model list) and "Model name rejected" rows to state the same underlying design reason (D-03): the shim shadows `gemini` for every PATH caller that never opted into agy, so it must not fail loud or warn loud on either condition, while the bridge is an explicit, watched invocation that validates up front and fails loud
- Closed S3 in `REQUIREMENTS.md`: the traceability row now names all five failure-mode rows, both plans they landed in, `FM01` as the gate, all six proof IDs, and states FM01's shape-only ceiling plus why `cy5` stays open on R11's account, not S3's

## Task Commits

1. **Task 1: Hung agy — pin FM01 contract shape and state the divergence reason** — `7f9a45a` (feat)
2. **Task 2: Two model-list divergences — bridge refuses, shim keeps caller running** — `255ee8a` (feat)
3. **Task 3: Close S3, prove the phase changed no shipped code** — `49fa2c7` (docs)

Post-task self-review fixups (all before final GREEN, same working session):
- `8783b8f` (fix) — renamed NAME-anchor `FM01_DETAIL` tokens from `name_*` to `passthru_*` to match the plan's documented vocabulary; added the degraded-list silent-passthrough case to the model-name row
- `9560787` (fix) — realigned both new divergence-reason rows to the plan's canonical D-03 rationale instead of a locally-invented one
- `ced7305` (fix) — corrected a row-order cross-reference direction ("the row above" → "the row below")
- `870653a` (fix) — removed a dangling forward-reference in the model-name row (it states the PATH-caller reason for the first time in the table; nothing above it says it yet)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `_FM_ANCHOR_PASSTHRU` vs `_FM_ANCHOR_NAME` naming conflict in the plan itself**
- **Found during:** Task 2, writing the FM01 anchor block
- **Issue:** The plan's action text names the third new anchor variable `_FM_ANCHOR_PASSTHRU`, but its own `_FM_PAIRS` entry for this row is `NAME:SH9` (key `NAME`, not `PASSTHRU`). The existing per-pair loop (inherited unchanged from 05-01) resolves the anchor variable as `_FM_ANCHOR_${_fm_key}` — for key `NAME` that is `_FM_ANCHOR_NAME`. Following the plan's literal variable name would make the `NAME:SH9` pair's anchor-existence check look for a variable that does not exist, failing FM01 with `pairs:anchor_missing_NAME`.
- **Fix:** Named the variable `_FM_ANCHOR_NAME` (matching the `_FM_PAIRS` key, required for correctness) instead of `_FM_ANCHOR_PASSTHRU` (the plan's literal but inconsistent text). Kept the plan's `passthru` wording for the free-form `FM01_DETAIL` debug tokens (`readme:passthru_rows_N`, `shim:passthru_literal_missing`) since those have no lookup dependency and matching the plan's documented vocabulary there costs nothing.
- **Files modified:** `tests/run-tests.sh`
- **Verification:** `bash tests/run-tests.sh` — `PASS=161 FAIL=0`, `_FM_PAIRS` all 7 entries resolve.
- **Committed in:** `255ee8a` (initial), `8783b8f` (token rename)

**2. [Rule 1 - Bug] Locally-invented divergence reasons instead of the plan's specified D-03 rationale**
- **Found during:** Self-review after Task 2's initial commit, before writing this SUMMARY
- **Issue:** My first drafts of the exit-2 and "Model name rejected" rows stated true but independently-invented reasons for the divergence (e.g., "a delegation call needs a real model id and the bridge hard-fails rather than guess one") instead of the plan's specified canonical one-liner (D-03: the shim shadows `gemini` for every PATH caller that never opted into agy, so a stderr warning there is box-wide noise; the bridge is explicit and watched, so a loud failure costs nothing). FM01's shape check passed either way (it only checks for the literal words "because"/"identical"), so this would not have been caught by the automated gate.
- **Fix:** Rewrote both rows to state the same D-03 reason, matching the plan's explicit instruction to reuse one shared one-line rationale across both rows rather than invent a per-row excuse.
- **Files modified:** `README.md`
- **Verification:** Re-ran `bash tests/run-tests.sh` — `PASS=161 FAIL=0`; re-read the finished rows.
- **Committed in:** `9560787`

**3. [Rule 1 - Bug] Two directional/self-reference errors in the "Model name rejected" row**
- **Found during:** Task 3's human read-through of the finished table
- **Issue:** (a) The row said "with no usable list (the row above)" but the degraded-list row is physically below "Model name rejected" in the table, not above. (b) The row said "for the same reason as the row above" but nothing above it states that reason yet — this row is the first to state it (the exit-2 row below correctly says "the row above" pointing back to this one).
- **Fix:** Changed "(the row above)" to "(the row below)"; removed the dangling "same reason as the row above" phrase and stated the PATH-caller reason directly instead.
- **Files modified:** `README.md`
- **Verification:** Re-ran `bash tests/run-tests.sh` after each fix — `PASS=161 FAIL=0` both times; final read-through recorded in `human-checks` above.
- **Committed in:** `ced7305`, `870653a`

---

**Total deviations:** 3 auto-fixed (Rule 1: one plan-internal naming inconsistency, two content-accuracy corrections found during self-review/human-check). None required an architectural decision or user input.
**Impact on plan:** None on shipped behavior (`scripts/` untouched throughout, confirmed by `git diff --name-only -- scripts/` returning empty after every task). All fixes are to test-file variable naming and README prose accuracy.

## RED/GREEN observations (recorded verbatim per plan's `<output>` instruction)

- **Task 1:** Extending `_FM_ANCHOR_HANG` and `HANG:EC06` into `_FM_PAIRS` produced an immediate `ok` — the exit-124 row's pre-existing text already satisfied FM01's SHAPE check (it already named both entry points and contained "identical"). No RED transition occurred for this task's FM01 check itself; this does not violate the TDD fail-fast rule (the check did not silently pass over an *unimplemented* behavior — the row's shape genuinely already existed). The row was still rewritten per the plan's action text to add the missing mechanism-level reason (why the bridge and shim diverge, not just that they do), which FM01's shape check cannot judge — that half is a human-check matter.
- **Task 2 RED** (after extending `_FM_ANCHOR_LIST`/`_FM_ANCHOR_NAME`/`_FM_PAIRS`, before README edits): `detail= readme:list_missing_reason readme:name_rows_0 readme:name_missing_bridge_name readme:name_missing_shim_name readme:name_missing_reason`
- **Task 2 GREEN:** `ok - FM01 failure-mode contract table names both entry points per row and states sameness or a reason`

## Verification (exact commands run, results recorded)

```
$ bash tests/run-tests.sh 2>&1 | tail -3
PASS=161 FAIL=0                                    # final run, and every re-run after each fixup
```

One run during self-review reported `PASS=160 FAIL=1`, immediately followed by two clean re-runs (`PASS=161 FAIL=0` each). No specific failing test name surfaced in that run's log beyond the summary line, and it did not recur across two subsequent runs. This matches the project's already-tracked intermittent flake (`delegate-agy-sup`, RB24 run_bounded trap-preservation), unrelated to this plan's files — not treated as a regression.

```
$ sed -n '/^## Troubleshooting$/,/^### Running the tests$/p' README.md | grep -c '^|'
13
$ grep -cF 'did not resolve against the agy model list; passing it through unchanged' README.md scripts/gemini_shim.sh
README.md:1
scripts/gemini_shim.sh:1
$ git diff --name-only -- scripts/ | wc -l
0
$ git diff -U0 README.md | grep -c '^[-+].*comparison-only'
0
```

**Phase-start baseline (captured at the start of Task 3, since 05-01's SUMMARY did not record one):**
```
 M .planning/PROJECT.md
?? .claude/.headroom_wrap_marker.json
?? .claude/commands/designqc.md
?? .claude/commands/handoff.md
?? .claude/commands/reframe.md
?? .claude/commands/security-audit.md
?? .claude/rules/
?? .claude/skills/
?? .opencode/
?? .planning/milestone.lock
?? .planning/phases/02-model-list-handling-end-to-end/02-BEADS.md
?? .planning/phases/03-the-exit-code-contract/03-BEADS.md
?? .planning/phases/04-installer-and-launcher-surface/04-BEADS.md
?? .planning/phases/05-the-shim-s-failure-mode-contract/05-BEADS-RECALL.md
?? .planning/phases/05-the-shim-s-failure-mode-contract/05-PATTERNS.md
?? .serena/
?? .wolf/
?? GEMINI.md
```
Diff against this baseline after Task 3's edit showed exactly one added line (`M .planning/REQUIREMENTS.md`), confirming Task 3 touched only that file.

## Issues Encountered

One intermittent full-suite flake (`PASS=160 FAIL=1`) observed during self-review re-runs, not reproduced on either the preceding or two following runs. Matches the pre-existing tracked issue `delegate-agy-sup` (RB24 run_bounded trap-preservation flake), unrelated to this plan's files. Not investigated further per that ticket's existing scope.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

Phase 5 is now complete: `FM01` pins all five failure-mode contract rows (missing dependency, superseded pin, hung agy, unparseable model list, unrecognized model name) across 7 `_FM_PAIRS` entries, and requirement S3 is closed in `REQUIREMENTS.md`. No further plans are queued in this phase; orchestrator-level phase verification (not run by this executor) is the next step.

---

*Phase: 05-the-shim-s-failure-mode-contract*
*Plan: 02*
*Completed: 2026-08-21T19:13:55Z*
*Status: PASSED*
