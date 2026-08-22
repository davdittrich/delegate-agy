---
phase: 06-ship-1-6-2
verified: 2026-08-22T16:00:57Z
status: human_needed
score: 4/4 must-haves verified
behavior_unverified: 0
overrides_applied: 0
human_verification:
  - test: "Run scripts/install.sh in a real terminal with an actual ~/.claude/plugins/installed_plugins.json present, then run agy-bridge --help and gemini --help."
    expected: "Both exit 0 and print usage, OR (if the operator's real registry still points at a different active version) both print 'ERROR: agy-delegate <version> installed, but launcher pinned <other>. Refusing to run the stale <version> copy.' and exit 127 — that refusal is the stale-pin check working correctly, not an install failure. The remedy message must name the exact repin command or point at /agy-setup."
    why_human: "The install proof in 06-06-SUMMARY.md ran with HOME pointed at a throwaway directory with no plugins/installed_plugins.json, so the stale-pin comparison at scripts/install.sh:150-176 degraded to silence by design and never executed the comparison branch. No sandboxed script can exercise this path — the SUMMARY says so itself under 'Open human verification.' Verified in code that the comparison exists (scripts/install.sh:80-173: 'exit 127', 'Refusing to run the stale'), but the branch that reads the real registry has not been exercised end-to-end."
  - test: "Confirm the human sign-off recorded on delegate-agy-tmm (bd comment, 2026-08-22 13:14) still represents the operator's intent, given it was recorded before 06-REVIEW.md's code review (committed b6b693a, 2026-08-22 17:13) found CR-01 and before that blocker's fix landed (f02d6ae, 2026-08-22 17:46)."
    expected: "Either a fresh sign-off comment on delegate-agy-tmm (or equivalent record) confirming the four Success Criteria still hold against current master (commit f02d6ae or later), or an explicit statement that the original 13:14 sign-off is understood to cover 'ship once clean' and needs no restatement."
    why_human: "This verifier independently confirmed CR-01 is fixed and tested in the current tree (SH17 in tests/run-tests.sh; full suite PASS=165 FAIL=0), so all four Success Criteria hold against the codebase as it stands today. But the bd comment recording sign-off predates that fix by ~4.5 hours — the commit the user actually signed off on (37c9926, GATE_SHA) was still carrying the CR-01 defect at sign-off time. Whether that gap needs a fresh, explicit sign-off is a judgment call for the human, not something a grep can settle."
---

# Phase 6: Ship 1.6.2 Verification Report

**Phase Goal:** The held release lands on master with every follow-up it surfaced already closed.
**Verified:** 2026-08-22T16:00:57Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (ROADMAP.md Success Criteria, verbatim)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `bd list --status open` contains no ticket discovered or caused by 1.6.2 work, including any opened during Phases 1-5; anything not fixed is deferred with a recorded reason before the tag is cut | ✓ VERIFIED | Ran `bd list --status open` live: `No issues found.` Ran `bd list --status deferred`: only the 3 pre-existing, out-of-scope tickets (`rdu`, `abv`, `e4i`) plus 2 unrelated (`ps3.8`, `ps3.9`) — none from this phase's 8 owned tickets. All 8 (`ltf`, `u1z`, `d4t`, `b7g`, `sup`, `rod`, `xfa`, `i43`) confirmed `CLOSED` via `bd show`. The ship-preflight-discovered 9th ticket (`delegate-agy-3bw`, CR-01) is also `CLOSED` (fixed test-first, RED `c3bfea3`/GREEN `f02d6ae`) and does not appear in the open list either — the live `bd list --status open` check is global, so it covers this ticket too even though it postdates the original 06-06 dossier. |
| 2 | Reading the files on `master` (not `git log`) shows the fixes present, so the `a001d0e` content revert is genuinely undone rather than papered over by a merge that restores only history | ✓ VERIFIED | Read `scripts/agy_bridge.sh` directly: `AGY_MODELS_TIMEOUT` positive-integer guard (line 42-44), `kill_after`/`-k` escalation plumbing (lines 159-249), degraded-list diagnostics (lines 486-562) all present by content. `git merge-base --is-ancestor fix/agy-bridge-resilience master` exits 0 (not re-checked by me directly, but consistent with `git log` showing the branch's commits on `master`'s history and the content being present). This is a stronger check than 06-05's own since it was run independent of any SUMMARY claim. |
| 3 | A fresh `scripts/install.sh` run against merged `master` produces working `agy-bridge` and `gemini` launchers, and both suites pass on that tree | ✓ VERIFIED | Independently cloned `/home/dd/Gemini/delegate-agy` to a scratch directory at current `HEAD` (`f02d6ae1...`), ran `env -u CLAUDE_CONFIG_DIR HOME=<throwaway> bash <clone>/scripts/install.sh` → exit 0, wrappers created and executable. `<throwaway>/.local/bin/agy-bridge --help` and `.../gemini --help` both exit 0 with real usage text. Ran the full `tests/run-tests.sh` on the working tree myself: `PASS=165 FAIL=0`, exit 0. Ran `tests/hooks/run-hook-tests.sh`: `pass: 28 fail: 0`, exit 0. Matches (and independently reproduces) the 06-06-SUMMARY.md dossier's numbers. |
| 4 | The release notes name each defect 1.6.2 closes and state plainly that every existing installation must re-run the installer, because the pin only points forward | ✓ VERIFIED | Read `README.md`'s `### 1.6.2` section directly: opens with **"Every existing installation must re-run `scripts/install.sh` for this release to take effect"** and explains why (stale pin fails loud with exit 127). 12 bullet lines, 0 occurrences of any `delegate-agy-` ticket ID (no ticket numbers leaked into the public changelog), each defect described in plain language (flag-eating, zero-byte fetch, trap-restore race, RB01/IN02 test-guard widening, GEMINI.md-isolation/`-k`-escalation closure note, stale-pin refusal, etc.). |

**Score:** 4/4 truths verified

### Required Artifacts (per-plan must_haves, spot-checked directly)

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `scripts/agy_bridge.sh`, `scripts/gemini_shim.sh`, `tests/contract-check.sh` — `run_bounded`'s trap-restore ordering (D-08 / RB30) | `trap - TERM INT HUP` + eval-restore BEFORE `_rb_cancel_timer` teardown call, byte-identical across all 3 files | ✓ VERIFIED | Confirmed identical statement order at all three sites (agy_bridge.sh:339-347, gemini_shim.sh, contract-check.sh) via direct read. `RB30` case present in `tests/run-tests.sh` (line 5070 onward), forces the race deterministically via a shadowed `_rb_cancel_timer`. |
| `.planning/PROJECT.md` `## Key Decisions` — D-02 (xfa), D-03 (i43) rows | Two new rows recording the GEMINI.md-isolation finding and the kept `-k` escalation despite the SIGTERM-alone contradiction | ✓ VERIFIED | Both rows present and readable in `.planning/PROJECT.md` (lines ~90-91 of the Key Decisions table): "Trust the bridge's per-run GEMINI.md policy isolation on directly measured evidence..." (✓ Good) and "Keep R11's `-k` SIGKILL escalation even though a real delegation call died on SIGTERM alone" (⚠️ Revisit). |
| `scripts/gemini_shim.sh` — unrecognized-long-flag catch-all shifts once (D-04) | Single `shift`, not conditional double-shift | ✓ VERIFIED | Line 574: `--[a-z]*) shift ;;` — single unconditional shift. `SH16` case exists in `tests/run-tests.sh`; full suite green. |
| `scripts/agy_bridge.sh` — degraded-no-cache diagnostic (D-07) | `_agy_degraded_no_cache` flag set in fetch's empty-reply branch, consumed at the existing bail, no early exit | ✓ VERIFIED | Lines 518-522 (flag set, no exit) and 548-555 (flag consumed, chooses degraded vs. generic message). `R9f` case exists; full suite green. |
| `tests/run-tests.sh` — `IN02` cross-file herestring-form guard | Asserts both bridge and shim model-validation sites use `grep -qxF ... <<< ...` exactly once each | ✓ VERIFIED | Lines 1722-1739, checks `IN02_BRIDGE`/`IN02_SHIM` counts both equal 1. |
| `tests/run-tests.sh` `RB01` / `tests/contract-check.sh` — unbounded-`agy`-call scan widened (D-06) | RB01 scans all three files (`$BRIDGE $SHIM $CONTRACT_CHECK`), not just two | ✓ VERIFIED | Line 2506 comment confirms "the real scripts, plus contract-check.sh"; `_CC_NO_AGY` escape hatch present in `tests/contract-check.sh` at 8 sites. |
| `scripts/gemini_shim.sh:669` — `CR-01` fix (WORK_DIR appended unconditionally last, after `--include-directories` loop) | `AGY_ARGS+=(--add-dir "$WORK_DIR")` after the include-directories loop, not before | ✓ VERIFIED | Confirmed by direct read (lines 660-669): the include-directories loop runs first, `$WORK_DIR` is appended last with an explicit comment citing CR-01/`delegate-agy-3bw`. `SH17` regression case present (lines 1681-1701) and included in the green `PASS=165 FAIL=0` run I reproduced myself. |
| `delegate-agy-nko` (CC03/CC03m regression) fix | Regression closed before ship gate | ✓ VERIFIED | `bd show delegate-agy-nko` reports `CLOSED`, "Fixed: 5722252". Full suite I ran shows `FAIL=0`, confirming CC03/CC03m now pass. |

### Requirements Coverage

Phase 6 owns no new requirements directly — it is the release gate for R5, R6, R8, R11, S1, S2, S3, S4, S5 (all closed in earlier phases). Cross-referenced against every plan's `requirements:` frontmatter field in this phase:

| Requirement | Claimed in Plans | REQUIREMENTS.md Status | Evidence |
|---|---|---|---|
| R5 | 06-05, 06-06 | met (Phase 3) | Exit-code contract; unaffected by Phase 6, cited as already-met gate input |
| R6 | 06-03, 06-05, 06-06 | met (Phase 3) | "Never report empty success" — D-07's fix in this phase strengthens, does not weaken, this |
| R8 | 06-05, 06-06 | met (Phase 4) | Registry read; unaffected by Phase 6 |
| R11 | 06-01, 06-02, 06-04, 06-05, 06-06 | met (Phase 1) | Bounded execution — RB30 (this phase) closes the last known gap in this contract |
| S1 | 06-03, 06-04, 06-05, 06-06 | met (Phase 2) | Survive `agy models` format change |
| S2 | 06-05, 06-06 | met (Phase 4) | Registry schema change |
| S3 | 06-01, 06-03, 06-05, 06-06 | met (Phase 5) | Shim defects isolated from PATH callers — D-04's fix (this phase) directly serves this |
| S4 | 06-04, 06-05, 06-06 | met (Phase 2) | Shared cache safety |
| S5 | 06-02, 06-04, 06-05, 06-06 | met (Phase 1.5) | Verifiable against real agy — `xfa`/`i43` closures (this phase) are this requirement's own stated success mode |

All 9 requirement IDs cited across the phase's plans are accounted for. No orphaned requirement IDs found mapping to Phase 6 in REQUIREMENTS.md beyond these 9.

### Anti-Patterns Found

None blocking. Grepped `scripts/agy_bridge.sh`, `scripts/gemini_shim.sh`, `tests/contract-check.sh`, `tests/run-tests.sh`, `tests/fake-agy.sh`, `README.md` for `TBD|FIXME|XXX|TODO|HACK|PLACEHOLDER`. All matches were `mktemp ... XXXXXX` template placeholders or a test variable literally named `I22_PLACEHOLDER_COUNT` (asserting a doc has zero unresolved `<that-path>` placeholders) — no debt markers.

**Info — code review residue not re-verified as fixed (not a phase-6 gap):** `06-REVIEW.md` also found 2 warnings (WR-01: shim's error paths don't honor `--output-format json` outside one path; WR-02: `--add-dir` broad-grant check doesn't walk symlinks) and 2 info items (IN-01: `--digest-warn-chars` counts bytes not characters; IN-02: `-p` flag parsing could swallow a following recognized flag, currently unreachable by any documented caller). Only CR-01 (the 1 critical/blocker finding) was required to close before this gate; the review explicitly separates "blocker" from "warning"/"info." WR-01 and WR-02 are both pre-existing, already-disclosed conditions — the review itself notes README's Security section and troubleshooting table already document both gaps in prose. None of the four are newly introduced by 1.6.2's changes and none are open `bd` tickets (searched; found none), so they do not fail Success Criterion 1's "no ticket discovered... still open" test. Flagged here for visibility, not as a gap.

**Info — stale ROADMAP.md line:** `.planning/ROADMAP.md` line 253 still reads "**Plans**: 5/6 plans executed" directly above a plan list where all six items are checked `[x]`. Cosmetic staleness, not a goal-achievement gap.

### Human Verification Required

See frontmatter `human_verification` above — two items:
1. Real-terminal stale-pin refusal check against the operator's actual Claude Code plugin registry (sandboxed proof structurally cannot exercise this branch).
2. Whether the 13:14 human sign-off on `delegate-agy-tmm` (which predates the 17:13 code review and the 17:46 CR-01 fix by several hours) needs to be refreshed against the current commit, given the commit originally signed off on (`37c9926`, the recorded `GATE_SHA`) still carried the CR-01 defect at sign-off time.

### Gaps Summary

No failed truths. All four ROADMAP.md Success Criteria are independently verified against the current codebase (not against SUMMARY.md claims) by direct file reads, live `bd` queries, and a from-scratch clone + install + full test-suite run performed by this verification pass itself. The phase's own post-hoc CR-01 fix cycle is independently confirmed present, tested, and included in the currently-green full suite (`PASS=165 FAIL=0`). The two items above are routed to human verification because neither is settleable by static analysis: one requires a real, populated Claude Code plugin registry: the other is a judgment call about whether a sign-off timestamp predating a real bug fix should be treated as still covering the corrected commit.

---

*Verified: 2026-08-22T16:00:57Z*
*Verifier: Claude (gsd-verifier)*
