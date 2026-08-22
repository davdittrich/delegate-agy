---
phase: 4
reviewers: [codex, antigravity]
reviewed_at: "2026-08-21T11:11:02Z"
plans_reviewed: [04-01-PLAN.md, 04-02-PLAN.md]
models:
  codex: "unknown"
  antigravity: "unknown"
model_sources:
  codex: "unknown"
  antigravity: "unknown"
---

# Cross-AI Plan Review — Phase 4

**Note on antigravity's run:** antigravity's first invocation crashed with a CLI-internal
bug (`Error: ContentOffset 46080 exceeds line range size 34033`) while paging the full
review bundle, not a timeout. It was re-run against the same bundle with the 57KB
`04-RESEARCH.md` section excluded (workaround for what looks like a size-triggered
paging bug) and completed successfully. This means antigravity's review is **not**
grounded in 04-RESEARCH.md's verified line numbers, Validation Architecture, or
Security Domain sections — only in the plans, ROADMAP, REQUIREMENTS.md, CONTEXT.md,
and the live repo it read directly. codex's review saw the full bundle including
RESEARCH.md.

## Consensus Summary

Both reviewers verified claims against the live repo (file:line citations from both) and
agree the phase is well-scoped, correctly sequenced (D-05 before D-03), and stays within
Phase 4's boundary. They diverge sharply on Plan 04-01's risk level — codex found two
HIGH-severity problems with the plan's *proof mechanisms* that antigravity's shallower
pass did not surface. Weighting: codex traced the pipe-buffer/SIGPIPE race and the
path-validation semantics down to the mechanism; antigravity confirmed the plan preserves
existing structure and anchors correctly but did not stress-test whether those mechanisms
prove what the plan claims. Treat codex's two HIGH findings on 04-01 as the higher-confidence
read.

### Agreed Strengths
- D-05 (branch-tip content sync) correctly sequenced **before** D-03 (SIGPIPE fix) — both reviewers independently confirmed via `git diff`/`git show` against `fix/agy-bridge-resilience` that the branch tip still carries the unguarded `head -1` pipeline, so syncing after fixing would silently overwrite the fix.
- Single-commit sync of `plugin.json` + both `.md` files is required by `ST6` (`tests/run-tests.sh:1130-1145`, cited by both), which checks all three together — a partial sync would go red at an intermediate commit.
- `_md_extract`'s content-anchored extraction (mirroring `_rb_extract`, `tests/run-tests.sh:1675-1677`) is the right choice over fenced-block ordinals or a new fixture file.
- 04-02's HOME precondition placement (immediately after the existing refuse-root check, before the first `$HOME` expansion) and its explicit-refusal shape (not a `${HOME:-/nonexistent}` fallback) are both correct and well-grounded — both reviewers traced this to the same line citations (`install.sh:37-41,58`; `uninstall.sh:15-19,20`).
- 04-02's python3-guard hoist reuses `_register_tokensave`'s established fail-open shape and correctly preserves the per-file dry-run advisory.
- D-07's decision to cite existing I16/I17/I18 coverage rather than duplicate registry fixtures is respected by both plans.

### Agreed Concerns
- **Stale/shifting line citations (MEDIUM, both reviewers independently on 04-02):** codex and antigravity both flag that I16-I18's `tests/run-tests.sh:3980-4239` citations going into REQUIREMENTS.md will be stale the moment 04-02's own new tests (I19/I20/I20b) are inserted earlier in the file, shifting those ranges. Fix: cite test IDs/headings, not raw line ranges, or resolve final line numbers after all insertions land.
- **Requirement-closure wording risk (MEDIUM/LOW, both):** both reviewers independently caution that closing R8/S2 in REQUIREMENTS.md must not imply this phase re-verified the registry-comparison logic — it deliberately doesn't touch `write_wrapper`. Suggested phrasing (codex): "formally closed in Phase 4 using previously shipped I16/I17/I18 evidence; registry logic unchanged."
- **Unicode-normalization residue is noise (LOW, both):** both flag that the flagged-assumption A2 (registry key differing only by Unicode normalization) is speculative and adds little value in the primary traceability row; keep it in risk notes rather than the main requirement row.

### Divergent Views

**Plan 04-01 overall risk — codex: HIGH vs. antigravity: LOW/APPROVED.** This is the
important disagreement in this review round, driven by two findings codex made and
antigravity's pass did not surface (note: antigravity ran without RESEARCH.md, which may
partly explain the gap, though neither finding depends on RESEARCH.md content — both are
derivable from the plan text and the live repo alone):

1. **HIGH — codex: the SIGPIPE RED test may be non-deterministic.** codex's reasoning: a
   small JSON payload (the plan's "three objects" fixture) can fit entirely inside the
   pipe buffer, letting `python3`'s write complete and the process exit 0 *before* `head -1`
   closes its read end — producing no SIGPIPE at all, and leaving the new regression test
   green against the still-defective `| head -1` block it's supposed to catch. Antigravity's
   review did not evaluate this race condition; it confirmed the anchor-matching mechanism
   for `_md_extract` but not the RED test's reliability. **This is a real, checkable claim
   about pipe-buffer semantics under `set -o pipefail`** — worth confirming against the
   actual planned fixture size before execution, independent of which reviewer is "right."

2. **HIGH — codex: the security rationale overstates the `case` path-validation
   guarantee.** codex's reasoning: the existing (unmodified by this phase) `case
   "$RESOLVED" in */agy-delegate/*/scripts/install.sh)` pattern match only rejects a
   non-matching *shape*; a hostile path such as `/tmp/agy-delegate/x/scripts/install.sh`
   satisfies the same pattern and would still be `bash`'d. Codex's point is specifically
   about the plan's own prose framing ("the security control R8 relies on") — the concern
   is documentation precision (the plan should not claim more than this pre-existing check
   proves), not that this phase introduces a new vulnerability (04-01 doesn't touch this
   validation). Antigravity's review noted the plan "preserves" the security control but
   did not question whether the control's own guarantee is being correctly described.
   Since D-03/D-04 don't modify this validation logic, this is a **plan-wording fix**
   (soften the security claim to what the check actually proves), not a blocker on the
   code change itself — but it should not ship into the plan's threat-model language
   unchanged.

3. **MEDIUM — codex only: D-05's final verification is self-contradicting.** Once Tasks
   2-3 intentionally modify the synced `.md` files, the plan's stated final check (`git
   diff` empty across all three synced files) can never pass. codex recommends splitting
   the check: `plugin.json` byte-identical to branch tip; each `.md` file differs from the
   branch tip *only* by the `head -1` removal. Antigravity did not flag this — worth
   confirming directly against 04-01's task text before execution regardless.

4. **MEDIUM — codex only: Task 2's `_md_extract` occurrence-count assertion is checked
   too early** (requires count `>=3` before Task 3's insertion makes that count true).
   Mechanical off-by-task-order issue, easy to verify by reading the task sequence.

**Everything else in codex's 04-01 findings (over-specification, "parity tested against
the wrong artifact") and 04-02 findings (brittle exact-occurrence-count assertions, a
`| tail` swallowing exit status) had no counter-signal from antigravity but also no
direct rebuttal — they read as reasonable plan-hardening suggestions, not confirmed
defects, and are lower-confidence than the four items above.**

---

## Codex Review

{see /tmp/gsd-review-Hdibfh/gsd-review-codex.md at time of writing — full text below}

### Plan 04-01 — Sync metadata/docs and fix fallback pipelines

**Summary:** The dependency ordering and "fix both docs" scope are correct, but the plan is not execution-ready. Its TDD RED gate is race-dependent and likely nondeterministic, its final branch-diff assertion contradicts the intentional fix, and its security model overstates what the pathname `case` actually guarantees.

**Strengths:**
- The D-05-before-D-03 ordering is correct — the branch-tip fallback (`fix/agy-bridge-resilience:.claude/commands/agy-setup.md:54-56`, mirrored `:45-47`) still contains the vulnerable `python3 ... | head -1` pipeline; syncing after fixing would overwrite the fix.
- Synchronizing all three version-bearing files together is appropriate — `ST6` (`tests/run-tests.sh:1137-1140`) checks both command docs against the manifest version, so a partial sync would fail.
- Content-anchored extraction (reusing `_rb_extract`'s pattern, `tests/run-tests.sh:1675-1677`) is preferable to fenced-block ordinals.
- Both setup and uninstall must be fixed — their branch-tip fallback blocks share the same defect.

**Concerns:**
- **HIGH** — the claimed security control does not prevent registry-controlled execution: the fallback accepts any regular file whose pathname matches the shape, not its provenance (`fix/agy-bridge-resilience:.claude/commands/agy-setup.md:54-62`).
- **HIGH** — the proposed RED observation is nondeterministic: a small JSON fixture may fit the pipe buffer, letting `python3` exit cleanly with no SIGPIPE, leaving the new test green against the defective block.
- **MEDIUM** — the final D-05 verification (`git diff` empty across 3 files) is internally impossible once Tasks 2-3 intentionally alter 2 of those files.
- **MEDIUM** — Task 2's `_md_extract >= 3` acceptance condition is premature (that count doesn't exist until Task 3).
- **MEDIUM** — "single-match parity" is checked against marker-script output, not the actual resolution output.
- **LOW** — the plan is substantially over-specified for a two-expression edit (4 commits, ~62k estimated tokens).

**Suggestions:**
- Replace the race-based SIGPIPE RED test with a deterministic producer exceeding the pipe buffer, or a controlled slow producer; assert the old block exits nonzero under `pipefail` before the fix.
- Reframe the docs validation honestly as a coarse path-shape/regular-file check, not proof of trusted provenance.
- Split D-05 verification: `plugin.json` byte-identical; each doc differs from branch tip only by the `head -1` removal.
- Move the `_md_extract >= 3` assertion to Task 3; use `>= 2` after Task 2.
- Prefer one shared parameterized test over near-duplicate I21/I21b logic.

**Risk Assessment: HIGH.** The implementation change is small, but the plan's central RED proof can fail nondeterministically and its security conclusion is not supported by the actual pathname validation.

### Plan 04-02 — HOME preconditions, optional-python guard, and requirement closure

**Summary:** Much closer to executable. Fixes are correctly placed and reuse established source patterns. Remaining problems are plan-maintenance issues: stale line citations, brittle source-count assertions, and documentation closure that should avoid claiming new verification of deliberately unmodified logic.

**Strengths:**
- HOME guard correctly placed immediately after the refuse-root block (`install.sh:37-41`, first HOME-dependent use at `:58`; `uninstall.sh:15-19`, `BIN_DIR` at `:20`).
- Explicit refusal is correct — substituting `/nonexistent` would not provide a usable destination; the generated wrapper's own `${HOME:-/nonexistent}` (`install.sh:156`) serves a different fail-silent runtime purpose and shouldn't be copied here.
- python3 guard correctly targeted at the only remaining unguarded optional-python path, alongside `_agy_detect`/`_register_tokensave` (`install.sh:260-283`).
- Hoisting the dependency check while preserving the per-file dry-run advisory is a good resolution of RESEARCH.md's open question.
- I19 correctly composes the existing alias-patch and python-absent harness patterns.
- D-07 respected — I16-I18 (`tests/run-tests.sh:3980-4239`) already exercise malformed/adjacent/compact/quoted-path shapes.

**Concerns:**
- **MEDIUM** — I19/I20/I20b insertion shifts I16-I18's current line ranges; citing the old ranges into REQUIREMENTS.md as final evidence would be immediately stale.
- **MEDIUM** — exact-occurrence-count assertions (`_alias_patch_py3_ok` x3, `command -v python3` x3) test spelling/count, not behavior — a harmless future comment would fail the gate.
- **MEDIUM** — requirement-closure prose risks conflating existing shipped evidence with this phase's own (unrelated) work; Tasks 1-2 deliberately don't touch `write_wrapper`.
- **LOW** — the Unicode-normalization residue (flagged assumption A2) is speculative and adds noise to the primary traceability row.
- **LOW** — direct HOME-verification commands piped through `tail` lose the installer's own exit status.
- **LOW** — five commits and a full-suite run after each for ~7 production lines is heavy ceremony.

**Suggestions:**
- Cite stable test IDs/headings instead of volatile line ranges, or resolve numbers after all insertions land.
- Replace occurrence-count gates with structural/behavioral checks (guard precedes loop; loop skips before backup+python; I19 proves one warning + no mutation).
- REQUIREMENTS.md closure language: "formally closed in Phase 4 using previously shipped I16/I17/I18 evidence; registry logic unchanged."
- Keep the normalization residue in risk notes, not the primary traceability row.
- Capture direct-test exit status without a trailing pipeline: `output="$(env -i ... 2>&1)"; rc=$?`.
- Consider one parameterized test for I20/I20b with distinct failure labels.

**Risk Assessment: MEDIUM-LOW.** Production changes are simple, correctly located, and well covered. Main risks are brittle verification metadata and stale citations, not functional defects.

**Overall Assessment:** Phase goals are achievable with these plans, but 04-01 should be revised before execution — its nondeterministic RED gate and unsupported security claim are substantive. 04-02 is sound after tightening evidence references and removing brittle count-based assertions.

---

## Antigravity Review

*Ran against a trimmed bundle (RESEARCH.md excluded) after an initial crash — see note above.*

### Plan 04-01 Review

**Summary:** Addresses `delegate-agy-k0f` (sync three post-revert files from `fix/agy-bridge-resilience`'s tip) and `delegate-agy-4vy` (eliminate `| head -1` to prevent SIGPIPE exit 141 under `set -euo pipefail`). Establishes `_md_extract` and adds `I21`/`I21b` regression tests via a strict task-level TDD workflow. Well-sequenced, tightly scoped, accurately accounts for repo-specific couplings.

**Strengths:**
- Sequencing discipline (D-05 before D-03) explicitly recognized and correct.
- Atomic manifest/doc sync for `ST6` (version bump `1.6.1`→`1.6.2` across all three files in one commit) prevents intermediate test breakage.
- Root-cause elimination (removing `head -1` entirely) over symptom suppression, per D-03.
- `_md_extract`'s content-anchored boundary matching verified to match exactly lines 54-62 in `agy-setup.md` and 45-53 in `agy-uninstall.md` on the branch tip.
- Plan explicitly prohibits modifying the `case` path-validation pattern.

**Concerns:**
- **LOW** — the exact Python one-liner is left to executor discretion; a naive `[0]` index on an empty list/generator raises `IndexError` (rc=1) before reaching the validating `case`, on a zero-match input.

**Suggestions:**
- Standardize on `next((x.get("installPath","") for x in json.load(sys.stdin) if x.get("id","").startswith("agy-delegate@")), "")` for clean empty-input behavior.

**Risk Assessment: LOW.** Changes are surgical, bounded to doc examples and test fixtures, verified by dedicated regression tests, no core runtime modification.

### Plan 04-02 Review

**Summary:** Closes `delegate-agy-4bp` (explicit `$HOME` precondition in both scripts) and `delegate-agy-4xn` (hoisted python3 check before the rc-alias loop); closes R8/S2 in REQUIREMENTS.md on existing I16-I18 coverage. Enforces fail-open behavior for optional features, prevents uninformative `set -u` aborts.

**Strengths:**
- Precondition placement verified: guarantees no `$HOME` expansion (`install.sh:58`, `uninstall.sh:20`) can trigger an unhandled abort under `set -u`.
- Anti-tampering: explicitly forbids a default-path fallback per D-06/T-04-05, avoiding a plantable/misdirected path on shared systems.
- Fail-open architecture: hoisted python3 check lets `install.sh` complete with wrappers intact on a missing binary.
- Dry-run advisory preserved via the hoisted flag.
- D-07 respected — cites I16-I18 (`tests/run-tests.sh:3980-4239`) rather than duplicating, while documenting the Unicode-normalization residue (A2).

**Concerns:**
- **LOW** — line-number drift: the plan correctly recalibrates the ticket's stale citations to the current working tree.
- **LOW** — I19's curated whitelist `PATH` must retain standard utilities (`sed`, `grep`, `mkdir`, `readlink`, `dirname`, `date`) so the test only fails on python3 absence, not a missing coreutil.

**Suggestions:**
- Confirm Task 2's warning string matches `_register_tokensave`'s exact format for diagnostic consistency.

**Risk Assessment: LOW.** Both changes are minimal, defensive, single-site, fail-open; neither touches the wrapper heredoc or runtime binary routing.

### Cross-Cutting & Architectural Analysis
- Wave 1 (04-01) cleanly precedes Wave 2 (04-02); both touch `tests/run-tests.sh`, so sequential execution avoids merge collisions.
- All five Phase 4 success criteria mapped to specific tests: criteria 1-3 → I16/I17/I18 (existing); criterion 4 → 04-02's I19; criterion 5 → 04-01's I21/I21b.
- Scope integrity confirmed: `scripts/agy_bridge.sh`/`scripts/gemini_shim.sh` untouched; stays within `04-CONTEXT.md`'s boundary.

### Final Verdict
Both plans **APPROVED** — "mathematically precise, well-anchored in the existing codebase, follow rigorous TDD mechanics, and completely satisfy the requirements of Phase 4."

---
