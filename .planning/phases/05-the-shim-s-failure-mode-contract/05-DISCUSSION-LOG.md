# Phase 5: The shim's failure-mode contract - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-21
**Phase:** 5-The shim's failure-mode contract
**Areas discussed:** Contract table placement, Superseded-pin test coverage, Model-list divergence

---

## Contract table placement

| Option | Description | Selected |
|--------|-------------|----------|
| New section, 4 rows only | New `## Shim failure-mode contract` section near "Drop-in gemini CLI replacement". Criterion 4 stays a cited test, not its own row. | |
| New section, 5 rows | Same new section, but unrecognized-model passthrough gets its own row since it's named as its own criterion in ROADMAP.md. | |
| Fold into existing Troubleshooting table | Extend the existing exit-code-indexed table (README.md:222) instead of a new one — avoids a second table saying similar things. | ✓ |

**User's choice:** Fold into existing Troubleshooting table.
**Notes:** The existing table already carries most of the shim-vs-bridge prose this phase needs in a different index (by error/exit-code rather than by failure-mode); consolidating avoids duplication. Exact fold mechanics left to Claude's discretion.

---

## Superseded-pin test coverage

| Option | Description | Selected |
|--------|-------------|----------|
| Add a direct gemini-wrapper assertion | New case building a versioned `gemini` wrapper fixture and asserting exit 127 on stale pin, mirroring I16's shape but targeting `gemini_shim.sh`'s wrapper. Matches this project's per-entry-point-proof convention (R11, EC03). | |
| Cite I16, shared code is proof enough | `write_wrapper` is one function invoked identically for both names (install.sh:206-207). Matches Phase 4's D-07 pattern. | ✓ |

**User's choice:** Cite I16, shared code is proof enough.
**Notes:** Explicitly a departure from this project's usual per-entry-point-proof convention (R11's "runtime proof per entry point", EC03's "mirror the guard into gemini_shim.sh"). The user weighed that convention against this specific case and judged the shared-function structure (one function, two call sites, no per-name branching) sufficient. Recorded as a noted gap, not an oversight — deferred, not closed, per CONTEXT.md's Deferred Ideas.

---

## Divergence — degraded model list

| Option | Description | Selected |
|--------|-------------|----------|
| Document as final, state why | Keep current behavior (bridge warns loud + exits 2, shim degrades silent). One-line reason: shim shadows gemini for every PATH caller, a stderr warning there is box-wide noise. No code change. | ✓ |
| Add a quiet signal, still not a hard failure | Give the shim a low-noise trace of a degraded fetch (e.g. opt-in env-gated log line) without breaking silent-by-design. Reopens `load_models()` in gemini_shim.sh. | |

**User's choice:** Document as final, state why.
**Notes:** This closes the exact question Phase 2's `02-CONTEXT.md` §D-05 explicitly left open for this phase ("this phase does not add a shim warning; that's S3/Phase 5 territory if it's ever revisited"). The answer is "keep as designed."

---

## Claude's Discretion

- Exact fold mechanics for the Troubleshooting table (lead-in paragraph vs. per-row divergence notes vs. re-keying) — subject to landing all four failure modes in the one existing table and satisfying ROADMAP criterion 3.
- Which specific existing test IDs to cite per row, and their exact line ranges.

## Deferred Ideas

- A quiet, opt-in signal for the shim on a degraded model list (declined under the Divergence decision) — would reopen `load_models()`, a real code change. Revisit only if an operator incident makes the silence a real problem.
- A direct test proving the `gemini` wrapper independently refuses a stale pin (declined under the Superseded-pin decision) — the gap is real but low-risk given the shared-function structure. Revisit if `write_wrapper()` ever grows a name-conditional branch.
