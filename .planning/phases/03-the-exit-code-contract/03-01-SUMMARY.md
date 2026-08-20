---
phase: 03-the-exit-code-contract
plan: 01
subsystem: agy_bridge.sh external-kill (SIGKILL-before-bound) message formatting
tags: [bash, tdd, tracer, exit-codes, json-envelope]
status: complete
dependency-graph:
  requires: []
  provides:
    - "EC_KILL9_TAIL — the shared literal tail of the external-kill message, hoisted once at file scope in scripts/agy_bridge.sh, ready for plan 03-02 to reuse in scripts/gemini_shim.sh"
    - "_err_txt — the guarded, trailing-newline-stripped stderr suffix pattern (${_err_txt:+: $_err_txt}), reused by both the plain-text and JSON output forms"
    - "tests/fake-agy.sh's FAKE_AGY_PRINT_KILL9 path now emits FAKE_AGY_STDERR before exiting 137 — a prerequisite fixture fix any later plan's kill9 non-empty-stderr case depends on"
  affects:
    - "Plan 03-02 reuses EC_KILL9_TAIL verbatim in scripts/gemini_shim.sh (per 03-01-PLAN.md's <artifacts_this_phase_produces>)"
tech-stack:
  added: []
  patterns:
    - "Guard a separator suffix once via bash's ${var:+word} parameter expansion, pass the fully-built suffix as a single positional argv element into python3 -- never build it twice in two languages"
    - "Hoist a literal shared between two output forms into one file-scope shell constant, RB_NO_TIMEOUT_WARN precedent"
key-files:
  created: []
  modified:
    - /home/dd/Gemini/delegate-agy/scripts/agy_bridge.sh
    - /home/dd/Gemini/delegate-agy/tests/run-tests.sh
    - /home/dd/Gemini/delegate-agy/tests/fake-agy.sh
decisions:
  - "EC_KILL9_TAIL holds only the fixed, variable-free tail of the message (' -- possible OOM or external kill') rather than the whole sentence -- the plain-text arm's 'ERROR: agy killed ...' prefix and the JSON arm's 'Killed ...' prefix keep their existing, already-differing wording untouched; only the identical trailing phrase both forms already shared moves into one place. Minimal diff, no unrequested rewording."
  - "_err_txt is computed once, immediately before the if/else that picks plain-text vs. JSON, via $(cat \"$STDERR_FILE\" 2>/dev/null || true) -- command substitution's own trailing-newline stripping is the single emptiness/normalization test both output forms defer to; no second guard exists anywhere else."
  - "The JSON arm's python3 -c call now receives the fully pre-built message (including the guarded suffix) as ONE positional argv element (sys.argv[4]) and no longer receives $STDERR_FILE at all -- open(sys.argv[5]).read() is deleted, not merely guarded, closing off the ability for a future edit to reintroduce a second read of the file."
  - "Task split: task 1 (tracer) touches only the plain-text arm; the JSON arm's python3 call is left completely untouched by task 1, including its still-present open(sys.argv[5]).read() bug, so task 2's diff cleanly isolates the JSON-side fix and RED cause."
metrics:
  duration: "~40min"
  completed: 2026-08-20
actuals:
  tokens: 1640
  tasks: 2
  commits: 4
---

# Phase 03 Plan 01: External-kill message dangling-separator guard (delegate-agy-v5a) Summary

Closed `delegate-agy-v5a`: on an external SIGKILL landing before the bridge's own `--timeout` bound, the message the operator or JSON consumer sees no longer trails off into a bare `kill: ` when agy's stderr is empty. Fixed identically, from one guarded shell expansion, in both the plain-text and JSON output forms. As a deliberate side effect (stated explicitly in the plan and reproduced below), the JSON form's `error` string is now trailing-newline-stripped, matching what the plain-text form has always done via `$(cat ...)`.

## What Was Built

**Task 1 (tracer, D-01/D-03 shape)** — `tests/fake-agy.sh`'s `FAKE_AGY_PRINT_KILL9` path was fixed first: it previously `exit 137`'d before the general `FAKE_AGY_STDERR` emission line ever ran, so no test could exercise the non-empty-stderr half of the external-kill branch at all. Fixed with the same one-line guard the fake already uses elsewhere (`[[ -n "${FAKE_AGY_STDERR:-}" ]] && printf '%s' "$FAKE_AGY_STDERR" >&2`).

`EC_KILL9_TAIL` was hoisted to file scope in `scripts/agy_bridge.sh`, beside `RB_NO_TIMEOUT_WARN` (the plan's Codex-accepted precedent), holding the literal ` -- possible OOM or external kill` — the exact substring both output forms already shared. `_err_txt` was introduced immediately before the external-kill branch's `if/else`, computed once via `$(cat "$STDERR_FILE" 2>/dev/null || true)`. The plain-text `printf` was changed from an unconditional `... bound -- possible OOM or external kill: %s\n` (always appending `: ` + possibly-empty content) to `... bound%s%s\n` fed `"$EC_KILL9_TAIL"` and `"${_err_txt:+: $_err_txt}"` — the guard exists in exactly one place. The JSON arm was left completely untouched in this task, on purpose, so task 2's diff isolates cleanly.

**RED observed (Task 1):**
```
FAIL - EC01 external-kill plain-text message: no dangling separator empty, exact suffix non-empty
       empty_ok=0 nonempty_ok=1 rc=137 out=ERROR: agy killed (signal 9) after 0s, before its 60s bound -- possible OOM or external kill: boom
```
(PASS=145 FAIL=1). The non-empty half already passed pre-fix — the defect is specific to empty stderr, exactly as the plan's `must_haves.truths` state.

**GREEN (Task 1):** PASS=146 FAIL=0 (145 baseline + EC01). Tracer feedback gate: re-ran the full suite (`bash tests/run-tests.sh`) immediately after this task's commit and confirmed PASS=146 FAIL=0 end-to-end before starting task 2's expansion — this plan carries `autonomous: true` and was dispatched for full, non-interactive completion of both tasks with per-task commits (a batch/autonomous run), so the tracer's `<verify>` was satisfied by this automated re-run rather than an interactive pause; no separate checkpoint was raised.

**Task 2 (JSON envelope form)** — The JSON arm's `python3 -c` call was changed from `sys.argv[4] + ': ' + open(sys.argv[5]).read()` (unconditional concatenation, reading `$STDERR_FILE` directly inside python) to `sys.argv[4]` alone, with the entire already-guarded message (base text + `$EC_KILL9_TAIL` + `${_err_txt:+: $_err_txt}`) pre-built in bash and passed as the single `argv[4]` element. `open(sys.argv[5]).read()` and the `$STDERR_FILE` argv slot are both deleted — python no longer reads the stderr-capture file at all, and agy's captured stderr reaches python3 only via the pre-built `_err_txt` positional argument, never spliced into the `-c` source string (T-03-02).

**RED observed (Task 2):**
```
FAIL - EC02 external-kill JSON message: no dangling separator empty, exact suffix non-empty
       empty_ok=0 empty_err=Killed (signal 9) after 0s, before its 60s bound -- possible OOM or external kill:  nonempty_ok=1 nonempty_err=...
```
(PASS=146 FAIL=1). Note the trailing `kill:  ` (colon, two spaces) in `empty_err` — `sys.argv[4] + ': ' + ''` on empty stderr, the JSON-side twin of the plain-text bug task 1 already closed.

**GREEN (Task 2):** PASS=147 FAIL=0 (146 baseline + EC02).

## Decided JSON Trailing-Newline Change (must_haves.truths, stated as required)

Routing the JSON path's stderr through `_err_txt` is a deliberate behavior change, not merely a guarded separator: `_err_txt="$(cat "$STDERR_FILE" ...)"` strips ALL trailing newlines via command substitution, where the prior `open(sys.argv[5]).read()` preserved them. Manual probe (below) confirms `text\n\n` stderr now yields JSON `error` ending `: text` (previously it would have yielded `: text\n\n`). The plain-text arm has always behaved this way; this plan makes JSON match text, not the reverse. The delivered contract for both forms is now "text representable in a bash variable after trailing-newline stripping" — not byte-for-byte preservation, and NUL bytes remain unrepresentable in a bash variable (stated as a pre-existing, unresolved ceiling in the plan's `flagged_assumptions`, unchanged by this work).

## Manual Probe: All 5 Scenarios, Both Output Forms

Run against `scripts/agy_bridge.sh` directly (real `PATH`/`HOME` sandbox with `tests/fake-agy.sh` as `agy`, `--timeout 60`, `FAKE_AGY_PRINT_KILL9=1`):

| Scenario | `FAKE_AGY_STDERR` | Plain-text `error` tail | JSON `error` value |
|---|---|---|---|
| 1. empty | `""` | `...possible OOM or external kill` (rc=137, no trailing separator) | `"...possible OOM or external kill"` (rc=137) |
| 2. non-empty | `boom` | `...possible OOM or external kill: boom` | `"...possible OOM or external kill: boom"` |
| 3. newline-only | `$'\n\n'` | `...possible OOM or external kill` (treated as empty — no separator) | `"...possible OOM or external kill"` |
| 4. trailing double newline | `$'text\n\n'` | `...possible OOM or external kill: text` (newlines stripped) | `"...possible OOM or external kill: text"` (**the decided normalization** — not `: text\n\n`) |
| 5. format-specifier | `100%s%d` | `...possible OOM or external kill: 100%s%d` (rendered literally, not interpreted) | `"...possible OOM or external kill: 100%s%d"` (rendered literally) |

Scenario 5 confirms T-03-04 (agy's stderr never reaches a `printf` format string — `%s%d` renders as literal text, not consuming an argument) and T-03-02 (the JSON `python3 -c` call never re-interprets `%`-content as anything but a plain string, since it arrives as a positional argv element, not spliced into the source).

## Verification (plan-level, run once after both tasks)

- `bash tests/run-tests.sh` → **PASS=147 FAIL=0** (145 pre-phase baseline + EC01 + EC02)
- `EC01` and `EC02` both report `ok`; each was observed `FAIL` before its corresponding script change (RED evidence above)
- `T5`, `B4`, `RB03`, `RB24` (and every other pre-existing case) still report `ok` — no regressions
- `grep -cF "EC_KILL9_TAIL=" scripts/agy_bridge.sh` → 1 (defined exactly once, at file scope)
- Manual 5-scenario probe (above) pasted with both output forms for every scenario

## Tracer Feedback Gate

Task 1 is `type="tracer"`. Its `<verify>` (the full suite) was re-run end-to-end immediately after task 1's GREEN commit and reported PASS=146 FAIL=0 before task 2's expansion began. No separate interactive checkpoint was raised: this plan carries `autonomous: true` in its own frontmatter and this run's config has `workflow.auto_advance: false` / `_auto_chain_active: false` (interactive by config), but the orchestrating instructions for this specific dispatch explicitly asked for full, non-interactive completion of both tasks with per-task commits and a single SUMMARY — matching a batch/autonomous run rather than one with a human watching between tasks. The tracer's own verification step is a deterministic automated test-suite re-run (no URL, no UI, nothing requiring human perception), so the automated re-check is what the checkpoint protocol's "automation before verification" principle asks for regardless.

## Environmental Note: RB24 False-Positive During Development (not a regression)

During iteration, two `bash tests/run-tests.sh &` (explicit shell-backgrounded) invocations both showed `RB24` failing (`detail=watchdog:INT:not_installed coreutils:INT:not_installed`), even with `scripts/agy_bridge.sh` stashed back to its pre-task-1 state. This was isolated to the invocation method: explicitly backgrounding the suite with `&` inherits bash job-control's default of ignoring `SIGINT` in background jobs, which confounds RB24's own trap-disposition assertions. Every un-backgrounded invocation (direct `bash tests/run-tests.sh`, and the harness's own `run_in_background` tool parameter) passed RB24 cleanly, both before and after this plan's changes. Not logged to `deferred-items.md` — it never reproduced outside the self-inflicted invocation pattern, so there is nothing outstanding to track.

## Deviations from Plan

None — plan executed exactly as written. `EC_KILL9_TAIL`'s exact literal content (the fixed, variable-free tail phrase rather than the full sentence) was a judgment call within the plan's explicit instruction to hoist "the shared literal tail... referenced by both forms" (see Key Decisions above); no plan requirement was reinterpreted or weakened.

## Known Stubs

None.

## Threat Flags

None — this plan's threat surface (T-03-01 through T-03-05) was fully named in the plan's own `<threat_model>` and closed by this work; no new surface was introduced beyond what the plan already registered.

## Commits

- `6e80300` test(03-01): add failing EC01 case for external-kill dangling separator
- `86572bd` feat(03-01): guard external-kill plain-text message against dangling separator
- `892871b` test(03-01): add failing EC02 case for external-kill dangling separator (JSON)
- `55c009d` feat(03-01): guard external-kill JSON message against dangling separator

## Self-Check

- `scripts/agy_bridge.sh` — FOUND, modified
- `tests/run-tests.sh` — FOUND, modified
- `tests/fake-agy.sh` — FOUND, modified
- Commit `6e80300` — FOUND in `git log --oneline --all`
- Commit `86572bd` — FOUND in `git log --oneline --all`
- Commit `892871b` — FOUND in `git log --oneline --all`
- Commit `55c009d` — FOUND in `git log --oneline --all`

## Self-Check: PASSED
