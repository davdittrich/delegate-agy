# Phase 4: Installer and launcher surface - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-21
**Phase:** 4-Installer and launcher surface
**Areas discussed:** python3 guard (4xn), SIGPIPE one-liner (4vy), stale docs/HOME precondition (k0f + 4bp), criteria 1-3 depth

---

## Gray-area selection

| Option | Description | Selected |
|--------|-------------|----------|
| python3 guard (4xn) | `install.sh:239`'s `AGY_SETUP_PATCH_ALIASES=1` branch calls python3 with no `command -v` guard | ✓ |
| SIGPIPE one-liner (4vy) | `agy-setup.md`/`agy-uninstall.md`'s `head -1` pipeline can SIGPIPE-abort under `set -euo pipefail` | ✓ |
| README/agy-setup.md drift | README describes a two-command install flow agy-setup.md's current content doesn't have | ✓ |
| Criteria 1-3 depth | Registry exact-match, absent/reshaped-registry silence, repin construction — already shipped and tested | ✓ |

**User's choice:** All four selected (multiSelect).

---

## python3 guard (4xn)

### Guard placement and degrade behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Guard once, before the loop | Check `command -v python3` once after the `AGY_SETUP_PATCH_ALIASES=1` gate, before the `for RC in ...` loop; fail-open warning matching `_register_tokensave`'s shape, skip the block, continue install | ✓ |
| Guard inside the loop, per RC file | Check right before each python3 invocation, inside the loop | |
| Hard-require python3 for this flag | Exit the whole installer if the flag is set and python3 is absent | |

**User's choice:** Guard once, before the loop.
**Notes:** Rejected "inside the loop" as redundant (unchanging fact re-checked per matched rc file). Rejected hard-require as contradicting the ticket's own "graceful degrade" framing.

### Test/documentation rigor

| Option | Description | Selected |
|--------|-------------|----------|
| Plain test, no README pinning | One new suite case proving exit 0, wrappers written, warning on stderr, rc file untouched | ✓ |
| Full RB03-style provenance pin | Also quote the warning text in README with a byte-identity test | |

**User's choice:** Plain test, no README pinning.
**Notes:** No existing sibling warning (`_register_tokensave`'s, `_agy_detect`'s) gets RB03 treatment either — only the Env-flags comment documents the flag exists.

---

## SIGPIPE one-liner (4vy)

### Fix mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| Eliminate `head -1` | python3 itself prints only the first match; no external `head`, no SIGPIPE possible | ✓ |
| Append `\|\| true` (ticket's own suggestion) | Suppress the pipeline's nonzero exit on the assignment | |

**User's choice:** Eliminate `head -1`.
**Notes:** Explicit override of the ticket's own suggested minimal fix — "fix the hazard class, not the symptom," matching Phase 2's D-08 precedent. Applies to both `agy-setup.md` and `agy-uninstall.md`.

### Regression coverage

| Option | Description | Selected |
|--------|-------------|----------|
| Extract-and-run test | New suite case extracts the fenced bash block and runs it under `bash -euo pipefail -c` against a multi-match fake `claude` stub | ✓ |
| Manual verification only | Confirm by hand, no permanent suite case | |

**User's choice:** Extract-and-run test.
**Notes:** Sequencing constraint recorded in CONTEXT.md — the branch-tip content this phase syncs in (k0f) still carries the same unguarded `head -1`; the SIGPIPE fix must land after the sync, not before.

---

## Stale docs / precondition scope (k0f + 4bp)

### Fold into Phase 4?

| Option | Description | Selected |
|--------|-------------|----------|
| Fold both in | k0f (doc/version sync) and 4bp (HOME precondition) both fixed this phase | ✓ |
| k0f only, defer 4bp | Sync docs now, leave the HOME-unset crash for later | |
| Neither — fix ROADMAP.md's ticket line only | Correct the stale tally, defer both tickets explicitly to Phase 6 | |

**User's choice:** Fold both in.
**Notes:** `bd list --status open` showed 11 open tickets against ROADMAP's "10 open tickets" tally; k0f (filed 2026-08-20) and 4bp were unmapped to any phase despite sitting on this phase's exact files. Leaving them out just defers discovery to Phase 6's release gate.

---

## Criteria 1-3 depth

| Option | Description | Selected |
|--------|-------------|----------|
| Trust, don't re-verify | Cite I16/I17/I18 as evidence in the plan, no new tasks | ✓ |
| Add one more adversarial fixture | Add a truncated-registry or missing-version-key case | |

**User's choice:** Trust, don't re-verify.
**Notes:** Same pattern as Phase 2's D-01/D-02 and Phase 3's already-shipped-criteria handling.

---

## Claude's Discretion

- Exact wording of the D-01 python3-absent warning (subject to matching `_register_tokensave`'s shape).
- Exact python3 rewrite mechanism for D-03 (index `[0]`, early `break`, or `next(...)`).
- Whether D-04's fake `claude` stub is a new fixture file or an inline heredoc.
- Whether D-06's HOME-precondition test is one shared case or two per-script cases.

## Deferred Ideas

- A lint/CI check flagging `ROADMAP.md`'s stale ticket-absorption tallies automatically.
- `delegate-agy-lkg`'s live-verify bound mechanism — already closed ahead of this phase, not reopened.
