# Phase 6: Ship 1.6.2 - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-21
**Phase:** 6-Ship 1.6.2
**Areas discussed:** Open-ticket disposition, Release notes format, Fresh-install verification

---

## Open-ticket disposition — overall policy

| Option | Description | Selected |
|--------|-------------|----------|
| Fix all 8, defer none | Matches PROJECT.md's recorded rule that follow-ups discovered during work block the release. | ✓ |
| Fix 7, defer sup | sup's own ticket text shows the flake reproduces on a pre-Phase-02-fix-round commit — arguably predates 1.6.2. | |
| Let me specify per-ticket | Walk through disposition one ticket at a time. | |

**User's choice:** Fix all 8, defer none.
**Notes:** Applies this project's own no-defer-for-discovered-work rule to itself, including the flaky test.

---

## Open-ticket disposition — xfa / i43

| Option | Description | Selected |
|--------|-------------|----------|
| Close both as resolved | xfa's ledger shows gemini-md-binds=verified; i43's own text recommends keeping the -k escalation as-is. | ✓ |
| Close xfa, reopen i43 as follow-up | Retest SIGTERM response across more payload shapes/models first. | |
| Keep both open, out of Phase 6 | Neither gets touched or closed this phase. | |

**User's choice:** Close both as resolved.
**Notes:** No code change for either; decisions recorded in PROJECT.md's Key Decisions table.

---

## Open-ticket disposition — ltf / u1z fix mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| Lock as specified | ltf: require `--flag=value` form for unknown long flags. u1z: add a `grep -cF` structural-equality check across both scripts' twin `grep -qxF` sites. | ✓ |
| Let the planner redesign | Treat ticket text as background only. | |

**User's choice:** Lock as specified.

---

## Open-ticket disposition — d4t / b7g minors

| Option | Description | Selected |
|--------|-------------|----------|
| Fix both | Matches the project's fold-minors-into-the-running-round convention. | ✓ |
| Fix d4t only | d4t is a real coverage gap; b7g is cosmetic. | |
| Defer both | Ticket both for a later milestone. | |

**User's choice:** Fix both.

---

## Release notes format

| Option | Description | Selected |
|--------|-------------|----------|
| Extend README's Changelog section | No prior GitHub Release exists for this repo; README's `### 1.6.2` header is the established mechanism. | ✓ |
| New GitHub Release | Create a new, previously-unused distribution artifact. | |
| Both | README stays durable record, GitHub Release also cut. | |

**User's choice:** Extend README's Changelog section.

---

## Fresh-install verification

| Option | Description | Selected |
|--------|-------------|----------|
| Manual documented step | No CI exists for this repo; a one-time documented checklist run before the tag. | ✓ |
| New automated E2E test case | A permanent scripted regression guard in tests/run-tests.sh. | |
| Both | One-time manual run now, plus a follow-up ticket to automate. | |

**User's choice:** Manual documented step.

---

## Claude's Discretion

- Exact wording of the release notes' re-run notice and per-item Changelog bullets.
- Exact grep/loop mechanics for the RB01 extension to `tests/contract-check.sh`.
- Whether `delegate-agy-sup`'s root-cause fix needs a new regression case or just a corrected `run_bounded` trap-handling fix.

## Deferred Ideas

None — every gray area surfaced was resolved in-phase; nothing was pushed to a future phase.
