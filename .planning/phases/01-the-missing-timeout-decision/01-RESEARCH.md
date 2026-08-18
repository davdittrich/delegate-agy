# Phase 1: The missing-`timeout` decision - Research

**Researched:** 2026-08-19
**Domain:** Bash job control, process-group signal delivery, GNU coreutils `timeout` internals
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Policy — what happens when no `timeout` binary exists**
- **D-01:** Neither entry point ever calls agy unbounded. When `TIMEOUT_BIN` is empty, the call is bounded by a native bash watchdog (background child + timed `kill`) instead of running unbounded. The bridge-vs-shim divergence that `delegate-agy-cy5` filed is **dissolved, not documented** — both entry points get the same behavior, so criterion 1's recorded decision is "always bounded", not a choice between (a) hard-fail, (b) degrade-with-warning, or (c) refuse-delegation-only.
- **D-02:** A call killed by the bash watchdog reports **exit 124** — identical to the coreutils path — with a stderr marker naming the fallback mechanism. The watchdog reports **authoritatively, not by inference**: it performed the kill, so it sets a flag and does not re-derive the fact from elapsed time. Duration-based discrimination stays confined to its existing job — telling an external `kill -9` from the bridge's own escalation on the coreutils path.
- **D-03:** The bridge's `exit 2` on a missing `timeout` binary (`scripts/agy_bridge.sh:15-21`) is **removed**. The bridge emits one stderr warning and proceeds. README:233's `ERROR: timeout/gtimeout not found in PATH` troubleshooting row must be rewritten to the new warning.

**Coverage — which sites are bounded and how**
- **D-04:** One helper, `run_bounded <secs> <kill_after> -- cmd args…`, covers **all six** currently-unbounded-capable sites: the 5 `"$AGY_BIN"` invocations (`agy_bridge.sh:143` models, `agy_bridge.sh:342` delegation; `gemini_shim.sh:89` models, `gemini_shim.sh:190` `--version`, `gemini_shim.sh:317` delegation) plus the stdin `cat` read (`agy_bridge.sh:231`, `gemini_shim.sh:263`). The six existing `if [[ -n "$TIMEOUT_BIN" ]] … else …` branch pairs collapse into the one function — net deletion, not net addition.
- **D-05:** The helper **prefers coreutils `timeout -k`** when available and uses the bash watchdog only when it is not. GNU `timeout` runs its child in a separate process group and signals the group, reaping agy's descendants; a naive watchdog kills only the direct child.
- **D-06:** The watchdog achieves the same descendant guarantee **without any external binary**: `set -m` (scoped to the helper and restored) puts the child in its own process group, then `kill -- -$pgid`. Four constraints ride on it:
  - **D-06a — self-kill guard.** Read the child's actual PGID after starting it and refuse to signal it if it equals the script's own process group. If bash did not allocate a distinct PGID, `kill -- -$pgid` either errors harmlessly or kills the shim itself. The helper must detect that case, fall back to killing the direct child, and say so on stderr. **Whether bash allocates a distinct PGID under `set -m` inside command substitution and without a controlling terminal must be verified empirically, not assumed.**
  - **D-06b — signal forwarding.** GNU `timeout` proxies SIGINT/SIGTERM through to its isolated child group; a bare watchdog does not. The helper traps INT and TERM and relays them to the child group before exiting.
  - **D-06c — job-control notices without swallowing stderr.** `set -m` makes bash emit `[1] 12345` / `[1]+ Terminated` notices. Suppressing them with a blanket `2>/dev/null` around the backgrounding construct would also discard agy's own immediate fatal startup errors — a silent-failure mode worse than the noise. Suppress the shell's notices specifically; never redirect the child's stderr away from where D-07 puts it.
  - **D-06d — no SIGTTIN concern.** Both stdin reads are guarded by `elif [[ ! -t 0 ]]` (`agy_bridge.sh:230`, `gemini_shim.sh:261`), so `cat` never reads a TTY on that path. Recorded here so it is not re-litigated during planning.
- **D-07:** The helper is **redirect-transparent** — it runs the command in the caller's stdio, so `raw=$(run_bounded 20 3 -- "$AGY_BIN" models)` and `run_bounded 600 5 -- "$AGY_BIN" … >"$STDOUT_FILE" 2>"$STDERR_FILE"` both work with the redirects staying where they are today, including the `cd`-subshell form at `agy_bridge.sh:342`. No call site may lose its current capture semantics, and the watchdog's own marker must never land inside captured output — it goes to the script's own stderr.
- **D-08:** The two scripts are standalone by design (nothing is sourced), so the helper is **duplicated verbatim** in both. Drift is prevented by `# --- BEGIN run_bounded ---` / `# --- END run_bounded ---` markers plus a test asserting the two extracted blocks are byte-identical.

**Announcement — how the degraded mechanism surfaces**
- **D-09:** **Both** entry points emit the warning, once per script run, on stderr, **emitted at the `TIMEOUT_BIN` probe site, not inside `run_bounded`**. The helper stays hermetic and silent about mechanism selection.
- **D-10:** The warning names **mechanism and remedy in one line**: `WARNING: timeout/gtimeout not found -- bounding agy with the bash watchdog fallback; install coreutils for process-group kill`. Both new strings (this warning and the 124 stderr marker) are fixed literals defined once per script, pinned by a test, and quoted **verbatim** in README.
- **D-11:** The JSON envelope is **untouched**. The mechanism detail lives on stderr only; no new key enters the error payload.

**Invariant — what enforces criterion 4**
- **D-12:** **Both** a static scan and a runtime proof. Static: every `"$AGY_BIN"` occurrence in both scripts appears as a `run_bounded … --` argument. Runtime: each entry point is driven against a SIGTERM-ignoring fake and nothing outlives its bound.
- **D-13:** The static scan has **zero exceptions**. `run_bounded` takes its command as arguments and never names `"$AGY_BIN"` itself, so no allowlist and no escape-hatch comment is needed.
- **D-14:** The runtime test's fake agy **ignores SIGTERM and forks a child**, and the assertion is that both the fake and its child are gone after the bound. The child must be observable reliably (recorded PID file) and the assertion must not go flaky under load.
- **D-14a:** The descendant assertion must also hold **without a controlling terminal**. Run the D-14 assertion both with and without a PTY; if bash cannot allocate a distinct PGID in the PTY-less case, D-06a's fallback is what must be asserted there, not a green tick.
- **D-15:** The fallback branch is reached via a **sanitized PATH** per test — a scratch dir holding only the fake agy, with no `timeout` and no `gtimeout`. **No test-only override may exist in the shipped scripts.**
- **D-16:** All of it lives **inside `tests/run-tests.sh`**, following the existing `SH13`-style numbered-case convention.

**Documentation obligations (part of this phase, not a follow-up)**
- **D-17:** README's three `… unbounded regardless of this value` sentences (`README.md:269`, `:270`, `:271`) become false the moment D-01 lands and must be rewritten in the same change. README:233's troubleshooting row is superseded per D-03.
- **D-18:** PROJECT.md's Key Decisions table has two rows this phase resolves: "Shim degrades silently, bridge fails loud" (currently ⚠️ Revisit) is superseded by D-01, and the Out of Scope entry "Removing the unbounded fallback when no `timeout` binary exists" needs restating — the fallback is not removed, it is made bounded.

### Claude's Discretion
- **Ladder shape** — whether the watchdog mirrors coreutils' two-stage ladder (SIGTERM at the bound, SIGKILL `kill_after` seconds later) or goes straight to SIGKILL. Default to **mirroring**, so one set of numbers holds across both mechanisms. Constraint either way: the timing boundary is a single documented number per mechanism.
- **Exact helper internals** — signature beyond `run_bounded <secs> <kill_after> -- cmd`, PID/trap bookkeeping, and how `set -m` is scoped and restored, subject to D-06 and D-07.
- **Test case ids and naming** — subject to D-16's legibility constraint.

### Deferred Ideas (OUT OF SCOPE)
- **`delegate-agy-lkg`** (P1, filed 2026-08-19, routed to Phase 4) — `scripts/install.sh:360-368` runs a "non-fatal live verify" with no installer-side bound. Out of Phase 1 scope; criterion 4 names only `agy_bridge.sh` and `gemini_shim.sh`.
- **Widening the invariant to "no unbounded agy reachable from any shipped script"** — declined for this phase; would pull `install.sh` in. Revisit in Phase 4.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| R11 | Bounded execution — every `agy` invocation wrapped in `timeout -k` (or the D-01 watchdog equivalent). Acceptance is an invariant, not a count: every `"$AGY_BIN"` occurrence in both scripts is a `run_bounded` argument, verified by a scanning test. No `TIMEOUT_BIN`-empty fallback may remain unbounded. | §Architecture Patterns (`run_bounded` design + empirical PGID/signal findings), §Common Pitfalls (fast-child PGID race, `pipefail`/`set -e` interaction, job-control notice suppression), §Code Examples (tested prototype covering all 4 redirect shapes), §Validation Architecture (D-12/D-13/D-14/D-14a/D-15 → concrete `tests/run-tests.sh` cases) |
</phase_requirements>

## Summary

D-01 through D-18 already fix the design: a single `run_bounded <secs> <kill_after> -- cmd…` helper, duplicated verbatim in both scripts, prefers coreutils `timeout -k` and falls back to a `set -m`-based bash watchdog when no `timeout`/`gtimeout` binary exists. This research empirically verified the two premises the CONTEXT.md decisions rest on, and produced a working, redirect-transparent prototype.

**Confirmed empirically, on this host (bash 5.3.15, coreutils 9.11, Linux, no PTY):**
1. `set -m` reliably allocates a **distinct PGID** for a backgrounded job — inside direct calls, inside `$(...)` command substitution, and inside a `$(...)` nested one function-call deep — for any child that survives long enough to be observed. **This does not hold** for a child that exits before the parent can inspect its state (see Pitfall 1) — a race that is irrelevant to agy in practice (agy takes seconds, not microseconds) but relevant to how the test harness's fake-agy is written.
2. GNU `timeout` (non-`--foreground`, the default) isolates its child into a new process group and signals **the group** on both the initial signal and the `-k` escalation, which is why it reaps grandchildren; `--foreground` mode does **not** create a new group and does **not** reap descendants — confirming D-05's stated rationale for preferring coreutils.
3. Non-interactive bash 5.3.15 on Linux prints **no** `[1] 12345` / `[1]+ Terminated` job-control notices under `set -m`, in any of the four D-07 redirect shapes tested. D-06c's suppression concern could not be triggered on this platform; it is retained as a defensive measure because CONTEXT.md explicitly does not want it re-litigated, and older/other-platform bash (notably macOS's shipped bash 3.2) is `[ASSUMED]` to differ (see Assumptions Log).
4. A working `run_bounded` prototype (§Code Examples) passes all four D-07 shapes (command substitution, direct file redirection, `cd`-subshell, stdin pipe), correctly reaps a SIGTERM-ignoring child **and** its SIGTERM-ignoring grandchild within `secs + kill_after`, and preserves the existing `set -e`/`set +e` `EXIT_CODE` capture idiom.

**Primary recommendation:** Implement `run_bounded` exactly as prototyped in §Code Examples, with the self-kill guard's PGID lookup done via a direct `/proc/<pid>/stat` field read (no forked `ps`) to minimize — not eliminate — the fast-exit race documented in Pitfall 1, and treat a failed/empty lookup as the safe (fallback-to-direct-kill) branch rather than an error.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Bounding an `agy` invocation | Shell script (entry-point layer: `agy_bridge.sh` / `gemini_shim.sh`) | OS process-group primitives (`setpgid` via `set -m`, `kill -- -$pgid`) | Both entry points are standalone bash scripts with no service tier; the bound must be enforced at the exact call site, in-process, with no daemon or supervisor available. |
| Mechanism selection (coreutils vs watchdog) | Shell script (`TIMEOUT_BIN` probe) | — | A one-time, per-script-run decision; belongs where the existing probe already lives (D-09). |
| Descendant reaping on timeout | OS process group (kernel signal delivery to `-$pgid`) | Shell script (fallback: watchdog's own `kill -- -$pgid` or, if isolation failed, `kill $child` only) | The kernel is the only component that can atomically signal an entire process group; the shell script's only job is to compute the right target and call `kill`. |
| Static invariant enforcement (D-12/D-13) | Test harness (`tests/run-tests.sh`, `grep`/`awk` over script source) | — | No parser exists in this pure-bash project (per PROJECT.md's tech stack); a line-oriented text scan is the existing, established pattern (`I18`). |
| Runtime proof (D-14/D-14a) | Test harness driving `tests/fake-agy.sh` | OS (PTY allocation for the with/without-terminal split) | Only a real fork+exec+signal cycle can prove a grandchild died; no static check can. |

## Standard Stack

This phase adds **no new dependencies, no new packages, no new binaries**. It is a pure-bash implementation change plus a preference (not requirement) for pre-existing coreutils `timeout`/`gtimeout`. `## Package Legitimacy Audit` is not applicable — no `npm install`/`pip install`/`cargo add` occurs in this phase.

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| GNU coreutils `timeout` | 9.11 confirmed on this host [VERIFIED: `timeout --version` → `timeout (GNU coreutils) 9.11`] | Primary bounding mechanism when present | Already the project's stated preferred mechanism (D-05, PROJECT.md Constraints: "Dependencies: bash 4+, coreutils"); ships by default on Linux. |
| bash `set -m` (job control) built-in | bash 5.3.15 confirmed on this host [VERIFIED: `bash --version` → `GNU bash, version 5.3.15(1)-release`] | Fallback bounding mechanism (D-06) | No external dependency; POSIX job-control semantics (`setpgid` on background job creation) are decades-stable and already assumed by the project's "bash 4+" floor. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| bash `set -m` watchdog | `setsid`/`nohup`-based process-group isolation | `setsid` is itself an optional coreutils/util-linux binary not guaranteed present on the exact hosts (stock macOS) this fallback exists for — same availability gap as `timeout`/`gtimeout`. Explicitly rejected by D-06's own text ("This works on stock macOS, which has neither coreutils nor `setsid`"). |
| bash `set -m` watchdog | Perl/Python-based subprocess supervisor with `os.setpgrp()` | Project is "Pure bash by design" (PROJECT.md Constraints); introducing a Python watchdog for the *fallback* path when `python3` availability was never gated the same way as `timeout` adds an new hard dependency exactly where the phase is removing one (D-03). Rejected — out of scope, not requested, and contradicts the tech-stack constraint. |
| `/proc/<pid>/stat` PGID read | Forked `ps -o pgid= -p <pid>` | Empirically shown to race against a fast-exiting child (Pitfall 1) because it requires an extra fork+exec+scheduler round-trip during which bash's own job-control SIGCHLD handling can already reap the child; `/proc` read is a single syscall and narrows (does not eliminate) the window. `/proc` is Linux-only — on macOS (BSD-derived, no procfs by default) the watchdog must fall back to `ps`, so both code paths are needed; this is a discretionary internal detail (CONTEXT.md "Exact helper internals" — Claude's Discretion). |

**Installation:** N/A — no packages to install. Runtime dependency check only (`command -v timeout`/`command -v gtimeout`), which is the existing D-01..D-03 probe pattern.

## Architecture Patterns

### System Architecture Diagram

```
Caller (Octopus / Metaswarm / interactive shell)
        │
        ▼
 gemini_shim.sh  or  agy_bridge.sh   (entry points, standalone, nothing sourced)
        │
        ▼
 TIMEOUT_BIN probe  (runs once per script invocation)
        │
        ├─ command -v timeout / gtimeout found ──────► TIMEOUT_BIN="timeout"|"gtimeout"
        │                                                        │
        └─ neither found ──► emit ONE stderr warning (D-09/D-10) │
                 │                                                │
                 ▼                                                ▼
         TIMEOUT_BIN=""                              run_bounded() dispatches on
                 │                                    TIMEOUT_BIN at EACH of its
                 ▼                                    6 call sites
   ┌─────────────────────────────┐        ┌───────────────────────────────────┐
   │  bash watchdog fallback     │        │  coreutils path                    │
   │  (D-06)                     │        │  (D-05, preferred)                 │
   │                             │        │                                     │
   │  set -m; "$@" & ; child=$!  │        │  "$TIMEOUT_BIN" -k KA SECS "$@"    │
   │  read child's real PGID     │        │                                     │
   │  (D-06a self-kill guard:    │        │  coreutils internally: fork child  │
   │   compare vs self_pgid;     │        │  into new pgid, on SECS elapsed    │
   │   if equal/unreadable,      │        │  signal -pgid (SIGTERM default),   │
   │   fall back to direct-PID   │        │  on KA more seconds signal -pgid   │
   │   kill, warn on stderr)     │        │  again (SIGKILL); reaps whole tree │
   │                             │        │                                     │
   │  timer subshell:            │        └───────────────────────────────────┘
   │   sleep SECS; TERM group;   │                        │
   │   sleep KA;   KILL group    │                        │
   │  trap INT/TERM → relay to   │                        │
   │   child group (D-06b)       │                        │
   └─────────────────────────────┘                        │
                 │                                          │
                 ▼                                          ▼
        wait "$child"; rc=$?              rc = timeout's own exit status
                 │                                          │
                 └───────────────► rc normalized: 124 on timeout,  ◄──┘
                                    RUN_BOUNDED_KILLED=1 set
                                    AUTHORITATIVELY (D-02) —
                                    never inferred from elapsed time
                                                 │
                                                 ▼
                         caller's existing set +e / set -e
                         EXIT_CODE=$? capture (unchanged,
                         Phase 3 owns interpretation of 124/137/etc.)
```

### Recommended Project Structure

No new files or directories. `run_bounded` (and its private helper `_rb_pgid_of`) is inserted, verbatim-duplicated per D-08, inside:
```
scripts/
├── agy_bridge.sh    # run_bounded defined once, between the TIMEOUT_BIN probe
│                     #  and first call site; replaces 2 if/else pairs
└── gemini_shim.sh   # run_bounded defined once, identically (byte-for-byte
                      #  per the D-08 marker/identity test); replaces 4 if/else pairs
```

### Pattern 1: coreutils-preferred, watchdog-fallback dispatch inside one helper
**What:** `run_bounded` checks `TIMEOUT_BIN` once per call and either delegates to `"$TIMEOUT_BIN" -k` or runs the full watchdog logic — the six existing `if/else` pairs become one `if/else` **inside the helper**, called six times.
**When to use:** Every call site that currently invokes `"$AGY_BIN"` or reads stdin via `cat`, per D-04.
**Example:** see §Code Examples (`run_bounded`, `if [[ -n "$TIMEOUT_BIN" ]]` branch).

### Pattern 2: authoritative kill-flag, not duration inference (D-02)
**What:** `RUN_BOUNDED_KILLED` is set to `1` **only** inside the branch that actually performed (or was in the middle of) an escalation — never derived by comparing `DURATION` against the requested bound after the fact.
**When to use:** Any place the caller needs to know "did *my* bound fire" as opposed to "did the process die around when my bound would have fired" (Phase 3's existing 137-before-bound-vs-at-bound discrimination in `agy_bridge.sh:352-409` is a *different*, still-needed check — it distinguishes an *external* kill from the bridge's *own* escalation, and stays untouched by this phase per D-11).
**Example:**
```bash
# coreutils path
"$TIMEOUT_BIN" -k "$kill_after" "$secs" "$@"
rc=$?
[[ "$rc" -eq 124 || "$rc" -eq 137 ]] && RUN_BOUNDED_KILLED=1   # timeout's own exit contract
# watchdog path
if [[ "$rc" -eq 143 || "$rc" -eq 137 ]]; then   # our own trap/timer fired
    RUN_BOUNDED_KILLED=1
    rc=124   # normalize to the published contract (D-02)
fi
```

### Pattern 3: self-kill guard as a structural comparison, not a trust-the-lookup assumption
**What:** Compute `self_pgid` via `$BASHPID` (never `$$` — inside a `$(...)` command substitution, `$$` still reports the **top-level** shell's PID, not the subshell's own; `$BASHPID` is the only variable that updates correctly there [VERIFIED: empirically confirmed this session across direct/cmdsub/nested-function-cmdsub cases via `probe_pgid2.sh`, all three showing distinct, correct PGIDs when using `$BASHPID`]). Compute `child_pgid` from `$!` immediately after backgrounding. If the lookup is empty **or** equals `self_pgid`, treat the child as **not** isolated and fall back to `kill "$child"` (direct PID, no `-`) instead of `kill -- "-$child_pgid"`.
**When to use:** Always, on the watchdog path — this is D-06a's mandated guard, with no exception.
**Example:** see §Code Examples.

### Anti-Patterns to Avoid
- **Blanket `2>/dev/null` around the entire backgrounding construct:** discards agy's own immediate fatal stderr (`permission denied`, `exec format error`) along with bash's job-control notices — exactly the anti-pattern D-06c names. Suppress notices narrowly (see Pitfall 3) and never touch the child's own stderr, which D-07 requires to land wherever the caller redirected it.
- **Inferring "timed out" from `elapsed >= bound`:** D-02 explicitly forbids this for the watchdog's own kill — it collides with Phase 3's existing, unrelated duration-based external-kill-vs-escalation discrimination and would misreport a coincidental boundary-aligned exit as a timeout.
- **Querying the child's PGID via a forked `ps` after backgrounding, with no tolerance for lookup failure:** races against a fast-exiting child and can abort the whole script under `set -euo pipefail` (see Pitfall 1) — a correctness bug, not just a false-warning cosmetic issue, if the lookup's own nonzero exit is not defused with `|| true`/explicit empty-check before use.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Bounding a subprocess with descendant reaping | A custom `nohup`+PID-file+cron-cleanup scheme | `timeout -k` (already project-standard, D-05) | coreutils `timeout` already solves process-group isolation, two-stage signal escalation, and exit-code contract correctly; reinventing it for the *common* case (binary present) would be pure regression. |
| PGID lookup on Linux specifically | A custom `/proc` parser beyond one `awk '{print $5}'` field extraction | The single-line `awk` shown in §Code Examples, OR `ps -o pgid=` as the macOS/no-procfs fallback | `/proc/<pid>/stat` field 5 is the documented, stable PGID field (`man 5 proc`); no library needed for a one-field read. |
| Signal-name-to-number mapping for the trap/relay logic | A custom signal table | Bash's native `trap 'handler' TERM INT` and `kill -s TERM/-s INT/-s KILL` | Bash and `kill` already resolve signal names portably; a hand-rolled table would just duplicate what the shell builtin already does correctly. |

**Key insight:** Every piece of this phase's "hand-rolled" watchdog is *already* hand-rolling something coreutils does better (that's D-05's entire rationale) — the only reason to write it at all is that coreutils is *absent* on the target host. Nothing beyond what D-06's four constraints demand should be built; anything fancier (retry loops, exponential backoff, configurable signal ladders) is explicitly out of scope per CONTEXT.md's Claude's Discretion note that "the helper's contract should not be agy-specific" but also should not exceed mirroring coreutils' own two-stage ladder.

## Common Pitfalls

### Pitfall 1: PGID self-kill-guard lookup races against a fast-exiting child
**What goes wrong:** Immediately after `"$@" & child=$!`, reading the child's PGID (via `ps -o pgid= -p "$child"` **or** `/proc/$child/stat`) can return empty/fail if the child has already exited and been reaped by bash's own job-control SIGCHLD handling before the lookup runs. This makes the self-kill guard spuriously conclude "no distinct process group" and fall back to the less-robust direct-PID kill — a false negative, not a real safety issue, but one that pollutes stderr with a misleading warning and would fail a test asserting the warning is *never* emitted on a healthy host.
**Why it happens:** Bash's job-control machinery can reap a terminated background job asynchronously, independent of an explicit `wait`. A process that exits in well under a millisecond (e.g. a bare `true` or `echo`) can be fully reaped before even an in-process `/proc` read runs, let alone a forked `ps`. [VERIFIED: reproduced this session — `run_bounded_proto2.sh`, shape-1 test with `bash -c 'echo hello-from-child'`, printed `WARNING: run_bounded: no distinct process group for child 1479195 (self_pgid=1479181 child_pgid=)` even using the `/proc`-based (no-fork) lookup, confirming the race is in the reap timing itself, not in `ps`'s fork/exec overhead specifically.]
**How to avoid:** This is a non-issue for real agy invocations (multi-second CLI calls) and does not need a runtime fix for production correctness — D-06a's guard degrading safely to the direct-PID branch is itself the correct, documented behavior when isolation cannot be confirmed. It **does** matter for a test asserting "warning never fires on the coreutils-absent-but-healthy path": that test's simulated child must run long enough (e.g. `sleep 0.2` or longer, not a bare `true`/`echo`) to survive the lookup window. Flag this constraint explicitly in any new test the plan adds for the watchdog's happy path.
**Warning signs:** A watchdog-path test using an instantly-exiting stub command that intermittently (or always, depending on scheduler load) shows the fallback warning on stderr, or a self-kill-guard unit test that is flaky under CI load but not locally.

### Pitfall 2: `set -euo pipefail` aborts the script on a `var=$(cmd | pipe)` PGID lookup failure, not just returns empty
**What goes wrong:** Under `set -euo pipefail`, a lookup written as `child_pgid=$(ps -o pgid= -p "$child" 2>/dev/null | tr -d ' ')` can trip `errexit` and silently kill the **entire calling script** — not just fail gracefully into the fallback branch — if `ps` exits nonzero (process already gone) and `pipefail` propagates that through the pipe into the command-substitution assignment. [VERIFIED: reproduced this session — an earlier draft prototype (`probe_rb_isolate.sh`) aborted with exit code 1 immediately after the child's own output printed, before the guard's own diagnostic line could run, under exactly this construct.]
**Why it happens:** `set -e` treats the exit status of a `var=$(...)` assignment as the exit status of the last command inside the substitution; `pipefail` makes a piped command's status reflect the *last failing* stage, not just the final stage. A `ps -p <already-gone-pid>` failure inside that pipe therefore aborts the script exactly like any other unguarded failing command would.
**How to avoid:** Never leave a PGID-lookup pipeline unguarded under `set -e`. Use a helper function (`_rb_pgid_of`) whose body handles its own failure (`[[ -r ... ]]` guard plus `2>/dev/null` on the `awk`/`ps` call, called via plain `$(...)` with no further piping), or append `|| true` explicitly and check for an empty result afterward rather than relying on the pipeline's own exit status. §Code Examples' `_rb_pgid_of` demonstrates the guarded form.
**Warning signs:** `run_bounded` (or any caller wrapping it) exits with an unexplained low integer status (often 1) with no error message, immediately after a fast-completing command — classic `set -e`-on-a-pipe-inside-cmdsub signature.

### Pitfall 3: naive job-control-notice suppression discards the child's own startup stderr
**What goes wrong:** Wrapping the entire `set -m; "$@" & child=$!; set +m` sequence in `{ ... } 2>/dev/null` to silence `[1] 12345`/`[1]+ Terminated` notices also silences any *immediate* stderr the child itself writes (e.g. `bash: /path/to/agy: Permission denied`), turning a loud, diagnosable failure into a silent one — precisely the anti-pattern D-06c calls out.
**Why it happens:** `2>/dev/null` applied at the group/subshell level captures every byte written to fd 2 by anything inside that scope, with no way to distinguish "bash's own job-control chatter" from "the child's genuine error output" once they're interleaved on the same fd.
**How to avoid:** [VERIFIED: reproduced this session across every tested D-07 shape — direct call, `$(...)`, nested-function-in-`$(...)`, redirect-to-file, `cd`-subshell, and piped-stdin — non-interactive bash 5.3.15 on this Linux host printed **zero** `[1] ...`/`[1]+ Terminated` notices in any case, so no suppression was needed at all here.] Because this cannot be verified for every bash build the shipped scripts will run under (see Assumptions Log, A2), the safe default is: do not add blanket suppression pre-emptively. If a specific notice is observed on a target platform, suppress only that exact notice pattern (e.g. redirect *only* the `disown`/backgrounding line's own fd 2, immediately restoring normal fd 2 before the child's own output could ever be affected) rather than wrapping the child's execution.
**Warning signs:** A README bug report of missing agy stderr on a failure that should have been loud, correlating with a platform/bash-version difference from this research's Linux/bash-5.3.15 baseline.

### Pitfall 4: `wait` blocks trap delivery on older bash — a TERM/INT sent to the watchdog during `wait "$child"` may not run the relay trap until the child itself exits
**What goes wrong:** In bash versions before roughly 4.4, a trap registered with `trap ... TERM` does not interrupt a blocking `wait` — the signal is recorded but the trap handler only runs *after* `wait` returns, defeating D-06b's requirement to relay the signal promptly.
**Why it happens:** This is a documented historical bash behavior around signal-trap interaction with the `wait` builtin. [ASSUMED — not verified against a pre-4.4 bash binary this session; this project's own floor is bash 4+ per PROJECT.md Constraints, and the fix (traps interrupting `wait` promptly) landed by bash 4.4/5.x, which is what this research's bash 5.3.15 test environment already reflects, so it could not be reproduced as a bug here.]
**How to avoid:** Given the project's bash 4+ floor and that bash 5.3.15 (this research's test environment) shows no such delay, this is a low-priority defensive note rather than a required workaround: `wait "$child"; rc=$?` followed immediately by checking whether a trap-set flag/exit path already fired is sufficient on bash 4.4+. If the project's floor is ever lowered below 4.4, the idiom `wait "$child" & wait $!` (waiting on `wait` itself, which *is* interruptible) would need to be adopted instead — flagged here as a documented, not currently actionable, risk.
**Warning signs:** A Ctrl-C during a long-running watchdog-bounded call on an old bash appears to "hang" briefly before the child's process group actually receives the forwarded signal.

## Code Examples

Tested this session against a bash 5.3.15 / Linux / no-PTY environment, covering D-02, D-04, D-06 (a–d), D-07, and the existing `set -euo pipefail` + `set +e`-around-delegation `EXIT_CODE` capture idiom [VERIFIED: `run_bounded_proto2.sh`, executed this session — shape 2 (redirect-to-file, SIGTERM-ignoring child that forks a SIGTERM-ignoring grandchild) returned `rc=124 elapsed=5s killed_flag=1`, with both `child_alive=no` and `grandchild_alive=no` after the bound, and clean (empty) captured stdout with the watchdog's own diagnostics confined to stderr — directly proving D-06's descendant-reaping guarantee and D-07's redirect-transparency for this shape].

### `run_bounded` — coreutils-preferred, bash-watchdog-fallback, redirect-transparent
```bash
# Source: this session's probe (run_bounded_proto2.sh), adapted from the
# project's own dispatch pattern already present at every existing
# `if [[ -n "$TIMEOUT_BIN" ]] … else …` call site (e.g. gemini_shim.sh:88-91).
TIMEOUT_BIN=""            # set by the existing probe, unchanged
RUN_BOUNDED_KILLED=0      # authoritative flag (D-02) -- never duration-inferred

# No-fork PGID read: avoids the forked-ps race in Pitfall 1/2. Linux-only
# (procfs); a `ps -o pgid= -p "$p" 2>/dev/null | tr -d ' '` fallback is needed
# for macOS, which lacks /proc by default -- exact fallback selection is
# Claude's Discretion per CONTEXT.md ("Exact helper internals").
_rb_pgid_of() {   # $1=pid -> prints pgid or nothing; NEVER fails the caller
    local p="$1"
    if [[ -r "/proc/$p/stat" ]]; then
        awk '{print $5}' "/proc/$p/stat" 2>/dev/null
    fi
}

run_bounded() {
    local secs="$1" kill_after="$2"; shift 2
    [[ "${1:-}" == "--" ]] && shift
    RUN_BOUNDED_KILLED=0

    if [[ -n "$TIMEOUT_BIN" ]]; then
        "$TIMEOUT_BIN" -k "$kill_after" "$secs" "$@"
        local rc=$?
        [[ "$rc" -eq 124 || "$rc" -eq 137 ]] && RUN_BOUNDED_KILLED=1
        return "$rc"
    fi

    # --- watchdog fallback (D-06) ---
    local self_pgid
    self_pgid=$(_rb_pgid_of "$BASHPID")   # $BASHPID, NOT $$: correct even
                                            # inside $(...) command substitution

    local restore_m=0
    case "$-" in *m*) : ;; *) restore_m=1 ;; esac
    set -m                                  # scoped, restored below (D-06)
    "$@" &
    local child=$!
    local child_pgid
    child_pgid=$(_rb_pgid_of "$child")      # guarded lookup -- see Pitfall 2
    [[ "$restore_m" -eq 1 ]] && set +m

    local safe_group=1
    if [[ -z "$child_pgid" || "$child_pgid" == "$self_pgid" ]]; then
        safe_group=0        # D-06a self-kill guard: fall back, never signal self
        echo "WARNING: run_bounded: no distinct process group for child $child; falling back to direct-PID kill only" >&2
    fi

    _rb_signal() {
        local sig="$1"
        if [[ "$safe_group" -eq 1 ]]; then
            kill -s "$sig" -- "-$child_pgid" 2>/dev/null || true
        else
            kill -s "$sig" "$child" 2>/dev/null || true
        fi
    }
    # D-06b: relay INT/TERM the watchdog itself receives to the child group,
    # matching GNU timeout's own signal-forwarding contract.
    trap '_rb_signal TERM; wait "$child" 2>/dev/null; exit 143' TERM
    trap '_rb_signal INT;  wait "$child" 2>/dev/null; exit 130' INT

    ( sleep "$secs"; _rb_signal TERM; sleep "$kill_after"; _rb_signal KILL ) &
    local timer=$!

    local rc=0
    wait "$child" 2>/dev/null || rc=$?
    kill "$timer" 2>/dev/null || true
    wait "$timer" 2>/dev/null || true

    if [[ "$rc" -eq 143 || "$rc" -eq 137 ]]; then
        RUN_BOUNDED_KILLED=1     # authoritative (D-02): we fired, don't infer
        rc=124                   # normalize to the published 124 contract
    fi
    trap - TERM INT
    return "$rc"
}
```

### All four D-07 redirect shapes, verified in one run
```bash
# Source: this session's probe run, verbatim invocation shapes matching the
# real call sites (agy_bridge.sh:144, :231, :342; gemini_shim.sh:89, :263, :317)

# Shape 1 -- command substitution (models fetch)
raw=$(run_bounded 5 2 -- bash -c 'echo hello-from-child')

# Shape 2 -- direct file redirects (delegation call)
run_bounded 3 2 -- /path/to/cmd > "$STDOUT_FILE" 2> "$STDERR_FILE"

# Shape 3 -- cd-subshell (agy_bridge.sh:342's exact form)
( cd "$WORK_DIR" && run_bounded 5 2 -- bash -c 'pwd' )

# Shape 4 -- stdin pipe (the stdin `cat` sites)
printf 'piped stdin content\n' | run_bounded 5 2 -- cat > "$PROMPT_FILE"

# Existing EXIT_CODE idiom, unchanged and preserved:
START=$SECONDS; EXIT_CODE=0; set +e
run_bounded "$TIMEOUT" 5 -- "$AGY_BIN" "${AGY_FLAGS[@]}" > "$STDOUT_FILE" 2> "$STDERR_FILE" < /dev/null
EXIT_CODE=$?; set -e
DURATION=$(( SECONDS - START ))
```
[VERIFIED: all four shapes plus the `EXIT_CODE` idiom executed successfully this session in `run_bounded_proto2.sh`; shape 2's SIGTERM-ignoring-child-plus-grandchild variant confirmed `rc=124`, `killed_flag=1`, both processes dead, clean stdout — see confidence note above.]

## State of the Art

| Old Approach (current shipped code) | New Approach (this phase) | When Changed | Impact |
|--------------------------------------|----------------------------|---------------|--------|
| `agy_bridge.sh` hard-exits 2 when no `timeout`/`gtimeout` on PATH (`agy_bridge.sh:15-21`) | Never fatal on a missing `timeout` binary; one stderr warning, then bounded via the watchdog | This phase (D-01, D-03) | Bridge now succeeds on hosts (e.g. bare macOS without `brew install coreutils`) where it previously refused to run at all. |
| `gemini_shim.sh` silently sets `TIMEOUT_BIN=""` and runs every subsequent call **unbounded** (`gemini_shim.sh:24-29`, all four if/else pairs) | Same watchdog-bounded behavior as the bridge — the box-wide-blast-radius shim can no longer hang forever | This phase (D-01) | Closes the exact defect `delegate-agy-cy5` names; also closes R11's "empty-`TIMEOUT_BIN` fallbacks are unbounded" gap noted in REQUIREMENTS.md. |
| Six separate `if [[ -n "$TIMEOUT_BIN" ]] … else …` branch pairs across two files | One `run_bounded` helper, duplicated verbatim (D-08), called six times | This phase (D-04) | Net code deletion; single point of correctness for the bound contract instead of six independently-maintained branches. |

**Deprecated/outdated:** The "unbounded fallback" framing in PROJECT.md's current Out of Scope row ("Removing the unbounded fallback when no `timeout` binary exists") is factually superseded the moment D-01 lands — the fallback is not removed, it becomes bounded by a different mechanism. D-18 requires PROJECT.md to restate this row rather than leave it describing pre-Phase-1 behavior.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | agy ignores SIGTERM (the stated rationale for every `-k` escalation, `agy_bridge.sh:340-341` and README:270) | Inherited premise throughout — not re-verified this phase | **Confirmed unverified per STATE.md**: "Not established: whether agy ignores SIGTERM — every probe call returned on its own, so no bound fired." If agy in fact *does* honor SIGTERM promptly, the `-k` escalation is dead code that never fires in practice (harmless) but the D-14/D-14a test's fake-agy behavior (ignores SIGTERM, forks a child) would still be the correct *worst-case* test regardless — this assumption affects production behavior expectations, not test validity. |
| A2 | Non-interactive bash under `set -m` prints no job-control notices on **all** bash builds the shipped scripts will run under (not just this session's bash 5.3.15/Linux) | Common Pitfall 3, D-06c | If a target platform's bash (notably macOS's shipped **bash 3.2**, frozen pre-GPLv3, and known to differ from modern bash in several job-control edge cases) *does* print notices, an un-suppressed watchdog would leak `[1]+ Terminated` lines to the script's stderr — cosmetic noise, not a correctness bug, but could break a test asserting exact stderr content. |
| A3 | Pre-4.4 bash's trap-delayed-until-`wait`-returns behavior is accurately characterized (Pitfall 4) | Common Pitfall 4 | Low risk: project's own floor is bash 4+ (PROJECT.md Constraints) and this session's bash 5.3.15 shows no such delay; only matters if the floor is ever lowered. |
| A4 | `/proc/<pid>/stat` field 5 is the correct, stable PGID field on every Linux the scripts will run under | §Code Examples `_rb_pgid_of` | Standard, decades-stable `man proc` contract; risk is effectively zero but not independently re-verified against `man 5 proc` text this session (relying on well-established general knowledge, not a fresh authoritative-source fetch). |

**If this table is empty:** N/A — see above; all four entries carry real but bounded risk and none blocks planning.

## Open Questions

1. **macOS-specific job-control-notice and PGID-allocation behavior (bash 3.2)**
   - What we know: Linux/bash-5.3.15/no-PTY shows clean, notice-free, correctly-PGID-isolated behavior in every tested shape.
   - What's unclear: whether macOS's shipped `/bin/bash` (3.2.57, the last GPLv2 release, materially older than every other tested config) behaves identically for `set -m` PGID allocation and notice suppression.
   - Recommendation: the plan should not block on macOS verification (no macOS host available in this research session), but the D-06c suppression code should be written defensively (narrow, not blanket) per Pitfall 3's guidance regardless, so it is correct on macOS whether or not notices actually appear there.

2. **Exact self-kill-guard fallback wording and whether `/proc` vs `ps` selection needs to be platform-detected at all, or whether `ps -o pgid=` alone (portable, slightly slower) is an acceptable single implementation**
   - What we know: `/proc` read is faster and narrows the Pitfall-1 race window on Linux; `ps -o pgid=` is the only option on macOS (no procfs).
   - What's unclear: whether the marginal race-window narrowing from a Linux-specific `/proc` fast path is worth the code-path branching, given that Pitfall 1 is irrelevant to real (multi-second) agy calls either way.
   - Recommendation: this is explicitly CONTEXT.md's "Exact helper internals" — Claude's Discretion. The planner should pick one implementation (this research recommends the `/proc`-with-`ps`-fallback shown in §Code Examples for correctness-on-both-platforms) and not treat it as an open design question requiring further research.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| GNU coreutils `timeout` | Primary bounding path (D-05) | ✓ | 9.11 [VERIFIED: `timeout --version`] | bash watchdog (this phase's entire subject) |
| bash job control (`set -m`) | Fallback bounding path (D-06) | ✓ | bash 5.3.15 [VERIFIED: `bash --version`] | none needed — it is itself the fallback |
| `/proc` filesystem | Fast, no-fork PGID lookup in `_rb_pgid_of` | ✓ (Linux) | n/a | `ps -o pgid= -p <pid>` (required on macOS, which has no procfs by default) |

**Missing dependencies with no fallback:** none — this phase's entire purpose is ensuring there is always a fallback.
**Missing dependencies with fallback:** `timeout`/`gtimeout` itself, when absent, falls back to the bash watchdog per D-01/D-05/D-06 — this is the phase's core deliverable, not a gap.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Hand-rolled bash harness, no external framework [VERIFIED: `tests/run-tests.sh:1-2` header comment: "Regression tests for scripts/agy_bridge.sh and scripts/gemini_shim.sh against a fake `agy` CLI stub (tests/fake-agy.sh)."; `tests/run-tests.sh:26`: `set -u` — no `set -e`, confirmed by reading the file top this session] |
| Config file | none — `tests/run-tests.sh` is both the config and the runner |
| Quick run command | `bash tests/run-tests.sh` (whole suite; no sub-selection mechanism exists) |
| Full suite command | `bash tests/run-tests.sh` (same — ~89 cases, all in one file per D-16) |

**Harness conventions confirmed this session** [VERIFIED: `tests/run-tests.sh:37-62`]:
- Sandbox: `SANDBOX="$(mktemp -d -t agy-tests.XXXXXX)"`; `mkdir -p "$SANDBOX/bin" "$SANDBOX/home"`; `cp "$HERE/fake-agy.sh" "$SANDBOX/bin/agy"`.
- PATH: `export PATH="$SANDBOX/bin:$PATH"` — **prepends**, does not replace; the real system `timeout`/`gtimeout` (if any) stays reachable. **D-15's sanitized-PATH-only test needs a PATH construction that does NOT inherit the outer PATH** — e.g. `PATH="$SANDBOX/bin:/usr/bin:/bin"` built from an explicit minimal allowlist that excludes wherever `timeout`/`gtimeout` actually live, or (more robustly, avoiding a hardcoded assumption about where those binaries are installed) a dedicated second sandbox dir containing only `agy` plus symlinks to the minimal external tools `run_bounded`'s watchdog path itself needs (`sleep`, `kill`, `awk` — no `timeout`/`gtimeout`).
- Result reporting: `ok()`/`bad()` increment `PASS`/`FAIL` module-level counters; final line `echo "PASS=$PASS FAIL=$FAIL"; if [[ "$FAIL" -eq 0 ]]; then exit 0; else exit 1; fi` [VERIFIED: `tests/run-tests.sh:1606-1611`].
- Capture helper: `_run OUTVAR RCVAR cmd...` (defined at `tests/run-tests.sh:63` onward, merges stdout+stderr).
- **No `set -e`** in the harness itself — a test's own failing command does not abort the suite; only the individual test's `if`/`ok`/`bad` logic determines pass/fail. This matters for how a new watchdog test should be written: unlike `run_bounded` itself (which needs the Pitfall-2 guard because it runs under the *scripts'* `set -euo pipefail`), the *test* driving it runs under the harness's own `set -u`-only discipline and can call fallible commands directly.

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| R11 (static) | Every `"$AGY_BIN"` occurrence in both scripts is a `run_bounded … --` argument, zero exceptions (D-12, D-13) | lint/static-scan, `bash -n` + `grep`/`awk`, following the `I18` precedent | new case in `tests/run-tests.sh`, e.g. `SH-STATIC-01`; pattern: `bash -n "$BRIDGE"`/`bash -n "$SHIM"` then `grep -n '"\$AGY_BIN"' "$f"` and assert every matched line also matches a `run_bounded\b.*--` pattern on the same logical statement, excluding comment-only lines (`^\s*#`) and the helper's own `# --- BEGIN/END run_bounded ---` block | ✅ (append to existing file) |
| R11 (runtime, coreutils present) | Delegation against a SIGTERM-ignoring fake agy that forks a SIGTERM-ignoring child dies — both processes — within `secs + kill_after` | integration, drives `FAKE_AGY_PRINT_HANG`-style env var (extended per D-14 to also fork) | `bash "$BRIDGE" ...` / `bash "$SHIM" ...` with `FAKE_AGY_PRINT_HANG=1` plus a new `FAKE_AGY_FORK_CHILD=1`-style var, PID files recorded, `ps -p` assertions after the bound | ❌ Wave 0 — `tests/fake-agy.sh` needs a new forking mode |
| R11 (runtime, watchdog fallback) | Same as above, but with `timeout`/`gtimeout` removed from PATH (D-15's sanitized PATH) | integration | same fake-agy invocation, PATH constructed per the D-15 gap noted above | ❌ Wave 0 — new sanitized-PATH construction needed alongside the existing sandbox |
| R11 (runtime, PTY vs no-PTY) | The above runtime assertion holds identically with and without a controlling terminal (D-14a) | integration, PTY allocation | with-PTY variant needs `script -qc` or similar PTY-allocation wrapper around the `bash "$SHIM"`/`bash "$BRIDGE"` invocation; no-PTY variant is the harness's existing default (it already runs non-interactively) | ❌ Wave 0 — PTY-allocation wrapper for the with-PTY half does not exist yet |
| R11 (D-08 duplication) | The two scripts' `run_bounded` blocks (between the `BEGIN`/`END` markers) are byte-identical | unit, text diff | `diff <(sed -n '/# --- BEGIN run_bounded ---/,/# --- END run_bounded ---/p' "$BRIDGE") <(sed -n '/# --- BEGIN run_bounded ---/,/# --- END run_bounded ---/p' "$SHIM")` | ❌ Wave 0 — new case |
| R11 (D-09/D-10 warning text) | Both scripts emit the exact literal warning string, once, when `TIMEOUT_BIN` is empty | unit, string match | grep the literal warning text from D-10 against both scripts' source **and** against captured stderr of a PATH-sanitized run | ❌ Wave 0 — new case; also covers D-17's README verbatim-quote obligation by using the same literal in both places |

### Sampling Rate
- **Per task commit:** `bash tests/run-tests.sh` (only one command exists; the suite currently runs in well under a minute per the `SH13` precedent's own internal `timeout 30` guard).
- **Per wave merge:** same command — no separate "full suite" distinct from "quick run" exists in this harness.
- **Phase gate:** `PASS=$PASS FAIL=$FAIL` line must show `FAIL=0` before `/gsd-verify-work`.

### Wave 0 Gaps
- [ ] `tests/fake-agy.sh` — extend with a forking, SIGTERM-ignoring mode (D-14): trap TERM, write own PID to a file, fork a child that also traps TERM and writes its own PID to a second file, both sleep past any plausible bound.
- [ ] `tests/run-tests.sh` — new sanitized-PATH sandbox construction that does NOT inherit the outer PATH's `timeout`/`gtimeout` (D-15 gap identified above).
- [ ] `tests/run-tests.sh` — PTY-allocation wrapper (e.g. via `script`) for the with-PTY half of D-14a; the no-PTY half is already covered by the harness's existing non-interactive execution.
- [ ] `tests/run-tests.sh` — new static-scan case (`bash -n` + `grep`/`awk`) for D-12/D-13, modeled on the existing `I18` case (`tests/run-tests.sh:1591-1604`).
- [ ] `tests/run-tests.sh` — new byte-identity case for D-08's duplicated `run_bounded` blocks.

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Out of scope — this phase touches process bounding only, not agy's OAuth flow. |
| V3 Session Management | no | N/A — no sessions in this phase's surface. |
| V4 Access Control | no | N/A. |
| V5 Input Validation | yes | `secs`/`kill_after` arguments to `run_bounded` should be validated as positive integers before use in `sleep`/`kill` (mirrors the existing `AGY_MODELS_TIMEOUT`/`GEMINI_SHIM_TIMEOUT` `^[1-9][0-9]*$` validation already present in both scripts, e.g. README:271's documented correct-not-reject pattern for `AGY_MODELS_TIMEOUT=0`). This phase does not introduce new *external* input surfaces (the bound values remain the existing env-var-derived constants), so no new validation is strictly required beyond what already exists — but `run_bounded`'s own arguments should not silently accept non-numeric input, since a malformed `secs` fed to `sleep` would fail in an unobvious way inside the timer subshell. |
| V6 Cryptography | no | N/A — no cryptographic material in this phase's surface. |

### Known Threat Patterns for this stack (bash process-group signaling)

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Self-kill via `kill -- -$pgid` when job-control isolation silently failed (a script signaling its own process group, terminating itself and any sibling job) | Denial of Service (self-inflicted) | D-06a's self-kill guard: compare `child_pgid` against `self_pgid` before ever calling `kill -- -$pgid`; fall back to direct-PID kill on any ambiguity. This is the phase's central, already-locked mitigation — see §Code Examples. |
| Orphaned process group surviving after the parent shell exits (e.g. Ctrl-C on the shim without signal relay) | Denial of Service (resource exhaustion via an unreaped background agy process burning CPU/quota indefinitely) | D-06b's INT/TERM trap-and-relay to the child group, mirroring GNU `timeout`'s own forwarding contract. |
| A quoting/escaping defect in `run_bounded`'s `"$@"` handling allowing an argument boundary to be lost (e.g. a prompt or path containing spaces being mis-split before reaching `agy`) | Tampering (argument injection) | `run_bounded` must use `"$@"` (never `$*` or unquoted expansion) throughout, exactly as every existing call site already does (`"${AGY_FLAGS[@]}"`, `"${AGY_ARGS[@]}"`) — this is a straightforward carry-forward of the existing pattern, not a new control. |

## Sources

### Primary (HIGH confidence)
- `timeout --help` and `timeout --version`, run on this host this session [VERIFIED: coreutils 9.11 — exact flag set (`-f/--foreground`, `-k/--kill-after`, `-p/--preserve-status`, `-s/--signal`, `-v/--verbose`) and exit-status contract (124/125/126/127/137/passthrough) quoted directly from local `--help` output]
- `bash --version`, run on this host this session [VERIFIED: GNU bash 5.3.15(1)-release]
- `/home/dd/Gemini/delegate-agy/.worktrees/agy-1.6.2/scripts/agy_bridge.sh` and `scripts/gemini_shim.sh`, read in full this session on the `fix/agy-bridge-resilience` worktree (never `master`, per CONTEXT.md's canonical-refs instruction) — all line-numbered quotes in §User Constraints and this document cross-checked via `grep -n` this session
- `/home/dd/Gemini/delegate-agy/.worktrees/agy-1.6.2/tests/run-tests.sh` and `tests/fake-agy.sh`, read this session — harness conventions, `SH13` and `I18` precedents, full `fake-agy.sh` env-var contract
- `/home/dd/Gemini/delegate-agy/.worktrees/agy-1.6.2/README.md`, lines 40-60 and 228-272 read this session — exact troubleshooting-row and env-var-table text
- This session's own empirical probes (`run_bounded_proto2.sh`, `probe_pgid2.sh`, and predecessors) — PGID allocation, descendant reaping, redirect-transparency, and the two documented pitfalls, all executed and their output captured this session

### Secondary (MEDIUM confidence)
- General bash job-control semantics (SIGCHLD-triggered asynchronous reaping of background jobs, `$BASHPID` vs `$$` subshell behavior) — consistent with this session's empirical results but not independently cross-checked against a second authoritative source (e.g. `man bash` was not re-fetched this session; relying on the empirical reproduction plus well-established training knowledge)

### Tertiary (LOW confidence)
- macOS bash 3.2 job-control-notice and PGID-allocation behavior — `[ASSUMED]`, no macOS host available this session, flagged in Assumptions Log A2 and Open Question 1
- Pre-4.4 bash trap-during-`wait` delay — `[ASSUMED]`, flagged in Assumptions Log A3, low actionability given the project's bash 4+ floor

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; existing coreutils/bash versions directly confirmed on-host this session.
- Architecture: HIGH — the `run_bounded` design is fully specified by CONTEXT.md's locked decisions; this research's contribution (empirical PGID/signal/redirect-transparency verification plus a working prototype) is directly reproducible and was reproduced this session.
- Pitfalls: HIGH for Pitfalls 1-3 (all empirically reproduced this session with captured output); MEDIUM for Pitfall 4 (documented historical bash behavior, not reproducible on this session's bash 5.3.15 environment, but consistent with the project's stated bash 4+ floor).

**Research date:** 2026-08-19
**Valid until:** 30 days (stable domain — bash job control and coreutils `timeout` semantics do not change on a fast cadence; re-verify only if the project's bash-floor or coreutils-preference constraints change, or if a macOS host becomes available to close Open Question 1).
