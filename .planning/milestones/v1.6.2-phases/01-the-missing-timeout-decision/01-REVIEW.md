---
phase: 01-the-missing-timeout-decision
reviewed: 2026-08-19T15:01:06Z
depth: deep
diff_range: 56be103..bb54c6f (fix/agy-bridge-resilience, worktree .worktrees/agy-1.6.2)
files_reviewed: 4
files_reviewed_list:
  - scripts/gemini_shim.sh
  - scripts/agy_bridge.sh
  - tests/run-tests.sh
  - tests/fake-agy.sh
findings:
  critical: 2
  high: 2
  medium: 5
  low: 3
  total: 12
status: issues_found
---

# Phase 01: Code Review Report

**Reviewed:** 2026-08-19T15:01:06Z
**Depth:** deep (cross-file, plus runtime reproduction of every Critical/High finding)
**Files Reviewed:** 4
**Status:** issues_found

## Summary

The convergence itself holds. Byte-identity of the two `run_bounded` copies is real
(`diff` of the two marker ranges is empty, 232 lines each), the coreutils and watchdog
arms both bound, the three phase-internal defects (`-vtx`, `-84e`, `-kk9.18`) do not
recur — I probed the `-84e` guard 20x per shape across four child shapes and got 0/80
false warnings, and the `-vtx` sleep leak is gone. No test-only switch, env var or flag
exists in either shipped script; `TIMEOUT_BIN` is set by the probe and the tests reach
the branches by sourcing the block and overriding in the driver, which is the correct
shape.

What does not hold is the block's own claim about its boundary. The docblock says it
"depends on exactly two things from its host script: `$TIMEOUT_BIN` and file descriptor
9. Add no third dependency." There are three undeclared ones, and two of them are the
findings below: it hands fd 9 to the bounded child instead of keeping it (C1), and it
takes ownership of the host's `TERM`/`INT` traps and then discards them (H1). A fourth,
external `awk`/`ps`, silently disables descendant reaping where it is absent (H2). And
the parity claim the whole phase rests on — "the coreutils mechanism and the bash
watchdog owe the caller the SAME contract" — breaks on SIGHUP: coreutils reaps, the
watchdog abandons the child permanently (C2).

Both Criticals are in failure class #1/#2 and both are reproduced end to end below, not
inferred. C1 in particular hangs a real caller forever on a *successful, fast* run, and
it is phase-introduced: `exec 9>&2` first appears in `079d787`.

The suite is strong — genuinely adversarial, mutation-checked in five places (RB01m,
RB02m, RB12's fourth observation, RB11's control probe, RB06d's tty assertion). Its gaps
are not tautologies; they are systematic blind spots that happen to be exactly the shape
of C1, H1 and H2, which is why the phase shipped with them.

---

## Critical

### CR-01: `exec 9>&2` is inherited by agy and every descendant — `out=$(gemini … 2>&1)` never returns

**File:** `scripts/gemini_shim.sh:27`, `:222`, `:243` — and identically `scripts/agy_bridge.sh:17`, `:205`, `:226`
**Introduced by:** `079d787` (shim), `487177e` (bridge). No pre-phase equivalent — fd 9 did not exist before this phase.

**Mechanism.** Line 27 dups the shim's *original* stderr onto fd 9. Nothing ever closes it
for the bounded command:

```bash
# watchdog arm, gemini_shim.sh:243
"$@" 2>&8 8>&- &          # fd 8 closed for the child, fd 9 left OPEN
# coreutils arm, gemini_shim.sh:222
"$TIMEOUT_BIN" -k "$kill_after" "$secs" "$@" || rc=$?   # fd 9 left OPEN
```

The timer subshell at `:170` closes it (`9>&-`); the long-lived, fork-happy child does
not. That asymmetry is the bug: whatever agy leaves behind — an MCP server, a language
server, any detached helper — inherits a write handle on the *caller's* stderr.

**Failure scenario.** Caller does `out=$(gemini -m X "prompt" 2>&1)`, which is the
single most common capture shape for a CLI that shadows `gemini` box-wide. `2>&1` makes
the shim's stderr the command-substitution pipe, so fd 9 *is* the pipe. agy runs, exits
0, the shim prints its answer and exits 0. The surviving descendant still holds fd 9, so
the pipe never reaches EOF and `$(…)` blocks forever. Nothing timed out — the run
*succeeded*.

**Reproduced** (fake agy that exits 0 after spawning one detached helper, i.e. exactly
what a real agy does; the 25s figure is my own outer net, not a natural end):

```
--- watchdog arm (no timeout/gtimeout on the shim's PATH) ---
out=$(gemini ...)      stdout only    rc=0    elapsed= 0s  out=AGY-REPLY
out=$(gemini ... 2>&1) merged         rc=124  elapsed=25s  out=''
--- coreutils arm (timeout on the shim's PATH) ---
out=$(gemini ... 2>&1) merged         rc=124  elapsed=25s  out=''
```

Both arms. The bound is irrelevant — the bound already fired and cleaned up; it is fd 9
that survives.

**The team already met this and treated it in the wrong place.** `tests/run-tests.sh:1774`
says it outright: *"Each entry point opens fd 9 on its own original stderr, and every
child inherits it — including the fake and the fake's fork. Under a command substitution
that descriptor IS the capture pipe … a mutated shim turned a ~10s red case into a ~5min
one."* The response was to move the *test harness* to file capture (RB05, RB09, RB10–RB14)
and to redirect the *fake's* child stdio to `/dev/null` (`tests/fake-agy.sh:151`). Real
callers got neither.

**Fix** (two tokens, no design change; fd 9 is for the *helper's* diagnostics, never for
the child):

```bash
# gemini_shim.sh:222 / agy_bridge.sh:205
"$TIMEOUT_BIN" -k "$kill_after" "$secs" "$@" 9>&- || rc=$?
# gemini_shim.sh:243 / agy_bridge.sh:226
"$@" 2>&8 8>&- 9>&- &
```

Redirections on a simple command are command-local, so run_bounded keeps fd 9 for its own
`>&9` writes at `:216`, `:262`, `:291`. Regression guard: assert `! -e /proc/self/fd/9`
inside a bounded child on both arms — a two-line unit case in the RB10–RB14 family.

---

### CR-02: SIGHUP during a watchdog-bounded call abandons the child permanently

**File:** `scripts/gemini_shim.sh:273-279` (traps + `wait`), identically `scripts/agy_bridge.sh:256-262`
**Interaction with:** `scripts/gemini_shim.sh:483` / `scripts/agy_bridge.sh:461` — `trap 'rm -rf "$WORK_DIR"' EXIT HUP INT QUIT TERM`

**Mechanism.** `run_bounded` relays exactly two signals:

```bash
trap '_rb_relay TERM 143' TERM
trap '_rb_relay INT  130' INT
_rb_start_timer "$secs" TERM
wait "$child" 2>/dev/null || rc=$?
_rb_cancel_timer "$timer" "$timer_pgid"
```

The host has *also* trapped `HUP`, with a handler that cleans up and **does not exit**.
Bash returns from `wait` with 128+signum as soon as any trapped signal arrives. So a
SIGHUP: `wait` returns 129, `_rb_cancel_timer` tears down the one mechanism that would
have killed the child, `rc=129` is neither 143 nor 137 so no escalation, and
`run_bounded` returns. The child — a SIGTERM-ignoring agy — is never signalled again by
anyone.

**Failure scenario.** User closes the terminal, an ssh session drops, or a systemd unit
stops, while `gemini` is mid-delegation on a coreutils-less host. The shim exits; agy and
everything it forked run to completion or forever. On the shim's real defaults this is a
full Antigravity CLI process leaked per HUP'd invocation, with no bound left on it at all.

**Reproduced** (bound 3s, kill_after 2s, TERM/HUP-ignoring child that forks; signal sent
while the call is in flight; liveness checked 8s later, well past 3+2):

```
term-watchdog (SIGTERM, TB='')     child_still_alive_after_8s=no    run_bounded returned 124/relay
hup-watchdog  (SIGHUP,  TB='')     child_still_alive_after_8s=YES   run_bounded returned 129
quit-watchdog (SIGQUIT, TB='')     child_still_alive_after_8s=no    run_bounded returned 124   (5/5 reps)
hup-coreutils (SIGHUP,  TB=timeout) child_still_alive_after_8s=no   run_bounded returned 137
```

SIGQUIT was tested 5x and does **not** reproduce — scoping this to HUP honestly. The last
row is the important one: the coreutils arm reaps on HUP, the watchdog arm does not. This
is a direct break of the parity claim in the block's own comment ("this path claims parity
with it") and of the shared-contract premise `_rb_assert_reaped` is built on. RB13/RB05
never send HUP, so the suite cannot see it.

**Fix.** Relay HUP the same way, which is also what coreutils `timeout` does (it forwards
the signal it received):

```bash
trap '_rb_relay TERM 143' TERM
trap '_rb_relay INT  130' INT
trap '_rb_relay HUP  129' HUP
```

`_rb_relay` exits, so the host's `EXIT` trap still performs the `rm -rf "$WORK_DIR"` the
host's own HUP handler was there for — no cleanup is lost. A more defensive variant, if
future host traps are a concern, is to re-enter `wait` while `kill -0 "$child"` still
succeeds instead of falling through on any `rc > 128` with no relay; that closes the class
rather than the instance. Regression guard: RB22 parameterised over `TERM` and `HUP`, both
required to leave nothing alive.

---

## High

### HI-01: `run_bounded` destroys the host's TERM/INT traps instead of restoring them

**File:** `scripts/gemini_shim.sh:279` (`trap - TERM INT`), identically `scripts/agy_bridge.sh:262`

**Mechanism.** `trap -` resets to *default disposition*; it does not restore whatever the
host had. Both hosts install their cleanup trap **before** the first bounded call
(shim: `:483` trap, `:511` first `run_bounded`; bridge: `:461` trap, `:486` first
`run_bounded`). On the watchdog arm the first bounded call therefore permanently deletes
the host's `TERM` and `INT` cleanup handlers.

**Reproduced** (watchdog arm vs coreutils arm as the control):

```
watchdog arm:
  before TERM: [trap -- 'echo HOST_CLEANUP_RAN' SIGTERM]
  before INT : [trap -- 'echo HOST_CLEANUP_RAN' SIGINT]
  after  TERM: []
  after  INT : []
coreutils arm (control):
  after  TERM: [trap -- 'echo HOST_CLEANUP_RAN' SIGTERM]
```

**Failure scenario.** Coreutils-less host, prompt arrives on stdin, so `run_bounded` at
`gemini_shim.sh:511` runs and clears the traps. From `:514` onward — the empty-prompt
`grep`, the GEMINI.md embed, arg assembly — and again from `:566` to the end (the
`python3` JSON emission), a Ctrl-C or SIGTERM now kills the shim with default disposition.
Bash does **not** run an `EXIT` trap for a process killed by an uncaught signal, so
`/tmp/gemini-shim.XXXXXX/` survives with `GEMINI.md` containing the full user prompt. The
bridge has the same window, and its is wider — the MCP autodetect `python3` subprocess at
`agy_bridge.sh:540-566` sits inside it. Repeated Ctrl-C'd runs accumulate prompt-bearing
temp dirs indefinitely.

Secondary, and the reason this is High rather than Medium: it is an undeclared side effect
on the host, in a block that documents its host contract as exactly two items and says
"Add no third dependency."

**Fix.** Save and restore rather than clear:

```bash
local _rb_t_term _rb_t_int
_rb_t_term="$(trap -p TERM)"; _rb_t_int="$(trap -p INT)"
trap '_rb_relay TERM 143' TERM
trap '_rb_relay INT  130' INT
…
trap - TERM INT
eval "${_rb_t_term:-}"; eval "${_rb_t_int:-}"
```

`trap -p` output is already correctly requoted by bash for re-eval, and the strings are
the host's own, not caller data. Add HI-01's restore alongside CR-02's HUP relay in one
edit. Regression guard: a unit case asserting `trap -p TERM` is byte-identical before and
after a `run_bounded` call on both arms — this is the assertion whose absence let it ship.

### HI-02: pgid lookup shells out to `awk`/`ps`; without them, descendant reaping silently fails

**File:** `scripts/gemini_shim.sh:92-110` (`_rb_pgid_of`), identically `scripts/agy_bridge.sh:75-93`

**Mechanism.** The procfs branch runs external `awk`; the fallback runs external `ps`.
Neither is otherwise needed by `run_bounded`, and neither is named in the block's host
contract. If neither binary resolves, `_rb_pgid_of` returns empty, `kill_pgid` stays
empty, and `_rb_signal` degrades to a pid-only `kill` — the child dies, its descendants
do not.

**Reproduced** (same TERM/HUP-ignoring forking child, bound 2s + 1s, only PATH differs):

```
with-awk-and-ps        pgid_warning=0  descendant_survived=no
no-awk-no-ps           pgid_warning=1  descendant_survived=YES
```

**Failure scenario.** The shim installs at `~/.local/bin/gemini` and is reached from
systemd units without a full `PATH`, `env -i` wrappers, container entrypoints and CI
runners — enumerated in the shim's own `${HOME:-}` comment at `:320-323` as exactly the
contexts it must survive. In any of them, on a coreutils-less host, the bound still fires
and still reports 124, but everything agy forked survives it. The operator sees the
`has no process group of its own` warning, which correctly reports the degradation — but
only if their stderr is not one of the four bounded sites that redirect it away.

The suite cannot see this: `_PUREBIN_TOOLS` (`tests/run-tests.sh:100-104`) hardcodes both
`awk` and `ps` into the sanitized PATH, and its comment calls that list "the deliverable
… it documents the real PATH dependency set". The list is right about the dependency; the
block's docblock and the README are silent on it.

**Fix.** Do it in bash and the dependency disappears (this also fixes MD-01 below, and
removes a fork per bounded call):

```bash
_rb_pgid_of() {
    local p="$1" v="" line
    if [[ -r "/proc/$p/stat" ]]; then
        read -r line < "/proc/$p/stat" 2>/dev/null || line=""
        line="${line##*') '}"                        # comm may contain spaces AND ')'
        v="${line#* }"; v="${v#* }"; v="${v%% *}"    # state ppid pgrp -> pgrp
    else
        v=$(ps -o pgid= -p "$p" 2>/dev/null) || v=""
    fi
    v="${v//[![:digit:]]/}"
    if [[ -n "$v" ]]; then printf '%s' "$v"; fi
    return 0
}
```

Regression guard: run the existing descendant case once with a PATH holding only `bash`
— the `no-awk-no-ps` row above is the assertion.

---

## Medium

### MD-01: `awk '{print $5}' /proc/pid/stat` mis-parses a `comm` containing whitespace

**File:** `scripts/gemini_shim.sh:95`, `scripts/agy_bridge.sh:78`

`/proc/pid/stat` is `pid (comm) state ppid pgrp …`, and `comm` may contain spaces and
`)`. Whitespace-splitting makes field 5 the pgrp *only* for a single-token comm.

**Measured on this host:**

```
comm='a b'    awk$5=1012776  sanitized=1012776  true_pgid=1012764   <- this is the PPID
comm='a b c'  awk$5=S        sanitized=''       true_pgid=1012764
comm='ab'     awk$5=1012764  sanitized=1012764  true_pgid=1012764
```

The two-word case is the dangerous one: it yields the **PPID**, which survives the
`[![:digit:]]` sanitiser, is not equal to `self_pgid`, and is therefore installed as
`kill_pgid` — so the ladder issues `kill -s TERM -- -<ppid>` and then
`kill -s KILL -- -<ppid>` at an unrelated process group. `_rb_signal`'s `|| true`
swallows the outcome either way, so the block reports a kill it may not have performed at
the target it named.

Not reachable from the shipped call sites — the bounded commands are `$AGY_BIN` (comm
`agy`) and `cat` — which is why this is Medium and not High. It is reachable the moment
anything else is passed. Note the irony worth recording: `_rb_pgid_of` carries an
eight-line comment defending a `ps -o pgid=` padding normalisation whose premise did not
reproduce on this host, two lines below a parse that is actually wrong.

**Fix:** the bash-only reader in HI-02, which splits after the last `') '` and is correct
for every comm.

### MD-02: `RUN_BOUNDED_KILLED` is dead in both shipped scripts

**File:** `scripts/gemini_shim.sh:86`, `:204`, `:223`, `:289` — identically `scripts/agy_bridge.sh:69`, `:187`, `:206`, `:272`

Assigned on four paths, read by **zero** lines in either shipped script. Every reader is a
test driver (`tests/run-tests.sh:2142`, `:2170`, `:2224`, `:2228`). The known-and-accepted
note covers only "it cannot escape the bridge's `cd` subshell, no code reads it *there*" —
the broader fact is that no shipped code reads it anywhere, on either entry point. Both
host sites discriminate on the exit code and `$DURATION` instead.

It is not a test-only *switch* (it changes no behaviour), so it is not the high-severity
class the brief names, but it is production state that exists to be observed by tests.
**Fix:** either delete it and have RB10/RB12 assert the biconditional through the exit code
alone, or give it a real reader — the shim's `137 && DURATION < SHIM_TIMEOUT`
external-kill discriminator at `:570` is precisely the site an authoritative flag would
replace, and doing so would also retire the `ponytail:` ceiling at `:285-287`.

### MD-03: RB04 and RB08 capture through the command substitution RB05 documents as unsafe

**File:** `tests/run-tests.sh:1258` (RB04), `:1857`/`:1871` (RB08), via `_run_sanitized` at `:146-156`

`_run_sanitized` captures with `__out="$(… 2>&1)"`. RB05's own comment at `:1774-1782`
explains that a surviving fake inherits fd 9, which under command substitution *is* the
capture pipe, and that this turned a ~10s red case into a ~5min one — and RB05, RB09,
RB10–RB14 were all moved to file capture as a result. RB04 and RB08 were not, and RB04 is
the case that drives `FAKE_AGY_FORK_HANG` through the shim.

A red RB04 therefore hangs until the outer `timeout … 30` net fires rather than failing on
its assertions. Not a false negative today, but it degrades the failure mode of the phase's
flagship case, and it means the suite's own defence against CR-01 is applied inconsistently.
**Fix:** route RB04/RB08 through the file-capture pattern the other cases use. (Fixing
CR-01 makes this moot, which is the better ordering.)

### MD-04: suite `cleanup()` SIGKILLs recorded PIDs without checking identity

**File:** `tests/run-tests.sh:38-47`

```bash
for f in "$SANDBOX"/*.pid; do
    p="$(cat "$f" 2>/dev/null)" || continue
    [[ "$p" =~ ^[0-9]+$ ]] && kill -KILL "$p" 2>/dev/null
done
```

Every `.pid` file written during the run is re-killed at EXIT, including those whose
process was deliberately reaped minutes earlier — `rb00b-*.pid` is written in the first
seconds of a 2m25s run. A recycled PID is SIGKILLed with no liveness or identity check.
On Linux with `pid_max` at 4194304 this is remote; on macOS, where `pid_max` is 99998 and
the phase's watchdog is the *reason the suite exists*, recycling inside 2m25s is ordinary.
A test harness that kills a developer's unrelated process is a defect regardless of
probability. **Fix:** truncate each pid file after its case reaps it, and/or verify the
target before killing (`ps -o comm= -p "$p"` matching the fake) — the cheap form is
`: > "$f"` at each case's own cleanup, which the cases already have.

### MD-05: `--version` is the only bounded site with no `</dev/null`

**File:** `scripts/gemini_shim.sh:435`

```bash
run_bounded 10 5 -- "$AGY_BIN" --version || _V_RC=$?
```

The other three bounded sites all pin stdin (`:338` and `:561` use `</dev/null`; `:511` is
guarded by `! -t 0` with a comment at `:509` explaining precisely why: *"so `cat` never
reads a TTY and backgrounding it in its own process group cannot stop on SIGTTIN"*). The
`--version` site has neither guard, so under `set -m` its child is backgrounded into its
own process group holding the caller's terminal and the caller's stdin.

Measured: a child that reads stdin at this site is not deadlocked — it is killed at
`secs + kill_after` (rc=124, elapsed 6s against a 4+2 bound) — so this is bounded, not a
hang. What it does cost: `gemini --version` stalls for its full 10s bound and exits 124
instead of answering, and the child can consume bytes from a caller's redirected stdin.
Real agy `--version` does not read stdin, which is why this is Medium. **Fix:** add
`</dev/null`, matching the other two agy sites.

---

## Low

### LO-01: the probe warning bypasses fd 9 and lands in `2>&1` payloads on every invocation

**File:** `scripts/gemini_shim.sh:46`, `scripts/agy_bridge.sh:37`

Deliberate and documented ("the probe runs before any call site has redirected anything"),
and RB08 pins both the count and the ordering. The residue: the line is emitted for
*every* invocation on a coreutils-less host, including `--help` and `--version`, and it is
the one diagnostic in the phase that does **not** use the descriptor introduced to keep
diagnostics out of payloads. A caller doing `v=$(gemini --version 2>&1)` — the standard
shape for probing a CLI's presence — gets the warning inside `$v`. The fd 9 rationale at
`:20-26` applies here too and is not applied. If the once-per-run property must hold, the
cheapest reconciliation is to emit it to fd 9 (already open by then — `exec 9>&2` is line
27/17, above the probe) rather than to plain stderr.

### LO-02: `exec 8>&2` / `exec 8>&-` clobbers and closes fd 8 in the caller's shell

**File:** `scripts/gemini_shim.sh:240`, `:247` — identically `scripts/agy_bridge.sh:223`, `:230`

An undeclared third descriptor dependency next to fd 9, and it is not merely borrowed: it
is opened and then **closed**, so a caller that passed fd 8 in (`gemini … 8>trace.log`)
loses it after the first watchdog-arm bounded call. Obscure, but the block ships as a
box-wide `gemini` and its docblock claims a two-item host contract. **Fix:** use a
bash-4.1 `{fd}>&2` dynamic descriptor, or at minimum add fd 8 to the declared contract.

### LO-03: `_rb_pgid_of`'s comment defends a normalisation whose premise did not reproduce

**File:** `scripts/gemini_shim.sh:99-107`, `scripts/agy_bridge.sh:82-90`

Eight lines justifying the `[![:digit:]]` strip against `ps -o pgid=` right-padding — a
premise the phase itself records as not reproducing on this host. Keeping the strip is
correct (it is the defence for the no-procfs/macOS path and it is what makes MD-01's
three-word case fail closed rather than open). The finding is proportion: the longest
comment in the function defends the cheapest line, while the line above it parses
`/proc/pid/stat` incorrectly (MD-01) with no comment at all. Trim the justification to one
sentence when MD-01 is fixed.

---

## Explicitly checked, no finding

- **Byte-identity (RB02's claim).** Verified independently: the two marker ranges are 232
  lines each and `diff` is empty. RB02 and RB02m are sound, and RB02m proves the
  comparison can fail.
- **Test-only switches in shipped code.** None. `TIMEOUT_BIN` is probe-set; RB21b's
  `_rb_pgid_of` override and RB14's `TIMEOUT_BIN` are in the *drivers*, which is correct.
  `RB_NO_TIMEOUT_WARN` / `RB_WATCHDOG_KILLED_NOTE` are string constants, not switches
  (RB03 pins them by grepping the source — a legitimate shape).
- **The three fixed defects.** No recurrence. `-84e` (false self-kill warning): 0/80
  warnings across builtin, external, script and forking-script children, and 0/20 across
  real shim runs on both the 2-site and 3-site paths. `-vtx` (orphaned timer sleep) and
  `-kk9.18` (unescalated relay) both hold — the TERM row of the CR-02 table is the relay
  working correctly.
- **Quoting / injection on bounds and paths.** Clean. Bounds are `^[1-9][0-9]*$`-validated
  at both the env-var source and inside the helper, and reach `sleep`/`kill`/`timeout`
  only as quoted operands — never eval'd, never interpolated into a command string. RB11's
  seven refusal probes plus its positive control cover the empty/zero/non-numeric set, and
  its "did not run" sentinel is the right assertion.
- **`set -euo pipefail` interaction.** `_rb_pgid_of` correctly swallows its own failures
  and `return 0`s; every `kill` carries `|| true`; every `$( )` that can fail carries a
  fallback. No unguarded pipeline in command substitution trips `errexit`.
- **`RUN_BOUNDED_KILLED` in the bridge's `cd` subshell, the fork-to-`timer=$!` window, the
  137-branch scoping, suite runtime.** Read as recorded ceilings; nothing found that
  understates them. The fork window in particular is as narrow as claimed — a signal must
  land between `&` and `timer=$!`, and the reversed order genuinely is worse.

---

_Reviewed: 2026-08-19T15:01:06Z_
_Reviewer: Claude (gsd-code-reviewer), adversarial stance_
_Depth: deep — every Critical and High finding reproduced at runtime against the shipped code, not inferred_
