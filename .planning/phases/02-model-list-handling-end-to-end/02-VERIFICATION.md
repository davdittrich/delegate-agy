---
phase: 02-model-list-handling-end-to-end
verified: 2026-08-20T15:09:18Z
status: human_needed
score: 6/7 must-haves verified
behavior_unverified: 0
overrides_applied: 0
re_verification: null
behavior_unverified_items: 0
human_verification:
  - test: "Feed `scripts/agy_bridge.sh` (and separately `scripts/gemini_shim.sh`) a fake `agy models` that exits 0 with a genuinely zero-byte stdout (not the two-line 'Please run agy auth login' garbage `fake-agy.sh` currently emits), with a good stale cache present, then with none."
    expected: "The zero-byte reply is treated identically to a gemini--less reply: never written to the cache (absent stays absent, present survives byte-identical), and — with a stale cache present — the bridge falls back to it with the degraded-cause warning; the shim falls back silently. Both `_agy_ids`/`ids` are `cut -f1` of an empty string, so `grep -q '^gemini-' <<< \"\"` must fail exactly as it does for the non-empty garbage case."
    why_human: "Both plans (02-01-PLAN.md, 02-02-PLAN.md) tag this exact truth `verification: backstop` — a deliberate, explicit acknowledgment that no test exercises it. `tests/fake-agy.sh`'s only garbage mode (`FAKE_AGY_MODELS_GARBAGE`) always emits two non-empty lines before `exit 0` (`tests/fake-agy.sh:164-167`); grepping the suite for a genuinely empty-stdout-with-rc=0 models case finds none. The code path is the same `if grep -q '^gemini-' <<< \"$_agy_ids\"` gate R9/R9b/SH15/SH15b already exercise with non-empty degraded input, so the inference is strong, but per this project's own must_haves tagging convention it is presence-and-inference, not a behavioral pass, and must be flagged rather than silently counted as verified."
---

# Phase 2: Model-list handling, end to end Verification Report

**Phase Goal:** A bare environment cannot crash the bridge, and one bad `agy models` reply cannot degrade the other tool or blame the user for it.
**Verified:** 2026-08-20T15:09:18Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (ROADMAP.md Success Criteria — the contract)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `agy-bridge` invoked with no `HOME` set reaches its own argument handling instead of dying on an unbound variable, and an unwritable cache path leaks no redirect error to stderr | ✓ VERIFIED | `RB27` (`tests/run-tests.sh:3760-3800`) runs the bridge under `env -i PATH=... bash "$BRIDGE" --type code -- "no home here"`, asserts `rc=0`, the delegation actually completed (`FAKE_AGY_STDOUT` marker present in output), stderr contains neither `"unbound variable"` nor `"No such file or directory"`, and a static scan (`grep -n '\$HOME/' "$BRIDGE" "$SHIM" \| grep -v '\${HOME:-'`) finds zero unguarded `$HOME/` path-prefix uses in either script. Ran and observed `ok` in this session's own `bash tests/run-tests.sh` (PASS=145 FAIL=0). Pre-existing (RB27, R8, SH14) per ROADMAP.md's own note; this phase did not touch it and it still passes. |
| 2 | An `agy models` reply with no `gemini-` ids is never written to `~/.cache/agy-bridge-models` by either writer, so the other tool re-fetches rather than reading poison for up to an hour | ✓ VERIFIED | Read `scripts/agy_bridge.sh:482-483` (`_agy_ids="$(printf '%s\n' "$_agy_models" \| cut -f1)"; if grep -q '^gemini-' <<< "$_agy_ids"`) and `scripts/gemini_shim.sh:420-421` (identical gate on `ids`) — both writers gate the cache write behind the same normalize-then-`^gemini-` test, so a degraded reply is refused by construction on *both* sides; there is no scenario where one writer poisons and the other reads it. Behaviorally proven by `R9`/`R9b` (bridge) and `SH15`/`SH15b` (shim) in `tests/run-tests.sh`, each asserting an absent-cache half (nothing created) and a present-cache half (byte-identical before/after a degraded reply). All four `ok` in this session's run. `bd show delegate-agy-8ph` confirms CLOSED with the same evidence. |
| 3 | A caller who hits a `gemini-`-less model list is told agy is degraded/unauthenticated and shown agy's own stderr, not told their `--type` did not match | ✓ VERIFIED | `R8` (`tests/run-tests.sh:497-505`) asserts `rc=2`, output contains `"no 'gemini-' ids"` and `"FAKE-AGY-DEGRADED"`, and does NOT contain `"for --type"`. `R9b` extends this to the degraded-but-successful/stale-cache-fallback path, asserting the same `FAKE-AGY-DEGRADED` stderr marker appears there too (closing the one gap ROADMAP.md flagged as pre-existing — the relocated, unconditional relay at `scripts/agy_bridge.sh:523`, `[[ -n "$_agy_err" && -s "$_agy_err" ]] && sed 's/^/       agy: /' "$_agy_err" >&2`, confirmed present by direct read and by `grep -cF` returning 1, i.e. relocated not duplicated). Both `ok` in this session's run. |
| 4 | A tab-suffixed or extra-column `agy models` reply still resolves a model: input normalized, anchored `^gemini-[0-9.]+-<class>$` matchers byte-identical to what shipped | ✓ VERIFIED | `R9c` (bridge) and `SH15c` (shim) drive a real `agy models` fetch through a synthetic `AGY_FIXTURES_DIR` fixture carrying a 3-column row and a trailing-tab row, through the full fetch→gate→normalize→match path (not just cache-read normalization), asserting the extra column and the trailing tab both resolve to the correct bare id. Both `ok`, and both SUMMARYs record a mutation-proof (temporarily broke the id, observed the test go red, reverted, observed green again) — the tests are not vacuous. `CC06` (`shipped derivation: version-sort precision, $-anchored adjacency, deterministic`) is also `ok`, and `git diff --stat 3c24f56 HEAD -- tests/fixtures/ config/model-map.json README.md` is empty, confirming the anchored matchers at `agy_bridge.sh:548-549` and `gemini_shim.sh:471` were never touched. |

**Score (roadmap contract):** 4/4 verified.

### Additional Plan-Level Must-Have (finer-grained than the roadmap contract)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 5 | An `agy models` reply that exits 0 with zero bytes is degraded under the same rule as a `gemini-`-less reply (never cached, stale cache preferred) | ⚠️ insufficient_spec (routed to human verification) | Present in both `02-01-PLAN.md` and `02-02-PLAN.md` `must_haves.truths`, both explicitly tagged `verification: backstop`. No test in `tests/run-tests.sh` exercises a genuinely zero-byte `agy models` stdout — `tests/fake-agy.sh`'s only garbage mode (`FAKE_AGY_MODELS_GARBAGE`, `:164-167`) always writes two non-empty lines before `exit 0`. The claim follows logically from the same code path R9/R9b/SH15/SH15b already exercise (`cut -f1` of an empty string yields an empty herestring, which `grep -q '^gemini-'` correctly fails), but per this project's own tagging convention and this verifier's non-inferable-truth rule, presence-and-inference does not substitute for a behavioral pass. Not a gap — the mechanism genuinely is the same gate — but not counted as independently verified either. |

**Score (this phase's full must-have set):** 6/7 verified, 1 flagged for human confirmation (a 1-line test-fixture addition would close it — see Human Verification below).

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `scripts/agy_bridge.sh` | D-03 write gate, D-04 stale-cache fallback, D-05 warning, D-07 relocated stderr relay, D-08 herestring hardening, CR-01/WR-02/IN-01 fix-round hardening | ✓ VERIFIED | Read in full. All claimed mechanisms present, wired, and exercised by passing tests (lines 468-556). |
| `scripts/gemini_shim.sh` | Mirrored D-03/D-04/D-05(silent)/D-08, plus WR-01/IN-01 fix-round hardening | ✓ VERIFIED | Read in full. `load_models()` (`:404-454`) and `map_model()` (`:456-487`) carry the mirrored gate, fallback, and herestring conversions; silent on the degraded path as designed (no new `>&2`/`>&9` in the fallback arm). |
| `tests/run-tests.sh` | R9/R9b/R9c/R9d/R9e (bridge), SH15/SH15b/SH15c/SH15d (shim), IN01, R8 extension | ✓ VERIFIED | All test bodies read directly; each asserts real behavior (cache byte-comparison, mtime checks, argv dumps) rather than structural greps alone, except R9d/R9e/SH15d/IN01 which are explicitly, self-documented as structural (SIGPIPE reproduction and umask-window closure are not practically reproducible in a regression suite at this fixture size — same convention the 02-01/02-02 D-08 work already used). |
| `tests/fake-agy.sh` | One new `FAKE-AGY-DEGRADED` stderr literal in the garbage branch | ✓ VERIFIED | Confirmed at `:165`, garbage branch only; fail/hang branches untouched. |
| `.planning/phases/.../deferred-items.md` | RB24 flake documented, not silently dropped | ✓ VERIFIED | File exists, names the ticket (`delegate-agy-sup`) and the reproduction that confirmed it pre-existing. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| Bridge write-gate (`:483`) | Bridge use-time check (`:539`) | Same `cut -f1` + `^gemini-` rule, both herestring form | ✓ WIRED | `grep -cF "grep -q '^gemini-' <<<" scripts/agy_bridge.sh` → 2, confirmed directly (this session). Zero pipe-form remnants. |
| Shim write-gate (`:421`) | `map_model`'s warning gate (`:483`) | Same rule, herestring form | ✓ WIRED | `grep -cF "grep -q '^gemini-' <<<" scripts/gemini_shim.sh` → 2, confirmed directly. |
| Degraded-fetch stderr capture (`_agy_err`) | Unconditional relay after `if/elif/else` | Relocated, not duplicated | ✓ WIRED | `grep -cF "sed 's/^/       agy: /'" scripts/agy_bridge.sh` → 1, confirmed directly; `R9b` asserts `FAKE-AGY-DEGRADED` appears in output on the fallback path. |
| Cache write (`mv`) | `chmod 600` | `( umask 077; ... )` scoped subshell | ✓ WIRED | Present verbatim in both scripts at the write sites; `IN01` test asserts the exact subshell text via `grep -cF`, `ok` in this session's run. |

### Behavioral Spot-Checks / Full Suite Run

Ran the full suite once from `/home/dd/Gemini/delegate-agy/.worktrees/agy-1.6.2`:

```
bash tests/run-tests.sh
...
PASS=145 FAIL=0
```

All phase-relevant cases (R8, R9, R9b, R9c, R9d, R9e, SH14, SH15, SH15b, SH15c, SH15d, IN01, RB27, CC06) observed `ok` in this run. The roadmap-noted RB24 intermittent flake (`delegate-agy-sup`, filed and open, unrelated to this phase) did not reproduce in this run.

`git diff --stat 3c24f56 HEAD` (pre-phase baseline → current tip): exactly four files — `scripts/agy_bridge.sh` (52 lines), `scripts/gemini_shim.sh` (46 lines), `tests/fake-agy.sh` (1 line), `tests/run-tests.sh` (306 lines). `git diff --stat 3c24f56 HEAD -- tests/fixtures/ config/model-map.json README.md` is empty — no fixture, config, or doc drift.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|--------------|------------|--------------|--------|----------|
| S1 — Survive an `agy models` format change | 02-01-PLAN.md, 02-02-PLAN.md | Degraded list reported distinctly; tab/extra-column input normalizes; anchored matchers never loosened | ✓ SATISFIED | `REQUIREMENTS.md:89` marks it "met" with the same evidence (R9c/R8/R9b, SH15c) this verification independently confirmed by reading the code and running the suite. |
| S4 — Shared model cache safe under two independent writers | 02-01-PLAN.md, 02-02-PLAN.md | Neither writer caches a degraded reply; writes stay atomic | ✓ SATISFIED | `REQUIREMENTS.md:92` marks it "met"; `bd show delegate-agy-8ph` confirms CLOSED with matching evidence (R9/R9b, SH15/SH15b). The tmp-then-`mv` atomic-write mechanism is unchanged (confirmed by direct read); the two-writer-concurrency edge case is explicitly flagged `FLAGGED, UNRESOLVED` in both plans' `must_haves.assumptions` (not a `must_haves.truths` item) — S4's stated acceptance is "writes stay atomic," which the per-file `mv` rename structurally satisfies without a live concurrency test. Not a gap: this is the acceptance criterion as written in `REQUIREMENTS.md:70`, not a broader promise. |

No orphaned requirements: `ROADMAP.md`'s Requirement Coverage table maps only S1 and S4 to Phase 2, both are declared in both plans' frontmatter `requirements: [S1, S4]`, and both are addressed above.

### Anti-Patterns Found

None. Scanned `scripts/agy_bridge.sh` and `scripts/gemini_shim.sh` for `TBD|FIXME|XXX|TODO|HACK|PLACEHOLDER` — the only matches are `mktemp -t ...XXXXXX` template strings (false positives, not debt markers). Scanned the new lines added to `tests/run-tests.sh`/`tests/fake-agy.sh` (`git diff 3c24f56 HEAD --`) for the same markers — none found. No empty-implementation or hardcoded-empty-data patterns in the reviewed diff.

### Bug-Tracker Cross-Check

- `delegate-agy-8ph` (S4, the phase's core ticket) — CLOSED, evidence matches code.
- `delegate-agy-30m` (unguarded `$HOME` crash, no requirement mapping but absorbed into Phase 2 per ROADMAP.md) — CLOSED (pre-phase, RB27 proves it still holds).
- Fix-round tickets `delegate-agy-28k` (CR-01), `delegate-agy-bg4` (WR-01), `delegate-agy-hrt` (WR-02), `delegate-agy-ke6` (IN-01) — all CLOSED, each with a commit reference that exists in `git log --oneline --all` (spot-checked `dbbd81f`, `3c5fb09`, `5272b90`, `f47ff6b` — all present).
- `delegate-agy-sup` (RB24 flake) — OPEN, P3, correctly deferred as unrelated to this phase's four reviewed sites.
- `delegate-agy-ltf` (WR-03, flag-parser bug) and `delegate-agy-u1z` (IN-02, structural-guard suggestion) — both OPEN, deliberately deferred per the phase's own `02-REVIEW.md` and `02-03-FIXROUND-SUMMARY.md`, explicitly gating Phase 6's ship gate rather than this phase's goal. Neither touches S1/S4 or any of the four roadmap success criteria, so their being open does not block this phase.
- Epic `delegate-agy-6q3` and all 6 child tasks — CLOSED.

### Human Verification Required

### 1. Zero-byte `agy models` reply is gated identically to a non-empty degraded reply

**Test:** Add a `fake-agy.sh` mode (or a one-off harness) where the `models` subcommand exits 0 with truly empty stdout (no lines at all, not even the two-line `FAKE_AGY_MODELS_GARBAGE` text), then run it through both `scripts/agy_bridge.sh` and `scripts/gemini_shim.sh` with a stale cache present and then absent.
**Expected:** Same outcome as `R9b`/`SH15b` (degraded-with-cache: falls back silently/with-warning, cache untouched) and `R9`/`SH15` (degraded-without-cache: nothing written).
**Why human:** Both plans tag this specific must-have `verification: backstop` — a deliberate acknowledgment that it rests on code-path inference (the same `cut -f1` + `grep -q '^gemini-'` gate, fed an empty string) rather than an executed test. No fixture or fake-agy mode currently produces this exact input shape, so it cannot be confirmed by re-running the existing suite; a human (or a follow-up plan) needs to either add the fixture or accept the inference as sufficient.

### Gaps Summary

No gaps. All four ROADMAP.md success criteria are verified against real, passing, non-vacuous tests (each with a demonstrated mutation-proof where the plan called for one), both S1 and S4 are satisfied and correctly cross-referenced in REQUIREMENTS.md, the diff surface is exactly the four files the plans claimed and nothing else, all prohibited patterns (lockfiles, TTL changes, matcher loosening, duplicated warning literals, duplicated stderr relays) were independently absent on direct grep, and the bug tracker's closed/open state matches the code precisely. The only open item is a single explicitly-flagged, low-risk, narrow-scope untested edge case (zero-byte model-list reply) that the phase's own authors chose not to test and tagged accordingly — it does not indicate incomplete work, but per this verifier's rule for non-inferable ("backstop") truths it cannot be marked VERIFIED on inference alone, so the phase routes to `human_needed` rather than `passed`.

---

_Verified: 2026-08-20T15:09:18Z_
_Verifier: Claude (gsd-verifier)_
