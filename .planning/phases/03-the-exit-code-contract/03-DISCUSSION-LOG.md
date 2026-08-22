# Phase 3: The exit-code contract - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-20
**Phase:** 3-The exit-code contract
**Areas discussed:** Dangling-colon fix scope, README troubleshooting depth, Exit-2 message scope, Message-pinning rigor

---

## Dangling-colon fix scope

| Option | Description | Selected |
|--------|-------------|----------|
| Bridge + shim, both | Same defect class, same fix shape; fixing only the ticketed file leaves the shim with the exact bug the ticket exists to close | ✓ |
| Bridge only, as literally ticketed | Stick to `delegate-agy-v5a`'s exact scope; file the shim finding separately | |

**User's choice:** Bridge + shim, both.
**Notes:** Found during codebase scouting, not named by either open ticket: `gemini_shim.sh`'s external-kill branch (~line 671) carries the identical unconditional `': %s'` suffix `delegate-agy-v5a` names only on the bridge.

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, same guard in the JSON branch | Criterion 3 explicitly names "in either the plain-text or the JSON form" — leaving JSON unfixed fails the criterion even if plain-text is clean | ✓ |
| No, JSON error strings are internal, don't touch | Leave the `python3 -c` invocations untouched | |

**User's choice:** Yes, fix the JSON form too.

| Option | Description | Selected |
|--------|-------------|----------|
| Drop the suffix entirely | No trailing colon at all when stderr is empty; append `": <stderr>"` only when non-empty | ✓ |
| Keep the colon, add a fallback placeholder | Always show the colon with `"(no stderr output)"` when empty | |

**User's choice:** Drop the suffix entirely.

| Option | Description | Selected |
|--------|-------------|----------|
| Expand `delegate-agy-v5a`'s scope to cover both files | One ticket, one fix-round | ✓ |
| File a new P3 ticket for the shim-side finding | Keep `v5a` scoped to its original literal text | |

**User's choice:** Expand `delegate-agy-v5a`.

---

## README troubleshooting depth

| Option | Description | Selected |
|--------|-------------|----------|
| Full 5-row audit | Criterion 4 says "each exit-code message" — a minimal patch leaves other rows stale the next time code shifts under them | ✓ |
| Minimal — just the two ticketed rows | Fix 137's missing suffix and the dangling colon only | |

**User's choice:** Full 5-row audit.

| Option | Description | Selected |
|--------|-------------|----------|
| Separate note only where they actually differ | Keep shared rows where wording matches; add a short aside only where bridge and shim genuinely diverge | ✓ |
| Keep one shared row per code, don't split | Table stays code-centric | |

**User's choice:** Separate note only where they actually differ.

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, quote the real "[class]: reason" shape | Matches criterion 4 literally | ✓ |
| No, keep it high-level as-is | Don't surface the internal class taxonomy in user docs | |

**User's choice:** Yes, quote the real shape.

---

## Exit-2 message scope

| Option | Description | Selected |
|--------|-------------|----------|
| Keep one exemplar row | Exit 2 means one semantic thing; each individual `ERROR:` message is already self-explanatory | ✓ |
| Add a few more representative rows | Pick 2-3 more commonly hit exit-2 causes | |

**User's choice:** Keep one exemplar row.

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, quick consistency pass | Cheap while already reading every exit-2 site for this phase's other work | ✓ |
| No, leave the 15 sites as they are | Don't touch code that isn't part of a named criterion or ticket | |

**User's choice:** Yes, quick consistency pass.

| Option | Description | Selected |
|--------|-------------|----------|
| Only the documented one needs a hard assertion | The other ~14 are ordinary argument-parsing guards, not part of the exit-code contract's documented surface | ✓ |
| Assert all ~15 are reachable in the suite | Full completeness for this code | |

**User's choice:** Only the documented one needs a hard assertion.

---

## Message-pinning rigor

| Option | Description | Selected |
|--------|-------------|----------|
| Extend to byte-exact + RB03-style provenance | Criterion 4 is exactly what RB03's shape already proves for Phase 1's warnings; a substring check can pass while doc and code quietly diverge | ✓ |
| Keep the existing substring-check style | Match the surrounding suite's convention | |

**User's choice:** Extend to byte-exact + RB03-style provenance.

| Option | Description | Selected |
|--------|-------------|----------|
| Only new/touched tests get the higher bar | Matches surgical-changes convention — don't touch what wasn't asked for | ✓ |
| Retrofit B2/S2/etc. to assert exact codes too | Full consistency across the suite | |

**User's choice:** Only new/touched tests get the higher bar.

---

## Claude's Discretion

- Exact RB03-style provenance test shape (case naming, one combined case vs. one per row).
- Which specific exit-2 sites, if any, the D-09 consistency pass finds worth changing.
- Whether the bridge-vs-shim divergence note in README is a sub-bullet, a parenthetical, or a two-line cell.

## Deferred Ideas

- Exit `127` and its launcher-wrapper message text — Phase 4's surface (`scripts/install.sh`, R8); this phase only re-verifies README's existing row against it, doesn't edit the code.
- Retrofitting pre-existing loose exit-code tests (`B2`/`S2` and similar) to the new exact-code/byte-exact standard.
- Auditing all ~15 exit-2 call sites for suite reachability.
- Adding more than one exemplar row for exit 2 in README.
