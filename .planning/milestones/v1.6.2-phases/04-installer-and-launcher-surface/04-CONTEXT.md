# Phase 4: Installer and launcher surface - Context

**Gathered:** 2026-08-21
**Status:** Ready for planning

<domain>
## Phase Boundary

`scripts/install.sh`, `scripts/uninstall.sh`, the generated launcher-wrapper heredoc, and the two `/agy-setup`/`/agy-uninstall` docs (`.claude/commands/agy-setup.md`, `.claude/commands/agy-uninstall.md`) plus `.claude-plugin/plugin.json`. This is an audit-and-close-gaps phase, the same shape as Phase 2 and Phase 3: ROADMAP.md's five success criteria look like open design work, but criteria 1-3 (registry exact-key match, absent/truncated/reshaped-registry silence, install-time-literal repin construction) are **already implemented and already covered** by `tests/run-tests.sh`'s I16/I17/I18 adversarial fixtures (lookalike-marketplace entry, empty-array/compact/semi-compact registry shapes, apostrophe-in-path). `REQUIREMENTS.md` already reads R8 and S2 as "shipped on branch, reviewed." This phase's real new-code surface is two known P3 bugs (criteria 4 and 5) plus two more open tickets discovered during this discussion that were never mapped to any phase in `ROADMAP.md`.

**Ticket-count correction found during this discussion:** `bd list --status open` shows **11** open tickets, not the 10 `ROADMAP.md`'s "All 10 open tickets are absorbed" line counts (written before `delegate-agy-k0f` was filed on 2026-08-20). Two open tickets sit on this phase's exact file surface and are unmapped to any phase: `delegate-agy-k0f` and `delegate-agy-4bp`. Both are folded into this phase's scope (D-05, D-06 below) — leaving them out just means Phase 6's release gate finds them later on files this phase already touches.

**In scope:**
- `delegate-agy-4xn` — `install.sh`'s `AGY_SETUP_PATCH_ALIASES=1` branch calls `python3` with no `command -v` guard (ROADMAP criterion 4).
- `delegate-agy-4vy` — the `claude plugin list --json | python3 ... | head -1` fallback in `agy-setup.md`/`agy-uninstall.md` can SIGPIPE-abort under `set -euo pipefail` (ROADMAP criterion 5).
- `delegate-agy-k0f` — `.claude-plugin/plugin.json`, `agy-setup.md`, `agy-uninstall.md` still carry `a001d0e`'s reverted, pre-1.6.2 content; `fix/agy-bridge-resilience`'s branch tip has the correct content (verified via `git diff` during this discussion — see canonical_refs).
- `delegate-agy-4bp` — `install.sh`/`uninstall.sh` crash with an opaque `HOME: unbound variable` instead of a stated precondition, when `HOME` is unset.
- Re-citing criteria 1-3's existing I16/I17/I18 coverage in the plan as evidence, without re-doing the work.

**Out of scope:**
- `delegate-agy-lkg` (installer live-verify 600s exposure) — already closed and fixed (`install.sh:381`'s `GEMINI_SHIM_TIMEOUT=20` prefix), confirmed by reading current `install.sh`. Do not reopen it.
- Any change to `scripts/agy_bridge.sh` or `scripts/gemini_shim.sh`'s own logic — this phase's files are the installer, the generated wrapper, and the setup/uninstall docs only.
- Adding new adversarial registry fixtures beyond I16/I17/I18 — explicitly declined (D-07).

</domain>

<decisions>
## Implementation Decisions

### delegate-agy-4xn — python3 guard in the rc-alias-patch branch

- **D-01:** Guard `command -v python3` **once**, immediately after the `AGY_SETUP_PATCH_ALIASES=1` gate is confirmed true and before the `for RC in ...` loop starts (`install.sh` around line 227-239) — not inside the loop per RC file. **User's explicit choice — overrides "guard inside the loop."** Checking an unchanging fact on every matched rc file is redundant; a single guard before the loop is cheaper and matches the ticket's "same graceful state as every other python3-absent path in the installer." On miss: print the same fail-open `WARNING: ... — skipping ... (fail-open).` shape `_register_tokensave` already uses at `install.sh:280-282`, naming the alias-patch feature specifically, skip the whole block, and let the rest of `install.sh` continue untouched (wrappers already written by this point in script order). — **Reversibility:** reversible.
- **D-02:** No RB03-style README-pinning for the new warning literal. **User's explicit choice — overrides "full provenance pin."** One new suite case is enough: `AGY_SETUP_PATCH_ALIASES=1` + a real recursive-`gemini` alias in a fake rc file + no `python3` on PATH → `install.sh` exits 0, wrappers still written, warning on stderr, rc file untouched. None of `install.sh`'s existing sibling warnings (`_register_tokensave`'s python3-absent line, `_agy_detect`'s) are quoted in README either — only the "Env flags" comment block documents that `AGY_SETUP_PATCH_ALIASES` exists at all. — **Reversibility:** reversible.

### delegate-agy-4vy — SIGPIPE-safe CLI fallback one-liner

- **D-03:** Eliminate `| head -1` from the `python3 -c '...'` pipeline entirely, rather than appending `|| true` to the `RESOLVED=` assignment (the ticket's own suggested minimal fix). **User's explicit choice — overrides the ticket's `|| true` suggestion.** Have the python3 one-liner itself select and print only the first matching `installPath` (e.g. index `[0]` of the filtered list, or `break` after the first match) so `head` is never spawned and there is nothing left to SIGPIPE `python3`. Same output, fewer moving parts — matches Phase 2's D-08 precedent of fixing a SIGPIPE-hazard class at its source rather than suppressing the resulting exit code. Applies **identically to both** `agy-setup.md` and `agy-uninstall.md` — same defect, same fix, same file class (mirrors Phase 3's D-01 "fix both, not just the one literally ticketed" pattern). — **Reversibility:** reversible.
- **D-04:** Add a new automated regression case that extracts the fenced bash block from each `.md` file and runs it under `bash -euo pipefail -c` against a fake `claude` stub returning **multiple** matching `agy-delegate@...` entries — the exact shape that triggered the old SIGPIPE — asserting the script reaches the validating `case` and does not abort. **User's explicit choice — overrides "manual verification only."** These two files are user-facing copy-paste docs rather than a path `run-tests.sh` already exercises, but the fix is proving behavior under a specific hazardous condition, not a doc-text match — inspection alone can't demonstrate that. — **Reversibility:** reversible.
- **Sequencing constraint (not a discretionary decision — verified by reading the branch):** `fix/agy-bridge-resilience`'s branch tip (what D-05's k0f sync pulls in) still carries the **same unguarded `head -1` pipeline** in its now-demoted fallback command block — confirmed via `git diff HEAD fix/agy-bridge-resilience -- .claude/commands/agy-setup.md .claude/commands/agy-uninstall.md` during this discussion. D-05's content sync must land **before** D-03's SIGPIPE fix; D-03 applies to the post-sync fallback block, not the current pre-sync one. Executing them in the other order re-fixes a block that's about to be overwritten.

### delegate-agy-k0f — stale post-revert docs and version string

- **D-05:** Fix mechanism is a **content sync from `fix/agy-bridge-resilience`'s branch tip**, not a hand-rewrite. Verified via `git diff HEAD fix/agy-bridge-resilience -- .claude-plugin/plugin.json .claude/commands/agy-setup.md .claude/commands/agy-uninstall.md` during this discussion — a clean, non-conflicting diff exists (plugin.json's version string `1.6.1`→`1.6.2`; both `.md` files gain the "two commands: find the path, then run it" flow, demoting the `claude plugin list --json` pipeline to a labeled fallback, per commit `7620963`). The ticket's own "Verify" section (`git diff HEAD fix/agy-bridge-resilience -- <3 files>` should be empty once fixed) is the acceptance check — no new design decision needed here. — **Reversibility:** reversible.

### delegate-agy-4bp — opaque HOME-unset crash

- **D-06:** Use the ticket's own already-decided fix shape verbatim: an explicit precondition — `[[ -n "${HOME:-}" ]] || { echo "ERROR: HOME is not set; run as a normal user with a home directory." >&2; exit 1; }` — sited next to the existing refuse-root check in **both** `install.sh` and `uninstall.sh`, before any `$HOME` expansion. **Not a `${HOME:-/nonexistent}` fallback** — these two scripts genuinely require a home directory (they install into `~/.local/bin` and write `~/.config/agy-delegate`), so silently redirecting to `/nonexistent` would install into a path the user never sees; the correct behavior is a stated refusal, not a redirect. This is the ticket's own bead-lock (`Task [explicit HOME precondition check in both scripts, sited with refuse-root] ! [no ${HOME:-/nonexistent} fallback]`) — the planner should treat it as decided, not open. — **Reversibility:** reversible.

### Criteria 1-3 — already shipped

- **D-07:** Trust I16/I17/I18's existing coverage; do not add new registry fixtures or re-verify criteria 1-3's logic. **User's explicit choice — overrides "add one more adversarial fixture" (a truncated-file or missing-version-key shape).** Same pattern as Phase 2's D-01/D-02 (already-shipped criteria are cited, not redone) and Phase 3's already-shipped-criteria treatment. The plan should cite I16 (`tests/run-tests.sh:3980-4105`), I17 (`:4107-4194`), and I18 (`:4197-4239`) by name and line in canonical_refs as evidence that criteria 1-3 are met, with no new tasks against them. Only re-open if a planning-time re-read finds an actual regression against the current file content. — **Reversibility:** reversible — re-opening later if a regression is found costs nothing this decision forecloses.

### Claude's Discretion

- **Exact wording of the D-01 python3-absent warning** — subject to matching `_register_tokensave`'s existing shape (`install.sh:280-282`) and naming the alias-patch feature specifically.
- **Exact python3 rewrite for D-03** (index `[0]` vs. an early `break` in the list comprehension vs. a `next(...)`-style single-match expression) — subject to producing byte-identical output to the current `| head -1` behavior on a single-match input.
- **Whether D-04's fake `claude` stub is a new fixture or an inline heredoc** in the new test case — subject to matching the suite's existing stub conventions for CLI-output fakes.
- **Whether D-06's HOME precondition test is one shared case covering both scripts or two separate cases** — subject to matching the existing per-script test-numbering convention (`I`-prefix for install.sh cases, per the ticket's own file list).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase intent and requirements
- `.planning/ROADMAP.md` §"Phase 4: Installer and launcher surface" — the five success criteria and the note naming `delegate-agy-lkg` as already-closed-ahead-of-phase context
- `.planning/REQUIREMENTS.md` §R8, §S2 — the two requirements this phase closes; both traceability rows already read "shipped on branch" (D-07 trusts this)
- `.planning/PROJECT.md` §Context — "Judge state by reading files, never by the commit graph"; this phase's k0f fix is a direct application of that rule (files on `master` vs. files on `fix/agy-bridge-resilience`)

### Prior-phase decisions this phase inherits
- `.planning/phases/02-model-list-handling-end-to-end/02-CONTEXT.md` §D-08 — the SIGPIPE-hazard-class fix pattern (avoid the early-closing consumer, don't just suppress the resulting exit code) D-03 applies to a different pipe shape (`| head -1` vs. `| grep -q`)
- `.planning/phases/02-model-list-handling-end-to-end/02-CONTEXT.md` §D-01 — "criterion already done, not this phase's work, don't reopen it" pattern D-07 applies to criteria 1-3
- `.planning/phases/03-the-exit-code-contract/03-CONTEXT.md` §D-01 — "fix both files, not just the one literally ticketed" pattern D-03 applies to `agy-setup.md`/`agy-uninstall.md`
- `.planning/phases/03-the-exit-code-contract/03-CONTEXT.md` §D-11/D-12 — the RB03-style provenance-pinning convention, and its limits (only messages a phase adds or touches, not everything) — D-02 explicitly declines to extend it to the new python3-guard warning

### Tracker
- `delegate-agy-4xn` (P3, open) — D-01, D-02
- `delegate-agy-4vy` (P3, open) — D-03, D-04
- `delegate-agy-k0f` (P3, open) — D-05; "Verify" section names the exact `git diff` acceptance check
- `delegate-agy-4bp` (P3, open) — D-06; carries its own decided fix shape verbatim in the ticket body
- `delegate-agy-lkg` (P1, CLOSED) — already fixed at `install.sh:372-381`; out of scope, do not reopen
- `delegate-agy-30m` / `delegate-agy-oyy` (CLOSED) — the sibling `$HOME`-unguarded fixes `delegate-agy-4bp` is explicitly distinct from (see the ticket's own "Distinct from" paragraph)

### Code under change (read on `master`, current state)
- `scripts/install.sh:227-250` — the `AGY_SETUP_PATCH_ALIASES=1` consent-gated rc-alias-patch loop; D-01's guard site, D-03's SIGPIPE fix does not touch this file
- `scripts/install.sh:280-282` — `_register_tokensave`'s existing fail-open python3-absent warning; D-01's wording template
- `scripts/install.sh:58` and further sites at `:223, :248, :249, :251` — the unguarded `$HOME` expansions D-06 fixes with one precondition
- `scripts/uninstall.sh:20, :60, :61` — the mirrored unguarded `$HOME` expansions D-06 fixes in the second file
- `.claude/commands/agy-setup.md:37-46`, `.claude/commands/agy-uninstall.md:28-37` — the `head -1` pipeline D-03 rewrites; D-05's sync replaces the surrounding content first
- `.claude-plugin/plugin.json` — the version string D-05 syncs
- `tests/run-tests.sh:3980-4105` (I16), `:4107-4194` (I17), `:4197-4239` (I18) — the existing criteria-1-3 coverage D-07 cites rather than duplicates

### Working tree / branch
- `fix/agy-bridge-resilience` (worktree `.worktrees/agy-1.6.2`) — the source of D-05's content sync; `git diff HEAD fix/agy-bridge-resilience -- .claude-plugin/plugin.json .claude/commands/agy-setup.md .claude/commands/agy-uninstall.md` is the exact command to both diagnose and verify the fix

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`_register_tokensave`'s python3-absent guard** (`install.sh:280-282`) — the fail-open warning shape D-01's new guard copies.
- **`_sq()`** (`install.sh:69`) and the reg-key derivation (`install.sh:99-114`) — already correct, untouched by this phase; D-07 cites, does not modify.
- **I16/I17/I18** (`tests/run-tests.sh`) — the existing registry-fixture test shapes; any new case this phase adds (D-04's extract-and-run, D-06's HOME-precondition case) should follow their `_fresh_home`/`env -i` isolation convention rather than inventing a new harness pattern.

### Established Patterns
- **Fail-open on a missing optional dependency, warn to stderr, continue** — `_agy_detect` (`install.sh:260-264`) and `_register_tokensave` (`install.sh:279-283`) both already do this for `python3`; D-01 extends the same pattern to the one remaining unguarded site.
- **Fix the SIGPIPE-hazard class at its source, not the resulting exit code** — Phase 2's D-08 precedent; D-03 applies it to a `| head -1` shape instead of Phase 2's `| grep -q` shape.
- **Judge state by reading files, not the commit graph** — `PROJECT.md`'s standing rule; directly how k0f was diagnosed and how D-05's fix is verified.

### Integration Points
- **`install.sh`'s script-order** — wrappers are written at `write_wrapper` calls (`install.sh:205-206`), well before the rc-alias-patch block (`:227-250`) and the tokensave/MCP block (`:252-360`) that follow. D-01's guard sits after wrappers already exist on disk, so a skip there can never leave the installer half-finished.
- **`agy-setup.md` ↔ `agy-uninstall.md`** — byte-identical pipeline shape in both files; D-03's fix and D-04's test must be applied/written for both, not just one.

</code_context>

<specifics>
## Specific Ideas

- User explicitly chose to eliminate `head -1` (D-03) over the ticket's own suggested `|| true` minimal patch — a deliberate "fix the class, not the symptom" override, not the agent's discretion.
- User explicitly chose to fold both `delegate-agy-k0f` and `delegate-agy-4bp` into this phase's scope after this discussion surfaced that neither was mapped to any phase in `ROADMAP.md` — a scope-correction discovered live during discussion, not pre-existing phase intent.
- User explicitly declined additional registry-fixture coverage for criteria 1-3 (D-07) — the existing I16/I17/I18 fixtures are treated as sufficient evidence, not a gap to close.

</specifics>

<deferred>
## Deferred Ideas

- **A lint/CI check flagging `ROADMAP.md`'s stale ticket-absorption tallies automatically** — the "10 open tickets" vs. 11-actual mismatch that surfaced `k0f`'s unmapped status was found by hand this session. Worth automating if this class of drift recurs; not this phase's surface.
- **`delegate-agy-lkg`'s live-verify bound mechanism** — already closed ahead of this phase (see In/Out of scope); revisit only if a regression is found.

### Reviewed Todos (not folded)
None — `cross_reference_todos` found zero matches for Phase 4.

</deferred>

---

*Phase: 4-Installer and launcher surface*
*Context gathered: 2026-08-21*
