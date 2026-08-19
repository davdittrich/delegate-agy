---
phase: 01-the-missing-timeout-decision
plan: 01
subsystem: infra
tags: [bash, process-groups, job-control, timeout, coreutils, signals, file-descriptors, testing]

# Dependency graph
requires: []
provides:
  - "`run_bounded <secs> <kill_after> -- cmd…` in `scripts/gemini_shim.sh`, between `# --- BEGIN run_bounded ---` / `# --- END run_bounded ---`, self-contained apart from `TIMEOUT_BIN` and fd 9 — ready to be copied verbatim into the bridge"
  - "`_rb_pgid_of` (guarded, digit-normalised PGID reader) and `_rb_signal` (group-or-pid signal relay)"
  - "`RUN_BOUNDED_KILLED` authoritative kill flag and the `RB_WATCHDOG_KILLED_NOTE` literal"
  - "fd 9 in `scripts/gemini_shim.sh` — a duplicate of the script's original stderr, opened before any capture redirect"
  - "The shim's delegation site rewired through `run_bounded`, with no mechanism-aware conditional left"
  - "`FAKE_AGY_FORK_HANG` / `FAKE_AGY_PID_FILE` / `FAKE_AGY_CHILD_PID_FILE` in `tests/fake-agy.sh`"
  - "`_purebin` (explicit-tool-list sandbox bin) and `_run_sanitized` (PATH fully replaced) in `tests/run-tests.sh`"
  - "Cases RB00a, RB00b, RB04"
affects: [01-02 remaining shim sites and the probe warning, 01-03 verbatim copy into the bridge, 01-04 README literals, 01-05 static scan, 01-06 helper-contract and PTY cases, phase-03 exit-code contract]

actuals:
  tokens: 30610
  tasks: 3
  commits: 4

tech-stack:
  added: []
  patterns:
    - "Bounded invocation as the primary abstraction; mechanism selection is an internal detail of one function"
    - "bash `set -m` process-group isolation plus `kill -- -<pgid>`, with a self-group guard, as a coreutils-free bounding mechanism"
    - "A dedicated diagnostic file descriptor (fd 9) duplicating the script's original stderr, so helper diagnostics cannot enter a caller-parsed capture file"
    - "Sanitized-PATH test execution built from an explicit, named tool list rather than a prepending sandbox"

key-files:
  created: []
  modified:
    - .worktrees/agy-1.6.2/scripts/gemini_shim.sh
    - .worktrees/agy-1.6.2/tests/run-tests.sh
    - .worktrees/agy-1.6.2/tests/fake-agy.sh

key-decisions:
  - "unify-124: a call killed by the bash watchdog reports exit 124, identical to the coreutils path, with a stderr marker naming the mechanism (D-02). Confirmed at the Task 2 checkpoint; distinct-code rejected."
  - "The kill fact is set by the branch that performed the kill, never derived from elapsed time. Duration-based discrimination stays confined to its existing job of telling an external kill from the script's own escalation."
  - "The timer subshell's stdio is detached, because cancelling it orphans its current `sleep`, and an orphan holding the caller's stdout open would block a caller that captured it for the rest of the bound."
  - "`_rb_pgid_of` normalises to digits at its single exit, so neither reader can hand back a padded value that would fail the guard open."
  - "The forking fake's parent blocks in `wait` on its child rather than in its own `sleep`, so no third process exists to be orphaned when the pair is reaped."
  - "The harness safety net keeps `--foreground` but gains `-k`, because a script blocked on a foreground child defers SIGTERM and the plain form bounded nothing."

patterns-established:
  - "Marker-delimited duplicated block: `# --- BEGIN run_bounded ---` / `# --- END run_bounded ---`, self-contained apart from two named host dependencies, never edited one-sidedly"
  - "Fixture self-proof: a fixture the phase's assertions depend on gets its own case asserting the property that makes it discriminating, before anything consumes it"
  - "Non-vacuous timeout assertions: assert elapsed time and process liveness, never the exit code alone, because the safety net produces the same code"

requirements-completed: []

coverage:
  - id: D1
    description: "With no timeout/gtimeout reachable on PATH, a real `gemini` shim delegation to an agy that ignores SIGTERM and has forked a SIGTERM-ignoring child returns 124 within its bound, and neither the fake nor its forked child is alive afterwards"
    requirement: R11
    verification:
      - kind: integration
        ref: "tests/run-tests.sh#RB04 no bounding binary: shim delegation returns 124 and reaps agy plus its fork"
        status: pass
    human_judgment: false
  - id: D2
    description: "The sanitized PATH resolves neither timeout nor gtimeout, yet is complete enough to run a full shim delegation end to end — proving the explicit tool list rather than assuming it"
    requirement: R11
    verification:
      - kind: integration
        ref: "tests/run-tests.sh#RB00a sanitized PATH resolves no timeout/gtimeout yet still runs a full shim delegation"
        status: pass
    human_judgment: false
  - id: D3
    description: "The forking fake agy ignores SIGTERM and its forked child outlives a direct-PID kill of the parent — the only shape that distinguishes a process-group kill from a direct-child kill"
    requirement: R11
    verification:
      - kind: integration
        ref: "tests/run-tests.sh#RB00b forking fake ignores SIGTERM and its child outlives a direct-PID kill of the parent"
        status: pass
    human_judgment: false
  - id: D4
    description: "`_rb_pgid_of` prints a bare digit string whichever reader produced it, byte-equal to `ps -o pgid= -p $$` with every non-digit removed"
    requirement: R11
    verification:
      - kind: unit
        ref: "ad-hoc driver sourcing the marked block under `set -euo pipefail`; permanent case is RB08 in plan 01-05 / RB10-RB12 in plan 01-06"
        status: pass
    human_judgment: true
    rationale: "Verified this run against an ad-hoc driver, but no committed case pins it yet — plan 01-06 owns `_rb_extract` and the helper-contract cases. Until then the property is proven, not regression-guarded."
  - id: D5
    description: "Neither the kill marker nor the self-kill-guard warning reaches the caller's captured stdout or stderr; both land on fd 9, and the child's own stdout/stderr still reach the capture files"
    requirement: R11
    verification:
      - kind: unit
        ref: "ad-hoc driver redirecting fd 9 and both capture files separately; permanent case is RB09 in plan 01-06"
        status: pass
    human_judgment: true
    rationale: "The capture files live in a mktemp WORK_DIR the shim removes on exit, so the end-to-end form needs RB09's instrumentation (plan 01-06). Verified at helper level this run; not yet regression-guarded."
  - id: D6
    description: "`run_bounded` refuses an empty, zero, or non-numeric bound and a call with no command, returning 2 and running nothing"
    requirement: R11
    verification:
      - kind: unit
        ref: "ad-hoc driver, 9 invalid shapes, non-execution observed through a sentinel; permanent case is RB11 in plan 01-06"
        status: pass
    human_judgment: true
    rationale: "Proven this run including the sentinel check, but plan 01-06 owns the committed case. Not yet regression-guarded."

duration: 4h 30m
completed: 2026-08-19
status: complete
---

# Phase 01 Plan 01: The tracer — one bounded shim delegation with no `timeout` binary Summary

**A native bash watchdog (`set -m` + `kill -- -<pgid>` with a self-group guard) now bounds the `gemini` shim's delegation when no `timeout`/`gtimeout` exists, reaping agy and everything agy forked, reporting 124, and keeping its own diagnostics on a dedicated fd 9 out of the caller's captured payload.**

## Performance

- **Duration:** ~4h 30m wall clock (long gap between Task 1 and the Task 2 checkpoint resolution; active work well under an hour)
- **Started:** 2026-08-19T03:30Z (approx.)
- **Completed:** 2026-08-19T08:00Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments

- **The phase's architecture is proven end to end on one path.** RB04 drives the real shim, on a PATH with genuinely no bounding binary, against an agy that ignores SIGTERM and has forked a SIGTERM-ignoring child. Exit 124, inside the bound, both processes gone. That is D-01, D-02, D-06 and D-14 established simultaneously rather than argued.
- **`run_bounded` exists as the primary abstraction and is ready to be copied.** The marked block is 148 lines whose only external references are `TIMEOUT_BIN`, `BASHPID` and fd 9 — verified by extracting it and scanning its uppercase references. Plan 01-03 can copy it verbatim.
- **The delegation site is a net deletion.** Eleven lines of `if [[ -n "$TIMEOUT_BIN" ]] … else …` became four, and the site no longer knows which mechanism bounds it. The `set +e` window, `EXIT_CODE` capture, redirections and `SECONDS`-derived duration are all exactly where they were.
- **The fixtures the whole phase depends on are proven, not assumed.** RB00a asserts the sanitized PATH resolves no bounding binary *and* is complete enough to run a full delegation. RB00b asserts the forking fake's child outlives a direct-PID kill of its parent — the property without which every descendant assertion in this phase would pass vacuously.
- **The suite went 89 → 92, `FAIL=0`, with no pre-existing case regressed.**

## Task Commits

Each task was committed atomically, in the worktree `/home/dd/Gemini/delegate-agy/.worktrees/agy-1.6.2` on branch `fix/agy-bridge-resilience`:

1. **Task 1: Wave 0 fixtures** — `4986fdf` (test)
2. **Task 2: Confirm the one-way door (checkpoint:decision)** — no code deliverable; the decision record is a `bd` comment on epic `delegate-agy-kk9` and on `delegate-agy-kk9.2`, per the project rule that gate verdicts live on the epic rather than in a file
3. **Task 3 (RED): RB04 observed failing against the untouched shim** — `8c54aa4` (test)
4. **Task 3 (GREEN): `run_bounded` + fd 9, delegation site rewired** — `079d787` (feat)

**Plan metadata:** committed on `master` in the main tree (SUMMARY.md, STATE.md, ROADMAP.md).

The RED commit is deliberately distinct from and prior to the GREEN one, as the plan's own acceptance criteria require. Its recorded failure:

```
rc=137 elapsed=35s parent=... parent_gone=0 child=... child_gone=0
```

The shim ran agy unbounded; the code the caller saw came from the harness safety net killing the shim at 35s, not from any bound the shim applied, and both fake processes survived. `delegate-agy-cy5` reproduced through the real script.

## Files Created/Modified

- `.worktrees/agy-1.6.2/scripts/gemini_shim.sh` — `exec 9>&2` immediately after `set -euo pipefail`; the marked `run_bounded` block (with `_rb_pgid_of`, `_rb_signal`, `RUN_BOUNDED_KILLED`, `RB_WATCHDOG_KILLED_NOTE`) between the `TIMEOUT_BIN` probe and the first call site; the delegation site rewired through it. The probe and the other three sites are untouched — plan 01-02 owns them.
- `.worktrees/agy-1.6.2/tests/run-tests.sh` — `_PUREBIN_TOOLS`, `_purebin`, `_run_sanitized`; a `cleanup` trap that reaps recorded PIDs; cases RB00a, RB00b, RB04.
- `.worktrees/agy-1.6.2/tests/fake-agy.sh` — `FAKE_AGY_FORK_HANG`, `FAKE_AGY_PID_FILE`, `FAKE_AGY_CHILD_PID_FILE`, documented in the header block in the existing format.

Nothing under the main tree's `scripts/`, `tests/`, `docs/` or `README.md` was touched.

## Decisions Made

**`unify-124` (Task 2 checkpoint, user-confirmed).** A call killed by the bash watchdog reports exit 124, identical to the coreutils path, with a stderr marker naming the fallback mechanism. `distinct-code` was rejected: it would add a sixth exit code to a contract Phase 3 freezes in the same release, and every existing 124-matching caller would stop recognising a timeout on coreutils-less hosts. Implemented by normalising the watchdog branch's status to 124 and setting `RUN_BOUNDED_KILLED` in the branch that performed the kill — never by comparing elapsed time against the bound, which would misreport an orchestrator-level cancellation landing at the bound as our own timeout.

**Two design choices made inside Claude's Discretion, both fixes over the RESEARCH prototype rather than restatements of it:**

1. **The timer subshell's stdio is detached** (`</dev/null >/dev/null 2>&1 9>&-`). Cancelling the timer kills the subshell but orphans its current `sleep`. An orphan holding the caller's stdout open blocks a caller that captured it for the rest of the bound — with the shim's 600s default, a `gemini` that returned in 5s would hang its caller for ~595s. In a script that shadows the system `gemini` for every PATH caller, that is precisely the class of failure this project's core value forbids. The prototype has this leak.
2. **The forking fake's parent blocks in `wait` on its forked child rather than in its own `sleep 300`.** Functionally identical — it outlives any bound the suite uses — but it means no third process exists. A plain `sleep` would strand a 300-second grandchild on every direct-PID kill of the parent, which is exactly what the plan forbids leaving on a developer's box.

**Known ceiling, marked in-source with a `ponytail:` comment.** On the watchdog path a child killed externally with SIGKILL is indistinguishable from the helper's own escalation, so both are relabelled 124. This is not a divergence from the coreutils path — GNU `timeout` conflates the same two cases, which is why the shim already carries a duration-based discriminator at its error branch. The plan's own truth statement fixes this design explicitly ("the watchdog path sets `RUN_BOUNDED_KILLED` authoritatively and performs no time-based inference at all"), so no marker-file mechanism was invented to separate them.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `_PUREBIN_TOOLS` needed `bash`, `readlink` and `dirname` beyond the plan's starting list**
- **Found during:** Task 1
- **Issue:** The plan's list started from `mktemp find grep sed sort tail head cat mkdir mv rm chmod cp tr cut awk date sleep ps env python3`. The shim resolves its `config/` and `config/policies/` directories through `readlink -f` plus `dirname` (`gemini_shim.sh:121`, `:247` pre-change), and the fake agy's `#!/usr/bin/env bash` shebang makes `env` search the *replacement* PATH for `bash`. Without these three, RB00a's "a plain delegation still succeeds end to end" half fails — which is the half whose entire purpose is to prove the list complete.
- **Fix:** Added the three tools, in a separately commented group naming why each is needed.
- **Files modified:** `.worktrees/agy-1.6.2/tests/run-tests.sh`
- **Verification:** RB00a green; the plan's own acceptance criterion for the completeness half is what caught it.
- **Committed in:** `4986fdf`
- **Status:** accepted by the user at the Task 2 checkpoint; no rework.

**2. [Rule 3 - Blocking] The harness safety net bounded nothing without `-k`**
- **Found during:** Task 3 (RED)
- **Issue:** The plan specifies `timeout --foreground 30` and — correctly and load-bearingly — insists `--foreground` must not be dropped, since the default mode signals the child's whole *group* and would reap the fake agy as a side effect, turning a genuinely failing descendant assertion into a vacuous pass. But `--foreground` alone sends only SIGTERM, and a script blocked on a foreground child *defers* SIGTERM until that child returns. The first RED run therefore sat for the fake's full 300 seconds (`elapsed=300s`) instead of failing fast. A broken implementation would hang the suite rather than fail it.
- **Fix:** `timeout --foreground -k 5 30`. The escalation is unavoidable and still reaches only the direct child, so the fake and its fork stay alive to be asserted on — `--foreground`'s purpose is preserved exactly.
- **Files modified:** `.worktrees/agy-1.6.2/tests/run-tests.sh`
- **Verification:** RED run then reported `rc=137 elapsed=35s parent_gone=0 child_gone=0` — a sharp, fast failure naming the real defect.
- **Committed in:** `8c54aa4` (folded into the RED commit, since it is part of making RB04 a valid failing test)

**3. [Naming, not a rule] Task 1's self-check case ids are `RB00a` / `RB00b`**
- **Found during:** Task 1
- **Issue:** The plan allocates "RB01 through RB14" and does not name the two self-check cases. RB01–RB14 are each claimed by plans 01-02 through 01-06.
- **Fix:** `RB00a` / `RB00b`, which keep the fixture self-checks legible and ahead of the numbered series without colliding.
- **Status:** accepted by the user at the Task 2 checkpoint.

---

**Total deviations:** 2 auto-fixed (both Rule 3 blocking), 1 naming choice. Both auto-fixes were caught by the plan's own acceptance criteria, and both were confirmed by the user before Task 3 proceeded.
**Impact on plan:** No scope creep. Both fixes are strictly inside the fixture surface Task 1 owns, and each removes a way a later assertion could pass vacuously or hang.

## Issues Encountered

**The `ps` padding premise could not be reproduced on this host.** The plan (and T-01-01) rest on `ps -o pgid=` right-padding its single-row output, which would make an unnormalised value fail the self-group guard *open*. On this host `ps -o pgid= -p $$` returned `3963176` with no padding at all, so the normalisation's necessity is unproven here. It is retained regardless: it is one substitution at the reader's single exit, it costs nothing, and the platform it defends is the one without procfs — macOS — which is already recorded in `01-VALIDATION.md` as manual-only. Recorded here so a later reader does not mistake it for verified-on-all-platforms.

**No job-control notices were observed**, consistent with RESEARCH's finding on this bash. The narrow suppression (group's own stderr to `/dev/null`, command's stderr explicitly restored from a transient fd 8) therefore ships as pure defence, per D-06c, and the macOS bash 3.2 check remains manual-only.

## Verification Run

- `bash /home/dd/Gemini/delegate-agy/.worktrees/agy-1.6.2/tests/run-tests.sh` → `PASS=92 FAIL=0`
- `bash -n` clean on `scripts/gemini_shim.sh`, `scripts/agy_bridge.sh`, `tests/run-tests.sh`, `tests/fake-agy.sh`
- Marked block extracts to 148 non-empty lines defining `run_bounded`, `_rb_pgid_of`, `_rb_signal`, `RUN_BOUNDED_KILLED`, `RB_WATCHDOG_KILLED_NOTE`; its only uppercase external references are `TIMEOUT_BIN` and `BASHPID`
- Delegation site: exactly one invocation, no `TIMEOUT_BIN` conditional, 11 lines → 4
- Helper-level checks all passing: digits-only PGID byte-equal to stripped `ps` output and agreeing across both readers; kill marker and guard warning on fd 9 and in neither capture file while the child's own stdout/stderr do reach them; a child exiting 42 inside the bound returning 42 with the flag clear and fd 9 empty; all 9 invalid bound shapes returning 2 with a sentinel proving nothing ran
- No fixture process survived the suite run

## Known Stubs

None. Every line added is production code or a committed assertion.

## Broken-windows note

Three of the six coverage deliverables (D4, D5, D6) are **proven but not yet regression-guarded** — they were verified this run against an ad-hoc driver, and the cases that pin them permanently (`_rb_extract` plus RB10–RB12 and RB09) are owned by plan 01-06. This is the plan's intended division of labour, not an omission, but until 01-06 lands a one-sided edit to the helper could break those properties silently. Recorded so 01-06 is not treated as optional polish.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

Ready for the rest of the phase. Specifically:

- **Plan 01-02** (remaining shim sites + the probe warning) — the block is in place and the pattern for rewiring a site is established by the delegation site. Note the two stdin sites need an explicit *positive* `kill_after`, since the helper refuses zero.
- **Plan 01-03** (verbatim copy into the bridge) — the block is self-contained apart from `TIMEOUT_BIN` and fd 9. The bridge will also need `exec 9>&2` after its own `set -euo pipefail`, and D-03's `exit 2` removal.
- **Plan 01-05** (static scan) — the delegation site is now a `run_bounded … --` argument; the other three shim sites and all three bridge sites are not yet, so the scan cannot go green until 01-02 and 01-03 land.
- **Plan 01-06** — `_run_sanitized` is the hook for the PTY variant RB06 needs; it currently has no PTY path, as planned.

**Concern to carry forward:** the external-SIGKILL-vs-own-escalation ambiguity on the watchdog path (see Decisions Made) is the seam with Phase 3's exit-code contract. Phase 3 should confirm that the shim's duration-based discriminator at its error branch still behaves as documented when the watchdog, rather than coreutils, produced the 124.

---
*Phase: 01-the-missing-timeout-decision*
*Completed: 2026-08-19*
