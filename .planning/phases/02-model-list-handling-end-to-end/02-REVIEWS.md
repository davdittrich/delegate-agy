---
phase: 2
reviewers: [codex, antigravity]
reviewed_at: 2026-08-20T11:34:59Z
plans_reviewed: [02-01-PLAN.md, 02-02-PLAN.md]
models:
  codex: "unknown"
  antigravity: "unknown"
model_sources:
  codex: "unknown"
  antigravity: "unknown"
---

# Cross-AI Plan Review — Phase 2

## Consensus Summary

Both reviewers verified the plans' claims against the actual source in `.worktrees/agy-1.6.2` (not the plan text alone) and independently reached the same overall verdict: the D-01..D-06 mechanism is sound, correctly reuses existing branches rather than inventing new ones, and the criterion-3 stderr-relay fold-in added to Plan 02-01 during this planning session is mechanically correct and internally consistent within that plan.

### Agreed Strengths
- The cache write-gate lands at the correct boundary (before persistence, not after), reusing the exact check already shipped at `agy_bridge.sh:515`.
- The D-04 stale-cache fallback reuses the existing fetch-failure read path — no new retrieval mechanism.
- Leaving `_agy_models` untouched on the no-cache-degraded path is necessary and correct — clearing it would route into the generic failure exit before the degraded-list message is ever reached, turning R8 red.
- The relocated stderr relay (Plan 02-01's fold-in) is correct: `$_agy_err` is already captured on every fetch attempt; moving the relay outside the `if/elif/else` surfaces it on the degraded-but-successful path without duplicating the line.
- The shim's silence (D-05) is architecturally guaranteed, not just a convention — `load_models()` redirects agy's stderr straight to `2>/dev/null` and never captures it, so the new fake-agy.sh stderr addition structurally cannot leak into SH14.
- D-06's `AGY_FIXTURES_DIR` approach correctly exercises the real fetch path rather than short-circuiting at the cache read.

### Agreed Concerns
- **[Fixed during this review round] Plan 02-02 was stale relative to Plan 02-01's revision.** Both reviewers independently caught the same bug: after Plan 02-01 was hand-edited to fold in the criterion-3 stderr fix, Plan 02-02's `must_haves.assumptions` still said "FLAGGED, NOT FOLDED IN ... raise as a follow-up bd issue at phase close," and its verification/success-criteria sections asserted `tests/fake-agy.sh` stays untouched "across the whole phase" — both now false since 02-01 modifies that file. **Corrected in `02-02-PLAN.md` immediately after this review returned** (assumptions reworded to point at 02-01's resolution, verification item 7 scoped to this plan's own diff, output section's stale bd-issue instruction removed).
- Neither reviewer flagged the S4 concurrency gap or the empty-success edge as new — both were already recorded as flagged assumptions in the plans before this review.

### Divergent Views

**The `pipefail`/SIGPIPE safety of the chosen two-element `printf | grep -q '^gemini-'` gate form (Alternatives Considered §A in both plans) — reviewers disagree, and this is unresolved.**

- **Antigravity (Strengths §1):** calls this form "pipefail-safe," reasoning that buffering the normalized list into a variable (`_agy_ids`/`ids`) before the `grep -q` check avoids the 3-element-pipeline hazard the plan's own Alternatives-A text describes (a `cut` in the middle dying of SIGPIPE when `grep -q` closes early).
- **Codex (Concern, MEDIUM, both plans):** argues the 2-element form is *not* fully safe — `printf` itself is the pipeline's *producer* in this form, and under `set -o pipefail`, if `grep -q` finds an early match in a sufficiently large `_agy_ids`/`ids` string and closes its read end before `printf` finishes writing, `printf` receives SIGPIPE and exits 141; since `grep`'s own exit is 0, bash's pipefail rule ("rightmost command with non-zero status") reports the pipeline's status as 141 — a **false-degraded verdict on a genuinely good list**, the exact failure mode the plan exists to prevent.

Working through bash's actual pipefail semantics independently: Codex's mechanism is correct as stated — a large `_agy_ids` with an early `^gemini-` match can produce SIGPIPE-on-printf with grep exiting 0, and pipefail's "rightmost non-zero" rule does report the pipeline as failed in that case. This is a real, if narrow, gap. Two things bound its practical severity, both worth weighing before deciding what to do about it:
1. **It is inherited, not introduced.** The identical 2-element shape already exists, shipped, at `agy_bridge.sh:515` (the pre-existing criterion-3 check this phase's new write-gate deliberately mirrors — "the same test the file already performs at :515," per the plan's own text). Fixing it in the new gate without also fixing `:515` would make the write-time gate and the use-time check inconsistent in robustness, which the plans' own prohibitions explicitly forbid ("the write-time gate and the use-time check apply the same test"). Fixing both means touching code D-01/D-02 mark closed.
2. **It requires a specific, unlikely trigger shape.** Real `agy models` output is ~14 short lines (Phase 1.5's captured fixture) — far below the 64 KiB pipe buffer where this can even begin to manifest. It would need either an adversarially huge reply or a reply that happens to place a matching line early *and* is large enough that `printf`'s write is still in flight when `grep -q` closes — a narrow, timing-dependent combination.

**This is a genuine open question for you, not something I'm deciding unilaterally:** leave the gate as specified (matches existing shipped pattern, in-scope discipline, real-world risk is very low), fold a proper fix into scope now (e.g. reading into an array or using process substitution instead of a pipe — but this would need to touch both the new gate *and* the existing `:515`/shim-equivalent check to keep them consistent, which reopens code D-01/D-02 currently call closed), or file it as a follow-up bd issue without touching code this phase.

## Full Reviews

## Codex Review

# Cross-AI Plan Review

## Summary

The implementation design is fundamentally sound and closely follows the existing fetch/cache architecture. Both plans correctly preserve the 60-minute TTL, atomic rename pattern, strict model matching, bare-`HOME` safeguards, and intentional shim silence. Plan 02-01’s revised stderr-relay addition is mechanically correct: the bridge already captures stderr for every fetch but currently relays it only inside the failure branch, so moving the single relay after the branch surfaces diagnostics on degraded-success paths without duplication. However, the revised scope was not propagated into Plan 02-02: that plan still calls the stderr gap unresolved, requires a follow-up issue, and contains impossible whole-phase diff assertions because Plan 02-01 now modifies `tests/fake-agy.sh`. There is also a correctness flaw in the plans’ `pipefail` reasoning: a two-stage `printf | grep -q` pipeline can still return 141 when output is sufficiently large.

## Plan 02-01 — Bridge

### Strengths

- The proposed cache gate addresses the actual defect at the correct boundary. The bridge currently writes every successful response unconditionally at `scripts/agy_bridge.sh:475-484`, while only later rejecting gemini-less normalized content at `scripts/agy_bridge.sh:502-518`. Moving validation ahead of persistence prevents data the bridge rejects from becoming authoritative to the shim.

- The stale-cache fallback reuses an established path rather than creating a parallel retrieval mechanism. Clearing `_agy_models` only when a cache exists naturally reaches the existing `cat "$CACHE_FILE"` fallback at `scripts/agy_bridge.sh:502-504`.

- Leaving `_agy_models` intact when no cache exists is necessary to preserve the specific degraded-list error. Clearing it would trigger the generic empty-list failure at `scripts/agy_bridge.sh:506` before reaching the diagnostic at `scripts/agy_bridge.sh:515-517`.

- The revised stderr-relay mechanism is correct. Stderr is captured on every attempted fetch at `scripts/agy_bridge.sh:474-476`, but the relay currently sits inside the non-zero-exit branch at `scripts/agy_bridge.sh:485-499`. Relocating that one statement after the branch will expose stderr for successful-but-degraded responses while retaining the existing failure behavior.

- The new fake diagnostic is attached to the appropriate stimulus. The garbage branch currently returns non-gemini stdout and exits zero at `tests/fake-agy.sh:163-167`; adding `FAKE-AGY-DEGRADED` there makes the previously invisible success-path stderr directly testable without changing failure or hang behavior.

- The normalization test uses a real fetch path. The fixture override is data-only and column-agnostic at `tests/fake-agy.sh:113-145`, whereas the existing R3c test only exercises cache-read normalization at `tests/run-tests.sh:437-448`.

- Existing safeguards are explicitly preserved: `${HOME:-/nonexistent}` at `scripts/agy_bridge.sh:468`, best-effort atomic replacement at `scripts/agy_bridge.sh:481-484`, strict anchored auto-selection at `scripts/agy_bridge.sh:524-525`, and exact explicit-model validation at `scripts/agy_bridge.sh:529`.

### Concerns

- **MEDIUM — The `pipefail` justification is incomplete and can produce the exact false-degraded verdict the plan says it prevents.** Plan 02-01 argues that assigning `cut -f1` first and then using `printf | grep -q` avoids SIGPIPE. Under `set -o pipefail`, however, `printf` itself can receive SIGPIPE when `grep -q` exits after an early match. The script enables `pipefail`, and the existing use-time check already uses this vulnerable form at `scripts/agy_bridge.sh:515`. Since the plan’s threat boundary explicitly treats response size as uncontrolled, a sufficiently large valid list can make the write gate return non-zero.

- **MEDIUM — Unconditional stderr relay broadens behavior beyond the stated degraded-list case.** Moving the relay outside the branch means stderr from every successful valid `agy models` response will now be emitted, not only stderr from degraded responses. The source captures stderr universally at `scripts/agy_bridge.sh:474-476`, so this follows mechanically. T-02-04 acknowledges the wider trigger, but R8/R9b only test degraded responses; there is no regression asserting the normal successful bridge path remains quiet when `agy models` emits harmless headers or notices.

- **LOW — The empty-success truth is not behaviorally tested.** The planned R9 stimulus is non-empty garbage from `tests/fake-agy.sh:164-166`. It does not prove the separate zero-byte-success case named in the plan’s must-haves. The proposed mechanism should preserve a stale cache for an empty response, but the no-cache outcome would be the generic error at `scripts/agy_bridge.sh:506`, not the degraded-list message at `scripts/agy_bridge.sh:515-517`.

- **LOW — The concurrency claim remains untested.** Atomic `mv` prevents partial-file reads, and per-process `.$ $` temporary paths prevent ordinary writer collision at `scripts/agy_bridge.sh:482-483`. Still, no test overlaps bridge and shim writers. Accepting this is reasonable for the stated S4 acceptance, but the phase should describe the guarantee narrowly as atomic complete-file replacement, not comprehensive coordination safety.

### Suggestions

- Replace `printf '%s\n' "$_agy_ids" | grep -q '^gemini-'` with a no-early-close form, such as `grep '^gemini-' >/dev/null` over the complete stream, or a pipeline-free input mechanism. Apply the same safe predicate at the use-time check so the two sites remain genuinely equivalent.

- Add a successful valid-fetch case where fake `agy models` emits stderr. Decide explicitly whether that stderr should be relayed. If only degraded/failure diagnostics should surface, condition the relocated relay on fetch failure or failed normalized validation rather than making it fully unconditional.

- Add an explicit empty-success test covering both absent and stale-cache states.

- Retain T-02-04, Alternatives §D, the one-site relay count, and the R8/R9b `FAKE-AGY-DEGRADED` assertions; those revised sections are otherwise internally consistent.

## Plan 02-02 — Shim

### Strengths

- It correctly addresses the second writer. The shim currently writes every non-empty successful reply at `scripts/gemini_shim.sh:412-421`; without this plan, the bridge gate alone cannot satisfy S4.

- The fallback mechanism is valid. Clearing `raw` when a degraded fetch finds an existing cache causes the existing line at `scripts/gemini_shim.sh:427` to load the cache, after which `cut -f1` at line 428 normalizes it.

- Shim silence is preserved at the correct layer. The live fetch already discards agy stderr at `scripts/gemini_shim.sh:412`, and the fallback rationale explicitly avoids warnings at `scripts/gemini_shim.sh:424-426`. The added fake stderr literal therefore cannot leak through SH14.

- No-cache pass-through is accurately traced. A gemini-less list cannot resolve a live ID at `scripts/gemini_shim.sh:438` or a class at line 447, and the warning gate at line 459 remains false, so the original model name is emitted unchanged at line 462.

- SH15b’s proposed argv inspection is stronger than checking the shim’s stdout. The resolved model is passed to agy rather than printed by the shim, matching the existing SH10 mechanism at `tests/run-tests.sh:1078-1097`.

### Concerns

- **HIGH — Plan 02-02 is stale relative to revised Plan 02-01.** It says the bridge stderr gap is “NOT FOLDED IN” and instructs phase close to file a follow-up at `.planning/phases/02-model-list-handling-end-to-end/02-02-PLAN.md:43-45` and `:197-200`. Revised Plan 02-01 explicitly makes the relay a required truth and closes that gap at `02-01-PLAN.md:23-27`, with the actual source mechanism supported by `scripts/agy_bridge.sh:474-499`. Executing both plans literally would create a false follow-up issue and record contradictory phase conclusions.

- **HIGH — One verification condition is impossible after revised Plan 02-01.** Plan 02-02 requires `git diff -- tests/fake-agy.sh ...` to be empty “across the whole phase” at `02-02-PLAN.md:183-185`, while Plan 02-01 explicitly adds `FAKE-AGY-DEGRADED` to that file at `02-01-PLAN.md:103-105` and includes it in Task 2 ownership at lines 171-176. The phase-wide success statement at `02-02-PLAN.md:194` similarly understates the final file set.

- **MEDIUM — The same `printf | grep -q` SIGPIPE issue carries into the shim gate.** The planned normalized predicate inherits the bridge’s unsafe reasoning. Under `set -o pipefail`, an upstream `printf` can fail after `grep -q` closes early. Because `load_models()` must never return non-zero (`scripts/gemini_shim.sh:401-403`), this deserves explicit handling even if the condition syntactically contains the status.

- **LOW — SH15 does not test simultaneous writers.** Behavioral coverage proves that each writer rejects degraded data independently, but not that a bridge fetch and shim fetch racing against the same cache always leave a complete valid file. Atomic rename makes this likely safe, but the test coverage should not be described as proving concurrency.

### Suggestions

- Remove the stale second assumption about criterion 3 and all instructions to file a follow-up. Carry forward only the concurrency assumption.

- Change verification item 7 to expect `tests/fake-agy.sh` to differ across the whole phase, while remaining untouched by Plan 02-02 itself.

- Correct the final phase inventory to four modified files: `scripts/agy_bridge.sh`, `scripts/gemini_shim.sh`, `tests/fake-agy.sh`, and `tests/run-tests.sh`.

- Use the same SIGPIPE-safe degraded-list predicate in both scripts and add a large-response regression if response size is truly part of the stated trust boundary.

## Risk Assessment

**Overall risk: MEDIUM.**

The production approach should achieve S1’s extra-column handling and S4’s primary cache-poisoning goal. The fallback routes, strict model selection, TTL behavior, and revised stderr relocation all trace correctly through the current source. Risk remains medium because Plan 02-02 is materially inconsistent with the revised Plan 02-01 and contains an impossible phase verification, while the chosen `pipefail` mitigation is not actually safe for arbitrarily large output. Correcting those items before execution should reduce implementation risk to low.

---

## Antigravity Review

# Implementation Plan Review: Phase 2 (Model-list handling, end to end)

## 1. Summary

The two plans (`02-01-PLAN.md` and `02-02-PLAN.md`) establish a well-scoped, surgical implementation for closing requirements S1 and S4 (ticket `delegate-agy-8ph`). Plan 02-01 handles the `agy_bridge.sh` tracer implementation, stale-cache fallback, multi-column normalization, and the folded-in unconditional stderr relay. Plan 02-02 mirrors the cache-write gate and fallback into `gemini_shim.sh`'s `load_models()` while strictly maintaining the shim's degrade-silently contract. Both plans adhere closely to architectural decisions D-01 through D-06, preserving existing atomic write semantics (`.tmp.$$` -> `mv`) and avoiding unnecessary shared library abstractions across standalone scripts. The mechanisms have been verified against the codebase in `.worktrees/agy-1.6.2`.

---

## 2. Strengths

- **Pipefail-Safe Normalization Variable (Alternatives Considered §A)**:
  In `scripts/agy_bridge.sh:475-484` and `scripts/gemini_shim.sh:413-423`, both plans buffer `_agy_ids` / `ids` via `printf '%s\n' "$_agy_models" | cut -f1` into a variable before running `grep -q '^gemini-'`. This avoids a 3-element pipeline under `set -euo pipefail` (`scripts/agy_bridge.sh:8`, `scripts/gemini_shim.sh:18`) where `grep -q` exiting on early match could cause an unbuffered `cut` to receive `SIGPIPE` and yield status 141.
- **Relocated Stderr Relay Eliminates Duplicate Logic (Plan 02-01, Alternatives §D)**:
  In `scripts/agy_bridge.sh:474-500`, relocating the existing line 498 (`[[ -s "$_agy_err" ]] && sed 's/^/       agy: /' "$_agy_err" >&2`) after the entire `if/elif/else` construct ensures that diagnostic stderr is captured and relayed across both fetch-failure and degraded-success paths without duplicating the `sed` invocation across 3 separate branches.
- **Consistent Stale-Cache Fallback Architecture (D-04)**:
  Both entry points reuse their existing stale-cache read paths (`scripts/agy_bridge.sh:504` via `_agy_models=""` and `scripts/gemini_shim.sh:427` via `raw=""`) when a degraded reply is received. Neither modifies the cache file on fallback, ensuring the 60-minute TTL (`find -mmin +60` at `agy_bridge.sh:470`, `gemini_shim.sh:406`) expires naturally without refreshing the file's mtime.
- **Strict Adherence to Entry-Point Contracts (D-05, T-02-08)**:
  The bridge provides an operator-visible warning (`WARNING: 'agy models' returned a list with no 'gemini-' ids...`) on stale fallback, while the shim in `scripts/gemini_shim.sh:404-430` remains completely silent on fallback, preventing spurious log noise for external callers like Metaswarm and Claude Octopus shadowing `gemini` on PATH.
- **Clean Fixture Isolation for Multi-Column Testing (D-06, CC04a)**:
  Task 3 in both plans uses `AGY_FIXTURES_DIR` to supply synthetic 3-column fixtures dynamically in temporary directories rather than polluting `tests/fixtures/agy-models.tsv` (which is reserved exclusively for captured live-probe outputs per `tests/fake-agy.sh:113-145`).

---

## 3. Concerns

- **[LOW] Stale Assumption & Instructions Carried Over in Plan 02-02 (`02-02-PLAN.md:655, 810`)**:
  - *Mechanism*: When Plan 02-01 was revised to fold in the previously deferred criterion-3 stderr relay fix (relocating `scripts/agy_bridge.sh:498`), Plan 02-01 updated its `must_haves.truths` and `<output>` instructions accordingly (`02-01-PLAN.md:400, 607`). However, Plan 02-02 still contains `must_haves.assumptions` line 655 (`"FLAGGED, NOT FOLDED IN — carried forward from 02-01: criterion 3's shown agy's own stderr half is unsatisfied..."`) and `<output>` line 810 instructing the agent to file a `bd` issue at phase close.
  - *Impact*: Minor documentation inconsistency between the two plan files; could lead the agent executing Wave 2 to create a redundant `bd` issue for an already-closed gap.
- **[LOW] Relative Ordering of Stderr Diagnostics on Degraded Exit (`scripts/agy_bridge.sh:500-519`)**:
  - *Mechanism*: In `scripts/agy_bridge.sh`, relocating `sed 's/^/       agy: /' "$_agy_err" >&2` to line 500 means that on a degraded fetch with no cache on disk, agy's captured stderr (`agy: FAKE-AGY-DEGRADED: ...`) is emitted *before* the bridge's own `ERROR: agy model list contains no 'gemini-' ids...` (emitted at lines 516-518). On fetch failure (`_agy_rc != 0`), the bridge's `ERROR: 'agy models' exited...` is emitted first (at line 496), followed by the relayed stderr.
  - *Impact*: In tests (`tests/run-tests.sh:501` / `R8`), `_run` captures merged stdout and stderr, so substring matching passes regardless. In terminal output, the sequence is slightly inverted between failure modes, but both diagnostics are clearly visible on stderr.

---

## 4. Suggestions

- **Update Plan 02-02 Metadata**:
  Remove the stale criterion-3 assumption from `02-02-PLAN.md:655` and the corresponding instruction in `02-02-PLAN.md:810` so Wave 2 execution aligns with the finalized Plan 02-01 scope.
- **Explicit Variable Scoping in `gemini_shim.sh:load_models()`**:
  Ensure `local ids=""` is explicitly declared on line 405 alongside `local raw=""` in `scripts/gemini_shim.sh` to maintain strict local scoping under Bash functions.

---

## 5. Risk Assessment

**Overall Risk Level: LOW**

**Justification:**
- The changes are tightly localized to the models fetch and cache-write branches in `scripts/agy_bridge.sh:475-500` and `scripts/gemini_shim.sh:412-430`.
- All changes preserve existing failure boundaries: `load_models()` continues to guarantee `return 0` with zero disruption to PATH callers (`scripts/gemini_shim.sh:429`), atomic tmp-file rename (`$$`) is preserved, and the test suite (`tests/run-tests.sh`) has comprehensive pre-existing regression gates (`R1-R8`, `RB01-RB27`, `SH7-SH14`).

---
