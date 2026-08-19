# Roadmap: agy-delegate

## Overview

This is brownfield. 1.6.1 ships and works; 1.6.2 is written, sits on `fix/agy-bridge-resilience`, and was content-reverted from `master` at `a001d0e` pending the follow-ups it surfaced. The roadmap therefore has two halves. Phases 1–4 close the open tracker tickets and finish the four v1.6.2 requirements against the branch — four independent code surfaces (the `TIMEOUT_BIN` branches, the shared model cache, the bridge's error output, the installer and launcher). Phase 5 converts those four now-settled failure modes into a stated, tested contract for the `gemini` shim, which is the only thing in this project with box-wide reach. Phase 6 is the release gate: 1.6.2 ships only when nothing it surfaced is still open.

**Phase 1.5 was Phase 7 until 2026-08-19.** It builds the check that would have caught the originating bug, and it was roadmapped last because `agy` was believed unresponsive — the harness was the deliverable and "unverified" was the expected verdict. A bounded probe that day disproved the premise: agy 1.1.13 answers, `agy models` returns in under 30s, and `--model` demonstrably accepts both ids and display names. The check therefore runs **before** the phases that reason about agy's output rather than after the release meant to validate them, so Phases 2 and 5 work from recorded fixtures instead of a hypothesis. It is an insertion under the decimal convention below, not a renumbering.

**Judge state by reading files, never by the commit graph.** `master`'s history contains the 1.6.2 commits; `master`'s files do not.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

**`Depends on` lines are machine-read.** The dependency extractor scrapes every number on the line and ignores the leading word, so `Nothing (independent of Phases 1–2)` resolves as a dependency on 1 and 2. Write the line as either `Nothing` or a bare phase list and put every parenthetical, rationale, or criterion reference in a `**Note**:` beneath the phase (`delegate-agy-1i9`).

- [ ] **Phase 1: The missing-`timeout` decision** - Settle whether the shim degrades or refuses when no `timeout` binary exists, then say so in both scripts
- [ ] **Phase 1.5: Contract check against a real agy** (INSERTED 2026-08-19, was Phase 7) - Ask the real binary which assumptions hold and record the answers as fixtures the later phases build on
- [ ] **Phase 2: Model-list handling, end to end** - No crash on a bare environment, no poisoned shared cache, no misattributed blame for a degraded agy
- [ ] **Phase 3: The exit-code contract** - Every documented code reachable, distinct, and quoted in the docs as the code actually prints it
- [ ] **Phase 4: Installer and launcher surface** - Registry read stays comparison-only; no install path aborts halfway
- [ ] **Phase 5: The shim's failure-mode contract** - One table stating what `gemini` does to a caller that never heard of agy, one test per row
- [ ] **Phase 6: Ship 1.6.2** - The held release lands on master with every follow-up it surfaced already closed

## Phase Details

### Phase 1: The missing-`timeout` decision

**Goal**: On a host with no `timeout`/`gtimeout`, both entry points behave one decided way, and both scripts and the README say which and why.
**Depends on**: Nothing (first phase)
**Requirements**: R11
**Tickets**: `delegate-agy-cy5` (P1)
**Success Criteria** (what must be TRUE):

  1. The divergence is decided and the decision recorded in PROJECT.md's Key Decisions table with its rationale — hard-fail like the bridge, degrade with a loud warning, or degrade for everything except the delegation call itself.
  2. With no `timeout`/`gtimeout` on PATH and an unresponsive fake agy, `gemini` and `agy-bridge` each do exactly what that decision says, proven by a test per entry point; neither leaves an agy process running with no bound unless the recorded decision says it should.
  3. A reader of README's environment-variable section finds both behaviors stated side by side, with the reason they do or do not differ.
  4. On either mechanism, no `agy` invocation anywhere in the scripts can outlive its bound against a SIGTERM-ignoring fake. This is enforced as an **invariant, not a count**: a test asserts that every `"$AGY_BIN"` occurrence in `scripts/agy_bridge.sh` and `scripts/gemini_shim.sh` is an argument to `run_bounded`, with zero exceptions — so a call site added later fails the suite instead of slipping through unbounded.

**Plans**: 4/6 plans executed

Plans:
**Wave 1**

- [x] 01-01-PLAN.md — Tracer: one bounded shim delegation that reaps agy and its child with no `timeout` binary present

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 01-02-PLAN.md — Route the shim's remaining three sites through `run_bounded` and warn once per run at the probe
- [x] 01-03-PLAN.md — Duplicate the helper into the bridge, remove its startup fatal, bound its three sites
- [x] 01-04-PLAN.md — Record the decision: README, PROJECT.md Key Decisions, REQUIREMENTS.md R11, ticket resolution

**Wave 3** *(blocked on Wave 2 completion)*

- [ ] 01-05-PLAN.md — Lock the invariant: static scan with zero exceptions, block identity, warning literal

**Wave 4** *(blocked on Wave 3 completion)*

- [ ] 01-06-PLAN.md — Runtime proof per entry point, on both mechanisms, with and without a controlling terminal

**Note**: the ticket names three candidate designs and states that the choice, not just the implementation, is open. This phase is not done when code changes; it is done when the choice is written down.

**Why criterion 4 is an invariant rather than a list.** The count of `agy` call sites has been stated wrong three times in three different ways: the original plan said two, a whole-branch review corrected it to four, and it is now five — the last because this project's own dynamic-model-resolution work added one to the shim. A criterion naming a number is correct only until the next commit and then silently goes stale, which is precisely the failure mode that let an unbounded call survive a release built to eliminate unbounded calls. Assert the property over the file instead: any new call site must justify itself against the test, not against someone's memory of how many there were.

### Phase 1.5: Contract check against a real agy

**Goal**: An operator can ask the real binary which assumptions hold and get either a recorded answer or an honest "could not ask" — and the later phases build on the recorded answers rather than on hypotheses.
**Depends on**: Nothing
**Requirements**: S5
**Tickets**: `delegate-agy-xfa` (P1). `delegate-agy-9qp` (P2) carries the probe evidence that motivated this phase's move and closes when its doc corrections land. `delegate-agy-62x`, which raised the id-vs-display-name question and was closed without ever being verified, is answered by criterion 1.
**Success Criteria** (what must be TRUE):

  1. One command, separate from the unit suite and never invoked by it, exercises the real `agy` and reports which assumptions hold — at minimum what `agy models` emits, whether `--model` accepts ids, display names, or both, and whether a per-run `GEMINI.md` in the working directory actually binds when agy can also see `GEMINI.md` files in other projects (`delegate-agy-xfa`).
  2. Run against an `agy` that hangs or is absent, the check exits within its own `-k` bound with a distinct "unverified" status, names the assumption it could not settle, and never reports pass — it does not hang the operator who ran it. This path is required and must be tested; it is no longer the expected outcome.
  3. Its captured output lands in `tests/` fixtures in a form the fake agy can be regenerated from, so the suite's fake tracks real output instead of a hypothesis. At minimum the fixtures carry the `id<TAB>display name` model list, the invalid-model rejection (which renders its "Available models:" list in display names), and the rc=0-with-empty-stdout response that R6 exists to catch.
  4. README states the verified behavior as fact — that `--model` accepts both ids and display names — carrying the `agy` version and the date it was verified against, and the check re-confirms it rather than the docs disclaiming it. No document may claim the assumption is unverified.

**Plans**: TBD

**Note**: this phase was Phase 7 until 2026-08-19 and depended on Phase 6. It moved because its blocking premise was disproven, not because its scope shrank. The "could not ask" path in criterion 2 stays mandatory — agy was unreachable last week and may be again — but the phase now has to produce a real verdict, and Phases 2 and 5 consume its fixtures. Verified so far against agy 1.1.13: `agy models` returns 14 lines of `id<TAB>display name` in under 30s; live ids carry a third segment (`gemini-3.1-pro-high`, `gemini-3.7-flash-medium`), so both scripts' anchored matchers and `config/model-map.json`'s `pro-high`/`flash-high` class values still hold.

### Phase 2: Model-list handling, end to end

**Goal**: A bare environment cannot crash the bridge, and one bad `agy models` reply cannot degrade the other tool or blame the user for it.
**Depends on**: Phase 1.5
**Requirements**: S1, S4
**Tickets**: `delegate-agy-30m` (P1), `delegate-agy-8ph` (P2)
**Success Criteria** (what must be TRUE):

  1. `agy-bridge` invoked with no `HOME` set — `env -i`, a container entrypoint, a `User=`-less systemd unit — reaches its own argument handling instead of dying on an unbound variable, and an unwritable cache path leaks no redirect error to stderr.
  2. An `agy models` reply containing no `gemini-` ids is never written to `~/.cache/agy-bridge-models` by either writer, so the next invocation of the *other* tool re-fetches rather than reading poison for up to an hour.
  3. A caller who hits a `gemini-`less model list is told agy is degraded or unauthenticated, and shown agy's own stderr — not told their `--type` did not match.
  4. A tab-suffixed or extra-column `agy models` reply still resolves a model: the input is normalized, and the anchored `^gemini-[0-9.]+-<class>$` matchers are byte-identical to what shipped.

**Plans**: TBD

**Note**: `delegate-agy-8ph` forbids a one-sided fix and forbids changing the 60-minute TTL as a substitute. Both writers change together or neither does.

**On the Phase 1.5 dependency**: 1.5's recorded fixtures are what criterion 4's "byte-identical to what shipped" is checked against — without them this phase re-asserts a hypothesis about `agy models` output rather than a fact. Otherwise this phase is independent of Phase 1: same two files, different code region.

### Phase 3: The exit-code contract

**Goal**: Every documented exit code is reachable, means exactly one thing, and the docs quote the message the code actually prints.
**Depends on**: Nothing
**Requirements**: R5, R6
**Tickets**: `delegate-agy-6q1` (P3), `delegate-agy-v5a` (P3)
**Success Criteria** (what must be TRUE):

  1. A caller can provoke each of 2, 3, 124, 127, and 137 and receives a distinct message naming that specific cause; the suite exercises all five.
  2. An agy killed by something else early is reported as an external kill, while one killed by the bridge's own `-k` escalation is reported as a timeout — the two are separated by elapsed duration against the bound, not conflated.
  3. When agy writes nothing to stderr, no error message ends in a dangling `: ` — in either the plain-text or the JSON form, at both the external-kill and the generic branch.
  4. README's troubleshooting table quotes each exit-code message as the code emits it, appended stderr suffix included, so an operator matching output against the docs finds their string.
  5. agy exiting 0 with empty stdout yields exit 3 with 0-byte stdout in text mode and an `{"error":…}` envelope carrying no `response` key in JSON mode — a regression test pins both shapes so the failure payload can never become success-shaped.

**Plans**: TBD

**Note**: independent of Phases 1–2 — this phase owns the bridge's error output, a different code region from the `TIMEOUT_BIN` branches and the model cache. Criterion 5's empty-success case is not hypothetical: a live agy was observed on 2026-08-19 exiting rc=0 with completely empty stdout when a tool hit a headless permission gate.

### Phase 4: Installer and launcher surface

**Goal**: The registry read stays a version comparison and contributes nothing else, and no install path can abort after the wrappers are written.
**Depends on**: Nothing
**Requirements**: R8, S2
**Tickets**: `delegate-agy-4vy` (P3), `delegate-agy-4xn` (P3)
**Success Criteria** (what must be TRUE):

  1. A lookalike plugin from another marketplace sitting in `installed_plugins.json` never matches this plugin's key, and an adjacent entry's version is never misattributed — proven with registry fixtures that place one immediately beside the other.
  2. An absent, truncated, or reshaped registry makes the launcher run silently rather than refuse, so a Claude Code schema change can never manufacture a false "superseded pin" and break `gemini` box-wide.
  3. The repin command printed on a real version mismatch is assembled from install-time literals plus a version matched against `^[0-9]+(\.[0-9]+)*$`; no registry-supplied string is ever printed as a command to run, and the exec target remains the install-time literal.
  4. `AGY_SETUP_PATCH_ALIASES=1` on a host with no `python3` ends in the same graceful state as every other python3-absent path in the installer, rather than hard-failing after the wrappers already exist on disk.
  5. The documented CLI fallback one-liner reaches its validating `case` under `set -euo pipefail` instead of aborting on a SIGPIPE from `head`.

**Plans**: TBD

**Note**: independent of Phases 1–3 — this phase owns `install.sh`, the generated wrapper, and the docs one-liner, none of which the other phases touch. `delegate-agy-lkg` lands here too: the "non-fatal live verify" at `install.sh:360-368` invokes the bridge and shim with no installer-side bound, so it can sit for up to `GEMINI_SHIM_TIMEOUT` (default 600s) under a line that says it is non-fatal.

### Phase 5: The shim's failure-mode contract

**Goal**: An operator can read exactly what `gemini` does to a caller that has never heard of agy, for every way this plugin fails.
**Depends on**: Phases 1, 1.5, 2, 3, 4
**Requirements**: S3
**Tickets**: none open — this phase states the contract the earlier phases make true
**Success Criteria** (what must be TRUE):

  1. README carries one table naming the shim's behavior for each failure mode — hung agy, unparseable model list, missing dependency, superseded pin — with the bridge's behavior in the adjacent column.
  2. Every row of that table has a test, so changing any of those four paths fails the suite rather than the next Octopus or Metaswarm run.
  3. Every row where the shim and bridge differ states why in one line, and no row differs without a stated reason.
  4. An unrecognized model name still passes through to agy unchanged — the shim warns or degrades but never hard-rejects input it merely does not recognize.

**Plans**: TBD

**Note**: each dependency settles one of the four failure modes this phase pins down. Phase 1.5 supplies the real-agy behavior the "hung agy" and "unparseable model list" rows are written against, so those rows describe what agy does rather than what it was assumed to do.

### Phase 6: Ship 1.6.2

**Goal**: The held release lands on master with every follow-up it surfaced already closed.
**Depends on**: Phases 1, 1.5, 2, 3, 4, 5
**Requirements**: none directly — this phase is the release gate for R5, R6, R8, R11, S1, S2, S3, S4, S5
**Tickets**: none at plan time; the gate is that none exist at ship time
**Success Criteria** (what must be TRUE):

  1. `bd list --status open` contains no ticket discovered or caused by 1.6.2 work, including any opened during Phases 1–5; anything not fixed is deferred with a recorded reason before the tag is cut.
  2. Reading the files on `master` — not `git log` — shows the fixes present, so the `a001d0e` content revert is genuinely undone rather than papered over by a merge that restores only history.
  3. A fresh `scripts/install.sh` run against merged `master` produces working `agy-bridge` and `gemini` launchers, and both suites pass on that tree.
  4. The release notes name each defect 1.6.2 closes and state plainly that every existing installation must re-run the installer, because the pin only points forward.

**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 1.5 → 2 → 3 → 4 → 5 → 6

Phases 1, 1.5, 3, and 4 have no dependencies on each other and may be planned or executed concurrently; Phase 2 waits on 1.5's fixtures. Phases 1–4 touch overlapping files (`agy_bridge.sh`, `gemini_shim.sh`), so concurrent execution trades merge friction for wall-clock, and that tradeoff is the planner's call. Phase 1.5 touches no shipped script — it adds a check and fixtures — so it merges cleanly alongside any of them.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. The missing-`timeout` decision | 4/6 | In Progress|  |
| 1.5. Contract check against a real agy | 0/TBD | Not started | - |
| 2. Model-list handling, end to end | 0/TBD | Not started | - |
| 3. The exit-code contract | 0/TBD | Not started | - |
| 4. Installer and launcher surface | 0/TBD | Not started | - |
| 5. The shim's failure-mode contract | 0/TBD | Not started | - |
| 6. Ship 1.6.2 | 0/TBD | Not started | - |

## Requirement Coverage

| Requirement | Phase | Open tickets |
|-------------|-------|--------------|
| R5 — Exit codes are a contract | Phase 3 | `6q1`, `v5a` |
| R6 — Never report empty success | Phase 3 | — |
| R8 — Registry read is comparison-only | Phase 4 | — |
| R11 — Bounded execution | Phase 1 | `cy5` |
| S1 — Survive an `agy models` format change | Phase 2 | — |
| S2 — Survive a Claude Code registry schema change | Phase 4 | — |
| S3 — Shim defects must not escape into PATH callers | Phase 5 | — |
| S4 — Shared model cache safe under two writers | Phase 2 | `8ph` |
| S5 — Verifiable against a real `agy` | Phase 1.5 | `xfa` |

9/9 requirements mapped, each to exactly one phase. No orphans, no duplicates.

All 10 open tickets are absorbed: `cy5` → Phase 1; `xfa`, `9qp` → Phase 1.5; `30m`, `8ph` → Phase 2; `6q1`, `v5a` → Phase 3; `4vy`, `4xn`, `lkg` → Phase 4. `delegate-agy-30m` carries no requirement mapping — it is a release-blocking crash surfaced by 1.6.2 work, and Phase 6's gate covers it. `lkg` (installer live-verify can block ~600s) and `9qp` (the stale "agy is unresponsive" blocker in STATE.md and PROJECT.md) were filed on 2026-08-19 during Phase 1's discussion; `xfa` (does the per-run `GEMINI.md` policy actually bind?) came out of the probe that disproved `9qp`'s premise.
