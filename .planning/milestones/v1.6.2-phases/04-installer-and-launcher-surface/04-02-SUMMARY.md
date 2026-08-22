---
phase: 04-installer-and-launcher-surface
plan: 02
subsystem: installer
tags: [bash, tdd, python3, home-env, requirements-closure]

# Dependency graph
requires:
  - phase: 04-installer-and-launcher-surface (plan 04-01)
    provides: k0f docs/version sync and the SIGPIPE-safe CLI fallback (I21/I21b), landed first so this plan's insertions above I16-I18 didn't collide with 04-01's own I21/I21b insertions
provides:
  - "scripts/install.sh and scripts/uninstall.sh: an explicit `HOME` precondition, sited immediately after the refuse-root check and before every `$HOME` expansion (D-06)"
  - "scripts/install.sh: a single hoisted `command -v python3` guard before the rc-alias-patch loop, carrying `_alias_patch_py3_ok` into the loop so a python3-absent host fails open once instead of crashing after both wrappers are already written (D-01/D-02)"
  - "tests/run-tests.sh: `_home_unset_case` helper plus regression cases I19, I20, I20b"
  - ".planning/REQUIREMENTS.md: R8 and S2 traceability rows closed `met`, citing I16/I17/I18 by case id (not line range) plus 04-01's I21/I21b for R8's criterion 5"
  - "delegate-agy-4bp and delegate-agy-4xn closed"
affects: ["06-ship-1.6.2 (release gate — R8 and S2 now read met)", "phase-5-shim-failure-mode-contract"]

# Actuals (#2632)
actuals:
  tokens: 3774
  tasks: 3
  commits: 5

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Hoist an invariant dependency check once before a loop, carrying a boolean flag into the loop body, rather than re-checking per iteration (D-01) — mirrors the shipped _register_tokensave/_agy_detect fail-open shape at install.sh:268-291"
    - "Explicit `[[ -n \"${VAR:-}\" ]] || { echo ERROR...; exit 1; }` precondition sited next to an existing same-shaped guard (refuse-root), rather than relying on bash's own set -u diagnostic"

key-files:
  created: []
  modified:
    - scripts/install.sh
    - scripts/uninstall.sh
    - tests/run-tests.sh
    - .planning/REQUIREMENTS.md

key-decisions:
  - "D-06's HOME precondition line is locked verbatim by the bead; inserted once per script, immediately after the refuse-root block, adding exactly one line per file so the fix(...) commit's `git show --stat` reads `1 +` for each"
  - "D-01's structural reading (hoist the check once before the loop, gated on the consent flag; the loop's existing per-file dry-run advisory stays untouched) resolves 04-RESEARCH.md's Open Question 1 in the recommended direction — the flag's *use* stays inside the loop, only the *dependency check* is hoisted"
  - "D-07: no new registry fixtures added; write_wrapper's registry-comparison heredoc (install.sh:85-182) is untouched across this plan's diff, confirmed via `git diff f06409b..HEAD -- scripts/install.sh`"
  - "R8/S2 traceability rows cite I16/I17/I18 by case id only, never by line range — this plan's own I19/I20/I20b insertions shifted I16-I18 earlier in tests/run-tests.sh, so any range recorded before those insertions would already be stale"
  - "The A2 Unicode-normalization residue is recorded as a risk note beneath the R8/S2 traceability rows, not inside them — an accepted assumption in the safe (degrade-to-silence) direction, not an open defect"

patterns-established:
  - "_home_unset_case SCRIPT_PATH CASE_ID LABEL: a parameterized regression-case body for 'this script under env -i with NO HOME key at all', reusable for any future unset-env-var precondition test"

requirements-completed: [R8, S2]

coverage:
  - id: D1
    description: "install.sh and uninstall.sh state a named HOME precondition and exit 1 instead of bash's own 'unbound variable' diagnostic when HOME is unset"
    requirement: "R8"
    verification:
      - kind: integration
        ref: "tests/run-tests.sh#I20 (install.sh), #I20b (uninstall.sh)"
        status: pass
    human_judgment: false
  - id: D2
    description: "install.sh's rc-alias patch fails open (one warning, wrappers already written stay intact, rc file untouched, no backup) on a python3-absent host with AGY_SETUP_PATCH_ALIASES=1 set"
    requirement: "R8"
    verification:
      - kind: integration
        ref: "tests/run-tests.sh#I19"
        status: pass
    human_judgment: false
  - id: D3
    description: "R8 and S2 traceability rows in REQUIREMENTS.md read met, citing I16/I17/I18 by case id, with the codex closure sentence and the A2 residue in risk notes"
    requirement: "R8, S2"
    verification:
      - kind: other
        ref: "tests/run-tests.sh#I16, #I17, #I18 (still ok post-phase); git diff --name-only HEAD~1 HEAD == .planning/REQUIREMENTS.md"
        status: pass
    human_judgment: false

duration: 22min
completed: 2026-08-21
status: complete
---

# Phase 4 Plan 2: HOME precondition, python3 fail-open guard, and R8/S2 closure Summary

**Both installer scripts now name their HOME precondition instead of crashing on bash's own `unbound variable`; the rc-alias patch fails open once, not after both launcher wrappers are already on disk; R8 and S2 close in REQUIREMENTS.md on I16/I17/I18's existing evidence.**

## Performance

- **Duration:** 22 min
- **Started:** 2026-08-21T14:43:11+02:00
- **Completed:** 2026-08-21T15:05:36+02:00
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments

- `scripts/install.sh` and `scripts/uninstall.sh` each gained one line: `[[ -n "${HOME:-}" ]] || { echo "ERROR: HOME is not set; run as a normal user with a home directory." >&2; exit 1; }`, sited immediately after the existing refuse-root check and before every `$HOME` expansion (`install.sh:58, 228, 253, 254, 256` and `uninstall.sh:20, 60, 61`)
- `scripts/install.sh`'s rc-alias-patch block now hoists one `command -v python3` check before the `for RC in ...` loop, gated on `AGY_SETUP_PATCH_ALIASES=1`; on miss it sets `_alias_patch_py3_ok=0`, echoes one warning naming the alias patch, and the loop skips the backup + `python3 -` call while leaving the existing per-file dry-run advisory (flag off) untouched
- Added `_home_unset_case` helper plus regression cases `I19` (python3-absent rc-alias patch), `I20` (`install.sh`, HOME unset) and `I20b` (`uninstall.sh`, HOME unset) to `tests/run-tests.sh`
- Closed `delegate-agy-4bp` and `delegate-agy-4xn`, each with a comment naming the closing commit and guarding case id
- `.planning/REQUIREMENTS.md`'s R8 and S2 traceability rows now read `met`, citing `I16`/`I17`/`I18` by case id (R8 additionally cites plan `04-01`'s `I21`/`I21b` for criterion 5's docs-tier half), carrying the exact sentence "formally closed in Phase 4 using previously shipped I16/I17/I18 evidence; registry logic unchanged", with the A2 Unicode-normalization residue recorded as a risk note beneath both rows

## Baseline and Suite Progression

- **BASELINE** (plan 04-01's final figure, re-confirmed before this plan's first edit): `PASS=155 FAIL=0`
- Task 1 RED (`I20`/`I20b` added, unfixed scripts): `FAIL - I20` — `scripts/install.sh: line 58: HOME: unbound variable`; `FAIL - I20b` — `scripts/uninstall.sh: line 20: HOME: unbound variable`. `PASS=155 FAIL=2`. Both reds are bash's own `set -u` diagnostic, the exact failure mode the fix replaces — confirmed via the negative assertion (`$out` must NOT contain `unbound variable`).
- Task 1 GREEN (HOME precondition inserted in both scripts): `PASS=157 FAIL=0` (BASELINE + 2)
- Task 2 RED (`I19` added, unfixed `install.sh`): `FAIL - I19` — `rc=127`, `install.sh: line 240: python3: command not found`, with `baks=1` (a `.bak-agy-*` backup already written by `cp -f` before the crash — exactly the "backup-then-fail" defect the guard exists to prevent). `PASS=157 FAIL=1`.
- Task 2 GREEN (hoisted python3 guard inserted): `PASS=158 FAIL=0` (BASELINE + 3, plan's target figure)
- Task 3 (REQUIREMENTS.md closure, doc-only): re-ran full suite unchanged — `PASS=158 FAIL=0` — confirming `I16`/`I17`/`I18` still `ok` and the doc edit introduced no regression

## Chosen Warning Wording (D-01, against the `install.sh:281` template)

Template (`_register_tokensave`, `install.sh:281`, N2): `WARNING: python3 not found — skipping tokensave registration (fail-open).`

Chosen (this plan, `install.sh:232`): `WARNING: python3 not found — skipping the recursive-gemini rc alias patch (fail-open).`

Same shape: `WARNING:` prefix, the phrase `python3 not found`, an em-dash-separated clause naming the skipped feature, the parenthetical fail-open marker, trailing period. The feature name (`the recursive-gemini rc alias patch`) is distinct from `tokensave registration`, which is what lets `I19`'s single-line assertion (`grep -ci 'python3 not found'` == 1, plus a check that the one match also contains `alias`) tell the two warnings apart.

## Task Commits

1. **Task 1 RED: add failing I20/I20b** - `0f4c873` (test)
2. **Task 1 GREEN: state the HOME precondition** - `3be29ce` (fix)
3. **Task 2 RED: add failing I19** - `474fd21` (test)
4. **Task 2 GREEN: guard the rc-alias patch's python3 dependency** - `aefeed1` (fix)
5. **Task 3: close R8/S2 in REQUIREMENTS.md, close the two beads** - `5747d38` (docs)

## Files Created/Modified

- `scripts/install.sh` — one-line HOME precondition (after the refuse-root check); hoisted `_alias_patch_py3_ok` python3 guard before the rc-alias-patch loop
- `scripts/uninstall.sh` — the mirrored one-line HOME precondition
- `tests/run-tests.sh` — `_home_unset_case` helper; cases `I19`, `I20`, `I20b`
- `.planning/REQUIREMENTS.md` — R8/S2 traceability rows closed `met`; A2 risk note added beneath the table

## Decisions Made

- D-06's HOME precondition is locked verbatim by the bead — no wording discretion; inserted identically in both scripts, exactly one line each, verified via `git show --stat` on the fix commit.
- D-01's hoisted-check structure resolves 04-RESEARCH.md's Open Question 1: the dependency check moves before the loop, but the consent-flag *read* stays inside the loop (per rc file) exactly as shipped, so the existing dry-run advisory keeps firing for every matched file when the flag is off.
- D-07: no new registry fixtures; `write_wrapper`'s registry-comparison heredoc (`install.sh:85-182`) is byte-unmodified across this plan's diff, confirmed by inspecting `git diff f06409b..HEAD -- scripts/install.sh` — both hunks sit well outside that range.
- REQUIREMENTS.md cites I16/I17/I18 by case id only, never by line range, because this plan's own I19/I20/I20b insertions land above them in the same file and would make any recorded range stale immediately.

## Deviations from Plan

None — plan executed exactly as written. All three tasks, all `must_haves`, and the D-01/D-02/D-06/D-07 locked mechanisms were followed without deviation. Task 2's initial edit was applied once, reverted, and reapplied in the correct RED-then-GREEN order after a self-caught sequencing slip during execution (the fix was drafted before its failing test existed); the failing `I19` test was added and observed red before the guard was committed, so no fix landed ahead of its test in the final commit history.

## Flagged Assumptions Disposition (A1, A2, A3)

- **A1** (R8, probe: empty/single-element/null input) — COVERED by shipped evidence, no new task this plan. `I17` exercises empty-array, compact and semi-compact registry shapes; `I16` covers absent/unparseable. Unchanged from the plan's own assessment.
- **A2** (R8, probe: bytes vs. code points vs. normalized form) — COVERED BY CONSTRUCTION, residue named. The registry key match and version regex are ASCII-only by construction; a registry key differing only by Unicode normalization form (NFC vs. NFD) would fail the exact-key match and degrade to silence — the safe direction. Recorded in REQUIREMENTS.md as a risk note beneath the R8/S2 rows, not inside them. Not an open defect, not a closed one; no test added (D-07).
- **A3** (S2, probe: unclassified) — COVERED by shipped evidence. `I17` covers bounded extraction and parse-failure-degrades-to-silence; `I16`'s lookalike-adjacent fixture covers no-cross-plugin misattribution.

## Issues Encountered

None beyond the self-corrected Task 2 sequencing slip noted above under Deviations — caught and fixed before any commit, so no red herring landed in git history.

## Known Stubs

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Phase 4 is complete: both plans (04-01, 04-02) executed, all five ROADMAP success criteria closed, R8 and S2 both read `met` in REQUIREMENTS.md, `delegate-agy-4bp`/`delegate-agy-4xn`/`delegate-agy-k0f`/`delegate-agy-4vy` all closed.
- Full suite: `PASS=158 FAIL=0` (baseline 155 + 3, this plan's target figure).
- No blockers for Phase 5 (the shim's failure-mode contract) or Phase 6 (the 1.6.2 release gate) — this phase's file surface (`scripts/install.sh`, `scripts/uninstall.sh`, the generated wrapper, and the setup/uninstall docs) is untouched by either dependency.

---
*Phase: 04-installer-and-launcher-surface*
*Completed: 2026-08-21*

## Self-Check: PASSED

All 4 modified files and this SUMMARY.md itself found on disk; all 5 commit hashes (0f4c873, 3be29ce, 474fd21, aefeed1, 5747d38) found in `git log --oneline --all`.
