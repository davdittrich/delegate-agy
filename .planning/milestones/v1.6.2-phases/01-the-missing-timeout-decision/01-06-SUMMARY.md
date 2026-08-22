---
phase: 01-the-missing-timeout-decision
plan: 06
subsystem: testing
tags: [bash, process-groups, signals, pty, timeout, coreutils, tdd]

requires:
  - phase: 01-01
    provides: "_purebin / _run_sanitized sanitized-PATH fixtures, the forking SIGTERM-ignoring fake agy with its two PID files, and RB04 — the first runtime proof, on one entry point and one mechanism"
  - phase: 01-03
    provides: "the byte-identical run_bounded block in both scripts, its BEGIN/END duplication markers, and the fd-9 diagnostics descriptor"
  - phase: 01-05
    provides: "_rb_extract, the $_RB_BLOCK sourceable extraction, the warning/notice literals, and the RB01m/RB02m self-checks that set the can-this-fail precedent"
provides:
  - "A runtime proof per entry point on each mechanism: RB04/RB05 (no bounding binary) and RB13 (bounding binary present), both entry points, all held to one shared assertion contract"
  - "_rb_assert_reaped — the single bounding contract every runtime descendant case is held to, carrying D-14a's degradation as a named, reported branch"
  - "RB06a-d: the descendant guarantee without and with a controlling terminal, with both PTY-allocator flavour branches pinned on one host and the terminal actually proven"
  - "RB07: the bridge reaches its own argument handling under a coreutils-less PATH instead of exiting 2"
  - "RB09a/RB09b: no helper diagnostic reaches the caller's stdout, the JSON payload, or the bounded call's own stderr — while the marker is still proven emitted"
  - "RB10a/RB10b/RB11/RB12/RB14: the helper's boundary, adjacency, refusal and argument-boundary contracts pinned by driving it directly"
  - "A SIGHUP-immune forking fake, without which the with-terminal descendant assertion is vacuous"
affects: [phase-02, phase-03, phase-04, any future edit to the run_bounded block]

actuals:
  tokens: 10300
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "One shared assertion contract for both bounding mechanisms, parameterised by entry point and PATH, so the two arms cannot drift into two similar-looking sets of assertions"
    - "Feature-probed tool flavour with both branches pinned by a stubbed probe result, rather than uname branching or a single assumed argv form"
    - "File capture instead of command substitution wherever a surviving descendant could inherit the script's fd 9"
    - "Every deliberately-simplified case carries a stated ceiling rather than a silent gap"

key-files:
  created: []
  modified:
    - ".worktrees/agy-1.6.2/tests/run-tests.sh — cases RB05, RB06a-d, RB07, RB09a-b, RB10a-b, RB11, RB12, RB13, RB14; the _rb_assert_reaped contract; _rb_extract moved ahead of first use"
    - ".worktrees/agy-1.6.2/tests/fake-agy.sh — FAKE_AGY_FORK_HANG now ignores SIGHUP as well as SIGTERM (deviation, Rule 2)"

key-decisions:
  - "RB13 asserts 124 at the entry point and makes no claim about the mechanism's own return code, because coreutils timeout -k measurably returns 137 (its SIGKILL to its own process group reaches itself) while both entry points map it to 124"
  - "RUN_BOUNDED_KILLED is never read at the bridge's delegation site, because that call runs inside a cd subshell and a case reading it there would assert a stale value"
  - "RB05/RB13/RB06/RB10b/RB12 capture into files rather than command substitutions: each script's fd 9 is inherited by agy and its forks, so under a command substitution a failing descendant assertion blocks for the fake's full 300s instead of failing"
  - "The forking fake was made SIGHUP-immune — without it the pty session's hangup reaps the pair and the with-terminal descendant assertion passes while asserting nothing"
  - "RB12 gained a fourth, race-immune observation after it was measured passing against a helper with no kill logic at all"
  - "No new _rb_extract was written; 01-05's was moved ahead of its first use and RB21's duplicate sed deleted"

patterns-established:
  - "Contract-first assertion helpers: when two implementations claim one contract, assert them through one helper — if they needed different assertions the claimed equivalence would be a fiction"
  - "Degradation as a named branch: where a guarantee cannot hold, assert the documented weaker outcome and say so in the reported label, never a silent pass"
  - "Tautology self-checks: every case that could pass against an implementation lacking the property was mutated until it failed, and strengthened where it did not"

requirements-completed: [R11]

coverage:
  - id: D1
    description: "With no timeout/gtimeout on PATH, both entry points bound an agy that ignores SIGTERM and has forked, returning 124 and leaving neither process alive (phase criterion 2)"
    requirement: "R11"
    verification:
      - kind: integration
        ref: "tests/run-tests.sh#RB04 (shim), #RB05 (bridge)"
        status: pass
    human_judgment: false
  - id: D2
    description: "With a bounding binary present, the same holds on both entry points against the same adversarial fake (phase criterion 4, runtime half)"
    requirement: "R11"
    verification:
      - kind: integration
        ref: "tests/run-tests.sh#RB13 (bridge and shim)"
        status: pass
    human_judgment: false
  - id: D3
    description: "The descendant guarantee holds identically without and with a controlling terminal, with the allocator's argument form flavour-probed and both branches pinned, and the terminal itself proven"
    requirement: "R11"
    verification:
      - kind: integration
        ref: "tests/run-tests.sh#RB06a, #RB06b, #RB06c, #RB06d"
        status: pass
    human_judgment: false
  - id: D4
    description: "With no bounding binary the bridge reaches its own argument handling instead of exiting 2 at startup (D-03)"
    requirement: "R11"
    verification:
      - kind: integration
        ref: "tests/run-tests.sh#RB07"
        status: pass
    human_judgment: false
  - id: D5
    description: "No helper diagnostic reaches the caller's stdout, the JSON error payload (whose key set is unchanged), or the bounded call's own stderr — while the kill marker is still proven emitted on the entry point's own stderr"
    requirement: "R11"
    verification:
      - kind: integration
        ref: "tests/run-tests.sh#RB09a, #RB09b"
        status: pass
    human_judgment: false
  - id: D6
    description: "run_bounded's boundary, adjacency, refusal and argument-boundary contracts pinned by driving the extracted helper directly"
    requirement: "R11"
    verification:
      - kind: unit
        ref: "tests/run-tests.sh#RB10a, #RB10b, #RB11, #RB12, #RB14"
        status: pass
    human_judgment: false
  - id: D7
    description: "On a stock macOS with no coreutils, `gemini` on a PATH lacking timeout/gtimeout emits the warning literal and nothing resembling a shell job-control notice"
    requirement: "R11"
    verification: []
    human_judgment: true
    rationale: "No macOS host is available to this project, and the job-control notice could not be reproduced on Linux under any tested shape. The narrow suppression ships regardless; this is the one assumption the suite cannot settle."
  - id: D8
    description: "README's environment-variable section presents the shim's and the bridge's behaviour together with the reason they no longer differ (phase criterion 3), and PROJECT.md's Key Decisions table carries the always-bounded decision with the superseded row resolved (phase criterion 1)"
    verification: []
    human_judgment: true
    rationale: "Both criteria are properties of prose, not of a string match — no assertion can judge whether the reason reads as a reason."

duration: 4h 40m
completed: 2026-08-19
status: complete
---

# Phase 01 Plan 06: Runtime proof per entry point, on both mechanisms, with and without a controlling terminal — Summary

**Every bounded invocation is now proven at runtime rather than structurally: on either entry point, on either mechanism, with or without a controlling terminal, nothing outlives its bound and nothing agy forked outlives it either — and three cases were caught passing while asserting nothing before they were allowed to ship.**

## Performance

- **Duration:** ~4h 40m
- **Tasks:** 3 of 3
- **Files modified:** 2
- **Suite:** PASS=118 FAIL=0, up from a PASS=103 FAIL=0 baseline. No inherited case weakened or removed.

## Accomplishments

- **The matrix is closed.** Plan 01-01 proved one path, on one entry point, on one mechanism. There are now proofs for both entry points on both mechanisms (RB04, RB05, RB13) and in both terminal configurations (RB06b, RB06c) — fifteen new `ok` lines in total.
- **One contract, not two.** `_rb_assert_reaped` is the single set of assertions every runtime descendant case is held to, parameterised by entry point and PATH. This is the promotion of the *bounded invocation* to primary noun made observable: if the coreutils arm and the bash watchdog needed different assertions, the claimed equivalence would be a fiction, and this helper is where that would show. RB04 was refactored onto it with no behavioural change.
- **The 01-01 broken-windows exposure is closed.** fd-9 isolation (RB09a/RB09b), argument refusal (RB11) and the helper's boundary/adjacency contracts (RB10a/RB10b, RB12) are now regression-guarded, so the one-sided edit 01-01's SUMMARY warned about can no longer break them silently. PGID normalisation is guarded behaviourally — see the ceiling below.
- **Three vacuous passes found and fixed before shipping.** Every case was mutated until it failed; two failed to fail and were strengthened, and one fixture was hardened. Details under Deviations.

## Task Commits

1. **Task 1: RB05, RB07, RB13 — the bridge under both mechanisms, and a startup that no longer refuses** — `1948a4a` (test)
2. **Task 2: RB06 and RB09 — the guarantee without a terminal, the diagnostics out of the payload** — `e4d8e82` (test)
3. **Task 3: RB10, RB11, RB12, RB14 — the helper's own contract at its edges** — `bb54c6f` (test)

All three on branch `fix/agy-bridge-resilience` in the worktree. No shipped script was modified by this plan; `bash -n` clean on both.

## Files Created/Modified

- `.worktrees/agy-1.6.2/tests/run-tests.sh` — the fifteen new assertions, the `_rb_assert_reaped` contract, the PTY allocator resolution and flavour selector, and `_rb_extract` moved ahead of its first use (deleting RB21's second, unanchored copy of the same `sed`).
- `.worktrees/agy-1.6.2/tests/fake-agy.sh` — `FAKE_AGY_FORK_HANG` now ignores SIGHUP as well as SIGTERM, in the parent and in the fork.

## Decisions Made

**RB13 asserts 124 at the entry point, not at the mechanism.** Measured on this host: coreutils `timeout -k` returns **137**, not 124, against a SIGTERM-ignoring child — the SIGKILL it sends to its own process group reaches `timeout` itself. `run_bounded` flags 124 and 137 alike as its own kill, and both entry points map both to 124. The `unify-124` contract is therefore a property of what the *caller* sees, and that is where RB13 asserts it. Asserting on the mechanism's own code would have pinned an implementation detail of coreutils.

**`RUN_BOUNDED_KILLED` is never read at the bridge's delegation site.** That call runs inside `( cd "$WORK_DIR" && run_bounded ... )`, so the flag never crosses back. A case reading it there would assert a stale value and pass for the wrong reason. What crosses the subshell boundary is the exit code and the two recorded PIDs, and those are what is asserted. Noted in the case comment so a later reader does not "fix" the omission.

**File capture, not command substitution, wherever a descendant might survive.** Each script does `exec 9>&2` at the top, and fd 9 is inherited by agy and by anything agy forks. Under a command substitution that descriptor *is* the capture pipe, so a run whose descendant assertion ought to fail instead blocks for the fake's full 300s sleep. Measured: this turned a ~10s red case into a ~5-minute one and made whole-suite mutation runs impractical. RB05, RB13, RB06, RB10b and RB12 capture into files; a red run now fails in ~35s. RB04 keeps `_run_sanitized` and keeps that pre-existing cost — changing it was outside this plan's remit.

**The PTY allocator's form is probed, never assumed.** `script --version` reports `script from util-linux 2.42.2` on this host, selecting the option form `-q -c CMD /dev/null`; any other result selects the BSD operand form `-q /dev/null CMD`. Both branches are pinned here by driving the selector with a stubbed probe result, because the branch this host cannot execute is precisely the branch the portability finding is about. Verified that getting it wrong is caught: handing this util-linux host the BSD operand form ran the command **not at all** (`saw='' rc=''`), which fails RB06d and `_rb_assert_reaped` together rather than reporting the with-terminal half green.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 — Missing critical functionality] The forking fake was made SIGHUP-immune, or RB06c asserts nothing**

- **Found during:** Task 2, while demonstrating RED for RB06.
- **Issue:** Allocating a pseudo-terminal means the kernel sends SIGHUP to the session when the terminal goes away. That reaped the fake and its fork for a reason having nothing to do with the bounding mechanism. Measured against a shim mutated to kill by pid alone: the terminal-**less** half went red (`child_gone=0`) while the with-terminal half stayed **green** (`child_gone=1`). RB06c as written would have passed against a shim with no descendant kill at all — exactly the vacuous pass the plan's own prohibition forbids, and T-01-14's failure mode.
- **Fix:** `FAKE_AGY_FORK_HANG` now sets `trap '' TERM HUP` in both the parent and the fork. `trap ''` sets `SIG_IGN`, and an ignored disposition survives `exec`, so the replacement `sleep` is immune too. Under the same mutation both halves now go red together; and in the control run the with-terminal elapsed rose from 3–4s to 8s, confirming the hangup had been short-circuiting the escalation.
- **Files modified:** `.worktrees/agy-1.6.2/tests/fake-agy.sh` (outside this plan's `files_modified`).
- **Blast radius checked:** no terminal-less case sends HUP, so RB00b, RB04, RB05, RB13 and RB22 are unaffected — all verified green afterwards. The change only makes the fixture more adversarial.
- **Commit:** `e4d8e82`

**2. [Rule 1 — Bug in a new case] RB12 was a tautology as first written**

- **Found during:** Task 3 RED round M6.
- **Issue:** RB12's three at-the-bound observations (`secs=1`, `kill_after=1`, child `sleep 1; exit 55`) all landed on the self-exited side, so against a helper mutated to never set the kill flag the case stayed green. It would have passed against a helper with no kill logic at all.
- **Fix:** a fourth observation whose child ignores SIGTERM and sleeps 30s past the bound. It cannot win the race, it is held to the **same** biconditional rather than a hand-picked answer, and the batch now additionally requires at least one flag-set observation — a requirement satisfied by the child that cannot win, so it is not flaky. The same mutation now reds RB12.
- **Commit:** `bb54c6f`

**3. [Rule 3 — Reuse over addition] No new `_rb_extract` was written**

- The plan asked for an `_rb_extract` helper. Plan 01-05 already landed one for RB02, and RB21 already wrote `$_RB_BLOCK`. Rather than add a third extraction, 01-05's function was moved ahead of its first use and RB21's second, unanchored `sed` deleted — one extraction expression where there were two. Net deletion.
- **Commit:** `bb54c6f`

### Notes on scope deliberately not taken

`REQUIREMENTS.md` is outside this plan's `files_modified`, so **`delegate-agy-8k0`'s stale `Evidence:` line on R11 was left untouched** rather than half-rewritten. The full list of now-available case ids was posted to that ticket so the one-time rewrite can be done in a single edit.

## TDD Evidence — every case demonstrated RED before it was committed green

Each mutation was applied to the **real** shipped scripts and reverted immediately; nothing mutated was committed, and `git status` in the worktree was verified clean after every round.

| Mutation | Effect | Cases that went RED |
|---|---|---|
| M1b `_rb_signal` forced to its direct-pid branch | watchdog arm kills by pid only | RB04, RB05, RB06b — RB13 stayed green, correctly (mutation touches only the watchdog arm) |
| M2 bridge probe restored to the deleted startup fatal | bridge exits 2 again | RB07 |
| M3d coreutils arm given `--foreground` | no process group on the coreutils arm | RB13: `rc=124 elapsed=8s parent_gone=1` all still green with `child_gone=0`, on both entry points |
| M4 helper note moved from `>&9` to `>&2` | diagnostics onto plain stderr | RB09a, RB09b — RB21a/RB21b stayed green, so the guard warning and the kill marker are independently pinned |
| M5 kill branch widened to "any non-zero rc" | self-exited child relabelled 124 | RB10a |
| M6b `RUN_BOUNDED_KILLED=1` deleted | flag decoupled from the return | RB10b, RB12 |
| M7b bound regex `[1-9][0-9]*` relaxed to `[0-9]*` | empty and zero accepted | RB11 |
| M8 watchdog arm's `"$@"` unquoted | argv boundaries lost | RB14 (plus RB10a/RB11/RB12 as collateral) |

M3d is the one worth reading twice: it is the shape where the exit code, the elapsed time and the direct-process kill all stay green while the fork survives. That is the "passes while leaving orphans" failure the descendant assertion exists to catch, and it is why the plan forbids softening it to "the entry point returned in time".

**On permanent self-checks in the RB01m/RB02m style.** None were added, and the reason is that RB01m and RB02m guard *scans over file text*, which can silently start matching nothing. Every case here drives a real process and asserts a real outcome, so the equivalent guard is built in: RB11 ends with a valid probe expected to run (so `norun` cannot be reported by a broken sentinel), RB09a asserts the marker **was** emitted (so absence-by-silence cannot pass), RB06d asserts the terminal was actually allocated, RB12 requires at least one observed kill, and `_rb_assert_reaped` requires both PIDs non-empty. Those are the same idea, paid for inline rather than as separate cases.

## Stated Ceilings

Recorded rather than left silent, per the plan's own discipline.

- **PGID normalisation (`_rb_pgid_of`) is pinned behaviourally, not structurally.** What is asserted is the *behaviour* the normalisation exists to protect — a bare digit string reaches both the self-group comparison and the kill target, so descendants are actually reaped (RB04, RB05, RB06b/c, RB13, RB10b) and the guard fires only for a genuinely live, genuinely group-sharing child (RB21a/RB21b). The `ps -o pgid=` right-padding premise itself is **not** asserted, because it did not reproduce on this host — `ps` returned an unpadded value — and it defends a no-procfs/macOS path `01-VALIDATION.md` marks manual-only. Asserting a padding that does not occur here would have pinned a fiction.
- **The bridge's real `$STDERR_FILE` cannot be read after a run.** The bridge unlinks its work directory from an `EXIT` trap. RB09b therefore reproduces the delegation site's exact redirect shape against the extracted block and asserts the two descriptors the bridge would later interpolate are clean, rather than reading a file that no longer exists.
- **On the 124 branch the bridge does not interpolate `$STDERR_FILE` at all** — its `error` value is the fixed `Timeout after Ns`. RB09a therefore pins the payload's *key set* as well as its text, so a new key could not slip in unnoticed.
- **A red descendant assertion in RB04 still costs ~300s.** RB04 keeps `_run_sanitized`'s command substitution and therefore keeps the inherited-fd-9 hold. The new cases do not.
- **Suite runtime is 2m 25s, over the plan's "under a minute".** The inherited baseline was already 1m 23s, so the criterion was unmeetable as stated before this plan began; the fifteen new assertions add ~1 minute, essentially all of it real sleeping against 3s bounds with 5s escalations. Flagged rather than met.

## Verification

- `bash /home/dd/Gemini/delegate-agy/.worktrees/agy-1.6.2/tests/run-tests.sh` → **`PASS=118 FAIL=0`**.
- Cases RB05, RB06a–d, RB07, RB09a–b, RB10a–b, RB11, RB12, RB13 (×2), RB14 all report `ok`.
- Cases RB00a/b, RB01, RB01m, RB02, RB02m, RB03, RB04, RB08, RB20a/b, RB21a/b, RB22 from earlier plans all still report `ok`.
- `bash -n` clean on `scripts/agy_bridge.sh`, `scripts/gemini_shim.sh`, `tests/run-tests.sh`, `tests/fake-agy.sh`.
- No shipped script modified: `git diff 3fdf663..HEAD --stat` touches `tests/` only.
- No residual fixture process survives the suite run (`ps` for `fake-agy`, `sleep 300`, `sleep 424*`, both entry points → none).
- No file under the main tree's `scripts/`, `tests/`, `docs/` or `README.md` was modified.

## Open — for the phase close, not this plan

- `delegate-agy-cy5` — left open by design; the runtime evidence was commented on it.
- `delegate-agy-8k0` — R11's `Evidence:` line; case ids posted, rewrite deferred to one edit.
- The three `<human-check>` items in the plan's task 3: the macOS job-control notice (D7), README's environment-variable prose (criterion 3) and PROJECT.md's Key Decisions row (criterion 1). All three are carried in `coverage` as `human_judgment: true` and none can be settled by this suite.

## Self-Check: PASSED

- `.planning/phases/01-the-missing-timeout-decision/01-06-SUMMARY.md` — FOUND
- `.worktrees/agy-1.6.2/tests/run-tests.sh` — FOUND
- `.worktrees/agy-1.6.2/tests/fake-agy.sh` — FOUND
- Commit `1948a4a` — FOUND
- Commit `e4d8e82` — FOUND
- Commit `bb54c6f` — FOUND
