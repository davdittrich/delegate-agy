---
phase: 02-model-list-handling-end-to-end
plan: 02
subsystem: gemini_shim.sh model-list fetch/cache path
tags: [bash, cache-poisoning, tdd]
status: complete
dependency-graph:
  requires:
    - "Plan 02-01: D-03 write gate, D-04 stale-cache fallback, D-08 herestring exception, all on scripts/agy_bridge.sh"
  provides:
    - "D-03 write gate on scripts/gemini_shim.sh's load_models() cache write (S4 shim half)"
    - "D-04 stale-cache fallback for a degraded-but-successful agy models reply, silent (D-05)"
    - "D-08 herestring form applied to the shim's new gate and to map_model's existing :459 warning-gate check (2 sites)"
    - "D-06 proof that cut -f1 normalizes an extra column and a trailing tab on the shim's real fetch path"
    - "S4 (delegate-agy-8ph) closed: both writers of ~/.cache/agy-bridge-models now gate the same way"
    - "S1 closed on the shim's entry point (criterion 4)"
  affects:
    - "REQUIREMENTS.md S1/S4 traceability rows -- both move from partial to met"
tech-stack:
  added: []
  patterns:
    - "Gate an existing atomic tmp-then-mv write with a condition, don't rewrite the write itself (mirrors 02-01)"
    - "Reuse the existing fetch-failure fallback branch (the shipped cat \"$MODELS_CACHE\" read) for a new failure class (degraded-but-successful) instead of adding a parallel branch"
    - "The bridge warns on the degraded-fallback path; the shim stays silent -- same mechanism, deliberately different message policy, both pinned by tests"
key-files:
  created: []
  modified:
    - /home/dd/Gemini/delegate-agy/.worktrees/agy-1.6.2/scripts/gemini_shim.sh
    - /home/dd/Gemini/delegate-agy/.worktrees/agy-1.6.2/tests/run-tests.sh
decisions:
  - "D-03's write gate lives in load_models() only: a new `ids` local (cut -f1-normalized, computed once in the fetch-success branch) gates the existing tmp-then-mv write behind `grep -q '^gemini-' <<< \"$ids\"`. No new function, no new variable beyond `ids`."
  - "D-08's herestring conversion touches exactly two sites in gemini_shim.sh: the new write-gate and the existing map_model warning-gate check (formerly `printf '%s\\n' \"$LIVE_MODELS\" | grep -q '^gemini-'`, now `grep -q '^gemini-' <<< \"$LIVE_MODELS\"`) -- mirrors the identical, narrow D-01/D-02 exception plan 02-01 applied to agy_bridge.sh's write-gate and its :515-era use-time check. map_model's other two matchers (`grep -qxF \"$m\"` at the live-id check, `grep -E \"^gemini-[0-9.]+-${class}$\"` at class resolution) are untouched -- confirmed via grep counts, not by eyeballing."
  - "D-04's fallback is a single `elif [[ -s \"$MODELS_CACHE\" ]]; then raw=\"\"; fi` on the same if the gate built. No new branch below it, no second cache read, no new variable beyond task 1's `ids`. The already-shipped fallback read a few lines below (`[[ -n \"$raw\" ]] || raw=$(cat \"$MODELS_CACHE\" ...)`) does the rest."
  - "D-05: the shim adds no stderr line, no fd-9 write, on the degraded-fallback path -- unlike the bridge, which warns. Verified structurally: `load_models()`'s body still greps to zero `>&2`/`>&9` occurrences outside comments, unchanged from its pre-plan value."
  - "The criterion-3 stderr-relay gap 02-01 closed does not apply to this side: `load_models()`'s fetch already redirects agy's own stderr to `2>/dev/null` (unlike the bridge, which keeps it in a file to relay). There was nothing to relocate here; recorded as resolved in 02-01, not carried into this plan, per the plan's own `must_haves.assumptions`."
  - "SH15c (D-06) required no production change -- the shim's `cut -f1` and map_model's matchers were already correct end to end; the task exists to prove that on the shim's real fetch path (AGY_FIXTURES_DIR), not to fix anything."
metrics:
  duration: "~1h"
  completed: 2026-08-20
actuals:
  tokens: 2628
  tasks: 3
  commits: 5
---

# Phase 02 Plan 02: Model-list cache-poisoning gate on the shim (D-03/D-04/D-05/D-06/D-08) Summary

Mirrored plan 02-01's bridge fix into `scripts/gemini_shim.sh`'s `load_models()`: a degraded (gemini--less) `agy models` reply can no longer overwrite the shared cache the bridge also reads, and a degraded-but-successful reply now falls back to a good stale cache instead of resolving models off garbage — silently, per the shim's own decision to never emit box-wide log noise. This closes `S4` (`delegate-agy-8ph`) on both writers and closes `S1` on the shim's entry point.

## What Was Built

**Task 1 (D-03, D-08)** — `ids` (a new `cut -f1`-normalized local, computed once inside the existing non-empty-`raw` guard) gates the existing atomic tmp-then-`mv` cache write behind `if grep -q '^gemini-' <<< "$ids"`. A gemini--less reply is never persisted: an absent cache stays absent, a present one survives byte-identical. `map_model`'s existing warning-gate check (previously `printf '%s\n' "$LIVE_MODELS" | grep -q '^gemini-'`) was also converted to the same herestring form, per D-08's narrow, user-approved exception to the D-01/D-02 closed-criteria boundary — mirroring the identical conversion plan 02-01 applied to `agy_bridge.sh`'s write-gate and its own use-time check. `map_model`'s other two matchers (the verbatim-id `grep -qxF` and the class-resolution `grep -E "^gemini-[0-9.]+-${class}$"`) are untouched.

**RED observed (Task 1, SH15):**
```
FAIL - SH15 a degraded agy models reply never reaches the cache file, absent or present
       absent-half: rc=0 model=flash cache_exists=yes out=ok; preservation-half: before=[gemini-3.1-pro-high	Gemini 3.1 Pro (High)] after=[Please run 'agy auth login' first.
no models available];
```
Both halves failed pre-fix (unlike the bridge's R9, where the absent-half already passed pre-fix) — the shim's shipped `load_models()` caches any non-empty fetch unconditionally, so a degraded reply both creates an absent cache and overwrites a present one.

**Task 2 (D-04, D-05)** — Extended Task 1's `if` with `elif [[ -s "$MODELS_CACHE" ]]; then raw=""; fi`: when the fetch is degraded but a stale cache exists, `raw` is cleared so the already-shipped fallback read (`[[ -n "$raw" ]] || raw=$(cat "$MODELS_CACHE" ...)`, unchanged) resolves the model off the cache instead. The cache file itself is never touched by this arm, so its mtime — and the TTL window — stay exactly as they were. Unlike the bridge, the shim adds **no** stderr line here (D-05): this script shadows `gemini` on PATH, and a warning would land in every Octopus/Metaswarm log line. `load_models()`'s criterion-3 stderr-relay gap that 02-01 closed on the bridge does not exist on this side — the shim's fetch already redirects agy's own stderr to `2>/dev/null`, so there was nothing to relocate here (resolved in 02-01, not this plan's work, per the plan's own `must_haves.assumptions`).

**RED observed (Task 2, SH15b):**
```
FAIL - SH15b a degraded reply falls back to a good stale cache, silently, mtime untouched
       model not resolved from cache, got=flash;
```
Only the resolution assertion failed — Task 1's gate already stopped the cache mutation, so the mtime/no-WARNING/byte-identical checks in SH15b's accumulating detail string all passed even pre-fix; the argv still carried the raw name (`flash`) instead of the cached `gemini-7.7-flash-high` id.

**Task 3 (D-06)** — Test-only: SH15c drives a real `agy models` fetch through a synthetic scratch fixture (`AGY_FIXTURES_DIR`, never `tests/fixtures/agy-models.tsv` per D-14/D-14a) containing a 3-column row (`gemini-9.4-flash-high<TAB>SH15c Flash<TAB>extra-column`) and a trailing-tab row (`gemini-9.3-pro-high<TAB>`), proving `cut -f1` normalizes both identically through the shim's whole fetch → gate → normalize → `map_model` path — the shim-side twin of plan 02-01's R9c. No production code changed in this task; `SH15c` passed immediately on first write, since the shim's `cut -f1` and `map_model`'s matchers were already correct.

**SH15c mutation-proof (per acceptance criteria):** temporarily changed only the 3-column row's id in SH15c's own fixture-construction line from `gemini-9.4-flash-high` to `gemini-9.4-MUTATED-nomatch` (leaving SH15c's assertion and the bridge's R9c — which shares the same literal id — untouched), re-ran the suite, observed:
```
FAIL - SH15c an extra column and a trailing tab both normalize through the real fetch path
```
(PASS=140 FAIL=1, `R9c` still `ok`), then reverted the mutation and re-ran to confirm PASS=141 FAIL=0 again — SH15c is proven capable of failing, and proven not to have silently coupled to the bridge's fixture.

## Side-by-side: how the shim's block differs from the bridge's, and why

The two blocks are a maintenance contract (`scripts/gemini_shim.sh:378-386` states why they are duplicated, not shared) — the next reader will diff them, so the differences are recorded here rather than left implicit:

| Aspect | `agy_bridge.sh` | `gemini_shim.sh` | Why |
|---|---|---|---|
| Degraded-fallback message | `echo "WARNING: ..." >&2` (D-05) | Silent — no line added | The bridge is a deliberate delegation call the operator is watching; the shim shadows `gemini` for every PATH caller, so a warning here is box-wide noise (D-05). |
| agy's own stderr relay | Relocated to fire unconditionally after the fetch if/elif/else (D-07, closed a criterion-3 gap) | Not applicable — `load_models()`'s fetch already redirects agy's stderr to `2>/dev/null`, always | Nothing to relocate on this side; the gap D-07 closed never existed here (resolved in 02-01, not carried forward per plan's `must_haves.assumptions`). |
| Variable holding the fetched list | `_agy_models` (top-level script scope) | `raw` (local to `load_models()`) | Different scope by construction — the bridge has no function boundary here, the shim does. |
| Normalized-id variable for the gate | `_agy_ids` | `ids` | Same role, different name to match each file's existing naming (`_agy_*` prefix vs. bare locals). |
| No-cache degraded outcome | rc=2, distinct `ERROR: ... no 'gemini-' ids ...` message (criterion 3) | rc=0, name passed through unchanged, silent (`map_model`'s existing warning gate, now herestring) | The bridge treats a degraded list as fatal by design (S1); the shim never refuses a name — refusing would break every PATH caller using a model the map has never heard of. This asymmetry predates this plan and is unchanged by it. |

## D-08's herestring fix (both plans, narrow scope)

Cross-AI review found `printf ... | grep -q '^gemini-'` is not fully `pipefail`-safe (an early `grep -q` match can SIGPIPE the upstream `printf`, and bash reports the pipeline's status as the SIGPIPE'd producer's 141, not `grep`'s 0 — reproduced empirically on the bridge in plan 02-01, bash 5.3.15). This plan converts the shim's two analogous sites: the new write-gate (built herestring from the start) and the existing `map_model` warning-gate check at the old `:459`. This is a deliberate, narrow, user-approved exception to the D-01/D-02 closed-criteria boundary — mirroring plan 02-01's identical conversion of `agy_bridge.sh`'s write-gate and its `:515`-era use-time check — not scope creep. Verified structurally, not just by inspection: `grep -cF "grep -q '^gemini-' <<<" scripts/gemini_shim.sh` returns 2, no `printf ... | grep -q '^gemini-'` pipe form remains, and `grep -qxF`/`grep -E "^gemini-` each still return exactly 1 (the exact-match and class-resolution lines are byte-identical to their pre-plan state).

## Remaining flagged assumption (carried forward verbatim, unresolved by this plan)

> FLAGGED, UNRESOLVED — carried forward from 02-01: the S4 edge probe returned `unclassified`, so no automated edge predicate was derived for the two-independent-writers concurrency requirement. No test in this phase runs the bridge and the shim concurrently against the same cache path. The concurrency property rests on the tmp-then-`mv` rename being atomic, which this phase preserves but does not test.

## Verification (plan-level, run once after all 3 tasks)

- `bash tests/run-tests.sh` → **PASS=141 FAIL=0**
- SH15, SH15b, SH15c: all `ok`; R9, R9b, R9c (plan 02-01): all still `ok`
- SH7, SH8, SH9, SH10, SH11, SH12, SH13, SH14, R1, R2, R3, R3b, R3c, R3d, R4, R5, R6, R7, R8, RB01, RB01m, RB02, RB02m, RB03, RB27, CC04a, CC04b, CC06: all still `ok`
- `bash -n scripts/gemini_shim.sh` and `bash -n scripts/agy_bridge.sh` → both exit 0
- Both writers carry the gate (read side by side, not counted — the two differ in variable names by necessity): `scripts/agy_bridge.sh`'s `if grep -q '^gemini-' <<< "$_agy_ids"` and `scripts/gemini_shim.sh`'s `if grep -q '^gemini-' <<< "$ids"`
- `grep -cF "grep -q '^gemini-' <<<" scripts/gemini_shim.sh` → 2; no `printf ... | grep -q '^gemini-'` pipe form remains
- `grep -cF "grep -qxF" scripts/gemini_shim.sh` → 1; `grep -cF 'grep -E "^gemini-' scripts/gemini_shim.sh` → 1 (both matchers byte-identical to pre-plan state)
- `git diff --stat f6c20d8 HEAD` (02-01's tip → this plan's tip) names exactly two files: `scripts/gemini_shim.sh` (39 changed lines), `tests/run-tests.sh` (123 changed lines)
- `git diff --stat 3c24f56 HEAD -- tests/fixtures/ config/model-map.json README.md` → empty across the whole phase
- `git diff --stat f6c20d8 HEAD -- tests/fake-agy.sh` → empty — this plan touches no fixture/fake-agy file (02-01's one-line addition there is 02-01's surface, not this plan's)
- Within `load_models()`'s body: `grep -v '^[[:space:]]*#' | grep -cE '>&(2|9)'` → 0, unchanged from its pre-plan value

## Deviations from Plan

None — plan executed exactly as written, including D-08's herestring conversion (folded in during planning review, same as plan 02-01) and SH15c's mutation-proof.

## Known Stubs

None.

## Threat Flags

None — this plan's threat surface (T-02-06 through T-02-10, T-02-05 carried, T-02-SC) was fully named in the plan's own `<threat_model>` and closed by this work; no new surface was introduced beyond what the plan already registered.

## Commits

- `92c0cac` test(02-02): SH15 pins a degraded agy models reply never reaching the cache (RED)
- `485b7b9` feat(02-02): gate the shim's models cache write on a non-degraded reply (D-03, D-08)
- `416606e` test(02-02): SH15b pins the D-04/D-05 stale-cache fallback (RED)
- `b5fdb03` feat(02-02): stale-cache fallback for a degraded shim fetch (D-04, D-05)
- `a7ab6bd` test(02-02): SH15c proves cut -f1 normalizes an extra column and a trailing tab (D-06)

All five commits are on `fix/agy-bridge-resilience` in `/home/dd/Gemini/delegate-agy/.worktrees/agy-1.6.2`.

## Self-Check

- `scripts/gemini_shim.sh` — FOUND, modified (39 changed lines vs. 02-01's tip)
- `tests/run-tests.sh` — FOUND, modified (123 changed lines vs. 02-01's tip)
- Commit `92c0cac` — FOUND in `git log --oneline --all`
- Commit `485b7b9` — FOUND in `git log --oneline --all`
- Commit `416606e` — FOUND in `git log --oneline --all`
- Commit `b5fdb03` — FOUND in `git log --oneline --all`
- Commit `a7ab6bd` — FOUND in `git log --oneline --all`

## Self-Check: PASSED
