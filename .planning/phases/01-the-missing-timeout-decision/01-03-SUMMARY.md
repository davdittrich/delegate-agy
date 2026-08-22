---
phase: 01-the-missing-timeout-decision
plan: 03
subsystem: bounded-invocation
tags: [shell, timeout, watchdog, agy-bridge, duplication]
status: complete

requires:
  - "01-01: the run_bounded block, its markers, and fd 9 in scripts/gemini_shim.sh"
  - "01-02: RB_NO_TIMEOUT_WARN defined at the shim's TIMEOUT_BIN probe"
provides:
  - "scripts/agy_bridge.sh carries a byte-identical run_bounded block between its markers"
  - "scripts/agy_bridge.sh opens fd 9 as its original stderr"
  - "scripts/agy_bridge.sh defines RB_NO_TIMEOUT_WARN once, at its probe"
  - "all three bridge call sites bounded through run_bounded on every host"
  - "exit 2 no longer has a missing-bounding-binary cause"
affects:
  - "01-04: README's troubleshooting row for the deleted fatal is now unreachable and must be rewritten"
  - "01-05: RB01 static scan, RB02 block identity, RB03 warning literal, RB08 warn-once now have both scripts to assert against"
  - "01-06: RB05/RB07/RB13 (bridge under both mechanisms, startup that no longer refuses) and RB09 (fd 9 isolation) now have a converted bridge"
  - "Phase 3: must not list a missing timeout/gtimeout among its reachable-exit-2 provocations"

tech-stack:
  added: []
  patterns:
    - "duplicate-rather-than-source, justified by the standalone-drop-in constraint already recorded at scripts/gemini_shim.sh model-mapping comment"
    - "helper diagnostics on fd 9, never plain stderr, at any site that captures fd 2 into an operator-visible file"

key-files:
  created: []
  modified:
    - ".worktrees/agy-1.6.2/scripts/agy_bridge.sh"

decisions:
  - "The bridge's startup fatal on a missing timeout/gtimeout is deleted rather than documented: its only justification was that an unbounded call beats a refusal, and with the watchdog there is no unbounded call left to refuse."
  - "The stdin read's kill_after is 1, not the 5 the agy calls use, derived from what cat does with SIGTERM rather than copied for symmetry."
  - "No permanent test case added: plan 01-03 is allocated no id in the phase's coverage split; red was observed via ad-hoc probes and recorded instead."

metrics:
  duration: "~35 min"
  completed: 2026-08-19
  tasks: 3
  commits: 3

actuals:
  tokens: 4098
  tasks: 3
  commits: 3
---

# Phase 01 Plan 03: Bridge Bounding Convergence Summary

The bridge stopped refusing to run without coreutils and started bounding all three of its call sites with the same helper bytes the shim uses.

## What Was Built

**Task 1 — `487177e`.** Extracted the 232-line marker-delimited `run_bounded` block from `scripts/gemini_shim.sh` with `sed` and spliced it into `scripts/agy_bridge.sh` unmodified, plus `exec 9>&2` and its comment immediately after the bridge's `set -euo pipefail`. Nothing was retyped: both the block and the fd-9 preamble were extracted programmatically and concatenated, so byte-identity is a property of the method, not of careful transcription. The block sits after the `AGY_MODELS_TIMEOUT` validation and before `# ── Defaults ──`, the same relative position it occupies in the shim (after the probe and the bound declarations).

**Task 2 — `b55be8b`.** Replaced the probe's `else` arm — `echo "ERROR: timeout/gtimeout not found in PATH (install coreutils)" >&2; exit 2` — with the shim's arm, also extracted verbatim (shim lines 38-46) so the literal could not drift in transit. `TIMEOUT_BIN` becomes the empty string, `RB_NO_TIMEOUT_WARN` is defined once, and it is written to plain stderr because the probe runs before any call site has redirected anything.

**Task 3 — `6cc8591`.** Converted all three sites, one at a time with the suite run after each so a regression would be attributable:

| Site | Before | After |
|------|--------|-------|
| model fetch | `"$TIMEOUT_BIN" -k 3 "$AGY_MODELS_TIMEOUT" "$AGY_BIN" models` | `run_bounded "$AGY_MODELS_TIMEOUT" 3 -- "$AGY_BIN" models` |
| stdin read | `"$TIMEOUT_BIN" "$STDIN_TIMEOUT" cat` | `run_bounded "$STDIN_TIMEOUT" 1 -- cat` |
| delegation | `"$TIMEOUT_BIN" -k 5 "$TIMEOUT" "$AGY_BIN"` | `run_bounded "$TIMEOUT" 5 -- "$AGY_BIN"` |

The `cd` subshell, all three redirections, the `set +e` window, `EXIT_CODE`, the `SECONDS`-derived duration, the duration-based external-kill branch and the JSON payload are all untouched — `git diff` over the plan's three commits shows no line touching any of them.

## Numeric Derivation: the stdin read's kill-after

The plan required an explicit positive `kill_after` at this site but did not fix its value. It is **1**, derived rather than tuned:

- It must be positive because `run_bounded` rejects a non-positive value, and because the coreutils binary reads a zero duration as "no timeout" — a bound that silently disables bounding.
- It must not be 5. The 5 the two agy sites carry exists for one reason: agy is observed to ignore SIGTERM, so the ladder needs a second stage. `cat` blocked on a pipe does not ignore SIGTERM and dies on the first one, so the second stage here is a guard interval, not a grace period. Copying 5 for symmetry would assert a property of `cat` that is false.

The reasoning is in the code as a comment, since the value is otherwise unexplainable to the next reader.

## TDD: red observed, no permanent case added

`tdd_mode` is true and tasks 2 and 3 are behaviour-adding, but **plan 01-03 is allocated no test-case id by the phase's own coverage split.** Every assertion for this plan's behaviour is explicitly owned downstream:

| This plan's behaviour | Permanent assertion | Owner |
|---|---|---|
| block identity between the two scripts | RB02 | 01-05 task 2 |
| the warning literal in script and README | RB03 | 01-05 task 2 |
| warning emitted once per run | RB08 | 01-05 task 3 |
| every `$AGY_BIN` is a `run_bounded` argument | RB01 | 01-05 task 1 |
| bridge under both mechanisms; startup no longer refuses | RB05, RB07, RB13 | 01-06 task 1 |
| helper diagnostics stay out of the payload | RB09 | 01-06 task 2 |

Adding a case here would squat an id reserved for those plans and duplicate work they do more thoroughly (01-05's RB01 and RB02 both carry mutation demonstrations proving the case can fail). So red was observed with **ad-hoc probes that were not committed**, and the transitions recorded here and as a `bd comment` on each bead:

**Task 2 red → green** (sanitized PATH resolving neither binary, built from the harness's own documented `_PUREBIN_TOOLS` list, with the safety-net `timeout` pre-resolved to an absolute path):

```
RED    bash scripts/agy_bridge.sh --help  ->  rc=2
       "ERROR: timeout/gtimeout not found in PATH (install coreutils)"
       warning absent; help never printed; grep -c RB_NO_TIMEOUT_WARN= -> 0
GREEN  rc=0; warning present exactly once; help printed; literal count 1 and
       byte-identical to the shim's; ordinary PATH emits the warning 0 times
```

**Task 3 red → green** (same sanitized PATH, both entry paths):

```
RED    --type code -- "do a thing"   -> rc=2, "line 394: : command not found"
       echo prompt | --type code     -> rc=2, same
GREEN  both -> rc=0 with the delegated output
```

The task-3 red is worth keeping on the record: it is the empty `$TIMEOUT_BIN` reaching a call site, i.e. exactly the intermediate state threat `T-01-07` accepts and the reason task 3 must follow task 2 inside one plan.

## Verification

| Check | Result |
|---|---|
| `bash tests/run-tests.sh` | `PASS=97 FAIL=0` (baseline 97, no regression) |
| marker ranges diff | `BLOCKS_IDENTICAL` |
| `bash -n` on both shipped scripts | clean |
| joined-logical-line scan for `$AGY_BIN` | 6 occurrences across both scripts, every one a `run_bounded … --` argument |
| `TIMEOUT_BIN` in the bridge | 6 references: 3 probe assignments, 1 block comment, 2 inside the marked block. No call site. |
| main tree `scripts/` `tests/` `docs/` `README.md` | untouched |

The suite was run after task 1, after each of task 3's three sites, and at the end — five green runs.

## Deviations from Plan

None affecting behaviour. Three notes:

**1. Byte-identity inherits one cosmetic imprecision.** The copied block's header says *"The escalation rationale is the one already stated at the bound declarations above."* In the shim that is true — `SHIM_TIMEOUT`'s declaration carries it. In the bridge the equivalent rationale sits *below* the block, at the model-fetch comment and the delegation site's `-k 5` comment. Correcting the word would break byte-identity, which is the harder guarantee and the one RB02 pins. Left verbatim, deliberately.

**2. A probe bug, not a product bug.** My first red probe wrote `PATH="$D" timeout …`, which also removed `timeout` from the search path used to resolve the safety net itself, producing a bogus `rc=127`. The harness avoids this by resolving `_TIMEOUT_NET` to an absolute path before the replacement PATH applies; the probe was fixed the same way before red was accepted. Recorded because a green reading from that broken probe would have been vacuous.

**3. `.serena/` is untracked in both trees.** Pre-existing, not created by this plan, not committed.

## Known Ceilings

Two inherited from the block, neither introduced here, both already argued upstream:

- **External SIGKILL is indistinguishable from our own escalation on the watchdog path.** The block maps `rc` 137 and 143 to 124, so the bridge's duration-based external-kill branch — which keys on `EXIT_CODE -eq 137` — cannot fire when the fallback is the active mechanism. The plan's own `must_haves` scopes that guarantee to the coreutils path ("still fires on the coreutils path"), and the block carries a `ponytail:` comment naming the ceiling. Unchanged by this plan.
- **`RUN_BOUNDED_KILLED` does not escape the delegation site.** That site is a `cd` subshell, so the flag set inside it cannot reach the parent. This is harmless today because the plan forbids the error branch consulting the flag (D-02, D-11), but plan 01-06 should not assert the flag's value at the bridge's delegation site without accounting for the subshell.

## Handoffs

- **Plan 01-04 (README):** the row documenting `ERROR: timeout/gtimeout not found in PATH (install coreutils)` is now unreachable — that string no longer exists in either script. The replacement literal is in `scripts/agy_bridge.sh` and `scripts/gemini_shim.sh` as `RB_NO_TIMEOUT_WARN`; quote the bytes, not a paraphrase.
- **Plan 01-05:** both scripts now have marker-delimited blocks to compare, and RB01's joined-logical-line scan will find 6 sites, all compliant — verified with a scan of RB01's own shape.
- **Phase 3:** exit 2 has lost the missing-bounding-binary cause. Do not list it among reachable-2 provocations.

## Self-Check: PASSED

- `scripts/agy_bridge.sh` — FOUND, modified
- `487177e`, `b55be8b`, `6cc8591` — all FOUND in `git log` on `fix/agy-bridge-resilience`
- Beads `delegate-agy-kk9.6`, `.7`, `.8` — all closed
