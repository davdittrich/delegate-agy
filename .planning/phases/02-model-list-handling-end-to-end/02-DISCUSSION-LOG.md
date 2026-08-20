# Phase 2: Model-list handling, end to end - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-20
**Phase:** 2-Model-list handling, end to end
**Areas discussed:** Fallback (degraded-fetch-this-call behavior), Scope (already-shipped criteria), Extra-col (synthetic column test), Done (closing check)

---

## Fallback — degraded-fetch-this-call behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Fall back to stale cache | A degraded-but-successful fetch is treated like a fetch FAILURE: if a valid pre-existing cache is on disk, use it — bridge warns to stderr and proceeds instead of exit 2; shim silently falls back per its existing degrade-silently design. | ✓ |
| Keep current: always fail loud (Recommended) | Unchanged: a degraded reply is authoritative for this call, never masked by an old cache. 8ph then purely stops future calls from being poisoned. | |

**User's choice:** Fall back to stale cache — explicitly overrode the recommended option.
**Notes:** Captured as CONTEXT.md D-04. With no stale cache present, behavior is unchanged (bridge exit 2, shim passthrough) — only the has-a-valid-stale-cache branch changes.

---

## Scope — already-shipped criteria 1 and 3

| Option | Description | Selected |
|--------|-------------|----------|
| Trust it, skip re-verification (Recommended) | Plan focuses entirely on 8ph (S4) + the criterion-4 extra-column test; criteria 1/3 get a one-line note citing closed tickets and existing tests. | ✓ |
| Add one confirmation pass | Planner adds a lightweight task re-running RB27/R8/SH14 and reading the closed-ticket commits before declaring 1 and 3 done. | |

**User's choice:** Trust it, skip re-verification.
**Notes:** Captured as CONTEXT.md D-01/D-02. `delegate-agy-30m` and `delegate-agy-oyy` are CLOSED; `RB27`, `R8`, `SH14` already assert the behavior.

---

## Extra-col — synthetic multi-column normalization test

| Option | Description | Selected |
|--------|-------------|----------|
| Add a synthetic 3-column fixture test (Recommended) | A hand-built row (id\tdisplay\textra) proves `cut -f1` holds without waiting for agy to actually emit that shape. | ✓ |
| Skip it — tab-suffix coverage is enough | agy has only ever emitted 2 columns; testing an unobserved shape is speculative. | |

**User's choice:** Add a synthetic 3-column fixture test.
**Notes:** Captured as CONTEXT.md D-06. Kept as a synthetic test-only payload, not added to `tests/fixtures/agy-models.tsv` (the real captured-evidence file).

---

## Done — closing check

| Option | Description | Selected |
|--------|-------------|----------|
| Ready for context (Recommended) | Write 02-CONTEXT.md now from what's captured. | ✓ |
| Explore more gray areas | Continue discussing. | |

**User's choice:** Ready for context.

---

## the agent's Discretion

- **D-05 — bridge fallback warning wording.** User's D-04 choice created a new warning message; exact string left to the agent, subject to the fixed-literal-quoted-in-docs convention Phase 1's D-09/D-10 set. Distinct from the existing fetch-failure warning text so an operator can tell the two failure modes apart. Shim stays silent on this path, unchanged.

## Deferred Ideas

- **The shim emitting its own warning on a degraded list** — surfaced while discussing D-05; declined for this phase, belongs to Phase 5 (S3, shim failure-mode contract) if ever revisited.
- **`delegate-agy-4bp`** (install.sh/uninstall.sh's own unguarded `$HOME`) — noted during domain-boundary scouting as out of scope; Phase 4's surface.
