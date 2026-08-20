---
phase: 03-the-exit-code-contract
plan: 04
subsystem: tests/run-tests.sh exact-exit-code + failure-payload-shape regression coverage (EC07, EC08); REQUIREMENTS.md R5/R6 closure
tags: [bash, tests, exit-codes, json-envelope, mutation-testing, requirements-traceability]
status: complete
dependency-graph:
  requires:
    - "EC_KILL9_TAIL, EC01-EC06, and the RB03/EC05/EC06 provenance+runtime-pin shape (plans 03-01/03-02/03-03) -- EC07 reuses the same T4/T5/SH6/EC06 provocation invocations verbatim rather than inventing new fixtures"
    - "I16 (:3840-ish, `-eq 127`/`-z \"$OUT_STALE\"`) and RB29 (:4167-ish, `-eq 127`/`-z \"$RB29_SOUT\"`) -- cited by EC07's four source assertions rather than re-provoked"
  provides:
    - "EC07 -- every documented exit code (2, 3, 124, 137) provoked and asserted by exact numeric value (2 bridge-only), cause-fragment exclusivity held across the four bridge-captured messages, plus four source assertions pinning that I16/RB29's exit-127 citation and its empty-stdout negative half have not rotted, plus two source assertions pinning the 137-vs-124 strict elapsed<bound comparison and the error branch's fixed arm order"
    - "EC08 -- R6's exit-3 failure payload proven never success-shaped on both entry points and both output modes: zero-byte stdout in text mode (measured via `wc -c` on a split-captured file, never a command substitution), a response-free/non-truthy-success JSON envelope parsed with a real JSON parser; plus the one-newline-byte-is-not-empty round-trip pinned in all four output shapes"
    - "_ec_run_split -- a stdout/stderr split-capture test helper, introduced because the suite's own `_run` merges both streams via `2>&1` and would make EC08's zero-byte-stdout assertion pass unconditionally"
    - "R5 and R6 traceability rows in REQUIREMENTS.md moved to `met`, R5's row naming the integer-second `SECONDS`-precision ceiling as a residue rather than reading as unqualifiedly closed; delegate-agy-v5a and delegate-agy-6q1 closed in bd with evidence"
  affects:
    - "Phase 6's release gate reads REQUIREMENTS.md's traceability table; R5 and R6 now read `met` with their residues/evidence stated inline rather than `partial`"
tech-stack:
  added: []
  patterns:
    - "Self-referential source assertion: EC07 greps tests/run-tests.sh itself (via escaped-regex ERE patterns whose raw source text differs from the plain literal target text) to pin that I16 and RB29's exit-127 citations have not rotted -- a technique this phase had not needed before, since EC05/EC06 only ever grepped the two shipped scripts and README, never their own file"
    - "Split-capture over merged capture for byte-exact zero-checks: _ec_run_split (new) captures stdout/stderr to separate files read back with `wc -c`, purpose-built because the suite's default `_run` (`2>&1` merge) would make a zero-byte-stdout assertion vacuous whenever agy's own stderr is non-empty"
    - "Provenance-plus-mutation-red satisfies tdd=\"true\" for an already-correct shipped behavior (EC05/EC06 precedent, plans 03-02/03-03): three deliberate, git-status-tracked, single-hunk mutations (one per case's load-bearing property), each observed to fail in isolation and reverted by rewriting the exact line back -- never git checkout/restore/reset/stash"
key-files:
  created: []
  modified:
    - /home/dd/Gemini/delegate-agy/tests/run-tests.sh
    - /home/dd/Gemini/delegate-agy/.planning/REQUIREMENTS.md
decisions:
  - "EC07's cause-fragment exclusivity check is scoped to the bridge's four captured messages (137/124/3/2), not all seven runtime invocations (bridge x4 + shim x3) -- the bridge is the only entry point that reaches all four codes, and the plan's must_haves name 'four captured messages', not seven."
  - "Exit 127 is cited via four source assertions, not two: the two Codex-named `-eq 127` pins (I16/RB29 citation-exactness) plus two more pinning the negative half (`-z \"$OUT_STALE\"` / `-z \"$RB29_SOUT\"`) that the plan's must_haves describe as 'likewise cited... and likewise pinned' -- read as a fourth must-have bullet distinct from the review-disposition's 'two source assertions' headline, which named only the exactness half of the Codex HIGH finding it was fixing."
  - "The four self-referential grep patterns in EC07 are written with escaped ERE metacharacters (`\\]\\]`, `\\|\\|`, `\\[\\[`, `\\$`) rather than as plain fixed-string literals -- the escaped source text never contiguously spells the plain target text it searches for, so the grep invocation's own line can never inflate its own 'exactly once' count. Verified empirically: the full suite run after adding EC07 showed `ok` with an empty detail string, meaning the count landed at exactly 1, not 2."
  - "EC08's --output-format flag is placed before -p on the shim invocation (`bash \"$SHIM\" --output-format json -p ...`), matching the suite's existing S3/S4 call convention rather than the trailing-flag order used elsewhere in this file, for consistency with the one other place the suite drives shim JSON mode."
  - "Task 1 (EC07) and Task 2 (EC08) were implemented in a single Edit pass for efficiency, then split into two commits by temporarily removing the EC08 block, committing EC07 alone, re-inserting EC08 byte-for-byte, and committing it separately -- preserving one-commit-per-task traceability to each task's own bd id (delegate-agy-byv.9, delegate-agy-byv.10) without any destructive git operation."
metrics:
  duration: "~1h"
  completed: 2026-08-21
actuals:
  tokens: 5324
  tasks: 3
  commits: 3
---

# Phase 03 Plan 04: EC07/EC08 exact-exit-code and failure-payload-shape regression coverage; R5/R6 closure Summary

Closed the two coverage gaps `delegate-agy-v5a`/`delegate-agy-6q1` and Phase 3's own objective named: `EC07` provokes and asserts the exact numeric value of exit codes 2, 3, 124 and 137 (127 cited via `I16`/`RB29` with its citation itself pinned against rot), and `EC08` proves R6's exit-3 failure payload can never become success-shaped on either entry point or output mode. Both cases passed immediately on first run — the underlying behavior was already correct from plans 03-01 through 03-03 and earlier phases — so each case's `tdd="true"` gate was satisfied via three deliberate, git-status-tracked mutations (one for EC07's strictness pin, two for EC08's two load-bearing properties), each observed to fail in isolation and reverted byte-for-byte. `REQUIREMENTS.md` moves R5 and R6 to `met`, with R5's row naming the integer-second `SECONDS`-precision ceiling as a stated residue rather than an implied closure, and both bd tickets are closed with evidence.

## What Was Built

**Task 1 (`delegate-agy-byv.9`, tdd) — `EC07`:** added to `tests/run-tests.sh`, provoking and asserting:

| Code | Entry point(s) | Mechanism | Fragment checked |
|---|---|---|---|
| 137 | bridge + shim | `FAKE_AGY_PRINT_KILL9=1`, well inside `--timeout 60` / `GEMINI_SHIM_TIMEOUT=60` | `killed` (bridge only, exclusivity loop) |
| 124 | bridge + shim | `FAKE_AGY_PRINT_HANG=1`, `--timeout 1` / `GEMINI_SHIM_TIMEOUT=1` | `timeout after` (bridge only) |
| 3 | bridge + shim | `FAKE_AGY_EXIT=0 FAKE_AGY_STDOUT="" FAKE_AGY_STDERR="ec07 boom"` | `empty output` (bridge only) |
| 2 | bridge only | `FAKE_AGY_MODELS_GARBAGE=1`, cache cleared before/after (R8 pattern) | `no 'gemini-' ids` (bridge only) |

Cause-fragment exclusivity (`_ec07_excl`) checked over the bridge's four captured messages: each contains its own fragment and none of the other three — a timeout is never reported as a kill, an empty output never as a timeout, a degraded list never confused with either.

Exit 127 is **not** provoked — it is cited via four source assertions against `tests/run-tests.sh` itself: two pin that `I16` and `RB29` still assert `-eq 127` exactly (the Codex HIGH finding's fix), two more pin that their stale-run stdout-empty assertions (`-z "$OUT_STALE"`, `-z "$RB29_SOUT"`) are still present. All four patterns are written with escaped ERE metacharacters so the grep invocation's own source line can never satisfy the pattern it searches for (verified empirically — the case passed with an empty detail string, meaning every count landed at exactly 1).

Two additional source assertions: the 137-vs-124 discrimination's strict `"$DURATION" -lt "$TIMEOUT"` / `"$SHIM_TIMEOUT"` comparison (present exactly once per script, no `-le` variant anywhere), and the error branch's fixed arm order (early-137, then 124-or-137, then generic-nonzero, then empty-stdout — verified by line-number ascension in both scripts).

**Task 2 (`delegate-agy-byv.10`, tdd) — `EC08`:** added `_ec_run_split` (stdout/stderr captured to separate files, read back via `wc -c` rather than a command substitution) because the suite's `_run` merges both streams via `2>&1`, which would make a zero-byte-stdout assertion pass unconditionally. `EC08` then pins:

1. Zero-byte stdout + empty stderr → the fixed fallback sentence `agy returned empty output (exit 0, no stdout)`, in all four shapes (bridge text/JSON, shim text/JSON). JSON shapes parsed with `python3 -c` `json.load` and asserted `"response" not in d`, `not d.get("success")`, correct `error`/`error_class` (bridge) or `error.message`/`error.class` (shim).
2. A stdout of exactly one newline byte (`FAKE_AGY_STDOUT=$'\n'`) is **not** empty: `rc=0`, `wc -c` reports exactly 1 byte, and the byte round-trips through all four output shapes (bridge's `cat`/`open().read()` preserve it directly; the shim's `RESPONSE=$(cat ...)` strips it and `printf '%s\n' "$RESPONSE"` restores it — verified as the actual emitted byte, not assumed).

**Task 3 (`delegate-agy-byv.11`, non-tdd) — `REQUIREMENTS.md`:** R5 and R6 traceability rows moved from `partial`/provisional to `met`. R5's row states EC07's four-provoked/one-cited coverage explicitly and names `edge:R5/precision` (integer-second `SECONDS` truncation) as a residue this work does not close, rather than reading as unqualified. R6's row states EC08's evidence and its mutation-red proof. `delegate-agy-v5a` and `delegate-agy-6q1` closed in `bd` with evidence citing the plans and cases that fixed and regression-pinned each.

## Mutation-Red Proof (three mutations, per plan prohibition)

`git status --porcelain` captured before the first mutation: only `tests/run-tests.sh` dirty (this plan's own additions). Captured again after the last revert: identical.

1. **EC07 strictness (edge:R5/adjacency).** `scripts/agy_bridge.sh:726` `-lt "$TIMEOUT"` → `-le "$TIMEOUT"`. Full suite: `PASS=152 FAIL=1`, isolated to `EC07` alone. Reverted by rewriting the exact line back; `git diff scripts/agy_bridge.sh` empty.
2. **EC08 zero-byte-stdout (T-03-13).** `scripts/agy_bridge.sh`'s exit-3 branch: inserted `printf '\n'` before `exit 3`. Full suite: `PASS=152 FAIL=1`, isolated to `EC08` alone. Reverted; `git diff` empty.
3. **EC08 no-response-key (T-03-12).** `scripts/agy_bridge.sh`'s exit-3 JSON dict literal: added `'response':''`. Full suite: `PASS=152 FAIL=1`, isolated to `EC08` alone. Reverted; `git diff` empty.

Each mutation touched exactly one hunk, was reverted by rewriting that hunk back (never `git checkout`/`restore`/`reset`/`stash`), and no mutation left any trace in the final diff (`git diff scripts/agy_bridge.sh` empty throughout).

## Verification (plan-level, run after all three tasks)

- `bash tests/run-tests.sh` → **PASS=153 FAIL=0** (151 baseline after plan 03-03 + EC07 + EC08), re-confirmed after the split-commit reconstruction (Task 1/Task 2 committed separately from one combined edit)
- `EC07` and `EC08` both report `ok`, empty detail strings
- Every documented exit code defended by an exact assertion: 2/3/124/137 via `EC07`, 127 via `I16`/`RB29` with `EC07`'s citation pin
- `EC07`'s `ok`/`bad` label states four provoked codes and one cited code; never claims five provoked
- `git status --porcelain` matched exactly before the first mutation and after the last revert
- No pre-existing case changed status or text (`git diff --stat` on `scripts/agy_bridge.sh` and `scripts/gemini_shim.sh` empty at the end of this plan)
- `delegate-agy-v5a` and `delegate-agy-6q1` closed in `bd` with evidence

## Deviations from Plan

**Commit granularity (mechanical, not substantive).** Task 1 (`EC07`) and Task 2 (`EC08`) were written in a single `Edit` pass for efficiency, then split into two commits by temporarily removing the `EC08` block from the file, committing `EC07` alone, re-inserting `EC08` byte-for-byte (verified via line count and a re-run of the full suite), and committing it separately. This preserves the plan's one-commit-per-task convention and each task's bd-id traceability (`delegate-agy-byv.9`, `delegate-agy-byv.10`) without any destructive git operation. No test content differs between the combined and split forms — the final `tests/run-tests.sh` is identical either way.

**Exit-127 citation pin count (4, not 2).** The plan's `review_dispositions` headline names "two source assertions" for the Codex HIGH finding (the `-eq 127` exactness pins). The plan's `must_haves.truths` fourth bullet separately describes the negative half (`-z "$OUT_STALE"` / `-z "$RB29_SOUT"`) as "likewise cited... and likewise pinned." Read literally, this is a distinct must-have requiring its own pin, not a restatement of the exactness pin. EC07 implements all four as source assertions rather than only the two named in the review-disposition headline, so no bullet in `must_haves.truths` is left unaddressed.

No other deviations — plan executed as written.

## Known Stubs

None.

## Threat Flags

None. This plan's threat surface (`T-03-12` through `T-03-15`, `T-03-05`) is fully named in the plan's own `<threat_model>` and closed by this work: `T-03-12` (spoofable success-shaped failure payload) and `T-03-13` (`EC08` going vacuous through a merged capture) both closed by `EC08`'s split-capture mechanism and mutation-red proof; `T-03-14` (suite wall-clock growth) accepted per plan, bounded to the same 2s bound `T4`/`SH4` already use; `T-03-15` (an over-claiming requirement row) closed by Task 3's explicit residue statement; `T-03-05` (package supply chain) n/a — no dependency added.

## Commits

- `9e3b53e` test(03-04): add EC07 pinning every documented exit code to its exact value
- `dfcb04d` test(03-04): add EC08 pinning the exit-3 payload as never success-shaped
- `027a89b` docs(03-04): close R5/R6 in REQUIREMENTS.md traceability, close v5a/6q1

## Self-Check

- `tests/run-tests.sh` — FOUND, modified (EC07 + EC08 present, suite green)
- `.planning/REQUIREMENTS.md` — FOUND, modified (R5/R6 rows `met`)
- `scripts/agy_bridge.sh` — FOUND, unmodified (`git diff` empty; mutation-red proofs all reverted)
- `scripts/gemini_shim.sh` — FOUND, unmodified
- Commit `9e3b53e` — FOUND in `git log --oneline --all`
- Commit `dfcb04d` — FOUND in `git log --oneline --all`
- Commit `027a89b` — FOUND in `git log --oneline --all`
- `delegate-agy-v5a` — FOUND, CLOSED in `bd show`
- `delegate-agy-6q1` — FOUND, CLOSED in `bd show`

## Self-Check: PASSED
