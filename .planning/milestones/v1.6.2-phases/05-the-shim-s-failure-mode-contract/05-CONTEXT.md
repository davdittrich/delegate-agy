# Phase 5: The shim's failure-mode contract - Context

**Gathered:** 2026-08-21
**Status:** Ready for planning

<domain>
## Phase Boundary

`README.md`'s documentation surface only — no change to `scripts/gemini_shim.sh` or `scripts/agy_bridge.sh` logic is in scope for this phase. Phase 5 states, in one place, what `gemini` does to a caller that has never heard of agy, for each of four failure modes (hung agy, unparseable model list, missing dependency, superseded pin), with the bridge's behavior alongside for comparison, and closes any test gap that would let one of those four rows go stale silently.

**Scouted, not hypothesized:** three of the four rows are already byte-identical between the shim and the bridge, sharing the exact same code:
- Missing-dependency (no `timeout`/`gtimeout`) warning — `RB_NO_TIMEOUT_WARN`, one literal, defined once per script, pinned equal by `RB03` (`tests/run-tests.sh:2498-2554`).
- Hung-agy / external-kill message — `EC_KILL9_TAIL`, shared tail literal (Phase 3, `03-CONTEXT.md` §D-11/D-12).
- Superseded-pin refusal (exit 127) — `write_wrapper()` (`scripts/install.sh:78-182`) is one function, invoked identically for both `"gemini"` and `"agy-bridge"` (`install.sh:206-207`); only the exec target and printed name differ.

Only one row carries a real, deliberate divergence: a degraded model list makes the bridge warn loud and exit 2, while the shim degrades silently. Phase 2's `02-CONTEXT.md` §D-05 explicitly punted the question of revisiting this to Phase 5 ("this phase does not add a shim warning; that's S3/Phase 5 territory if it's ever revisited").

Criterion 4 (an unrecognized model name still reaches agy unchanged, never hard-rejected) is already true and already pinned by test `SH9` (`tests/run-tests.sh:1320-1329`) — no new work needed there.

**In scope:**
- Fold the four-row failure-mode contract into the existing Troubleshooting table (`README.md:220-236`), not a new section.
- Ensure every row states, in one line, whether the shim and bridge behave the same (and why that's fine to leave unstated as "same, shared code") or differently (and why).
- Cite existing test coverage per row (`RB03`, `RB04`/`RB05`/runtime-proof tests, `SH14`/`SH15`-series, `I16`/`I17`/`I18`) rather than duplicating it.

**Out of scope:**
- Any code change to `scripts/gemini_shim.sh` or `scripts/agy_bridge.sh` — this phase documents and tests what earlier phases already made true, it does not change behavior.
- A new test independently proving the `gemini` wrapper (as opposed to the `agy-bridge` wrapper) refuses a stale pin — declined (D-02 below); `I16`'s coverage of the shared `write_wrapper()` function is treated as sufficient.
- Reopening the model-list silent-vs-loud divergence's behavior — declined (D-03 below); only the documentation states the reason, no code changes.

</domain>

<decisions>
## Implementation Decisions

### Contract table placement

- **D-01:** Fold the four-row failure-mode contract into the existing Troubleshooting table (`README.md:220-236`) rather than creating a new section. **User's explicit choice — overrides "new dedicated section."** The existing table already carries most of the needed content in a different index (by error/exit-code rather than by failure-mode): the degraded-model-list row (`:230`), the timeout-124 row (`:231`), the OOM/external-kill-137 row (`:232`), and the missing-dependency warning row (`:234`) already state shim-vs-bridge behavior inline; the superseded-pin explanation currently lives in the Security section (`:258`) rather than the Troubleshooting table and needs consolidating in. The planner/executor must decide exactly how the fold reads — whether by adding a short lead-in sentence framing the existing rows as the four-mode contract, by adding an explicit "same for both / differs because" clause to any row missing one, or by literally re-keying rows — but the row must land in the existing table, not a parallel one. — **Reversibility:** reversible — a doc-only restructuring.

### Superseded-pin test coverage

- **D-02:** Cite `I16` (`tests/run-tests.sh:4330-4453`) as sufficient proof for the superseded-pin row; do not add a new test independently exercising the `gemini` wrapper's own exit-127 refusal. **User's explicit choice — overrides "add a direct gemini-wrapper assertion."** `write_wrapper()` (`install.sh:78-182`) is one function invoked identically for both `"gemini"` and `"agy-bridge"` (`install.sh:206-207`) — no branch in the generated wrapper differs by name except the exec target and the printed error text. This is the same "trust shared/shipped code, don't re-verify" pattern Phase 4's `04-CONTEXT.md` §D-07 already applied to criteria 1-3 of the registry read. **Noted departure from this project's own stated per-entry-point-proof convention** (R11's "test reads scripts... runtime proof per entry point, on both mechanisms"; Phase 3's EC03 "mirror the guard into `gemini_shim.sh`" rather than infer from the bridge) — the user weighed that convention against this specific case and judged the shared-function structure different enough (one function, two call sites, no per-name branching) to not warrant duplicate proof. Record this row in the contract table as "same for both, shared `write_wrapper()`, proven via `I16`" so a reader can see the citation is to shared-code evidence, not a per-entry-point test. — **Reversibility:** reversible — a gap identified but not closed; adding the direct assertion later costs nothing this decision forecloses.

### Model-list divergence — document, don't reopen

- **D-03:** Document the shim-silent/bridge-loud divergence on a degraded model list as final; make no code change to `scripts/gemini_shim.sh`'s `load_models()`. **User's explicit choice — overrides "add a quiet signal" (e.g., an opt-in env-gated log line).** One-line reason for the table: the shim shadows `gemini` for every PATH caller (Octopus, Metaswarm, interactive shells) that never opted into agy, so a stderr warning there is box-wide noise; the bridge is an explicit, watched invocation where a loud warning costs nothing. This closes the question Phase 2's `02-CONTEXT.md` §D-05 explicitly left open for this phase — the answer is "keep as designed," not "revisit." — **Reversibility:** reversible — re-opening `load_models()` later to add a signal is a local change to one function; nothing this phase does forecloses it.

### Claude's Discretion

- **Exact fold mechanics for D-01** — whether the four-mode contract reads as a lead-in paragraph plus existing rows, an added "Divergence" note per row, or a light re-keying of the table — subject to landing all four modes in the one existing table and satisfying ROADMAP criterion 3 (every differing row states why, in one line; non-differing rows say so too so a reader isn't left wondering).
- **Which specific existing test IDs to cite per row** in the table or in planning docs — `RB03` (missing dependency), the Phase 1 runtime-proof tests (hung agy), `SH14`/`SH15`-series (unparseable model list), `I16` (superseded pin), `SH9` (criterion 4 passthrough) — subject to citing the actual line ranges, not paraphrasing test intent.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase intent and requirements
- `.planning/ROADMAP.md` §"Phase 5: The shim's failure-mode contract" — the four success criteria and the note that each dependency phase (1, 1.5, 2, 3, 4) settles one of the four failure-mode rows
- `.planning/REQUIREMENTS.md` §S3 — the requirement this phase closes: "every failure mode, shim's behavior toward non-agy-aware caller is stated and tested — hang, unparseable model list, missing dependency, superseded pin. Where shim and bridge diverge, divergence is deliberate and documented."
- `.planning/PROJECT.md` §Core Value — "Delegation must never break the caller" — the box-wide-noise rationale behind D-03 traces directly to this

### Prior-phase decisions this phase inherits
- `.planning/phases/02-model-list-handling-end-to-end/02-CONTEXT.md` §D-05 — explicitly defers the "should the shim warn on a degraded list" question to this phase; D-03 answers it
- `.planning/phases/02-model-list-handling-end-to-end/02-CONTEXT.md` §D-07 — the shim's stderr-visibility asymmetry with the bridge (bridge relays `$_agy_err`, shim never captures it) — same divergence class as D-03, already decided, restated not reopened
- `.planning/phases/04-installer-and-launcher-surface/04-CONTEXT.md` §D-07 — "trust shipped/shared coverage, don't re-verify" pattern D-02 applies to `I16` and the shared `write_wrapper()`
- `.planning/phases/03-the-exit-code-contract/03-CONTEXT.md` §D-11/D-12 — the RB03-style provenance-pinning convention this phase's table citations follow, and its limits

### Existing test coverage this phase cites (do not duplicate)
- `tests/run-tests.sh:2498-2554` (`RB03`) — both scripts define the missing-timeout warning once, README quotes both literals — cited for the "missing dependency" row
- `tests/run-tests.sh` Phase 1 Wave 4 runtime-proof tests (`RB04`/`RB05`/`RB13`/`RB06b-c`, see `01-CONTEXT.md`) — per-entry-point proof that nothing outlives its bound — cited for the "hung agy" row
- `tests/run-tests.sh:1320-1329` (`SH9`) — unknown model reaches agy unchanged, warning on stderr only — cited for criterion 4 (passthrough)
- `tests/run-tests.sh` `SH14`/`SH15`/`SH15b`/`SH15c` (see `02-CONTEXT.md`) — shim-side degraded-list handling — cited for the "unparseable model list" row
- `tests/run-tests.sh:4330-4453` (`I16`) — stale pin vs. install registry → exit 127, tested against the `agy-bridge` wrapper instance — cited for the "superseded pin" row per D-02

### Code under change (read on `master`, current state)
- `README.md:220-236` — the existing Troubleshooting table D-01 folds the contract into
- `README.md:258` — Security section's superseded-pin paragraph, source material to consolidate into the fold
- `README.md:292-298` (`#### Bounding without timeout/gtimeout`) — existing prose already stating shim/bridge sameness for the missing-dependency row
- `scripts/install.sh:78-182` (`write_wrapper`) — the shared function D-02's citation rests on; read-only, no change
- `scripts/gemini_shim.sh:465-495` (`map_model`) — the passthrough-on-unresolved logic criterion 4 already satisfies; read-only, no change
- `scripts/gemini_shim.sh:404-429` (`load_models`) — the silent-degrade logic D-03 documents as final; read-only, no change

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- The existing Troubleshooting table rows (`README.md:230-234`) already carry most of the shim-vs-bridge prose this phase needs — D-01's fold reuses and consolidates them rather than starting from a blank table.
- `RB_NO_TIMEOUT_WARN` and `EC_KILL9_TAIL` — the two shared literals proving byte-identical shim/bridge behavior for two of the four rows; cite, don't re-derive.

### Established Patterns
- "Trust shipped/shared coverage, don't re-verify" — Phase 2's D-01/D-02, Phase 4's D-07, and now this phase's D-02 all apply the same pattern to already-closed criteria.
- Fixed-literal warnings, defined once per script, quoted verbatim where README references them — Phase 1's D-09/D-10 convention; this phase's table citations follow it rather than paraphrasing.

### Integration Points
- `write_wrapper()`'s two call sites (`install.sh:206-207`) — the single seam D-02's citation rests on; any future divergence between the two wrapper instances would have to be introduced here, which is exactly why the shared-function argument holds today.

</code_context>

<specifics>
## Specific Ideas

- User explicitly chose to fold the new contract into the existing Troubleshooting table (D-01) over a new dedicated section — avoid a second table saying similar things.
- User explicitly chose to cite `I16`'s shared-code coverage over adding a new per-entry-point test for the superseded-pin row (D-02) — a deliberate, noted departure from this project's usual per-entry-point-proof convention, not an oversight.
- User explicitly chose to document the model-list silent/loud divergence as final (D-03) over adding a quiet shim-side signal — this closes the question Phase 2 left open for this phase.

</specifics>

<deferred>
## Deferred Ideas

- **A quiet, opt-in signal for the shim on a degraded model list** — considered under D-03 and declined for this phase. Would reopen `gemini_shim.sh`'s `load_models()`, a real code change, not a documentation one. Revisit only if an operator incident makes the current silence a real problem.
- **A direct test proving the `gemini` wrapper (not just `agy-bridge`) refuses a stale pin** — considered under D-02 and declined; the gap is real but judged low-risk given the shared-function structure. Revisit if `write_wrapper()` ever grows a name-conditional branch.

### Reviewed Todos (not folded)
None — `cross_reference_todos` found zero matches for Phase 5.

</deferred>

---

*Phase: 5-The shim's failure-mode contract*
*Context gathered: 2026-08-21*
