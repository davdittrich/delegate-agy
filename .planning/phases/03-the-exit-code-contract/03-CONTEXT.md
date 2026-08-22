# Phase 3: The exit-code contract - Context

**Gathered:** 2026-08-20
**Status:** Ready for planning

<domain>
## Phase Boundary

`scripts/agy_bridge.sh`'s and `scripts/gemini_shim.sh`'s error-output surface: what each of the five documented exit codes (`2`, `3`, `124`, `127`, `137`) means, the exact message text each emits (plain-text stderr and JSON envelope), and whether `README.md`'s troubleshooting table quotes that text as the code actually prints it. This is an audit-and-close-gaps phase, not new-feature work — the 137-vs-124 external-kill-vs-timeout discrimination (Phase 1's D-02) and R6's empty-success JSON guard are already shipped and tested; this phase's real surface is narrower than `ROADMAP.md`'s "Plans: TBD" implies.

**In scope:** the dangling `: ` suffix bug on both scripts' external-kill and generic-nonzero branches, plain-text and JSON forms (`delegate-agy-v5a`, expanded); a full audit/rewrite of README's 5 exit-code rows against actual current output (`delegate-agy-6q1` plus the other 4 rows); a quick consistency pass over `agy_bridge.sh`'s ~15 distinct `exit 2` call sites; upgrading exit-code test rigor to Phase 1's byte-exact/defined-once/README-verbatim-pinned (RB03-style) convention for messages this phase adds or touches.

**Out of scope:** exit `127` and its message text — that code lives entirely in `scripts/install.sh`'s generated launcher-wrapper templates (Phase 4's file, R8's requirement), is already tested (`I16`, `RB29`) and already documented accurately in README; this phase does not edit `install.sh`. Retrofitting pre-existing loose tests (`B2`/`S2`'s `RC -ne 0` and similar) to the new exact-code standard — only new/touched tests get the higher bar. Auditing all ~15 exit-2 sites for suite reachability — only the one README's row documents needs a hard assertion. R8 (registry read) — not this phase's requirement; `ROADMAP.md` maps it to Phase 4.

</domain>

<decisions>
## Implementation Decisions

### The dangling `: ` suffix bug — fix scope

- **D-01:** Fix **both** `scripts/agy_bridge.sh` and `scripts/gemini_shim.sh`, not just the bridge `delegate-agy-v5a` literally names. The shim's external-kill branch (`gemini_shim.sh` ~line 671: `printf '...external kill: %s\n' ... "$(cat "$STDERR_FILE")"`) carries the identical unconditional-suffix defect, undiscovered when `v5a` was filed. **User's explicit choice — overrides "bridge only, as literally ticketed."** Same defect class, same fix shape; leaving the shim unfixed would leave the box-wide-shadowing entry point with the exact bug the ticket exists to close. — **Reversibility:** reversible — a guard around an existing separator, local to each site.
- **D-02:** Fix the **JSON form too**, not just the plain-text `printf`/`echo` paths. The bridge's `python3 -c` invocations build the error string as `sys.argv[4] + ': ' + open(stderr_file).read()` — an empty stderr file yields the same dangling `: ` inside the JSON string. Criterion 3 says "in either the plain-text or the JSON form" explicitly; leaving JSON unfixed fails the criterion even with plain-text clean. — **Reversibility:** reversible.
- **D-03:** When stderr is empty, **drop the suffix entirely** — `"...possible OOM or external kill"` with no trailing colon — rather than keeping a colon with a fallback placeholder like `"(no stderr output)"`. When stderr is non-empty, append `": <stderr>"` as today. **User's explicit choice — overrides the placeholder-fallback alternative.** Matches the guard-the-separator convention already used elsewhere in these scripts rather than inventing a new placeholder string. Applies identically to the generic-nonzero branch's `"ERROR: agy exit %d: %s"` shape. — **Reversibility:** reversible.
- **D-04:** Expand `delegate-agy-v5a`'s scope to cover both files rather than filing a new ticket for the shim-side finding. One ticket, one fix-round, since it's the same defect fixed the same way in the same phase.

### README troubleshooting table — depth

- **D-05:** Audit and rewrite **all 5** exit-code rows (`2`, `3`, `124`, `127`, `137`) against what the code actually emits today, not just the two rows `delegate-agy-6q1` and D-01–D-03 name. **User's explicit choice — overrides "minimal patch, just the ticketed rows."** Criterion 4 says "each exit-code message," and exit 3's row is already stale independent of this phase's own fixes (see D-07). A minimal patch leaves the other rows stale the next time code shifts under them, which is exactly how `delegate-agy-6q1` happened. Exit `127`'s row is in scope to **re-verify** against current `install.sh` output (read-only check) even though the code itself is out of scope (D-out-of-scope above) — if it's already accurate, no edit; if not, that's a Phase-4-scoped finding to ticket, not fix here. — **Reversibility:** reversible.
- **D-06:** Where the bridge and shim word the **same exit code differently**, add a short aside noting the divergence (e.g., `137`'s stderr-suffix shape, the generic-nonzero branch — bridge prefixes `"ERROR: agy exit N: "`, shim relays agy's raw stderr with no prefix) rather than either doubling the whole table per entry point or silently picking one script's wording to represent both. **User's explicit choice — overrides "keep one shared row, don't split."** Keep shared rows where wording actually matches. — **Reversibility:** reversible.
- **D-07:** Exit 3's row is rewritten to quote the **real `"[<class>]: <reason>"` shape** the bridge emits (`class` ∈ `empty_output`/`quota`/`auth`) rather than the current flat `"agy returned empty output"` summary, and to note the shim's differently-shaped JSON (`{"error":{"message":...,"class":...}}` vs. the bridge's flat `{"success":false,...,"error":...,"error_class":...}`) per D-06's divergence-note convention. **User's explicit choice — overrides "keep it high-level."** Matches criterion 4 literally: an operator grepping their actual stderr should find a matching string in the docs. — **Reversibility:** reversible.

### Exit-2 message scope

- **D-08:** README keeps **one exemplar row** for exit `2` (the model-list-degraded case, already present) rather than adding rows for more of the ~15 distinct `exit 2` causes in `agy_bridge.sh` (bad flag, missing policy file, empty prompt, unknown `--model`, ...). **User's explicit choice — overrides "add 2-3 more representative rows."** Exit 2 means one semantic thing — bad input/config, not agy's fault — and each individual `ERROR:` message is already self-explanatory directly off the operator's own terminal; enumerating all 15 adds table bulk without adding findability. — **Reversibility:** reversible — adding more rows later is purely additive.
- **D-09:** Run a **quick consistency pass** over the ~15 exit-2 call sites in `agy_bridge.sh` (all start with `ERROR:`, wording style matches, no two messages could be confused with each other) as part of this phase's work, separate from what README documents. **User's explicit choice — overrides "leave the 15 sites as-is."** Cheap while already reading every exit-2 site for D-08/other work; catches a stray inconsistent message before it becomes its own bug report. This is a read-and-verify pass, not a rewrite mandate — only fix a site actually found inconsistent. — **Reversibility:** reversible.
- **D-10:** Test coverage for exit 2 stays scoped to the **one site README's row documents** (the model-list-degraded case, already covered by existing `R7`/`R8`-family tests) — do **not** add reachability tests for the other ~14 sites. **User's explicit choice — overrides "assert all ~15 are reachable."** The other sites are ordinary argument-parsing guards, not part of the exit-code contract's documented surface; auditing all of them for suite reachability is a materially different, larger task (general CLI flag-parsing coverage) that doesn't belong to "the exit-code contract" phase.

### Message-pinning rigor

- **D-11:** Extend Phase 1's D-10 convention — fixed literal, defined once per script, pinned by a test, quoted **verbatim** in README (RB03-style provenance) — to the exit-code messages this phase adds or touches (the dangling-colon fix's new shape, exit 3's rewritten row, any exit-2 site touched by D-09's consistency pass). **User's explicit choice — overrides "keep the existing substring-check style."** Criterion 4 (README quotes exactly what the code prints) is exactly what RB03's shape already proves for Phase 1's warnings; a substring check can pass while doc and code quietly diverge — precisely how `delegate-agy-6q1` happened. — **Reversibility:** reversible — a stricter assertion style on new/touched tests only; doesn't require touching passing tests.
- **D-12:** Do **not** retrofit pre-existing loose tests (`B2`/`S2`'s `"RC -ne 0"` instead of `"RC -eq 3"`, and similar substring checks in `T4`/`T5`/`SH4`-`SH6`) to the new exact-code/byte-exact standard. **User's explicit choice — overrides "retrofit everything for consistency."** Matches the project's surgical-changes convention — `B2`/`S2` aren't broken, don't touch what wasn't asked for. New and touched tests (the dangling-colon fix, exit 3's rewritten message, any D-09 consistency fix) get the higher bar; everything else is left alone. — **Reversibility:** reversible — a later phase can still retrofit them; nothing here forecloses it.

### Claude's Discretion

- **Exact RB03-style provenance test shape** for the exit-code rows D-11 pins — case naming, whether it's one combined case or one per row — subject to matching the existing `RB03` pattern (`tests/run-tests.sh:2019-2073`) rather than inventing a new mechanism.
- **Which specific exit-2 sites, if any, D-09's consistency pass finds worth changing** — the pass is a read-and-verify step; whether it turns up zero or several findings is not predetermined.
- **Whether the D-06 bridge-vs-shim divergence note is a sub-bullet, a parenthetical, or a two-line cell** in README's table — subject to matching the existing table's formatting conventions.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase intent and requirements
- `.planning/ROADMAP.md` §"Phase 3: The exit-code contract" — the five success criteria and the note explaining this phase's file scope (the bridge's error output, distinct from `TIMEOUT_BIN` branches and the model cache)
- `.planning/REQUIREMENTS.md` §R5, §R6 — the two requirements this phase closes; R5's traceability row already flags "137 discrimination shipped on branch; docs and empty-stderr suffix still wrong" and R6's "shipped on branch, needs regression coverage" — both match this phase's actual scope exactly
- `.planning/PROJECT.md` §Context — "Judge state by reading files, never by the commit graph"; this phase's code was read directly off `master` post-merge (54d4772), not off `git log`

### Prior-phase decisions this phase inherits
- `.planning/phases/01-the-missing-timeout-decision/01-CONTEXT.md` §D-02 — the elapsed-vs-bound (137-lands-before-the-timeout ⇒ external kill, not the bridge's own `-k` escalation) discrimination this phase does NOT re-derive, only tests/pins the message wording around
- `.planning/phases/01-the-missing-timeout-decision/01-CONTEXT.md` §D-09/D-10 — fixed-literal-warning convention (defined once, pinned by test, quoted verbatim in README) D-11 extends to exit-code messages
- `.planning/phases/01-the-missing-timeout-decision/01-CONTEXT.md` §D-11 — "JSON envelope untouched" by Phase 1; this phase's D-02/D-07 are the first phase to touch the JSON error string's content, narrowly
- `.planning/phases/01.5-contract-check-against-a-real-agy/01.5-CONTEXT.md` §D-07 — `tests/contract-check.sh`'s exit codes are disjoint from this phase's five; do not confuse the two numbering spaces
- `.planning/phases/01.5-contract-check-against-a-real-agy/01.5-CONTEXT.md` §D-11/D-12a — the real, live-observed `rc=0`-with-empty-stdout case (2026-08-19 probe, headless permission gate) that grounds R6's criterion 5 as non-hypothetical

### Tracker
- `delegate-agy-v5a` (P3, open) — "bridge: empty stderr leaves a trailing ': ' in error output"; D-01–D-04 expand its scope to both scripts and both output forms
- `delegate-agy-6q1` (P3, open) — "docs: troubleshooting exit-137 row omits the stderr suffix the code now appends"; D-05–D-07 widen the fix to all 5 rows

### Code under change (read on `master`, current post-merge state)
- `scripts/agy_bridge.sh:719-775` — the error-handling block: 137-external-kill branch (`:719-732`, D-01/D-02/D-03's primary site), 124-timeout branch (`:733-742`), generic-nonzero branch (`:743-752`, D-01/D-02/D-03 mirrored), R6 empty-stdout branch (`:753-774`, D-07's real message shape, `error_class` field)
- `scripts/gemini_shim.sh:667-706` — the mirrored block: 137-external-kill branch (`:667-676`, the newly-found D-01 site), 124-timeout branch (`:676-679`), generic-nonzero branch (`:679-681`, note: no `"ERROR: agy exit N:"` prefix here — D-06's divergence-note target), R6 empty-stdout branch (`:682-705`, differently-shaped JSON — `{"error":{"message":...,"class":...}}`)
- `scripts/agy_bridge.sh` — the ~15 `exit 2` call sites D-08/D-09/D-10 cover (flag parsing ~`:371-460`, model resolution `:530-554`, policy/prompt `:585-641`)
- `README.md` §Troubleshooting — the 5-row exit-code table (and the disjoint contract-check exit-code table immediately below it, which D-05 does not touch)
- `tests/run-tests.sh` — existing coverage to build on: `B1-B4`/`S1-S6` (basic pass/empty-output/JSON shape), `T4`/`T5` (bridge 137-vs-timeout), `SH4-SH6` (shim 137-vs-timeout); `RB03` (`:2019-2073`) is the provenance-test shape D-11 copies
- `scripts/install.sh:137`, `:173` — exit `127`'s actual sites, out of scope to edit, in scope to re-verify against README's existing row (D-05)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`RB03` (`tests/run-tests.sh:2019-2073`)** — the existing README-vs-script literal-matching provenance test; D-11's new assertions copy its shape rather than inventing a new mechanism.
- **The elapsed-vs-bound discrimination (`EXIT_CODE -eq 137 && DURATION -lt bound`)** — already correct and tested (`T5`, `SH6`); this phase only touches the message text inside the branch, never the condition.
- **The `error_class` classification (`RESOURCE_EXHAUSTED`/`429`/`quota` → `quota`; `Auth`/`UNAUTHENTICATED` → `auth`; else `empty_output`)** — already implemented on the bridge side; D-07 documents it, does not change it.

### Established Patterns
- **Fixed literals, defined once, README-verbatim-pinned** — Phase 1's D-09/D-10 convention; D-11 is this phase applying it to a surface Phase 1 didn't cover.
- **Guard a separator on non-empty content rather than always printing it** — not yet a pattern in these two scripts for error messages (that's exactly the bug D-01-D-03 fixes), but is the shape D-03 introduces as the fix.
- **Bridge fails loud with a structured JSON envelope; shim degrades case-by-case** — established by Phase 2 (D-05: bridge warns, shim stays silent on cache fallback) and confirmed again here: the shim's generic-nonzero branch relays raw stderr with no added prefix, unlike the bridge's `"ERROR: agy exit N: "` wrapping. D-06 documents this rather than unifying it — no decision in this phase's discussion proposed changing that asymmetry, only naming it in docs.

### Integration Points
- **`EXIT_CODE`/`DURATION` → the four-way `if/elif/elif/elif` branch → stderr or JSON output** — the single seam all of D-01–D-07's fixes sit inside, on both scripts.
- **README's troubleshooting table → `tests/run-tests.sh`'s `RB03`-style provenance case** — the seam D-11's new tests close, mirroring how Phase 1's warnings are already held to their docs.

</code_context>

<specifics>
## Specific Ideas

- User explicitly chose to widen `delegate-agy-v5a`'s and `delegate-agy-6q1`'s literal scope (bridge-only, 137-row-only) to cover the shim's mirrored bug and all 5 README rows respectively — both are "same defect, same fix, don't leave half of it done" calls, not the agent's discretion.
- User explicitly chose the higher message-pinning rigor bar (D-11) over matching the existing suite's looser convention, while explicitly declining to retrofit pre-existing tests (D-12) — a deliberately asymmetric choice: raise the bar going forward, don't spend this phase paying down existing test debt that wasn't asked for.
- User explicitly chose to keep exit 2's README footprint at one exemplar row (D-08) while still auditing the underlying code for consistency (D-09) — documentation scope and code-quality scope were treated as two separate questions with two different answers.

</specifics>

<deferred>
## Deferred Ideas

- **Exit `127` and its launcher-wrapper message text** — out of scope; that code lives in `scripts/install.sh`, which is Phase 4's surface (R8, registry-read-is-comparison-only). This phase re-verifies README's existing row against it (D-05) but does not edit the code.
- **Retrofitting `B2`/`S2` and other pre-existing loose exit-code tests to exact-code/byte-exact assertions** — explicitly declined this phase (D-12). Revisit if a future phase touches those same branches and the inconsistency becomes an actual problem.
- **Auditing all ~15 exit-2 call sites for suite reachability** — explicitly declined (D-10); would be a general CLI-flag-parsing coverage task, materially larger than this phase's named surface.
- **Adding more than one exemplar row for exit 2 in README** — explicitly declined (D-08); revisit only if a real operator report shows the one exemplar isn't findable enough.

### Reviewed Todos (not folded)
None — `cross_reference_todos` found zero matches for Phase 3.

</deferred>

---

*Phase: 3-The exit-code contract*
*Context gathered: 2026-08-20*
