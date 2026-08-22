---
phase: 03-the-exit-code-contract
plan: 02
subsystem: gemini_shim.sh external-kill message + agy_bridge.sh generic-nonzero message formatting; README exit-137 row
tags: [bash, tdd, exit-codes, json-envelope, docs]
status: complete
dependency-graph:
  requires:
    - "EC_KILL9_TAIL (agy_bridge.sh, plan 03-01) — mirrored verbatim into gemini_shim.sh by this plan's task 1"
    - "_err_txt guard pattern (agy_bridge.sh's external-kill branch, plan 03-01) — reused verbatim by this plan's task 1 (shim) and task 2 (bridge generic-nonzero)"
  provides:
    - "EC_KILL9_TAIL — now defined byte-identically in BOTH scripts/agy_bridge.sh and scripts/gemini_shim.sh, pinned across both plus README by EC05"
    - "The bridge's generic-nonzero plain-text arm (agy_bridge.sh:765) guards its stderr suffix the same way EC01 already proved on the external-kill branch"
  affects:
    - "Plan 03-03 (README's remaining exit-code rows, D-05/D-07) inherits the divergence-note requirement covering BOTH bridge-vs-shim wording AND bridge-text-vs-bridge-JSON output-mode divergence on the generic-nonzero branch, per this plan's must_haves.truths"
tech-stack:
  added: []
  patterns:
    - "Guard a separator suffix once via bash's ${var:+word} parameter expansion — applied to a second call site (bridge generic-nonzero) and mirrored into a second script (shim external-kill), same shape as plan 03-01's original site"
    - "Hoist a literal shared between two scripts into one file-scope shell constant per script, pinned by a test that counts the ASSIGNMENT form exactly once (RB03/EC05 precedent) rather than 'at least one'"
    - "Prove a provenance/pinning test is not vacuous via a manual, git-status-tracked mutation of the real file (never a $SANDBOX copy) — reverted by rewriting the exact line, never git checkout/restore/reset/stash"
key-files:
  created: []
  modified:
    - /home/dd/Gemini/delegate-agy/scripts/gemini_shim.sh
    - /home/dd/Gemini/delegate-agy/scripts/agy_bridge.sh
    - /home/dd/Gemini/delegate-agy/tests/run-tests.sh
    - /home/dd/Gemini/delegate-agy/README.md
decisions:
  - "The shim's external-kill fix reuses EC_KILL9_TAIL's IDENTICAL literal value (mirrored, not merely equivalent-in-meaning) so the two scripts' lines are byte-equal, not just similarly-worded — this is what makes EC03's cross-script comparison a meaningful, non-tautological test rather than two independently-written expected strings."
  - "The bridge's generic-nonzero JSON arm (agy_bridge.sh:759-763, open(sys.argv[4]).read()) is left completely untouched per the plan's explicit prohibition — it has no context prefix (\"ERROR: agy exit N: \") to dangle a separator off of, so it was never the defect delegate-agy-v5a named. Documenting this divergence in README is plan 03-03's job, not this plan's; this plan states the fact in must_haves.truths and leaves the code alone."
  - "EC05's mutation-red proof is a manual, one-time verification during task 3 execution (captured below with before/after evidence), not a permanent self-mutating case in the suite — matching RB03's own shape (a static provenance check, no runtime mutation) and Phase 1's established precedent for mutation-checked-but-not-embedded assertions."
  - "EC03's and EC04's 4th/3rd scenario (a printf-format-string stderr value, e.g. '100%s%d') double as T-03-04's mitigation evidence at both new call sites, reusing the same threat-register finding plan 03-01 already reproduced rather than re-deriving it."
metrics:
  duration: "~30min"
  completed: 2026-08-20
actuals:
  tokens: 2860
  tasks: 3
  commits: 5
---

# Phase 03 Plan 02: External-kill + generic-nonzero dangling-separator guard, mirrored and pinned Summary

Expanded plan 03-01's proven fix sideways to the two sites `03-CONTEXT.md` D-01/D-02/D-03 named but 03-01 didn't touch: the shim's own external-kill branch (the box-wide, PATH-shadowing entry point) and the bridge's generic-nonzero branch. Then pinned the shared `EC_KILL9_TAIL` literal across both scripts and README so the exact drift that produced `delegate-agy-6q1` (docs said one thing, code printed another) cannot recur silently. The bridge's generic-nonzero JSON arm and the shim's generic-nonzero relay are both explicitly untouched — verified by diff, not just by intent — per the plan's own prohibitions.

## What Was Built

**Task 1 (`delegate-agy-byv.3`, tdd)** — `gemini_shim.sh` gained `EC_KILL9_TAIL` at file scope, byte-identical to `agy_bridge.sh`'s (`' -- possible OOM or external kill'`), and its external-kill branch's `printf` was changed from an unconditional `... bound -- possible OOM or external kill: %s\n` (always appending `: ` + possibly-empty content) to the same guarded shape plan 03-01 already proved on the bridge: `... bound%s%s\n` fed `"$EC_KILL9_TAIL"` and `"${_err_txt:+: $_err_txt}"`.

**RED observed (Task 1, EC03):**
```
FAIL - EC03 shim external-kill message: byte-identical to the bridge's across 4 stderr scenarios, format-specifier rendered literally
```
(PASS=147 FAIL=1 — EC01/EC02/T5/SH6 unaffected.) EC03 compares the shim's line against the bridge's OWN line (not a separately-written expected string) across 4 stderr scenarios (empty, non-empty "boom", newline-only, and a printf-format-string value "100%s%d" for T-03-04), so the RED failure is against the bridge's already-fixed output, not a hand-written literal.

**GREEN (Task 1):** PASS=148 FAIL=0 (147 baseline + EC03).

**Task 2 (`delegate-agy-byv.4`, tdd)** — the bridge's generic-nonzero plain-text arm (`agy_bridge.sh:765`) was changed from `printf 'ERROR: agy exit %d: %s\n' "$EXIT_CODE" "$(cat "$STDERR_FILE" ...)"` (unconditional `: ` + possibly-empty content) to `_err_txt="$(cat "$STDERR_FILE" ...)"` computed once, then `printf 'ERROR: agy exit %d%s\n' "$EXIT_CODE" "${_err_txt:+: $_err_txt}"`. The JSON arm at the same branch (`:759-763`) was read, confirmed to have no context prefix to dangle a separator off of, and left byte-for-byte untouched — confirmed by `git diff` below, not just asserted.

**RED observed (Task 2, EC04):**
```
FAIL - EC04 bridge generic-nonzero plain-text message: no dangling separator empty, exact suffix non-empty, format-specifier literal
```
(PASS=148 FAIL=1 — EC01/EC02/EC03 unaffected.) Three scenarios: empty stderr (must end at `exit 5` with no colon), non-empty ("boom", must end `exit 5: boom`), and a format-specifier value ("100%s%d", T-03-04) — all against `FAKE_AGY_EXIT=5`, the generic-nonzero path.

**GREEN (Task 2):** PASS=149 FAIL=0 (148 + EC04).

**Task 3 (`delegate-agy-byv.5`, non-tdd)** — README's exit-137 troubleshooting row was restated to quote `EC_KILL9_TAIL`'s bytes verbatim AND state the stderr-suffix rule explicitly: `` : <agy's stderr> `` appended when agy wrote to stderr, nothing appended when it didn't; the row also now notes `agy-bridge` and the `gemini` shim word this identically (true as of task 1). `EC05` was added: it asserts `EC_KILL9_TAIL='...'` is defined EXACTLY once per script (comment lines filtered — RB03's own precedent, `tests/run-tests.sh:2427`), referenced by symbol at least once in each, and that README quotes the literal verbatim.

**EC05 mutation-red proof (manual, one-time, per the plan's cross-plan prohibition on this task):**
1. `git status --porcelain` captured before any mutation (only `README.md` and `tests/run-tests.sh` dirty — this plan's own uncommitted task-3 changes at that point; `scripts/agy_bridge.sh` clean).
2. `scripts/agy_bridge.sh:52`'s `EC_KILL9_TAIL` literal mutated by one character: `OOM` → `OOm`.
3. Full suite re-run: **PASS=148 FAIL=2** — both `EC03` (cross-script byte-identity, since the shim's copy still says `OOM`) and `EC05` (the assignment-count/verbatim check) caught it. Not vacuous.
4. Reverted by rewriting line 52 back to its exact original text (`sed` targeting the single line number, never `git checkout`/`restore`/`reset`/`stash`). `diff` against a pre-mutation copy of the file: empty (byte-identical revert).
5. `git status --porcelain` captured again: identical to step 1's capture.
6. Full suite re-run: **PASS=150 FAIL=0** (149 + EC05).

## Verification (plan-level, run once after all three tasks)

- `bash tests/run-tests.sh` → **PASS=150 FAIL=0** (147 pre-phase baseline + EC01 + EC02 [plan 03-01] + EC03 + EC04 + EC05 [this plan])
- `EC03`, `EC04`, `EC05` all report `ok`; each observed `FAIL` before its corresponding change (RED evidence above; EC05 via the manual mutation)
- `T5`, `SH6`, `B3`, `S5`, `RB03` all still report `ok`; `git diff 4eac0d3 HEAD -- tests/run-tests.sh` shows only additive insertions around the EC03/EC04/EC05 blocks, no edits to any pre-existing case body
- The shim's and the bridge's external-kill lines are byte-equal under 4 stderr scenarios (EC03: empty, non-empty, newline-only, format-specifier)
- `grep -ic 'unbounded' README.md` → `0`
- `git diff 4eac0d3 HEAD -- scripts/agy_bridge.sh scripts/gemini_shim.sh` (pasted above in "What Was Built") confirms: the bridge's generic-nonzero JSON arm and the shim's generic-nonzero plain-text relay (`cat "$STDERR_FILE" >&2`) are both byte-for-byte unchanged
- `git diff --diff-filter=D --name-only 4eac0d3 HEAD` → empty (no deletions)

## Deviations from Plan

None — plan executed exactly as written. `EC05`'s mutation-red proof was implemented as a manual, git-status-tracked verification during task 3 (documented above) rather than a permanent self-mutating case embedded in the suite; this is a judgment call within the plan's "Claude's Discretion" note on RB03-pattern conformance (RB03 itself is a static provenance check with no embedded mutation), not a reinterpretation of any must_have or prohibition. The plan's own prohibition text (git-status-before/after, never `git checkout`/`restore`/`reset`/`stash`) only makes sense against the real, git-tracked file — a `$SANDBOX`-copy mutation (the RB02m/RB01m style) would need none of that ceremony — so treating this as a one-time manual proof rather than an automated case is the reading that makes every clause in the prohibition load-bearing.

## Known Stubs

None.

## Threat Flags

None — this plan's threat surface (T-03-04 through T-03-08) was fully named in the plan's own `<threat_model>` and closed by this work; no new surface was introduced beyond what the plan already registered.

## Commits

- `cb257a1` test(03-02): add failing EC03 for shim external-kill dangling separator
- `facac7c` feat(03-02): guard shim external-kill message against dangling separator
- `0010eb7` test(03-02): add failing EC04 for bridge generic-nonzero dangling separator
- `7b91499` feat(03-02): guard bridge generic-nonzero message against dangling separator
- `fcdec5e` docs(03-02): pin EC_KILL9_TAIL across both scripts and README (EC05)

## Self-Check

- `scripts/gemini_shim.sh` — FOUND, modified
- `scripts/agy_bridge.sh` — FOUND, modified
- `tests/run-tests.sh` — FOUND, modified
- `README.md` — FOUND, modified
- Commit `cb257a1` — FOUND in `git log --oneline --all`
- Commit `facac7c` — FOUND in `git log --oneline --all`
- Commit `0010eb7` — FOUND in `git log --oneline --all`
- Commit `7b91499` — FOUND in `git log --oneline --all`
- Commit `fcdec5e` — FOUND in `git log --oneline --all`

## Self-Check: PASSED
