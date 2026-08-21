---
phase: 04-installer-and-launcher-surface
plan: 03
subsystem: installer
tags: [bash, python3, docs, tdd, security, claude-plugin]

# Dependency graph
requires:
  - phase: 04-installer-and-launcher-surface (plans 04-01, 04-02)
    provides: the CLI-fallback one-liner's SIGPIPE-safe producer expression (04-01) and the rc-alias-patch python3 guard structure (04-02) this plan splits and refines
provides:
  - "agy-setup.md / agy-uninstall.md: the CLI-fallback block's case success arm prints (never execs) the resolved path; a new, separate `bash \"$RESOLVED\"` line below its own \"check it looks right, then run\" prose is what actually execs (CR-01, CR-02)"
  - "agy-setup.md / agy-uninstall.md: the fallback's `python3 -c` expression wraps `json.load` in try/except, degrading any parse failure to the existing empty-result branch (IN-01)"
  - "agy-setup.md / agy-uninstall.md: primary flow's step 1 captures the resolved install path into a real `$AGY_PATH` variable instead of the invalid `<that-path>` placeholder; every subsequent command in both docs uses `\"$AGY_PATH/scripts/...\"` (WR-02)"
  - "scripts/install.sh: the python3-absent rc-alias-patch warning now fires only once a recursive alias is actually found in the current rc file, not unconditionally before the loop (WR-01)"
  - "tests/run-tests.sh: I21/I21b redesigned for the two-step resolve-then-exec contract (Tests A-D); new cases I19b, I22"
  - "delegate-agy-5r9.7, delegate-agy-5r9.8, delegate-agy-5r9.9 closed"
affects: ["06-ship-1.6.2 (release gate)"]

# Actuals (#2632)
actuals:
  tokens: 6243
  tasks: 3
  commits: 5

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Two-step resolve-then-exec: a validating block prints a resolved path for human review; a separate, explicit line the reader runs themselves does the actual exec -- extends the primary flow's existing 'print, check, then run' idiom to the CLI-fallback path"
    - "Exact whole-line grep (grep -x) to detect a doc-text addition when a substring match would collide with a pre-existing, legitimate mention of the same string elsewhere in the same file"
    - "Hoist-into-loop dependency check: a python3-presence guard moves from unconditional-before-a-loop to conditional-on-the-loop's-own match branch, so the guard only fires when there is something for it to gate"

key-files:
  created: []
  modified:
    - .claude/commands/agy-setup.md
    - .claude/commands/agy-uninstall.md
    - scripts/install.sh
    - tests/run-tests.sh

key-decisions:
  - "Test A's hostile fixture reuses the exact CR-01/CR-02 reproduction shape (agy-delegate@evil-marketplace listed before agy-delegate@real-marketplace) rather than inventing a different lookalike shape, so the pre-fix RED demonstrates the identical attack the review reproduced"
  - "Test B extracts the doc's own second exec line via an exact whole-line grep -x (not a substring grep -c) specifically because both docs carry a pre-existing, legitimate 'e.g. ... bash \"$RESOLVED\"' mention in the opt-in-variants prose that a substring count would wrongly collide with -- verified this discriminates all three states (pre-fix embedded form: 0, correct fix: 1, fix with the line missing: 0) without ever miscounting the prose mention"
  - "Test B executes the line text extracted from the live file, not a hand-written `bash \"$RESOLVED\"` the test invents independently -- a doc shipped with the second line simply missing must fail Test B even though Test A (no-auto-exec) would still pass"
  - "WR-01's fix hoists only the *dependency check* into the loop's existing alias-match branch; the `_alias_patch_py3_ok` flag and its `continue` gate stay exactly where 04-02 sited them (after the dry-run advisory's own continue, before the cp -f backup) -- only when the check runs changed, not the flag's own gating position"
  - "Task 3 (WR-02) is not TDD -- there is no runtime mechanism to exercise, only doc text -- so I22 is a single negative-grep case added in the same commit as the doc fix, not a separate RED/GREEN pair"

patterns-established:
  - "_md_fallback_case Tests A-D: a hostile-fixture no-exec proof, a doc's-own-extracted-line end-to-end exec proof, single-match parity, and a dual zero-match/invalid-JSON degradation proof -- reusable for any future 'resolve now, exec later' doc mechanism"

requirements-completed: [R8]

coverage:
  - id: D1
    description: "agy-setup.md's and agy-uninstall.md's CLI-fallback blocks split resolve/validate from exec: the case success arm prints the resolved path, a separate explicit bash \"$RESOLVED\" line execs it, and json.load degrades any parse failure to the existing empty-result branch"
    requirement: "delegate-agy-5r9.7"
    verification:
      - kind: integration
        ref: "tests/run-tests.sh#I21, #I21b"
        status: pass
    human_judgment: false
  - id: D2
    description: "scripts/install.sh's python3-absent rc-alias-patch warning fires only when a recursive alias was actually found, never on a fresh HOME with no matching rc file"
    requirement: "delegate-agy-5r9.8"
    verification:
      - kind: integration
        ref: "tests/run-tests.sh#I19b (negative case), #I19 (positive case still holds)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Neither doc contains the <that-path> placeholder as a bash argument; both docs' primary flow captures the resolved install path into a real $AGY_PATH variable and every subsequent command uses it"
    requirement: "delegate-agy-5r9.9"
    verification:
      - kind: integration
        ref: "tests/run-tests.sh#I22"
        status: pass
    human_judgment: false

duration: 41min
completed: 2026-08-21
status: complete
---

# Phase 4 Plan 3: Close the CLI-fallback exec gap, the python3-guard false positive, and the `<that-path>` doc placeholder Summary

**Split the CLI-fallback one-liner's resolve/validate step from its exec step in both command docs (closing an arbitrary-code-execution gap a lookalike-marketplace plugin could exploit), made its JSON parse fail closed, scoped the python3-absent rc-alias warning to only fire when there's something to patch, and replaced the invalid `<that-path>` placeholder with a real captured `$AGY_PATH` shell variable.**

## Performance

- **Duration:** 41 min
- **Started:** 2026-08-21T14:00:00Z
- **Completed:** 2026-08-21T14:36:11Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments

- Both `.claude/commands/agy-setup.md` and `.claude/commands/agy-uninstall.md`'s CLI-fallback blocks now print `Resolved: $RESOLVED` on their case statement's success arm instead of executing it in the same paste; a new, separate `bash "$RESOLVED"` line — with its own "check the printed path, then run" prose — is what actually execs. A lookalike-marketplace entry listed first in `claude plugin list --json` can still resolve into `$RESOLVED`, but nothing runs until the reader reads the printed path and pastes the second line themselves (CR-01, CR-02).
- The same block's `python3 -c` expression now wraps `json.load(sys.stdin)` in `try`/`except`, degrading any parse failure (e.g. `claude` itself producing empty/invalid output) to the same empty-list default as a zero-match reply, instead of aborting with a raw Python traceback under `set -euo pipefail` (IN-01).
- `scripts/install.sh`'s python3-absent rc-alias-patch warning moved from unconditional-before-the-loop to conditional-on-a-recursive-alias-actually-found inside the loop's existing match branch — it no longer fires on a fresh `HOME` with no rc files, or rc files with no matching alias (WR-01).
- Both docs' primary flow now captures the resolved install path into a real `$AGY_PATH` shell variable (mirroring the fallback block's own `$RESOLVED` idiom) instead of the invalid `<that-path>` bracket placeholder; every subsequent command — the primary install/uninstall line, both opt-in variants, and the tokensave de-register variant — uses `"$AGY_PATH/scripts/..."` so each is genuinely paste-able in the same shell session as step 1 (WR-02). All 11 confirmed `<that-path>` occurrences (7 in `agy-setup.md`, 4 in `agy-uninstall.md`) are gone.
- Redesigned `I21`/`I21b` in `tests/run-tests.sh` for the two-step contract (Tests A-D); added `I19b` (python3-absent guard's negative case) and `I22` (negative grep for the `<that-path>` placeholder).
- Closed `delegate-agy-5r9.7`, `delegate-agy-5r9.8`, `delegate-agy-5r9.9`, each with a comment naming its closing commit(s).

## Pre-fix Reproductions (recorded at each RED commit, per plan's `<output>` spec)

**Task 1, Test A (CR-01/CR-02):** fed the unfixed block a two-entry hostile reply (`agy-delegate@evil-marketplace` listed before `agy-delegate@real-marketplace`, same shape as the review's own reproduction). Pre-fix output: `EVIL_TOKEN_I21` / `EVIL_TOKEN_I21b` (the **hostile** marker, not the legitimate one) — the block auto-executed the lookalike entry it happened to resolve first, exactly as `04-REVIEW.md` reproduced.

**Task 1, Test D2 (IN-01):** fed the unfixed block an empty/invalid `claude` reply. Pre-fix output was the exact traceback:
```
Traceback (most recent call last):
  File "<string>", line 1, in <module>
    import sys,json;print(next((x.get("installPath","") for x in json.load(sys.stdin) if x.get("id","").startswith("agy-delegate@")), ""))
```
rc=1 — never reaching the friendly `ERROR:` branch, confirming IN-01's exact reported behavior under `set -euo pipefail`.

**Task 2, I19b (WR-01):** a fresh `HOME` with `AGY_SETUP_PATCH_ALIASES=1`, python3 absent, and **no rc file at all**. Pre-fix: `rc=0 warns=1` — `WARNING: python3 not found — skipping the recursive-gemini rc alias patch (fail-open).` printed despite there being nothing to skip.

## Baseline and Suite Progression

- **BASELINE** (plan 04-02's final figure, re-confirmed before this plan's first edit): `PASS=158 FAIL=0`
- Task 1 RED (`I21`/`I21b` redesigned, unfixed docs): `FAIL - I21`, `FAIL - I21b` — Test A shows the hostile marker executed; Test B shows the standalone exec line doesn't exist yet (`exact_line_count=0`); Test D2 shows the exact `JSONDecodeError` traceback. `PASS=156 FAIL=2`.
- Task 1 GREEN (two-step split + try/except in both docs): `PASS=158 FAIL=0` (BASELINE + 0 net — same two case ids, redesigned in place, no new case for this task).
- Task 2 RED (`I19b` added, unfixed `install.sh`): `FAIL - I19b` — `rc=0 warns=1`, the false-positive fires with no rc file present. `PASS=158 FAIL=1`.
- Task 2 GREEN (python3 check hoisted into the loop's match branch): `PASS=159 FAIL=0` (BASELINE + 1).
- Task 3 (doc placeholder fix + `I22`, no separate RED — doc-only, not TDD): `PASS=160 FAIL=0` (BASELINE + 2, the plan's final target figure).

## Task Commits

Five commits total (Tasks 1 and 2 are `tdd="true"` — test/fix pairs; Task 3 is `type="auto"` without `tdd`, so its doc fix and its one new negative-grep case land in a single commit):

1. **Task 1 RED: redesign I21/I21b for the two-step contract** - `9380446` (test)
2. **Task 1 GREEN: split resolve/validate from exec, fail-close the JSON parse** - `e11bb9d` (fix)
3. **Task 2 RED: add failing I19b for the false-positive warning** - `90eec6d` (test)
4. **Task 2 GREEN: hoist the python3 check into the loop's match branch** - `f87b445` (fix)
5. **Task 3: replace `<that-path>` with `$AGY_PATH`, add I22** - `3760368` (fix)

## Files Created/Modified

- `.claude/commands/agy-setup.md` — fallback block's success arm now prints instead of execs; `json.load` wrapped in try/except; new standalone `bash "$RESOLVED"` block; `$AGY_PATH` replaces `<that-path>` in step 1, both opt-in variants, and the Uninstall section
- `.claude/commands/agy-uninstall.md` — identical shape, targeting `uninstall.sh`
- `scripts/install.sh` — python3-presence check moved from unconditional-before-the-loop to inside the loop's existing recursive-alias-match branch, with a new `_alias_patch_py3_warned` flag keeping the warning to once per run
- `tests/run-tests.sh` — `_md_fallback_case` redesigned (Tests A-D replace the four one-shot tests); new cases `I19b`, `I22`

## Decisions Made

- Test A reuses the review's exact hostile-fixture shape (`agy-delegate@evil-marketplace` before `agy-delegate@real-marketplace`) rather than a different lookalike construction, so the RED demonstrates the identical reported attack.
- Test B's doc-line extraction uses `grep -x` (exact whole line), not `grep -c`/`grep -F` (substring), specifically because both docs carry a pre-existing, legitimate "e.g. ... bash \"$RESOLVED\"" mention in the opt-in-variants prose that a substring count would collide with — independently verified this discriminates pre-fix (0), correct-fix (1), and broken-fix-with-the-line-missing (0) correctly in all three states.
- Test B executes the line text extracted from the live doc file, never a `bash "$RESOLVED"` the test writes itself — a doc shipped with the second line simply absent must fail Test B even though Test A alone would still pass.
- WR-01's fix hoists only the *dependency check* into the loop's existing match branch; the `_alias_patch_py3_ok` flag's own `continue` gate stays exactly where 04-02 sited it (after the dry-run advisory's continue, before the `cp -f` backup) — verified via line-number ordering (`command -v python3` at line 241, strictly between the match `if` at 233 and `cp -f` at 248).
- Task 3 is not TDD (no runtime mechanism, only doc text) — its one new negative-grep case (`I22`) lands in the same commit as the doc fix rather than a separate test-then-fix pair, matching the plan's own framing.

## Deviations from Plan

None — plan executed exactly as written. All three tasks, every `must_haves` truth/artifact, and every locked mechanism (the two-step split, the `grep -x` discrimination, the hoist-into-loop-branch structure, the `$AGY_PATH` capture) were followed without deviation. Both RED observations were confirmed for the exact stated reason before their GREEN commits landed.

## Issues Encountered

- The sandboxed shell environment intercepts some bare multi-pattern `grep -E` invocations containing escaped alternation (`\|`) with a `lean-ctx` path-scoping error unrelated to the actual command; retrying with plain `-E '|'` alternation (no backslash-escaping) worked reliably. This affected only my own manual exploration commands during this session, never the shipped test harness or its assertions.

## Known Stubs

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Phase 4 is now complete across all three plans (`04-01`, `04-02`, `04-03`): the SIGPIPE-safe fallback (04-01), the HOME precondition and python3 fail-open guard (04-02), and this plan's gap closures (CR-01/CR-02/WR-01/WR-02/IN-01) all ship together.
- All three review-surfaced beads (`delegate-agy-5r9.7`, `delegate-agy-5r9.8`, `delegate-agy-5r9.9`) are closed, each with a comment naming its closing commit hash.
- Full suite: `PASS=160 FAIL=0` (158 baseline + `I19b` + `I22`; `I21`/`I21b` redesigned in place, not net-new).
- No blockers for Phase 5 or Phase 6 — this plan's file surface (`agy-setup.md`, `agy-uninstall.md`, `scripts/install.sh`, `tests/run-tests.sh`) is the same surface 04-01/04-02 already isolated from both.

---
*Phase: 04-installer-and-launcher-surface*
*Completed: 2026-08-21*

## Self-Check: PASSED

All 4 modified files and this SUMMARY.md itself found on disk; all 5 commit hashes (9380446, e11bb9d, 90eec6d, f87b445, 3760368) found in `git log --oneline --all`.
