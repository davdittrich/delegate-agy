---
gsd_state_version: 1.0
milestone: v1.6.2
current_phase: 01.5
current_phase_name: Contract check against a real agy
status: executing
stopped_at: Completed 01.5-01-PLAN.md
last_updated: "2026-08-20T02:07:25.581Z"
last_activity: 2026-08-20
last_activity_desc: Phase 01.5 execution started
state_head: 555cbd346938decdfc487a32dfb6a637cce69c4a
progress:
  total_phases: 7
  completed_phases: 0
  total_plans: 12
  completed_plans: 7
milestone_name: milestone
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-19)

**Core value:** Delegation must never break the caller — the shim shadows `gemini` for every PATH caller, so a hang, crash, or silent empty-success here is not scoped to this plugin.
**Current focus:** Phase 01.5 — Contract check against a real agy

## Current Position

Phase: 01.5 (Contract check against a real agy) — EXECUTING
Plan: 2 of 6
Status: Ready to execute
Last activity: 2026-08-20 — Phase 01.5 execution started

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: —
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

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

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Follow-ups discovered during work block the release they belong to — first applied to 1.6.2, so all 7 open tickets gate Phase 6.
- Resolve models from the live `agy models` list, never a frozen display-name map.
- The launcher's exec target is an install-time literal; the registry read is comparison-only.
- OPEN (Phase 1 must settle): bridge treats a missing `timeout` binary as fatal while the shim degrades to unbounded. Both defensible; the divergence is undocumented.
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

### Pending Todos

None yet.

### Blockers/Concerns

- **Master's files lag its history.** `master` merged 1.6.2 at `1a0051c` then content-reverted at `a001d0e`. `git log` shows the fixes; `git show HEAD:file` does not. Completed work lives on `fix/agy-bridge-resilience` at `56be103`, worktree `.worktrees/agy-1.6.2`. Judge state by reading files.
- **The shim's blast radius is box-wide.** `~/.local/bin/gemini` shadows the real binary for interactive shells, Octopus, and Metaswarm. Weight any shim defect above an equivalent bridge defect.
- **The per-run GEMINI.md policy may not be authoritative.** A probe from a throwaway CWD had agy answer that it found `GEMINI.md` in five unrelated projects, so agy discovers context outside its working directory. `agy_bridge.sh`'s per-type tool restriction assumes its own GEMINI.md binds. Not yet reproduced through the bridge, which also passes `--sandbox` and `--add-dir` (`delegate-agy-xfa`, P1, Phase 1.5).
- **R6's empty-success case is real, not hypothetical.** The same probe saw agy exit rc=0 with completely empty stdout when a tool hit a headless permission gate (`jetski: no output produced -- a tool required the "command" permission ... auto-denied`). Phase 3's exit-3 requirement is grounded in observed behavior.
- **agy is live; the docs that said otherwise are corrected, the phases are not yet re-read.** Verified 2026-08-19 against agy 1.1.13: `--version` and `agy models` both return in seconds, and a real `--type review` delegation returned 4721 bytes. `agy --model` accepts BOTH ids and display names; a bogus name gives rc=1 with an `Available models:` list rendered in display names. PROJECT.md and ROADMAP.md are corrected and Phase 7 moved to Phase 1.5; `delegate-agy-9qp` stays open until Phase 1.5 lands the fixtures and the README statement. **Not established:** whether agy ignores SIGTERM -- every probe call returned on its own, so no bound fired and the `-k` rationale rests on its original observation, untested.
- delegate-agy-vtx (P0): run_bounded's watchdog timer leaks one 'sleep <bound>' process per bounded call, reparented to init and alive for the full bound -- up to 3 per gemini invocation with the shim's defaults. Inside the marker block, so 01-02 could not fix it; 01-03 copies the block byte-for-byte and will double the blast radius. Fix both copies in one commit.
- delegate-agy-84e (P1): run_bounded's self-kill guard prints 'no process group of its own; descendants may survive' deterministically for any bounded child that exits before the PGID read -- i.e. every fast successful watchdog-path call. False, and it masks the real signal. Inside the marker block; same both-copies constraint.
- **Phase 1 did not pass on the first attempt, and the record must not read as if it did.** The code review of `bb54c6f` found two Criticals in `run_bounded` itself, both reproduced at runtime, both introduced by this phase: (1) `exec 9>&2` was inherited by the bounded child and every descendant, so under `out=$(gemini ... 2>&1)` -- the commonest capture shape for a CLI that shadows `gemini` box-wide -- a surviving agy descendant held the caller's capture pipe open forever, on a run that exited 0 in under a second, on BOTH mechanisms; (2) SIGHUP was not relayed, so on the watchdog arm a HUP returned from `wait` as 129, cancelled the timer and left agy running with no bound on it at all, while the coreutils arm reaped -- a direct break of the mechanism parity the whole phase rests on. Also fixed in the same round: `trap - TERM INT` destroyed the host's cleanup handlers instead of restoring them (a later Ctrl-C then left the full user prompt in `/tmp/gemini-shim.XXXXXX/GEMINI.md`, since bash runs no EXIT trap for a signal-killed process); the pgid lookup shelled out to `awk`/`ps` and silently stopped reaping descendants where neither resolved; its `/proc` parse returned the PPID for any comm containing whitespace, which then became a `kill -- -<pgid>` operand aimed at an unrelated process group; and RB01 counted violating LINES rather than OCCURRENCES, so two occurrences on one line and a decoy string both scanned clean. **The lesson worth carrying: the suite was green, mutation-checked in five places, and none of it saw any of this** -- every gap was structural (`_PUREBIN_TOOLS` hardcodes the binaries the pgid lookup needed; no case ever sent HUP; no case ever asserted the trap table; the harness fixed fd 9 for ITSELF and left the shipped scripts alone). Regression cases RB23-RB26 and RB22-over-HUP now exist, each demonstrated red against the shipped code before its fix. Suite PASS=123 FAIL=0. R11 is deliberately still open: its acceptance was met before this round, but the runtime guarantee it states did not hold, so the completion call is the human's.

### Roadmap Evolution

- Phase 1.5 changed: re-scoped and moved from Phase 7 to Phase 1.5 (decimal insertion). Its blocking premise -- agy unresponsive, live check unachievable -- was disproven by a bounded read-only probe on 2026-08-19: agy 1.1.13 answers, 'agy models' returns 14 lines of id<TAB>display-name in under 30s, and --model accepts BOTH ids and display names, settling delegate-agy-62x which was closed unverified. Criterion 4 inverted from 'README states the assumption is unverified' to 'README states the verified fact with the agy version and date'. Criterion 2's unverified-verdict path stays mandatory but is no longer the expected outcome. Phase 2 now depends on 1.5's fixtures; Phases 5 and 6 gained it as a dependency. Evidence: delegate-agy-9qp.

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| *(none)* | | | |

## Session Continuity

Last session: 2026-08-20T02:07:25.563Z
Stopped at: Completed 01.5-01-PLAN.md
Resume file: None
