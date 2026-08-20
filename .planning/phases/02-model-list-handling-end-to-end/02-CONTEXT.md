# Phase 2: Model-list handling, end to end - Context

**Gathered:** 2026-08-20
**Status:** Ready for planning

<domain>
## Phase Boundary

`scripts/agy_bridge.sh` and `scripts/gemini_shim.sh`'s `agy models` fetch/cache/normalize path, on `fix/agy-bridge-resilience` (worktree `.worktrees/agy-1.6.2`) — the branch this phase's plan and tests operate against. Two of the roadmap's four success criteria are already shipped and tested by work that landed ahead of this phase's formal planning (see Decisions below); this phase's actual new-code surface is narrower than `ROADMAP.md`'s "Plans: TBD" implies.

**In scope:** `delegate-agy-8ph` (S4 — shared cache poisoning, still open) on both writers; the fallback behavior a degraded-but-successful fetch triggers within the *same* call; a synthetic extra-column normalization test (S1, criterion 4's untested half).

**Out of scope:** re-verifying criteria 1 (`delegate-agy-30m`, closed) and 3 (already shipped, already tested) — see Decisions. Shim messaging changes beyond what's decided here — that's Phase 5's failure-mode-contract surface (S3), not this phase's. `install.sh`/`uninstall.sh`'s own unguarded-`$HOME` sites (`delegate-agy-4bp`, P3) — different files, Phase 4's surface, not mapped to Phase 2 in `REQUIREMENTS.md`'s traceability table.

</domain>

<decisions>
## Implementation Decisions

### Already-shipped criteria — trust, don't re-verify

- **D-01:** Criterion 1 (a bare-environment `agy-bridge` invocation reaches its own argument handling instead of dying on `HOME: unbound variable`) is **done, not this phase's work**. `delegate-agy-30m` is CLOSED (fixed at `a409358` on `fix/agy-bridge-resilience`, RED proven at `869d453`/`RB27`). The fix covers four `$HOME`-unguarded sites, not the one the ticket originally named: `scripts/agy_bridge.sh:468` (models cache), plus the MCP cache and two config paths handed to `python3`. Both cache writes are wrapped `{ ...; } 2>/dev/null || true` (`agy_bridge.sh:482-483`, mirroring `gemini_shim.sh:419-420`), closing the redirect-error leak the ticket also named. `tests/run-tests.sh:3457` (`RB27`) already drives a real delegation under `env -i` with no `HOME` and asserts rc=0 with empty stderr. A sibling installer-side crash this fix surfaced (`delegate-agy-oyy`, generated wrapper crashes on unbound `$HOME` at `install.sh:151`) is also CLOSED — separately, Phase 4's surface. **the agent must not open new tasks against criterion 1**; if `RB27` is found failing during this phase's work, that is a regression to investigate, not unfinished phase-1 scope. — **Reversibility:** n/a, this decision only scopes what Phase 2 does *not* redo.

- **D-02:** Criterion 3 (a `gemini-`-less model list is reported as a degraded/unauthenticated agy, not blamed on `--type`) is **also done, not this phase's work**. Shipped at `a73b188` — original 1.6.2 branch work that pre-dates this phase's planning entirely, not something Phase 1 or 1.5 added. `scripts/agy_bridge.sh:515-517` already emits the distinct message; `tests/run-tests.sh:497` (`R8`) already asserts `rc=2`, the `"no 'gemini-' ids"` text, and the *absence* of `"for --type"` in the same output. The shim side is asserted too: `tests/run-tests.sh:1168` (`SH14`) proves a gemini-less list is never treated as evidence that a live model name (`flash`) is unknown — no spurious `WARNING`. Criterion 3's wording ("not told their `--type` did not match") is bridge-specific — the shim has no `--type` flag — so `SH14`'s narrower assertion (no false "unknown name" warning) is the correct shim-side reading, not a gap. — **Reversibility:** n/a, same as D-01.

### The one criterion still open — S4 / `delegate-agy-8ph`

- **D-03:** Both writers must **stop caching a fetch reply with no `^gemini-` ids**, unmodified from the ticket's own framing: `Task [refuse to cache a reply with no ^gemini- ids, on both writers] ! [no one-sided fix, no changing the 60-min TTL as a substitute]`. `scripts/agy_bridge.sh:475-483` currently writes `$_agy_models` to `$CACHE_FILE` unconditionally inside the `run_bounded` success branch — the `grep -q '^gemini-'` check at `:515` runs only *after* the cache write, at use time. `scripts/gemini_shim.sh`'s `load_models()` (`:404-429`) has the identical shape: `raw` is written to `$MODELS_CACHE` at `:418-420` whenever non-empty, with no `gemini-` gate anywhere in the function. The fix gates the write on the same normalized (`cut -f1` then `grep '^gemini-'`) check criterion 3 already performs at use time — reusing it, not inventing a second check. The existing atomic tmp-file-then-`mv` write pattern is unchanged (S4's acceptance requires writes "stay atomic", not that a new locking mechanism be added). — **Reversibility:** reversible — the gate is a single condition around an existing write; removing it later is local.

- **D-04:** A **live fetch that succeeds but is degraded (zero `gemini-` ids) is treated like a fetch *failure* for this call**, not only for future cache writes: if a valid, non-poisoned stale cache exists on disk, this invocation falls back to it rather than failing loud immediately. **User's explicit choice — overrides the recommended "keep current: always fail loud" option.** Concretely: the same branch each script already uses when the bounded fetch itself errors (`agy_bridge.sh`'s `else` at `:490-499`, reading back `$CACHE_FILE`; `gemini_shim.sh:427`, reading back `$MODELS_CACHE`) is what a degraded-but-successful fetch also falls into — the degraded `$_agy_models`/`raw` is discarded rather than caching it (per D-03) and rather than treating it as the authoritative answer for this call. **With no stale cache to fall back to, behavior is unchanged**: bridge exit 2 (`R7`'s "no cache" shape, `tests/run-tests.sh` around `:485-491`), shim silent passthrough. TTL bookkeeping needs no new logic — because the degraded reply is never written, the cache file's mtime stays at its last *good* write, so the next call within 60 minutes still sees it as fresh-enough per the existing `find … -mmin +60` check; past 60 minutes it retries the fetch exactly as today. — **Reversibility:** reversible — this is a branch condition, not a new state machine; reverting to immediate-fail is a local diff.

- **D-05 (the agent's discretion):** The bridge's fallback warning uses **wording distinct from** the existing fetch-failure warning (`agy_bridge.sh:494`, `"'agy models' $_agy_why; using the stale cached list."`) — something naming the degraded-reply cause specifically (e.g. `"'agy models' returned no gemini- ids (degraded/unauthenticated); using the stale cached list."`), so an operator debugging stderr can tell "agy call failed" from "agy call succeeded but returned garbage" without re-deriving it from exit codes. The shim stays silent on this path too, per its existing degrade-silently design (`gemini_shim.sh:104-106`'s rationale) — this phase does not add a shim warning; that's S3/Phase 5 territory if it's ever revisited. Exact string wording is the agent's call, subject to the existing "fixed literal defined once, quoted verbatim in README's troubleshooting table if one exists for this row" convention Phase 1's D-10 and D-16 set.

### Criterion 4 — extra-column normalization

- **D-06:** Add a **synthetic 3-column fixture test** (`id<TAB>display name<TAB>extra`) proving `cut -f1` resolves it identically to a real 2-column row, on both the bridge and the shim. **User's explicit choice — overrides the "skip it, tab-suffix coverage is enough" alternative.** Real agy has only ever emitted 2 columns (Phase 1.5's live probe, `tests/fixtures/agy-models.tsv`), so this is a synthetic row constructed for the test, not a captured fixture — do not add it to `tests/fixtures/agy-models.tsv` itself, which D-14/D-14a (Phase 1.5) established as the real captured evidence `fake-agy.sh` reads at runtime; keep the synthetic row inline in the new test case (or a separate small fixture file) so it can never be confused with real captured output. The anchored matchers (`^gemini-[0-9.]+-flash-high$` etc.) themselves stay byte-identical to what shipped — this test proves the normalization step ahead of them, not a matcher change. — **Reversibility:** reversible — one new test case, no production-code change beyond D-03/D-04's gate.

### Decisions made during planning review (post-checker-pass, pre-execution)

- **D-07:** Fold criterion 3's remaining stderr-visibility gap into this phase's scope, reversing D-02's original "raise as follow-up bd issue" disposition. **User's explicit choice.** `$_agy_err` is captured on every `agy_bridge.sh` fetch attempt but was surfaced only inside the fetch-failure branch; a degraded-but-successful reply discarded it unread. Fix: relocate the existing `sed 's/^/       agy: /' "$_agy_err" >&2` relay (currently inside the `else` block) to run unconditionally after the whole `if/elif/else`, so it fires on the fetch-failure path (unchanged) and the degraded-success path (new) alike. One line moved, not duplicated. Bridge-only — the shim's `load_models()` redirects agy's stderr straight to `2>/dev/null` and never captures it, so there is nothing to relay on that side; D-05's "shim stays silent" already holds architecturally. Landed in Plan 02-01 Task 2 (`delegate-agy-6q3.2`). — **Reversibility:** reversible — a one-line position change, trivially reverted.

- **D-08:** Fold a `pipefail`/SIGPIPE correctness fix into scope, reopening the D-01/D-02 "closed, must not disturb" boundary for exactly two existing shipped lines. **User's explicit choice, after independent verification the hazard is real.** Cross-AI review (Codex) found that the degraded-list gate's chosen two-element form (`printf '%s\n' "$var" | grep -q '^gemini-'`) is not fully `pipefail`-safe: a `grep -q` that finds an early match in a sufficiently large `$var` can close its read end before `printf` finishes writing, SIGPIPE-killing `printf` (exit 141) while `grep` itself exits 0 — under `set -o pipefail`, bash reports the *pipeline's* status as 141 (rightmost non-zero exit), which the enclosing `if` reads as a degraded list for a genuinely good one. Empirically reproduced on bash 5.3.15 (5/5 iterations, ~500KB input, early match): pipe form → `rc=141` every time; herestring form (`grep -q '^gemini-' <<< "$var"`) → `rc=0` every time, because a herestring is backed by a temp file bash writes synchronously before the reader starts, not a live pipe, so there is no producer left to receive SIGPIPE.
  Fix, applied consistently: use the herestring form (`<<<`), not a pipe, at all four `grep -q '^gemini-'` degraded-list-detection sites — the two new write-gates this phase adds (`agy_bridge.sh`, `gemini_shim.sh`, both Task 1) **and** the two existing shipped checks the new gates were built to mirror (`agy_bridge.sh:515`, `gemini_shim.sh:459`). The existing checks are closed work under D-01/D-02; this is a narrow, explicit, user-approved exception for this one hazard class only — it does not reopen either criterion for any other reason.
  **Explicitly out of scope, even under this exception:** `agy_bridge.sh:524-525` and `gemini_shim.sh:447`'s `grep -E ... | sort -V | tail -1` auto-select/class-resolution lines (`tail -1` must consume its entire input to find the last line, so it has no early-close hazard — not the same bug class), and `agy_bridge.sh:529` / `gemini_shim.sh:438`'s `grep -qxF` exact-model-id validation (a different mechanism the user's directive did not name). Landed in Plan 02-01 Task 1 (`delegate-agy-6q3.1`) and Plan 02-02 Task 1 (`delegate-agy-6q3.4`). — **Reversibility:** reversible — four `<<<` tokens replacing four `|` pipe forms, each a one-line, mechanically identical substitution.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase intent and requirements
- `.planning/ROADMAP.md` §"Phase 2: Model-list handling, end to end" — the four success criteria, and the "On the Phase 1.5 dependency" note explaining why criterion 4's "byte-identical to what shipped" needs Phase 1.5's fixtures
- `.planning/REQUIREMENTS.md` §S1, §S4 — the two requirements this phase closes; note S1's traceability row ("degraded-list reporting not yet distinct from an unmatched `--type`") is **stale** as of this phase — see D-02
- `.planning/PROJECT.md` §Context, §Key Decisions — "Judge state by reading files, never by the commit graph"; this phase's decisions were verified by reading `.worktrees/agy-1.6.2` directly, not by trusting `git log` or `REQUIREMENTS.md`'s traceability table

### Prior-phase decisions this phase inherits
- `.planning/phases/01-the-missing-timeout-decision/01-CONTEXT.md` §D-09/D-10 — fixed-literal-warnings-quoted-in-docs convention D-05 follows for the new fallback warning
- `.planning/phases/01.5-contract-check-against-a-real-agy/01.5-CONTEXT.md` §D-14/D-14a/D-15 — the fixture-vs-canned-block distinction D-06 respects (the synthetic 3-column row is a test artifact, not a captured fixture)
- `.planning/phases/01.5-contract-check-against-a-real-agy/01.5-CONTEXT.md` §Specifics — the 2026-08-19 probe's captured model-id shapes (`gemini-3.7/3.6/3.5-flash-{high,medium,low}`, `gemini-3.1-pro-{high,low}`), the real 2-column shape D-06's synthetic row extends

### Code under change (read on `fix/agy-bridge-resilience`, not `master`)
- `scripts/agy_bridge.sh:468` — `CACHE_FILE`, already `${HOME:-/nonexistent}`-guarded (D-01)
- `scripts/agy_bridge.sh:471-499` — the fetch/cache/fallback block D-03 and D-04 change: `:475-483` unconditional write (D-03's gate point), `:490-499` the existing fetch-failure fallback branch (D-04's reuse target)
- `scripts/agy_bridge.sh:502-517` — `VALID_MODELS` assembly and the criterion-3 degraded-list check (`:515-517`), unchanged by this phase, reused as the gate condition
- `scripts/gemini_shim.sh:398` — `MODELS_CACHE`, already `${HOME:-/nonexistent}`-guarded (D-01)
- `scripts/gemini_shim.sh:404-429` — `load_models()`: `:412-420` the fetch/write (D-03's gate point), `:427-428` the existing fetch-failure fallback + `cut -f1` (D-04's reuse target, D-06's normalization step)
- `tests/run-tests.sh:3457` (`RB27`) — the closed-criterion-1 regression test, must stay green, not be duplicated
- `tests/run-tests.sh:497` (`R8`) and `:1168` (`SH14`) — the closed-criterion-3 regression tests, must stay green, not be duplicated
- `tests/run-tests.sh` around `:485-491` (`R7`) — the existing "no cache to fall back to" hard-fail shape D-04 leaves unchanged

### Tracker
- `delegate-agy-8ph` (P2, open) — S4, this phase's substantive remaining work (D-03, D-04)
- `delegate-agy-30m` (P1, CLOSED) — criterion 1, done ahead of this phase (D-01)
- `delegate-agy-oyy` (P1, CLOSED) — sibling installer-side `$HOME` crash found by 30m's fix round; Phase 4's surface, not this phase's
- `delegate-agy-4bp` (P3, open) — `install.sh`/`uninstall.sh`'s own unguarded `$HOME`; out of scope, Phase 4's surface

### Working tree
- `.worktrees/agy-1.6.2` on `fix/agy-bridge-resilience` — where all code cited above actually lives; `master`'s files lag its history per `PROJECT.md`/`STATE.md`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **The existing fetch-failure fallback branches** (`agy_bridge.sh:490-499`, `gemini_shim.sh:427`) — D-04 routes a degraded-but-successful fetch into the same branch rather than adding a parallel one.
- **The criterion-3 `grep -q '^gemini-'` check** (`agy_bridge.sh:515`) — D-03's cache-write gate reuses this exact test rather than a second implementation of "is this list degraded".
- **`cut -f1`** (`agy_bridge.sh` inside `VALID_MODELS` assembly, `gemini_shim.sh:428`) — already column-count-agnostic; D-06 proves it rather than changing it.
- **The atomic tmp-file-then-`mv` write pattern**, present at both cache-write sites — unchanged by D-03; the gate wraps around it, not into it.

### Established Patterns
- **`${HOME:-/nonexistent}` guard + block-level `2>/dev/null || true` on cache writes** — the shape D-01 confirms is already applied uniformly; any new cache-adjacent code this phase adds must match it, not reintroduce a bare `$HOME`.
- **Fixed-literal warnings, defined once per script, quoted verbatim where docs reference them** — Phase 1's D-09/D-10 convention; D-05's new warning string follows it.
- **Real captured fixtures vs. synthetic test-only payloads stay in separate files** — Phase 1.5's D-14/D-14a rule; D-06's synthetic 3-column row must not be added to `tests/fixtures/agy-models.tsv`.

### Integration Points
- **`agy_bridge.sh`'s fetch block → `VALID_MODELS` → model auto-select/validation** — D-04's fallback determines what `VALID_MODELS` ends up holding; everything downstream (auto-select, `--model` validation) is unchanged and already correct once `VALID_MODELS` holds the right list.
- **`gemini_shim.sh`'s `load_models()` → `LIVE_MODELS` → `map_model()`** — same shape; D-04's fallback is entirely inside `load_models()`, `map_model()` needs no change.
- **`tests/fake-agy.sh`'s `FAKE_AGY_MODELS_GARBAGE` knob** — already exists (used by `R8`/`SH14`); D-03/D-04's new tests reuse it rather than adding a second garbage-simulation mechanism, and additionally need to assert the cache file's *contents* after the call (not just the call's own output), which `R8`/`SH14` currently do not check.

</code_context>

<specifics>
## Specific Ideas

- User explicitly chose "fall back to stale cache" (D-04) over the recommended fail-loud default — a deliberate override, not the agent's discretion.
- User explicitly chose to add the synthetic extra-column test (D-06) over skipping it as speculative, because criterion 4 names it literally.

</specifics>

<deferred>
## Deferred Ideas

- **The shim emitting its own warning when it detects a degraded list** — considered under D-05 and declined for this phase; it would break the shim's current silent-by-design behavior (`gemini_shim.sh:104-106`). Belongs to Phase 5 (S3, the shim's failure-mode contract) if ever revisited.
- **`delegate-agy-4bp`** (`install.sh`/`uninstall.sh`'s own unguarded `$HOME` sites) — different files, Phase 4's surface. Not folded into this phase.

### Reviewed Todos (not folded)
None — `cross_reference_todos` found zero matches for Phase 2.

</deferred>

---

*Phase: 2-Model-list handling, end to end*
*Context gathered: 2026-08-20*
