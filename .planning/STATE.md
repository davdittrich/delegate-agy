---
gsd_state_version: 1.0
milestone: v1.6.2
current_phase: 03
current_phase_name: the-exit-code-contract
status: verifying
stopped_at: Completed 03-04-PLAN.md
last_updated: "2026-08-20T22:58:08.672Z"
last_activity: 2026-08-20
last_activity_desc: Phase 03 execution started
state_head: 027a89bc6302964cb409b9719ca3cf3fff3f0505
progress:
  total_phases: 7
  completed_phases: 3
  total_plans: 18
  completed_plans: 18
milestone_name: milestone
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-20)

**Core value:** Delegation must never break the caller — the shim shadows `gemini` for every PATH caller, so a hang, crash, or silent empty-success here is not scoped to this plugin.
**Current focus:** Phase 03 — the-exit-code-contract

## Current Position

Phase: 03 (the-exit-code-contract) — EXECUTING
Plan: 4 of 4
Status: Phase complete — ready for verification
Last activity: 2026-08-20 — Phase 03 execution started

Progress: [░░░░░░░░░░░░░░░░░░░░] 14/14 plans overall (Phase 02 complete: 2/2 plans; Phase 3 not yet planned)

## Performance Metrics

**Velocity:**

- Total plans completed: 15
- Average duration: —
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01.5 | 6 | - | - |
| 01 | 6 | - | - |
| 02 | 3 | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

*Updated after each plan completion*
**Per-Plan Metrics:**

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 01 P01 | 4h 30m | 3 tasks | 3 files |
| Phase 01 P02 | 1h 10m | 2 tasks | 1 files |
| Phase 01 P03 | 35m | 3 tasks | 1 files |
| Phase 01 P04 | 18min | 3 tasks | 3 files |
| Phase 01 P05 | 50min | 3 tasks | 1 files |
| Phase 01 P06 | 4h 40m | 3 tasks | 2 files |
| Phase 01.5 P01 | 1h20m | 3 tasks | 3 files |
| Phase 01.5 P02 | 55min | 2 tasks | 1 files |
| Phase 01.5 P03 | 45min | 2 tasks | 3 files |
| Phase 01.5 P04 | 30min | 3 tasks | 2 files |
| Phase 01.5 P05 | 55min | 3 tasks | 1 files |
| Phase 01.5 P06 | 31min | 3 tasks | 4 files |
| Phase 03 P01 | 40min | 2 tasks | 3 files |
| Phase 03 P02 | ~30min | 3 tasks | 4 files |
| Phase 03 P03 | ~1h10min | 3 tasks | 2 files |
| Phase 03 P04 | 1h | 3 tasks | 2 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Follow-ups discovered during work block the release they belong to — first applied to 1.6.2, so all 7 open tickets gate Phase 6.
- Resolve models from the live `agy models` list, never a frozen display-name map.
- The launcher's exec target is an install-time literal; the registry read is comparison-only.
- The stdin read gets an explicit positive `kill_after`, not a zero mirroring the bare `timeout <secs> cat` it replaces — so `run_bounded` validates every bound with one rule and no site can pass a value coreutils reads as *no timeout*. (Phase 1, plan 02)
- The missing-binary warning is emitted at the `TIMEOUT_BIN` probe, never inside `run_bounded` — the probe runs once per invocation while the helper runs up to three times, and plain stderr rather than fd 9 puts the line ahead of every bounded call's output. (Phase 1, plan 02)
- [Phase ?]: 01-03: deleted the bridge's startup fatal on a missing timeout/gtimeout rather than documenting the divergence -- its only justification was that an unbounded call beats a refusal, and the watchdog leaves no unbounded call to refuse
- [Phase ?]: 01-03: the bridge's stdin-read kill_after is 1, derived from cat not ignoring SIGTERM, not the 5 the agy sites carry for a SIGTERM-ignoring child
- [Phase ?]: 01-03: added no permanent test case -- the phase coverage split allocates plan 01-03 no RB id; red was observed via uncommitted probes and recorded in the summary and on the beads
- [Phase ?]: Phase 1's recorded decision is *always bounded* — none of delegate-agy-cy5's three candidate designs; the premise that a missing timeout binary forces a tradeoff was rejected
- [Phase ?]: coreutils demoted from dependency to recommendation in README and PROJECT.md; it buys process-group kill, not the bound
- [Phase ?]: 01-05: criterion 4 enforced as a static invariant over both scripts (RB01), with committed mutation cases wherever the scan logic could go vacuous
- [Phase ?]: 01-05: RB08 drives its prompt via stdin -- an argument-driven version was a proven false negative because the fetch and delegation sites redirect stderr into files
- [Phase ?]: 01-06: RB13 asserts 124 at the entry point, not at the mechanism: coreutils timeout -k measurably returns 137 against a SIGTERM-ignoring child because its own SIGKILL to its process group reaches itself; both entry points map it to 124, so unify-124 is a property of what the caller sees
- [Phase ?]: 01-06: Runtime descendant cases capture into files, not command substitutions: each script's fd 9 is inherited by agy and its forks, so under a command substitution a failing descendant assertion blocks for the fake's full 300s instead of failing
- [Phase ?]: 01-06: The forking fake ignores SIGHUP as well as SIGTERM: without it the pty session's hangup reaps the pair and the with-terminal descendant assertion passes while asserting nothing
- [Phase ?]: 01-06: The PTY allocator's argv form is chosen by probing script --version, never by uname, with both flavour branches pinned on one host via a stubbed probe result
- [Phase 01.5]: 01.5-01: tracer-feedback gate observed -- committed Task 1, paused for human confirmation of real-agy and absent-binary runs, then proceeded to Task 2/3 after approval
- [Phase 01.5]: 01.5-01: two literal acceptance-criteria shell commands (grep for 'set -euo pipefail' substring; PATH=/nonexistent bash invocation) could not pass/run as literally typed due to D-03's mandated verbatim comment text and bash's own command-prefix PATH lookup semantics -- verified via intent-equivalent checks instead, documented in SUMMARY, no code changed
- [Phase 01.5]: 01.5-01: CC01's sanitized PATH needed an explicit 'timeout' entry beyond the existing _PUREBIN_TOOLS whitelist -- the outer bounding wrapper itself must resolve under CC01's fully-replaced PATH, unlike every other _purebin() caller which keeps the harness's original PATH available for its own outer safety net
- [Phase 01.5]: 01.5-02: CC02 reuses _purebin()'s directory (fake agy present, no timeout/gtimeout by design per RB00a) and composes an external `timeout 30` via `env PATH=...` rather than mutating that shared directory or reusing _run_sanitized's own safety net as the bound
- [Phase 01.5]: 01.5-02: CC03's isolation scan needed a dedicated _cc_raw_segments helper (same split as _rb_agy_segments, without its noise-stripping) because that stripping erases the leading PATH= assignment CC01/CC02's own invocations rely on as their clearing signal -- found live when the scan first ran against the real, correct file
- [Phase 01.5]: 01.5-02: CC03m's mutation payloads are assembled from separator-free arguments joined inside the harness function's own code, not as a literal `;` in a probe's call-site text, because that text is itself part of the file the scan reads
- [Phase 01.5]: 01.5-03: preflight-once design -- agy --version and agy models each called exactly once per run, reused by three probes; agy models requires </dev/null or it hangs indefinitely
- [Phase 01.5]: 01.5-03: invalid-model-rejection derives its verdict from whether agy's rejection names the impossible id WE supplied, never from pinned message text
- [Phase 01.5]: 01.5-04: fake-agy.sh reads tests/fixtures/agy-models.tsv at runtime via _fake_fixture (three-tier resolution: AGY_FIXTURES_DIR, dirname $0/fixtures, $AGY_PLUGIN_DIR/tests/fixtures), loud non-zero on total failure or zero-row fixture -- never a silent empty list (D-14, D-14a)
- [Phase 01.5]: 01.5-04: R2, R4, and CC06 all derive their expected model id via _cc_expect_model (shipped grep|sort -V|tail -1 rule) instead of pinning a literal, so a fixture recapture cannot leave a stale expectation passing silently (D-15a)
- [Phase 01.5]: [Phase 01.5]: 01.5-05: gemini-md-binds (D-10) verified against real agy 1.1.13 with a competing decoy GEMINI.md present -- forbidden run_shell_command declined, cksum discriminator absent, decoy marker did not leak; delegate-agy-xfa updated with evidence, left open for 01.5-06 (D-18) to close
- [Phase 01.5]: [Phase 01.5]: 01.5-05: sigterm-ignored (D-12) contradicted -- real agy 1.1.13 died on SIGTERM alone (rc=124) under a strict 8s bound; R11's -k escalation rationale not reproduced this run; delegate-agy-i43 filed rather than changing run_bounded/R11 in this phase (phase boundary)
- [Phase 01.5]: [Phase 01.5]: 01.5-05: model-arg-accepts aggregates two observations (F6) -- a bare id harvested free from the gemini-md-binds probe's already-billed bridge call, plus a direct display-name call -- keeping the whole run's billed count at 2 (within D-13's budget of 3), both accepted against real agy
- [Phase 01.5]: S5 corrected: README states the verified --model fact (both ids and display names) with agy 1.1.13/2026-08-20; REQUIREMENTS.md moves S5 to Phase 1.5, status met, naming the one contradicted assumption (sigterm-ignored, delegate-agy-i43) plainly
- [Phase 02]: 02-01: D-03's write gate lives on the fetch-success branch only; the no-cache degraded path leaves `$_agy_models` untouched so the shipped criterion-3 check (now use-time, herestring form under D-08) is what reports the degraded-list message -- clearing it unconditionally would let the generic retrieval-failure fatal fire first and lose R8's distinct message
- [Phase 02]: 02-01: D-08's herestring exception is scoped to exactly two sites in `agy_bridge.sh` (the new write-gate and the existing `:515`-era use-time check) -- a narrow, user-approved carve-out of D-01/D-02's closed-criteria boundary after Codex found the `printf | grep -q` pipe form shares the same SIGPIPE hazard class it was chosen to avoid (reproduced empirically, bash 5.3.15)
- [Phase 02]: 02-01: D-07's stderr relay is relocated (one line moved to fire unconditionally after the whole fetch if/elif/else), not duplicated per branch -- folded into this plan's Task 2 rather than raised as a follow-up bd issue, closing the last open half of criterion 3 in this phase instead of a later one
- [Phase 02]: 02-01: D-06's synthetic 3-column/trailing-tab fixture lives in a scratch `AGY_FIXTURES_DIR`, never in `tests/fixtures/agy-models.tsv` (D-14/D-14a's captured-vs-synthetic separation)
- [Phase 02]: 02-01: S4 (`delegate-agy-8ph`) and S1 both stay "partial" in REQUIREMENTS.md, not "met" -- `8ph` explicitly forbids a one-sided fix, so both requirements close only after plan 02-02 mirrors the same gate/fallback into `gemini_shim.sh`
- [Phase 02]: 02-02: the shim's write gate lives entirely inside `load_models()` -- a new `ids` local (cut -f1-normalized) gates the existing tmp-then-mv write; the D-04 fallback is one `elif [[ -s "$MODELS_CACHE" ]]; then raw=""; fi` on the same if, no new branch, no second cache read
- [Phase 02]: 02-02: unlike the bridge, the shim adds no stderr line on the degraded-fallback path (D-05) -- this script shadows `gemini` on PATH, so a warning here would land in every Octopus/Metaswarm log line; the bridge's D-07 stderr-relocation gap does not apply here since `load_models()`'s fetch already redirects agy's own stderr to `2>/dev/null`
- [Phase 02]: 02-02: D-08's herestring conversion touches exactly two sites in `gemini_shim.sh` -- the new write-gate and the existing `map_model` warning-gate check (formerly a `printf | grep -q` pipe) -- mirroring plan 02-01's identical, narrow D-01/D-02 exception on `agy_bridge.sh`; `map_model`'s verbatim-id and class-resolution matchers are untouched
- [Phase 02]: 02-02: `delegate-agy-8ph` closed -- both writers of `~/.cache/agy-bridge-models` (`agy_bridge.sh` plan 02-01, `gemini_shim.sh` plan 02-02) now carry the write gate, the D-04 stale-cache fallback and atomic-write preservation; S1 and S4 both move to "met" in REQUIREMENTS.md. Suite PASS=141 FAIL=0.
- [Phase 03]: 03-01: EC_KILL9_TAIL holds only the fixed variable-free tail ' -- possible OOM or external kill', not the whole sentence -- both output forms keep their existing, already-differing prefixes untouched
- [Phase 03]: 03-01: _err_txt is computed once via $(cat "$STDERR_FILE" 2>/dev/null || true) immediately before the plain-text/JSON branch, guarded once via ${_err_txt:+...}, and is the single normalization point both output forms defer to -- the JSON path's open(sys.argv[5]).read() is deleted, not guarded
- [Phase 03]: 03-01: the JSON path's error string is now trailing-newline-stripped (decided behavior change, not a bug fix) -- text\n\n now yields ': text', matching the plain-text arm's pre-existing $(cat ...) behavior
- [Phase 03]: [Phase 03]: 03-02: the shim's EC_KILL9_TAIL mirrors the bridge's literal exactly (not just equivalent wording) so EC03's cross-script comparison is a meaningful byte-identity check, not two independently-written expected strings
- [Phase 03]: [Phase 03]: 03-02: EC05's mutation-red proof (T-03-08) is a manual, git-status-tracked verification of the real file during task execution, not a permanent self-mutating suite case -- matches RB03's own static-provenance shape
- [Phase 03]: [Phase 03]: 03-03: README's exit-124 row quotes both timeout literals as bridge-text-vs-bridge-JSON divergence, not bridge-vs-shim -- the two entry points' TEXT forms are byte-identical
- [Phase 03]: [Phase 03]: 03-03: D-09 exit-2 consistency pass found zero inconsistencies among 25 call sites in agy_bridge.sh; delegate-agy-b7g recorded with explicit left-for-another-phase disposition, no production change
- [Phase 03]: [Phase 03]: 03-04: EC07's cause-fragment exclusivity check is scoped to the bridge's four captured messages (137/124/3/2), not all seven runtime invocations -- the bridge is the only entry point that reaches all four codes
- [Phase 03]: [Phase 03]: 03-04: exit 127 is cited via four source assertions (not two) -- the two Codex-named -eq127 exactness pins plus two more pinning the negative half (-z OUT_STALE / -z RB29_SOUT) that must_haves separately require
- [Phase 03]: [Phase 03]: 03-04: EC07's four self-referential grep patterns use escaped ERE metacharacters so the grep invocation's own source line can never satisfy the pattern it searches for -- verified empirically via an empty detail string
- [Phase 03]: [Phase 03]: 03-04: EC07/EC08 were written in one Edit pass then split into two commits by temporarily removing and re-inserting the EC08 block, preserving per-task bd-id traceability without any destructive git operation
- [Phase 03]: [Phase 03]: 03-04: R5's REQUIREMENTS.md row is closed met but names the integer-second SECONDS-precision ceiling (edge:R5/precision) as a stated residue rather than an implied closure

### Pending Todos

None yet.

### Blockers/Concerns

- **Master's files no longer lag for the 5 conflicted files — 3 non-code files still do.** `master` merged 1.6.2 at `1a0051c`, content-reverted at `a001d0e` (8 files), then re-merged `fix/agy-bridge-resilience` at `54d4772` after Phase 2 closed the follow-ups the hold was waiting on — 5-file conflict (`README.md`, `scripts/agy_bridge.sh`, `scripts/install.sh`, `tests/fake-agy.sh`, `tests/run-tests.sh`) resolved in the branch's favor, diffed byte-identical against the branch tip, full suite clean post-merge (`PASS=145 FAIL=0`). `scripts/gemini_shim.sh` was never reverted (added after `a001d0e`) and is current too. Still stale: `.claude-plugin/plugin.json` (version reads `1.6.1`) and `.claude/commands/agy-setup.md`/`agy-uninstall.md` (describe the pre-fix flow) — these 3 fell outside the 5-file conflict, so the merge left them on `a001d0e`'s reverted content. Filed as `delegate-agy-k0f` (P3). Judge state by reading files, not the commit graph.
- **The shim's blast radius is box-wide.** `~/.local/bin/gemini` shadows the real binary for interactive shells, Octopus, and Metaswarm. Weight any shim defect above an equivalent bridge defect.
- **The per-run GEMINI.md policy may not be authoritative.** A probe from a throwaway CWD had agy answer that it found `GEMINI.md` in five unrelated projects, so agy discovers context outside its working directory. `agy_bridge.sh`'s per-type tool restriction assumes its own GEMINI.md binds. Not yet reproduced through the bridge, which also passes `--sandbox` and `--add-dir` (`delegate-agy-xfa`, P1, Phase 1.5).
- **R6's empty-success case is real, not hypothetical.** The same probe saw agy exit rc=0 with completely empty stdout when a tool hit a headless permission gate (`jetski: no output produced -- a tool required the "command" permission ... auto-denied`). Phase 3's exit-3 requirement is grounded in observed behavior.
- **agy is live; the docs that said otherwise are corrected, the phases are not yet re-read.** Verified 2026-08-19 against agy 1.1.13: `--version` and `agy models` both return in seconds, and a real `--type review` delegation returned 4721 bytes. `agy --model` accepts BOTH ids and display names; a bogus name gives rc=1 with an `Available models:` list rendered in display names. PROJECT.md and ROADMAP.md are corrected and Phase 7 moved to Phase 1.5; `delegate-agy-9qp` stays open until Phase 1.5 lands the fixtures and the README statement. **Not established:** whether agy ignores SIGTERM -- every probe call returned on its own, so no bound fired and the `-k` rationale rests on its original observation, untested.
- **Phase 1 did not pass on the first attempt, and the record must not read as if it did.** The code review of `bb54c6f` found two Criticals in `run_bounded` itself, both reproduced at runtime, both introduced by this phase: (1) `exec 9>&2` was inherited by the bounded child and every descendant, so under `out=$(gemini ... 2>&1)` -- the commonest capture shape for a CLI that shadows `gemini` box-wide -- a surviving agy descendant held the caller's capture pipe open forever, on a run that exited 0 in under a second, on BOTH mechanisms; (2) SIGHUP was not relayed, so on the watchdog arm a HUP returned from `wait` as 129, cancelled the timer and left agy running with no bound on it at all, while the coreutils arm reaped -- a direct break of the mechanism parity the whole phase rests on. Also fixed in the same round: `trap - TERM INT` destroyed the host's cleanup handlers instead of restoring them (a later Ctrl-C then left the full user prompt in `/tmp/gemini-shim.XXXXXX/GEMINI.md`, since bash runs no EXIT trap for a signal-killed process); the pgid lookup shelled out to `awk`/`ps` and silently stopped reaping descendants where neither resolved; its `/proc` parse returned the PPID for any comm containing whitespace, which then became a `kill -- -<pgid>` operand aimed at an unrelated process group; and RB01 counted violating LINES rather than OCCURRENCES, so two occurrences on one line and a decoy string both scanned clean. **The lesson worth carrying: the suite was green, mutation-checked in five places, and none of it saw any of this** -- every gap was structural (`_PUREBIN_TOOLS` hardcodes the binaries the pgid lookup needed; no case ever sent HUP; no case ever asserted the trap table; the harness fixed fd 9 for ITSELF and left the shipped scripts alone). Regression cases RB23-RB26 and RB22-over-HUP now exist, each demonstrated red against the shipped code before its fix. Suite PASS=135 FAIL=0 (re-confirmed 2026-08-20). R11 is now Validated (PROJECT.md, Phase 1): 28/29 UAT checks passed directly, 1 (macOS job-control notice) explicitly accepted unverified (no macOS host available), 15/15 security threats closed. Two bugs surfaced by this phase's own code review (delegate-agy-vtx, delegate-agy-84e) are fixed and closed, guarded by RB20a/b and RB21a/b.

- **RB01's static scan doesn't cover `tests/contract-check.sh`.** T-01-06's regression guard (RB01) scans only the two shipped scripts. `contract-check.sh` (added Phase 1.5) carries 3 agy call sites, hand-verified `run_bounded`-wrapped, but not in RB01's loop — a future edit there could add an unbounded call site with the suite staying green. `delegate-agy-d4t` filed (Phase 1 security audit, 2026-08-20).

### Roadmap Evolution

- Phase 1.5 changed: re-scoped and moved from Phase 7 to Phase 1.5 (decimal insertion). Its blocking premise -- agy unresponsive, live check unachievable -- was disproven by a bounded read-only probe on 2026-08-19: agy 1.1.13 answers, 'agy models' returns 14 lines of id<TAB>display-name in under 30s, and --model accepts BOTH ids and display names, settling delegate-agy-62x which was closed unverified. Criterion 4 inverted from 'README states the assumption is unverified' to 'README states the verified fact with the agy version and date'. Criterion 2's unverified-verdict path stays mandatory but is no longer the expected outcome. Phase 2 now depends on 1.5's fixtures; Phases 5 and 6 gained it as a dependency. Evidence: delegate-agy-9qp.

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| *(none)* | | | |

## Session Continuity

Last session: 2026-08-20T22:58:08.642Z
Stopped at: Completed 03-04-PLAN.md
Resume file: None
