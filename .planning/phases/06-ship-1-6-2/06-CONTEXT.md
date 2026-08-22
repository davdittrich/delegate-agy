# Phase 6: Ship 1.6.2 - Context

**Gathered:** 2026-08-21
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase adds no new capability. It is the release gate: every follow-up 1.6.2 work surfaced (`bd list --status open`, currently 8 tickets) gets fixed or closed with a recorded reason, `master`'s files (not `git log`) are confirmed to actually carry the fixes, a fresh `scripts/install.sh` run against merged `master` is proven to produce working launchers with both test suites passing, and release notes name each closed defect plus the mandatory-reinstall notice. The actual `git tag`/publish step is out of this phase's scope — that's the standing GSD milestone `ship` step (`.planning/config.json`'s `git.create_tag: true`), which runs after this phase's plan is executed and verified.

**Scouted, not hypothesized:**
- `fix/agy-bridge-resilience` **is** an ancestor of `master` (`git merge-base --is-ancestor` confirmed) — the `a001d0e` content revert is genuinely undone, matching PROJECT.md's own claim. `git diff master fix/agy-bridge-resilience --stat` shows master strictly ahead (has all the newer `.planning/` docs the fix branch predates; the five shared script/doc files carry small forward diffs from Phases 3-5's own work, not a regression).
- No CI exists for this repo (pure bash, no package manifest, `gh release list` is empty — no prior GitHub Release has ever been cut for this project).
- "Both suites" (ROADMAP's criterion 3 note) resolves mechanically to two files: `tests/run-tests.sh` (the ~89-test harness, which already contains the installer's `I`-prefixed cases) and `tests/hooks/run-hook-tests.sh` (the 28-test hook suite) — not a separate, undiscovered installer suite.
- `README.md` already carries a `## Changelog` section with `### 1.6.2` / `### 1.6.1` / `### 1.6.0` headers populated by prior phases — the established release-notes mechanism for this project.

**In scope:**
- Disposition of all 8 currently-open tickets (see Decisions below) — six real fixes, two investigation-closures.
- Extending README's existing `### 1.6.2` Changelog entry with the newly-closed defects and the mandatory-reinstall notice.
- A manual, documented fresh-install verification pass (clone to scratch dir, run `install.sh`, run both suites, confirm both launchers exec) recorded in this phase's verification artifact.
- Closing `delegate-agy-rod` (Phase 5's epic, 5/5 tasks done, eligible to close) as routine bd hygiene.

**Out of scope:**
- Cutting the actual `v1.6.2` git tag or publishing a GitHub Release/pushing to the plugin marketplace — that's the milestone-level `/gsd-ship` step, not this phase's plan.
- Any new CI/automation infrastructure for the fresh-install check — explicitly declined (see D-08).
- Re-litigating `tests/contract-check.sh`'s exclusion from the release gate — already decided (`03-CONTEXT.md`/ROADMAP note: an agy outage must never block a tag).

</domain>

<decisions>
## Implementation Decisions

### Overall ticket-disposition policy

- **D-01:** Fix or investigation-close all 8 currently-open tickets before Phase 6's gate is satisfied — defer none, including `delegate-agy-sup`'s intermittent flake. **User's explicit choice — overrides "defer sup as pre-existing."** This is a direct application of PROJECT.md's own recorded rule ("follow-ups discovered during work block the release it belongs to") rather than a new policy invented for this phase. — **Reversibility:** reversible — a disposition choice, not a code change in itself.

### delegate-agy-xfa and delegate-agy-i43 — close as resolved-by-investigation

- **D-02:** Close `delegate-agy-xfa` (P1 — GEMINI.md cross-project resolution / per-run policy isolation) as resolved, no code change. Its own ledger already shows `gemini-md-binds=verified` against real agy 1.1.13 (2026-08-20): the bridge's `--sandbox --add-dir WORK_DIR` invocation declined a forbidden tool cleanly, the locally-computed checksum never leaked into the reply, and the decoy `GEMINI.md`'s marker never appeared. Record the closure and the one-run caveat (one prompt shape, one model, one agy version) in PROJECT.md. — **Reversibility:** reversible — reopen if a future incident contradicts the verified isolation.
- **D-03:** Close `delegate-agy-i43` (P2 bug — real agy died on SIGTERM alone, rc=124, contradicting the "-k escalation is load-bearing" assumption) as resolved, no code change. **Do not remove the `-k` SIGKILL escalation** — it stays as defense-in-depth for other agy versions or a wedged descendant process; the single contradicting result is recorded as a noted discrepancy in PROJECT.md's Key Decisions table, not acted on. **User's explicit choice — overrides "reopen i43 as a retest follow-up."** — **Reversibility:** reversible — a future incident can reopen the question; the `-k` mechanism itself is untouched either way.

### delegate-agy-ltf and delegate-agy-u1z — fix, mechanism locked

- **D-04:** Fix `delegate-agy-ltf` (P2 bug — `gemini_shim.sh`'s unknown-long-flag branch silently consumes and drops the next token, including the prompt itself, whenever that token doesn't itself look like a flag) exactly as the ticket already specifies: require `--flag=value` form for unrecognized long flags — never consume the next token as that flag's value — except for an explicit allowlist of flags already known to take a separate value. **User's explicit choice — overrides "let the planner redesign."** — **Reversibility:** reversible.
- **D-05:** Fix `delegate-agy-u1z` (P2 — the write-gate/fallback block is deliberately duplicated, not sourced, across `agy_bridge.sh` and `gemini_shim.sh`, so the twin sites can silently diverge) exactly as specified: add a `grep -cF` structural-equality check across both files' twin `grep -qxF` sites, mirroring the herestring-count assertion pattern Phase 2 (`02-01-PLAN.md`/`02-02-PLAN.md`) already established for a different duplicated block. **User's explicit choice — overrides "let the planner redesign."** — **Reversibility:** reversible.

### delegate-agy-d4t and delegate-agy-b7g — fold into this round

- **D-06:** Fix `delegate-agy-d4t` (P2 — `RB01`'s static unbounded-call scan covers only `agy_bridge.sh`/`gemini_shim.sh`, not `tests/contract-check.sh`, which carries 3 hand-verified-but-unregistered `agy` call sites) by extending RB01's loop to include `contract-check.sh`. **User's explicit choice — overrides "defer, ticket for later."** — **Reversibility:** reversible.
- **D-07:** Fix `delegate-agy-b7g` (P3 — on a truly zero-byte, no-cache `agy models` reply, `agy_bridge.sh` emits the generic "failed to retrieve model list" message instead of the more actionable "no `gemini-` ids; agy may be unauthenticated" message R9 uses elsewhere) — route the empty-`$_agy_models` case through the same degraded-message path garbage replies already use. Same exit code, same cache-untouched guarantee; this only improves diagnostic specificity. **User's explicit choice — overrides "defer as purely cosmetic."** Matches this project's fold-review-minors-into-the-running-round convention rather than filing and returning. — **Reversibility:** reversible.

### delegate-agy-sup — root-cause, not paper over

- **D-08 (implied by D-01):** `delegate-agy-sup` (P3 — `RB24`'s TERM/INT/HUP trap-preservation test is an intermittent flake, reproduced even on a pre-Phase-02-fix-round commit) gets root-caused rather than deferred, per D-01. The ticket's own text already narrows the likely cause to a timing race in `run_bounded`'s trap save/restore around its two mechanisms (coreutils vs. bash watchdog) — the planner should start there rather than re-diagnosing from scratch. — **Reversibility:** reversible.

### Release notes

- **D-09:** Extend README's existing `## Changelog` → `### 1.6.2` section with the six newly-fixed items (ltf, u1z, d4t, b7g, plus a line noting xfa/i43's investigation-closures) and an explicit "every existing installation must re-run the installer, the pin only points forward" notice. **User's explicit choice — overrides "new GitHub Release" and "both."** No prior GitHub Release exists for this repo (`gh release list` is empty); README's Changelog is the established, already-populated mechanism from Phases 1 through 5. — **Reversibility:** reversible — a GitHub Release can still be cut later from the same content; nothing here forecloses it.

### Fresh-install verification

- **D-10:** Prove criterion 3 (fresh `install.sh` run on merged `master`, both suites pass) via a **one-time manual, documented step** — clone to a scratch directory, run `install.sh`, run `tests/run-tests.sh` and `tests/hooks/run-hook-tests.sh`, confirm both `agy-bridge` and `gemini` launchers execute — recorded in this phase's verification artifact (not a new permanent automated test). **User's explicit choice — overrides "new automated E2E test case" and "both."** No CI exists for this repo; adding one is out of scope for a single-repo bash project's release gate. — **Reversibility:** reversible — an automated version can be added later without this decision blocking it.

### Claude's Discretion

- **Exact wording of the release notes' re-run notice and per-item Changelog bullets** — subject to matching the existing `### 1.6.2` section's established bullet style (one bullet per defect, plain language, no ticket IDs inline).
- **Exact grep/loop mechanics for D-06's RB01 extension** — subject to reusing RB01's existing scan shape rather than inventing a new one.
- **Whether D-08's root-cause fix for `delegate-agy-sup` needs a new regression case or just a corrected `run_bounded` trap-handling fix** — the planner should read RB24's existing test and `run_bounded`'s trap save/restore before deciding.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase intent and requirements
- `.planning/ROADMAP.md` §"Phase 6: Ship 1.6.2" — the four success criteria and the explicit note that criterion 3 excludes `tests/contract-check.sh` from the gate
- `.planning/REQUIREMENTS.md` — this phase maps to no single requirement; it is the release gate for R5, R6, R8, R11, S1, S2, S3, S4, S5, all already validated in Phases 1-5
- `.planning/PROJECT.md` §Key Decisions — "Follow-ups discovered during release shipping known defects it surfaced itself misrepresents what it fixes" — the rule D-01 applies directly
- `.planning/PROJECT.md` §Context — "Judge state by reading files, never by the commit graph" — directly how this phase's `master`-vs-`fix/agy-bridge-resilience` scouting was done and how criterion 2 should be checked

### Prior-phase decisions this phase inherits
- `.planning/phases/02-model-list-handling-end-to-end/02-CONTEXT.md` (herestring-count assertion pattern) — D-05's `grep -cF` structural check follows this precedent
- `.planning/phases/03-the-exit-code-contract/03-CONTEXT.md` — the ROADMAP note this phase's `03-CONTEXT.md` corresponds to for `tests/contract-check.sh`'s deliberate exclusion from the release gate

### Tracker — all 8 currently-open tickets
- `delegate-agy-xfa` (P1, bug) — D-02, close as resolved
- `delegate-agy-i43` (P2, bug) — D-03, close as resolved, `-k` kept
- `delegate-agy-d4t` (P2) — D-06, fix (extend RB01)
- `delegate-agy-ltf` (P2, bug) — D-04, fix (flag-parsing guard)
- `delegate-agy-rod` (P2, epic) — Phase 5's epic, 5/5 done, close as bd hygiene
- `delegate-agy-u1z` (P2) — D-05, fix (structural-equality check)
- `delegate-agy-b7g` (P3, bug) — D-07, fix (degraded-message routing)
- `delegate-agy-sup` (P3) — D-08, root-cause (trap save/restore race)

### Code under change (read on `master`, current state)
- `scripts/gemini_shim.sh:556` — the unknown-long-flag branch D-04 fixes
- `scripts/agy_bridge.sh`, `scripts/gemini_shim.sh` — the duplicated write-gate/fallback block and its twin `grep -qxF` sites D-05's structural check covers
- `tests/run-tests.sh` — `RB01`'s existing static-scan loop (D-06 extends it to `tests/contract-check.sh`), `RB24` (D-08's flaky trap-preservation test)
- `scripts/agy_bridge.sh` — the model-fetch block where empty-`$_agy_models` currently falls through to the generic error instead of R9's degraded-list message (D-07)
- `README.md` §Changelog, `### 1.6.2` — D-09's target section
- `scripts/install.sh` — D-10's manual verification target; no code change expected here, read-only for this phase unless D-06/D-08's fixes touch shared helpers it also uses

### Working tree / branches
- `fix/agy-bridge-resilience` (worktree `.worktrees/agy-1.6.2`) — confirmed ancestor of `master`; no further sync needed for this phase
- `master` — the tree criterion 2 and criterion 3 are checked against

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **RB01's existing static-scan loop** (`tests/run-tests.sh`) — D-06 extends its file list rather than writing a new scanner.
- **Phase 2's herestring-count assertion pattern** (`02-01-PLAN.md`/`02-02-PLAN.md`) — D-05's structural-equality check follows this exact shape for a different duplicated block.
- **R9's existing degraded-list message path** (`agy_bridge.sh`) — D-07 routes the empty-reply case through this same path rather than writing a new message.

### Established Patterns
- **"Fold review Minors into the fix round in progress"** — this project's own standing convention (PROJECT.md), applied here to d4t and b7g rather than filing and deferring.
- **"Judge state by reading files, never the commit graph"** — how criterion 2's `master`-vs-`fix/agy-bridge-resilience` state was confirmed during this discussion, and how the planner/executor should re-confirm it.
- **Fixed literal, defined once, pinned by a test, quoted verbatim in docs** — the RB03-style provenance convention prior phases established; any new message D-07 introduces should follow it if it's user-facing.

### Integration Points
- **`run_bounded`'s two mechanisms (coreutils `timeout -k` vs. bash watchdog)** — the likely seam for D-08's root cause; both arms need checking, not just one.
- **`write_wrapper()`'s two call sites** (`install.sh:206-207`) — read-only for this phase; D-10's manual verification exercises this path end to end without touching it.

</code_context>

<specifics>
## Specific Ideas

- User explicitly chose "fix or investigation-close all 8, defer none" over deferring `delegate-agy-sup`'s flake, applying this project's own no-defer-for-discovered-work rule to itself.
- User explicitly chose to lock `ltf` and `u1z`'s fix mechanisms exactly as their own ticket bodies already specify, rather than leaving them open for the planner to redesign.
- User explicitly chose README's existing Changelog section over a new GitHub Release, since this project has never cut one and the Changelog is the established mechanism.
- User explicitly chose a one-time manual verification pass over new CI/automated E2E infrastructure for the fresh-install proof, since no CI exists for this repo.

</specifics>

<deferred>
## Deferred Ideas

None — every gray area surfaced during scouting (ticket disposition, release-notes format, fresh-install verification) was fixed in-phase per D-01 through D-10. Nothing was pushed to a future phase.

### Reviewed Todos (not folded)
None — `cross_reference_todos` found zero matches for Phase 6.

</deferred>

---

*Phase: 6-Ship 1.6.2*
*Context gathered: 2026-08-21*
