---
phase: 02-model-list-handling-end-to-end
plan: 01
subsystem: agy_bridge.sh model-list fetch/cache path
tags: [bash, cache-poisoning, tdd, tracer]
status: complete
dependency-graph:
  requires: []
  provides:
    - "D-03 write gate on scripts/agy_bridge.sh's models cache (S4 tracer half)"
    - "D-04 stale-cache fallback for a degraded-but-successful agy models reply"
    - "D-05 distinct degraded-list warning literal"
    - "D-07 unconditional agy stderr relay (closes criterion 3's last gap)"
    - "D-08 SIGPIPE-safe herestring form for the degraded-list test (2 sites in agy_bridge.sh)"
    - "D-06 proof that cut -f1 normalizes an extra column and a trailing tab on the real fetch path"
  affects:
    - "Plan 02-02 (scripts/gemini_shim.sh) mirrors this shape -- D-08's herestring exception, D-03's gate, D-04's fallback"
tech-stack:
  added: []
  patterns:
    - "Gate an existing atomic tmp-then-mv write with a condition, don't rewrite the write itself"
    - "Reuse the existing fetch-failure fallback branch for a new failure class (degraded-but-successful) instead of adding a parallel branch"
    - "Relocate a diagnostic relay to fire unconditionally rather than duplicating it per branch"
key-files:
  created: []
  modified:
    - /home/dd/Gemini/delegate-agy/.worktrees/agy-1.6.2/scripts/agy_bridge.sh
    - /home/dd/Gemini/delegate-agy/.worktrees/agy-1.6.2/tests/run-tests.sh
    - /home/dd/Gemini/delegate-agy/.worktrees/agy-1.6.2/tests/fake-agy.sh
decisions:
  - "D-04's no-cache path leaves \$_agy_models untouched (not cleared unconditionally) so the shipped criterion-3 check at :515 (now use-time, herestring form) is what reports the degraded-list message -- clearing it unconditionally would let the generic 'failed to retrieve model list' fatal at :506 fire first and lose R8's distinct message, per the plan's Alternatives Considered B."
  - "D-07's stderr relay is relocated, not duplicated -- one line moved from inside the else block to immediately after the whole if/elif/else, firing whenever \$_agy_err has content on any branch (fetch failure, degraded success, or plain success where it's empty and silent)."
  - "D-08 converts both the new write-gate AND the existing :515 use-time check to the herestring form (\`grep -q '^gemini-' <<< \"\$var\"\`), a narrow, user-approved exception to the D-01/D-02 closed-criteria boundary -- the printf|grep -q pipe form is not fully pipefail-safe (an early grep -q match can SIGPIPE the upstream printf, and bash reports the pipeline's status as the SIGPIPE'd producer's 141, not grep's 0)."
metrics:
  duration: "~2h"
  completed: 2026-08-20
actuals:
  tokens: 2880
  tasks: 3
  commits: 5
---

# Phase 02 Plan 01: Model-list cache-poisoning gate on the bridge (D-03/D-04/D-05/D-06/D-07/D-08) Summary

Closed S4's remaining half (`delegate-agy-8ph`) on `scripts/agy_bridge.sh`: a degraded (gemini--less) `agy models` reply can no longer overwrite the shared cache the shim also reads, a degraded-but-successful reply now falls back to a good stale cache instead of failing loud, and agy's own stderr diagnostic now surfaces on every fetch outcome that has one -- closing the last open half of criterion 3.

## What Was Built

**Task 1 (D-03, D-08, tracer)** — `_agy_ids` (a new `cut -f1`-normalized variable, computed once in the fetch-success branch) gates the existing atomic tmp-then-`mv` cache write behind `if grep -q '^gemini-' <<< "$_agy_ids"`. A gemini--less reply is never persisted; an absent cache stays absent, a present one survives byte-identical. The existing use-time check at the old `:515` (criterion 3's shipped degraded-list detector) was also converted from a `printf '%s\n' "$VALID_MODELS" | grep -q '^gemini-'` pipe to the same herestring form, per D-08's narrow, user-approved exception to the D-01/D-02 closed-criteria boundary — the pipe form is not fully `pipefail`-safe (empirically reproduced hazard, see `02-CONTEXT.md` §D-08: bash 5.3.15, 5/5 iterations at ~500KB input with an early match, pipe form → `rc=141`, herestring form → `rc=0`).

**RED observed (Task 1):** R9's preservation half failed before the production edit --
```
FAIL - R9 a degraded agy models reply never reaches the cache file, absent or present
       absent-half: rc=2 cache_exists=yes out=ERROR: agy model list contains no 'gemini-' ids; ...
       preservation-half: before=[gemini-3.1-pro-high	Gemini 3.1 Pro (High)] after=[Please run 'agy auth login' first.
       no models available];
```
(The absent-half already passed pre-fix, matching D-03's spec that only the preservation half is expected RED.)

**Task 2 (D-04, D-05, D-07)** — Extended the D-03 gate's `if` with an `elif [[ -s "$CACHE_FILE" ]]`: when the fetch is degraded but a stale cache exists, the bridge prints a new, distinctly-worded warning (`WARNING: 'agy models' returned a list with no 'gemini-' ids (agy may be unauthenticated); using the stale cached list.`) and clears `$_agy_models`, so the existing cache-read fallback a few lines below serves the call at rc 0. The cache file itself is never touched by this arm, so its mtime — and the `-mmin +60` TTL window — stay exactly as they were. Separately, the existing `[[ -s "$_agy_err" ]] && sed 's/^/       agy: /' "$_agy_err" >&2` relay was **relocated** (not duplicated) from inside the fetch-failure `else` block to immediately after the whole `if/elif/else`, so agy's own stderr now shows on the degraded-but-successful path too — closing the criterion-3 gap this phase folded in during planning review (D-07). `tests/fake-agy.sh` gained one new stderr literal, `FAKE-AGY-DEGRADED: not authenticated`, in the `models` garbage branch only (parallels the existing `FAKE-AGY-AUTH-FAILURE` in the fail branch).

**RED observed (Task 2):** R8's new third clause and all of R9b's rc/model/WARNING/stderr clauses failed before the production edit --
```
FAIL - R8 model list with no gemini ids reports a degraded list, not a bad --type
       rc=2 out=ERROR: agy model list contains no 'gemini-' ids; agy may be unauthenticated
       or its 'agy models' output format changed. Run 'agy models' to inspect.
FAIL - R9b a degraded reply with a stale cache falls back at rc 0, warns distinctly, shows agy's stderr, mtime untouched
       rc=2 (want 0); model not resolved from cache, out=ERROR: agy model list contains no 'gemini-' ids; ...;
       no WARNING in out=ERROR: ...; agy's own stderr (FAKE-AGY-DEGRADED) not shown, out=ERROR: ...
```

**Task 3 (D-06)** — Test-only: R9c drives a real `agy models` fetch through a synthetic scratch fixture (`AGY_FIXTURES_DIR`, never `tests/fixtures/agy-models.tsv` per D-14/D-14a) containing a 3-column row (`gemini-9.4-flash-high<TAB>display<TAB>extra`) and a trailing-tab row (`gemini-9.3-pro-high<TAB>`), proving `cut -f1` normalizes both identically to a plain 2-column row, through the bridge's whole fetch → gate → normalize → match path (not merely the cache-read normalization R3c already proves). The two anchored auto-select matchers (`^gemini-[0-9.]+-flash-high$`, `^gemini-[0-9.]+-pro-high$`) are byte-identical to their pre-phase state — confirmed via `git diff` on `scripts/agy_bridge.sh` showing zero changes for this task. No production code changed in this task.

**R9c mutation-proof (per acceptance criteria):** temporarily changed the 3-column row's id from `gemini-9.4-flash-high` to `gemini-9.4-MUTATED-nomatch`, re-ran the suite, observed:
```
FAIL - R9c an extra column and a trailing tab both normalize through the real fetch path
```
(PASS=137 FAIL=1), then reverted the mutation and re-ran to confirm PASS=138 FAIL=0 again — R9c is proven capable of failing, not a vacuous pass.

## The criterion-3 stderr gap is now proven, not carried forward as an assumption

`02-CONTEXT.md`'s D-07 originally flagged this as a follow-up to raise as a bd issue; the planning round folded it into this plan's Task 2 instead. It is now a closed `must_haves.truths` item (R8's third clause + R9b's stderr clause, both green). A future reader should not go looking for a still-open bd ticket on this — none was ever filed, because the gap was closed here.

## Remaining flagged assumption (carried forward verbatim, unresolved by this plan)

> FLAGGED, UNRESOLVED — the S4 edge probe returned `unclassified`, so no automated edge predicate was derived for the two-independent-writers concurrency requirement. Everything this phase asserts is single-process and sequential: no test here runs the bridge and the shim concurrently against the same cache path. The concurrency property S4 names rests on the tmp-then-`mv` rename being atomic, which this phase preserves but does not test.

## Tracer Feedback Gate

Task 1 is `type="tracer"`. Its `<verify>` (the full suite, `bash tests/run-tests.sh`) was re-run end-to-end immediately after Task 1's commit and reported PASS=136 FAIL=0 with R9 green and R1-R8/RB27 unaffected, before Task 2's expansion began — the gate the plan's execution flow requires before building on a tracer slice. No separate interactive checkpoint was raised: this plan carries `autonomous: true` in its own frontmatter and was dispatched for full, non-interactive completion of all three tasks with per-task commits, matching a batch/autonomous run rather than one with a human watching between tasks.

## Verification (plan-level, run once after all 3 tasks)

- `bash tests/run-tests.sh` → **PASS=138 FAIL=0**
- R9, R9b, R9c: all `ok`
- R1, R2, R3, R3b, R3c, R3d, R5, R6, R7, R8, RB01, RB02, RB03, RB27, CC04a, CC04b, CC06: all still `ok`
- `bash -n scripts/agy_bridge.sh` → exits 0
- `git diff --stat 3c24f56 HEAD` (pre-phase baseline → this plan's tip) names exactly three files: `scripts/agy_bridge.sh` (40 changed lines), `tests/run-tests.sh` (113 changed lines), `tests/fake-agy.sh` (1 line)
- `git diff 3c24f56 HEAD -- tests/fixtures/ scripts/gemini_shim.sh` → empty
- `grep -cF "sed 's/^/       agy: /'" scripts/agy_bridge.sh` → 1 (relocated, not duplicated)
- `grep -cF "grep -q '^gemini-' <<<" scripts/agy_bridge.sh` → 2 (the new write-gate and the converted `:515`-era use-time check); zero `printf ... | grep -q '^gemini-'` pipe forms remain

## Deviations from Plan

None — plan executed exactly as written, including the three items folded into scope during planning review (D-07's stderr relocation, D-08's herestring exception, D-06's synthetic-row test).

## Known Stubs

None.

## Threat Flags

None — this plan's threat surface (T-02-01 through T-02-05, T-02-SC) was fully named in the plan's own `<threat_model>` and closed by this work; no new surface was introduced beyond what the plan already registered.

## Commits

- `9508fa5` test(02-01): R9 pins a degraded agy models reply never reaching the cache (RED)
- `e615439` feat(02-01): gate the models cache write on a non-degraded reply (D-03, D-08)
- `4beb274` test(02-01): R9b pins the D-04/D-05/D-07 stale-cache fallback (RED)
- `d706563` feat(02-01): stale-cache fallback for a degraded fetch, relocate stderr relay (D-04, D-05, D-07)
- `f6c20d8` test(02-01): R9c proves cut -f1 normalizes an extra column and a trailing tab (D-06)

All five commits are on `fix/agy-bridge-resilience` in `/home/dd/Gemini/delegate-agy/.worktrees/agy-1.6.2`.

## Self-Check

- `scripts/agy_bridge.sh` — FOUND, modified (40 changed lines vs. pre-phase baseline)
- `tests/run-tests.sh` — FOUND, modified (113 changed lines vs. pre-phase baseline)
- `tests/fake-agy.sh` — FOUND, modified (1 changed line vs. pre-phase baseline)
- Commit `9508fa5` — FOUND in `git log --oneline --all`
- Commit `e615439` — FOUND in `git log --oneline --all`
- Commit `4beb274` — FOUND in `git log --oneline --all`
- Commit `d706563` — FOUND in `git log --oneline --all`
- Commit `f6c20d8` — FOUND in `git log --oneline --all`

## Self-Check: PASSED
