---
phase: 03-the-exit-code-contract
verified: 2026-08-21T00:00:00Z
status: passed
score: 5/5 must-haves verified
behavior_unverified: 0
overrides_applied: 0
---

# Phase 03: The Exit-Code Contract Verification Report

**Phase Goal:** Every documented exit code is reachable, means exactly one thing, and the docs quote the message the code actually prints.
**Verified:** 2026-08-21
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A caller can provoke each of 2, 3, 124, 127, 137 and receives a distinct message naming that specific cause; the suite exercises all five | ✓ VERIFIED | `tests/run-tests.sh` `EC07` provokes and asserts exact rc + cause-fragment exclusivity for 2 (bridge), 3, 124, 137 (both entry points where applicable); 127 is provoked and asserted exactly by pre-existing cases `I16` (`tests/run-tests.sh:4084`, `-eq 127`) and `RB29` (`:4411`, `-eq 127`), with `EC07` adding four source assertions pinning that those two citations have not rotted. Full suite run confirms `PASS=153 FAIL=0`, `EC07` `ok`. |
| 2 | An early external kill is reported as an external kill; a kill from the bridge's own `-k` escalation is reported as a timeout — separated by elapsed duration against the bound, not conflated | ✓ VERIFIED | `scripts/agy_bridge.sh:724` / `scripts/gemini_shim.sh` gate the external-kill branch on `"$EXIT_CODE" -eq 137 && "$DURATION" -lt "$TIMEOUT"` (strict less-than); the sibling `elif` at `:743` catches `124 \|\| 137` for everything else. `EC07` source-asserts the strict `-lt` (and the absence of any `-le` variant) exactly once per script, and asserts the four-arm ordering (early-137 → 124-or-137 → generic-nonzero → empty-stdout). Runtime cases `EC01`/`EC03` drive the external-kill path end to end on both entry points. |
| 3 | No error message ends in a dangling `: ` when agy writes nothing to stderr — plain-text or JSON, external-kill or generic branch | ✓ VERIFIED | All four sites use the same guarded expansion `${_err_txt:+: $_err_txt}` (`scripts/agy_bridge.sh:730,742,745,765`; `scripts/gemini_shim.sh:684`). Runtime cases `EC01` (bridge text), `EC02` (bridge JSON), `EC03` (shim text, byte-compared against the bridge's own line), `EC04` (bridge generic-nonzero text) each assert the empty-stderr case ends with no separator and the non-empty case ends in exactly `: <stderr>`, across 4 stderr scenarios (empty, non-empty, newline-only, format-specifier). |
| 4 | README's troubleshooting table quotes each exit-code message as the code emits it, appended stderr suffix included | ✓ VERIFIED | README.md:230-233 quotes the exit-2/124/137/3 messages byte-for-byte, including the `EC_KILL9_TAIL` suffix rule and the generic-nonzero divergence note (bridge-vs-shim, and bridge text-vs-JSON). Cross-checked against live source at every cited line; `EC05`/`EC06` pin these literals statically (present exactly once per script, comment-filtered) and at runtime (driven invocations compared byte-for-byte against the README-quoted form). |
| 5 | agy exiting 0 with empty stdout → exit 3, 0-byte stdout in text mode, `{"error":…}` envelope with no `response` key in JSON mode — regression test pins both shapes | ✓ VERIFIED | `EC08` (`tests/run-tests.sh:2832-2957`) uses a purpose-built split-capture helper (`_ec_run_split`, never the merging `_run`) and `wc -c` (never a command substitution) to assert zero-byte stdout on both entry points in text mode, and a real `json.load` parse asserting `"response" not in d` / `not d.get("success")` on both entry points in JSON mode. Also pins that a one-newline-byte stdout is NOT empty and round-trips through all four output shapes. |

**Score:** 5/5 truths verified (0 present, behavior-unverified)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `scripts/agy_bridge.sh` — `EC_KILL9_TAIL` constant, guarded external-kill/generic-nonzero branches | Shared literal, no dangling separator | ✓ VERIFIED | Line 52 (`EC_KILL9_TAIL=' -- possible OOM or external kill'`), used at :742/:745; generic-nonzero guard at :765 |
| `scripts/gemini_shim.sh` — mirrored `EC_KILL9_TAIL`, guarded external-kill branch | Byte-identical to bridge's | ✓ VERIFIED | Line 71, used at :684; generic-nonzero relay intentionally unguarded/raw at the shim (documented divergence, not a defect) |
| `tests/run-tests.sh` — `EC01`-`EC08` | Runtime + provenance regression coverage for the whole contract | ✓ VERIFIED | All eight cases present, each traced to source and confirmed passing (`PASS=153 FAIL=0`) |
| `README.md` — troubleshooting rows for 2/3/124/127/137 + generic-nonzero divergence note | Quotes emitted messages byte-for-byte | ✓ VERIFIED | Lines 225-236, cross-checked against live script text and `scripts/install.sh` (exit 127) |
| `.planning/REQUIREMENTS.md` — R5/R6 traceability rows | Moved to `met` with residues stated | ✓ VERIFIED | R5 states 4-provoked/1-cited coverage plus the named `edge:R5/precision` residue; R6 states EC08's evidence |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `tests/fake-agy.sh` `FAKE_AGY_PRINT_KILL9` path | bridge's `EXIT_CODE -eq 137 && DURATION -lt TIMEOUT` branch | fixture now emits `FAKE_AGY_STDERR` before exiting 137 | ✓ WIRED | Fixed in plan 03-01 task 1; without it the non-empty-stderr half of EC01/EC02/EC03 would be unreachable — confirmed the fixture path is exercised by all downstream EC0x cases |
| Guarded `_err_txt` expansion | both `printf %s` and `python3 sys.argv` | positional argument, never spliced into format string or python source | ✓ WIRED | Confirmed at every site; format-specifier scenario (`100%s%d`) in EC01/EC03/EC04 renders literally, proving no injection |
| `EC_KILL9_TAIL` single literal | both scripts' definitions + README's quoted row | `EC05` static provenance (`grep -cF` exactly 1 per script, comment-filtered) + README substring match | ✓ WIRED | `EC05` `ok`; verified live against `scripts/agy_bridge.sh:52`, `scripts/gemini_shim.sh:71`, `README.md:232` |
| Four literals (empty-output, timeout-text, timeout-JSON, degraded-list) | both scripts + README | `EC06` static + runtime cross-entry agreement | ✓ WIRED | `EC06` `ok`; runtime driven invocations on both entry points produce byte-identical lines |
| `I16`/`RB29`'s `-eq 127` assertions | `EC07`'s self-referential source assertions | escaped-ERE `grep -cE` against `tests/run-tests.sh` itself, count must equal 1 | ✓ WIRED | Verified present at `:4084` (I16) and `:4411` (RB29); `EC07` passed with empty detail, confirming the count landed at exactly 1 (not inflated by its own grep line) |
| Exit-3 zero-byte-stdout assertion | split-stream capture, not merged `2>&1` | `_ec_run_split` helper | ✓ WIRED | Confirmed the helper captures stdout/stderr to separate files and reads back via `wc -c`; `EC08` would be vacuous under the suite's default `_run` merge, and the plan explicitly avoids it |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| R5 | 03-01, 03-02, 03-03, 03-04 | Exit codes are a contract — each code reachable, distinct message, 137-vs-124 discrimination by elapsed duration | ✓ SATISFIED | `.planning/REQUIREMENTS.md` traceability row: `met`, residue `edge:R5/precision` (integer-second `SECONDS` truncation) named explicitly, not silently absorbed |
| R6 | 03-01, 03-02, 03-04 | Never report empty success — fail loud, failure payload never success-shaped | ✓ SATISFIED | `.planning/REQUIREMENTS.md` traceability row: `met`, `EC08` cited as the closing evidence |

No orphaned requirements found for Phase 3 in `.planning/REQUIREMENTS.md`'s traceability table (only R5 and R6 map to Phase 3).

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | No `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/`PLACEHOLDER` markers found in `scripts/agy_bridge.sh`, `scripts/gemini_shim.sh`, or `README.md` (the `mktemp -t ...XXXXXX` template hits are mktemp syntax, not debt markers) | — | — | No blocker |
| `README.md` Changelog | — | No changelog entry for the dangling-separator fix or the restated exit-code table (03-REVIEW.md WR-01) | ℹ️ Info | Non-blocking process gap, already flagged in the committed code review; does not affect goal achievement |
| `tests/run-tests.sh:2566` | — | `EC_KILL9_TAIL` cross-script identity is proven indirectly (each script vs. a third hardcoded test literal) rather than directly diff'd against each other (03-REVIEW.md WR-02) | ℹ️ Info | Non-blocking; `EC03`'s runtime byte-comparison already subsumes this in practice |

No blocker-severity anti-patterns found. Both warnings above were raised and dispositioned in the phase's own committed code review (`03-REVIEW.md`, 0 critical / 2 warning / 1 info, `PASS=153 FAIL=0` independently confirmed by that review) and are process/coverage-depth notes, not goal-blocking defects.

### Behavioral Spot-Checks / Full Suite

Ran `bash tests/run-tests.sh` directly (not merely trusting SUMMARY claims): **PASS=153 FAIL=0**, matching the phase's own final verification count. `EC01` through `EC08` all report `ok`. Traced `EC07`'s and `EC08`'s bodies line-by-line against the plan's `must_haves` and confirmed the mechanism described in each SUMMARY (split-capture helper, escaped-ERE self-referential source assertions, strict `-lt` source pin) is exactly what is in the shipped file — not a stub or a weaker proxy.

### Human Verification Required

None. Every must-have truth is backed by a runtime-exercised regression test (`EC01`-`EC08`) that was independently re-run and confirmed passing, not merely presence/wiring checks.

### Gaps Summary

None. All five roadmap success criteria hold against the live codebase: the exit-code branches, the guarded suffix, the README rows, and the R6 failure-payload shape are all present, wired, and behaviorally proven by tests re-run during this verification (not merely claimed in SUMMARY.md). `R5` and `R6` are recorded `met` in `.planning/REQUIREMENTS.md` with their genuine residues (the integer-second `SECONDS` precision ceiling) stated rather than hidden.

---

_Verified: 2026-08-21_
_Verifier: Claude (gsd-verifier)_
