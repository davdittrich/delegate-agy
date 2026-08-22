---
phase: 06-ship-1-6-2
plan: 06
subsystem: release
tags: [release-gate, beads, install-proof, changelog, verification]

requires:
  - phase: 06-ship-1-6-2 (plans 01-05)
    provides: RB30 trap-restore fix, xfa/i43 investigation closures, D-04/D-07 flag-eating and zero-byte-fetch fixes, IN02/CC03-widening structural test guards, criterion-2 content proof + finished 1.6.2 changelog, and the CC03/CC03m regression fix (commit 5722252, ahead of this plan)
provides:
  - Fresh-clone install proof at a pinned GATE_SHA, in a sandboxed HOME, with both `agy-bridge` and `gemini` executing and both test suites green (Success Criterion 3)
  - Closure of all eight tickets this phase owns (ltf, u1z, d4t, b7g, sup, xfa, i43) plus the Phase 5 epic (rod), with cited evidence, satisfying Success Criterion 1
  - The release-gate dossier: all four Success Criteria stated verbatim with literal evidence, plus the one item that requires a human's own terminal
affects: [gsd-ship, next-milestone]

actuals:
  tokens: 9200
  tasks: 3
  commits: 1

tech-stack:
  added: []
  patterns: []

key-files:
  created:
    - .planning/phases/06-ship-1-6-2/06-06-SUMMARY.md
  modified: []

key-decisions:
  - "Task 1's install proof ran against a clone of the local repository detached at GATE_SHA (37c9926), not an unpinned `master` and not the working tree — the configured GitHub remote (origin) still resolves to `a001d0e`, well behind local history, so cloning the remote would have proven nothing about the state this gate exists to certify. Ship-time obligation recorded: whoever pushes and tags must confirm the pushed remote resolves to GATE_SHA before tagging."
  - "None of this plan's eight owned tickets were deferred, including delegate-agy-sup's intermittent flake — the project's own follow-ups-are-blockers rule overrides the instinct to defer a pre-existing flake, and Task 1's plan text names this explicitly (D-01)."
  - "delegate-agy-sup's closure comment states an explicit bound: RB30 proves the ORDERING INVARIANT (host trap restored before watchdog teardown completes), not that RB30 independently reproduces every historical RB24 flake report outside its own forced window."

requirements-completed: [R5, R6, R8, R11, S1, S2, S3, S4, S5]

coverage:
  - id: D1
    description: "Success Criterion 3 — fresh install from a clean clone pinned to GATE_SHA, sandboxed HOME, both suites green"
    requirement: "R11"
    verification:
      - kind: integration
        ref: "env -u CLAUDE_CONFIG_DIR HOME=<throwaway> bash <clone>/scripts/install.sh — exit 0"
        status: pass
      - kind: integration
        ref: "bash tests/run-tests.sh (clone @ GATE_SHA) — PASS=165 FAIL=0, exit 0"
        status: pass
      - kind: integration
        ref: "bash tests/hooks/run-hook-tests.sh (clone @ GATE_SHA) — pass: 28 fail: 0, exit 0"
        status: pass
    human_judgment: false
  - id: D2
    description: "Success Criterion 1 — all eight owned tickets and the Phase 5 epic closed with cited evidence, no unexplained open ticket"
    verification:
      - kind: other
        ref: "bd list --status open 2>&1 | grep -cE 'delegate-agy-(ltf|u1z|d4t|b7g|sup|rod|xfa|i43)' → 0"
        status: pass
      - kind: other
        ref: "bd list --status deferred 2>&1 | grep -cE 'delegate-agy-(rdu|abv|e4i)' → 3 (untouched)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Success Criterion 2 — a001d0e content-revert proven undone by content, not git log (carried from plan 06-05, cited here)"
    verification:
      - kind: other
        ref: "06-05-SUMMARY.md's seven-item content-grep script — VERDICT: PASS, all pieces present on master"
        status: pass
    human_judgment: false
  - id: D4
    description: "Success Criterion 4 — README's ### 1.6.2 names every defect this release closes and states the re-run requirement plainly"
    verification:
      - kind: unit
        ref: "sed -n '/^### 1\\.6\\.2$/,/^### 1\\.6\\.1$/p' README.md | grep -c '^- ' → 12; ticket-ID leak check → 0; re-run notice → 1"
        status: pass
    human_judgment: false
  - id: D5
    description: "Real install remains untouched by the sandboxed proof (isolation check)"
    verification:
      - kind: other
        ref: "before/after sha256+mtime snapshot of ~/.local/bin/{agy-bridge,gemini} — byte-identical"
        status: pass
    human_judgment: false
  - id: D6
    description: "Human sign-off on all four criteria, plus the real-terminal install/stale-pin check no script in this phase can perform"
    verification: []
    human_judgment: true
    rationale: "Task 1's proof runs in a throwaway HOME with no plugin registry; the stale-pin comparison only ever exercises the operator's real ~/.claude/plugins/installed_plugins.json, so that specific path is unverifiable by any script this phase can run."

duration: 45min
completed: 2026-08-22
status: complete
---

# Phase 06 Plan 06: Ship 1.6.2 release gate Summary

**All eight tickets Phase 6 owns are closed with cited evidence, a clone pinned to `GATE_SHA=37c9926` installs cleanly into a sandboxed home with both suites green (PASS=165 FAIL=0, hooks 28/0), the real launcher paths are byte-unchanged, and all four Success Criteria are assembled below with literal evidence for human sign-off.**

## Performance

- **Duration:** ~45 min (includes two full `tests/run-tests.sh` runs — working tree and clone — plus the hook suite, each ~3.5 min)
- **Tasks:** 3/3 completed
- **Files modified:** 0 repository files (all three tasks are proof/ticket/dossier tasks per their own `<files>` declarations — this SUMMARY is the only artifact)

## Accomplishments

- **Task 1 (D-10, Criterion 3):** Resolved `GATE_SHA` from local `master`, cloned the *local* repository (not the lagging GitHub remote), detached at that SHA, and ran a full sandboxed install (`HOME` pointed at a throwaway directory, `CLAUDE_CONFIG_DIR` unset) — installer exited 0, both wrappers carry the `# agy-delegate-wrapper` marker and execute (`--help` exits 0 on both), both suites are green on the clone, and the two real launcher paths are proven byte-identical before and after via sha256+mtime snapshot.
- **Task 2 (Criterion 1):** Closed all five fix tickets this phase owns (`ltf`, `u1z`, `d4t`, `b7g`, `sup`) each with a `bd comment` citing the exact commit(s) and test case that proves it, closed the Phase 5 epic (`rod`) on completion (not a fix), and verified `bd list --status open` contains zero of the eight scoped tickets. The three already-deferred tickets outside this phase's scope (`rdu`, `abv`, `e4i`) remain untouched at count 3.
- **Task 3 (dossier):** Assembled the `## Release Gate` section below quoting all four Success Criteria verbatim from `.planning/ROADMAP.md` with literal evidence under each, plus an `### Open for human verification` subsection naming the one thing no sandboxed script can prove — the real install's stale-pin comparison against the operator's actual plugin registry.

## Task Commits

1. **Task 1: D-10 — fresh install proof (Criterion 3)** — no repository file; proof recorded in this SUMMARY.
2. **Task 2: Close five fix tickets + Phase 5 epic, verify Criterion 1** — no repository file; `bd` issue-state changes only (see Beads Ledger below).
3. **Task 3: Assemble release-gate dossier** — no repository file; dossier is this SUMMARY's `## Release Gate` section.

**Plan metadata:** this commit (SUMMARY.md, STATE.md, ROADMAP.md, REQUIREMENTS.md).

## Files Created/Modified

- `.planning/phases/06-ship-1-6-2/06-06-SUMMARY.md` — this file (new)

None of the three tasks touch `scripts/`, `tests/`, or `README.md` — confirmed by `git status --short` at every step of this plan (clean before, during, and after).

## Beads Ledger (Task 2)

| Ticket | Disposition | Evidence cited in `bd comment` |
|---|---|---|
| `delegate-agy-ltf` | Closed — fixed | Plan 06-03 (D-04): shim's unrecognized-long-flag catch-all shifts once, not twice. RED `c6b3d68` (SH16), GREEN `6e79225`. |
| `delegate-agy-u1z` | Closed — fixed | Plan 06-04 (D-05): IN02 joint invariant over the twin SIGPIPE-safe herestring model-validation sites. Commit `875834b`. |
| `delegate-agy-d4t` | Closed — fixed | Plan 06-04 (D-06): RB01 widened to `tests/contract-check.sh`; measured violations=7→0, occurrences=11→4. Commits `875834b`, `ea3dd79`. |
| `delegate-agy-b7g` | Closed — fixed | Plan 06-03 (D-07): zero-byte no-cache fetch now reports the degraded diagnostic. RED `cbe80f1` (R9f), GREEN `aecc234`. |
| `delegate-agy-sup` | Closed — fixed | Plan 06-01 (D-08): RB30 deterministic forcing case, RED `776dbfd`, GREEN `d887a8f`. Comment states explicit bound: proves the ordering invariant, not that it is RB24's sole historical cause. |
| `delegate-agy-rod` | Closed — completion | Phase 5 epic; all five children (`rod.1`-`rod.5`) done, phase's two success criteria recorded complete in ROADMAP.md. Never carried a defect. |
| `delegate-agy-xfa` | Already closed (plan 06-02) | Verified still closed; not reopened, not re-closed. |
| `delegate-agy-i43` | Already closed (plan 06-02) | Verified still closed; not reopened, not re-closed. |

**Verification commands and results:**

```
$ bd list --status open 2>&1 | grep -cE 'delegate-agy-(ltf|u1z|d4t|b7g|sup|rod|xfa|i43)'
0
$ bd list --status deferred 2>&1 | grep -cE 'delegate-agy-(rdu|abv|e4i)'
3
```

Remaining `bd list --status open` output after Task 2's closures — only this plan's own epic and its three child task tickets, none of them defects:

```
○ delegate-agy-tmm ● P2 [epic] Phase 6: Ship 1.6.2
├── ○ delegate-agy-tmm.11 ● P2 06-06.1 Task 1: D-10 — fresh install from a clean clone, both suites green (Criterion 3)
├── ○ delegate-agy-tmm.12 ● P2 06-06.2 Task 2: Close the five fix tickets and the Phase 5 epic, then verify Criterion 1
└── ○ delegate-agy-tmm.13 ● P2 06-06.3 Task 3: Assemble the release-gate dossier for human sign-off

Total: 4 issues (4 open, 0 in progress)
```

Already-deferred set, outside this phase's D-01 scope, untouched and requiring no action: `delegate-agy-rdu`, `delegate-agy-abv`, `delegate-agy-e4i` (plus `ps3.8`/`ps3.9`, unrelated subagent-hook work).

**Reopen mapping (recorded per Task 2's instruction, in case Task 3's human sign-off rejects a criterion):**

| If rejected | Reopen |
|---|---|
| Criterion 1 (ticket ledger) | The specific disputed ticket among `ltf`, `u1z`, `d4t`, `b7g`, `sup`, `rod` — `bd reopen <id>` with a comment naming the rejected criterion. |
| Criterion 3 (install/suites) | No ticket to reopen; re-run Task 1's proof after the underlying fix. |
| Criterion 2 or 4 | No ticket to reopen; these are documentation/content checks (06-05's script, README's changelog), not backed by any of this phase's eight tickets. |

## Decisions Made

- Cloned the **local** repository, not `origin` — `git ls-remote origin refs/heads/master` returned `a001d0e857c064ca8534bc6610417e6cdfcfa47e`, the pre-revert-undo commit, well behind local `master`. A clone of the remote would have proven the wrong tree. This is recorded as a fact for the ship-time obligation below, not a defect of this plan.
- `delegate-agy-sup` was fixed and closed like the other four, not deferred, per the user's explicit instruction (D-01) that overrides the general instinct to defer a pre-existing flake — the project's own "follow-ups discovered during work are blockers" rule governs.
- `delegate-agy-rod` (Phase 5 epic) closes on completion, not on a fix — its closure comment says so explicitly to avoid inventing a defect it never had.

## Release Gate

Quoted verbatim from `.planning/ROADMAP.md`, Phase 6's Success Criteria:

### Criterion 1 — `bd list --status open` contains no ticket discovered or caused by 1.6.2 work, including any opened during Phases 1-5; anything not fixed is deferred with a recorded reason before the tag is cut.

**Evidence:** All eight tickets this phase owns (`ltf`, `u1z`, `d4t`, `b7g`, `sup`, `rod`, `xfa`, `i43`) are closed — see the Beads Ledger above, each with a `bd comment` citing its fix commit(s) or completion basis. `bd list --status open 2>&1 | grep -cE 'delegate-agy-(ltf|u1z|d4t|b7g|sup|rod|xfa|i43)'` → `0`. No ticket was deferred; `delegate-agy-sup`'s intermittent-flake candidate for deferral was fixed instead, per the project's standing rule that a follow-up discovered during work is a blocker, not a deferral candidate. The pre-existing deferred set (`rdu`, `abv`, `e4i`), outside this phase's eight, is unchanged at count `3`.

**Met.**

### Criterion 2 — Reading files on `master` (not `git log`) shows the fixes present, so the `a001d0e` content revert is genuinely undone rather than papered over by a merge that restores only history.

**Evidence (from plan 06-05's own verification, cited not re-run since no file changed since):**

```
1. AGY_MODELS_TIMEOUT default + positive-integer validation guard:  count=1  -> PASS
2. run_bounded "$AGY_MODELS_TIMEOUT" 3 --  (model-fetch kill-after 3):        count=1  -> PASS
3. run_bounded "$TIMEOUT" 5 --  (delegation kill-after 5):                    count=1  -> PASS
4. "AGY_MODELS_TIMEOUT must be a positive integer" text:                      count=1  -> PASS
5. degraded-list "no 'gemini-' ids" text (expect >=3):                        count=3  -> PASS
6. external-kill arm "$EXIT_CODE" -eq 137 && "$DURATION" -lt "$TIMEOUT":      count=1  -> PASS
7. timeout-normalization arm "$EXIT_CODE" -eq 124 || "$EXIT_CODE" -eq 137:   count=1  -> PASS
VERDICT: PASS -- all seven pieces confirmed present on master by content, not by git log.
```

`git merge-base --is-ancestor fix/agy-bridge-resilience master` — exit 0 (ancestry confirmed).

**Met.**

### Criterion 3 — A fresh `scripts/install.sh` run against merged `master` produces working `agy-bridge` and `gemini` launchers, and both suites pass on that tree.

**Evidence:**

- `GATE_SHA = 37c9926b28c64b4ad8dd7e248cf09f8a685d016f` (local `master` at plan start; `git status --short` under `scripts/`, `tests/`, `README.md` was clean at resolution time).
- Clone source: **local repository** (`git clone /home/dd/Gemini/delegate-agy <scratch>`), detached at `GATE_SHA`; `git -C <scratch> rev-parse HEAD` printed the same 40-character SHA.
- Remote fact, not a failure: `git ls-remote origin refs/heads/master` → `a001d0e857c064ca8534bc6610417e6cdfcfa47e` — the remote lags local `master` substantially. **Ship-time obligation:** whoever runs `/gsd:ship` must confirm the pushed remote resolves to `GATE_SHA` (or a fast-forward descendant carrying it) before tagging.
- Sandboxed install: `env -u CLAUDE_CONFIG_DIR HOME=<throwaway> bash <clone>/scripts/install.sh` → exit `0`. Both `agy-bridge` and `gemini` exist under `<throwaway>/.local/bin`, executable, second line `# agy-delegate-wrapper` in both.
- `<throwaway>/.local/bin/agy-bridge --help` → exit `0`, output contains `--type` (count 2).
- `<throwaway>/.local/bin/gemini --help` → exit `0`, output non-empty (16 lines).
- `bash tests/run-tests.sh` on the clone → **`PASS=165 FAIL=0`**, exit `0`.
- `bash tests/hooks/run-hook-tests.sh` on the clone → **`pass: 28 fail: 0`**, exit `0`.
- Isolation proof — real launcher paths before and after the sandboxed install, byte-identical:
  ```
  /home/dd/.local/bin/agy-bridge size=1732 mtime=1787068888 sha256=0e26632aa4201afeb428387c52c6ead95e99dfd77beda6369d9db775734badc1
  /home/dd/.local/bin/gemini    size=1725 mtime=1787068888 sha256=0fee2631246203a479a48135a98a76ee9523c759c8f1fcaa041e48396f4a64d7
  ```
  Identical before Task 1 began and after cleanup.
- All logs and transcripts (`install-output.txt`, `bridge-help.txt`, `gemini-help.txt`, `clone-run-tests.txt`, `clone-hook-tests.txt`, before/after snapshots) were copied out of the scratch tree before the clone and throwaway home were deleted.

**Met.**

### Criterion 4 — Release notes name each defect 1.6.2 closes and state plainly that every existing installation must re-run the installer, with the pin only pointing forward.

**Evidence:** `README.md`'s `### 1.6.2` section (finished in plan 06-05) carries the re-run notice as its first line and 12 bullets total (six pre-existing shipped-on-branch items plus six new: five fixes plus one investigation-closure note). Verified fresh in this plan:

```
$ sed -n '/^### 1\.6\.2$/,/^### 1\.6\.1$/p' README.md | grep -c '^- '
12
$ sed -n '/^### 1\.6\.2$/,/^### 1\.6\.1$/p' README.md | grep -c 'delegate-agy-'
0
$ sed -n '/^### 1\.6\.2$/,/^### 1\.6\.1$/p' README.md | grep -c 're-run'
1
```

No ticket identifiers leaked into the public changelog. The re-run notice states the pin mechanism and its forward-only remedy in one sentence.

**Met.**

### Open for human verification

Task 1's proof runs in a throwaway `HOME` with no plugin registry present at all — the stale-pin comparison in `scripts/install.sh:150-176` degrades to silence whenever `installed_plugins.json` is missing or unreadable (that is the documented, intentional behavior for dev/test installs). A sandboxed proof can therefore never exercise the actual comparison path that runs against the operator's real `~/.claude/plugins/installed_plugins.json`.

**In your own terminal:** run the installer from the plugin directory exactly as `README.md`'s `### 1.6.2` re-run notice instructs, then run `agy-bridge --help` and `gemini --help`. Both should exit 0 and print usage.

If either instead reports `ERROR: agy-delegate <version> is installed, but this launcher is pinned to <other>. Refusing to run the stale <version> copy.` — that is the stale-pin check **working correctly**, not an install failure. Its remedy is to re-run the installer at the path the message names (or via `/agy-setup`), exactly as `scripts/install.sh:150-176`'s comparison logic and repin-command construction are designed to prompt.

**Please confirm, per criterion:**
1. Criterion 1 — does every ticket still listed by `bd list --status open` have a disposition you accept?
2. Criterion 2 — does the seven-item content check convince you the `a001d0e` revert is undone in the files, not just in history?
3. Criterion 3 — do both suite summary lines plus your own install result satisfy you?
4. Criterion 4 — does `README.md`'s `### 1.6.2` name every defect this release closes, and is the re-run requirement stated plainly enough that a skimming user acts on it?

Answer per criterion: met, or not met and why. If any criterion is rejected, the reopen mapping under "Beads Ledger" above states exactly which ticket(s) to `bd reopen` before any further work — no criterion is renegotiated and no rejection is deferred (project standing rule: a defect found at the release gate is a blocker, answered with a fix round, not a deferral).

## Next Phase Readiness

All four Success Criteria are met by the evidence above, pending the human sign-off recorded in "Open for human verification." No tag, merge, push, or release action was taken by this plan — that remains `/gsd:ship`'s job, gated on the sign-off above and the ship-time obligation that the pushed remote resolves to `GATE_SHA` (`37c9926b28c64b4ad8dd7e248cf09f8a685d016f`) before tagging.

## Known Stubs

None.

## Deviations from Plan

None — plan executed exactly as written. All three tasks' acceptance criteria were met without needing Rule 1-4 fixes.

---
*Phase: 06-ship-1-6-2*
*Completed: 2026-08-22*

## Self-Check: PASSED

- FOUND: `.planning/phases/06-ship-1-6-2/06-06-SUMMARY.md`
- FOUND: commits `776dbfd`, `d887a8f`, `875834b`, `ea3dd79`, `c6b3d68`, `6e79225`, `cbe80f1`, `aecc234` in `git log --oneline --all`
- FOUND: `bd show delegate-agy-ltf` reports `CLOSED`
- FOUND: `bd show delegate-agy-rod` reports `CLOSED`
- Task 3's automated verify: `grep -c '^## Release Gate'` → `1`, `grep -c '^### Open for human verification'` → `1`
