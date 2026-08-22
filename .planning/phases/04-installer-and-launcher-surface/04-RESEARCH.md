# Phase 4: Installer and launcher surface - Research

**Researched:** 2026-08-21
**Domain:** bash installer hardening (POSIX-ish bash 5.x, `set -euo pipefail`, python3 stdlib helpers) — no new runtime dependencies
**Confidence:** HIGH (all claims below are grounded in files read this session or the project's own test harness; no new external library is introduced by this phase)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**delegate-agy-4xn — python3 guard in the rc-alias-patch branch**
- **D-01:** Guard `command -v python3` **once**, immediately after the `AGY_SETUP_PATCH_ALIASES=1` gate is confirmed true and before the `for RC in ...` loop starts (`install.sh` around line 227-239) — not inside the loop per RC file. **User's explicit choice — overrides "guard inside the loop."** Checking an unchanging fact on every matched rc file is redundant; a single guard before the loop is cheaper and matches the ticket's "same graceful state as every other python3-absent path in the installer." On miss: print the same fail-open `WARNING: ... — skipping ... (fail-open).` shape `_register_tokensave` already uses at `install.sh:280-282`, naming the alias-patch feature specifically, skip the whole block, and let the rest of `install.sh` continue untouched (wrappers already written by this point in script order). — **Reversibility:** reversible.
- **D-02:** No RB03-style README-pinning for the new warning literal. **User's explicit choice — overrides "full provenance pin."** One new suite case is enough: `AGY_SETUP_PATCH_ALIASES=1` + a real recursive-`gemini` alias in a fake rc file + no `python3` on PATH → `install.sh` exits 0, wrappers still written, warning on stderr, rc file untouched. None of `install.sh`'s existing sibling warnings (`_register_tokensave`'s python3-absent line, `_agy_detect`'s) are quoted in README either — only the "Env flags" comment block documents that `AGY_SETUP_PATCH_ALIASES` exists at all. — **Reversibility:** reversible.

**delegate-agy-4vy — SIGPIPE-safe CLI fallback one-liner**
- **D-03:** Eliminate `| head -1` from the `python3 -c '...'` pipeline entirely, rather than appending `|| true` to the `RESOLVED=` assignment (the ticket's own suggested minimal fix). **User's explicit choice — overrides the ticket's `|| true` suggestion.** Have the python3 one-liner itself select and print only the first matching `installPath` (e.g. index `[0]` of the filtered list, or `break` after the first match) so `head` is never spawned and there is nothing left to SIGPIPE `python3`. Same output, fewer moving parts — matches Phase 2's D-08 precedent of fixing a SIGPIPE-hazard class at its source rather than suppressing the resulting exit code. Applies **identically to both** `agy-setup.md` and `agy-uninstall.md` — same defect, same fix, same file class (mirrors Phase 3's D-01 "fix both, not just the one literally ticketed" pattern). — **Reversibility:** reversible.
- **D-04:** Add a new automated regression case that extracts the fenced bash block from each `.md` file and runs it under `bash -euo pipefail -c` against a fake `claude` stub returning **multiple** matching `agy-delegate@...` entries — the exact shape that triggered the old SIGPIPE. **User's explicit choice — overrides "manual verification only."** These two files are user-facing copy-paste docs rather than a path `run-tests.sh` already exercises, but the fix is proving behavior under a specific hazardous condition, not a doc-text match — inspection alone can't demonstrate that. — **Reversibility:** reversible.
- **Sequencing constraint (verified by reading the branch):** `fix/agy-bridge-resilience`'s branch tip (what D-05's k0f sync pulls in) still carries the **same unguarded `head -1` pipeline** in its now-demoted fallback command block — confirmed via `git diff HEAD fix/agy-bridge-resilience -- .claude/commands/agy-setup.md .claude/commands/agy-uninstall.md` during this session (see Code Examples below). D-05's content sync must land **before** D-03's SIGPIPE fix; D-03 applies to the post-sync fallback block, not the current pre-sync one.

**delegate-agy-k0f — stale post-revert docs and version string**
- **D-05:** Fix mechanism is a **content sync from `fix/agy-bridge-resilience`'s branch tip**, not a hand-rewrite. Verified via `git diff HEAD fix/agy-bridge-resilience -- .claude-plugin/plugin.json .claude/commands/agy-setup.md .claude/commands/agy-uninstall.md` — a clean, non-conflicting diff exists (plugin.json's version string `1.6.1`→`1.6.2`; both `.md` files gain the "two commands: find the path, then run it" flow, demoting the `claude plugin list --json` pipeline to a labeled fallback). The ticket's own "Verify" section (that same `git diff` command returning empty once fixed) is the acceptance check. — **Reversibility:** reversible.

**delegate-agy-4bp — opaque HOME-unset crash**
- **D-06:** Use the ticket's own already-decided fix shape verbatim: `[[ -n "${HOME:-}" ]] || { echo "ERROR: HOME is not set; run as a normal user with a home directory." >&2; exit 1; }`, sited next to the existing refuse-root check in **both** `install.sh` and `uninstall.sh`, before any `$HOME` expansion. **Not** a `${HOME:-/nonexistent}` fallback — these scripts genuinely require a home directory. — **Reversibility:** reversible.

**Criteria 1-3 — already shipped**
- **D-07:** Trust I16/I17/I18's existing coverage; do not add new registry fixtures or re-verify criteria 1-3's logic. Cite I16 (`tests/run-tests.sh:3980-4105`), I17 (`:4107-4194`), I18 (`:4197-4239`) by name and line as evidence; no new tasks against them. — **Reversibility:** reversible.

### Claude's Discretion

- **Exact wording of the D-01 python3-absent warning** — subject to matching `_register_tokensave`'s existing shape (`install.sh:280-282`) and naming the alias-patch feature specifically.
- **Exact python3 rewrite for D-03** (index `[0]` vs. an early `break` in the list comprehension vs. a `next(...)`-style single-match expression) — subject to producing byte-identical output to the current `| head -1` behavior on a single-match input.
- **Whether D-04's fake `claude` stub is a new fixture or an inline heredoc** in the new test case — subject to matching the suite's existing stub conventions for CLI-output fakes.
- **Whether D-06's HOME precondition test is one shared case covering both scripts or two separate cases** — subject to matching the existing per-script test-numbering convention (`I`-prefix for install.sh cases, per the ticket's own file list).

### Deferred Ideas (OUT OF SCOPE)

- **A lint/CI check flagging `ROADMAP.md`'s stale ticket-absorption tallies automatically** — not this phase's surface.
- **`delegate-agy-lkg`'s live-verify bound mechanism** — already closed ahead of this phase; revisit only if a regression is found.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| R8 | Registry read is comparison-only — exact key match, install-time-literal repin construction, absent/unparseable registry degrades to silence | Already implemented and covered by `tests/run-tests.sh` I16 (`:3980-4105`, cases a–e) — see Code Examples and Validation Architecture. This phase does not modify the registry-comparison logic (`install.sh`'s `write_wrapper` heredoc, lines 125-177); D-01/D-03/D-05/D-06 touch unrelated code paths in the same file. |
| S2 | Survive a Claude Code registry schema change — extraction bounded to the plugin's own entry, no cross-plugin misattribution, parse failure degrades to silence | Already implemented and covered by I17 (`:4107-4194`, empty-array/compact/semi-compact shapes). Same non-modification note as R8. |

Both requirements' `REQUIREMENTS.md` traceability rows already read "shipped on branch, reviewed" (R8) / "shipped on branch" (S2) — confirmed current by reading `install.sh`'s `write_wrapper` function this session (lines 85-182): the sed extraction is anchored to `/"$reg_key_re_sq":[[:space:]]*\[$/,/^[[:space:]]*\]/p` (bounded window) and the version match is `^[[:space:]]*"version"[[:space:]]*:...` (line-start anchored), matching I16/I17's stated intent verbatim. This phase's real work (D-01 through D-06) closes four P3 tickets that sit on the same files but do not touch this logic.
</phase_requirements>

## Summary

This is an audit-and-close-gaps phase, not new design work. Every fix mechanism is locked in `04-CONTEXT.md` (D-01 through D-06); the four ticket bugs are small, independent, and mechanically simple: (1) add one `command -v python3` guard before a loop in `install.sh`, (2) remove `| head -1` from a python3 pipeline embedded in two markdown docs, (3) sync three stale files from a branch tip via `git diff`/copy, (4) add one explicit `HOME` precondition check to two scripts. None require a new library, package, or framework. The registry-comparison logic that R8/S2 exist to protect (`write_wrapper`'s heredoc, `install.sh:85-182`) is untouched by this phase and already covered by three adversarial fixture tests (I16/I17/I18) — cite, do not re-verify.

The one finding worth flagging loudly for planning: **`delegate-agy-4bp`'s own line-number citations for `install.sh` (`:223, :248, :249, :251`) are stale by a consistent +5-line offset** against the file as it reads today. The actual unguarded `$HOME` sites this session found by reading the current file are `install.sh:58, 228, 253, 254, 256` and `uninstall.sh:20, 60, 61` (uninstall.sh's citations were accurate). The ticket's site *count* (4 further sites in install.sh, matching D-06's fix) is still correct — only the line numbers drifted, most likely from unrelated edits landing in Phases 1–3. Plan tasks should cite the freshly-verified line numbers below, not the ticket's.

**Primary recommendation:** Implement D-01/D-03/D-05/D-06 in the sequence CONTEXT.md's canonical_refs already states (D-05 sync first, then D-03's SIGPIPE fix on the post-sync fallback block, D-01 and D-06 independently at any point), add one regression case per fix using the existing `_fresh_home`/`env -i` isolation harness already proven in `I8`/`I8b`/`I10`/`RB27`, and change nothing in `agy_bridge.sh`, `gemini_shim.sh`, or the `write_wrapper` heredoc.

## Architectural Responsibility Map

This phase has no web-tier architecture; it is a filesystem installer plus generated launcher scripts plus static documentation. The relevant "tiers" are execution contexts, not network layers.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| python3-absent guard before rc-alias patch (D-01) | Installer script (`install.sh`, install-time) | — | Runs once, on the installing user's host, before any wrapper is invoked; has no runtime/launcher-tier counterpart. |
| SIGPIPE-safe fallback one-liner (D-03/D-04) | Docs / copy-paste one-liner (executed in the *user's own interactive shell*, not by any project script) | — | The `.md` files are never executed by `install.sh` or any test harness directly — a user copy-pastes the fenced block into their terminal. D-04's test must therefore extract and execute the block itself to exercise this tier at all. |
| Stale content sync (D-05) | Docs (`*.md`) + plugin metadata (`plugin.json`) | — | Static text/version-string correctness; no executable logic. |
| HOME-unset precondition (D-06) | Installer script (`install.sh`/`uninstall.sh`, install-time) | — | Both scripts write into `$HOME`-relative paths; the precondition belongs at the same install-time tier as D-01, sited next to the existing refuse-root check. |
| Registry comparison-only read, exact-key match, bounded extraction window (R8/S2, criteria 1-3) | Generated wrapper (the heredoc `write_wrapper` emits into `~/.local/bin/{agy-bridge,gemini}`, evaluated at *every wrapper invocation*, not at install time) | Installer script (constructs the heredoc's literals at install time) | The comparison logic runs inside the wrapper the user's shell execs on every `gemini`/`agy-bridge` call — this is why S2's "false refusal" risk is box-wide (shim shadows `gemini` on PATH) rather than confined to one install run. Already shipped; this phase does not touch it. |

## Standard Stack

No new dependencies. Every mechanism this phase touches uses tools already present in the codebase's baseline:

| Tool | Version (verified this session) | Purpose | Already used for |
|------|-----------|---------|-------------------|
| `bash` | 5.3.15(1)-release [VERIFIED: `bash --version` on the dev host] | Installer/uninstaller/wrapper scripting | Entire `install.sh`/`uninstall.sh`/generated-wrapper surface |
| `python3` | 3.14.7 [VERIFIED: `python3 --version` on the dev host] | JSON parsing (`installed_plugins.json`-adjacent uses; the `.md` fallback's `claude plugin list --json` parse; the rc-alias `re.sub` patch) | `_agy_detect`, `_register_tokensave`, the rc-alias patch's `python3 - <<'PY'` block (`install.sh:239-246`), and both `.md` fallback one-liners |
| `shellcheck` | 0.11.0 [VERIFIED: `shellcheck --version` on the dev host] | Static lint (not currently wired into a CI/test target in this repo — no `Makefile`, no `package.json`; verified no such file exists) | Not currently invoked by `tests/run-tests.sh`; available on the dev host if the planner wants a lint pass, but adding one is out of this phase's locked scope (D-01–D-07 name no lint task) |

No `npm`/`pip`/`cargo` package is installed, imported, or referenced anywhere in this phase's scope. **Package Legitimacy Audit is not applicable** — see below.

### Alternatives Considered

Not applicable in the "swap this library for that one" sense CLAUDE.md's Alternatives-Considered mandate usually targets — this phase adds zero new dependencies. The one real design choice already made and locked by the user is D-03's mechanism selection (fix the SIGPIPE hazard *at its source* — eliminate `head` from the pipeline — vs. the ticket's own suggested `|| true` suppression). That tradeoff is recorded verbatim in User Constraints above; SOTA research below (State of the Art / Common Pitfalls) confirms it is the community-preferred fix, not merely a stylistic pick.

**Installation:** none — this phase ships no new package.

## Package Legitimacy Audit

Not applicable. This phase installs zero new npm/pip/cargo packages; every tool it touches (`bash`, `python3`, `git`, `sed`, `grep`) is a pre-existing system dependency already used elsewhere in `install.sh`/`uninstall.sh`. The Package Legitimacy Gate protocol is skipped per its own trigger condition ("Every phase that installs external packages").

## Architecture Patterns

### System Architecture Diagram

```
                    ┌─────────────────────────────────────────────┐
                    │  User's interactive shell (copy-pastes       │
                    │  /agy-setup's or /agy-uninstall's printed     │
                    │  one-liner)                                   │
                    └───────────────────┬───────────────────────────┘
                                         │ runs the fenced bash block
                                         ▼
                    ┌─────────────────────────────────────────────┐
                    │ D-03/D-04 scope: CLI fallback one-liner       │
                    │  (agy-setup.md / agy-uninstall.md, post-sync) │
                    │  claude plugin list --json                    │
                    │       │ (2>/dev/null)                         │
                    │       ▼                                       │
                    │  python3 -c '...print installPath...'          │
                    │       │ (D-03: NO trailing | head -1)          │
                    │       ▼                                       │
                    │  RESOLVED=...  →  case "$RESOLVED" in ... esac │
                    │       │ validates */agy-delegate/*/scripts/*   │
                    │       ▼                                       │
                    │  bash "$RESOLVED"  (install.sh or uninstall.sh)│
                    └───────────────────┬───────────────────────────┘
                                         ▼
                    ┌─────────────────────────────────────────────┐
                    │ install.sh (D-01/D-06 scope)                  │
                    │  1. refuse-root check                         │
                    │  2. D-06: HOME-unset precondition (NEW)        │
                    │  3. resolve PLUGIN_DIR, write both wrappers    │
                    │     (registry-comparison heredoc — UNCHANGED,  │
                    │      already covered by I16/I17/I18)           │
                    │  4. full-$PATH shadow scan + disclosure         │
                    │  5. D-01: python3 guard (NEW) → consent-gated   │
                    │     rc-alias patch loop (unchanged otherwise)   │
                    │  6. tokensave MCP registration (unchanged,      │
                    │     already python3-guarded via                │
                    │     _register_tokensave)                        │
                    │  7. bounded live-verify (unchanged, already     │
                    │     fixed by delegate-agy-lkg / RB28)            │
                    └───────────────────┬───────────────────────────┘
                                         ▼
                    ┌─────────────────────────────────────────────┐
                    │ ~/.local/bin/{agy-bridge,gemini} wrappers     │
                    │ (generated; registry-comparison-only read at  │
                    │  every invocation — untouched by this phase)  │
                    └─────────────────────────────────────────────┘
```

### Recommended Project Structure

No new files. This phase edits exactly the files CONTEXT.md's `<domain>` already names:
```
scripts/install.sh                        # D-01, D-06
scripts/uninstall.sh                       # D-06
.claude/commands/agy-setup.md              # D-03 (post-sync), D-05
.claude/commands/agy-uninstall.md          # D-03 (post-sync), D-05
.claude-plugin/plugin.json                 # D-05
tests/run-tests.sh                         # new regression cases for D-01, D-04, D-06
```

### Pattern 1: Fail-open on a missing optional dependency, warn to stderr, continue

**What:** When an optional external binary (`python3`) is absent, the script prints one `WARNING: ...` line to stderr naming the specific feature being skipped, returns/continues rather than aborting, and leaves everything already written on disk intact.
**When to use:** D-01's python3 guard for the rc-alias-patch loop — this is the exact template.
**Example (current, already-shipped instance at `install.sh:279-283`):**
```bash
# Source: install.sh:279-283 (read this session)
_register_tokensave() {
    if ! command -v python3 >/dev/null 2>&1; then
        echo "WARNING: python3 not found — skipping tokensave registration (fail-open)." >&2
        return 0
    fi
```
D-01's new guard must mirror this shape ("naming the alias-patch feature specifically" per the decision), sited once before `install.sh`'s `for RC in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_aliases"; do` loop (currently at line 228), not per-iteration.

### Pattern 2: Fix a SIGPIPE-hazard class at its source, not by suppressing the resulting exit code

**What:** When a pipeline under `set -o pipefail` truncates its own upstream producer early (`... | head -N`), the SOTA fix is to make the producer stop emitting on its own (so the truncating consumer is never spawned), not to catch/suppress the resulting SIGPIPE (141) exit code with `|| true`.
**When to use:** D-03's fix for the `claude plugin list --json | python3 -c '...' | head -1` pipeline.
**Confirmed against current 2026 community guidance (WebSearch, `docs.kodekloud.com`/multiple sources — see Sources):** "the accepted best practice is to either avoid `pipefail` for pipelines that intentionally truncate output early (like `... | head`), or explicitly detect and suppress the SIGPIPE (141) exit code rather than broadly ignoring all errors." D-03's approach (make the producer — the python3 one-liner — select only the first match itself) removes the truncating consumer from the pipeline entirely, which is the strictly cleaner of the two accepted options and matches this project's own Phase 2 D-08 precedent.
**Current code being fixed (post-sync content, verified via `git show fix/agy-bridge-resilience:.claude/commands/agy-setup.md`, lines 53-63):**
```bash
# Source: fix/agy-bridge-resilience:.claude/commands/agy-setup.md:54-62
#         (byte-identical block also present in agy-uninstall.md:45-53)
RESOLVED="$(claude plugin list --json 2>/dev/null \
  | python3 -c 'import sys,json;[print(x.get("installPath","")) for x in json.load(sys.stdin) if x.get("id","").startswith("agy-delegate@")]' \
  | head -1)/scripts/install.sh"; \
case "$RESOLVED" in \
  */agy-delegate/*/scripts/install.sh) [[ -f "$RESOLVED" ]] \
    && bash "$RESOLVED" \
    || echo "ERROR: resolved installer '$RESOLVED' is not a regular file — is agy-delegate installed?" >&2 ;; \
  *) echo "ERROR: refusing to run '$RESOLVED' — does not match */agy-delegate/*/scripts/install.sh" >&2 ;; \
esac
```
D-03's fix removes `| head -1` and rewrites the python3 `-c` argument to print only the first match (index `[0]` of the filtered list, an early `break`, or a `next(..., "")`-style single expression — Claude's Discretion, "subject to producing byte-identical output to the current `| head -1` behavior on a single-match input"). The empty-match case (no `agy-delegate@...` entry) must still produce empty output (matching `head -1` on an empty stream), not raise `IndexError`/`StopIteration` — whichever rewrite is chosen must guard that case explicitly.

### Pattern 3: Judge state by reading files, not the commit graph

**What:** When a merge/revert history is complicated (as `master`'s 1.6.2 hold-then-remerge is — see PROJECT.md `:61`), determine current file state by reading the file directly or diffing against the source-of-truth ref, never by inferring from commit messages.
**When to use:** D-05's k0f sync, and — as this session's own line-number-drift finding shows — *any* task that cites a specific line number from a ticket filed more than a few commits ago.
**Source:** `.planning/PROJECT.md:61` [VERIFIED: PROJECT.md:61] — `"Judge state by reading files, never by the commit graph."` The verify command named in the ticket itself is exactly this pattern: `git diff HEAD fix/agy-bridge-resilience -- .claude-plugin/plugin.json .claude/commands/agy-setup.md .claude/commands/agy-uninstall.md` should be empty once D-05 lands.

### Pattern 4: Marker-anchored block extraction for regression tests

**What:** The suite already has a precedent for extracting a delimited block from a file via `sed -n '/^START_MARKER$/,/^END_MARKER$/p'` rather than hardcoding line numbers, specifically because line numbers drift.
**When to use:** D-04's fenced-bash-block extraction from the `.md` files.
**Example (existing, `tests/run-tests.sh:1675-1677`):**
```bash
# Source: tests/run-tests.sh:1675-1677 (read this session)
_rb_extract() {
    sed -n '/^# --- BEGIN run_bounded ---$/,/^# --- END run_bounded ---$/p' "$1"
}
```
The `.md` files carry no explicit `BEGIN`/`END` sentinel comments (they are user-facing docs, not scripts), so D-04's extractor cannot copy `_rb_extract` verbatim — it must anchor on the fenced-code-block delimiters (```` ```bash ```` / ```` ``` ````) plus a content signature, because each `.md` file has **six** fenced bash blocks post-sync and only one of them (the one starting `RESOLVED="$(claude plugin list...`) is the SIGPIPE-hazard block. An anchor like `awk '/^```bash$/{n++} n==N,/^```$/' ` (extract the Nth fenced block) is brittle to doc edits reordering blocks; anchoring on the first line's content (`/^RESOLVED="\$\(claude plugin list/,/^esac$/`, both ends content-anchored, mirroring `_rb_extract`'s "anchored at both ends" discipline) is the safer choice and does not require a magic block index.

### Anti-Patterns to Avoid

- **Guarding `command -v python3` per-loop-iteration instead of once:** explicitly overridden by D-01 — "Checking an unchanging fact on every matched rc file is redundant."
- **Suppressing SIGPIPE with `|| true` on the `RESOLVED=` assignment:** explicitly overridden by D-03 in favor of removing the hazard at its source.
- **Adding a `${HOME:-/nonexistent}` fallback instead of a hard precondition:** explicitly forbidden by D-06 — these scripts write into `$HOME`-relative paths, so a silent redirect would install into a location the user never sees. The ticket's own bead-lock states this: `Task [explicit HOME precondition check in both scripts, sited with refuse-root] ! [no ${HOME:-/nonexistent} fallback]`.
- **Hand-rewriting the k0f-affected files instead of syncing from the branch tip:** explicitly overridden by D-05 — a hand-rewrite risks reintroducing a divergence from the branch's already-reviewed content.
- **Citing ticket line numbers without re-reading the current file:** this session found `delegate-agy-4bp`'s `install.sh` line citations stale by +5 lines (see Summary and Common Pitfalls). Any plan task must cite the line numbers verified in this document, not the ticket body.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON parsing of `claude plugin list --json` output | A hand-written string/regex JSON scraper in bash | `python3`'s stdlib `json` module (already the pattern in both `.md` files and in `install.sh`'s `_agy_detect`/`_register_tokensave`) | bash has no native JSON parser; every existing JSON-touching site in this codebase already uses `python3 -c '...json...'` — D-03's fix keeps this pattern, it only removes the trailing `head -1`. |
| Detecting whether a required env var is set before using it | A custom "try and catch the error" pattern (letting `set -u` abort and grep-matching the resulting message) | The direct `[[ -n "${HOME:-}" ]] || { ...; exit 1; }` precondition D-06 already specifies | This is the SOTA-confirmed idiom (see Common Pitfalls / State of the Art below) — `: "${HOME:?msg}"` is the terser POSIX-portable equivalent but D-06's ticket already locked the `[[ ]]`-based form, which is also this repo's established style (`[[ ]]` not `[ ]`, per `install.sh`'s own header comment: "every expansion quoted; `[[ ]]` not `[ ]`"). |

**Key insight:** every problem this phase touches already has an established, working pattern *somewhere else in this same file*. The work is copying that pattern to a new site, not designing a new one.

## Common Pitfalls

### Pitfall 1: Stale ticket line-number citations
**What goes wrong:** A plan task cites `install.sh:223` (from `delegate-agy-4bp`'s body) expecting to find an unguarded `$HOME` expansion there; the current line 223 is `echo "  fish:      fish_add_path ~/.local/bin" >&2` — no `$HOME` at all.
**Why it happens:** The ticket was filed 2026-08-19; Phases 1–3's work landed additional lines in `install.sh` since, shifting everything below by a consistent +5.
**How to avoid:** Always re-grep/re-read the current file before writing a task's line-number reference; this document's line numbers were verified this session (`grep -n '\$HOME' scripts/install.sh scripts/uninstall.sh`, cross-checked against a full `Read` of both files).
**Warning signs:** A `sed -i` or line-anchored `Edit` targeting a line number pulled straight from a ticket body without a preceding read-and-confirm step.

### Pitfall 2: `head -1` under `set -o pipefail` aborting a script that "looks fine" in interactive testing
**What goes wrong:** `producer | head -1` works perfectly when run interactively (most shells are not `-e` by default, and small outputs mean the producer often finishes writing before `head` closes the pipe) but intermittently aborts a `set -euo pipefail` script when the producer's output crosses a buffering/timing threshold — exactly what `delegate-agy-4vy`'s own ticket text calls "mostly theoretical... interactive shells are not -e by default."
**Why it happens:** `head -N` closes its stdin after reading N lines; if the producer (here, `python3`) is still writing when that close happens, the producer receives `SIGPIPE`, exits 141, and `pipefail` propagates that as the pipeline's exit status.
**How to avoid:** D-03's fix (make the producer itself stop after the first match, never spawning `head`) — confirmed as the community-preferred approach in this session's SOTA search (see Sources).
**Warning signs:** A pipeline ending in `| head -N` or `| tail -N` inside any script carrying `set -o pipefail`, especially one whose producer can emit more than one line.

### Pitfall 3: `set -u` turning an unset `$HOME` into an opaque bash-internals message
**What goes wrong:** `env -i PATH=/usr/bin:/bin bash scripts/install.sh` (or any environment lacking `HOME` — `systemd` units without `User=`, container entrypoints, some CI runners) crashes with `install.sh: line 58: HOME: unbound variable` — a message that names bash's own mechanism, not the actual precondition the script needs.
**Why it happens:** `set -u`/`set -o nounset` treats any reference to an unset variable as a fatal error the instant it is expanded — `BIN_DIR="$HOME/.local/bin"` expands `$HOME` before the script has said anything about why it needs it.
**How to avoid:** D-06's explicit precondition, checked immediately after refuse-root and before the first `$HOME` use.
**Warning signs:** Any `"$HOME/..."` or `"${HOME}/..."` expansion (no `:-` default) appearing before an explicit `HOME` presence check in a `set -u` script. Note: the *generated wrapper* heredoc already guards this correctly via `"${HOME:-/nonexistent}"` (see `install.sh:156`, `RB27`/`RB29` tests) — that pattern is deliberately **not** what D-06 wants for `install.sh`/`uninstall.sh` themselves, because those two scripts must refuse outright rather than silently write into `/nonexistent`.

## Code Examples

### D-01 site — current code, exact current line numbers (verified via `Read` this session)

```bash
# Source: scripts/install.sh:226-250 (current master, read this session)
# ── consent-gated recursive-gemini rc alias patch (dry-run unless flag) ───────
if [[ -n "$_real_gemini" ]]; then
    for RC in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_aliases"; do
        [[ -f "$RC" ]] || continue
        if grep -qE "^alias gemini='[^']* gemini'\$" "$RC" 2>/dev/null; then
            old_line="$(grep "^alias gemini=" "$RC" || true)"
            echo "Recursive 'gemini' alias found in $RC:"
            echo "  $old_line"
            if [[ "${AGY_SETUP_PATCH_ALIASES:-0}" != "1" ]]; then
                echo "  (dry-run) set AGY_SETUP_PATCH_ALIASES=1 to rewrite it to call $_real_gemini."
                continue
            fi
            cp -f "$RC" "$RC.bak-agy-$(_ts)"
            python3 - "$RC" "$_real_gemini" <<'PY'
import re, sys
rc, real = sys.argv[1], sys.argv[2]
txt = open(rc).read()
out = re.sub(r"^(alias gemini='.*) gemini'$",
             lambda m: m.group(1) + ' ' + real + "'", txt, flags=re.M)
open(rc, 'w').write(out)
PY
            echo "Patched $RC (backup written)."
        fi
    done
fi
```
Note: CONTEXT.md's own citation ("around line 227-239") is close but not exact against the file as it reads today — the block above spans 226-250; the `python3 -` invocation the guard must protect is at line 239.

### D-06 site — exact insertion points (verified this session)

```bash
# Source: scripts/install.sh:36-41 (read this session) — insertion point for the new precondition
if [[ "${EUID:-$(id -u)}" -eq 0 || -n "${SUDO_USER:-}" ]]; then
    echo "ERROR: refusing to run as root (or via sudo). Run as your normal user." >&2
    exit 1
fi
# <-- D-06's HOME precondition goes here, before line 42's plugin-root resolution
#     and BEFORE line 58's first $HOME use: BIN_DIR="$HOME/.local/bin"
```
```bash
# Source: scripts/uninstall.sh:14-19 (read this session) — insertion point for the new precondition
if [[ "${EUID:-$(id -u)}" -eq 0 || -n "${SUDO_USER:-}" ]]; then
    echo "ERROR: refusing to run as root (or via sudo). Run as your normal user." >&2
    exit 1
fi
# <-- D-06's HOME precondition goes here, before line 20's first $HOME use:
#     BIN_DIR="$HOME/.local/bin"
```
**Every unguarded `$HOME` site D-06 must precede, current line numbers (verified via `grep -n '\$HOME' scripts/install.sh scripts/uninstall.sh` this session, cross-checked against a full file `Read`):**
- `install.sh:58` — `BIN_DIR="$HOME/.local/bin"`
- `install.sh:228` — `for RC in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_aliases"; do` (3 expansions on one line)
- `install.sh:253` — `AGY_MCP_CFG="$HOME/.gemini/antigravity-cli/mcp_config.json"`
- `install.sh:254` — `HINT_DIR="$HOME/.config/agy-delegate"`
- `install.sh:256` — `TOKENSAVE_BIN="$(command -v tokensave 2>/dev/null || echo "$HOME/.local/bin/tokensave")"`
- `uninstall.sh:20` — `BIN_DIR="$HOME/.local/bin"`
- `uninstall.sh:60` — `AGY_MCP_CFG="$HOME/.gemini/antigravity-cli/mcp_config.json"`
- `uninstall.sh:61` — `HINT="$HOME/.config/agy-delegate/config.json"`

(`install.sh:222`'s `\$HOME` is escaped inside a double-quoted `echo` string printed for the user to paste into their own rc file — it is never expanded by `install.sh` itself and is not a crash site.)

### D-03/D-04 site — post-sync fenced block, exact line numbers (verified via `git show fix/agy-bridge-resilience:...`)

- `agy-setup.md`: fenced block at post-sync lines **53-63**; the block immediately preceding it (path-lookup instructions) is at lines 32-51.
- `agy-uninstall.md`: fenced block at post-sync lines **44-54**; preceding instructions at lines 23-42.

Both blocks are byte-identical in shape (only `install.sh`/`uninstall.sh` and the `installPath` filter target differ — both filter on `x.get("id","").startswith("agy-delegate@")`, since one plugin ships both scripts).

### Existing regression-test building blocks (verified via `Read` of `tests/run-tests.sh`)

**Isolation harness (`tests/run-tests.sh:3668-3684`):**
```bash
# Source: tests/run-tests.sh:3668-3684
_fresh_home() {
    local h; h="$(mktemp -d "$SANDBOX/ihome.XXXXXX")"
    mkdir -p "$h/.local/bin" "$h/bin"
    cp "$HERE/fake-agy.sh" "$h/bin/agy"
    chmod +x "$h/bin/agy"
    _cc_fixtures_beside "$h/bin"
    printf '%s' "$h"
}

_install_in() {
    local h="$1"; shift
    env -i HOME="$h" PATH="$h/bin:$h/.local/bin:/usr/bin:/bin" \
        AGY_PLUGIN_DIR="$ROOT" "$@" \
        bash "$INSTALL" > "$SANDBOX/last-install.log" 2>&1
}
```

**D-01's nearest existing analog — "python3 absent, install completes, feature fails open" (`I10`, `tests/run-tests.sh:3862-3881`):**
```bash
# Source: tests/run-tests.sh:3862-3881
IH="$(_fresh_home)"
mkdir -p "$IH/.gemini/antigravity-cli" "$IH/nopy"
for b in bash cat grep sed date mktemp mkdir rm mv cp chmod ls readlink id printf command env; do
    _src="$(command -v "$b" 2>/dev/null)"; [[ -n "$_src" ]] && ln -sf "$_src" "$IH/nopy/$b" 2>/dev/null || true
done
cp "$HERE/fake-agy.sh" "$IH/nopy/agy"; chmod +x "$IH/nopy/agy"
_cc_fixtures_beside "$IH/nopy"
printf '#!/bin/sh\nexit 0\n' > "$IH/nopy/tokensave"; chmod +x "$IH/nopy/tokensave"
printf '%s\n' '{"mcpServers":{}}' > "$IH/.gemini/antigravity-cli/mcp_config.json"
env -i HOME="$IH" PATH="$IH/nopy" AGY_PLUGIN_DIR="$ROOT" \
    AGY_SETUP_REGISTER_TOKENSAVE=1 \
    bash "$INSTALL" > "$SANDBOX/last-install.log" 2>&1; I10_RC=$?
if [[ "$I10_RC" -eq 0 && -f "$IH/.local/bin/agy-bridge" ]] \
   && ! grep -q '"tokensave"' "$IH/.gemini/antigravity-cli/mcp_config.json" \
   && grep -qi 'python3 not found' "$SANDBOX/last-install.log"; then
```
`$IH/nopy` is a curated `PATH` directory that symlinks every tool `install.sh` actually needs **except** `python3` — the exact recipe D-01's new test must reuse (whitelist approach, not a blocklist, so a future new `command -v` call in `install.sh` fails loud in this test instead of silently finding the real host's `python3`).

**D-01's nearest existing analog for the alias-patch trigger itself — "flag set, real recursive alias present" (`I8b`, `tests/run-tests.sh:3810-3825`):**
```bash
# Source: tests/run-tests.sh:3810-3825
IH="$(_fresh_home)"
mkdir -p "$IH/otherbin"
printf '#!/bin/sh\necho real\n' > "$IH/otherbin/gemini"; chmod +x "$IH/otherbin/gemini"
printf "%s\n" "alias gemini='GEMINI_API_KEY=x gemini'" > "$IH/.bashrc"
env -i HOME="$IH" PATH="$IH/bin:$IH/otherbin:$IH/.local/bin:/usr/bin:/bin" \
    AGY_PLUGIN_DIR="$ROOT" AGY_SETUP_PATCH_ALIASES=1 \
    bash "$INSTALL" > "$SANDBOX/last-install.log" 2>&1
```
D-01's new case is these two patterns composed: `I8b`'s setup (real `gemini` in `$otherbin`, a matching recursive alias in `$IH/.bashrc`, `AGY_SETUP_PATCH_ALIASES=1`) run against `I10`'s `$IH/nopy`-style python3-absent `PATH`, then asserting (per the ticket's own acceptance text) `install.sh` exits 0, both wrappers exist, a `WARNING:` naming the alias-patch feature is on stderr, and `$IH/.bashrc` is byte-identical to its pre-run content (`cksum`, `I8`'s own no-op-detection idiom at `:3799-3804`).

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `producer \| head -1` inside a `set -o pipefail` script, tolerated because interactive shells rarely hit the race | Make the producer stop emitting after its first match itself; never spawn a truncating consumer | Not a version-dated language change — this is a stable, long-established `bash`/POSIX pipe-semantics gotcha (SIGPIPE=141 under `pipefail`); confirmed still the consensus 2026 guidance via WebSearch this session | D-03's fix eliminates the hazard class rather than papering over one exit code |
| Letting `set -u` surface bash's own "unbound variable" message for a missing required env var | An explicit, named precondition check (`[[ -n "${VAR:-}" ]] \|\| { echo "ERROR: ..."; exit 1; }`) before first use | Same — stable bash idiom, not a recent change; confirmed via WebSearch this session (`: "${HOME:?msg}"` is the terser POSIX form; this repo's own style already prefers `[[ ]]` and D-06 locks the `[[ ]]` form) | D-06's fix turns an opaque bash-internals crash into a stated, actionable error |

**Deprecated/outdated:** nothing in this phase's scope deprecates a prior approach within the codebase — all four fixes add a guard that was simply missing, they do not replace a previously-correct-but-now-obsolete pattern.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | D-01's guard should be placed structurally as "check `_real_gemini` non-empty, then a single `command -v python3` check, then the `for RC in ...` loop" — i.e., the guard fires once per `install.sh` run whenever a real shadowed `gemini` was found, *independent of* whether `AGY_SETUP_PATCH_ALIASES=1` was actually set or whether any rc file has a recursive alias to patch. This is one plausible literal reading of D-01's text ("immediately after the `AGY_SETUP_PATCH_ALIASES=1` gate is confirmed true and before the `for RC in ...` loop starts") but the current code structurally checks the `AGY_SETUP_PATCH_ALIASES` env var *inside* the loop, per matched RC file (`install.sh:234`) — there is no single point today where "the gate is confirmed true" and the loop has not yet started, unless the flag check is itself hoisted out of the loop as part of this fix. | Decisions / Code Examples (D-01 site) | If the planner reads D-01 as requiring the flag-check to be hoisted too (not just the python3 guard), the diff shape changes materially — worth a one-line clarifying question at plan-review time rather than guessing silently. Flagged as an Open Question below rather than resolved here, since resolving it is an implementation decision, not a research finding. |

**All other claims in this document are `[VERIFIED]` (read directly this session) or `[CITED]` (WebSearch results cross-referencing stable, non-controversial bash semantics) — no other `[ASSUMED]` claims.**

## Open Questions

1. **Does D-01's python3 guard need the `AGY_SETUP_PATCH_ALIASES` flag-check hoisted out of the loop, or can it be evaluated once right after `if [[ -n "$_real_gemini" ]]; then` regardless of the flag's value?**
   - What we know: D-01's text names two spatial anchors ("immediately after the `AGY_SETUP_PATCH_ALIASES=1` gate is confirmed true" AND "before the `for RC in ...` loop starts") that do not currently coincide at one point in the code — the flag is checked per-RC-file, inside the loop, today.
   - What's unclear: whether "the gate is confirmed true" means the *existing* per-file check (implying the guard would need to move inside a restructured loop after all, contradicting "before the loop starts"), or whether D-01 intends a *new*, hoisted flag check as part of this same fix.
   - Recommendation: the simplest reading that satisfies both anchors and preserves the existing dry-run advisory message (still printed per matched RC file when the flag is off) is: place the `command -v python3` guard right after `if [[ -n "$_real_gemini" ]]; then` (line 227), gated on `[[ "${AGY_SETUP_PATCH_ALIASES:-0}" == "1" ]]` evaluated at that same point (a *read* of the flag, not a restructure of where it's used later) — i.e., add one `if [[ "${AGY_SETUP_PATCH_ALIASES:-0}" == "1" ]] && ! command -v python3 >/dev/null 2>&1; then <warn>; fi` immediately before the loop, and have the loop's existing per-file `python3 -` invocation skip when that warning fired (a one-flag-variable carry). This keeps the dry-run advisory intact for every RC file regardless of python3 presence, and fires the new warning exactly once per `install.sh` run. Confirm this reading with the user or leave the exact micro-structure to the executing agent, since either reading satisfies the ticket's stated acceptance test (I8b-style scenario, exit 0, wrappers written, one warning, rc file untouched).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `bash` | All of `install.sh`/`uninstall.sh`/tests | ✓ [VERIFIED: `bash --version` this session] | 5.3.15(1)-release | — |
| `python3` | D-01's guarded feature, D-03's fallback one-liner, D-04's test fixture, existing `_agy_detect`/`_register_tokensave` | ✓ [VERIFIED: `python3 --version` this session] | 3.14.7 | Every python3-dependent feature in this phase's scope is already designed to fail open when absent — D-01 adds the one remaining missing guard, it does not introduce a new hard dependency. |
| `shellcheck` | Not required by any locked decision in this phase | ✓ [VERIFIED: `shellcheck --version` this session] | 0.11.0 | Not wired into `tests/run-tests.sh` or any CI config found in this repo (no `Makefile`, no `.github/workflows` checked — out of this phase's scope to add). |
| `git` | D-05's content sync (`git diff`/`git show` against `fix/agy-bridge-resilience`) | ✓ (used throughout this session) | — | — |

No missing dependency blocks this phase.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Hand-rolled bash assertion harness — no third-party test framework. `ok`/`bad` counter functions, `PASS=$PASS FAIL=$FAIL` summary, `exit 0`/`exit 1` [VERIFIED: `tests/run-tests.sh:88-101, 4918-4924`] |
| Config file | none — the harness is the single file `tests/run-tests.sh` (4924 lines) [VERIFIED: `wc -l tests/run-tests.sh`] |
| Quick run command | Not applicable — the suite has no fast subset selector; a targeted manual run during development is done by commenting out unrelated sections or `sed`-extracting a range, per this project's existing convention (no `--filter`/`-k` flag exists in the harness) |
| Full suite command | `bash tests/run-tests.sh` (run from repo root; the script self-resolves `ROOT` via `BASH_SOURCE`) [VERIFIED: `tests/run-tests.sh:30-31`] |

**Current baseline, run to completion this session:** `PASS=153 FAIL=0` [VERIFIED: `bash tests/run-tests.sh`, run in full this session — the full 4924-line suite completes clean]. This supersedes STATE.md's `PASS=145 FAIL=0` figure (dated 2026-08-20, before Phase 3's later plans and RB29/CC01-CC06 additions landed) — cite `153` as the pre-phase-4 baseline in the plan, and confirm the same-or-higher count (`0` failures) after each task. The suite's own header comment states "SUITE STATE: fully GREEN. New cases must keep the suite green; no assertion may be weakened to pass early" [VERIFIED: `tests/run-tests.sh:26-27`].

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| R8 | Registry read stays comparison-only (exact key match, no cross-marketplace match, install-time-literal repin construction) | integration (isolated `env -i` install + wrapper invocation) | Already covered — no new command needed | ✅ `tests/run-tests.sh:3980-4105` (I16) |
| S2 | Registry-schema-change survival (bounded extraction window, no cross-plugin misattribution) | integration | Already covered — no new command needed | ✅ `tests/run-tests.sh:4107-4194` (I17) |
| delegate-agy-4xn (D-01/D-02) | `AGY_SETUP_PATCH_ALIASES=1` + python3-absent → exits 0, wrappers written, warning on stderr, rc file untouched | integration (`_fresh_home` + `nopy`-style `PATH`) | New case — run via `bash tests/run-tests.sh` (no standalone command; whole-suite run is the harness's only mode) | ❌ Wave 0 (new case, composing `I8b` + `I10` patterns above) |
| delegate-agy-4vy (D-03/D-04) | Fenced fallback block in both `.md` files reaches its validating `case` under `bash -euo pipefail -c` against a multi-match fake `claude`, without a SIGPIPE abort | integration (doc-block extraction + execution against a fake `claude` stub) | New case — run via `bash tests/run-tests.sh` | ❌ Wave 0 (new extraction helper + new case; no prior `.md`-execution test exists in this suite) |
| delegate-agy-k0f (D-05) | `git diff HEAD fix/agy-bridge-resilience -- .claude-plugin/plugin.json .claude/commands/agy-setup.md .claude/commands/agy-uninstall.md` is empty | manual/CI verification command (not a `run-tests.sh` case — the ticket's own "Verify" section names this exact `git diff` as the acceptance check) | `git diff HEAD fix/agy-bridge-resilience -- .claude-plugin/plugin.json .claude/commands/agy-setup.md .claude/commands/agy-uninstall.md` (expect empty output) | N/A — this is a content-sync fix verified by diff, not by a new suite assertion. `jq -r .version .claude-plugin/plugin.json` should read `1.6.2` (per the ticket's own second verify line). |
| delegate-agy-4bp (D-06) | `install.sh`/`uninstall.sh` run under `env -i` with `HOME` unset → stated `ERROR: HOME is not set...` on stderr, exit 1, no `unbound variable` message | integration (`env -i PATH=... bash install.sh`, no `HOME` key at all) | New case(s) — run via `bash tests/run-tests.sh` | ❌ Wave 0 (new case(s); the existing `RB27`/`RB29` HOME-unset cases exercise `agy_bridge.sh`/`gemini_shim.sh`/the *generated wrapper*, not `install.sh`/`uninstall.sh` themselves — this is a genuinely new gap, not a duplicate) |

### Sampling Rate
- **Per task commit:** `bash tests/run-tests.sh` (the harness has no fast subset — every commit that touches `install.sh`/`uninstall.sh`/the two `.md` files should run the full suite; it is the project's only automated gate and is fast enough to run per-commit per its own "fully GREEN" convention)
- **Per wave merge:** `bash tests/run-tests.sh` (same command — no distinct "full suite" superset exists)
- **Phase gate:** Full suite green (`PASS=N FAIL=0`) before `/gsd:verify-work`, plus D-05's `git diff` emptiness check run manually (it is not, and should not become, a `run-tests.sh` assertion — it is a one-time content-sync verification, not a runtime behavior).

### Wave 0 Gaps
- [ ] New `I`-prefixed (or `I8c`/`I19`-style) case in `tests/run-tests.sh` for D-01: composes the `I8b` (real recursive alias + `AGY_SETUP_PATCH_ALIASES=1`) and `I10` (`nopy`-style python3-absent `PATH`) patterns already in the suite — no new fixture files needed, both source patterns already exist inline.
- [ ] New case(s) in `tests/run-tests.sh` for D-06: `env -i PATH=<curated dir> bash "$INSTALL"` / `bash "$UNINSTALL"` with **no `HOME` key at all** in the environment (distinct from every existing case, which always sets `HOME="$IH"`); assert stderr contains the exact D-06 message and stdout/stderr never contains `unbound variable`; assert `rc=1`. Discretion: one shared case parameterized over `install.sh`/`uninstall.sh`, or two separate cases — match the suite's existing per-script convention (`I6`/`I6b` is the precedent for "same behavior, two scripts, two IDs").
- [ ] New extraction helper + case(s) in `tests/run-tests.sh` for D-04: a `_md_extract`-style function (see Pattern 4 above) that pulls the SIGPIPE-hazard fenced block out of `agy-setup.md`/`agy-uninstall.md` by content anchor, plus a fake `claude` CLI stub (inline `printf '#!/bin/sh\n...'` heredoc, matching the suite's established inline-fake convention used for `tokensave` in `I9`/`I9b`/`I10`, rather than a new `tests/fixtures/` file — Claude's Discretion per CONTEXT.md, but the inline convention is what every other one-off CLI fake in this suite already does) emitting a JSON array with **two or more** `agy-delegate@...`-prefixed `id` entries. Run the extracted block via `bash -euo pipefail -c "$BLOCK"` with the fake `claude` on `PATH`; assert the process does not exit 141 and that stderr/stdout show the block reached its `case` statement (either the `bash "$RESOLVED"` arm or one of the two `echo "ERROR: ..."` arms — reaching either is "not aborting").
- [ ] No new test-framework install needed — the harness is self-contained bash; `bash`/`python3` are the only interpreters the new cases need, both already verified present.

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Not applicable — no auth surface in an installer script |
| V3 Session Management | no | Not applicable |
| V4 Access Control | no | Not applicable — refuse-root is a privilege-*avoidance* check, not access control over resources |
| V5 Input Validation | yes | `install.sh` already validates the registry-supplied version string against `^[0-9]+(\.[0-9]+)*$` before using it to construct a repin path (`install.sh:167`, unchanged by this phase); the `.md` fallback already validates `$RESOLVED` against `*/agy-delegate/*/scripts/install.sh` before executing it (`case` statement, unchanged shape, only the upstream `head -1` truncation is removed by D-03) |
| V6 Cryptography | no | Not applicable |
| V10 Malicious Code / Untrusted Data | yes | The core security property this phase's untouched code (`write_wrapper`) already enforces and this phase's fixes must not weaken: no registry-supplied string (`installPath`, a version string that fails the numeric regex) ever reaches `exec` or is printed as a command to run (`install.sh:163-172`, `WRAP` heredoc). D-01/D-03/D-05/D-06 touch no code on this path. |
| V12 Files and Resources | yes | D-06's precondition prevents `install.sh`/`uninstall.sh` from writing into an unintended path derived from an unset `$HOME` (the exact failure mode a `${HOME:-/nonexistent}` fallback would have produced, which D-06 explicitly forbids); the non-clobber/backup logic for pre-existing files at the wrapper destinations (`is_our_wrapper`, `write_wrapper`'s backup branch) is unchanged. |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Registry-supplied path/version string reaching `exec` or a printed re-run command (path/command injection via a hostile or malformed `installed_plugins.json`) | Tampering / Elevation of Privilege | Exact-key match + numeric-only version regex before use in a re-run command (already shipped, I16/I17/I18-covered; this phase does not touch it) |
| SIGPIPE-driven early abort of a doc-published one-liner leaving a partially-assigned `$RESOLVED` that a user might copy-paste and re-run blind | Denial of Service (of the install flow itself, not a security compromise, but a fail-open→fail-broken regression) | D-03: eliminate the hazard at its source rather than suppress the resulting exit code, so the validating `case` (the actual security control — path-pattern validation before `bash`-ing an arbitrary string) always runs |
| Unset `$HOME` causing an installer to write into an unintended/predictable path (a `${HOME:-/tmp}`-style fallback would be attacker-predictable on a shared host) | Tampering | D-06 refuses outright rather than falling back to a guessable default path — this is the security-relevant reason the ticket explicitly forbids a `${HOME:-/nonexistent}` fallback, beyond the stated UX rationale |

## Sources

### Primary (HIGH confidence — read directly this session)
- `scripts/install.sh` (full file, 389 lines) — read via `Read`
- `scripts/uninstall.sh` (full file, 104 lines) — read via `Read`
- `.claude/commands/agy-setup.md`, `.claude/commands/agy-uninstall.md` (both current-master and `fix/agy-bridge-resilience` branch-tip versions) — read via `Read` and `git show`
- `.claude-plugin/plugin.json` (both versions) — read via `Read` and `git show`
- `tests/run-tests.sh` (targeted ranges: 1-100, 1660-1700, 3660-4430, 4880-4924) — read via `Read`
- `.planning/phases/04-installer-and-launcher-surface/04-CONTEXT.md`, `.planning/REQUIREMENTS.md`, `.planning/STATE.md`, `.planning/ROADMAP.md` (Phase 4 section), `.planning/PROJECT.md:61` — read via `Read`/`awk`
- `bd show delegate-agy-4xn`, `delegate-agy-4vy`, `delegate-agy-k0f`, `delegate-agy-4bp` — read via `bd show`
- `git diff HEAD fix/agy-bridge-resilience -- .claude-plugin/plugin.json .claude/commands/agy-setup.md .claude/commands/agy-uninstall.md` — run this session, full diff captured
- `bash --version`, `python3 --version`, `shellcheck --version` — run this session on the dev host

### Secondary (MEDIUM confidence — WebSearch cross-referencing stable bash semantics, no single canonical spec page)
- [Pipefail - KodeKloud](https://notes.kodekloud.com/docs/Advanced-Bash-Scripting/Streams/Pipefail/page) — SIGPIPE/pipefail interaction
- [Prevent Exit When Receiving SIGPIPE with Pipefail Set - Relentless Coding](https://blog.vandenakker.xyz/posts/prevent-exit-when-sigpipe-received-and-pipefail-set/)
- [Re: pipefail with SIGPIPE/EPIPE (bug-bash mailing list)](https://lists.gnu.org/archive/html/bug-bash/2017-03/msg00179.html)
- [How to Fix 'Broken Pipe' Errors in Bash Pipelines - oneuptime.com](https://oneuptime.com/blog/post/2026-01-24-bash-broken-pipe/view)
- [Bash Scripting Best Practices for Reliable Automation - oneuptime.com](https://oneuptime.com/blog/post/2026-02-13-bash-best-practices/view) — `check_dependencies()`/`die()` pattern, required-env-var validation
- [5 Methods to Check If Environment Variable is Set in Bash - LinuxSimply](https://linuxsimply.com/bash-scripting-tutorial/variables/usage/check-if-environment-variable-is-set/)

### Tertiary (LOW confidence)
None used — every claim above is either read-verified this session or cross-referenced against multiple WebSearch results describing long-stable, non-controversial bash semantics.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependency; every tool version confirmed on the actual dev host this session.
- Architecture: HIGH — every code site quoted was read directly this session; the one open question (D-01's exact insertion structure) is called out explicitly rather than guessed silently.
- Pitfalls: HIGH — the stale-line-number pitfall is a first-hand finding from this session (ticket vs. current file diff), not a generic claim; the SIGPIPE and unset-HOME pitfalls are cross-referenced against current WebSearch guidance.

**Research date:** 2026-08-21
**Valid until:** Line-number citations in this document are valid only against `master` as of this session's `HEAD`; any further commits to `scripts/install.sh`/`scripts/uninstall.sh` before this phase executes should trigger a re-read, not a re-use of these numbers (see Pitfall 1). Non-line-number findings (SOTA patterns, existing test conventions) are stable for the life of this milestone (30+ days).
