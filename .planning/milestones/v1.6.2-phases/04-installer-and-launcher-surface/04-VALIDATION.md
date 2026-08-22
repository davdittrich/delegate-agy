---
phase: 4
slug: installer-and-launcher-surface
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-21
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `04-RESEARCH.md` §Validation Architecture.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | None — hand-rolled bash. `tests/run-tests.sh` carries its own `ok()`/`bad()`/`PASS`/`FAIL` bookkeeping (`:88-101, 4918-4924`) |
| **Config file** | none — the harness is a single executable file (4924 lines) |
| **Quick run command** | Not applicable — no fast subset selector exists in this harness; quick and full are the same command |
| **Full suite command** | `bash tests/run-tests.sh` (self-resolves `ROOT` via `BASH_SOURCE`) |
| **Estimated runtime** | Not separately timed this session (no built-in timer); the suite is fast enough that the project's own convention runs it per-commit |
| **Baseline** | `PASS=153 FAIL=0`, verified by running the full suite to completion this session — supersedes STATE.md's stale `PASS=145` figure (dated 2026-08-20, before Phase 3's later plans and RB29/CC01-CC06 additions landed) |

---

## Sampling Rate

- **After every task commit:** `bash tests/run-tests.sh` (only granularity available — no fast subset exists)
- **After every plan wave:** `bash tests/run-tests.sh`, full run (same command — no distinct "full suite" superset exists)
- **Before `/gsd-verify-work`:** full suite green (`PASS=N FAIL=0`), plus D-05's `git diff HEAD fix/agy-bridge-resilience -- .claude-plugin/plugin.json .claude/commands/agy-setup.md .claude/commands/agy-uninstall.md` emptiness check run manually (a one-time content-sync verification, not a runtime behavior — never becomes a `run-tests.sh` assertion)
- **Max feedback latency:** one full-suite run — there is no shorter signal in this harness

---

## Per-Task Verification Map

Task IDs are assigned by the planner; rows below map each requirement/ticket to the evidence that settles it. The planner fills `Task ID` / `Plan` / `Wave` as tasks are created.

| Task ID | Plan | Wave | Requirement | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------------|-----------|-------------------|-------------|--------|
| TBD | TBD | TBD | R8 — registry read stays comparison-only | Exact-key match, no cross-marketplace match, install-time-literal repin construction | integration | Already covered — no new command needed | ✅ `tests/run-tests.sh:3980-4105` (I16) | ⬜ pending |
| TBD | TBD | TBD | S2 — registry-schema-change survival | Bounded extraction window, no cross-plugin misattribution | integration | Already covered — no new command needed | ✅ `tests/run-tests.sh:4107-4194` (I17) | ⬜ pending |
| TBD | TBD | TBD | delegate-agy-4xn (D-01/D-02) — python3 guard before rc-alias-patch loop | `AGY_SETUP_PATCH_ALIASES=1` + python3-absent → exits 0, wrappers written, warning on stderr, rc file untouched | integration (`_fresh_home` + `nopy`-style `PATH`) | New case via `bash tests/run-tests.sh` (composes existing `I8b` + `I10` patterns) | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | delegate-agy-4vy (D-03/D-04) — SIGPIPE-safe CLI fallback | Fenced fallback block in both `.md` files reaches its validating `case` under `bash -euo pipefail -c` against a multi-match fake `claude`, without a SIGPIPE abort | integration (doc-block extraction + execution) | New case via `bash tests/run-tests.sh` (new `.md`-block extraction helper) | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | delegate-agy-k0f (D-05) — content sync from branch tip | `git diff HEAD fix/agy-bridge-resilience -- .claude-plugin/plugin.json .claude/commands/agy-setup.md .claude/commands/agy-uninstall.md` is empty | manual/CI verification | `git diff HEAD fix/agy-bridge-resilience -- .claude-plugin/plugin.json .claude/commands/agy-setup.md .claude/commands/agy-uninstall.md` (expect empty); `jq -r .version .claude-plugin/plugin.json` = `1.6.2` | N/A — content-sync verified by diff, not a suite assertion | ⬜ pending |
| TBD | TBD | TBD | delegate-agy-4bp (D-06) — explicit HOME-unset precondition | `install.sh`/`uninstall.sh` under `env -i` with `HOME` unset → stated `ERROR: HOME is not set...` on stderr, exit 1, no `unbound variable` message | integration (`env -i PATH=... bash install.sh`, no `HOME` key) | New case(s) via `bash tests/run-tests.sh` (distinct from existing `RB27`/`RB29`, which cover the bridge/shim/wrapper, not `install.sh`/`uninstall.sh` themselves) | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] New `I`-prefixed case in `tests/run-tests.sh` for D-01: composes the `I8b` (real recursive alias + `AGY_SETUP_PATCH_ALIASES=1`) and `I10` (`nopy`-style python3-absent `PATH`) patterns already in the suite — no new fixture files needed
- [ ] New case(s) in `tests/run-tests.sh` for D-06: `env -i PATH=<curated dir> bash "$INSTALL"` / `bash "$UNINSTALL"` with no `HOME` key at all; assert the exact D-06 stderr message, absence of `unbound variable`, and `rc=1`
- [ ] New extraction helper + case(s) in `tests/run-tests.sh` for D-04: a `_md_extract`-style function pulling the SIGPIPE-hazard fenced block out of `agy-setup.md`/`agy-uninstall.md` by content anchor, plus an inline fake `claude` CLI stub (matching the suite's existing inline-fake convention) emitting two-or-more matching entries; run the extracted block under `bash -euo pipefail -c` and assert it reaches its validating `case` without a SIGPIPE abort
- [ ] Framework install: **none** — the harness is self-contained bash; `bash`/`python3` are the only interpreters needed, both already verified present

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| D-05's content sync is byte-exact with `fix/agy-bridge-resilience`'s branch tip | delegate-agy-k0f | The ticket's own acceptance check is a `git diff` against a specific branch, not a suite assertion | `git diff HEAD fix/agy-bridge-resilience -- .claude-plugin/plugin.json .claude/commands/agy-setup.md .claude/commands/agy-uninstall.md` — expect empty output |

*All other phase behaviors have automated verification via `tests/run-tests.sh`.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency = one full-suite run (no shorter signal exists in this harness)
- [ ] D-05's manual `git diff` emptiness check recorded
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
