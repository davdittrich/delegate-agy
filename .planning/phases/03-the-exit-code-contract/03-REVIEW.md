---
phase: 03-the-exit-code-contract
reviewed: 2026-08-20T23:13:20Z
depth: standard
files_reviewed: 5
files_reviewed_list:
  - scripts/agy_bridge.sh
  - scripts/gemini_shim.sh
  - tests/run-tests.sh
  - tests/fake-agy.sh
  - README.md
findings:
  critical: 0
  warning: 2
  info: 1
  total: 3
status: issues_found
---

# Phase 03: Code Review Report

**Reviewed:** 2026-08-20T23:13:20Z
**Depth:** standard
**Files Reviewed:** 5
**Status:** issues_found

## Summary

Reviewed the phase-03 delta in full: the dangling-separator fix on the external-kill
branches of `scripts/agy_bridge.sh` (both plain-text and `--json`) and
`scripts/gemini_shim.sh`, the same fix on the bridge's generic-nonzero plain-text
branch, the new shared `EC_KILL9_TAIL` literal, the one-line `fake-agy.sh` addition
that lets the fixture emit stderr on the kill9 path, the restated README exit-code
table, and the EC01-EC08 regression tests added across `tests/run-tests.sh`.

I traced the diff against `dbbd81f` (last commit before phase 03's first test
commit) rather than the whole files, confirmed each fix's `${_err_txt:+: $_err_txt}`
guard produces no dangling `: ` on empty stderr and an exact `: <stderr>` suffix on
non-empty stderr in every branch it touches, and cross-checked every literal the new
EC05/EC06 tests pin (`EC_KILL9_TAIL`, the exit-3/124/2 message fragments) against
the actual bytes in both scripts and the README table. Also ran the full suite
(`bash tests/run-tests.sh`): **PASS=153 FAIL=0**, confirming the file's own
"SUITE STATE: fully GREEN" claim.

The fix itself is correct and narrowly scoped — no logic error, no injection risk
(all interpolated stderr text flows through `printf`'s `%s` or a Python `sys.argv`
element, never into a format string or `eval`), and no divergence from what the
tests assert. I did not find a BLOCKER in the phase-03 delta. Two WARNING-level
process/documentation gaps and one pre-existing INFO-level classification gap
(visible in, but not introduced by, this diff) are below.

## Warnings

### WR-01: No changelog entry for the dangling-separator fix or the restated exit-code table

**File:** `README.md` (Changelog section, top entry `### 1.6.2`, lines ~407-419)
**Issue:** Phase 03 changes the observable stderr/JSON payload of three exit-code
branches (137 external-kill in both scripts, generic-nonzero in the bridge) and
substantially rewrites the exit-2/3/124/137 troubleshooting rows plus adds the new
"Generic (undocumented) nonzero exit codes" paragraph — a real behavioral fix
(previously a bare `agy killed ...: ` with nothing after the colon on empty stderr)
and a real documentation rewrite. Every other behavioral/doc change in this
project's history gets a Changelog entry (see the `1.6.1`/`1.6.0`/`1.5.1` entries,
each of which itemizes exactly this class of fix). Nothing under `### 1.6.2` (or
any other version) mentions the dangling-separator fix, `EC_KILL9_TAIL`, or the
exit-code table rewrite. `.claude-plugin/plugin.json` is still pinned at `1.6.1`,
one version behind the changelog's top entry, so there is no version slot this
phase's changes are recorded against at all.
**Fix:** Add a changelog entry (either appending to `1.6.2` or bumping to a new
version) itemizing: (1) the external-kill and generic-nonzero messages no longer
trail off into a dangling `: ` when agy's stderr was empty; (2) `EC_KILL9_TAIL` is
now a single named literal shared byte-for-byte between both scripts; (3) the
troubleshooting table's exit-2/3/124/137 rows were rewritten to state the exact
message shape, JSON-envelope shape, and bridge/shim divergence for each code.

### WR-02: `EC_KILL9_TAIL` duplication has no test asserting the two scripts' definitions stay byte-identical to each other, only to a hardcoded literal

**File:** `scripts/agy_bridge.sh:52`, `scripts/gemini_shim.sh:71`, `tests/run-tests.sh:2566`
**Issue:** EC05 (`tests/run-tests.sh:2557-2582`) asserts each script defines
`EC_KILL9_TAIL='$_EC_KILL9_LITERAL'` exactly once, where `_EC_KILL9_LITERAL` is a
literal string written directly into the test file. That proves both scripts match
the test's copy, but not that they match *each other* directly — if a future edit
changed both scripts' definitions to a new, mutually-identical string without
updating the test's `_EC_KILL9_LITERAL`, the suite would go red on both scripts at
once with a misleading "doesn't match the pinned literal" diagnosis rather than a
"scripts diverged from each other" one; conversely, if someone edited
`_EC_KILL9_LITERAL` in the test to chase a script change instead of fixing the
script, EC05 would still pass while quietly loosening the byte-identity guarantee
the design comments in both scripts claim ("Byte-identical to
scripts/agy_bridge.sh's EC_KILL9_TAIL by design"). This is a coverage gap in the
regression test the phase added, not a runtime bug — the current three literals
(bridge, shim, test) are in fact identical today.
**Fix:** Not blocking; low-value to fix given EC03 already asserts the two
scripts' *emitted lines* are byte-identical across four stderr scenarios (which is
a stronger, behavior-level guarantee that subsumes this gap in practice). Optional:
add a direct `diff <(grep ... "$BRIDGE") <(grep ... "$SHIM")` comparison to EC05 if
the indirection through a third hardcoded literal is ever found confusing during a
future edit.

## Info

### IN-01: Exit-3 quota/auth classifier only recognizes two of many real casings (pre-existing, not introduced by phase 03)

**File:** `scripts/agy_bridge.sh:780-782`, `scripts/gemini_shim.sh:705-707`
**Issue:** The classifier `case "$_reason" in *RESOURCE_EXHAUSTED*|*429*|*[Qq]uota*) ... *[Aa]uth*|*UNAUTHENTICATED*) ...` uses bash character-class globs that only match a stderr string containing exactly `Quota`/`quota` or `Auth`/`auth` as a substring — not, e.g., `QUOTA`, `AUTHENTICATION`, or `auTHentication` in any other casing, since `[Qq]` toggles only the first letter. A real agy stderr worded e.g. `"AUTH FAILURE"` would fall through to the generic `empty_output` class instead of `auth`. This is unchanged by phase 03 (present in both scripts before and after this diff) and does not affect the exit code itself (still exits 3 either way) — only the `error_class`/`[<class>]` label README documents as `quota`, `auth`, or `empty_output`. Flagging because the phase's own README rewrite (EC06/WR-01 above) newly documents this classifier's three-way output as a stable contract, which makes the classifier's actual coverage worth being accurate about going forward.
**Fix:** If exact-casing coverage matters, use `shopt -s nocasematch` around the
`case`, or match on a canonicalized-lowercase copy of `$_reason` (`_reason_lc="${_reason,,}"`) against all-lowercase patterns. Not a phase-03 regression; ticket as follow-up rather than blocking this phase.

---

_Reviewed: 2026-08-20T23:13:20Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
