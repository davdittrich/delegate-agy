# Phase 1: The missing-`timeout` decision - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-19
**Phase:** 1-The missing-`timeout` decision
**Areas discussed:** The policy itself, Uniform vs per-call-site, How degradation announces itself, Shape of the invariant test

---

## The policy itself

### Q1 — On a host with no `timeout`/`gtimeout`, what is the decided behavior?

| Option | Description | Selected |
|--------|-------------|----------|
| Bash watchdog fallback | No unbounded path anywhere; both scripts bound agy with a native bash watchdog when `TIMEOUT_BIN` is empty. Divergence disappears rather than being documented. | ✓ |
| Refuse only the delegation call | Ticket option (c). Shim keeps working for `--version`/`--help`/model resolution; the delegation call errors instead of running unbounded. | |
| Hard-fail both (exit 2) | Ticket option (a). Maximum consistency, but `gemini` stops working box-wide on any host without coreutils. | |
| Keep divergence, document it | PROJECT.md's implied 4th. Zero behavior change; satisfies criterion 2 only by recording that an unbounded agy is acceptable. | |

**User's choice:** Bash watchdog fallback
**Notes:** Ticket option (b) — degrade in both, warn loudly — was named in the preamble as available via "Other" and not taken; a warning does not prevent the hang. The watchdog option is not one of the three the ticket names: it rejects the premise that a missing binary forces a tradeoff.

### Q2 — When the bash watchdog is what killed agy, what exit code does the caller see?

| Option | Description | Selected |
|--------|-------------|----------|
| 124 + stderr marker | One contract regardless of mechanism; stderr suffix names the fallback. Requires distinguishing own kill from external kill via elapsed-vs-bound. | ✓ |
| Plain 124, no marker | Fully transparent, smallest surface; no signal that the fallback path is in play. | |
| Distinct code for the fallback | Maximally explicit; adds a 6th code to a contract Phase 3 is about to freeze at five. | |

**User's choice:** 124 + stderr marker

### Q3 — With a watchdog available, what happens to the bridge's `exit 2`?

| Option | Description | Selected |
|--------|-------------|----------|
| Drop the fatal, warn once | The fatal no longer has a reason; bridge warns and proceeds. Removes the last source of divergence. | ✓ |
| Drop the fatal, stay silent | Cleanest output; a host silently missing coreutils never tells anyone. | |
| Keep exit 2 in the bridge | Preserves the existing documented behavior and PROJECT.md's "shim degrades, bridge fails loud" line; divergence survives. | |

**User's choice:** Drop the fatal, warn once
**Notes:** Consequence accepted — exit 2 loses a documented cause and README:233 must be rewritten.

### Q4 — Does the watchdog replicate coreutils' two-stage `-k` ladder?

| Option | Description | Selected |
|--------|-------------|----------|
| Mirror the ladder | SIGTERM at the bound, SIGKILL k seconds later; one set of numbers across both mechanisms. | |
| Straight SIGKILL at the bound | agy ignores SIGTERM so the TERM stage buys nothing; shortest watchdog, but two different boundaries per host. | |
| You decide | Planner's call, with the outcome stated in CONTEXT.md. | ✓ |

**User's choice:** You decide
**Notes:** Recorded as Claude discretion with a stated default of mirroring, and the constraint that the timing boundary be a single documented number per mechanism.

---

## Uniform vs per-call-site

### Q1 — Which call sites does the bound cover, and how is it structured?

| Option | Description | Selected |
|--------|-------------|----------|
| All sites, one helper | `run_bounded()` over all 5 agy sites plus the stdin read; the 6 if/else pairs collapse into one function — net deletion. | ✓ |
| All agy sites, stdin excluded | Stdin `cat` keeps its existing shape; one unbounded path survives and the invariant needs a carve-out. | |
| Delegation call only | Smallest diff; four paths stay unbounded and each fallback branch must be justified. | |

**User's choice:** All sites, one helper

### Q2 — When coreutils `timeout` IS present, does the helper still use it?

| Option | Description | Selected |
|--------|-------------|----------|
| Prefer coreutils, watchdog as fallback | Keeps the battle-tested, process-group-killing path primary. | ✓ |
| Always watchdog, delete TIMEOUT_BIN | Maximum deletion; replaces a proven binary with hand-rolled bash on every host. | |
| You decide | Planner picks, constrained to killing descendants and proving it. | |

**User's choice:** Prefer coreutils, watchdog as fallback

### Q3 — How is drift prevented between the two duplicated helpers?

| Option | Description | Selected |
|--------|-------------|----------|
| Marker comments + identity test | Extract both blocks, assert byte-identical; same shape `delegate-agy-8ph` demands for the cache writers. | ✓ |
| Generate one from the other | Impossible to drift; introduces a generation step to a project with none. | |
| Accept the risk | Zero cost now; exactly the one-sided-fix pattern the project already had to forbid. | |

**User's choice:** Marker comments + identity test

### Q4 — On a host with neither coreutils nor `setsid`, how do descendants die?

| Option | Description | Selected |
|--------|-------------|----------|
| bash job control + kill the group | `set -m` gives the child its own process group, `kill -- -$pgid` reaps everything it forked; no external binary. | ✓ |
| Direct child only, document the gap | Simplest fallback; leaves orphans on exactly the hosts the fallback exists for. | |
| Require `setsid`, else direct child | Three mechanisms, three guarantees; the weakest still lands on stock macOS. | |

**User's choice:** bash job control + kill the group

### Q5 — What calling convention does `run_bounded` take?

| Option | Description | Selected |
|--------|-------------|----------|
| Redirect-transparent, callers keep redirects | `run_bounded <secs> <kill_after> -- cmd…` runs in the caller's stdio; smallest diff at each site. | ✓ |
| Helper owns stdio, returns via files | Uniform internals; rewrites all 6 sites and adds temp-file handling where none is needed. | |
| You decide | Planner picks, constrained to preserving capture semantics. | |

**User's choice:** Redirect-transparent, callers keep redirects
**Notes:** Constraint carried forward — the watchdog's marker must never land inside captured output.

---

## How degradation announces itself

### Q1 — Does the shim emit the same startup warning as the bridge?

| Option | Description | Selected |
|--------|-------------|----------|
| Both, one stderr line per invocation | Same rule both entry points; stderr does not break Octopus or Metaswarm, which read stdout / the JSON envelope. | ✓ |
| Bridge warns, shim only on fire | Zero added noise for PATH callers; reintroduces a narrower divergence needing a stated reason. | |
| Both, once per host per day | Seen but not spammed; new on-disk state that can be unwritable, and vanishes when someone greps for it. | |

**User's choice:** Both, one stderr line per invocation
**Notes:** Accepted cost — on a coreutils-less host every interactive `gemini` call gains a line.

### Q2 — What does the startup warning say, and where does the remedy live?

| Option | Description | Selected |
|--------|-------------|----------|
| Mechanism + remedy in one line | Inherits the remedy the removed `exit 2` message carried; both strings become pinned literals quoted verbatim in README. | ✓ |
| Mechanism only, remedy in README | Terser; the remedy is one lookup away at the moment it is needed. | |
| You decide | Planner writes both strings under the pinned-literal constraint. | |

**User's choice:** Mechanism + remedy in one line

### Q3 — In JSON output mode, does the marker also appear in the envelope?

| Option | Description | Selected |
|--------|-------------|----------|
| stderr only | Envelope shape stays exactly as Phase 3 is about to freeze it; nothing downstream learns a new field. | ✓ |
| Marker in the envelope too | Machine callers can tell the mechanism without scraping stderr; widens the envelope in the release that freezes it. | |
| You decide | Planner picks, constrained to updating Phase 3's payload-shape test in lockstep. | |

**User's choice:** stderr only

---

## Shape of the invariant test

### Q1 — What enforces criterion 4?

| Option | Description | Selected |
|--------|-------------|----------|
| Both static and runtime | Static catches a call site on a path no test exercises (criterion 4); runtime proves the mechanism works (criterion 2). Neither alone satisfies both. | ✓ |
| Static scan only | Cheapest; proves the text, not the behavior. | |
| Runtime only | Proves the mechanism; only covers paths a test reaches — how the count went 2→4→5 unnoticed. | |

**User's choice:** Both

### Q2 — Does the static scan allow exceptions?

| Option | Description | Selected |
|--------|-------------|----------|
| Zero exceptions | The helper never names `"$AGY_BIN"` itself, so no allowlist is needed; a future exception must change the rule in the open. | ✓ |
| Marker-comment escape hatch | Gives a legitimate future case a path; an escape hatch is how the unbounded call survived last time. | |
| You decide | Planner picks under a non-empty-reason constraint. | |

**User's choice:** Zero exceptions

### Q3 — What must the runtime test's fake agy do?

| Option | Description | Selected |
|--------|-------------|----------|
| Ignore SIGTERM and fork a child | Only assertion that distinguishes a process-group kill from a direct-child kill; without it the fallback passes while leaving orphans. | ✓ |
| Ignore SIGTERM only | Reuses the existing fake; says nothing about descendants, leaving the reason for bash job control untested. | |
| You decide | Planner picks, constrained to failing if only the direct child dies. | |

**User's choice:** Ignore SIGTERM and fork a child

### Q4 — How does the suite reach the fallback on a machine that has coreutils?

| Option | Description | Selected |
|--------|-------------|----------|
| Sanitized PATH per test | Scratch dir with only the fake agy; the fallback is genuinely exercised, and the real dependency set gets documented. | ✓ |
| Override variable in the scripts | Trivial; ships a test hook in scripts that shadow `gemini` box-wide, and proves the branch rather than the condition. | |
| You decide | Planner picks, constrained to no test-only switch in shipped scripts. | |

**User's choice:** Sanitized PATH per test

### Q5 — Where does the installer's up-to-600s live-verify go?

| Option | Description | Selected |
|--------|-------------|----------|
| Ticket it, route to Phase 4 | Files the blocker now; Phase 4 owns the installer surface. Phase 1's scan stays on the two files criterion 4 names. | ✓ |
| Widen Phase 1's scan to install.sh | Catches the whole class at once; expands a phase whose criterion names exactly two files. | |
| Ticket it, leave routing open | An unrouted blocker against a release gate requiring zero open tickets. | |

**User's choice:** Ticket it, route to Phase 4
**Notes:** Surfaced during the discussion, not from the roadmap — `scripts/install.sh:360-368` invokes the shim and bridge with no installer-side bound. Filed as `delegate-agy-lkg` (P1) during the session.

### Q6 — Where do the new tests live?

| Option | Description | Selected |
|--------|-------------|----------|
| Inside tests/run-tests.sh | One entry point, one command, nothing extra for Phase 6's gate to remember. | ✓ |
| Separate tests/invariants.sh | Keeps lint-shaped assertions distinguishable; a second file the release gate must remember. | |
| You decide | Planner picks, constrained to running under the same command as the gate. | |

**User's choice:** Inside tests/run-tests.sh

---

## Claude's Discretion

- **Ladder shape** — mirror coreutils' TERM-then-KILL ladder, or straight SIGKILL. Default: mirror. Constraint: one documented boundary number per mechanism.
- **Helper internals** — signature beyond `run_bounded <secs> <kill_after> -- cmd`, PID/trap bookkeeping, and how `set -m` is scoped and restored.
- **Test case ids and naming** — subject to keeping the lint-shaped scan legible among the behavioral cases.

## Deferred Ideas

- `delegate-agy-lkg` (P1) — installer live-verify can block ~600s on a hung agy. Routed to Phase 4.
- Widening the invariant to "no unbounded agy reachable from any shipped script" — declined for Phase 1, worth revisiting in Phase 4 once `delegate-agy-lkg` is fixed.
