---
phase: 5
reviewers: [codex, antigravity]
reviewed_at: 2026-08-21T15:59:51Z
plans_reviewed: [05-01-PLAN.md, 05-02-PLAN.md]
models:
  codex: "gpt-5.6-sol (reasoning=low)"
  antigravity: "unknown"
model_sources:
  codex: "banner"
  antigravity: "unknown"
---

# Cross-AI Plan Review — Phase 5

## Codex Review

### Summary

Phase is well scoped and grounded in existing behavior: documentation and regression-contract tests only, no shipped script changes. Source review confirms the important shim/bridge divergences described in Plan 05-02. However, Plan 05-01 contains a blocking test-design error: FM01 requires the missing-dependency warning phrase to occur exactly once across all of `README.md`, but it deliberately already occurs twice — once in the Troubleshooting table, once in the detailed bounding section. There are also weaker traceability/wording issues: the proof-ID guard is disconnected from the README rows it's meant to back, and two proposed explanations incorrectly describe two invocations of the same function as a "shared" mechanism.

### Plan 05-01

**Strengths**

- Superseded-pin behavior is genuinely implemented as one function used by both launchers. `write_wrapper()` generates the wrapper at [scripts/install.sh:78](scripts/install.sh:78), invoked for both `agy-bridge` and `gemini` at [scripts/install.sh:206](scripts/install.sh:206) and [scripts/install.sh:207](scripts/install.sh:207). The I16 shared-function evidence is consistent with D-02.
- The pinning-refusal fragment adds real value: the emitted text lives at [scripts/install.sh:162](scripts/install.sh:162), while I16 tests the runtime refusal behavior at [tests/run-tests.sh:4330](tests/run-tests.sh:4330) but does not bind the wording to README.
- Keeping the Security paragraph intact is appropriate — it contains materially different guarantees (comparison-only registry input, pinned exec target) at [README.md:258](README.md:258), and should not be replaced by the shorter operational row at [README.md:220](README.md:220).
- Plan correctly reuses the existing Troubleshooting table rather than creating a parallel contract surface; that table is already the operator-facing error reference.

**Concerns**

- **HIGH** — FM01's missing-dependency uniqueness assertion is unsatisfiable as written. The warning phrase already occurs twice in README ([README.md:234](README.md:234) and [README.md:308](README.md:308)) — once in the Troubleshooting table, once in the detailed bounding section — and the plan does not scope the exactly-once check to the Troubleshooting table only.
- **MEDIUM** — The proof-ID guard verifies that labels like RB03/I16 still occur as `ok`/`bad` calls somewhere in `tests/run-tests.sh`, but does not verify that the README row actually contains the corresponding ID, nor maintain a machine-checked row-to-proof mapping. For example, RB03's label exists at [tests/run-tests.sh:2551](tests/run-tests.sh:2551), but FM01 would pass even if README stopped citing RB03 altogether.
- **MEDIUM** — "Same shared `run_bounded` helper" is factually inaccurate. The scripts contain separate definitions at [scripts/agy_bridge.sh:224](scripts/agy_bridge.sh:224) and [scripts/gemini_shim.sh:243](scripts/gemini_shim.sh:243). Earlier tests establish byte-identity, not a single shared runtime helper. Prefer "byte-identical copies of `run_bounded`" or "the same bounded-execution mechanism."
- **LOW** — "Same `write_wrapper()` call" is imprecise: these are two calls to the same function, not one call producing two outputs ([scripts/install.sh:206](scripts/install.sh:206)-[207](scripts/install.sh:207)). The shared-code argument remains valid; prefer "the same `write_wrapper()` implementation, invoked once per launcher."
- **LOW** — FM01's `because`/`identical` check is a syntactic shape gate, easily satisfied by meaningless prose, while Plan 05-01's language ("pin the contract end-to-end") overstates what the check actually establishes. Plan 05-02 eventually records this as a named ceiling; 05-01 does not.

**Suggestions**

- Scope the row-uniqueness check to the Troubleshooting table only, not the whole README: extract lines between `## Troubleshooting` and `### Running tests`, and require the matching line begin with `|`. Keep the second, more detailed warning in the bounding section verbatim.
- Make the proof-to-row mapping explicit and testable rather than a loose existence check.

**Risk Assessment: HIGH** as currently written — the global README occurrence-count check cannot satisfy both acceptance criteria (uniqueness + preserving the existing detailed warning). After correcting the check's scope, risk drops to medium-to-low since changes are confined to documentation and test assertions.

### Plan 05-02

**Strengths**

- Timeout divergence is accurately traced: the shim prints to stderr and exits 124 without inspecting output mode at [scripts/gemini_shim.sh:686](scripts/gemini_shim.sh:686); the bridge forks JSON/text handling at [scripts/agy_bridge.sh:748](scripts/agy_bridge.sh:748)-[757](scripts/agy_bridge.sh:757).
- Keeping exit 124 and exit 137 as separate rows is correct — the existing exit-137 row explicitly says increasing the timeout will not help ([README.md:232](README.md:232)); combining them would lose an operationally important distinction.
- The degraded-list divergence is real: the bridge exits 2 when no normalized `gemini-` IDs remain ([scripts/agy_bridge.sh:547](scripts/agy_bridge.sh:547)), while the shim intentionally treats an unresolved list as pass-through rather than fatal, documented in code at [scripts/gemini_shim.sh:411](scripts/gemini_shim.sh:411)-[412](scripts/gemini_shim.sh:412).
- The unknown-model divergence is also accurately identified: the bridge rejects before delegation ([scripts/agy_bridge.sh:560](scripts/agy_bridge.sh:560)-[562](scripts/agy_bridge.sh:562)), while the shim warns and passes it through unchanged ([scripts/gemini_shim.sh:487](scripts/gemini_shim.sh:487)-[493](scripts/gemini_shim.sh:493)); SH9 verifies the forwarded-model, stderr-only warning at [tests/run-tests.sh:1310](tests/run-tests.sh:1310)-[1329](tests/run-tests.sh:1329)).
- Adding a fifth row is justified rather than scope creep: although S3 names four failure modes, Roadmap criterion 4 separately requires the unknown-model pass-through remain visible and tested; folding it into the same table gives operators one coherent contract.
- Plan 05-02 honestly acknowledges FM01's semantic limit: grep can enforce row shape, but human review must determine whether the stated rationale is actually true.

**Concerns**

- **MEDIUM** — Plan 05-02 inherits Plan 05-01's broken FM01 foundation; the wave cannot begin successfully until the duplicate missing-warning occurrence is handled.
- **MEDIUM** — "Every row has a test" mostly represents label existence, not behavioral linkage. SH14 does exercise the quiet degraded-list pass-through ([tests/run-tests.sh:1424](tests/run-tests.sh:1424)-[1442](tests/run-tests.sh:1442)), and SH9 exercises the unknown-name pass-through, but merely checking that labels still exist does not ensure the assertions still match the corresponding README claims.
- **LOW** — The degraded-list explanation risks conflating a model-list failure with forwarding a particular name: the shim's `load_models()` degrades silently, but `map_model()` warns only when a valid live list does not recognize the supplied name — comments explicitly suppress the warning when the list itself is degraded ([scripts/gemini_shim.sh:487](scripts/gemini_shim.sh:487)-[491](scripts/gemini_shim.sh:491)). README wording must keep these two cases distinct.
- **LOW** — Closing S3 while retaining ticket `cy5` could confuse status readers; may be correct since the ticket is shared with R11, but the new status text should explicitly say why the ticket remains listed against a met requirement.
- **LOW** — The final changed-file check may include pre-existing user changes — the current worktree already contains modifications to untracked planning/support files. The plan's expected-changed-file list should be compared against a captured baseline (`git status --porcelain` at phase start), not asserted against the entire repository, so it doesn't imply the phase introduced unrelated pre-existing changes.

**Suggestions**

- Fix FM01 in Plan 05-01 before approving Wave 2.
- For each anchor, encode an explicit mapping: `anchor | README row | source literal | behavioral test ID`. Then FM01 can independently check: one table-row match; required entry-point names in the disposition marker; source provenance validity; existence of a mapped behavioral test.
- In the degraded-list row, state clearly that the shim silently passes the requested name unchanged when the list is unavailable or unusable; reserve the stderr warning for the separate case where a valid list exists but does not contain the name.
- Capture `git status --porcelain` as a phase-start baseline and diff the end-state against it, rather than asserting on the whole repo.

**Risk Assessment: MEDIUM** — behavioral analysis strongly matches the scripts, and the phase does not alter runtime code. Risk comes from dependency on the broken Plan 05-01 FM01 gate, plus weaker row-to-test traceability than the plan claims.

### Overall Risk

**HIGH as currently written**, driven entirely by the unsatisfiable missing-dependency uniqueness assertion in Plan 05-01. Correcting the check to be table-scoped reduces overall phase risk to **MEDIUM-LOW**: runtime claims are substantially accurate, dependency ordering is sensible, and changes are confined to README, tests, and planning traceability.

---

## Antigravity Review

### 1. Summary

Phase 5's plan set (`05-01-PLAN.md`, `05-02-PLAN.md`) provides a rigorous, highly disciplined approach to fulfilling requirement S3 ("a shim defect must not escape into unrelated PATH callers"). By treating documentation as a testable contract, the plans consolidate the failure modes and behavioral divergences between `agy-bridge` and the `gemini` shim into `README.md`'s existing Troubleshooting table ([README.md:220-236](README.md:220-236)), while introducing a dedicated regression gate, `FM01`, in `tests/run-tests.sh`. Crucially, the phase is strictly non-invasive to runtime logic — enforcing a hard zero-diff boundary on `scripts/` — while introducing bidirectional static provenance assertions between docs and shipped code ([scripts/install.sh:162](scripts/install.sh:162), [scripts/gemini_shim.sh:493](scripts/gemini_shim.sh:493)). The phase cleanly balances exhaustive verification with scope discipline.

### 2. Strengths

- **Exact Code-Grounded Provenance Verification:**
  - Mirrors the battle-tested literal-pinning pattern established by RB03 ([tests/run-tests.sh:2498-2555](tests/run-tests.sh:2498-2555)) and EC06 ([tests/run-tests.sh:2584-2685](tests/run-tests.sh:2584-2685)). Literals are defined verbatim in the test rather than dynamically extracted from target files (preventing circular tautologies).
  - Establishes two-way static anchors: pins README's superseded-pin refusal to `scripts/install.sh:162` (`"is installed, but launcher pinned to"`), and README's model passthrough warning to `scripts/gemini_shim.sh:493` (`"did not resolve agy model list; passing through unchanged"`).
- **Strict Scope Boundaries and Safety Invariants:**
  - Enforces `git diff --name-only -- scripts/ | wc -l == 0` across every task acceptance criterion, preventing accidental drift into runtime shell scripts.
  - Respects Phase 5 context decisions: folds the contract into the existing Troubleshooting table (D-01), accepts shared-function coverage via I16 ([tests/run-tests.sh:4451](tests/run-tests.sh:4451)) for `write_wrapper()` (D-02), and documents degraded-list silence without reopening `load_models()` in [scripts/gemini_shim.sh:404-429](scripts/gemini_shim.sh:404-429) (D-03).
  - Explicitly preserves adjacent invariants: guards README.md:258's comparison-only registry security claims (`git diff -U0 README.md | grep -c '^[-+].*comparison-only' == 0`), and preserves exit 137 ([README.md:232](README.md:232)) as a row distinct from exit 124 timeout ([README.md:231](README.md:231)).
- **Citation-Rot Protection:**
  - Implements an automated guard ensuring all cited test proof labels (RB03, EC06, SH14, SH9, I16) actually exist as `ok`/`bad` invocations in `tests/run-tests.sh`, preventing test reorganization from silently invalidating documentation claims.
- **TDD Mutation Demonstration:**
  - Enforces an explicit observed-RED state prior to the documentation updates, as well as a deliberate label-deletion mutation test against SH14 to prove the citation-rot guard is actually functional.

### 3. Concerns

- **[LOW] Syntactic Shape Gate, Not Semantic Check (`because` vs. `identical`):**
  - *Mechanism:* FM01 asserts matched README lines contain `agy-bridge`, `gemini`, and either `because` or `identical`.
  - *Trace:* This mechanically ensures a rationale clause is present in the markdown table row, but is only a syntactic proxy for semantic justification.
  - *Evidence:* Handled appropriately — Task 3's explicit `<human-check>` instruction ([05-02-PLAN.md:798-799](.planning/phases/05-the-shim-s-failure-mode-contract/05-02-PLAN.md)) states this as a ceiling in the plan, acknowledging semantic accuracy requires human review.
- **[LOW] Risk of Triggering RB03's Negative Assertion on "unbounded":**
  - *Mechanism:* [tests/run-tests.sh:2549](tests/run-tests.sh:2549) runs `grep -qiF 'unbounded' "$_RB_README"`.
  - *Trace:* In the one-line reason for the missing-dependency row ([README.md:234](README.md:234)) explaining fallback execution, any casual use of the word "unbounded" would trip RB03's negative assertion.
  - *Evidence:* Plan 05-01 Task 1 explicitly cites [tests/run-tests.sh:2528-2549](tests/run-tests.sh:2528-2549) in `<read_first>` to warn the executor of the exact constraint.
- **[LOW] Citation Guard Regex Specificity:**
  - *Mechanism:* Plan 05-01 Task 2 instructs matching `ok` or `bad` calls starting with `${ID} `.
  - *Trace:* In `tests/run-tests.sh`, test reporting helpers use forms like `ok "SH14 ..."` or `bad "SH14 ..."`. The matcher should account for single or double quote variations (e.g. `^[[:space:]]*(ok|bad)[[:space:]]+["']${id}[[:space:]]`).

### 4. Suggestions

- **Ensure Quote-Agnostic Matching in Citation Guard:** In `tests/run-tests.sh`, implement the citation-rot check using `grep -qE "^[[:space:]]*(ok|bad)[[:space:]]+[\"']${id}[[:space:]]"` to ensure robustness against quote style variations.
- **Maintain Markdown Table Row Single-Line Formatting:** When expanding the descriptions for [README.md:229](README.md:229), 230, 231, 234, and 226, ensure each table row remains on a single physical line without unescaped raw newlines so that standard line-oriented grep filters (`grep -cF`) match cleanly.

### 5. Risk Assessment: LOW

- **No Runtime Code Modifications:** The phase alters zero lines in `scripts/`.
- **Deterministic & High-Speed Verification:** The test harness `tests/run-tests.sh` runs locally and quickly against `tests/fake-agy.sh` without external network access or real agy quota consumption.
- **Full Reversibility:** Any unexpected discrepancy or failure in FM01 or README.md can be rolled back trivially with no database, schema, or API breakage.

---

## Consensus Summary

Both reviewers independently traced the plans against the live source tree and largely agree the phase's strict zero-diff boundary on `scripts/` and its literal-pinning test pattern (reusing the RB03/EC06 approach) are sound. **The reviews diverge sharply on overall risk** (Codex: HIGH-as-written / Antigravity: LOW) because only Codex actually counted the missing-dependency phrase's occurrences in README.md and found FM01's uniqueness assertion unsatisfiable — Antigravity's LOW rating does not account for this blocking defect and should not be read as contradicting it.

### Agreed Strengths

- Hard scope discipline: the `git diff --name-only -- scripts/ | wc -l == 0` (or equivalent) invariant keeps the phase strictly documentation/test-only, with no runtime script changes — noted by both reviewers.
- The provenance-pinning mechanism (anchoring README claims to literal, verbatim strings at [scripts/install.sh:162](scripts/install.sh:162) and [scripts/gemini_shim.sh:493](scripts/gemini_shim.sh:493), following the RB03/EC06 precedent) is well-grounded and avoids circular tautologies — both reviewers cite the exact same anchors as evidence.

### Agreed Concerns

- **The FM01 rationale check (`because`/`identical`) is a syntactic shape gate, not a semantic one.** Both reviewers flag this independently — Codex as MEDIUM-adjacent ("easy to satisfy with meaningless prose... 05-01's language overstates what the check establishes"), Antigravity as LOW (noting Plan 05-02's Task 3 already names this as an acknowledged ceiling via `<human-check>`). Net: acceptable if Plan 05-01 is corrected to match 05-02's honesty about the limit, not left overstated.
- **The citation/proof-ID guard's fidelity is weaker than claimed**, though the two reviewers found different specific gaps: Codex (MEDIUM) — the guard confirms a label like RB03 exists *somewhere* in `tests/run-tests.sh` but never checks that the corresponding README row actually cites that ID, so README could drop a citation and FM01 would still pass. Antigravity (LOW) — the guard's `ok`/`bad` regex may not be quote-style-agnostic and should use `["']` to match both quoting conventions. These are complementary, not conflicting — both point at the same guard needing a stronger regex and a real row-to-proof mapping, not just label existence.

### Divergent Views

- **Codex's HIGH-severity, plan-blocking finding was not caught by Antigravity at all**: FM01 requires the missing-dependency warning phrase to appear exactly once across all of README.md, but it verifiably already occurs twice ([README.md:234](README.md:234) and [README.md:308](README.md:308)) — in the Troubleshooting table and in the detailed bounding section. As written, Task 1 cannot satisfy both "assert uniqueness" and "preserve the existing detailed warning." This is a concrete, source-verified defect that should block Wave 2 until the check is scoped to the Troubleshooting table only (Codex's suggested fix). Antigravity's LOW overall risk rating appears to have missed this specific occurrence-count check.
- **"Shared" terminology precision**: Codex separately flags that "same shared `run_bounded` helper" is factually imprecise — the scripts hold two separate, byte-identical *copies* of `run_bounded` ([scripts/agy_bridge.sh:224](scripts/agy_bridge.sh:224), [scripts/gemini_shim.sh:243](scripts/gemini_shim.sh:243)), not one shared runtime helper — while Antigravity's strengths section accepts "shared-function coverage via I16 for `write_wrapper()`" without flagging the same imprecision for `run_bounded`. This isn't a direct contradiction (Antigravity's example is `write_wrapper()`, which genuinely is one shared function; Codex's concern is specifically about `run_bounded` wording), but the plans should apply Codex's stricter terminology to `run_bounded` claims regardless.
- **Antigravity's phase-start baseline concern for the changed-files check** ([05-02-PLAN.md:798-799](.planning/phases/05-the-shim-s-failure-mode-contract/05-02-PLAN.md) area) and its RB03 "unbounded"-trigger-word warning are both unique findings Codex did not raise — worth folding into the fix round even though only one reviewer surfaced them, since both cite exact source lines.
