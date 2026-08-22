---
phase: 06
slug: ship-1-6-2
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-21
---

# Phase 06 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Custom bash harness (`ok`/`bad` functions), no external test framework |
| **Config file** | none — `tests/run-tests.sh` is self-contained; `tests/hooks/run-hook-tests.sh` is a separate self-contained harness |
| **Quick run command** | none available — no `--filter` flag exists in either harness [VERIFIED: grep for FILTER/--filter in tests/run-tests.sh found nothing] |
| **Full suite command** | `bash tests/run-tests.sh` (161 cases, ~3m44s measured) + `bash tests/hooks/run-hook-tests.sh` |
| **Estimated runtime** | ~230 seconds (run-tests.sh) + hook suite |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/run-tests.sh` (no faster targeted-run option exists in this harness)
- **After every plan wave:** Run `bash tests/run-tests.sh && bash tests/hooks/run-hook-tests.sh`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** ~230 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 06-01 | TBD | TBD | D-04 (`ltf`) | — | unknown long flag never consumes the next token | integration | `bash tests/run-tests.sh` (new case) | ❌ W0 | ⬜ pending |
| 06-02 | TBD | TBD | D-05 (`u1z`) | — | twin `grep -qxF` sites structurally present in both files | integration | `bash tests/run-tests.sh` (new IN01-shaped case) | ❌ W0 | ⬜ pending |
| 06-03 | TBD | TBD | D-06 (`d4t`) | — | `RB01` scans `contract-check.sh` too, zero violations | integration | `bash tests/run-tests.sh` (extend RB01) | ✅ | ⬜ pending |
| 06-04 | TBD | TBD | D-07 (`b7g`) | — | empty successful fetch, no cache → degraded-list message, not generic fetch-failure | integration | `bash tests/run-tests.sh` (new case) | ❌ W0 | ⬜ pending |
| 06-05 | TBD | TBD | D-08 (`sup`) | — | `RB24` deterministically green pre- and post-fix | integration | `bash tests/run-tests.sh` (existing RB24 + new forcing case) | ⚠️ W0 (forcing case needed) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/run-tests.sh` new case — D-04 unknown-flag-never-eats-next-token
- [ ] `tests/run-tests.sh` new case — D-05 twin `grep -qxF` site structural presence (`IN01`-shaped)
- [ ] `tests/run-tests.sh` new case — D-07 empty-successful-fetch-no-cache message
- [ ] `tests/run-tests.sh` new deterministic forcing case — D-08 (signal delivered into the exact narrow race window, not relying on natural jitter)
- [ ] `tests/contract-check.sh` guard-clause restructure (7 sites: lines 527, 565, 600, 644, 698, 829, 1008) required *before* D-06's `RB01` loop-widen lands, or `RB01` goes red

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Fresh `scripts/install.sh` produces working `agy-bridge`/`gemini` launchers on merged `master` | Success Criterion 3 | Installer behavior on a real filesystem/PATH, not exercised by the bash test harness | Run `scripts/install.sh` against a clean checkout of merged `master`, confirm both launchers exec and both suites (`run-tests.sh`, `run-hook-tests.sh`) pass |
| `a001d0e` content revert genuinely undone on `master` (files, not just history) | Success Criterion 2 | Requires reading file contents at HEAD, not `git log` | `git merge-base --is-ancestor fix/agy-bridge-resilience master` + diff the 3 touched files (README.md, agy_bridge.sh, install.sh) against current `master` |
| Release notes name each defect and the re-run-installer requirement | Success Criterion 4 | Prose review, not machine-checkable | Read README.md `## Changelog` → `### 1.6.2` entry, confirm each ticket named and re-install requirement stated |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 230s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
