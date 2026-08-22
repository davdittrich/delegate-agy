---
phase: 03-the-exit-code-contract
plan: 03
subsystem: README troubleshooting table (exit 2/3/124 rows + generic-nonzero divergence note); tests/run-tests.sh provenance/runtime pin (EC06); exit-2 message consistency audit (agy_bridge.sh, read-only)
tags: [bash, docs, provenance, exit-codes, json-envelope, audit]
status: complete
dependency-graph:
  requires:
    - "EC_KILL9_TAIL and the RB03/EC05 provenance-pin pattern (plan 03-02) — reused verbatim by this plan's EC06 for four new literals"
    - "The generic-nonzero dangling-separator guard on the bridge's plain-text arm (plan 03-02) — read (not modified) to write the divergence note's Axis A/B description"
  provides:
    - "README's exit-2/3/124 troubleshooting rows now quote byte-for-byte message shapes, name the three exit-3 class values, and state where the bridge's and shim's JSON envelopes diverge in shape"
    - "A generic-nonzero divergence note (bridge-vs-shim prefix; bridge text-vs-JSON newline-stripping), the third gap the phase's objective named"
    - "EC06 — a provenance + runtime pin covering four literals (_EC_EMPTY_OUTPUT_LITERAL, _EC_TIMEOUT_TEXT_LITERAL, _EC_TIMEOUT_JSON_LITERAL, _EC_DEGRADED_LITERAL) across both scripts and README, plus runtime cross-entry agreement for exit-3 and exit-124's text form, plus all three exit-3 classifier outcomes"
    - "A recorded, per-site consistency verdict for every exit-2 call site in agy_bridge.sh (D-09), with delegate-agy-b7g's disposition stated explicitly and left for Phase 6"
  affects:
    - "Plan 03-04 (delegate-agy-byv.9, EC07) inherits the same four literals and the exit-2 verdict table as its baseline for asserting every documented exit code by exact value"
tech-stack:
  added: []
  patterns:
    - "Provenance pin over FOUR literals in one case (RB03/EC05 shape extended to a batch), each with its own per-script/per-README assertion rather than one shared literal papering over two different forms (Codex HIGH finding, corrected: exit-124's divergence is bridge-text-vs-bridge-JSON, not bridge-vs-shim)"
    - "Runtime agreement check layered on top of static provenance: static grep proves the literal is IN the file; a driven run through both entry points with identical stderr/bound proves the ASSEMBLED line is byte-identical, closing the gap static-only pinning can't reach for a runtime-computed reason/class/bound"
    - "D-09 site-by-site audit against four fixed questions (ERROR: prefix? names the specific value? confusable with a sibling? narrower than its condition?) recorded as a verdict table, not a blanket pass/fail — the default outcome is no code change, with the one exception (delegate-agy-b7g) already ticketed and left in place"
key-files:
  created: []
  modified:
    - /home/dd/Gemini/delegate-agy/README.md
    - /home/dd/Gemini/delegate-agy/tests/run-tests.sh
decisions:
  - "README's exit-124 row quotes BOTH the shared text-form literal (byte-identical in agy-bridge and the gemini shim) and the bridge-only JSON literal, framed explicitly as a within-the-bridge (text-vs-JSON) divergence, not a bridge-vs-shim one — correcting the pre-review draft's premise per the plan's own review_dispositions."
  - "The generic-nonzero divergence note covers two independent axes in one paragraph rather than two rows: bridge-vs-shim (prefix present or absent) and, within the bridge itself, text-vs-JSON (the text arm's stderr is trailing-newline-stripped since plan 03-02's fix; the JSON arm's is not, because it still reads $STDERR_FILE directly via open().read())."
  - "EC06's exit-3 and exit-124 runtime agreement checks drive BOTH entry points with the exact same stderr/bound and compare the emitted lines for byte-identity, rather than comparing each against a hand-written expected string — the same non-tautological shape EC03 established in plan 03-02."
  - "EC06's mutation-red proof follows plan 03-02's EC05 precedent exactly: a git-status-tracked, one-character mutation of the real file (scripts/agy_bridge.sh's degraded-list literal, 'unauthenticated' -> 'unauthenticatd'), reverted by rewriting the exact line — never git checkout/restore/reset/stash. This satisfies task 2's tdd=\"true\" flag via the provenance-pin mechanism the plan's own Alternatives Considered section pre-authorized, since the literals pinned were already correct (from task 1 and prior plans) and there was no missing implementation to drive a conventional pre-fix RED."
  - "Task 3's D-09 audit found zero inconsistencies among the 25 exit-2 call sites and recorded one already-known gap (delegate-agy-b7g, line 537) with an explicit left-for-another-phase disposition, per the plan's own default-no-change expectation. scripts/agy_bridge.sh's committed diff for this plan is empty (git diff --stat scripts/agy_bridge.sh reports nothing) — the mutation-red proof for EC06 touched the file only transiently and was reverted byte-for-byte before any commit."
  - "Line 396's --add-dir 'is not a directory' message was judged NOT a Q4 finding despite `cd` failing for three distinct OS-level reasons (missing path, wrong type, permission denied): all three route the operator to the identical corrective action (supply a valid, accessible directory), unlike delegate-agy-b7g's category confusion between an auth-degraded response and an outright fetch failure. Left unchanged."
metrics:
  duration: "~1h10min"
  completed: 2026-08-21
actuals:
  tokens: 3072
  tasks: 3
  commits: 2
---

# Phase 03 Plan 03: README exit-2/3/124 restatement + EC06 provenance pin + exit-2 consistency audit (D-09) Summary

Closed the three documentation gaps `delegate-agy-6q1`'s phase exists to end: README's exit-3 row now quotes the message it summarised before, the exit-124 row now quotes both timeout literals it was silent on, and a new divergence note names the generic-nonzero bridge-vs-shim and bridge-text-vs-JSON splits the table never mentioned. `EC06` pins all four touched literals (empty-output prefix, timeout text, timeout JSON, degraded-list) across both scripts and README with both static provenance and runtime cross-entry agreement, proven non-vacuous by a git-status-tracked one-character mutation. Task 3's D-09 pass read every exit-2 call site in `agy_bridge.sh` and found the messages already consistent; the one known gap (`delegate-agy-b7g`) is recorded with an explicit disposition rather than silently fixed or silently skipped. `scripts/agy_bridge.sh`'s final diff for this plan is empty, matching the plan's own default-no-change prohibition.

## What Was Built

**Task 1 (`delegate-agy-byv.6`)** — README's troubleshooting table restated:
- **Exit code 2 row:** kept the single existing exemplar (the degraded-model-list message), and added that only `agy-bridge` emits it — `the gemini shim has no matching check and degrades quietly on the same input instead`.
- **Exit code 124 row:** now quotes `` `ERROR: agy timeout after <N>s` `` (byte-identical in `agy-bridge` and the `gemini` shim) AND the bridge-only JSON literal `` `"error": "Timeout after <N>s"` ``, explicitly stating the shim has no JSON arm for that branch at all — corrected per the plan's own re-read of Codex's finding: the divergence is text-vs-JSON WITHIN the bridge, not bridge-vs-shim (the two entry points' TEXT forms are byte-identical, just constructed differently — `printf %d` vs. inline expansion).
- **Exit code 3 row:** now quotes `` `ERROR: agy returned empty output [<class>]: <reason>` `` (byte-identical in both scripts), names all three class values (`quota`, `auth`, `empty_output`), and states the two entry points' JSON envelopes are shaped differently: the bridge's is a flat `{"success":false,...,"error":...,"error_class":...}`, the shim's nests `{"error":{"message":...,"class":...}}`.
- **New divergence note** beneath the table for generic (undocumented) nonzero exits: Axis A (bridge-vs-shim) — the bridge prefixes `ERROR: agy exit <N>: `, the shim relays agy's raw stderr with no prefix; Axis B (bridge text-vs-JSON) — the JSON arm carries agy's stderr alone with no `ERROR: agy exit <N>` context, and (since plan 03-02) the text arm's stderr is trailing-newline-stripped while the JSON arm's is not.
- Exit-127 rows were read-only verified against `scripts/install.sh:134-135` and `:161-162` and found to already match (see Verification below) — left untouched, no Phase-4 finding needed.
- `grep -ic 'unbounded' README.md` → `0`; `git diff --exit-code scripts/install.sh` → clean (unchanged).

**Task 2 (`delegate-agy-byv.7`, tdd)** — `EC06` added to `tests/run-tests.sh`, pinning four literals:

| Literal | Value | Bridge | Shim | README |
|---|---|---|---|---|
| `_EC_EMPTY_OUTPUT_LITERAL` | `ERROR: agy returned empty output [` | present | present | present |
| `_EC_TIMEOUT_TEXT_LITERAL` | `ERROR: agy timeout after ` | exactly 1 (comment-filtered) | exactly 1 (comment-filtered) | present |
| `_EC_TIMEOUT_JSON_LITERAL` | `Timeout after ` | exactly 1 (comment-filtered) | exactly 0 | present |
| `_EC_DEGRADED_LITERAL` | `agy model list contains no 'gemini-' ids; agy may be unauthenticated` | exactly 1 (comment-filtered) | exactly 0 | present |

Plus runtime checks: exit-3 driven on both entry points with identical `FAKE_AGY_STDERR="boom"` — byte-identical emitted lines; the exit-3 classifier driven through all three class values (`RESOURCE_EXHAUSTED`-bearing → `[quota]`, `UNAUTHENTICATED`-bearing → `[auth]`, neither → `[empty_output]`); exit-124's text form driven on both entry points via `FAKE_AGY_PRINT_HANG=1` with a 1s bound (`--timeout 1` / `GEMINI_SHIM_TIMEOUT=1`) — byte-identical emitted lines; exit-124's JSON form driven on the bridge alone — confirmed the literal `"error": "Timeout after 1s"` actually reaches the emitted envelope, not just the source file.

**First run (all literals already correct from task 1 + prior plans):** `PASS=151 FAIL=0` — EC06 passed immediately, since nothing in this plan's scope required a code fix (no pre-existing implementation gap to drive a conventional RED).

**Mutation-red proof (manual, one-time, per the plan's cross-plan prohibition):**
1. `git status --porcelain` captured before mutation: only `tests/run-tests.sh` dirty (this plan's own task-2 addition; `scripts/agy_bridge.sh` clean).
2. `scripts/agy_bridge.sh:547`'s degraded-list literal mutated by one character: `unauthenticated` → `unauthenticatd`.
3. Full suite re-run: **PASS=150 FAIL=1** — only `EC06` failed, detail `bridge:degraded_count_0`. Not vacuous, and correctly isolated (no other case depends on that trailing word).
4. Reverted by rewriting the exact line back (never `git checkout`/`restore`/`reset`/`stash`). `git diff scripts/agy_bridge.sh` after revert: empty.
5. `git status --porcelain` captured again: identical to step 1's capture.
6. Full suite re-run: **PASS=151 FAIL=0**.

**Task 3 (`delegate-agy-byv.8`, D-09, non-tdd)** — every `exit 2` occurrence in `scripts/agy_bridge.sh` read and given a recorded verdict (26 rows total: 25 call sites + 1 usage-text comment, matching `grep -c 'exit 2' scripts/agy_bridge.sh` exactly). Judged against four questions: (1) starts with `ERROR: `? (2) names the specific offending flag/value/file? (3) confusable with a sibling exit-2 message? (4) narrower than the condition that reaches it?

### Exit-2 Verdict Table

| Line | Message | Verdict |
|---|---|---|
| 21 | `ERROR: agy not found in PATH (expected at ~/.local/bin/agy)` | consistent |
| 44 | `ERROR: AGY_MODELS_TIMEOUT must be a positive integer` | consistent |
| 378 | `ERROR: --type requires a value` | consistent |
| 381 | `ERROR: --model requires a value` | consistent |
| 384 | `ERROR: --timeout requires a value` | consistent |
| 385 | `ERROR: --timeout must be a positive integer` | consistent |
| 388 | `ERROR: --stdin-timeout requires a value` | consistent |
| 389 | `ERROR: --stdin-timeout must be a positive integer` | consistent |
| 392 | `ERROR: --log-file requires a value` | consistent |
| 395 | `ERROR: --add-dir requires a value` | consistent |
| 396 | `ERROR: --add-dir '$2' is not a directory` | consistent: Q4 judged explicitly — `cd -- "$2"` can fail for three OS-level reasons (missing path, wrong type, permission denied); the message names only the middle one, but all three route the operator to the same corrective action (supply a valid, accessible directory), unlike delegate-agy-b7g's category confusion between two operationally different failure classes. Not fixed. |
| 404 | `ERROR: --add-dir '$_d' grants broad filesystem access; set AGY_ALLOW_BROAD_GRANT=1 to override` | consistent |
| 413 | `ERROR: --digest-warn-chars requires a value` | consistent |
| 414 | `ERROR: --digest-warn-chars must be a positive integer` | consistent |
| 440 | *(usage-text comment: "refused with exit 2 unless AGY_ALLOW_BROAD_GRANT=1")* | not a call site — accurately describes the behavior of the :404 site |
| 458 | `ERROR: unknown flag: $1` | consistent |
| 467 | `ERROR: unknown --type '${TYPE_SAFE}'; expected search\|code\|review\|analysis\|implement` | consistent |
| 537 | `ERROR: failed to retrieve model list from agy` | **left for another phase: delegate-agy-b7g** — fires whenever `$VALID_MODELS` is empty after fetch+cache fallback, which includes BOTH a genuine fetch failure AND a zero-byte/empty successful reply with no cache; the narrower degraded-list message at :547 needs a non-empty-but-`gemini-`-less list, so a truly empty reply never reaches it. Exit code and cache-untouched behavior are already correct; the fix belongs in the model-fetch control flow (Phase 2 surface, requirement S1), not in message text. ROADMAP.md's Phase 6 gate already holds this ticket. |
| 547 | `ERROR: agy model list contains no 'gemini-' ids; agy may be unauthenticated` / `or its 'agy models' output format changed. Run 'agy models' to inspect.` | consistent |
| 558 | `ERROR: no gemini model for --type '$TYPE' in agy models` | consistent |
| 561 | `ERROR: unknown --model '${MODEL}'; run 'agy models' for valid names` | consistent |
| 592 | `ERROR: policy file missing: $_POLICY_FILE` | consistent |
| 604 | `ERROR: stdin read timed out after ${STDIN_TIMEOUT}s` | consistent |
| 607 | `ERROR: no prompt (no stdin, no -- args)` | consistent |
| 611 | `ERROR: empty prompt` | consistent: Q3 judged explicitly — distinguishable from :607 (fires when nothing was supplied at all: no stdin AND no `--` args) vs. :611 (fires when something was supplied but reduced to nothing after whitespace-trimming); not confusable |
| 648 | `ERROR: failed to embed prompt into GEMINI.md` | consistent |

**Result:** 25/26 rows `consistent` (the 26th is the :440 comment, not a call site), 1 row `left for another phase: delegate-agy-b7g`. No site changed. `git diff --stat scripts/agy_bridge.sh` at the end of this plan is **empty** — the DEFAULT outcome the plan names, confirmed rather than assumed.

`bd comment delegate-agy-byv` recorded the pass's outcome on the phase's tracking issue (epic), per this repository's convention of using `bd comment` rather than a standalone file.

## Exit-127 Read-Only Verdict

Re-checked README's two exit-127 rows against the generated launcher's own text in `scripts/install.sh` (not edited by this plan, per prohibition):

| README row (quoted key phrase) | `scripts/install.sh` source | Match |
|---|---|---|
| `` `agy-delegate moved or was updated` `` (wrapper fails loud) | `:135` `echo "ERROR: agy-delegate moved or was updated; '\$_AGY_TARGET' is gone." >&2` | substring match — README's key phrase is a byte-for-byte substring of the emitted line |
| `` `ERROR: agy-delegate ... is installed, but this launcher is pinned to ...` `` | `:161` `echo "ERROR: agy-delegate \$_agy_active is installed, but this launcher is pinned to \$_AGY_VERSION." >&2` | match — README's `...` placeholders correctly stand in for the interpolated `$_agy_active` and `$_AGY_VERSION` |

Both rows already matched; no Phase-4 finding recorded, no README edit made for exit-127. `git diff --exit-code scripts/install.sh` confirmed clean throughout this plan.

## Verification (plan-level, run once after all three tasks)

- `bash tests/run-tests.sh` → **PASS=151 FAIL=0** (150 pre-phase baseline + EC06)
- `EC06` reports `ok`; observed `FAIL` (mutation-red, non-vacuous, isolated to EC06 alone) before its revert (evidence above)
- `grep -ic 'unbounded' README.md` → `0`
- Every exit-code message README quotes is present byte-for-byte in the script(s) that emit it, including both timeout literals, each checked against the script(s) that actually emit it and `Timeout after ` checked ABSENT from the shim (EC06's static assertions)
- `git diff --stat scripts/agy_bridge.sh` → empty (task 3 made no production change)
- `scripts/install.sh` → unchanged throughout (`git diff --exit-code scripts/install.sh` clean)
- The exit-2 verdict table above is complete (26/26 `grep -n 'exit 2'` hits accounted for exactly once) and `delegate-agy-b7g`'s disposition is explicit

## Deviations from Plan

None — plan executed exactly as written. Task 2's `tdd="true"` flag was satisfied via the provenance-pin/mutation-red mechanism the plan's own `<execution_context>` Alternatives Considered section pre-authorized (matching plan 03-02's `EC05` precedent), rather than a conventional pre-fix RED, because the literals pinned were already correct before EC06 existed (from task 1's README edits and prior plans' shipped code) — there was no missing implementation to drive a traditional RED-before-GREEN cycle. This is the same judgment call plan 03-02 already made and documented for `EC05`, not a new interpretation.

Line 396's `--add-dir` message was considered as a possible Q4 finding (a `cd` failure collapses three distinct OS-level causes into one message naming only one of them) and judged NOT a finding, with the reasoning recorded explicitly in the verdict table rather than silently passed over, per the task's instruction to state an answer per site rather than a blanket "all fine."

## Known Stubs

None.

## Threat Flags

None — this plan's threat surface (T-03-07 through T-03-11) was fully named in the plan's own `<threat_model>` and closed by this work; no new surface was introduced beyond what the plan already registered. T-03-10 (editing `scripts/install.sh` while "just fixing a row") is confirmed closed by the read-only verification above; T-03-11 (an exit-2 site rewritten with no finding behind it) is confirmed closed by the empty `git diff --stat scripts/agy_bridge.sh`.

## Commits

- `25880e8` docs(03-03): restate exit-2/3/124 rows and add generic-nonzero divergence note
- `94fb465` test(03-03): add EC06 pinning exit-2/3/124 literals across both scripts and README

(Task 3 made no code change and required no commit; its outcome is recorded in this SUMMARY's verdict table and via `bd comment` on `delegate-agy-byv`.)

## Self-Check

- `README.md` — FOUND, modified
- `tests/run-tests.sh` — FOUND, modified
- `scripts/agy_bridge.sh` — FOUND, unmodified (git diff empty, as expected)
- Commit `25880e8` — FOUND in `git log --oneline --all`
- Commit `94fb465` — FOUND in `git log --oneline --all`

## Self-Check: PASSED
