---
phase: 1
slug: the-missing-timeout-decision
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-19
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Seeded from `01-RESEARCH.md` § Validation Architecture. Task IDs fill in after the planner runs.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hand-rolled bash harness, no external framework (`tests/run-tests.sh:1-2`) |
| **Config file** | none — `tests/run-tests.sh` is both config and runner |
| **Quick run command** | `bash tests/run-tests.sh` |
| **Full suite command** | `bash tests/run-tests.sh` (identical — no sub-selection mechanism exists) |
| **Estimated runtime** | well under 60 seconds (~89 cases; the `SH13` precedent carries its own internal `timeout 30` guard) |

**Harness discipline that constrains how tests are written:** `tests/run-tests.sh:26` sets `set -u` **without** `set -e`. A test's own failing command does not abort the suite — only its `if`/`ok`/`bad` logic decides pass/fail. So a test driving `run_bounded` may call fallible commands directly, even though `run_bounded` itself must carry the Pitfall-2 guard because it runs under the *scripts'* `set -euo pipefail`.

Result reporting: `ok()` / `bad()` increment `PASS` / `FAIL`; the runner ends with `echo "PASS=$PASS FAIL=$FAIL"` and exits non-zero when `FAIL` is non-zero (`tests/run-tests.sh:1606-1611`). Capture helper: `_run OUTVAR RCVAR cmd…` (`tests/run-tests.sh:63`), which merges stdout and stderr.

---

## Sampling Rate

- **After every task commit:** `bash tests/run-tests.sh`
- **After every plan wave:** `bash tests/run-tests.sh` (no distinct full suite exists)
- **Before `/gsd-verify-work`:** the `PASS=… FAIL=…` line must show `FAIL=0`
- **Max feedback latency:** ~60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| TBD | TBD | 0 | R11 (D-14) | — | A hung agy and every process it forked are dead within the bound; nothing survives to consume CPU unattended | fixture | `bash tests/run-tests.sh` | ❌ W0 — `tests/fake-agy.sh` needs a forking, SIGTERM-ignoring mode | ⬜ pending |
| TBD | TBD | 0 | R11 (D-15) | — | The watchdog path is exercised on a host that does have coreutils, so the fallback cannot rot untested | fixture | `bash tests/run-tests.sh` | ❌ W0 — sanitized-PATH sandbox that does **not** inherit the outer PATH | ⬜ pending |
| TBD | TBD | 0 | R11 (D-14a) | — | The descendant guarantee holds identically with and without a controlling terminal | fixture | `bash tests/run-tests.sh` | ❌ W0 — PTY-allocation wrapper (`script -qc` or equivalent) | ⬜ pending |
| TBD | TBD | 1 | R11 (D-12, D-13) | — | Every `"$AGY_BIN"` occurrence in both scripts is a `run_bounded … --` argument, zero exceptions — a call site added later fails the suite | lint/static-scan | `bash tests/run-tests.sh` | ✅ append to existing file, modeled on the `I18` case (`tests/run-tests.sh:1591-1604`) | ⬜ pending |
| TBD | TBD | 1 | R11 (D-08) | — | The two duplicated `run_bounded` blocks stay byte-identical; a one-sided edit fails | unit, text diff | `bash tests/run-tests.sh` | ❌ W0 — new case | ⬜ pending |
| TBD | TBD | 1 | R11 (D-09, D-10) | — | Both entry points emit the exact literal warning once when `TIMEOUT_BIN` is empty, and README quotes that same literal | unit, string match | `bash tests/run-tests.sh` | ❌ W0 — new case; also discharges D-17's verbatim-quote obligation | ⬜ pending |
| TBD | TBD | 1 | R11 (runtime, coreutils present) | — | A SIGTERM-ignoring fake and its SIGTERM-ignoring grandchild both die within `secs + kill_after` | integration | `bash tests/run-tests.sh` | ❌ W0 — depends on the forking fake above | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/fake-agy.sh` — forking, SIGTERM-ignoring mode: trap TERM, write own PID to a file, fork a child that also traps TERM and writes its PID to a second file, both sleeping past any plausible bound (D-14).
- [ ] `tests/run-tests.sh` — sanitized-PATH sandbox construction. **The existing sandbox is not sufficient:** `tests/run-tests.sh:37-62` does `export PATH="$SANDBOX/bin:$PATH"`, which *prepends* and leaves the real `timeout`/`gtimeout` reachable. D-15 needs a PATH built from an explicit minimal set — a second sandbox dir holding only `agy` plus the few external tools the watchdog path itself needs (`sleep`, `kill`, `awk`), and no `timeout`/`gtimeout` — rather than a hardcoded guess at where those binaries live (D-15).
- [ ] `tests/run-tests.sh` — PTY-allocation wrapper for the with-PTY half of D-14a; the no-PTY half is already covered by the harness running non-interactively (D-14a).
- [ ] `tests/run-tests.sh` — static-scan case for the `run_bounded` invariant, modeled on the existing `I18` case (D-12, D-13).
- [ ] `tests/run-tests.sh` — byte-identity case for the duplicated `run_bounded` blocks (D-08).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Job-control notice suppression on macOS bash 3.2 | R11 (D-06c) | No macOS host is available to this project. Non-interactive bash 5.3.15 on Linux emitted **zero** job-control notices in every shape the researcher tested, so the failure D-06c guards against could not be reproduced here — it remains `[ASSUMED]` for bash 3.2. | On a macOS host with stock `/bin/bash` (3.2) and no coreutils: run `gemini` with a PATH lacking `timeout`/`gtimeout` and confirm stderr carries the D-10 warning and nothing resembling `[1] 12345` or `[1]+ Terminated`. Narrow (not blanket) suppression ships regardless. |
| README reads correctly side by side | R11 (criterion 3) | Criterion 3 is about whether a human reader finds both behaviors stated together with the reason — a property of prose, not of a string match. | Read README's environment-variable section end to end and confirm the bridge's and shim's behavior appear together, with the reason they no longer differ. |
| PROJECT.md Key Decisions row records the choice | R11 (criterion 1) | The phase "is done when the choice is written down", which no automated assertion can judge. | Confirm the Key Decisions table carries the watchdog decision and its rationale, and that the superseded "shim degrades silently, bridge fails loud" row is resolved rather than left ⚠️ Revisit (D-18). |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
