---
phase: 02
slug: model-list-handling-end-to-end
status: verified
threats_open: 0
asvs_level: 1
created: 2026-08-20
---

# Phase 02 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

> **Scope note:** at audit time (2026-08-20, before the merge below), `master`'s
> checked-out `scripts/agy_bridge.sh` / `scripts/gemini_shim.sh` did **not**
> contain this phase's code — `master` had merged 1.6.2 then content-reverted
> at `a001d0e` (documented in `.planning/STATE.md`, "Master's files lag its
> history"). All code in this register was read from and verified against
> branch `fix/agy-bridge-resilience`, worktree `.worktrees/agy-1.6.2`,
> HEAD `dbbd81f`. **Update:** `fix/agy-bridge-resilience` was merged into
> `master` the same day at `54d4772` (5-file conflict, resolved in the
> branch's favor per the revert's own "hold, not a discard" note; full suite
> re-run post-merge, `PASS=145 FAIL=0`). The 5 conflicted files
> (`README.md`, `scripts/agy_bridge.sh`, `scripts/install.sh`,
> `tests/fake-agy.sh`, `tests/run-tests.sh`) were diffed byte-identical
> against the branch tip before committing. This register now applies to
> `master` as checked out.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| `agy` subprocess stdout → bridge | Untrusted, unvalidated third-party CLI output crosses at `scripts/agy_bridge.sh:475-476`. Format/content/size outside project control. | model-id list (id\<TAB\>display name) |
| bridge → `~/.cache/agy-bridge-models` | Bridge persists that output to a file `scripts/gemini_shim.sh` also reads as authoritative for up to 60 minutes. | cached model-id list |
| `agy` subprocess stdout → shim | Same untrusted source crosses at `scripts/gemini_shim.sh:412`. | model-id list |
| shim → `~/.cache/agy-bridge-models` | `load_models()` persists to the same file the bridge reads. Second, independent writer to the shared cache. | cached model-id list |
| cache file → `--model` argv | Cached content becomes a subprocess argv value at `agy_bridge.sh:673` (auto-select `:548-549`, validation `:553`) and via `map_model()`'s live-id/class resolution in the shim. | model id string |
| shim → every PATH caller of `gemini` | Shim installs as `~/.local/bin/gemini`, shadowing the real binary for Octopus, Metaswarm, interactive shells. Anything written to stderr, or any failure mode, reaches processes unaware of this project. | stderr diagnostics, process exit code |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-02-01 | Tampering | `agy_bridge.sh` cache write (`:481-495`) | medium | mitigate | Write gated on `cut -f1` normalization + `grep -q '^gemini-'` match before the tmp-then-`mv` write; a degraded/unauthenticated reply is never persisted. Verified present at `:482-483,493-495`, and behaviorally confirmed live (UAT-02 test 1: zero-byte reply never reaches the cache, absent or present). | closed |
| T-02-02 | Tampering | `~/.cache/agy-bridge-models` as `--model` input | medium | mitigate | `chmod 600` (`:495`), atomic tmp-then-`mv` (`:493-494`), `${HOME:-/nonexistent}` path guard (`:468`), `cut -f1` normalization (`:534`), `grep -qxF` exact-id validation (`:553`) — all present and unchanged in shape from the plan. | closed |
| T-02-03 | Denial of service | Bridge D-04 stale-cache fallback | low | mitigate | Fallback reads via `cat` and never writes; mtime — and the `find -mmin +60` TTL window — stay at the last good write. Behaviorally confirmed live: UAT-02 test 1's R9b-EMPTY case asserts `find -mmin +60` still matches after the fallback call. | closed |
| T-02-04 | Information disclosure | agy stderr relay, unconditional (`:521-523`) | low | accept | Fires on every path with content, success (degraded or not) or failure alike — required as the only auth/network diagnostic available. Prefixed, stderr-only, never stdout/JSON. Confirmed present at `:521-523`, unchanged guarantee from pre-phase behavior — accepted disposition, no further action. | closed |
| T-02-05 | Tampering | Two independent writers (bridge + shim), one cache path | low | accept | Both writers use per-file atomic `mv`, satisfying the write-atomicity acceptance criterion; no lock added by design (`delegate-agy-8ph` explicitly scopes this phase to the cache-poisoning gate, not a coordination mechanism). Recorded as an untested-under-concurrency property — accepted, not verified beyond atomicity of each individual write. | closed |
| T-02-06 | Tampering | `gemini_shim.sh` cache write (`load_models()` `:417-434`) | medium | mitigate | Same `cut -f1` + `grep -q '^gemini-'` gate as T-02-01, mirrored on the shim's writer. Verified present at `:420-421,432-434`, and behaviorally confirmed live (UAT-02 test 1: SH15-EMPTY, nothing cached from a zero-byte reply). | closed |
| T-02-07 | Denial of service | `load_models()` under `set -euo pipefail` | medium | mitigate | Function contract: never fails its caller (a non-zero return would abort `gemini` for every PATH caller, not just this plugin). New gate/arm both sit inside the existing `[[ -n "$raw" ]]` guard; `return 0` (`:453`) is unconditional and unmoved. Verified present. | closed |
| T-02-08 | Information disclosure | Shim stderr reaching unrelated PATH callers | low | mitigate | No stderr line added on the degraded path (D-05) — silent by design, since a warning would land in every Octopus/Metaswarm log line. Behaviorally confirmed live: UAT-02 test 1's SH15-EMPTY/SH15b-EMPTY cases assert no `WARNING` in output. | closed |
| T-02-09 | Tampering | `~/.cache/agy-bridge-models` as `--model` input (shim side) | medium | mitigate | `chmod 600` (`:434`), atomic tmp-then-`mv` (`:432-433`), `${HOME:-/nonexistent}` guard (`:398`), `cut -f1` (`:420`), verbatim live-id check (`:462`), anchored class matcher (`:471`) — all present. | closed |
| T-02-10 | Denial of service | Shim D-04 stale-cache fallback | low | mitigate | Reads via `cat`, never writes; mtime/TTL window unaffected. Behaviorally confirmed live: UAT-02 test 1's SH15b-EMPTY case asserts `find -mmin +60` still matches after the fallback call. | closed |
| T-02-SC | Tampering | npm/pip/cargo installs | low | accept | Phase installs no packages, adds no dependency — surface is two bash scripts and one test file. No supply-chain checkpoint applies. | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on (`high`) count toward `threats_open`*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-02-01 | T-02-04 | Unconditional stderr relay of agy's own diagnostic is required to keep auth/network faults debuggable on the degraded-but-successful path; stderr-only, no new stream/destination. | Dennis Alexis Valin Dittrich | 2026-08-20 |
| AR-02-02 | T-02-05 | Two independent atomic writers to one cache path is accepted without a lock — `delegate-agy-8ph` scoped this phase to the poisoning gate only; concurrent-write interleaving is an untested property, not a verified-safe one. | Dennis Alexis Valin Dittrich | 2026-08-20 |
| AR-02-03 | T-02-SC | No new dependency introduced by this phase. | Dennis Alexis Valin Dittrich | 2026-08-20 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-08-20 | 11 | 11 | 0 | Claude (orchestrator, L1 grep-level verification + live behavioral confirmation from UAT-02 test 1; short-circuited per `threats_open:0 AND register_authored_at_plan_time:true AND asvs_level==1` — no auditor subagent spawned) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-08-20 — scoped to `fix/agy-bridge-resilience` @ `dbbd81f` (see Scope note above); re-verify after merge to `master`.
