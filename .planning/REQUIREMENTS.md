# Requirements — agy-delegate

Scope: finish 1.6.2, then close the structural coupling that produced the 1.6.x bug cluster.

**Sources.** R-requirements are inferred from `README.md` on `fix/agy-bridge-resilience` — they are promises the project already makes to users, so each is testable against stated behavior. S-requirements come from the incident pattern across 1.6.0–1.6.2 and the committed codebase map (`.planning/codebase/CONCERNS.md`); the README implies them but does not state them.

**Authority.** `bd` is authoritative for pending work (7 open tickets). This document is the *why*; the tracker is the *what's left*.

---

## v1.6.2 Requirements

### R5 — Exit codes are a contract

Each documented code means exactly one thing, and the message says which: `2` (bad input, or a model list with no `gemini-` ids), `3` (agy exited 0 with no output), `124` (the bridge's own timeout), `127` (superseded pin, refusing to run), `137` (killed before the bound elapsed — OOM or external kill, not a timeout).

- Acceptance: each code reachable in the suite; the 137 path distinguishes an early external kill from the bridge's own `-k` escalation by comparing elapsed duration against the bound.
- Evidence: `README.md` §Troubleshooting; `tests/run-tests.sh` T4/T5.

### R6 — Never report empty success

agy exits 0 with empty stdout on quota exhaustion (`RESOURCE_EXHAUSTED`/429) and on silent backend errors. Both entry points must fail loud with agy's own stderr as the reason, and the failure payload must never be success-shaped.

- Acceptance: JSON mode emits an `{"error":…}` envelope with no `response` key; text mode writes the reason to stderr with 0-byte stdout; exit 3.
- Evidence: `README.md` §Troubleshooting; `scripts/gemini_shim.sh` empty-output guard.

### R8 — Registry read is comparison-only

The launcher compares its pinned version against Claude Code's install registry and refuses to run a superseded copy. The registry contributes **a version string and nothing else**.

- Acceptance: exact key match derived from the cache layout, so a lookalike plugin from another marketplace cannot match; the repin command is constructed from install-time literals and a numeric-validated version, never from a registry-supplied path; absent or unparseable registry degrades to silence.
- Evidence: `README.md` §Security; `tests/run-tests.sh` I16 cases (a)–(e), I17.

### R11 — Bounded execution

Every `agy` invocation is bounded, on every host. agy ignores SIGTERM, so every bound escalates to SIGKILL; a missing `timeout`/`gtimeout` binary changes which mechanism enforces the bound, never whether one exists.

- Acceptance, stated as an invariant rather than a list: **every** `"$AGY_BIN"` occurrence in `scripts/agy_bridge.sh` and `scripts/gemini_shim.sh` is an argument to `run_bounded` — no permitted-fallback clause and no exceptions — enforced by a test that reads the scripts; plus a runtime proof per entry point, on both mechanisms, that nothing outlives its bound.
- Do not restate this as a count. It has been wrong three times — two, then four, now five — most recently because this project's own work added a call site. A number decays; the invariant does not.
- Decided in Phase 1, recorded in `PROJECT.md` §Key Decisions as *always bounded*: the bridge/shim divergence this requirement once flagged is dissolved rather than documented. Both entry points warn once per run when no bounding binary is found and then proceed bounded; the bridge's startup fatal is deleted.
- Evidence: `README.md` §Environment variables; `tests/run-tests.sh` RB00a-b (the sanitized PATH and the adversarial fake are themselves asserted), RB01/RB01m (the static invariant, and the scan proven able to fail), RB02/RB02m (one helper duplicated into two files, byte-identical), RB03/RB08 (the operator-visible literals, once per run, ahead of any bounded output), RB04/RB05/RB13 (runtime proof per entry point, on both mechanisms, that nothing outlives its bound), RB06a-d (the same with and without a controlling terminal), RB07, RB09a-b (the helper's diagnostics never in a caller-parsed payload), RB10a-b/RB11/RB12/RB14 (the helper's own contract at its edges), RB20a-b/RB21a-b/RB22 (the defect regressions, RB22 over TERM and HUP), RB23-RB26 (the gap round: fd 9 never reaching the bounded child, the host's traps given back, the pgid lookup with no external binary and a whitespace comm).

---

## Structural Requirements

These exist because the same failure shape produced three separate incidents: the plugin depends on formats it does not control and cannot detect drift in.

### S1 — Survive an `agy models` format change

An output-format change must fail loudly and diagnosably, never silently resolve to nothing.

- Acceptance: a degraded list (no `gemini-` ids) is reported as a degraded/unauthenticated agy, distinct from an unmatched `--type`; a tab-suffixed list normalizes rather than failing to match; anchored matchers are never loosened to compensate — the input is normalized instead.
- Origin: the 1.6.1 incident. `agy models` began emitting `id<TAB>display name`; every `$`-anchored matcher stopped matching and all delegation failed with a message blaming the user's `--type`.

### S2 — Survive a Claude Code registry schema change

- Acceptance: the extraction is bounded to the plugin's own entry rather than a fixed line window; a neighbouring plugin's data can never be misattributed; any parse failure degrades to silence, never to a false refusal.
- Origin: `grep -A6` plus a greedy match could read an adjacent plugin's version under registry shapes Claude Code does not currently emit but has never promised not to.

### S3 — Shim defects must not escape into unrelated PATH callers

- Acceptance: for every failure mode, the shim's behavior toward a non-agy-aware caller is stated and tested — a hang, an unparseable model list, a missing dependency, a superseded pin. Where the shim and bridge diverge, the divergence is deliberate and documented.
- Origin: the shim installs as `~/.local/bin/gemini`. Octopus, Metaswarm, and interactive shells all route through it.

### S4 — Shared model cache safe under two independent writers

`agy_bridge.sh` and `gemini_shim.sh` both read and write `~/.cache/agy-bridge-models` with a 60-minute TTL and no coordination.

- Acceptance: neither writer caches a reply containing no `gemini-` ids; a poisoned or partial cache cannot degrade the other tool; writes stay atomic.
- Origin: ticket `delegate-agy-8ph`. One bad `agy models` response currently poisons both tools for up to an hour.

### S5 — Verifiable against a real `agy`

- Acceptance: a contract check, runnable on demand and separate from the unit suite, that exercises the real binary and reports which assumptions hold — at minimum whether `--model` accepts ids, display names, or both, and what `agy models` actually emits.
- Origin: three independent reviews could not settle the id-vs-display-name question because nothing in the repo can ask it. The fake is deterministic and fast, which is why the suite stayed green while the real integration was broken. **This is the requirement that would have caught the originating bug.**
- Constraint: cannot be satisfied on the current machine — agy is unresponsive and returns 124.

---

## Traceability

| Req | Phase | Open tickets | Status |
|-----|-------|--------------|--------|
| R5 | Phase 3 | `6q1`, `v5a` | partial — 137 discrimination shipped on branch; docs and empty-stderr suffix still wrong |
| R6 | Phase 3 | — | shipped on branch, needs regression coverage |
| R8 | Phase 4 | — | shipped on branch, reviewed |
| R11 | Phase 1 | `cy5` | met — both scripts are now converted: the shim's sites as of plan 01-02, the bridge's as of plan 01-03, all through `run_bounded`, all bounded on a host with no `timeout`/`gtimeout`. The divergence this requirement flagged as an open question is dissolved rather than documented (bound always, warn once per run, never fatal); the decision is recorded in `PROJECT.md` §Key Decisions and R11's acceptance is rewritten to match, as of plan 01-04. Both halves of the acceptance have landed: the test that reads the scripts is RB01/RB01m (plan 01-05) and the runtime proof per entry point, on both mechanisms, is RB04/RB05/RB13/RB06b-c (plan 01-06). Re-assessed and met after the phase-01 fix round; the qualifier that follows records why it was NOT met at the moment the acceptance was first satisfied: the code review found two Criticals in the mechanism itself -- a descriptor handed to the bounded child that hung a capturing caller on a SUCCESSFUL sub-second run, and a SIGHUP that abandoned the bounded child permanently on the watchdog arm -- so the runtime guarantee this requirement states did not actually hold when the acceptance was first met. Both are fixed with regression cases (RB23, and RB22 parameterised over HUP), as are the pgid lookup's two blind spots (RB25, RB26) and the scan's per-line hole (RB01m). No count stated deliberately: see R11's acceptance |
| S1 | Phase 2 | — | partial — tab normalization shipped 1.6.1; degraded-list reporting not yet distinct from an unmatched `--type` |
| S2 | Phase 4 | — | shipped on branch |
| S3 | Phase 5 | `cy5` (shared with R11) | open — contract table and per-mode tests not written |
| S4 | Phase 2 | `8ph` | open |
| S5 | Phase 7 | — | open, externally blocked (agy returns 124 on every call) |

**Tickets with no requirement mapping.** `delegate-agy-30m` (P1, unguarded `$HOME` crashes the bridge), `delegate-agy-4vy` and `delegate-agy-4xn` (P3, install and docs hardening) are release-blocking defects surfaced by 1.6.2 work rather than requirement gaps. They are absorbed by Phases 2 and 4 respectively and gated by Phase 6.

**Correction against the tracker (2026-08-19).** `delegate-agy-62x`, previously listed here as S5's open ticket, is CLOSED — closed without ever being verified, so the id-vs-display-name question it raised remains a hypothesis. S5 has no open ticket backing it.
