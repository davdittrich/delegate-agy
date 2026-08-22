---
phase: 01-the-missing-timeout-decision
plan: 05
subsystem: testing
tags: [bash, static-analysis, regression-tests, run_bounded, invariant]

requires:
  - phase: 01-01
    provides: run_bounded, the _purebin/_run_sanitized sanitized-PATH harness, the forking fake agy
  - phase: 01-02
    provides: the shim's four bounded sites and the warn-once-at-the-probe placement
  - phase: 01-03
    provides: the bridge's byte-identical copy of the block and its three bounded sites
  - phase: 01-04
    provides: README quoting the two literals verbatim, which RB03 pins
provides:
  - "RB01 + RB01m: phase criterion 4 enforced as an invariant over both script files, zero exceptions, proven capable of failing"
  - "RB02 + RB02m: the two run_bounded copies are one artifact; a one-sided edit fails the suite"
  - "RB03: the warning and watchdog-notice literals are the same bytes in both scripts and in README, plus the negative half (delegate-agy-6f6)"
  - "RB08: one warning per coreutils-less run, ahead of any bounded output, none with coreutils"
affects: [01-06, phase-3-exit-codes, phase-5-shim-contract, phase-6-ship]

actuals:
  tokens: 3965
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Static invariant over a file, asserted in the suite: joined logical lines, comment lines dropped, zero exceptions, floor-not-count"
    - "Mutation-proof-of-sensitivity as a committed case (RB01m, RB02m) wherever the scan logic could go vacuous"

key-files:
  created: []
  modified:
    - .worktrees/agy-1.6.2/tests/run-tests.sh

key-decisions:
  - "Occurrence matching covers every expansion form ($AGY_BIN, ${AGY_BIN}, quoted or bare), not only the doubly-quoted form the criterion names — a brace rewrite would otherwise walk past a zero-violation verdict"
  - "RB08 drives its prompt through stdin, not as an argument: the fetch and delegation sites redirect stderr into files, so an argument-driven RB08 was a proven false negative"
  - "The negative checks (delegate-agy-6f6) are scoped to what ships — README and the two scripts — not to .planning/, which lives in the other tree and is absent from a release tarball"
  - "The README ban on the word 'unbounded' is blanket, and its ceiling is stated in the case comment rather than worked around with an allowlist"

patterns-established:
  - "A scan never shown to fail is a scan that passes forever: every static case here was demonstrated red against a mutated real file before being committed green"
  - "Ceilings are labelled in the case comment where an assertion cannot see something (mention-vs-invoke, redirect-swallowed emissions, the README word ban)"

# R11 is NOT marked complete here. Its acceptance is "the static invariant PLUS a runtime
# proof per entry point on both mechanisms"; this plan delivers the static half only, and
# plan 01-06 delivers the runtime half. Marking it now would be a false green.
requirements-completed: []

coverage:
  - id: D1
    description: "Every agy invocation in both scripts is a run_bounded argument, enforced over the files with zero exceptions and a non-vacuity floor"
    requirement: R11
    verification:
      - kind: unit
        ref: "tests/run-tests.sh#RB01, tests/run-tests.sh#RB01m"
        status: pass
    human_judgment: false
  - id: D2
    description: "The two duplicated run_bounded blocks are byte-identical and non-empty; a one-sided edit fails the suite"
    requirement: R11
    verification:
      - kind: unit
        ref: "tests/run-tests.sh#RB02, tests/run-tests.sh#RB02m"
        status: pass
    human_judgment: false
  - id: D3
    description: "Both scripts define the warning literal once with identical bytes, README quotes both literals verbatim, and the reversed claims (deleted startup fatal, 'unbounded') cannot come back into what ships"
    requirement: R11
    verification:
      - kind: unit
        ref: "tests/run-tests.sh#RB03"
        status: pass
    human_judgment: false
  - id: D4
    description: "Each entry point warns exactly once per coreutils-less run, ahead of any bounded output, and never when a bounding binary resolves"
    requirement: R11
    verification:
      - kind: integration
        ref: "tests/run-tests.sh#RB08"
        status: pass
    human_judgment: false

duration: 50min
completed: 2026-08-19
status: complete
---

# Phase 01 Plan 05: Lock the invariant Summary

**Phase criterion 4 now lives in the suite as a property of the two script files rather than in anyone's memory of how many call sites there are: an agy invocation added later that is not a `run_bounded` argument fails `tests/run-tests.sh` today, and each of the four new cases was demonstrated red against a mutated real file before being committed green.**

## Performance

- **Duration:** ~50 min
- **Started:** 2026-08-19T11:20Z (approx)
- **Completed:** 2026-08-19T12:09Z
- **Tasks:** 3
- **Files modified:** 1 (`tests/run-tests.sh`, +279 lines)

Suite: **PASS=103 FAIL=0**, up from the inherited **PASS=97 FAIL=0**. Six new `ok` lines (RB01, RB01m, RB02, RB02m, RB03, RB08). Neither shipped script was modified; `bash -n` clean on both.

## Accomplishments

- **RB01** asserts the restated criterion 4 over both files: comment-only lines dropped, backslash continuations joined into logical lines, then every occurrence of an `AGY_BIN` expansion must sit on a logical line where `run_bounded … -- ` precedes it. Zero exceptions, no allowlist, no escape-hatch comment. Violations must be zero and total occurrences at least one — a floor, not a count.
- **RB01m** proves the scan can fail: a copied shim with an injected direct invocation is reported, a copied shim gaining only a *comment* naming the variable is not.
- **RB02/RB02m** compare the two marker-delimited `run_bounded` ranges, reject empty or definition-less ranges, and prove a one-character edit inside a copy is caught.
- **RB03** pins the warning and watchdog-notice literals against fixed text held in the test (no extract-and-grep tautology), counting the definition once per script with comment lines filtered first, and greps README with `-F`. It also carries the negative half folded in from `delegate-agy-6f6`.
- **RB08** drives each entry point through a coreutils-less run that exercises all three bounded sites and asserts exactly one warning, positioned ahead of the delegation's output, and zero warnings under the ordinary PATH.

## Task Commits

Each task was committed atomically on `fix/agy-bridge-resilience` in `.worktrees/agy-1.6.2`:

1. **Task 1: RB01 — every agy invocation is a `run_bounded` argument** — `1b0c3ac` (test)
2. **Task 2: RB02 and RB03 — block identity and the strings an operator sees (incl. `delegate-agy-6f6`)** — `be578ec` (test)
3. **Task 3: RB08 — one warning per run, ahead of any bounded output** — `3fdf663` (test)

## Files Created/Modified

- `.worktrees/agy-1.6.2/tests/run-tests.sh` — six new cases and three new helpers (`_rb_logical_lines`, `_rb_agy_scan`, `_rb_extract`), inserted between the RB20–RB22 gap-fix block and the installer section.

## The count discrepancy, investigated rather than tuned around

`01-03-SUMMARY.md` predicted RB01's scan would find **6** agy sites across both scripts. It finds **5** (bridge 2, shim 3), which matches the ROADMAP note's "it is now five".

The six is wrong and the scan was not adjusted toward it. `01-03` counted **bounded call sites** — bridge 3 (model fetch, stdin `cat`, delegation) and shim 4 (model fetch, `--version`, stdin `cat`, delegation) — and only 5 of those 7 invoke agy; the two `cat` calls do not. Nothing in either script changed between `6cf6f57` and this plan (`git status` clean, `git log` unchanged), so the discrepancy is a miscount in the prior summary, not drift. RB01 asserts no number beyond the floor of one, so nothing here depends on which figure is right — which is the point of stating the criterion as an invariant.

## Criterion 4: the restated text is what RB01 enforces

The plan's prose predates `520b3f9`. Where it spoke of a `"$AGY_BIN"` occurrence being "either wrapped in `"$TIMEOUT_BIN" -k …` or in a `TIMEOUT_BIN`-empty fallback branch", the ROADMAP now reads: *every `"$AGY_BIN"` occurrence … is an argument to `run_bounded`, with zero exceptions*. RB01 implements the ROADMAP text. The only `if [[ -n "$TIMEOUT_BIN" ]]` left in either script is `run_bounded`'s own internal mechanism selector (`agy_bridge.sh:204`, `gemini_shim.sh:221`); RB01 does not look at conditionals at all, so it cannot flag it. The plan's Task 1 precondition ("halt if either file still contains such a conditional outside the marked block") was checked by reading the files: both sites are inside the `# --- BEGIN/END run_bounded ---` markers (bridge 47–278, shim 64–295). Precondition met.

## Decisions Made

1. **Occurrences match any expansion form.** The criterion names `"$AGY_BIN"`, but matching only that form would let `"${AGY_BIN}"` or a bare `$AGY_BIN` slip past a scan still reporting zero violations — the one way this case could fail silently. The scan matches `\$\{?AGY_BIN\}?`. The assignment line carries no `$` and is correctly not an occurrence.
2. **The mention-vs-invoke ceiling is accepted and labelled.** A line that merely prints `$AGY_BIN` in a diagnostic is reported as a violation. Separating "invokes" from "mentions" needs a shell parser (rejected in the plan's alternatives on LOC grounds); the cheap approximation errs toward failing loudly, and a legitimate future mention has to change the rule in the open.
3. **Committed mutation cases only where the logic can go vacuous.** RB01 and RB02 carry permanent mutation cases (RB01m, RB02m) because their joining/extraction logic could silently match nothing. RB03's checks are direct fixed-string presence tests with no logic to go vacuous, so its mutation demonstrations were run ad hoc against the real files and recorded below rather than committed.
4. **Negative checks scoped to what ships.** See below.

## `delegate-agy-6f6`, folded into Task 2 — and what it does not cover

Two absences are now pinned inside RB03:

- **The deleted bridge fatal** `ERROR: timeout/gtimeout not found in PATH (install coreutils)` must appear in neither shipped script nor README. Fixed-string, exact.
- **The word `unbounded`** must not appear in README.

Two scoping calls, both deliberate and both stated here because they are limitations:

- **`.planning/PROJECT.md` and `.planning/REQUIREMENTS.md` are not checked.** They live in the main tree while the suite runs from the worktree, and the suite must also pass from a release tarball that contains no `.planning/` at all. A check reaching across trees would make the suite fail for a reason unrelated to what ships. Both files were verified clean by hand at execution time (zero `unbounded` occurrences, no trace of the deleted fatal).
- **The `unbounded` ban covers README only, and is broader than the property.** The property worth pinning is "no present-tense claim that either entry point runs agy unbounded". That is not mechanically separable from a legitimate historical or contrast mention, so per the instruction I asserted the thing I can pin exactly: README carries zero occurrences today, so a blanket ban is exact today and a future legitimate mention must change the rule in the open. The two shipped scripts are deliberately excluded — they use the word correctly in three hazard comments (`agy_bridge.sh:171`, `gemini_shim.sh:188`, `gemini_shim.sh:314`), which is precisely the case that cannot be separated mechanically.

## TDD: the red observed for each case

Every mutation was applied to a **real** file, the suite run, then the mutation reverted; `git status` was clean of script and README changes after each, and no mutated file was committed.

| Case | Mutation applied to the real tree | Observed |
|------|-----------------------------------|----------|
| RB01 | appended `if [[ "${RED_DEMO_NEVER:-0}" == "1" ]]; then "$AGY_BIN" --version; fi` to `scripts/gemini_shim.sh` | `FAIL - RB01`, `FAIL - RB01m`, `PASS=97 FAIL=2` |
| RB02 | one character inside the bridge's block (`# Bounded invocation` → `# bounded invocation`) | `FAIL - RB02`, `FAIL - RB02m`, `PASS=100 FAIL=2` |
| RB03 | README paraphrase: em dash for the `--` in the warning literal | `FAIL - RB03`, `PASS=101 FAIL=1` |
| RB03 (negative half) | README regains the deleted fatal plus an "…runs agy unbounded" sentence | `FAIL - RB03`, `PASS=101 FAIL=1` |
| RB08 (count) | `echo "$RB_NO_TIMEOUT_WARN" >&2` moved inside `run_bounded`, i.e. once per bounded call | `FAIL - RB08`, `PASS=99 FAIL=4` |
| RB08 (ordering) | probe emission removed, re-emitted at the end of the shim | `FAIL - RB08` |

Green afterwards, every time: `PASS=103 FAIL=0`.

## Issues Encountered

**RB08 passed its own mutation on the first write — a real false negative, fixed rather than tuned around.**

The first version of RB08 supplied the prompt as an argument (`-p` / `--`), which exercises two bounded sites: the model fetch and the delegation. Both redirect their stderr into files (`2>"$_agy_err"`, `2> "$STDERR_FILE"`, `2>/dev/null`), so a shim mutated to emit the warning inside `run_bounded` — exactly the migration RB08 exists to catch — still showed a count of 1 and the case stayed green (`PASS=100 FAIL=3`, with RB08 among the `ok` lines).

Fix: RB08 now sends the prompt on **stdin**, which brings in the third bounded site, the stdin `cat`, whose stderr is not redirected and therefore reaches the captured stream. The same mutation is now red. The residual ceiling is stated in the case comment: a migration touching only the two redirect-into-a-file sites would still be invisible to this case and would have to be caught by reading those files.

This is the concrete instance of the rule that motivated the whole plan — a check that has never been shown to fail is a check that passes forever.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] RB08 as specified was insensitive to the defect it guards**
- **Found during:** Task 3
- **Issue:** the plan's RB08 recipe ("supply a prompt so the delegation call runs too") produced a case that stayed green against a per-call warning emission, because the two sites it exercised both redirect stderr away from the captured stream.
- **Fix:** drive the prompt through stdin so all three bounded sites run; the stdin `cat` site's stderr is the one the count can see. Residual ceiling documented in the case comment.
- **Files modified:** `.worktrees/agy-1.6.2/tests/run-tests.sh`
- **Verification:** the mutation that previously passed now fails (`FAIL - RB08`, `PASS=99 FAIL=4`); real scripts green.
- **Committed in:** `3fdf663`

**2. [Rule 2 - Missing critical functionality] The scan matched only the doubly-quoted expansion**
- **Found during:** Task 1
- **Issue:** the criterion's wording names `"$AGY_BIN"`; a scan honouring only that form reports zero violations for a call site written `"${AGY_BIN}"` or bare `$AGY_BIN`.
- **Fix:** occurrence and violation patterns both use `\$\{?AGY_BIN\}?`.
- **Files modified:** `.worktrees/agy-1.6.2/tests/run-tests.sh`
- **Verification:** occurrence total unchanged at 5 under the broadened pattern (the assignment lines carry no `$` and stay excluded); RB01m still red on an injected site.
- **Committed in:** `1b0c3ac`

---

**Total deviations:** 2 auto-fixed (1× Rule 1, 1× Rule 2)
**Impact on plan:** both strengthen the assertions the plan asked for; neither widens scope beyond `tests/run-tests.sh`. No prohibition was touched — no count is asserted, no allowlist exists, no shipped script gained a test-only affordance, and no existing assertion was weakened.

## Out of scope, recorded so it is not lost

`REQUIREMENTS.md` R11's `Evidence:` line still cites `tests/run-tests.sh R5/R6/R7, T4/T5, SH4/SH5/SH6` and names none of the RB cases. Updating it is correct but outside this plan's declared `files_modified` (`tests/run-tests.sh` only), and plan 01-06 adds RB05–RB14, so the line should be rewritten once after 01-06 lands rather than twice. Filed as `delegate-agy-8k0` so it does not depend on anyone's memory.

## Known Stubs

None. No stub, skipped test, or unrun `<verify>` was introduced. Both plan `<verify>` blocks were run in full (`bash tests/run-tests.sh`), not just grepped.

## User Setup Required

None.

## Next Phase Readiness

Plan 01-06 (Wave 4) is unblocked: it owns RB05, RB06, RB07, RB09–RB14 and the runtime proofs per entry point on both mechanisms. Two inherited cautions carry forward unchanged — `RUN_BOUNDED_KILLED` cannot escape the bridge delegation site's `cd` subshell, so no case may assert the flag's value there without accounting for it; and the watchdog path maps 137/143 → 124, so a host script's `EXIT_CODE -eq 137` branch cannot fire on that path by design.

Phase criterion 4 is now enforced. Criteria 1–3 were discharged by 01-04; criterion 2's runtime half is 01-06's.

## Self-Check

- `.worktrees/agy-1.6.2/tests/run-tests.sh` — FOUND, modified, +279 lines
- Commits `1b0c3ac`, `be578ec`, `3fdf663` — FOUND on `fix/agy-bridge-resilience`
- `bash tests/run-tests.sh` — `PASS=103 FAIL=0`
- `bash -n` on both shipped scripts — clean; `git status` shows neither modified
- Main tree `scripts/`, `tests/`, `docs/`, `README.md` — untouched

## Self-Check: PASSED
