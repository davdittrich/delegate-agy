---
gsd_state_version: 1.0
milestone: v1.6.2
current_phase: 5
current_phase_name: The shim's failure-mode contract
status: executing
stopped_at: Phase 5 context gathered
last_updated: "2026-08-21T15:49:59.457Z"
last_activity: 2026-08-21
last_activity_desc: Phase 04 complete, transitioned to Phase 5
state_head: 2f271271f87d03efb6ca7c6e02e4d192e98d26f3
progress:
  total_phases: 7
  completed_phases: 5
  total_plans: 23
  completed_plans: 21
milestone_name: milestone
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-21)

**Core value:** Delegation must never break the caller — the shim shadows `gemini` for every PATH caller, so a hang, crash, or silent empty-success here is not scoped to this plugin.
**Current focus:** Phase 5 — The shim's failure-mode contract

## Current Position

Phase: 5 (The shim's failure-mode contract) — READY TO EXECUTE
Plan: Not started
Status: Ready to execute
Last activity: 2026-08-21 — Phase 04 complete, transitioned to Phase 5

Progress: [████████████████████] 21/21 plans overall (Phase 4 complete: 3/3 plans)

## Performance Metrics

**Velocity:**

- Total plans completed: 16
- Average duration: —
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01.5 | 6 | - | - |
| 03 | 4 | - | - |
| 04 | 3 | - | - |

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
| Phase 04 P01 | 27min | 3 tasks | 4 files |
| Phase 04 P02 | 22min | 3 tasks | 4 files |
| Phase 04 P03 | 41min | 3 tasks | 4 files |

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
- [Phase 04]: 04-01: D-05 (sync) landed before D-03 (SIGPIPE fix) -- the branch tip carries the identical unfixed pipeline, so fixing first would have been silently overwritten by the sync
- [Phase 04]: 04-01: D-03a locked next((<gen>), "") over an index-[0] rewrite -- measured (M5) that indexing raises IndexError and aborts under -e on a zero-match reply
- [Phase 04]: 04-01: RED fixture sized >=131072 bytes of producer output (2x the measured 65536-byte pipe capacity) -- the plan's earlier 3-entry fixture was measured to pass 8/8 against the unfixed code and would have been vacuous
- [Phase 04]: [Phase 04]: 04-02: D-06's HOME precondition is locked verbatim by the bead; inserted once per script immediately after refuse-root, exactly one added line each
- [Phase 04]: [Phase 04]: 04-02: D-01's hoisted python3 guard resolves 04-RESEARCH.md's Open Question 1 -- the dependency check moves before the rc-alias loop, but the consent-flag read stays inside the loop per rc file, leaving the existing dry-run advisory untouched
- [Phase 04]: [Phase 04]: 04-02: R8/S2 traceability rows cite I16/I17/I18 by case id only, never by line range -- this plan's own I19/I20/I20b insertions shifted those cases earlier in tests/run-tests.sh, so any range recorded before those insertions would already be stale
- [Phase 04]: [Phase 04]: 04-03: Test B extracts the doc's own second exec line via exact whole-line grep -x, not substring grep -c -- both docs carry a pre-existing legitimate 'e.g. ... bash "$RESOLVED"' prose mention a substring count would collide with
- [Phase 04]: [Phase 04]: 04-03: WR-01's fix hoists only the python3 dependency check into the loop's existing alias-match branch; the _alias_patch_py3_ok flag's own continue gate stays exactly where 04-02 sited it
- [Phase 04]: [Phase 04]: 04-03: closed delegate-agy-5r9.7/.8/.9 (CR-01, CR-02, IN-01, WR-01, WR-02) -- a deep code review found these after 04-01/04-02 shipped; per project rule, review findings are blockers, not deferred. Suite PASS=160 FAIL=0

### Pending Todos

None yet.

### Blockers/Concerns

- **The shim's blast radius is box-wide.** `~/.local/bin/gemini` shadows the real binary for interactive shells, Octopus, and Metaswarm. Weight any shim defect above an equivalent bridge defect.
- **The per-run GEMINI.md policy may not be authoritative.** A probe from a throwaway CWD had agy answer that it found `GEMINI.md` in five unrelated projects, so agy discovers context outside its working directory. `agy_bridge.sh`'s per-type tool restriction assumes its own GEMINI.md binds. Not yet reproduced through the bridge, which also passes `--sandbox` and `--add-dir` (`delegate-agy-xfa`, P1, Phase 1.5).
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

Last session: 2026-08-21T15:20:33.791Z
Stopped at: Phase 5 context gathered
Resume file: .planning/phases/05-the-shim-s-failure-mode-contract/05-CONTEXT.md
