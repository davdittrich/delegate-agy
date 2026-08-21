---
phase: 05-the-shim-s-failure-mode-contract
reviewed: 2026-08-21T19:45:32Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - README.md
  - tests/run-tests.sh
findings:
  critical: 0
  warning: 2
  info: 1
  total: 3
status: issues_found
---

# Phase 05: Code Review Report

**Reviewed:** 2026-08-21T19:45:32Z
**Depth:** standard
**Files Reviewed:** 2
**Status:** issues_found

## Summary

Reviewed the FM01 test case added to `tests/run-tests.sh` (Troubleshooting-table
contract pinning) and the five rewritten Troubleshooting rows in `README.md`
(dependency-warning, superseded-pin, hung-agy/exit-124, degraded-model-list/exit-2,
model-name-rejected).

Verified by direct execution: FM01 currently passes (`bash tests/run-tests.sh`
prints `ok - FM01 ...`). Cross-checked every literal anchor FM01 pins
(`_FM_ANCHOR_DEP`, `_FM_ANCHOR_PIN`, `_FM_ANCHOR_HANG`, `_FM_ANCHOR_LIST`,
`_FM_ANCHOR_NAME`) against the live `README.md`, `scripts/install.sh`, and
`scripts/gemini_shim.sh` text — all five match byte-for-byte, all five rows carry
exactly one occurrence inside the table window, the deliberate second
whole-file occurrence of the DEP warning (README:308, inside a fenced example)
is accounted for, and no table row has an unescaped `|` that would corrupt the
Markdown table's column count. No BLOCKER-level defect found in either file.

Two WARNING-level robustness gaps and one INFO item remain, detailed below —
none currently produce a wrong result, but both WARNINGs describe a class of
regression that FM01, as written, would not catch.

## Warnings

### WR-01: `_FM_PAIRS` proof-binding checks proof *existence by label*, not proof *content linkage* — a gutted proof can keep FM01 green

**File:** `tests/run-tests.sh:2799-2829`
**Issue:** For each `KEY:ID` pair in `_FM_PAIRS` (e.g. `LIST:EC06`, `NAME:SH9`),
FM01 only confirms two things: (1) a line matching
`^[[:space:]]*(ok|bad)[[:space:]]+["']ID[[:space:]]` exists somewhere in
`run-tests.sh`, and (2) the anchor variable `_FM_ANCHOR_<KEY>` used by FM01
itself is non-empty. It never confirms that test `ID`'s own body still
compares the README row's literal against the row's claimed source file. The
in-code comment at lines 2799-2807 discloses this precisely ("does NOT prove
the test still asserts the README row's claims -- a test can be gutted and
keep its label"), so the gap is intentional and documented rather than
accidental — but it is still a real coverage hole: if a future edit to EC06,
RB02, RB03, SH14, SH9, or I16 removes or weakens the specific
literal-comparison that backs one of the five FM01 rows (while leaving the
`ok "ID ..."` label and some other assertion in place), FM01 continues to
report green even though the row it is nominally proving is now unverified.
Today this is not actually exploitable in practice — spot-checking EC06 (used
for both `HANG` and `LIST`) confirms it independently greps the same literals
out of `README.md`, `scripts/agy_bridge.sh`, and `scripts/gemini_shim.sh` and
also drives both entry points at runtime — but that fidelity is coincidental
from FM01's point of view, not something FM01 itself enforces.
**Fix:** Either (a) accept this as a documented, human-verified boundary (it
already is, explicitly, in the surrounding comments — no action needed beyond
leaving the comment as the record), or (b) tighten the check to require that
the named proof's body (the text between its `echo "== ... =="` banner and its
`ok "ID ...` call) contains the same `_FM_ANCHOR_<KEY>` literal FM01 uses, e.g.:
```bash
_fm_proof_line="$(grep -nE "^[[:space:]]*(ok|bad)[[:space:]]+[\"']${_fm_id}[[:space:]]" "$_FM_SELF" | head -1 | cut -d: -f1)"
_fm_proof_start="$(awk -v n="$_fm_proof_line" 'NR<n && /^echo "==/{l=NR} END{print l+0}' "$_FM_SELF")"
sed -n "${_fm_proof_start:-1},${_fm_proof_line}p" "$_FM_SELF" | grep -qF "${!_fm_anchor_var}" \
    || { FM01_OK=0; FM01_DETAIL="$FM01_DETAIL proof:${_fm_id}_anchor_not_asserted"; }
```
This closes the label/content gap without requiring semantic (truth) judgment,
which FM01 correctly leaves to human review.

### WR-02: The remaining "(the row below)" cross-reference in the Model-name-rejected row is order-dependent and untested — this exact row has already broken this way twice

**File:** `README.md:229`
**Issue:** The row states: "...with no usable list (the row below) the same
name passes through silently instead." This phrase is only true because the
Exit-code-2 / degraded-model-list row (`README.md:230`) happens to be the very
next row in the table today. No test — including FM01 — checks table row
*order* or *adjacency*; FM01's per-row checks only confirm that required
substrings (`agy-bridge`, `gemini`, `because`/`identical`) are present inside
a matched row, not where that row sits relative to any other. This is not a
hypothetical risk for this specific line: the git history for this same row
shows it was already fixed twice in this phase for exactly this class of bug —
`ced7305` ("correct row-order reference in model-name-rejected row", the
phrase pointed the wrong direction) and `870653a` ("remove dangling
forward-reference in model-name-rejected row", a different self-reference was
removed as redundant). If the table is ever reordered, or a row inserted
between `README.md:229` and `README.md:230` (e.g. to alphabetize, or to add a
new failure mode), this phrase silently becomes false and nothing in the test
suite will flag it.
**Fix:** Either drop the positional phrase and inline the fact directly
(matching the pattern already used to fix the sibling "same reason as the row
above" self-reference in `870653a`), e.g. replace "with no usable list (the
row below) the same name passes through silently instead" with "with no usable
list (i.e. when `agy model list contains no 'gemini-' ids`) the same name
passes through silently instead" — or, if the terser phrasing is kept, add an
FM01 assertion that the LIST-anchored row's line number is strictly greater
than the NAME-anchored row's line number within `$_FM_TABLE`, e.g.:
```bash
_fm_name_ln="$(printf '%s\n' "$_FM_TABLE" | grep -nF "$_FM_ANCHOR_NAME" | head -1 | cut -d: -f1)"
_fm_list_ln="$(printf '%s\n' "$_FM_TABLE" | grep -nF "$_FM_ANCHOR_LIST" | head -1 | cut -d: -f1)"
[[ -n "$_fm_name_ln" && -n "$_fm_list_ln" && "$_fm_list_ln" -gt "$_fm_name_ln" ]] \
    || { FM01_OK=0; FM01_DETAIL="$FM01_DETAIL readme:name_row_below_reference_stale"; }
```

## Info

### IN-01: `_fm_dep_total -eq 2` couples an unrelated doc edit (removing the fenced-example duplicate) to FM01's pass/fail

**File:** `tests/run-tests.sh:2718-2719`
**Issue:** FM01 requires the DEP warning literal to appear exactly twice in
the whole file: once in the table row, once in the fenced shell example at
`README.md:308`. This is documented as deliberate in the surrounding comment
(lines 2700-2706), and is not a bug, but it means a legitimate future
copy-edit that removes the redundant fenced-example line (e.g. because it is
judged no longer useful) will fail FM01 for a reason unrelated to "is the
Troubleshooting row broken", surfacing as `readme:dep_total_1` — a maintainer
unfamiliar with this specific rationale would have to read the test comment to
understand why a seemingly-safe doc trim broke the suite.
**Fix:** No change required if the intent is genuinely to pin the
fenced-example duplicate too; if not, consider isolating that specific
assertion under its own detail token / comment pointing directly at
`README.md:308` (already partially done) so the failure message is
self-explanatory without needing to trace back to the FM01 comment block.

---

_Reviewed: 2026-08-21T19:45:32Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
