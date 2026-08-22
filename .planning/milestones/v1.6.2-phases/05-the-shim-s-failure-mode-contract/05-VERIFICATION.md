---
phase: 05-the-shim-s-failure-mode-contract
verified: 2026-08-21T19:35:28Z
status: passed
score: 11/11 must-haves verified
behavior_unverified: 0
overrides_applied: 0
---

# Phase 5: The shim's failure-mode contract — Verification Report

**Phase Goal:** An operator can read exactly what `gemini` does to a caller that has never heard of agy, for every way this plugin fails.
**Verified:** 2026-08-21T19:35:28Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria, Phase 5)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | README carries one table naming the shim's behavior for each of the 4 failure modes (hung agy, unparseable model list, missing dependency, superseded pin), bridge behavior in the adjacent column | ✓ VERIFIED | `sed -n '/^## Troubleshooting$/,/^### Running the tests$/p' README.md` shows all 4 rows present, each stating both `agy-bridge` and `gemini` shim behavior in one cell. No second table, no new section (`git diff` shows in-place rewrites only). |
| 2 | Every row of the table has a test, so a code regression fails the suite | ✓ VERIFIED | `FM01` (tests/run-tests.sh:2685-2836) row-shape-checks every anchor and binds each row to a live proof via `_FM_PAIRS` (`DEP:RB03`, `DEP:RB02`, `PIN:I16`, `HANG:EC06`, `LIST:SH14`, `LIST:EC06`, `NAME:SH9`). All 6 cited proof IDs exist as live `ok`/`bad` labels (grep confirmed). Full suite run: `PASS=161 FAIL=0`, exit 0. |
| 3 | Every row where shim/bridge differ states why in one line; no row differs without a stated reason | ✓ VERIFIED | Read full table text. Superseded-pin and missing-dependency rows state sameness with a mechanism (`run_bounded` byte-identical copies per RB02; shared `write_wrapper()` invoked once per launcher per I16). The 3 divergent rows (hung agy, unparseable list, model name rejected) each state a one-line "why" tied to a real code mechanism, independently confirmed by reading `scripts/agy_bridge.sh` and `scripts/gemini_shim.sh` (see Data-Flow Trace below). No row lacks a stated reason. |
| 4 | An unrecognized model name passes through to agy unchanged — shim warns/degrades, never hard-rejects | ✓ VERIFIED | `scripts/gemini_shim.sh` `map_model()` (:471-495): on no match, `printf '%s\n' "$m"` (pass-through) always executes; a `WARNING:` is emitted only conditionally (`grep -q '^gemini-' <<< "$LIVE_MODELS"`), never a hard rejection. `agy_bridge.sh:558-561` by contrast exits 2 on the same input. SH9 (tests/run-tests.sh:1327) asserts this at runtime and passed in the full suite run. |

**Score:** 4/4 ROADMAP truths verified.

### PLAN Frontmatter Must-Haves (05-01, 05-02)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 5 | FM01 fails if a row loses an entry-point name, disposition clause, quoted literal, or is duplicated inside the table window | ✓ VERIFIED | Code inspected at tests/run-tests.sh:2685-2836: per-anchor checks for `agy-bridge`, `gemini`, `because`/`identical`, table-scoped uniqueness count. |
| 6 | FM01 counts occurrences only inside the Troubleshooting-table window, not whole-file | ✓ VERIFIED | `_FM_TABLE="$(sed -n '/^## Troubleshooting$/,/^### Running the tests$/p' "$_FM_README" | grep '^|')"` (tests/run-tests.sh:2707); dep-literal whole-file count separately asserted `=2` (row + README:308 fenced copy, which remains verbatim). |
| 7 | Every contract row occupies exactly one physical line | ✓ VERIFIED | `grep -c '^|'` over the table window returns `13`, unchanged before/after all edits (confirmed via `git diff` — each row rewritten in place, none added/wrapped). |
| 8 | Superseded-pin literal byte-identical between install.sh heredoc and README | ✓ VERIFIED | `_FM_ANCHOR_PIN='is installed, but this launcher is pinned to'` checked against both `$INSTALL` (scripts/install.sh:162, confirmed via Read) and the README row via the same literal. |
| 9 | Row-to-proof mapping is machine-checked DATA (`_FM_PAIRS`), not a comment | ✓ VERIFIED | `_FM_PAIRS=(DEP:RB03 DEP:RB02 PIN:I16 HANG:EC06 LIST:SH14 LIST:EC06 NAME:SH9)` is a bash array asserted at count `7`; each entry's proof ID is grep-checked as a live `ok`/`bad` label. Mutation-demonstrations (label deletion, `_FM_PAIRS` entry deletion, single-quote label) recorded in 05-01-SUMMARY.md and reverted cleanly (`git status --porcelain` matched before/after). |
| 10 | Superseded-pin row states the shim/bridge contract via shared `write_wrapper()`, invoked once per launcher | ✓ VERIFIED | `scripts/install.sh:206-207` — `write_wrapper "agy-bridge" ...` and `write_wrapper "gemini" ...`, two call sites into the one function, matching the README row's exact wording ("invoked once per launcher"). |
| 11 | `bash tests/run-tests.sh` exits 0 with `FAIL=0`; no file under `scripts/` modified by the phase | ✓ VERIFIED | Full suite run this session: `PASS=161 FAIL=0`, `[exited with code 0]`. `git diff d6cfd1c~1..90125a3 --stat` shows only `README.md`, `tests/run-tests.sh`, `.planning/*` changed — zero files under `scripts/`. |

**Score:** 11/11 must-haves verified (4 ROADMAP + 7 PLAN-specific, deduplicated).

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `README.md` Troubleshooting table | 4 failure-mode rows + pre-existing exit-code rows, all naming both entry points | ✓ VERIFIED | 13 rows in table window, all rewritten rows present and consistent (see truths above) |
| `tests/run-tests.sh` FM01 block | New test binding rows to proofs | ✓ VERIFIED | tests/run-tests.sh:2685-2836, wired into main suite execution (ran and passed) |
| `.planning/REQUIREMENTS.md` S3 row | Marked met | ✓ VERIFIED | Line 91: "met — all five failure-mode rows ... FM01 ... is the gate" |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| README missing-dependency row | `scripts/agy_bridge.sh:224`, `scripts/gemini_shim.sh:243` `run_bounded()` | RB02 byte-identity assertion | ✓ WIRED | RB02 (tests/run-tests.sh:2443-2476) extracts and diffs the three copies; passed in full run |
| README superseded-pin row | `scripts/install.sh:162,206-207` | I16 + FM01's `_FM_ANCHOR_PIN` static grep against `$INSTALL` | ✓ WIRED | Literal `is installed, but this launcher is pinned to` confirmed present in both files by direct Read/grep |
| README hung-agy row | `scripts/agy_bridge.sh` JSON/text fork at exit 124, `scripts/gemini_shim.sh` text-only exit 124 arm | Direct code read + EC06 | ✓ WIRED | Confirmed asymmetry: bridge forks on `$JSON_OUTPUT`, shim's timeout arm (gemini_shim.sh:687-688) has no JSON branch |
| README unparseable-list row | `scripts/agy_bridge.sh:545-549` (exit 2), `scripts/gemini_shim.sh` `load_models()` silent degrade | Direct code read + SH14/EC06 | ✓ WIRED | Bridge's `ERROR: agy model list contains no 'gemini-' ids...` confirmed byte-identical to FM01's `_FM_ANCHOR_LIST`; shim has no matching hard-exit path, confirmed by reading `load_models()` |
| README model-name-rejected row | `scripts/gemini_shim.sh` `map_model()` pass-through, `scripts/agy_bridge.sh:558-561` hard reject | Direct code read + SH9 | ✓ WIRED | Confirmed exact divergence and matching WARNING literal (`_FM_ANCHOR_NAME`) present in `$SHIM` |

### Data-Flow Trace

All 5 contract rows terminate in literal strings and behavioral branches actually present in `scripts/agy_bridge.sh` and `scripts/gemini_shim.sh` — read directly, not inferred from SUMMARY claims. No row was found asserting behavior the shipped scripts do not produce. This resolves the judgment-tier prohibition ("MUST NOT state a behavior in the contract table that the shipped scripts do not actually produce") — **non-authoritative LLM-judge verdict**: all 5 rows check out against source. The plans additionally recorded matching human `<human-check>`/read-through verdicts in both SUMMARYs (05-01: Task 1 verdict "reads as a real, checkable claim rather than filler"; 05-02: "PASS. Every divergence row now states a real, independently checkable mechanism").

### Behavioral Spot-Checks / Full Suite Run

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full regression suite (run once, per policy) | `bash tests/run-tests.sh` | `PASS=161 FAIL=0`, exit 0 | ✓ PASS |
| FM01 specifically | Implied by FAIL=0 (any FM01 failure would surface as nonzero FAIL count) | passed | ✓ PASS |
| No `scripts/` files touched across phase commits | `git diff d6cfd1c~1..90125a3 --stat -- scripts/` | empty | ✓ PASS |
| Row count unchanged (13) pre/post edits | `grep -c '^|'` over table window | `13` | ✓ PASS |
| No `unbounded` string introduced | `grep -ciF 'unbounded' README.md` | `0` | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| S3 | 05-01, 05-02 | Shim defects must not escape into unrelated PATH callers | ✓ SATISFIED | REQUIREMENTS.md:91 marks it met, citing FM01 and all 6 proof IDs; independently confirmed all proof IDs live and the suite green |

No orphaned requirements: REQUIREMENTS.md traceability table maps only S3 to Phase 5, and both plans declare `requirements: [S3]`.

### Anti-Patterns Found

None. Scanned the FM01 block (tests/run-tests.sh:2685-2836) and the modified README rows for `TODO|FIXME|XXX|HACK|PLACEHOLDER` — zero matches. No stub returns, no hardcoded-empty patterns applicable (bash test/doc content, not application code with render paths).

### Deviations Noted (from task prompt, cross-checked)

The task prompt asked whether 05-02's 3 auto-fixed Rule-1 deviations (anchor key naming, D-03 wording alignment, two directional wording bugs in the "Model name rejected" row) left contract rows internally inconsistent. Checked via `git log` (commits `8783b8f`, `9560787`, `ced7305`, `870653a`) and by reading the final table text in full:

- The "Model name rejected" row's forward reference ("the row below") correctly points at the immediately-following "Exit code 2" row in the current table order — consistent.
- The "Exit code 2" row's D-03 rationale text ("the shim shadows the system `gemini` for every PATH caller ... box-wide noise ... the bridge is an explicit, watched invocation where a loud failure costs nothing") matches 05-CONTEXT.md §D-03's stated one-line reason almost verbatim.
- No dangling references, no contradicting claims between adjacent rows found.

No inconsistency remains. The fixes were applied and are reflected in the current tree, not just claimed in the SUMMARY.

### Human Verification Required

None. All must-haves resolved via direct source inspection, a live full-suite run (`PASS=161 FAIL=0`), and cross-reading of both plans' recorded `<human-check>` verdicts (which themselves already satisfy the judgment-tier truth-of-reason checks the plans designed FM01's shape-only ceiling to require).

### Gaps Summary

None. All 4 ROADMAP success criteria and all plan-declared must-haves verified against the actual codebase (README.md, tests/run-tests.sh, scripts/agy_bridge.sh, scripts/gemini_shim.sh, scripts/install.sh), not merely against SUMMARY.md narrative. The one outstanding administrative item — beads epic `delegate-agy-rod` shows all 5 child tasks complete but the epic itself is not yet closed — is bookkeeping, not a phase-goal gap, and does not block phase completion.

---

_Verified: 2026-08-21T19:35:28Z_
_Verifier: Claude (gsd-verifier)_
