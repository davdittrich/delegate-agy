---
phase: 01
slug: the-missing-timeout-decision
status: verified
threats_open: 0
asvs_level: 1
created: 2026-08-20
---

# Phase 01 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| PATH/explicit caller → `gemini` shim / `agy-bridge` | Untrusted argv, stdin, and environment cross here — from interactive shells, Claude Octopus, and Metaswarm for the shim (which shadows the system binary); from explicit invocation for the bridge. | argv, stdin, env vars |
| Environment/flags → bound values | `GEMINI_SHIM_TIMEOUT`, `AGY_MODELS_TIMEOUT`, `GEMINI_SHIM_STDIN_TIMEOUT`, `--timeout`, `--stdin-timeout` become operands of `sleep`, `kill`, and `timeout`. | timeout durations |
| Script → OS signal delivery, with and without a controlling terminal | `kill -- -$pgid` targets a process group computed at runtime; job control behaves differently in a terminal-less runner, so the boundary is crossed twice with different guarantees. | process signals |
| Caller argv → agy subprocess argv | Argument boundaries cross at 7 `run_bounded` call sites across shim + bridge; a lost boundary silently changes what agy is asked to do. | command arguments |
| `run_bounded` → caller's captured streams and JSON payload | The helper's diagnostics cross here if written to the wrong descriptor. | diagnostic text, JSON envelope |
| The duplicated `run_bounded` copies (shim, bridge, contract-check) → each other | A fix applied to one and not the others crosses this boundary silently. | shared code block |
| Documentation (README, PROJECT.md) → operator / future implementer | An operator matches real output against README's troubleshooting table; later phases read PROJECT.md's Key Decisions as authority. | documented behavior claims |
| Future contributor → the two shipped scripts | A new agy call site enters here, with only the static scan standing between it and a box-wide hang. | new code |
| Test harness → the processes it observes | The outer safety net is itself a process killer; if it signals a group it destroys the evidence a case exists to check. | process groups under test |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-01-01 | Denial of Service | `run_bounded`'s process-group kill (shim + bridge, both mechanisms, with/without controlling terminal) | high | mitigate | D-06a self-kill guard (`$BASHPID`, never `$$`; empty/matching → direct-PID fallback; `_rb_pgid_of` digit-normalizes before its single exit). RB06a-d, RB04, RB05, RB13, RB25, RB21a/b all pass. | closed |
| T-01-02 | Denial of Service | orphaned agy process group after shim/bridge exits | medium | mitigate | D-06b: trap INT/TERM/HUP, relay to child target, cancel timer, restart ladder at delay 0. RB22 (parameterised over TERM/HUP) + RB20b pass. | closed |
| T-01-03 | Tampering | argument passing through `run_bounded` (7 call sites, shim + bridge) | high | mitigate | `"$@"` throughout, zero `$*`, zero unquoted `$@`. RB14 passes on both mechanisms. | closed |
| T-01-04 | Tampering | env/flag-supplied bound values reaching `sleep`/`kill` | medium | mitigate | Positive-integer validation at both the script's own probe and inside `run_bounded` (defense in depth). RB11 passes (7 refusals, 7 fixed errors on fd 9, sentinel proof, 1 valid control). | closed |
| T-01-05 | Tampering | caller-visible error payload / JSON envelope | medium | mitigate | D-07/D-11: all helper diagnostics on fd 9 only — zero plain-stderr diagnostic writes in the block. RB09a (incl. key-set equality + marker-still-emitted) and RB09b pass. | closed |
| T-01-06 | Denial of Service | a future unbounded agy call site (regression prevention) | high | mitigate | D-12/D-13 static scan, zero exceptions, no escape hatch, joined-logical-line over both shipped scripts. RB01 passes. | closed |
| T-01-07 | Denial of Service | the bridge's removed startup fatal on missing timeout/gtimeout | low | accept | Safe because every downstream call site converts to `run_bounded` in the same plan before the fatal is removed (task ordering + suite gate). Independently confirmed: the old fatal string is absent from both scripts and RB03 pins its absence as a regression. | closed |
| T-01-08 | Repudiation | README's quoted literals drifting from the shipped warning string | medium | mitigate | RB03: literals written independently in the test (not extracted from source), fixed-string match against README and both scripts, "defined exactly once" count. | closed |
| T-01-09 | Information disclosure | documenting the watchdog's fallback behaviour in README | low | accept | The strings/mechanism are already visible on any host running the scripts; documenting them discloses nothing an attacker couldn't observe. | closed |
| T-01-10 | Tampering | the static scan (RB01) itself passing vacuously | high | mitigate | RB01m is a real negative test (4 mutation probes: mutated/commented/twoonone/decoy), not a positive-count assertion. | closed |
| T-01-11 | Tampering | one-sided edit to a duplicated `run_bounded` block | medium | mitigate | RB02 (widened to 3 copies: bridge, shim, contract-check) requires non-empty + `run_bounded() {` present; RB02m proves a 1-char edit is caught. Independently re-verified via `cmp` — all 3 blocks byte-identical. | closed |
| T-01-12 | Denial of Service | the no-timeout warning printing more/less than once per run | low | mitigate | RB08: both entry points, count == 1, ordering asserted (warning precedes delegation), negative case (0 emissions with coreutils present). | closed |
| T-01-13 | Denial of Service | the test harness's own outer safety net reaping the fake processes a case is trying to observe | high | mitigate | All 11 descendant-observing cases use the foreground form or no net. 4 non-descendant-observing safety nets (SH11, SH13, CC01, CC02) use the bare form but assert on rc/elapsed/file state that survives a group kill, with an elapsed margin that turns a net-fire into a failure — the declared harm does not materialize. Residual note: a future descendant-observing case copied from that pattern would silently inherit it (see Unregistered Flags below). | closed |
| T-01-14 | Repudiation | a test case reporting success in an environment where it structurally could not make its real assertion (missing PTY allocator) | medium | mitigate | Missing allocator emits a named failure, never a silent skip. Allocator argv form flavour-probed from the binary (not `uname`); both branches pinned via stubbed probe; with-terminal case asserts it actually observed a tty. | closed |
| T-01-SC | Tampering | supply-chain (npm/pip/cargo installs) | low | accept | No package-manager install occurs in this phase; RESEARCH.md's Package Legitimacy Audit recorded not-applicable. | closed |

*Status: open · closed · open — below {block_on} threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-01 | T-01-07 | Removing the bridge's startup fatal on missing timeout/gtimeout is safe only because every downstream call site converts to `run_bounded` first, in the same plan, gated by the suite — verified absent + regression-pinned. | Phase 01 plan (01-03) | 2026-08-19 |
| AR-02 | T-01-09 | Documenting the watchdog fallback in README discloses nothing an attacker couldn't already observe by running the scripts. | Phase 01 plan (01-04) | 2026-08-19 |
| AR-03 | T-01-SC | No dependency added this phase; Package Legitimacy Audit not applicable. | Phase 01 RESEARCH.md | 2026-08-19 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-08-20 | 15 | 15 | 0 | gsd-security-auditor (opus, ASVS L1, block_on=high) |

**Unregistered flags (non-blocking, recorded for follow-up):**
1. No `## Threat Flags` section exists in any of the six SUMMARY.md files (structurally absent, not empty) — executors declared no new attack surface but left no positive record they looked.
2. `tests/contract-check.sh` (added in Phase 1.5, after this threat model was authored) carries 3 agy call sites, hand-verified `run_bounded`-wrapped and covered by RB02's byte-identity check — but RB01's static-scan loop (T-01-06's regression guard) was never widened to include it. Not a blocker: T-01-06's declared scope is the two shipped scripts, and contract-check.sh is test-side. Filed as delegate-agy-d4t.

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-08-20
