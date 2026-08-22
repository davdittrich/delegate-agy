---
phase: 06
plan: 02
subsystem: docs/tracking
tags: [tickets, key-decisions, gemini-md-binds, sigterm]
requirements: [S5, R11]
beads_epic: delegate-agy-tmm
dependency-graph:
  requires: [06-01]
  provides: [D-02, D-03 Key Decisions rows; xfa/i43 closed]
  affects: [PROJECT.md, STATE.md, ROADMAP.md]
tech-stack:
  added: []
  patterns: ["Key Decisions table row: one-sentence decision, rationale names the forcing ticket, Outcome cell opens with ✓ Good / ⚠️ Revisit / ✗ Superseded glyph"]
key-files:
  created: []
  modified:
    - .planning/PROJECT.md
    - .planning/STATE.md
    - .planning/ROADMAP.md
decisions:
  - "D-02: trust the bridge's per-run GEMINI.md policy isolation on measured evidence, not the CWD-binding comment alone — verified good against real agy 1.1.13, one-run caveat noted"
  - "D-03: keep R11's -k SIGKILL escalation even though a real delegation call died on SIGTERM alone — contradiction recorded, escalation kept as defense-in-depth"
actuals:
  tokens: 4200
  tasks: 2
  commits: 1
metrics:
  duration: 8min
  completed: 2026-08-21
status: complete
---

# Phase 6 Plan 2: Close xfa/i43 findings against Key Decisions rows Summary

Two pending investigation tickets (`delegate-agy-xfa`, `delegate-agy-i43`) closed by formalizing their findings as new rows in `PROJECT.md`'s Key Decisions table, then closing each ticket against its row via a linking `bd` comment. No source code touched.

## What Was Built

**Task 1 — PROJECT.md Key Decisions rows (D-02, D-03).** Appended exactly two rows to the existing table (same three-cell shape: Decision | Rationale | Outcome, glyph-led Outcome cell), zero deletions:

- **D-02** (`xfa`): "Trust the bridge's per-run GEMINI.md policy isolation on directly measured evidence rather than on the CWD-binding comment alone." Outcome: `✓ Good` — Phase 01.5-05's `_cc_probe_gemini_md_binds` re-ran the concern at the real bridge invocation shape (`--sandbox --add-dir WORK_DIR`, a never-granted decoy GEMINI.md, a per-run nonce/cksum discriminator). Verified against real agy 1.1.13 on 2026-08-20: the forbidden tool was declined, the cksum never appeared, the decoy marker never leaked (`checksum_matched=no decoy_seen=no`). Caveat carried forward explicitly: one run, one prompt shape, one model, one agy version.
- **D-03** (`i43`): "Keep R11's `-k` SIGKILL escalation even though a real delegation call died on SIGTERM alone." Outcome: `⚠️ Revisit` — the `-k` escalation's stated basis was a *models*-subcommand observation (`timeout 25 agy models` still running after 3+ minutes); Phase 01.5-05's probe drove a real *delegation* call (`--type code`, ~50000-word essay, `timeout -k 5 8`) and got `rc=124` at `elapsed=8s` — the first-stage SIGTERM alone ended agy, before the second stage ever fired. Recorded as a genuine contradiction between two different call shapes, not a resolved question; the escalation stays as defense-in-depth rather than being removed on one sample.

**Task 2 — closed both tickets against their rows.** `bd comment` on each ticket names the specific PROJECT.md row and its evidence; `bd close` on both. No git-tracked files changed by this task (bd state lives outside the repo tree) — `git status --short` confirms no change under `scripts/`, `tests/`, or `README.md`.

## Deviations from Plan

### Auto-fixed / Documented Issues

**1. [Plan-defect, not a code defect] `rc=124` global-uniqueness acceptance criterion is unsatisfiable as literally written.**
- **Found during:** Task 1 self-verification.
- **Issue:** The plan's acceptance criteria required `grep -F 'rc=124' .planning/PROJECT.md` to match exactly one line (the new D-03 row) while a sibling criterion required the task's `git diff --stat` to show exactly 2 insertions and 0 deletions. `PROJECT.md` already carries a pre-existing sub-bullet under `## Requirements` → `### Validated` → R11 ("Caveat: R11's stated premise... rc=124, under a strict 8s bound...") that documents the same `i43` finding and already contains the literal string `rc=124`. These two criteria cannot both hold: satisfying global uniqueness would require deleting or rewording that pre-existing bullet, which violates the 0-deletions constraint on this same task.
- **Resolution:** Did not touch the pre-existing bullet (out of scope for this task; it belongs to a different, already-shipped requirement's Validated entry, not to the Key Decisions table this task edits). The new D-03 row does satisfy the criterion's actual intent — it contains `rc=124` on the same line as `⚠️ Revisit`. Verified: `git diff --stat` shows exactly `.planning/PROJECT.md | 2 ++`, 1 file changed, 2 insertions, 0 deletions — the sibling criterion holds exactly.
- **Files modified:** none beyond the planned PROJECT.md row addition.
- **Commit:** `bad56a9`

**2. [Stale line-number reference in plan text] `scripts/agy_bridge.sh:478-480` citation in D-03's Outcome cell no longer points at the exact comment.**
- **Found during:** Task 1, verifying the plan's required literal citation against the live file.
- **Issue:** The plan (and its own acceptance criterion) required the D-03 row to cite `scripts/agy_bridge.sh:478-480` verbatim as the location of the "-k escalates to SIGKILL" inline rationale. Reading the live file (`grep -n "ignores SIGTERM"`) shows that comment now sits at lines 482-483 — a 4-line drift, almost certainly introduced when plan 06-01's RB30 trap-restore fix (commit `d887a8f`) added lines earlier in the same file.
- **Resolution:** Kept the required literal substring `scripts/agy_bridge.sh:478-480` (satisfies the mechanical acceptance check and the plan's explicit citation) and added a parenthetical noting the actual current location (`now at 482-483 after 06-01's trap-restore fix shifted the file`) so the row stays accurate for a future reader who greps the live file rather than trusting the stale line number.
- **Files modified:** `.planning/PROJECT.md` (same row as above).
- **Commit:** `bad56a9`

**3. [Mechanical check false positives, no actual defect] `bd list` grep-count acceptance checks collide with this plan's own task-ticket titles.**
- **Found during:** Task 2 self-verification.
- **Issue:** Both tasks' acceptance criteria include `bd list --status open | grep -cE '...'` counts expected to be `0` (for `xfa`/`i43`, post-close) and `6` (for the six untouched tickets `ltf`, `u1z`, `d4t`, `b7g`, `sup`, `rod`). Actual counts were `1` and `10` respectively. Root cause: this phase's own sibling task tickets (`delegate-agy-tmm.4` through `.8`) name the target bug IDs in their own titles (e.g. "06-02.2 Task 2: Close delegate-agy-xfa and delegate-agy-i43..."), and the naive `grep -E` pattern matches those titles too.
- **Resolution:** Verified the substantive state directly via `bd show delegate-agy-xfa` / `bd show delegate-agy-i43` (both report `CLOSED`) and `bd list --status open | grep -E '...'` output by eye (the 6 named tickets are the only genuinely-open bug/epic-type matches; the remaining lines are `tmm.*` task tickets referencing them by name, not the tickets themselves). No ticket state is incorrect; only the literal grep-count check is too naive to exclude title collisions.
- **Files modified:** none.
- **Commit:** n/a (verification-only finding).

None of the three affect correctness of the actual documented outcome — both closures are real, both PROJECT.md rows exist with the required content, and no unrelated file was touched.

## Ticket Closures

| Ticket | Disposition | Evidence |
|--------|-------------|----------|
| `delegate-agy-xfa` | CLOSED | `bd comment` names PROJECT.md's D-02 row; `checksum_matched=no decoy_seen=no`, one-run caveat stated |
| `delegate-agy-i43` | CLOSED | `bd comment` names PROJECT.md's D-03 row; `-k` kept, contradiction (`rc=124`, `elapsed=8s`) recorded |

## Self-Check: PASSED

- `.planning/PROJECT.md` contains the two new Key Decisions rows — FOUND (verified via `grep`).
- Commit `bad56a9` exists in `git log` — FOUND.
- `bd show delegate-agy-xfa` reports `CLOSED` — FOUND.
- `bd show delegate-agy-i43` reports `CLOSED` — FOUND.
- `bd comments delegate-agy-xfa` contains "one agy version" — FOUND.
- `bd comments delegate-agy-i43` contains "-k" and "kept" — FOUND.
- `git status --short` shows no change under `scripts/`, `tests/`, `README.md` — CONFIRMED (none).
