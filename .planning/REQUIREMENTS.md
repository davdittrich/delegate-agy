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
- Constraint: satisfied by `tests/contract-check.sh` — a repo-only tool, run on demand and separate from the unit suite, that spends real quota against the live binary. The "could not ask" path (a hung or absent agy reported as `unverified`, never a false pass) remains a required, tested capability rather than the expected outcome: agy was unreachable a week before this requirement was verified against it, and may be again.

---

## Traceability

| Req | Phase | Open tickets | Status |
|-----|-------|--------------|--------|
| R5 | Phase 3 | — | met — `v5a` and `6q1` both closed (plan 03-04). 137 discrimination shipped (plan 03-01: bridge external-kill, both output forms; plan 03-02: shim external-kill (EC03) and bridge generic-nonzero (EC04) mirrored, EC_KILL9_TAIL pinned across both scripts and README (EC05), exit-137 row restated); plan 03-03 restated README's exit-2/3/124 rows and pinned all four literals with static + runtime agreement (EC06), and ran the exit-2 consistency pass (D-09, zero inconsistencies, `delegate-agy-b7g` left open with explicit disposition); plan 03-04's EC07 closes the remaining gap — every documented exit code now asserted by its exact numeric value: 2, 3, 124 and 137 provoked and asserted (2 bridge-only), cause-fragment exclusivity held across the four; 127 cited (not re-provoked) via `I16`/`RB29`, with two source assertions pinning that those cases still assert `-eq 127` exactly so a later loosening of either fails EC07 instead of silently rotting the citation; the 137-vs-124 discrimination's strict `elapsed < bound` comparison and the error branch's fixed arm order are both pinned as source assertions (edge:R5/adjacency, edge:R5/ordering). **Residue, not closed by this work:** edge:R5/precision — `SECONDS` gives integer-second resolution truncated toward zero, so a SIGKILL landing in the final second before the bound can misclassify as an external kill rather than a timeout; this is shipped Phase-1 behavior, stated here as a named ceiling, and no test in this phase pins sub-second behavior because none can. |
| R6 | Phase 3 | — | met — EC06 (plan 03-03) added runtime regression coverage (byte-identical exit-3 lines across both entry points on identical stderr, all three classifier outcomes driven and asserted, bridge-vs-shim JSON envelope shape divergence documented in README); plan 03-04's EC08 closes criterion 5 fully: the exit-3 failure payload is pinned as never success-shaped on both entry points and both output modes — zero-byte stdout in text mode (asserted via a split-stream capture and `wc -c` on the file, never a command substitution, so a merged capture or a stripped trailing newline cannot make the assertion vacuous), and a `response`-free, non-truthy-`success` JSON envelope parsed with a real JSON parser rather than a substring guess. Also pins that a stdout of exactly one newline byte is NOT empty (`test -s`'s own rule): it passes through as success and round-trips byte-for-byte through all four output shapes (bridge/shim × text/json). EC08's two load-bearing properties (zero-byte-stdout, no-response-key) were each independently demonstrated red under a deliberate one-line mutation and reverted by rewriting the exact line back (never `git checkout`/`restore`/`reset`/`stash`); `git status --porcelain` matched before the first mutation and after the last revert. |
| R8 | Phase 4 | — | met — formally closed in Phase 4 using previously shipped I16/I17/I18 evidence; registry logic unchanged. `I16` (stale pin vs. install registry exits 127; absent/unparseable registry degrades to silence; exec target pinned to the install-time literal), `I17` (registry window bounded to our own entry across empty/compact/semi-compact shapes) and `I18` (apostrophe in the plugin cache path does not break the generated wrapper) hold criteria 1-3. Criterion 5's docs-tier half — the published `/agy-setup`/`/agy-uninstall` fallback one-liner reaching its validating `case` on every registry reply shape instead of aborting — is closed by plan `04-01`'s `I21`/`I21b`. No new registry fixtures were added; `write_wrapper`'s registry-comparison heredoc (`scripts/install.sh:85-182`) is unmodified across this phase's diff (D-07). |
| R11 | Phase 1 | `cy5` | met — both scripts are now converted: the shim's sites as of plan 01-02, the bridge's as of plan 01-03, all through `run_bounded`, all bounded on a host with no `timeout`/`gtimeout`. The divergence this requirement flagged as an open question is dissolved rather than documented (bound always, warn once per run, never fatal); the decision is recorded in `PROJECT.md` §Key Decisions and R11's acceptance is rewritten to match, as of plan 01-04. Both halves of the acceptance have landed: the test that reads the scripts is RB01/RB01m (plan 01-05) and the runtime proof per entry point, on both mechanisms, is RB04/RB05/RB13/RB06b-c (plan 01-06). Re-assessed and met after the phase-01 fix round; the qualifier that follows records why it was NOT met at the moment the acceptance was first satisfied: the code review found two Criticals in the mechanism itself -- a descriptor handed to the bounded child that hung a capturing caller on a SUCCESSFUL sub-second run, and a SIGHUP that abandoned the bounded child permanently on the watchdog arm -- so the runtime guarantee this requirement states did not actually hold when the acceptance was first met. Both are fixed with regression cases (RB23, and RB22 parameterised over HUP), as are the pgid lookup's two blind spots (RB25, RB26) and the scan's per-line hole (RB01m). No count stated deliberately: see R11's acceptance |
| S1 | Phase 2 | — | met — tab/extra-column normalization and distinct degraded-list reporting proven end to end on both entry points: the bridge (plan 02-01: R9c, R8/R9b) and the shim (plan 02-02: SH15c). Anchored matchers unchanged on both sides. |
| S2 | Phase 4 | — | met — formally closed in Phase 4 using previously shipped I16/I17/I18 evidence; registry logic unchanged. `I17` covers the bounded extraction window across the empty-array, compact and semi-compact registry shapes; `I16`'s lookalike-adjacent fixture (a neighbouring marketplace entry placed immediately beside our own key) covers no-cross-plugin misattribution. Any parse failure degrades to silence, never a false refusal, matching S2's own acceptance. |
| S3 | Phase 5 | `cy5` (shared with R11 — stays open on R11's account, not S3's) | met — all five failure-mode rows (missing dependency, superseded pin, hung agy, unparseable model list, unrecognized model name) name both `agy-bridge` and the `gemini` shim and state sameness or a one-line reason for the divergence; missing dependency and superseded pin landed in plan 05-01, hung agy/unparseable model list/unrecognized model name landed in plan 05-02. `FM01` (`tests/run-tests.sh`) is the gate: it fails if a row loses an entry-point name, its disposition clause, or its quoted literal, and its `_FM_PAIRS` array binds each row BY NAME to a live proof (RB02, RB03, EC06, SH14, SH9, I16), so a row cannot silently unbind from its evidence. Stated ceiling: FM01 proves row SHAPE only — that a reason is present, never that it is true; that half is settled by each plan's own `<human-check>` verdict, recorded in 05-01-SUMMARY.md and 05-02-SUMMARY.md, not by grep. |
| S4 | Phase 2 | — | met — `delegate-agy-8ph` closed. Both writers of `~/.cache/agy-bridge-models` now carry the write gate (D-03), the stale-cache fallback (D-04) and atomic-write preservation: the bridge (plan 02-01: R9, R9b) and the shim (plan 02-02: SH15, SH15b). No one-sided fix landed. |
| S5 | Phase 1.5 | `xfa` | met — `tests/contract-check.sh` (plans 01.5-01 through 01.5-06) exercises real agy 1.1.13 and reports which of D-09's seven assumptions hold, run once against the live binary on 2026-08-20: 6 **verified** (`agy-version-shape`, `models-format`, `non-gemini-rows`, `invalid-model-rejection`, `gemini-md-binds`, `model-arg-accepts` — both a bare id and a display name were accepted), 1 **contradicted** (`sigterm-ignored`: agy died on `SIGTERM` alone this run, contradicting R11's `-k` escalation rationale — `delegate-agy-i43` filed against it, not acted on in this phase by design, a phase-boundary deferral). `empty-success-capture` is a stated, honest capture-attempt gap (the headless permission gate did not fire this run), not a scored assumption. S5's acceptance is that the check *reports* which assumptions hold, not that every one does — the contradicted row is a success of this requirement, not a failure of it, and is visible here without opening the ledger. |

**Risk note (R8/S2, A2, Phase 4).** The registry key match inside `write_wrapper` (`scripts/install.sh:85-182`) is a literal byte comparison, and the version is matched against `^[0-9]+(\.[0-9]+)*$`, both ASCII-only by construction. A registry key differing only by Unicode normalization form (NFC vs. NFD) would therefore fail the exact-key match, and the launcher would degrade to silence rather than repin or refuse. This is the safe failure direction and satisfies S2's own "degrades to silence, never a false refusal" acceptance — an accepted assumption, not an open defect and not a closed one. No test was added for it (D-07).

**Tickets with no requirement mapping.** `delegate-agy-30m` (P1, unguarded `$HOME` crashes the bridge), `delegate-agy-4vy` and `delegate-agy-4xn` (P3, install and docs hardening) are release-blocking defects surfaced by 1.6.2 work rather than requirement gaps. They are absorbed by Phases 2 and 4 respectively and gated by Phase 6.

**Correction against the tracker (2026-08-19).** `delegate-agy-62x`, previously listed here as S5's open ticket, is CLOSED — closed without ever being verified, so the id-vs-display-name question it raised remains a hypothesis. S5 has no open ticket backing it.

**S5's tickets, updated (2026-08-20).** `delegate-agy-9qp` (the stale blocker claiming agy could not be reached, previously repeated in this document, `PROJECT.md` and `STATE.md`) closes with this correction landing — see `bd` for the closure. `delegate-agy-xfa` (does the per-run `GEMINI.md` policy actually bind against a competing `GEMINI.md` outside the granted work dir?) resolves `verified` on this phase's `gemini-md-binds` evidence: the decoy's marker did not leak and the forbidden tool was declined. It stays open pending its own closure step; the run's evidence is recorded in the ticket's comment, not repeated here.
