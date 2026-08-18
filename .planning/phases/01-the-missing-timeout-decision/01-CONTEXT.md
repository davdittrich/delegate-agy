# Phase 1: The missing-`timeout` decision - Context

**Gathered:** 2026-08-19
**Status:** Ready for planning

<domain>
## Phase Boundary

On a host with no `timeout`/`gtimeout` binary, both entry points (`scripts/agy_bridge.sh`, `scripts/gemini_shim.sh`) behave one decided way; the decision is recorded in PROJECT.md's Key Decisions table with its rationale, stated in README's environment-variable section, and locked by a test that fails when a future `"$AGY_BIN"` call site is added unbounded.

This phase is not done when code changes. It is done when the choice is written down, enforced, and documented.

**In scope:** the `TIMEOUT_BIN` probe and every bounded-invocation site in `scripts/agy_bridge.sh` and `scripts/gemini_shim.sh`; the README rows describing those bounds; the PROJECT.md decision rows the outcome supersedes; the tests that pin the invariant.

**Out of scope:** `scripts/install.sh` and `scripts/uninstall.sh` (Phase 4's surface — see Deferred); the exit-code contract's five codes as a whole (Phase 3, though this phase hands it two changes it must absorb); the shim's failure-mode table (Phase 5).

</domain>

<decisions>
## Implementation Decisions

### Policy — what happens when no `timeout` binary exists

- **D-01:** Neither entry point ever calls agy unbounded. When `TIMEOUT_BIN` is empty, the call is bounded by a native bash watchdog (background child + timed `kill`) instead of running unbounded. The bridge-vs-shim divergence that `delegate-agy-cy5` filed is **dissolved, not documented** — both entry points get the same behavior, so criterion 1's recorded decision is "always bounded", not a choice between (a) hard-fail, (b) degrade-with-warning, or (c) refuse-delegation-only. — **Reversibility:** costly — undoing it means reintroducing an unbounded path in a script that shadows `gemini` for every PATH caller, and re-opening `delegate-agy-cy5` against a release built to eliminate unbounded calls.
- **D-02:** A call killed by the bash watchdog reports **exit 124** — identical to the coreutils path — with a stderr marker naming the fallback mechanism. One contract regardless of which mechanism bounded the call, so README's troubleshooting table and any caller matching on 124 keep working. The watchdog reports **authoritatively, not by inference**: it performed the kill, so it sets a flag and does not re-derive the fact from elapsed time. Duration-based discrimination stays confined to its existing job — telling an external `kill -9` from the bridge's own escalation on the coreutils path — because inferring "I timed out" from `DURATION >= bound` misreports an orchestrator-level cancellation that lands at the bound (Octopus enforcing its own timeout, or a normal exit registering at the boundary) as an internal bridge timeout. — **Reversibility:** one-way — 124 is a published exit code that Octopus, Metaswarm, and README's troubleshooting table already key on; changing what it means later breaks callers that cannot be enumerated. Phase 3 freezes this contract in the same release.
- **D-03:** The bridge's `exit 2` on a missing `timeout` binary (`scripts/agy_bridge.sh:15-21`) is **removed**. With the watchdog in place the fatal has no remaining justification. The bridge emits one stderr warning and proceeds. Exit 2 loses this cause — Phase 3 must not list "timeout/gtimeout not found" among its reachable-2 provocations — and README:233's `ERROR: timeout/gtimeout not found in PATH` troubleshooting row must be rewritten to the new warning. — **Reversibility:** costly — restoring the fatal means the bridge again fails on hosts where it now succeeds, and README plus Phase 3's exit-code tests move with it.

### Coverage — which sites are bounded and how

- **D-04:** One helper, `run_bounded <secs> <kill_after> -- cmd args…`, covers **all six** currently-unbounded-capable sites: the 5 `"$AGY_BIN"` invocations (`agy_bridge.sh:143` models, `agy_bridge.sh:342` delegation; `gemini_shim.sh:89` models, `gemini_shim.sh:190` `--version`, `gemini_shim.sh:317` delegation) plus the stdin `cat` read (`agy_bridge.sh:231`, `gemini_shim.sh:263`). The six existing `if [[ -n "$TIMEOUT_BIN" ]] … else …` branch pairs collapse into the one function — this is net deletion, not net addition.
- **D-05:** The helper **prefers coreutils `timeout -k`** when available and uses the bash watchdog only when it is not. Rationale: GNU `timeout` runs its child in a separate process group and signals the group, so it reaps agy's descendants; a naive watchdog kills only the direct child. Keep the proven mechanism primary; the fallback serves the minority of hosts, not all of them.
- **D-06:** The watchdog achieves the same descendant guarantee **without any external binary**: `set -m` (scoped to the helper and restored) puts the child in its own process group, then `kill -- -$pgid`. This works on stock macOS, which has neither coreutils nor `setsid`. Four constraints ride on it, each from the adversarial review and each a way the naive version fails:
  - **D-06a — self-kill guard.** Read the child's actual PGID after starting it and refuse to signal it if it equals the script's own process group. If bash did not allocate a distinct PGID — plausible inside the `$(…)` command substitution D-07 requires, and in a PTY-less CI runner — then `kill -- -$pgid` either errors harmlessly or kills the shim itself. The helper must detect that case, fall back to killing the direct child, and say so on stderr rather than silently doing either. **Whether bash allocates a distinct PGID under `set -m` inside command substitution and without a controlling terminal must be verified empirically, not assumed** — it decides whether the fallback is a rare edge or the common path.
  - **D-06b — signal forwarding.** GNU `timeout` proxies SIGINT/SIGTERM through to its isolated child group; a bare watchdog does not. Without a forwarding trap, `Ctrl-C` on a delegating `gemini` kills the shim while agy — now in a process group detached from the terminal — survives as an orphan burning CPU. The helper traps INT and TERM and relays them to the child group before exiting.
  - **D-06c — job-control notices without swallowing stderr.** `set -m` makes bash emit `[1] 12345` / `[1]+ Terminated` notices. Suppressing them with a blanket `2>/dev/null` around the backgrounding construct would also discard agy's own immediate fatal startup errors (`permission denied`, `exec format error`) — a silent-failure mode worse than the noise. Suppress the shell's notices specifically (restore `set +m` promptly, `disown`, or redirect only the construct's own diagnostics); never redirect the child's stderr away from where D-07 puts it.
  - **D-06d — no SIGTTIN concern.** The review raised a terminal-stop risk for the stdin `cat` once it runs in a background process group. It does not apply: both stdin reads are guarded by `elif [[ ! -t 0 ]]` (`agy_bridge.sh:230`, `gemini_shim.sh:261`), so `cat` never reads a TTY on that path — and the bridge already runs it under GNU `timeout`, which likewise puts the child in its own process group, so the shipped code would already exhibit the freeze if it were reachable. Recorded here so it is not re-litigated during planning.
- **D-07:** The helper is **redirect-transparent** — it runs the command in the caller's stdio, so `raw=$(run_bounded 20 3 -- "$AGY_BIN" models)` and `run_bounded 600 5 -- "$AGY_BIN" … >"$STDOUT_FILE" 2>"$STDERR_FILE"` both work with the redirects staying where they are today, including the `cd`-subshell form at `agy_bridge.sh:342`. No call site may lose its current capture semantics, and the watchdog's own marker must never land inside captured output — it goes to the script's own stderr.
- **D-08:** The two scripts are standalone by design (nothing is sourced; `grep '^source'` returns nothing), so the helper is **duplicated verbatim** in both. Drift is prevented by `# --- BEGIN run_bounded ---` / `# --- END run_bounded ---` markers plus a test asserting the two extracted blocks are byte-identical. This is the same one-sided-fix enforcement `delegate-agy-8ph` already demands for the two cache writers. — **Reversibility:** reversible — the markers and the identity test are local; extracting to a shared file later is a contained change, though it would cost the shim its standalone property.

### Announcement — how the degraded mechanism surfaces

- **D-09:** **Both** entry points emit the warning, once per script run, on stderr. "Once per script run" means **emitted at the `TIMEOUT_BIN` probe site, not inside `run_bounded`** — a bridge invocation calls the helper three times (models, stdin, delegation), so a warning living in the helper would print three times per run. The helper stays hermetic and silent about mechanism selection; the probe owns the announcement. The shim is where the box-wide risk lives, so silencing it there is backwards. stderr does not break Octopus or Metaswarm — both read stdout / the JSON envelope. Accepted cost: on a coreutils-less host, every `gemini` call in an interactive shell gains a line.
- **D-10:** The warning names **mechanism and remedy in one line**, inheriting the remedy the removed `exit 2` message carried — shape: `WARNING: timeout/gtimeout not found -- bounding agy with the bash watchdog fallback; install coreutils for process-group kill`. Both new strings (this warning and the 124 stderr marker) are fixed literals defined once per script, pinned by a test, and quoted **verbatim** in README — the same rule Phase 3 criterion 4 sets for exit-code messages.
- **D-11:** The JSON envelope is **untouched**. The mechanism detail lives on stderr only; no new key enters the error payload. Phase 3 criterion 5 pins the failure payload's shape precisely so it can never become success-shaped, and this phase must not widen it in the same release that freezes it. — **Reversibility:** reversible — adding a key later is additive; the constraint is that Phase 3's payload-shape regression test moves in lockstep if it ever happens.

### Invariant — what enforces criterion 4

- **D-12:** **Both** a static scan and a runtime proof, because neither alone satisfies both criteria. Static: every `"$AGY_BIN"` occurrence in both scripts appears as a `run_bounded … --` argument — this is what makes a call site added later fail the suite even on a path no test exercises, which criterion 4 demands. Runtime: each entry point is driven against a SIGTERM-ignoring fake and nothing outlives its bound — which criterion 2 demands.
- **D-13:** The static scan has **zero exceptions**. `run_bounded` takes its command as arguments and never names `"$AGY_BIN"` itself, so no allowlist and no escape-hatch comment is needed. A future site that genuinely cannot be bounded must change the rule in the open rather than annotate its way past it — an inline escape hatch is cheaper to add than a decision is to revisit, which is how the unbounded call survived the last time.
- **D-14:** The runtime test's fake agy **ignores SIGTERM and forks a child**, and the assertion is that both the fake and its child are gone after the bound. This is the only assertion that distinguishes a process-group kill from a direct-child kill; without it, D-06 passes while leaving orphans — the exact failure the fallback exists to prevent. The child must be observable reliably (recorded PID file) and the assertion must not go flaky under load.
- **D-14a:** The descendant assertion must also hold **without a controlling terminal**. Job control degrades in a PTY-less runner, so a test that only ever runs under a developer's terminal can pass locally and fail — or worse, pass vacuously — in CI. Run the D-14 assertion both with and without a PTY; if bash cannot allocate a distinct PGID in the PTY-less case, D-06a's fallback is what must be asserted there, not a green tick.
- **D-15:** The fallback branch is reached via a **sanitized PATH** per test — a scratch dir holding only the fake agy, with no `timeout` and no `gtimeout` — so the fallback is genuinely exercised on any dev machine rather than simulated. **No test-only override may exist in the shipped scripts**: they shadow `gemini` box-wide, and a forced-`TIMEOUT_BIN` switch would prove the branch rather than the condition. Whatever other PATH binaries the scripts need get added to the sanitized PATH explicitly, which usefully documents the real dependency set.
- **D-16:** All of it lives **inside `tests/run-tests.sh`**, following the existing `SH13`-style numbered-case convention. One entry point, one command, nothing extra for Phase 6's "both suites pass" gate to remember. The static scan is lint-shaped rather than behavior-shaped, so its case names must make that legible among the ~89 behavioral tests.

### Documentation obligations (part of this phase, not a follow-up)

- **D-17:** README's three `… unbounded regardless of this value` sentences (`README.md:269`, `:270`, `:271`) become false the moment D-01 lands and must be rewritten in the same change. README:233's troubleshooting row is superseded per D-03.
- **D-18:** PROJECT.md's Key Decisions table has two rows this phase resolves: "Shim degrades silently, bridge fails loud" (currently ⚠️ Revisit) is superseded by D-01, and the Out of Scope entry "Removing the unbounded fallback when no `timeout` binary exists" needs restating — the fallback is not removed, it is made bounded, which is a different thing and the open question it names is now closed.

### Claude's Discretion

- **Ladder shape** — whether the watchdog mirrors coreutils' two-stage ladder (SIGTERM at the bound, SIGKILL `kill_after` seconds later) or goes straight to SIGKILL. Default to **mirroring**, so one set of numbers holds across both mechanisms and Phase 3's elapsed-vs-bound discriminator has the same boundary on every host. SIGTERM is ceremony for agy specifically, but the helper's contract should not be agy-specific. Constraint either way: the timing boundary is a single documented number per mechanism.
- **Exact helper internals** — signature beyond `run_bounded <secs> <kill_after> -- cmd`, PID/trap bookkeeping, and how `set -m` is scoped and restored, subject to D-06 and D-07.
- **Test case ids and naming** — subject to D-16's legibility constraint.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase intent and requirements
- `.planning/ROADMAP.md` §"Phase 1: The missing-`timeout` decision" — the four success criteria, and the note explaining why criterion 4 is an invariant rather than a count
- `.planning/REQUIREMENTS.md` — R11 (bounded execution), the requirement this phase closes
- `.planning/PROJECT.md` §Key Decisions, §Out of Scope, §Constraints — the two rows D-18 supersedes, and the core value ("delegation must never break the caller") that decided D-01
- `.planning/STATE.md` §Blockers/Concerns — master's files lag its history; judge state by reading files on `fix/agy-bridge-resilience`

### Code under change (read on the branch, not `master`)
- `scripts/agy_bridge.sh:14-21` — the `TIMEOUT_BIN` probe and the `exit 2` D-03 removes
- `scripts/agy_bridge.sh:143`, `:231`, `:342` — the bridge's bounded sites (models fetch, stdin read, delegation)
- `scripts/gemini_shim.sh:23-29` — the probe that sets `TIMEOUT_BIN=""`, the defect `delegate-agy-cy5` names
- `scripts/gemini_shim.sh:88-91`, `:189-192`, `:262-263`, `:316-322` — the shim's four if/else branch pairs D-04 collapses
- `tests/run-tests.sh` — the ~89-case hand-rolled harness; case `SH13` (line 990) is the closest existing analog for a bound-semantics test
- `tests/fake-agy.sh` — the fake D-14 extends with a forking, SIGTERM-ignoring mode

### Documentation under change
- `README.md:233` — the troubleshooting row D-03 supersedes
- `README.md:269-271` — the three `unbounded regardless of this value` sentences D-17 invalidates
- `README.md:43`, `:54-57` — the coreutils dependency lines, which become a preference rather than a requirement

### Tracker
- `delegate-agy-cy5` (P1, open) — the originating ticket; names candidate designs (a)/(b)/(c) and states the choice itself is open. D-01 selects none of the three and dissolves the question instead; the ticket's resolution note must say so.
- `delegate-agy-lkg` (P1, open) — filed during this discussion, routed to Phase 4 (see Deferred)

### Working tree
- `.worktrees/agy-1.6.2` on `fix/agy-bridge-resilience` at `56be103` — where the 1.6.2 content actually lives; `master` content-reverted it at `a001d0e`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **The existing `if [[ -n "$TIMEOUT_BIN" ]] … else …` pairs** — six of them; they are the thing being replaced, and their bound values (`AGY_MODELS_TIMEOUT` 20 / `-k 3`, `SHIM_TIMEOUT` 600 / `-k 5`, `TIMEOUT` / `-k 5`, `STDIN_TIMEOUT` 30 / no `-k`) are the arguments `run_bounded` takes. No new env knobs are needed.
- **`tests/fake-agy.sh`** — already the suite's agy stand-in; D-14 extends it rather than adding a second fake.
- **`tests/run-tests.sh` case SH13** (line 990) — already asserts a bound-semantics property (`AGY_MODELS_TIMEOUT=0` must not disable the bound), so the conventions for this kind of test exist.
- **The bridge's `-k 5` comment at `agy_bridge.sh:340-341`** — already states why the escalation exists ("agy ignores SIGTERM (observed), so plain `timeout` would send the signal and then block forever"). The watchdog's rationale comment should not restate it in a second voice.

### Established Patterns
- **Standalone scripts, nothing sourced** — the shim must work as a lone drop-in at `~/.local/bin/gemini`. This forces D-08's duplication-plus-identity-test rather than a shared lib.
- **Validate-and-correct, not reject, for optional knobs** — `AGY_MODELS_TIMEOUT=0` is corrected to 20 rather than rejected (README:271, test SH13) because "an optional knob must not stop a `gemini` that shadows the system binary". D-01 and D-03 are the same principle applied to a missing binary.
- **`set -euo pipefail` in both scripts, with `set +e` around the delegation call** to capture `EXIT_CODE` — the helper must preserve this, and must not let `set -m` or the watchdog's own exit disturb the captured code.
- **Elapsed-vs-bound discrimination already exists** — the bridge separates an external `kill -9` from its own `-k` escalation by duration (`DURATION=$(( SECONDS - START ))`, README:231). D-02 reuses that mechanism rather than inventing one.

### Integration Points
- **`TIMEOUT_BIN` probe** (`agy_bridge.sh:15-21`, `gemini_shim.sh:24-29`) — where the helper's mechanism selection lands and where D-09's warning is emitted.
- **Both delegation call sites** feed `EXIT_CODE` into the exit-code reporting Phase 3 owns; D-02's 124 mapping and D-11's untouched-envelope constraint are the seam between the two phases.
- **README's env-var table** (`:269-271`) is the doc surface criterion 3 checks, and Phase 5's shim-vs-bridge contract table will cite the row this phase writes.

</code_context>

<specifics>
## Specific Ideas

- The originating ticket `delegate-agy-cy5` offers three designs and asks which to pick. The answer is **none of the three** — each accepts an unbounded path or a broken caller as the price. Bash can bound a call natively, so the premise that a missing binary forces a tradeoff is what gets rejected. The Key Decisions row should say that plainly rather than record a pick from the menu.
- Roadmap criterion 4's phrasing ("wrapped in `"$TIMEOUT_BIN" -k …` or sits in a `TIMEOUT_BIN`-empty fallback branch that Criterion 1's recorded decision explicitly permits") assumes the fallback branch survives. Under D-01 it does not; the invariant tightens to "every `"$AGY_BIN"` is a `run_bounded` argument" with no permitted-fallback clause. The criterion is satisfied more strictly than written, not reinterpreted more loosely.
- **This record was reviewed adversarially by agy (Gemini Pro) on 2026-08-19 before planning.** Five findings were folded in as D-02's authoritative-reporting rule, D-06a–D-06c, D-09's placement rule, and D-14a. One finding (SIGTTIN freeze on the stdin `cat`) was refuted against the code and recorded as D-06d so it is not raised again. The review also established a fact contradicting STATE.md: **agy answered a real delegation call, returning in well under its bound** — the "agy is presently unresponsive / returns 124 on every call" blocker is stale, which matters most for Phase 7, whose entire premise is that the real binary cannot be asked.
- The count of agy call sites has been stated as two, then four, then five. It is currently five, and the roadmap is explicit that any criterion naming a number goes stale on the next commit. Nothing in this phase's tests may assert a count.

</specifics>

<deferred>
## Deferred Ideas

- **`delegate-agy-lkg` (P1, filed 2026-08-19, routed to Phase 4)** — `scripts/install.sh:360-368` runs a "non-fatal live verify" that invokes `agy-bridge --types` and pipes a real prompt through the `gemini` shim. Neither carries an installer-side bound, so both inherit the script bounds: `--types` resolves models (~20s) and the smoke call is a genuine delegation bounded at `GEMINI_SHIM_TIMEOUT`, default 600s. Against today's unresponsive agy the installer sits for up to ten minutes under a line that reads "non-fatal". Found while scoping criterion 4's static scan. Out of Phase 1 scope — criterion 4 names only `agy_bridge.sh` and `gemini_shim.sh`, and the fix is installer-side code, which is Phase 4's surface alongside its existing "no install path aborts halfway" criterion. Blocks 1.6.2 per the follow-up rule.
- **Widening the invariant to "no unbounded agy reachable from any shipped script"** — considered and declined for this phase; it would pull `install.sh` into a phase whose criterion names two files. Worth revisiting in Phase 4 once `delegate-agy-lkg` is fixed, so the scan covers the whole class in one assertion.

</deferred>

---

*Phase: 1-The missing-`timeout` decision*
*Context gathered: 2026-08-19*
