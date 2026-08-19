---
phase: 01-the-missing-timeout-decision
verified: 2026-08-19T17:05:00Z
status: human_needed
score: 4/4 success criteria verified
behavior_unverified: 0
overrides_applied: 0
verifier_ran:
  - "bash .worktrees/agy-1.6.2/tests/run-tests.sh -> PASS=118 FAIL=0, exit 0"
  - "independent re-implementation of RB01's _rb_agy_scan against 7 mutants of gemini_shim.sh"
  - "independent M1b-equivalent mutation (_rb_signal forced to its direct-pid branch), plain and under an allocated pty"
  - "independent coreutils-arm mutation (-k dropped) and fd-9->fd-2 diagnostic mutation"
gaps: []
deferred: []
findings:
  - id: F1
    severity: warning
    title: "RB01's scan is per-logical-line, so a bounded and an unbounded `$AGY_BIN` on ONE line reports zero violations"
    evidence: "_rb_agy_scan counts violating LINES via `grep -cvE`, not violating OCCURRENCES. Measured on a copy of the shim with `run_bounded 5 2 -- \"$AGY_BIN\" foo; \"$AGY_BIN\" --version` appended: `0 4` — zero violations. Also `echo \"run_bounded x -- $AGY_BIN\"` -> `0 4`."
    impact: "The invariant holds on the files as they stand today (independently confirmed: bridge `0 2`, shim `0 3`). This is a hole in the guard, not a live violation — but criterion 4's own wording is 'zero exceptions', and RB01's stated ceiling claims the scan 'errs toward failing loudly', which is the opposite bias from what these two shapes produce."
    action: "File a follow-up ticket. Not phase-goal-blocking; release-blocking under PROJECT.md's own 'follow-ups discovered during work block the release' decision."
  - id: F2
    severity: warning
    title: "Plan 01-01's must_have 'run_bounded returns 124 if and only if RUN_BOUNDED_KILLED is 1' is false as written and should be corrected in the record"
    evidence: "gemini_shim.sh:221-225 coreutils arm sets the flag on 124|137 and returns rc UNCHANGED. Measured directly: `coreutils[pristine]: saw='137 1'`. Present since 01-01 (`git show 079d787` lines 135-136 are identical), so not a later regression."
    impact: "Record defect, NOT a code gap — see the adjudication section."
    action: "Amend 01-01-SUMMARY/PLAN must_have to scope the biconditional to the watchdog arm and state the caller-visible unify-124 contract separately."
  - id: F3
    severity: warning
    title: "R11 cannot be marked complete until delegate-agy-8k0's one edit lands"
    evidence: "REQUIREMENTS.md:41 Evidence still reads 'tests/run-tests.sh R5/R6/R7, T4/T5, SH4/SH5/SH6'; REQUIREMENTS.md:88 coverage cell still says R11 'Stays open only for the enforcement half'. Both halves landed."
    action: "One edit rewriting both lines to cite RB01/RB01m/RB02/RB02m/RB03/RB04/RB05/RB06a-d/RB07/RB08/RB09a-b/RB10a-b/RB11/RB12/RB13/RB14/RB20-22, then mark R11 complete and close 8k0."
human_verification:
  - test: "On a stock macOS with no coreutils and a PATH lacking timeout/gtimeout, run `gemini -p 'x'` against a hung agy."
    expected: "The warning literal appears; no shell job-control notice ('Terminated', '[1]+ ...') leaks to stderr; the call returns 124 within its bound."
    why_human: "No macOS host is reachable from this project and the job-control notice could not be reproduced on Linux under any tested shape. Broken Window #1. This is the one assumption neither the suite nor this verification can settle."
  - test: "Confirm the judgment-tier prohibitions carried by plans 01-01 through 01-06 (no test-only override switch in the shipped scripts; helper diagnostics never in a caller-parsed stream; no --no-verify / git add -A)."
    expected: "All resolved."
    why_human: "Prohibitions are judgment-tier by declaration. Verifier findings: no env/flag override of the mechanism exists outside the block (only the three probe assignments at gemini_shim.sh:33-38 / agy_bridge.sh:24-29); RB09a/RB09b pin the diagnostic isolation and I confirmed the fd-9 -> fd-2 mutant is caught; the worktree is clean at bb54c6f. Recorded as a NON-AUTHORITATIVE verdict — human confirmation recommended."
---

# Phase 1: The missing-`timeout` decision — Verification Report

**Phase Goal:** On a host with no `timeout`/`gtimeout`, both entry points behave one decided way, and both scripts and the README say which and why.
**Verified:** 2026-08-19
**Status:** human_needed — all four success criteria MET; one hardware-blocked human check and three record-hygiene items remain.
**Re-verification:** No — initial verification.

Everything below was checked against files in the code worktree
`/home/dd/Gemini/delegate-agy/.worktrees/agy-1.6.2` (branch `fix/agy-bridge-resilience`, tip
`bb54c6f`, working tree clean apart from an untracked `.serena/`). The main tree's `scripts/`,
`tests/` and `README.md` were not consulted for behaviour. No source or test file was modified;
every mutation below was applied to copies under a scratch directory.

---

## Goal Achievement

| # | Success criterion | Verdict | Confidence |
|---|-------------------|---------|-----------|
| 1 | Decision recorded in PROJECT.md's Key Decisions table with rationale | ✓ MET | 95 |
| 2 | Both entry points do what the decision says under a coreutils-less PATH, one test per entry point, nothing left unbounded | ✓ MET | 92 |
| 3 | README's environment-variable section states both behaviours side by side with the reason | ✓ MET | 90 |
| 4 | (restated) Every `"$AGY_BIN"` occurrence in both scripts is a `run_bounded` argument, enforced as an invariant | ✓ MET | 88 |

**Score: 4/4.**

### Suite, run by the verifier

```
$ bash /home/dd/Gemini/delegate-agy/.worktrees/agy-1.6.2/tests/run-tests.sh
...
PASS=118 FAIL=0
EXIT=0
```

Twenty-eight `RB*` lines, all `ok`. Green is necessary, not sufficient — the mutation work below
is what makes it evidence.

---

### Criterion 1 — the decision is recorded

`.planning/PROJECT.md:81`:

> | Every agy call is bounded on every host, by coreutils `timeout` where it exists and a native bash watchdog where it does not | `delegate-agy-cy5` asked whether the bridge should hard-fail, degrade with a warning, or refuse only the delegation call. Each of the three buys either a call with no bound or a caller broken at startup, and the core value forbids both — a `gemini` that refuses to run is the same failure as one that hangs, moved one step earlier. Bash bounds a call natively with no external binary, so the premise that a missing binary forces the trade is what was rejected; the recorded decision is *always bounded*, none of the three | ✓ Good — both entry points now warn once per run and proceed bounded; the bridge's startup fatal is deleted (Phase 1) |

The superseded row is resolved rather than deleted (`PROJECT.md:80`, Outcome `✗ Superseded by the
row below — Phase 1 dissolved the missing-`timeout` divergence instead of documenting it`). The
residual ceiling is recorded in the same document at `PROJECT.md:48` (Out of Scope) and
`PROJECT.md:69` (Constraints: coreutils "optional as of Phase 1 — it buys a process-group kill,
not the bound itself"). The ticket's three candidate designs were each rejected by name, which is
what the ROADMAP's Note demanded ("this phase is not done when code changes; it is done when the
choice is written down").

**MET.** Broken Window #3 records this as suite-unverifiable, which is correct — but it is a
property of a document I can read, and I read it. Recommend resolving BW#3 on that basis.

### Criterion 2 — both entry points do exactly that, one test per entry point

Recorded decision = *always bounded, no exception*. So criterion 2's escape clause ("unless the
recorded decision says it should") must now be unused. **It is unused, and I proved it rather
than assuming it.**

`_rb_assert_reaped` (`tests/run-tests.sh:1214-1244`) contains a soft branch: when the self-kill
guard warned, it appends `[D-14a degradation: guard warned, so only the direct kill is claimed]`
to the label and **skips the descendant assertion**. If that branch were taken on this host,
RB04/RB05/RB06b/RB06c would all be asserting only half of what criterion 2 asks for.

It is not taken. No `[D-14a degradation` string appears anywhere in the suite output, on any of
the six runtime cases. I reproduced the RB04 shape independently against a hand-built sanitized
PATH:

```
baseline: rc=124 elapsed=8s parent=990599 gone=1 child=990603 gone=1 guard_warned=0 notice=1
```

`elapsed=8s` is exactly `secs=3 + kill_after=5`, so the bound fired and not the 30s outer net;
`guard_warned=0` confirms `degraded=0`, so the descendant assertion was genuinely made.

**And the descendant assertion bites.** Forcing `_rb_signal` to its direct-pid branch (the
project's own M1b) on an extracted copy of the block:

```
pristine: saw='124 1' parent=992405 gone=1 child=992409 gone=1
pidonly:  saw='124 1' parent=992576 gone=1 child=992580 gone=0
```

Same exit code, same reaped parent — **only the forked child's survival separates them**. That is
the assertion doing the work, on this host, today.

Per entry point:

| Entry point | Mechanism | Case | Result |
|---|---|---|---|
| `gemini` shim | bash watchdog | RB04 (`run-tests.sh:1246-1263`) | ok, no degradation note |
| `agy-bridge` | bash watchdog | RB05 (`run-tests.sh:1792-1806`) | ok, no degradation note |
| both | coreutils | RB13 (`run-tests.sh:1845-1864`) | ok ×2, no degradation note |
| shim, no tty / with tty | bash watchdog | RB06b / RB06c | ok, terminal state itself asserted by RB06d |

RB07 (`run-tests.sh:1808-1825`) pins the other half of the decision: under a coreutils-less PATH
the bridge reaches its own argument handling instead of the exit-2 startup fatal it used to print,
and the warning literal on stderr is what proves the probe ran and chose to degrade rather than
the bridge merely skipping the probe.

**MET.**

### Criterion 3 — README states both behaviours side by side with the reason

`README.md:274-285`, inside `### Environment variables`, heading `#### Bounding without
timeout/gtimeout`:

> Both entry points do the same thing here, and that sameness is the decision rather than a coincidence. […] Earlier releases diverged: the bridge refused to start at all without a coreutils binary, while the shim ran the delegation call with no bound. Those were two ways of paying the same price […]

| | `timeout`/`gtimeout` on PATH | no bounding binary |
|-|------------------------------|--------------------|
| `agy-bridge` | coreutils enforces the bound | warns once at startup, then bounds with the bash watchdog |
| `gemini` shim | coreutils enforces the bound | warns once at startup, then bounds with the bash watchdog |

Both entry points, adjacent rows, and the paragraph above the table states *why* they do not
differ. `README.md:285` states the one thing coreutils does buy, and it matches the code
(`gemini_shim.sh:250-263` — the guard degrades to a direct-pid kill only when the child's group
could not be confirmed distinct).

Every behavioural claim in that section checks out against the scripts:

| README claim | Code | ✓ |
|---|---|---|
| `GEMINI_SHIM_TIMEOUT` "escalated to SIGKILL 5s after SIGTERM" | `gemini_shim.sh:561` `run_bounded "$SHIM_TIMEOUT" 5` | ✓ |
| `AGY_MODELS_TIMEOUT` "escalated to SIGKILL after 3s", "shared with agy_bridge.sh" | `gemini_shim.sh:338` and `agy_bridge.sh:393` both `run_bounded … 3` | ✓ |
| `AGY_MODELS_TIMEOUT` "corrected to 20 rather than rejected" | `gemini_shim.sh:319` `|| AGY_MODELS_TIMEOUT=20` | ✓ |
| stdin read "bounded whether or not a `timeout`/`gtimeout` binary is on PATH" | `gemini_shim.sh:511` `run_bounded "$STDIN_TIMEOUT" 5 -- cat` | ✓ |
| warning literal, `--` not an em dash | `gemini_shim.sh:45` / `agy_bridge.sh:36`, byte-identical; pinned by RB03 against literals typed independently in the test | ✓ |
| notice literal | `gemini_shim.sh:85` / `agy_bridge.sh:68` | ✓ |

Negative half verified independently: `grep -c 'ERROR: timeout/gtimeout not found in PATH'` returns
0 for `README.md`, both shipped scripts, `install.sh` and `uninstall.sh`; `grep -ci unbounded
README.md` returns 0.

**MET.** Broken Window #2 records this as suite-unverifiable, which is correct — no assertion can
judge whether a reason reads as a reason. I read it; it does. Recommend resolving BW#2 on that
basis.

### Criterion 4 (restated) — the invariant, not a count

RB01 (`run-tests.sh:1530-1581`). I re-implemented `_rb_agy_scan` byte-for-byte in a scratch script
and ran it myself rather than trusting the suite's own `ok`:

```
bridge: 0 2          <- 0 violations, 2 occurrences
shim:   0 3          <- 0 violations, 3 occurrences
```

Five occurrences, zero unbounded — matching R11's refusal to state a count while the current
number happens to be five. The occurrences are `agy_bridge.sh:394` (joined from the continuation
at 393) and `:597`; `gemini_shim.sh:338`, `:435`, `:561`. `AGY_BIN=$(command -v agy)` at
`agy_bridge.sh:23` / `gemini_shim.sh:32` carries no `$` and is correctly not an occurrence.

**On the mechanism selector.** `agy_bridge.sh:204` / `gemini_shim.sh:221` are
`if [[ -n "$TIMEOUT_BIN" ]]; then` — `run_bounded`'s internal arm selection. They contain no
`$AGY_BIN` at all, so RB01 cannot flag them, and the occurrence counts above confirm it does not.
Separately verified that no mechanism-aware conditional survives at any *call site*: stripping the
marked block from both files leaves `TIMEOUT_BIN` appearing only as the three probe assignments
(`gemini_shim.sh:34,36,38`, `agy_bridge.sh:25,27,29`).

**RB01m is real.** Independently exercised the same helper against seven mutants:

| Mutant | Result | Would RB01 fail? |
|---|---|---|
| append `"$AGY_BIN" --version` (RB01m's own mutation) | `1 4` | yes |
| append `foo ${AGY_BIN} bar` (brace form) | `1 4` | yes |
| append `# a comment mentioning "$AGY_BIN"` | `0 4` | no — correct, RB01m pins this noise floor |
| rename `AGY_BIN` -> `AGY_EXE` throughout | `0 0` | yes — the `RB01_TOTAL -lt 1` floor trips |
| append `eval "$AGY_BIN --version"` | `1 4` | yes |
| append `X="$AGY_BIN"` + `"$X" --version` | `1 4` | yes (the assignment line itself is flagged) |
| append `run_bounded 5 2 -- "$AGY_BIN" foo; "$AGY_BIN" --version` | **`0 4`** | **no — see F1** |
| append `echo "run_bounded x -- $AGY_BIN"` | **`0 4`** | **no — see F1** |

The runtime half is likewise real. RB13's coreutils arm was checked by dropping `-k` from
`"$TIMEOUT_BIN" -k "$kill_after" "$secs"`:

```
coreutils[pristine]: saw='137 1' elapsed=5s  parent_gone=1 child_gone=1
coreutils[nok]:      saw=''      elapsed=30s parent_gone=0 child_gone=0
```

The mutant runs to the 30s outer net with both processes alive — RB13's `elapsed < 20` cap and
both PID checks fire together.

**MET**, with F1 as a warning on the guard's robustness rather than on the invariant's current
truth.

---

## The live discrepancy, adjudicated

Plan 01-01 `must_haves.truths`:

> "`run_bounded` returns 124 if and only if its own kill flag `RUN_BOUNDED_KILLED` is 1; a child that exited on its own is never relabelled 124 even when elapsed time equals the bound (adjacency edge, D-02)."

**Verdict: (a) a stale, mechanism-blind must_have needing correction in the record. Not a gap in
the contract.** Evidence, in order:

1. **The statement is literally false on the coreutils arm.** `gemini_shim.sh:221-225`:
   ```bash
   if [[ -n "$TIMEOUT_BIN" ]]; then
       "$TIMEOUT_BIN" -k "$kill_after" "$secs" "$@" || rc=$?
       if [[ "$rc" -eq 124 || "$rc" -eq 137 ]]; then RUN_BOUNDED_KILLED=1; fi
       return "$rc"
   fi
   ```
   I measured it, not inferred it: `coreutils[pristine]: saw='137 1'` — flag set, rc 137.
2. **It was false when it was written.** `git show 079d787:scripts/gemini_shim.sh` lines 135-136
   are the same two lines. This is not drift introduced by a later plan; the must_have described
   the watchdog arm and mistook it for the helper.
3. **The caller-visible contract holds, at every host site.** `gemini_shim.sh:578-581` and
   `agy_bridge.sh:622-631` both map `124|137 -> exit 124`; the shim's `--version` site does the
   same at `:436-439`. RB13 pins it at the entry point, deliberately making no claim about the
   mechanism's own code (`run-tests.sh:1839-1844`).
4. **Normalising 137 -> 124 inside the helper would break a different requirement.** Both scripts
   discriminate an external kill from their own escalation with
   `EXIT_CODE -eq 137 && DURATION < TIMEOUT` (`gemini_shim.sh:571`, `agy_bridge.sh:607`). That is
   R5 / Phase 3 criterion 2. A helper that swallowed the 137 would delete the discriminator's
   input. The code is right; the sentence is wrong.
5. **The suite already scopes the claim correctly.** RB12 (`run-tests.sh:2216-2229`) drives the
   biconditional only under `TIMEOUT_BIN=""`, and 01-06-SUMMARY's first key-decision states the
   split in the same terms.

Correction to make: rewrite that must_have as two sentences — the biconditional scoped to the
watchdog arm, and the caller-visible `unify-124` contract stated separately as the entry points'
obligation. Filed as **F2**.

*Secondary, already documented:* even on the watchdog arm the biconditional has a ceiling — a
child that self-exits with 137 or 143 is relabelled 124 with the flag set
(`gemini_shim.sh:288-292`, ceiling stated in the `ponytail:` comment at `:285-287`). RB12 does not
cover it. Correctly disclosed, no action.

---

## Can the tests fail? — fourth-vacuity hunt

The phase caught three of its own (RB06c's pty HUP, RB12's three self-exited observations,
RB08-as-planned). I looked for a fourth and did not find one among the runtime cases. What I ran:

| Probe | Result |
|---|---|
| M1b-equivalent (`_rb_signal` forced to direct-pid), plain | child survives -> RB04/RB05/RB06b/RB10b would go red. **Non-vacuous.** |
| M1b-equivalent **under an allocated pty** (`script` util-linux 2.42.2) | `PTY[pristine] child_gone=1` vs `PTY[pidonly] child_gone=0`, both `saw_terminal=tty`. **RB06c's SIGHUP hardening genuinely fixed it** — the with-terminal half now discriminates. |
| coreutils arm with `-k` dropped | 30s to the outer net, both processes alive -> RB13 red. **Non-vacuous.** |
| helper diagnostics `>&9` -> `>&2` | `captured_stderr_has_note=1` -> RB09b red. **Non-vacuous.** Repeated the RB09b shape ×10: note on fd 9 10/10, caller streams clean 10/10. |
| RB01 scan, 8 mutants | 6 caught, 2 blind spots (**F1**). |

Structural anti-vacuity guards I checked exist and are real: `_rb_assert_reaped` requires both PIDs
non-empty (`:1225-1226`); RB09a asserts the marker *was* emitted so absence-by-silence cannot pass
(`:2057`); RB11 ends with a valid control probe expected to run (`:2290`, `RB11_RAN -eq 1`); RB12
requires at least one flag-set observation, satisfied by the child that cannot win the race
(`:2244`); RB06d asserts the terminal state directly rather than inferring it from exit status
(`:1990-1996`); RB20b proves `_rb_sleepers` can actually see a sentinel sleeper before RB20a's
zero-count means anything; RB08's ordering assertion is fed through stdin precisely because the
other two sites redirect their stderr into files.

**No fourth vacuous case found.** The one weakness I did find is static, not runtime: F1.

---

## Requirements coverage

| Requirement | Status | Evidence |
|---|---|---|
| R11 — Bounded execution | **Acceptance MET; do not mark complete yet** | Static invariant: RB01 + RB01m, independently re-run. Runtime proof per entry point on both mechanisms: RB04 (shim/watchdog), RB05 (bridge/watchdog), RB13 ×2 (both/coreutils), RB06b/c (terminal-less and with terminal). |

**Should R11 be marked complete? Yes — but only in the same edit that fixes its own record.**
`REQUIREMENTS.md:41` still reads `Evidence: README.md §Environment variables;
tests/run-tests.sh R5/R6/R7, T4/T5, SH4/SH5/SH6` — none of which enforce R11's acceptance — and
`REQUIREMENTS.md:88`'s coverage cell still says R11 "Stays open only for the enforcement half",
which is no longer true. Marking it complete while those two lines stand would ship a
requirement whose evidence pointer is false. That is `delegate-agy-8k0`, correctly deferred to one
edit; it is now the gating item and should be done at phase close. **F3.**

One scope note, not a blocker: every runtime proof exercises the **delegation** site. The
model-fetch and `--version` agy sites have runtime hang coverage only on the coreutils arm
(SH4/SH5 at `run-tests.sh:900,912`, and the models-hang cases at `:390,1036,1081`, all under the
ordinary PATH). On the watchdog arm those two sites are covered by the static invariant alone.
R11's acceptance is written per *entry point*, not per call site, so this is satisfied as stated —
recording it so a later reader does not assume more coverage than exists.

---

## Anti-patterns

Scanned both shipped scripts, `tests/run-tests.sh` and `tests/fake-agy.sh` for debt markers.

| Pattern | Result |
|---|---|
| `TBD` / `FIXME` / `XXX` | none |
| `TODO` / `HACK` / `PLACEHOLDER` | none |
| deliberate simplification markers | two `ponytail:` comments (`gemini_shim.sh:285`, and its byte-identical twin in the bridge), each naming its ceiling — this is the project's own convention, not debt |

Worktree clean at `bb54c6f` (only untracked `.serena/`). No shipped script was modified by plans
01-05 or 01-06; `git diff 3fdf663..HEAD --stat` touches `tests/` only, as 01-06-SUMMARY claims.

---

## Previously-recorded gaps — scoping assessment

| Item | Correctly scoped? |
|---|---|
| Suite runtime 2m25s vs plan 01-06's "under a minute" | **Yes.** The inherited baseline was 1m23s, so the plan criterion was unmeetable before the plan started. Flagged not met rather than gamed. My own run confirms the suite completes and exits 0. |
| `delegate-agy-8k0` (R11 Evidence line) | **Yes**, and it is now the gate on marking R11 complete — see F3. |
| `delegate-agy-cy5` (originating ticket) | **Yes** — but note its *description* still asserts the shim "calls agy unbounded", which is now false. Close it with the resolution rather than leaving a false statement in the tracker. |
| `delegate-agy-s4x` (RESEARCH prototype annotated in place) | Yes. |
| PROJECT.md / REQUIREMENTS.md outside the absence checks | **Yes, and the reason is sound** (`run-tests.sh:1690-1693`): the suite runs from the worktree and must also pass from a release tarball with no `.planning/`. I verified both by hand: PROJECT.md carries the always-bounded row with the superseded row resolved; REQUIREMENTS.md's R11 acceptance matches the shipped behaviour (its *Evidence* line does not — F3). |
| WINDOWS.md's five entries | Partly. #1 (macOS) is genuinely human-blocked and stays open. #2 and #3 are prose properties I have now read and judged satisfied — resolve them. #4 (SIGHUP-immune fake) is a deviation that was *applied*, and I verified it works under a real pty; it is a completed deviation, not an open window. #5 is F3. With `windows_enforce` on, four of the five need a disposition before `/gsd-ship` will pass. |

---

## Must be resolved before this phase ships

1. **F3 — `delegate-agy-8k0`**: rewrite R11's `Evidence:` line and its coverage-table cell, then
   mark R11 complete. Gating.
2. **F2** — correct plan 01-01's `run_bounded returns 124 iff RUN_BOUNDED_KILLED` must_have. The
   code is right; the record is not, and it is the only false statement I found in the phase's
   audit trail.
3. **F1** — file a follow-up for RB01's per-line blind spot (two occurrences on one logical line;
   a decoy string). Release-blocking under PROJECT.md's own follow-up rule, not phase-blocking.
4. **`delegate-agy-cy5`** — close with the resolution; its description asserts behaviour that no
   longer exists.
5. **WINDOWS.md** — dispose of #2, #3, #4 (fixed) and #5 (-> F3). #1 stays open, human-blocked.
6. **ROADMAP.md** — Phase 1's checkbox is still `[ ]` and the progress table still reads
   `In Progress`.

---

## Bottom line

The phase goal is achieved. The divergence is dissolved rather than documented, the decision is
written down with its rationale, both entry points bound every agy call on a coreutils-less host,
the README says so with the reason, and the invariant that stops the next call site slipping
through is enforced by a scan I re-ran myself against eight mutants. The three vacuous cases the
phase caught in itself were caught correctly and the fixes hold under independent mutation — I
confirmed RB06c's pty half, which had been the worst of them, now discriminates.

What remains is record hygiene, one narrow hole in the static scan, and one assumption no Linux
host can settle.

---

*Verified: 2026-08-19*
*Verifier: Claude (gsd-verifier)*
