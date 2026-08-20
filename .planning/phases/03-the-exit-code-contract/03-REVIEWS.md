---
phase: 03
reviewers: [antigravity, codex]
reviewed_at: 2026-08-20T17:42:15Z
plans_reviewed: [03-01-PLAN.md, 03-02-PLAN.md, 03-03-PLAN.md, 03-04-PLAN.md]
models:
  antigravity: "unknown"
  codex: "unknown"
model_sources:
  antigravity: "unknown"
  codex: "unknown"
---

# Cross-AI Plan Review — Phase 3

## Antigravity Review

# Cross-AI Plan Review: Phase 3 — The Exit-Code Contract

## 1. Summary

The implementation plans for Phase 3 (`03-01-PLAN.md` through `03-04-PLAN.md`) establish a well-structured, incremental TDD path to eliminate trailing separator bugs (`delegate-agy-v5a`), synchronize documentation with runtime error messages (`delegate-agy-6q1`), and enforce exact exit-code contracts across `scripts/agy_bridge.sh` and `scripts/gemini_shim.sh`. The phased wave architecture (Wave 1: tracer on bridge external kill; Wave 2: mirroring to shim and generic nonzero; Wave 3: README audit and exit-2 consistency pass; Wave 4: strict numeric assertion and R6 payload pinning) enforces tight scope boundaries and prevents test regression. All claims and line references have been verified directly against source files in the repository.

---

## 2. Strengths

- **Surgical, Single-Point Guard Logic:** In [scripts/agy_bridge.sh:719-732](file:///home/dd/Gemini/delegate-agy/scripts/agy_bridge.sh#L719-L732) and [scripts/gemini_shim.sh:668-675](file:///home/dd/Gemini/delegate-agy/scripts/gemini_shim.sh#L668-L675), both the plain-text and JSON error-formatting paths currently produce dangling trailing colons when `$STDERR_FILE` is 0 bytes or contains only whitespace (`open(sys.argv[5]).read()` vs `$(cat "$STDERR_FILE")`). Using Bash parameter expansion `${_err_txt:+: $_err_txt}` in Wave 1 and Wave 2 provides a clean, single-point guard in Bash without redundant string parsing inside Python.
- **Strict Separation of stdout and stderr in Test Harness:** Plan 04 correctly observes that the standard test runner helper `_run` ([tests/run-tests.sh:105-113](file:///home/dd/Gemini/delegate-agy/tests/run-tests.sh#L105-L113)) merges streams via `2>&1`. Testing R6 (zero-byte stdout on exit 3) using `_run` would pass vacuously because stderr contains the diagnostic message. Introducing `_ec_run_split` to capture stdout and stderr independently into discrete variables/files closes a critical testing loophole.
- **Accurate Divergence Tracking between Bridge and Shim:**
  - On generic nonzero exit codes ([scripts/agy_bridge.sh:750](file:///home/dd/Gemini/delegate-agy/scripts/agy_bridge.sh#L750) vs [scripts/gemini_shim.sh:680](file:///home/dd/Gemini/delegate-agy/scripts/gemini_shim.sh#L680)), the bridge prefixes `ERROR: agy exit %d:` while the shim directly outputs raw stderr. Plan 02/03 preserves this intentional design divergence rather than forcing unnecessary unification.
  - On exit 3 JSON envelopes ([scripts/agy_bridge.sh:767-771](file:///home/dd/Gemini/delegate-agy/scripts/agy_bridge.sh#L767-L771) vs [scripts/gemini_shim.sh:699-704](file:///home/dd/Gemini/delegate-agy/scripts/gemini_shim.sh#L699-L704)), the bridge emits a flat envelope (`{"success":false,...,"error":...,"error_class":...}`) while the shim emits a nested envelope (`{"error":{"message":...,"class":...}}`). Plan 04 asserts the absence of the `response` key in both without forcing schema breakage on downstream consumers like Metaswarm and Octopus.
- **Provenance Discipline (RB03 Pattern):** Plans 02 and 03 extend the proven provenance check pattern from [tests/run-tests.sh:2019-2073](file:///home/dd/Gemini/delegate-agy/tests/run-tests.sh#L2019-L2073) (`RB03`) to assert exact literal synchronization between [README.md:220-235](file:///home/dd/Gemini/delegate-agy/README.md#L220-L235) and script output constants, preventing doc-drift regressions like `delegate-agy-6q1`.
- **Pre-existing Test Integrity Protection:** In accordance with D-12, historical tests (`T4`, `T5`, `SH4`-`SH6`, `B2`, `S2`) that check loose conditions (`RC -ne 0`) are preserved untouched, with new strict assertions (`EC01`-`EC08`) added adjacently.

---

## 3. Concerns

- **`fake-agy.sh` Early Exit 137 Stderr Behavior (Severity: LOW)**
  - *Context:* In [tests/fake-agy.sh:237-239](file:///home/dd/Gemini/delegate-agy/tests/fake-agy.sh#L237-L239), the `FAKE_AGY_PRINT_KILL9` branch currently exits 137 unconditionally before evaluating `FAKE_AGY_STDERR` (which is printed at line 292).
  - *Trace:* Plan 01 modifies `fake-agy.sh` so `FAKE_AGY_PRINT_KILL9` emits `FAKE_AGY_STDERR` when set. If `fake-agy.sh` is not modified *before* `EC01`/`EC02` run non-empty stderr assertions, those tests will fail or pass vacuously on empty stderr.
  - *Mitigation:* Plan 01 Task 1 explicitly lists `tests/fake-agy.sh` as an affected file in Task 1 before implementing assertions in `tests/run-tests.sh`.

- **Handling `delegate-agy-b7g` in Exit-2 Consistency Pass (Severity: LOW)**
  - *Context:* In [scripts/agy_bridge.sh:530](file:///home/dd/Gemini/delegate-agy/scripts/agy_bridge.sh#L530), a 0-byte `agy models` response without a cache emits `ERROR: failed to retrieve model list from agy` (exit 2). However, [README.md:230](file:///home/dd/Gemini/delegate-agy/README.md#L230) documents exit 2 exclusively as `agy model list contains no 'gemini-' ids; agy may be unauthenticated`.
  - *Risk:* Plan 03 Task 3 (D-09 pass) could trigger an unintended refactor of line 530 if not strictly bounded.
  - *Mitigation:* Plan 03 flagged assumptions explicitly identify `delegate-agy-b7g` as a known Phase 2/S1 model-fetch wording gap and mandate recording a verdict rather than modifying line 530 out-of-phase.

- **Integer Second Truncation at Timeout Boundary (Severity: LOW)**
  - *Context:* In [scripts/agy_bridge.sh:716](file:///home/dd/Gemini/delegate-agy/scripts/agy_bridge.sh#L716) and [scripts/gemini_shim.sh:665](file:///home/dd/Gemini/delegate-agy/scripts/gemini_shim.sh#L665), `DURATION=$(( SECONDS - START ))` truncates to whole integer seconds.
  - *Risk:* A SIGKILL arriving at `TIMEOUT - 0.1s` can evaluate as `DURATION < TIMEOUT` (external kill) or `DURATION == TIMEOUT` depending on integer boundary alignment.
  - *Mitigation:* Both Plan 01 and Plan 04 explicitly flag `edge:R5/precision` as an accepted ceiling inherited from Phase 1 D-02, tested strictly via simulated synthetic boundaries in `EC07`.

---

## 4. Suggestions

1. **Verify Python 3 Execution Path with Trailing Newlines in Stderr:**
   - In [scripts/agy_bridge.sh:727](file:///home/dd/Gemini/delegate-agy/scripts/agy_bridge.sh#L727), `open(sys.argv[5]).read()` preserves any trailing newline from the stderr file, whereas `_err_txt="$(cat "$STDERR_FILE" 2>/dev/null || true)"` in Bash strips trailing newlines. Ensure `_err_txt` is passed as a positional parameter into Python `sys.argv` (as specified in Plan 01 Task 2) so both plain-text and JSON envelopes receive identically stripped strings.
2. **Explicit Verification of `scripts/install.sh` Immutability:**
   - In Plan 03 Task 1, ensure the read-only check of the exit 127 message against [scripts/install.sh:135,161](file:///home/dd/Gemini/delegate-agy/scripts/install.sh#L135-L161) includes a pre- and post-task `git diff --exit-code scripts/install.sh` check to guarantee zero inadvertent modifications.

---

## 5. Risk Assessment

**Overall Risk Level: LOW**

**Justification:**
- The changes are localized to error-formatting branches and assertion test cases without modifying core process lifecycle, timeout loops, or model resolution logic.
- All modifications are strictly additive in the test suite and reversible single-hunk edits in the shell scripts.
- The 4-wave division cleanly decouples the tracer fix from cross-script propagation and documentation verification.
- Security constraints (untrusted stderr treated strictly as data arguments to `printf '%s'` and `sys.argv` slots, preventing format-string injection and code execution) are explicitly defined and tested.

---

## Codex Review

# Plan Review

## Summary

The plans are unusually thorough and largely align with the live implementation. They correctly target the current defects: the bridge's JSON external-kill path unconditionally appends `": "` ([scripts/agy_bridge.sh:727](/home/dd/Gemini/delegate-agy/scripts/agy_bridge.sh:727)), the shim has a mirrored kill branch, the fake's kill-137 path currently exits before its general stderr emission ([tests/fake-agy.sh:237](/home/dd/Gemini/delegate-agy/tests/fake-agy.sh:237), [tests/fake-agy.sh:292](/home/dd/Gemini/delegate-agy/tests/fake-agy.sh:292)), and the two entry points intentionally use different JSON envelope shapes ([scripts/agy_bridge.sh:770](/home/dd/Gemini/delegate-agy/scripts/agy_bridge.sh:770), [scripts/gemini_shim.sh:702](/home/dd/Gemini/delegate-agy/scripts/gemini_shim.sh:702)). The main weaknesses are excessive sequencing for a small formatting change, an unaddressed NUL-byte limitation in the proposed shared shell variable, and ambiguity about whether the final tests independently validate all five exit-code contracts or merely cite older tests.

Overall risk: **MEDIUM**. The production changes are small, but this is a box-wide shim and the proposed normalization changes observable stderr behavior.

## Plan 03-01

### Strengths

- It traces the defect end-to-end instead of testing a formatting helper in isolation. This is necessary because `FAKE_AGY_PRINT_KILL9` currently takes its special path at [tests/fake-agy.sh:237](/home/dd/Gemini/delegate-agy/tests/fake-agy.sh:237), before the ordinary `FAKE_AGY_STDERR` emission at [tests/fake-agy.sh:292](/home/dd/Gemini/delegate-agy/tests/fake-agy.sh:292).

- It accurately identifies the JSON defect. The bridge currently constructs the error with unconditional `sys.argv[4] + ': ' + open(...).read()` at [scripts/agy_bridge.sh:727](/home/dd/Gemini/delegate-agy/scripts/agy_bridge.sh:727).

- Keeping captured stderr out of Python source and out of the `printf` format string is sound. The current JSON path already transports values through positional arguments at [scripts/agy_bridge.sh:727](/home/dd/Gemini/delegate-agy/scripts/agy_bridge.sh:727).

- Explicit empty, non-empty, newline-only, and format-directive cases are valuable. They cover both the visible defect and common injection mistakes.

### Concerns

- **MEDIUM — the "every byte" invariant is false for shell variables.** `_err_txt="$(cat "$STDERR_FILE")"` cannot preserve NUL bytes because Bash variables cannot contain NUL. It also removes all trailing newline bytes. The current JSON implementation reads the file directly in Python at [scripts/agy_bridge.sh:727](/home/dd/Gemini/delegate-agy/scripts/agy_bridge.sh:727), so the proposed unification changes JSON behavior beyond merely removing a dangling separator.

- **MEDIUM — newline stripping is a policy change, not just a bug fix.** A stderr file containing `failure\n` will become `failure` in JSON after the proposed shared-shell-variable change. The plan acknowledges newline-only input, but its success criteria should explicitly state that all trailing newlines are normalized away.

- **LOW — the constant's proposed scope is confusing.** `EC_KILL9_TAIL` is described as a "shell constant" located inside the branch. Defining it at file scope would better satisfy "defined exactly once" and make provenance checks less fragile.

### Suggestions

- Define the actual contract as "text representable in a Bash variable after trailing-newline stripping," rather than claiming byte preservation.

- Add a NUL-bearing test or explicitly document NUL as unsupported. If preservation matters, let Python read the file and make the plain-text path use a file-size guard without transporting contents through a shell variable.

- State the precise normalized result for `text\n\n`, not only newline-only stderr.

## Plan 03-02

### Strengths

- Extending the correction to the shim is justified by its PATH-wide blast radius.

- Preserving the shim's raw generic-nonzero relay is correct. The plan does not force artificial parity where the implementations intentionally differ.

- Pinning the external-kill tail across both scripts and README is well targeted. The bridge currently supplies the sentence separately at [scripts/agy_bridge.sh:728](/home/dd/Gemini/delegate-agy/scripts/agy_bridge.sh:728), so drift is possible today.

- Testing `%`-bearing stderr as data is a useful security regression.

### Concerns

- **MEDIUM — "byte-identical" is underspecified across output modes.** JSON necessarily escapes some bytes while plain text does not. The intended comparison appears to concern decoded error strings, but the plan sometimes describes emitted bytes. EC03/EC05 should distinguish raw JSON bytes from parsed error values.

- **MEDIUM — the generic bridge JSON arm remains semantically different from its text arm.** The JSON branch reads raw stderr directly at [scripts/agy_bridge.sh:747](/home/dd/Gemini/delegate-agy/scripts/agy_bridge.sh:747), while the text branch supplies the `ERROR: agy exit N` context. Leaving it untouched satisfies the no-dangling-separator criterion, but README must document this output-mode divergence as well as the bridge-versus-shim divergence.

- **LOW — EC05's source counting is brittle.** Filtering comments before `grep -cF` does not distinguish a definition from a non-comment use containing the same literal. Exact count assertions can fail after harmless refactoring.

### Suggestions

- Compare parsed semantic strings for JSON and literal bytes for text.

- Document three generic-nonzero forms where applicable: bridge text, bridge JSON, and shim relay.

- Make EC05 locate the assignment syntax specifically, then separately assert that the symbol is used.

## Plan 03-03

### Strengths

- It respects the Phase 4 boundary: launcher code is inspected but not edited. The relevant generated-wrapper logic lives in [scripts/install.sh:137](/home/dd/Gemini/delegate-agy/scripts/install.sh:137) and [scripts/install.sh:173](/home/dd/Gemini/delegate-agy/scripts/install.sh:173).

- The exit-2 audit is constrained to consistency rather than expanding into comprehensive CLI parser coverage.

- Recording one verdict per `exit 2` site is a useful audit artifact, especially given the known `delegate-agy-b7g` exception.

- It correctly notices that timeout text is not shared. The bridge's JSON value is `Timeout after …` at [scripts/agy_bridge.sh:738](/home/dd/Gemini/delegate-agy/scripts/agy_bridge.sh:738), whereas the shim prints `ERROR: agy timeout after …` at [scripts/gemini_shim.sh:677](/home/dd/Gemini/delegate-agy/scripts/gemini_shim.sh:677).

### Concerns

- **HIGH — EC06 cannot treat exit 124 as one shared literal.** The live scripts use materially different capitalization and wording at the cited lines. The test artifact lists only one `_EC_TIMEOUT_LITERAL`, while its task says it will pin the message to both scripts. One literal cannot accurately represent both.

- **MEDIUM — exit-3 documentation exceeds the planned runtime coverage.** README will name `empty_output`, `quota`, and `auth`, but the later EC08 plan primarily pins the empty-stderr fallback. If existing classification tests are loose, a class-specific README claim can still drift.

- **MEDIUM — "every message README quotes is byte-for-byte present in source" is not sufficient for dynamic messages.** Exit-3 output includes runtime class and reason; exit-124 includes runtime timeout values. Static substring provenance does not prove the assembled output.

- **LOW — declaring `scripts/agy_bridge.sh` modified for a nominal read-only audit invites scope expansion.** The plan does prohibit edits without findings, but the default outcome should explicitly be no production change.

### Suggestions

- Split `_EC_TIMEOUT_LITERAL` into bridge and shim constants and document both forms.

- Add three exit-3 classification scenarios, or explicitly cite existing cases that prove each class and exact assembled message.

- Make the exit-2 audit task read-only by default; if it finds a new inconsistency, stop and record whether that finding belongs in this phase before editing.

## Plan 03-04

### Strengths

- The split-stream helper is necessary. The existing `_run` helper at [tests/run-tests.sh:105](/home/dd/Gemini/delegate-agy/tests/run-tests.sh:105) merges output, which cannot prove zero-byte stdout independently.

- Parsing JSON with Python and asserting the absence of `response` is the correct way to protect R6. The current bridge uses a flat failure envelope at [scripts/agy_bridge.sh:770](/home/dd/Gemini/delegate-agy/scripts/agy_bridge.sh:770), while the shim uses a nested envelope at [scripts/gemini_shim.sh:702](/home/dd/Gemini/delegate-agy/scripts/gemini_shim.sh:702).

- Testing a one-newline stdout as non-empty correctly reflects `test -s` byte semantics.

- Pinning strict `< bound` and branch ordering guards important behavior without adding multiple wall-clock timeout tests.

### Concerns

- **HIGH — EC07's stated scope conflicts with its mechanism.** Its truth says every one of the five codes is asserted and never conflated, but exit 2 and 127 are delegated to existing `R8`, `I16`, and `RB29` cases. Cross-referencing old cases does not establish cause-fragment exclusivity unless those cases already make those negative assertions.

- **MEDIUM — source assertions for control flow are fragile.** A textual assertion of branch order or `DURATION < TIMEOUT` can pass despite semantically equivalent restructuring, or fail after a safe refactor. Runtime boundary tests remain the stronger evidence.

- **MEDIUM — the newline-success case may expose invalid JSON behavior.** A one-newline agy stdout is correctly non-empty, but in JSON mode it may be passed through or wrapped differently. The plan should state and test the actual expected JSON behavior rather than merely asserting exit 0.

- **LOW — requirement closure is premature if the precision ceiling remains undocumented.** The plan explicitly acknowledges integer-second misclassification near the timeout boundary. R5 can still be met, but the traceability row should retain this known limitation.

### Suggestions

- Make EC07 a true aggregate contract test that runs or directly validates all five scenarios, or narrow its claims to the scenarios it actually executes.

- For exit 2 and 127, explicitly verify exact code, required cause fragment, and absence of timeout/kill/empty-output fragments.

- Keep runtime tests for well-inside versus at/after-bound behavior; use source checks only as supplementary ordering guards.

- Record the integer-resolution limitation in the final R5 status rather than marking the requirement unqualifiedly met.

## Cross-plan concerns

- **MEDIUM — over-sequencing and execution cost.** Four strictly serial waves, eight new cases, deliberate mutation exercises, manual probes, and roughly 240,000 estimated tokens are disproportionate to two separator guards, documentation corrections, and regression coverage. The safety-critical context warrants rigor, but Plans 01 and 02 could reasonably be one implementation plan, with Plans 03 and 04 forming the documentation/closure plan.

- **MEDIUM — mutation steps need safe mechanics.** Each plan requires temporary deliberate corruption and reversion. In a potentially dirty shared worktree, executors must restore only their exact mutation and must not use broad checkout/reset operations.

- **LOW — tests depend heavily on static grep provenance.** Static checks are useful for documentation drift, but should not be described as proof of runtime output. The plans mostly recognize this, though EC05/EC06 still overstate it.

## Recommended disposition

Approve with revisions. Before execution:

1. Resolve the NUL/trailing-newline contract in Plan 03-01.
2. Split the bridge and shim timeout literals in Plan 03-03.
3. Make EC07's actual coverage match its stated five-code contract.
4. Document bridge text-versus-JSON generic-nonzero divergence.
5. Consider collapsing the four waves into two without reducing runtime coverage.

---

## Consensus Summary

Both reviewers verified claims directly against the live source (not the plan text alone) and agree the plans correctly diagnose the real defects: the bridge's unconditional `": "` suffix on empty stderr in both plain-text ([scripts/agy_bridge.sh:730](https://scripts/agy_bridge.sh:730)) and JSON ([scripts/agy_bridge.sh:727](https://scripts/agy_bridge.sh:727)) forms, the shim's mirrored external-kill bug, `fake-agy.sh`'s `FAKE_AGY_PRINT_KILL9` path currently short-circuiting before stderr emission ([tests/fake-agy.sh:237](https://tests/fake-agy.sh:237) vs `:292`), and the intentional bridge/shim envelope-shape divergence the plans preserve rather than "fix." Neither reviewer found a defect the plans missed.

The two reviews diverge sharply on **risk level and actionability**, and that split is itself the most important finding here: Antigravity read the plans largely as a confirmation pass and returned **LOW** risk with only LOW-severity concerns, all already mitigated in the plan text. Codex read the same plans at a deeper mechanism level and returned **MEDIUM** risk with **2 HIGH-severity findings**, recommending "approve with revisions" rather than a clean pass. Codex's findings carry more weight here — they are mechanism-level (traced against the actual differing bridge/shim message text, not just the presence of a fix) rather than confirmatory.

### Agreed Strengths
- Both reviews confirm every cited defect against the actual source, with matching file:line evidence (no hallucinated citations).
- Both praise Plan 04's stdout/stderr stream-splitting (`_ec_run_split` / split-stream helper) as necessary — the existing `_run` harness (`tests/run-tests.sh:105-113`) merges streams via `2>&1`, which would let an R6 zero-byte-stdout assertion pass vacuously.
- Both confirm the plans correctly preserve intentional bridge-vs-shim wording divergence (generic-nonzero: bridge prefixes `"ERROR: agy exit N:"`, shim relays raw stderr) rather than forcing false parity between the two entry points.
- Both confirm Plan 01's fix to `tests/fake-agy.sh` (making `FAKE_AGY_PRINT_KILL9` honor `FAKE_AGY_STDERR` before its `exit 137`) is required and correctly sequenced before the new EC assertions that depend on it.

### Agreed Concerns
- **Integer-second timeout-boundary precision** (`SECONDS`-based `DURATION` truncates to whole seconds, so a kill in the final sub-second window can misclassify 137-vs-124): flagged by Antigravity as LOW/accepted-ceiling, and implicitly the same fragility class Codex raises (MEDIUM) against Plan 04's textual `DURATION < TIMEOUT` source assertions being weaker evidence than a runtime boundary test. Both reviewers treat this as a known, already-flagged limitation rather than a blocker — but neither considers it fully closed.

### Divergent Views
- **Risk level: LOW (Antigravity) vs. MEDIUM (Codex).** Codex's MEDIUM rating rests on findings Antigravity's pass did not surface at the same depth (see below); this is a real disagreement in review depth, not just a difference in tolerance.
- **NUL-byte / trailing-newline handling (Codex, MEDIUM, not raised by Antigravity):** Plan 03-01's proposed shared `_err_txt="$(cat "$STDERR_FILE")"` cannot preserve NUL bytes (Bash variables can't hold them) and strips trailing newlines — meaning the JSON path's current byte-exact `open(...).read()` behavior changes beyond just removing the dangling separator. Antigravity's suggestion #1 gestures at the newline-stripping half of this but does not flag the NUL-byte impossibility or call it a policy change requiring explicit success-criteria wording.
- **`_EC_TIMEOUT_LITERAL` treated as one shared string across scripts (Codex, HIGH, not raised by Antigravity):** the bridge and shim word the exit-124 timeout message differently (confirmed at `scripts/agy_bridge.sh:738` vs `scripts/gemini_shim.sh:677`), so EC06 as planned cannot pin both scripts to a single literal. This is the review's most concrete, highest-severity, and most directly actionable finding — worth resolving before execution regardless of the other divergences.
- **EC07's aggregate-contract framing (Codex, HIGH, not raised by Antigravity):** the plan's `must_haves` truth claims all five exit codes are independently asserted and never conflated, but exit 2 and 127 coverage is delegated to pre-existing `R8`/`I16`/`RB29` cases rather than asserted fresh — a scope-vs-mechanism mismatch in the plan's own claim, not a code defect.
- **Execution cost / sequencing (Codex, MEDIUM, not raised by Antigravity):** 4 strictly serial waves plus deliberate mutation-and-revert cycles is heavy for the size of the underlying fix; Codex suggests collapsing to 2 plans without losing coverage. This overlaps with the concern the planner itself already flagged (03-02 task 3 / 03-03 task 2's mutation-testing overhead) — external review independently arrived at the same worry from a different angle (cost/proportionality, not test-integrity).
