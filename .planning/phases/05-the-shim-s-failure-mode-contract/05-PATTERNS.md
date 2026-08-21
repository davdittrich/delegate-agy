# Phase 5: The shim's failure-mode contract - Pattern Map

**Mapped:** 2026-08-21
**Files analyzed:** 2 (both existing files being edited — no new files this phase)
**Analogs found:** 2 / 2 (self-analogous: each file's own prior-phase edits are the closest analog)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|-----------------|----------------|
| `README.md` (Troubleshooting table, `:220-236`) | doc (reference table) | request-response (operator looks up an observed string) | Phase 3's own restructuring of the same table (`03-CONTEXT.md` D-05/D-07/D-11) | exact — same table, same file, same "fold rows in place, don't parallel-table" convention |
| `tests/run-tests.sh` (test-citation, no new provocation) | test | event-driven (assertion cites existing shared-code proof) | Phase 4's D-07 citing I16/I17/I18 as sufficient evidence | exact — same "cite by name+line in canonical_refs, add zero new tasks" pattern |

## Pattern Assignments

### `README.md` — Troubleshooting table edit (D-01)

**Analog:** the table's own current shape at `README.md:220-236`, produced by Phase 3's D-05/D-07 restructure and Phase 1's D-09/D-10 RB03-provenance convention.

**Current row shapes to fold into, not duplicate** (read verbatim, `README.md:229-236`):
- `:229` — Model name rejected row (agy's own validation, unrelated to this phase's four rows but establishes the row-per-behavior convention).
- `:230` — degraded model-list row: currently states `agy-bridge` warns loud on a `gemini-`-prefixed-model-list check while `gemini` shim has no matching check and degrades quietly on the same input. This is the ONE row with real divergence (D-03) — extend it with the explicit "same both / differs because" clause the CONTEXT calls for, not a new row.
- `:231` — exit 124 (timeout) row: already states byte-identical stderr string across both entry points, with the JSON-arm wording difference noted inline. Use this row's inline-divergence-note style as the template for the D-01 "same both / differs because" clause on other rows.
- `:232` — exit 137 (external-kill) row: already states the two entry points "word this identically" — this is the `EC_KILL9_TAIL` row (Phase 3 D-11/D-12 pinned, shared tail literal). No new content needed; confirm wording still matches shared literal.
- `:234` — missing-dependency (`timeout`/`gtimeout`) `WARNING:` row: already states literal shared once per script — this is the RB03 row.
- `:258` (Security section, not Troubleshooting) — superseded-pin exit-127 refusal: currently prose, not a table row; D-01 folds a same-table row for this into the four-row failure-mode contract per CONTEXT, citing `write_wrapper()` (`scripts/install.sh:78-182`, invoked identically for `"gemini"`/`"agy-bridge"` at `install.sh:206-207`) and noting "same both, shared `write_wrapper()`, proven via I16."

**Row-editing convention to copy (from Phase 3 D-05/D-07, `03-CONTEXT.md:29-31`):** rows are rewritten/re-keyed in place against what the code actually emits, quoting the real message shape verbatim (RB03-style provenance) rather than a paraphrase — never add a second parallel table for shim-vs-bridge comparison.

**Divergence-note inline style to copy** (already live in the table, use as literal template): exit-3 row (`README.md:233`) explicit clause: *"Both `agy-bridge` and the `gemini` shim fail loud here rather than reporting empty success. The two entry points' JSON envelopes differ in shape: ... a JSON consumer must not assume one schema fits both."* — this is exactly the "same both / differs because" clause shape D-01 asks the four target rows to carry.

---

### `tests/run-tests.sh` — citation only, no new test (D-02)

**Analog:** Phase 4's `04-CONTEXT.md` D-07, citing `I16`/`I17`/`I18` by name and line as sufficient evidence for criteria 1-3, adding zero new fixtures.

**Existing test to cite, not duplicate:**
```
tests/run-tests.sh:4330-4453  (I16)
```
Read excerpt (`:4330-4341`):
```bash
# I16: a stale pin FAILS LOUD. The launcher compares its install-time pinned
# version against the active version in Claude Code's install registry and
# refuses to exec when they differ, naming the repin command. A missing or
# unparseable registry degrades to silence (dev installs must keep working),
# and the exec target stays the install-time literal in every case.
IH="$(_fresh_home)"
VROOT="$(mktemp -d "$SANDBOX/vfake.XXXXXX")"
mkdir -p "$VROOT/agy-delegate/1.0.0/scripts"
cp "$ROOT/scripts/agy_bridge.sh" "$ROOT/scripts/gemini_shim.sh" "$VROOT/agy-delegate/1.0.0/scripts/"
```
Note the fixture already copies both `agy_bridge.sh` and `gemini_shim.sh` into the fake plugin dir and installs both wrappers through the same `install.sh` run — this is the "one shared function, two call sites" proof CONTEXT's D-02 leans on; no per-entry-point-named assertion exists (or is needed) beyond this shared fixture.

**Citation style to copy verbatim** (from `04-CONTEXT.md:51,93`):
> "The plan should cite I16 (`tests/run-tests.sh:3980-4105`)... by name and line in canonical_refs as evidence that criteria 1-3 are met, with no new tasks against them."

Apply identically: cite `I16` (`tests/run-tests.sh:4330-4453`) in the plan's canonical_refs as evidence for the superseded-pin row; zero new test tasks against `gemini_shim.sh`'s own exec path.

**Existing RB03 test to cite for the missing-dependency row** (already-shipped, do not duplicate):
```
tests/run-tests.sh:2498-2554  (RB03)
```
Read excerpt (`:2498-2521`):
```bash
echo "== the strings an operator actually sees (RB03) =="
# RB03: README's troubleshooting table is matched by hand against real output,
...
RB03_OK=1
RB03_DETAIL=""
    [[ "$_rb03_n" -eq 1 ]] || { RB03_OK=0; RB03_DETAIL="$RB03_DETAIL ${_rb03_f##*/}:defines_${_rb03_n}"; }
```
RB03 already asserts each warning literal (including the missing-timeout `WARNING:` string) is defined exactly once per script and matches the README quote — this is the provenance proof for the `:234` row; no new assertion needed.

**EC_KILL9_TAIL citation for the exit-137 row** (Phase 3 D-11/D-12, `tests/run-tests.sh:882`):
```bash
# same EC_KILL9_TAIL constant and _err_txt pattern EC01 already proved.
```
Cite this comment/pattern as the shared-tail-literal proof for the exit-137 row; no re-provocation.

**SH9 citation, no new work** (per CONTEXT, criterion-4-adjacent but already closed):
```
tests/run-tests.sh:1320-1329  (SH9)
```
Read excerpt (`:1307,1327-1329`):
```bash
# SH9: an unrecognised name still REACHES agy unchanged. This shim shadows
...
    ok "SH9 unknown model reaches agy unchanged; warning on stderr only, never stdout"
...
    bad "SH9 unknown model reaches agy unchanged; warning on stderr only, never stdout" \
```
Already proves the shim never hard-rejects an unrecognized model — cite, no new task.

## Shared Patterns

### "Cite an existing test ID, don't duplicate it" (source: Phase 4 D-07, Phase 3 EC03/EC07 same convention)
**Apply to:** all four `tests/run-tests.sh` citations above (`I16`, `RB03`, `EC_KILL9_TAIL`/EC01, `SH9`).
Pattern: canonical_refs entries name the test ID and exact line range; the plan's task list carries zero new provocation/assertion tasks against already-proven behavior — a new task is only warranted if a planning-time re-read of the cited range finds an actual regression against current file content.

### "Fold rows into the existing table, never build a parallel one" (source: Phase 3 D-01 lineage, restated in `05-CONTEXT.md` D-01)
**Apply to:** `README.md` Troubleshooting table edits only.
Pattern: re-key/rewrite rows in place at their current line numbers (`:229-236`, plus a new same-table row for the exit-127 superseded-pin case currently living only in prose at `:258`); quote the real emitted string verbatim (RB03-style provenance); add a "same both / differs because" clause per row using the exit-3 row's (`:233`) existing inline-divergence-note phrasing as the literal template.

## No Analog Found

None — both target files (`README.md`, `tests/run-tests.sh`) already contain the exact rows/tests this phase edits; the analog for each is the file's own current content plus the immediately preceding phase's edit convention.

## Metadata

**Analog search scope:** `README.md` (Troubleshooting table, Security section), `tests/run-tests.sh` (RB03, EC_KILL9_TAIL/EC01, SH9, I16 blocks), `.planning/phases/03-the-exit-code-contract/03-CONTEXT.md`, `.planning/phases/04-installer-and-launcher-surface/04-CONTEXT.md`, `scripts/install.sh:78-182,206-207`
**Files scanned:** 5
**Pattern extraction date:** 2026-08-21
