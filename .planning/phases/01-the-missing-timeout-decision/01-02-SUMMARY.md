---
phase: 01-the-missing-timeout-decision
plan: 02
subsystem: infra
tags: [bash, process-groups, timeout, coreutils, signals, file-descriptors, diagnostics]

# Dependency graph
requires:
  - "01-01: the `run_bounded` block between `# --- BEGIN run_bounded ---` / `# --- END run_bounded ---`, plus `exec 9>&2`, in `scripts/gemini_shim.sh`"
provides:
  - "All four `scripts/gemini_shim.sh` bounded sites routed through `run_bounded`: the `agy models` fetch, `--version`, the stdin read, and the delegation 01-01 already converted"
  - "`RB_NO_TIMEOUT_WARN` in `scripts/gemini_shim.sh`, defined once at the `TIMEOUT_BIN` probe and emitted to plain stderr there"
  - "The literal `WARNING: timeout/gtimeout not found -- bounding agy with the bash watchdog fallback; install coreutils for process-group kill`, ready for plan 01-04 to quote verbatim in README and plan 01-05 to pin with case RB03"
  - "A shim in which no `if [[ -n \"$TIMEOUT_BIN\" ]] … else …` pair survives outside the marked block"
affects: [01-03 verbatim copy into the bridge, 01-04 README literals, 01-05 static scan RB01 and warning case RB03, 01-06 helper-contract cases, phase-03 exit-code contract]

actuals:
  tokens: 41000
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Mechanism announcement at the probe, not in the helper: the one site that runs once per invocation owns the message, so the helper stays hermetic and cannot repeat it per call"
    - "A single bound-validation rule for every site, bought by giving even a site that can never need escalation an explicit positive `kill_after`"

key-files:
  created: []
  modified:
    - .worktrees/agy-1.6.2/scripts/gemini_shim.sh

key-decisions:
  - "The stdin read gets an explicit positive `kill_after` of 5 rather than a zero mirroring the bare `timeout <secs> cat` it replaces. `cat` can never need the escalation, so the value is unobservable -- but admitting zero anywhere would mean `run_bounded` could not validate its bounds with one rule, and coreutils reads a zero duration as *no timeout*, so the exact hazard case SH13 guards against would reappear at a different site."
  - "The model-fetch rationale comment was corrected from `-k` to 'the second bound', since the site no longer names a binary or its flags. The comment was kept rather than moved into the helper, per the plan's instruction not to restate site rationale inside the block."
  - "Task 2's rationale comment was trimmed from 13 lines to 6 after measuring its cost against the plan's own 'the file is shorter' criterion. The three facts kept are the ones a future reader would otherwise get wrong: why the probe and not the helper, why plain stderr and not fd 9, and why a variable."
  - "Neither of the two defects found inside the marker block was fixed here. The plan's prohibition is explicit and plan 01-03 copies the block byte-for-byte in this same wave, so a one-sided edit would diverge the two copies and fail case RB02. Both are filed as blockers instead."

patterns-established:
  - "Elapsed time, never the exit code, as the discriminator for 'was this bounded': the harness safety net returns 124 too, so a site that bounds nothing still looks like a timeout -- just late"
  - "Measure the shim, not the fixture: a `writer | shim` pipeline makes the shell wait for the writer, reporting the writer's lifetime for a shim that returned at its bound"

requirements-completed: [R11]

coverage:
  - id: D1
    description: "With no timeout/gtimeout reachable on PATH, the `agy models` fetch is abandoned at its own bound and the shim degrades to pass-through rather than hanging"
    requirement: R11
    verification:
      - kind: integration
        ref: "ad-hoc driver, sanitized PATH, FAKE_AGY_MODELS_HANG=1 AGY_MODELS_TIMEOUT=2: rc=0 at 5s (2+3) with the delegation's output intact; previously 12s, bounded only by the harness net"
        status: pass
    human_judgment: false
  - id: D2
    description: "With no timeout/gtimeout reachable on PATH, a hung `--version` exits 124 after its 10-second bound with the existing message"
    requirement: R11
    verification:
      - kind: integration
        ref: "ad-hoc driver, sanitized PATH, FAKE_AGY_VERSION_HANG=1: rc=124 at 15s (10+5) with `ERROR: agy --version timeout after 10s`; previously 22s, bounded only by the harness net"
        status: pass
    human_judgment: false
  - id: D3
    description: "With no timeout/gtimeout reachable on PATH, a stdin read that never sees EOF exits 2 at its bound with the existing message"
    requirement: R11
    verification:
      - kind: integration
        ref: "ad-hoc driver, sanitized PATH, FIFO held open by a non-writing writer, GEMINI_SHIM_STDIN_TIMEOUT=2: rc=2 at 2s with `ERROR: stdin read timed out after 2s`; previously not bounded at all -- the read outlived the harness net and returned only when the writer finished"
        status: pass
    human_judgment: false
  - id: D4
    description: "AGY_MODELS_TIMEOUT=0 is corrected rather than rejected AND the fetch stays bounded on the watchdog path"
    requirement: R11
    verification:
      - kind: integration
        ref: "tests/run-tests.sh#SH13 (coreutils path, pre-existing, still green) plus an ad-hoc sanitized-PATH run: rc=0 at 23s (corrected to 20, +3) with output intact; previously 12s, bounded only by the harness net"
        status: pass
    human_judgment: false
  - id: D5
    description: "On a host resolving neither binary, the warning appears on stderr exactly once per run however many bounded calls that run makes, and is the first line on stderr"
    requirement: R11
    verification:
      - kind: integration
        ref: "ad-hoc driver, sanitized PATH, one run making THREE bounded calls (fresh-HOME model fetch + piped stdin read + delegation): warn_count=1, and `head -1` of stderr is the warning -- ahead of run_bounded's own fd-9 diagnostics, which are in the same stream. Permanent case is RB03 in plan 01-05."
        status: pass
    human_judgment: true
    rationale: "Verified this run; the committed case that pins it (RB03) is plan 01-05's, so the property is proven but not yet regression-guarded."
  - id: D6
    description: "On a host where a bounding binary resolves, nothing new reaches stderr on any path"
    requirement: R11
    verification:
      - kind: integration
        ref: "ad-hoc driver, ordinary PATH, delegating and --version paths: warn_count=0 and combined stderr entirely EMPTY. Also covered indirectly by the pre-existing SH12, which asserts empty stderr on HOME-unset runs and stays green."
        status: pass
    human_judgment: false
  - id: D7
    description: "The JSON envelope is byte-for-byte what it was, warning or no warning"
    requirement: R11
    verification:
      - kind: integration
        ref: "ad-hoc driver, `-o json` on both a sanitized and an ordinary PATH: identical payloads, `{\"response\": \"ok\", \"usageMetadata\": {…}, \"model\": \"agy\", \"duration_seconds\": 0}`, no added key"
        status: pass
    human_judgment: false
  - id: D8
    description: "No mechanism-aware branch remains outside the marked block, and the marked block is untouched"
    requirement: R11
    verification:
      - kind: static
        ref: "`grep -c 'if [[ -n \"$TIMEOUT_BIN\" ]]'` = 1, at line 134 inside the markers; every `\"$AGY_BIN\"` occurrence follows `run_bounded … --`; the marker block's sha256 is 9496f21c…, identical to commit 079d787. Permanent case is RB01/RB02 in plan 01-05."
        status: pass
    human_judgment: false

duration: 1h 10m
completed: 2026-08-19
status: complete
---

# Phase 01 Plan 02: Expand the bounded slice across the rest of the shim Summary

**All four of `gemini_shim.sh`'s agy-touching call sites now go through one helper, so none of them can run unbounded on a host with no `timeout`/`gtimeout` — and such a host is told once per run, in one line, which mechanism is bounding it and how to get the better one.**

## Performance

- **Duration:** ~1h 10m
- **Tasks:** 2
- **Files modified:** 1
- **Net diff vs plan 01-01's commit:** 25 insertions, 22 deletions

## Accomplishments

- **The shim can no longer call agy unbounded, anywhere.** Before this plan three of its four sites fell back to a bare invocation when no bounding binary resolved — and one of them, the model fetch, is on the path every `gemini` invocation with `-m` takes. Measured on a PATH resolving neither binary, all three were bounded only by the test harness's own safety net, and the stdin read was not bounded even by that: it outlived the net and returned only when its writer finished.
- **Each conversion is a net deletion.** 22 lines out, 17 in for Task 1; the file went 542 → 537. Not one call site now knows which mechanism bounds it.
- **The one-per-run warning works on the run that would break a per-call implementation.** A shim invocation with a cold cache and piped stdin makes three bounded calls. The warning appears once, and as the *first* line on stderr — ahead of `run_bounded`'s own fd-9 diagnostics, which share that stream, so the ordering assertion is a real discriminator rather than a vacuous one.
- **The JSON envelope is untouched**, byte-for-byte identical between a sanitized and an ordinary PATH (D-11).
- **Two real defects were found inside the `run_bounded` block and filed rather than papered over**, one of them a P0 process leak. Both were invisible to the suite, which is green in every configuration.
- **Suite: `PASS=92 FAIL=0`**, unchanged from the 01-01 baseline, re-run after each of the three site conversions so any regression would have been attributable.

## Task Commits

Both committed in the worktree `/home/dd/Gemini/delegate-agy/.worktrees/agy-1.6.2` on branch `fix/agy-bridge-resilience`:

1. **Task 1: the three remaining sites** — `9924393` (feat)
2. **Task 2: the probe warning** — `68619f6` (feat)

**Plan metadata:** committed on `master` in the main tree (SUMMARY.md, STATE.md, ROADMAP.md).

### On red-before-green

This plan allocates **no new committed test case to itself**. `RB01` (the static scan) and `RB03` (the warning) are both owned by plan 01-05, `RB02` by 01-05, and `RB09`–`RB12` by 01-06; Task 2's own acceptance criteria require that `git diff` show *no change to any file other than `scripts/gemini_shim.sh`*, and Task 1's `<files>` names only that file. There is therefore no test-file diff that could constitute a RED commit, and creating one would violate the plan's explicit criterion.

RED was instead **observed and recorded before any implementation**, against the untouched shim, using the same ad-hoc-driver pattern plan 01-01 used for its D4/D5/D6 deliverables. The recorded failing run:

```
MODELS   rc=124  elapsed= 12s  UNBOUNDED (bound was 2s -- the harness net fired, not the shim)
VERSION  rc=124  elapsed= 22s  UNBOUNDED (bound was 10s -- likewise)
STDIN    rc=137  elapsed= 60s  UNBOUNDED (bound was 2s -- outlived the net entirely)
SH13PURE rc=124  elapsed= 12s  UNBOUNDED (zero bound corrected to 20, but the fetch was unbounded anyway)
WARN no-binary  count=0   (want exactly 1)
```

An earlier RED attempt is worth recording because of what it exposed: capturing the shim's output through `$(…)` made the *first* probe report `elapsed=300s`. The unbounded fetch orphaned a fake agy that had inherited fd 9 — the shim's own stderr, which was the capture pipe — so the orphan held the reader open for its full sleep. That is a second, independent symptom of the same unbounded call, and it is why every probe here writes to files instead.

The properties are proven, not regression-guarded, until 01-05 and 01-06 land their cases. See **Broken-windows note**.

## Files Created/Modified

- `.worktrees/agy-1.6.2/scripts/gemini_shim.sh`
  - **model fetch** (`load_models`): the `if/else` pair became `raw=$(run_bounded "$AGY_MODELS_TIMEOUT" 3 -- "$AGY_BIN" models </dev/null 2>/dev/null) || raw=""`. Redirections, the `|| raw=""` guard and the rationale comment above it all stay; the comment's reference to `-k` became "the second bound", since the site no longer names a binary or its flags.
  - **`--version`**: became `run_bounded 10 5 -- "$AGY_BIN" --version || _V_RC=$?`. The 10-second bound stays non-configurable and the 124/137 mapping is untouched.
  - **stdin read**: became `run_bounded "$STDIN_TIMEOUT" 5 -- cat > "$PROMPT_FILE" || { … exit 2; }`, with a comment recording why the `kill_after` is positive and why D-06d means backgrounding `cat` cannot stop on SIGTTIN.
  - **`TIMEOUT_BIN` probe**: the empty-string branch gained `RB_NO_TIMEOUT_WARN` and one `echo … >&2`.
  - **Nothing between the markers changed** — sha256 `9496f21c…`, identical to `079d787`, verified before each commit.

Nothing under the main tree's `scripts/`, `tests/`, `docs/` or `README.md` was touched.

## Deviations from Plan

### 1. [Documented, not auto-fixed] The file is 545 lines, not fewer than the 542 it started at

- **Criterion:** the plan's `<success_criteria>` says "Six lines of mechanism-aware branching are gone and the file is shorter."
- **What happened:** Task 1's own criterion — "fewer lines than it did before this task" — was met: 542 → 537. Task 2 then added the warning, which the plan itself mandates, taking the file to 552 with a 13-line rationale comment.
- **Action:** the comment was trimmed to 6 lines, landing at 545. Getting under 542 would have meant a comment of at most 4 lines, too tight to hold the three facts a future reader would otherwise get wrong — above all *why the warning lives at the probe and not in the helper*, which is the exact wrong move D-09 exists to prevent.
- **Assessment:** the criterion's intent (this plan is net deletion of branching, not net addition of complexity) holds — the branching is gone and Task 1 alone shortened the file. The plan-level phrasing did not account for its own Task 2. Recorded rather than gamed; 3 net lines for a required deliverable is the honest number.

### 2. [Correction, not a rule] The model-fetch comment's `-k` reference

The kept rationale comment said "so `-k` escalates to SIGKILL; a plain `timeout` would hand the shim the very hang this release exists to fix." After the conversion the site names neither a flag nor a binary. Reworded to "the second bound escalates to SIGKILL; a bound without that escalation would…", and "bounded like the other two" → "the other three". Leaving it would have left the file pointing at a mechanism its own code no longer mentions.

### No auto-fixes were applied

Rules 1–3 were not invoked. Both defects found are inside the marker block this plan is forbidden to edit, so they are filed rather than fixed — see below.

## Blockers Filed

Both live **inside the `run_bounded` marker block**, so plan 01-02 could not touch them: the prohibition is explicit, and plan 01-03 copies that block byte-for-byte into the bridge in this same wave, so a one-sided edit would diverge the two copies and fail case RB02. **Whoever fixes either must fix both copies in one commit.** Neither is visible to the suite, which is green in every configuration.

### `delegate-agy-vtx` (P0) — the watchdog timer leaks one `sleep <bound>` per bounded call

Every **successful** bounded call on the watchdog path leaks a `sleep <secs>`, reparented to init, alive for the full bound. `kill "$timer"` kills the timer *subshell*; its in-flight `sleep` is a separate child, orphaned rather than killed, and the subshell is not a process-group leader (the enclosing `set -m` window has already closed), so there is no group to signal instead.

Measured through the real shim on a sanitized PATH with `GEMINI_SHIM_TIMEOUT=4242`:

```
before:            0
shim rc=0  stdout=ok
after 1 call:      1        4119988 sleep 4242
after 6 calls:     6        <- one per call
coreutils control: 6        <- six MORE calls with coreutils on PATH added none
leaked pid 4119988 ppid=1 etime=00:01   still alive after 3s: YES
```

With the shim's real defaults that is up to three leaks per `gemini` invocation — `sleep 600` + `sleep 20` + `sleep 30` — from the script that shadows `gemini` box-wide. An Octopus/Metaswarm loop at one call per second reaches a steady state in the low thousands of resident processes. That is a denial of service on stock macOS, precisely the platform the watchdog exists to serve and the only one where it is the sole mechanism.

**01-01 saw this orphan and fixed only its stdio consequence** (detaching the timer's stdio so it cannot hold a capturing caller's stdout), recording its continued existence as harmless. It is not. **This plan raised the rate**, from one leak per run to up to three, by converting the other three sites — which is why it is filed at P0 rather than carried as a note.

### `delegate-agy-84e` (P1) — the self-kill guard warns on every fast successful call

A bounded child that exits *before* `run_bounded` reads its PGID makes `_rb_pgid_of` return empty from both readers, so the D-06a guard takes its degraded branch and prints, on fd 9:

```
WARNING: run_bounded: child <pid> has no process group of its own; bounding it by pid only, descendants may survive
```

The claim is false — the child had its own group, it just finished first — and bounding is unaffected (exit code and `RUN_BOUNDED_KILLED` are both correct). Deterministic, not a race:

```
instant exit 0             rc=0   killed=0   guard_fired=1
instant exit 42            rc=42  killed=0   guard_fired=1
instant cat </dev/null     rc=0   killed=0   guard_fired=1
sleep 1 then exit 0        rc=0   killed=0   guard_fired=0
sleep 2 then exit 0        rc=0   killed=0   guard_fired=0
hangs, must be killed      rc=124 killed=1   guard_fired=0
guard fired in 10 / 10 instant-exit runs
```

Beyond the noise — on a coreutils-less host, on top of the one line this plan adds deliberately — it **weakens the real signal**: an operator seeing the warning when descendants genuinely may survive cannot tell it from the benign case. Suggested gate: only warn when `kill -0 "$child"` still succeeds.

Both are recorded as `bd comment`s on epic `delegate-agy-kk9`, per the project rule that gate verdicts and findings live on the epic rather than in a file.

## Issues Encountered

**A reaper that killed its own shell.** `pkill -9 -f 'sleep 4242'`, run to clean up the leaked processes, matched the command line of the shell *running the pkill* — `-f` matches the full command line, and that command line contains the pattern text. Three consecutive invocations died silently with exit 1 and no output before the cause was clear. `pkill -x -f` (whole command line must *equal* the pattern) is the correct form. Recorded in `delegate-agy-vtx` for whoever writes the permanent leak case, since that case has to reap what it counts.

**Two probe artifacts that would have read as product defects**, both fixed in the driver rather than the shim:
- A `writer | shim` pipeline makes the shell wait for the *writer*, so a stdin read bounded correctly at 2s reported `elapsed=60s`. Replaced with a FIFO held open by a non-writing writer that is reaped as soon as the shim returns.
- The `AGY_MODELS_TIMEOUT=0` probe sat under a 12-second safety net while the corrected bound is 20+3, so the net always fired first and the site read as unbounded. The net had to be raised above the bound it was meant to backstop.

Both are the same error in two forms: a safety net or fixture that is not comfortably outside the bound under test measures itself.

## Verification Run

- `bash /home/dd/Gemini/delegate-agy/.worktrees/agy-1.6.2/tests/run-tests.sh` → `PASS=92 FAIL=0`, run after each of the three site conversions and again after Task 2 and after the comment trim
- `bash -n scripts/gemini_shim.sh` clean at every step
- `grep -n '"$AGY_BIN"'` → 3 occurrences, all following `run_bounded … --` (the fourth site is `cat`)
- `grep -c 'if [[ -n "$TIMEOUT_BIN" ]]'` → 1, at line 134, inside the markers
- `grep -c 'RB_NO_TIMEOUT_WARN='` → 1
- Marker block sha256 `9496f21c0d1a8d8938e31623be7003e3b89ab35732784fb1ee90a888b2b075f5`, identical to `079d787`; all three diff hunks fall outside lines 56–203
- `git diff 079d787..HEAD` touches `scripts/gemini_shim.sh` only, 25 insertions / 22 deletions
- Main tree `scripts/`, `tests/`, `docs/`, `README.md`: unmodified (`git status --short` on those paths is empty)
- Every fixture and leaked timer process from the probe runs reaped; `sleep 4242`, `sleep 600`, `sleep 300`, `sleep 60` all at 0 afterwards

## Known Stubs

None. Every line added is production code.

## Broken-windows note

Six of this plan's eight coverage deliverables are pinned only by ad-hoc runs recorded above, because **this plan owns no committed test case** — `RB01`/`RB02`/`RB03` belong to plan 01-05 and `RB09`–`RB12` to plan 01-06, and Task 2's acceptance criteria forbid touching any file but the shim. That division is the plan's intent, not an omission, but until those cases land:

- a future site could reintroduce a direct `"$AGY_BIN"` call and nothing would go red (01-05, RB01);
- the two shim/bridge copies of the block could diverge silently (01-05, RB02);
- the warning could be moved into the helper, or dropped, or reworded away from the README's verbatim quote, and the suite would stay green (01-05, RB03).

`.planning/WINDOWS.md` does not exist in this project, so these are recorded here and on the epic instead.

## User Setup Required

None.

## Next Phase Readiness

- **Plan 01-03** (verbatim copy into the bridge) — unblocked and unaffected: the marker block is byte-identical to what 01-01 left, verified by sha256 before each commit here. The bridge still needs `exec 9>&2` after its own `set -euo pipefail`, D-03's `exit 2` removal, and its own copy of the probe warning. **Read `delegate-agy-vtx` and `delegate-agy-84e` first** — copying the block verbatim also copies both defects into the bridge, doubling the leak's blast radius.
- **Plan 01-04** (README) — both literals now exist in the shipped script and can be quoted verbatim: `RB_NO_TIMEOUT_WARN` and `RB_WATCHDOG_KILLED_NOTE`.
- **Plan 01-05** (static scan) — all four shim sites are now `run_bounded … --` arguments. The scan still cannot go green until 01-03 converts the three bridge sites.
- **Plan 01-06** (helper contract) — its remit should grow by two cases, one per blocker: a successful watchdog-path call leaves no `sleep <bound>` behind, and writes nothing to fd 9. Both are the kind of assertion that passes vacuously if it only inspects the bounded child.

**Concern to carry forward:** the suite was green throughout, in every configuration, while both filed defects were present — a P0 process leak among them. Every assertion in the phase so far observes the bounded child's fate; none observes what the *helper* leaves behind. That blind spot, not either individual bug, is the thing 01-06 should close.

## Self-Check: PASSED

- File claimed modified: `.worktrees/agy-1.6.2/scripts/gemini_shim.sh` FOUND on disk
- Commits claimed: `9924393`, `68619f6` FOUND on `fix/agy-bridge-resilience`
- `bash tests/run-tests.sh` → `PASS=92 FAIL=0`
- Marker block sha256 matches `079d787`
- Main tree `scripts/`, `tests/`, `docs/`, `README.md`: unmodified
- Beads: `delegate-agy-kk9.4` and `delegate-agy-kk9.5` closed with evidence comments; `delegate-agy-vtx` (P0) and `delegate-agy-84e` (P1) open, both commented onto epic `delegate-agy-kk9`

---
*Phase: 01-the-missing-timeout-decision*
*Completed: 2026-08-19*
