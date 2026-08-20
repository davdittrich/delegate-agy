---
status: complete
phase: 01-the-missing-timeout-decision
source: [01-01-SUMMARY.md, 01-02-SUMMARY.md, 01-03-SUMMARY.md, 01-04-SUMMARY.md, 01-05-SUMMARY.md, 01-06-SUMMARY.md]
started: 2026-08-20T09:02:14Z
updated: 2026-08-20T09:24:05Z
---

<!--
Coverage-aware classification note (#1602): each *-SUMMARY.md's own coverage
block was classified independently via `uat.classify-coverage`, then
cross-checked by hand against every OTHER summary in the phase, since a
plan's own coverage block can only cite what was true when IT was written —
not what a later plan in the same phase went on to commit. Five entries that
their own summary marked human_judgment (present) are recorded here as
automated pass instead, because a later plan's SUMMARY shows the exact same
claim now pinned by a committed, passing regression test:

  - 01-01 D5 -> covered by 01-06 D5 (RB09a, RB09b)
  - 01-01 D6 -> covered by 01-06 D6 (RB11)
  - 01-02 D5 -> covered by 01-05 D4 (RB08)
  - 01-02 D8 -> covered by 01-05 D1+D2 (RB01/RB01m, RB02/RB02m)
  - 01-04 D2 -> covered by 01-05 D3 (RB03)

01-06 D8 (README env-var section + PROJECT.md Key Decisions, re-asserted as
phase criteria 3 and 1) is a duplicate of 01-04 D1 and 01-04 D3 — confirmed
against 01-06's key-files list, which touches only tests/run-tests.sh and
tests/fake-agy.sh, not README.md or PROJECT.md. Merged into tests 15 and 17
below rather than presented a second time.

01-03 (bridge bounding convergence) contributed no coverage block (legacy,
internal refactor) and no separately testable user-observable deliverable —
its behavior is exactly what 01-01 D1 and 01-06 D1/D2 already assert (both
entry points bounded, with and without coreutils). Included in `source`
since it was reviewed, but adds no Test entry.

Test 29 (macOS job-control notice) was explicitly accepted rather than
tested — no macOS host was available. `uat-passed`'s predicate has no
distinct "accepted" result state, so this is recorded as `result: pass`
with `accepted_risk: true` and the evidence field stating plainly it was
not independently verified, mirroring SECURITY.md's disposition:accept
pattern (T-01-09) so the acceptance is auditable, not silently disguised
as a real check. User decision, 2026-08-20.
-->

## Current Test
<!-- OVERWRITE each test - shows where we are -->

[testing complete]

## Tests

### 1. No-timeout shim delegation returns 124 and reaps the fake plus its fork (D1)
expected: With no timeout/gtimeout reachable on PATH, a real gemini shim delegation to an agy that ignores SIGTERM and has forked a SIGTERM-ignoring child returns 124 within its bound, and neither the fake nor its forked child is alive afterwards.
result: pass
source: automated
coverage_id: 01-01-D1

### 2. Sanitized PATH still resolves a full shim delegation with no timeout/gtimeout (D2)
expected: The sanitized PATH resolves neither timeout nor gtimeout, yet is complete enough to run a full shim delegation end to end.
result: pass
source: automated
coverage_id: 01-01-D2

### 3. Forking fake's child outlives a direct-PID kill of the parent (D3)
expected: The forking fake agy ignores SIGTERM and its forked child outlives a direct-PID kill of the parent — the shape that distinguishes a process-group kill from a direct-child kill.
result: pass
source: automated
coverage_id: 01-01-D3

### 4. run_bounded's PGID extraction matches `ps`
expected: |
  `_rb_pgid_of` prints a bare digit string, byte-equal to `ps -o pgid= -p $$`
  with every non-digit removed. Not yet regression-guarded — verify by hand.
result: pass
verified_by: agent
evidence: |
  Extracted _rb_pgid_of from scripts/gemini_shim.sh:104-137 into an ad-hoc
  driver (set -euo pipefail), same technique 01-01/01-03's own probes used.
  Three cases, all byte-identical to `ps -o pgid= -p $PID | tr -d '[:space:]'`:
  a background child (sleep 30, pid 200108 -> pgid 200093), the driver's own
  $$ (pid 201572 -> pgid 201550), and a second child spawned via `exec -a`
  (pid 201573 -> pgid 201550; comm came back "sleep", not a two-word name --
  exec -a doesn't rewrite /proc/pid/comm, so this run didn't exercise that
  specific edge case, but the core byte-equality claim held in all 3 runs).
  Still not committed as a regression test (matches the summary's own note).

### 5. No mechanism-aware branch escapes the marked block; kill marker stays off caller stdio (D5, upgraded)
expected: Neither the kill marker nor the self-kill-guard warning reaches the caller's captured stdout or stderr; both land on fd 9, and the child's own stdout/stderr still reach the capture files.
result: pass
source: automated
coverage_id: 01-01-D5
note: "Marked present/human_judgment in 01-01-SUMMARY.md; upgraded to automated — now pinned by 01-06's RB09a/RB09b (D5, status pass)."

### 6. run_bounded refuses invalid bounds and empty commands (D6, upgraded)
expected: run_bounded refuses an empty, zero, or non-numeric bound and a call with no command, returning 2 and running nothing.
result: pass
source: automated
coverage_id: 01-01-D6
note: "Marked present/human_judgment in 01-01-SUMMARY.md; upgraded to automated — now pinned by 01-06's RB11 (D6, status pass)."

### 7. No-timeout models fetch degrades to pass-through instead of hanging (D1)
expected: With no timeout/gtimeout reachable on PATH, the agy models fetch is abandoned at its own bound and the shim degrades to pass-through rather than hanging.
result: pass
source: automated
coverage_id: 01-02-D1

### 8. No-timeout hung --version exits 124 at its bound (D2)
expected: With no timeout/gtimeout reachable on PATH, a hung --version exits 124 after its 10-second bound with the existing message.
result: pass
source: automated
coverage_id: 01-02-D2

### 9. No-timeout stdin read exits 2 at its bound (D3)
expected: With no timeout/gtimeout reachable on PATH, a stdin read that never sees EOF exits 2 at its bound with the existing message.
result: pass
source: automated
coverage_id: 01-02-D3

### 10. AGY_MODELS_TIMEOUT=0 is corrected, not rejected (D4)
expected: AGY_MODELS_TIMEOUT=0 is corrected rather than rejected AND the fetch stays bounded on the watchdog path.
result: pass
source: automated
coverage_id: 01-02-D4

### 11. No new stderr noise when a bounding binary resolves (D5, upgraded)
expected: On a host where a bounding binary resolves, nothing new reaches stderr on any path.
result: pass
source: automated
coverage_id: 01-02-D5
note: "Marked present/human_judgment in 01-02-SUMMARY.md; upgraded to automated — now pinned by 01-05's RB08 (D4, status pass)."

### 12. JSON envelope is byte-identical regardless of warning (D6)
expected: The JSON envelope is byte-for-byte what it was, warning or no warning.
result: pass
source: automated
coverage_id: 01-02-D6

### 13. Warning appears on stderr exactly once, ahead of bounded output (D7)
expected: On a host resolving neither binary, the warning appears on stderr exactly once per run however many bounded calls that run makes, and is the first line on stderr.
result: pass
source: automated
coverage_id: 01-02-D7

### 14. No mechanism-aware branch outside the marked block; block untouched (D8, upgraded)
expected: No mechanism-aware branch remains outside the marked block, and the marked block is untouched.
result: pass
source: automated
coverage_id: 01-02-D8
note: "Marked present in 01-02-SUMMARY.md (schema validation_failed on its own verification entry); upgraded to automated — now pinned by 01-05's RB01/RB01m and RB02/RB02m (D1+D2, status pass)."

### 15. README documents no-bounding-binary behavior for both entry points (D1)
expected: |
  README states both entry points' behaviour on a host with no bounding
  binary, together and with the reason — a reading check, not a grep.
  (Also stands in for 01-06 D8's README half: no README changes landed
  after 01-04, confirmed against 01-06's key-files list.)
result: pass

### 16. Both scripts' warning literal quoted verbatim in README (D2, upgraded)
expected: Both script literals quoted verbatim in README; the unreachable ERROR row replaced by the warning now emitted.
result: pass
source: automated
coverage_id: 01-04-D2
note: "Marked present/verification_not_passing in 01-04-SUMMARY.md (RB03 not yet written at the time); upgraded to automated — now pinned by 01-05's RB03 (D3, status pass)."

### 17. PROJECT.md's Key Decisions record is adequate (D3)
expected: |
  PROJECT.md Key Decisions records "always bounded" with rationale;
  superseded rows resolved — is the rationale adequate for a future
  reader, not just present?
  (Also stands in for 01-06 D8's PROJECT.md half: no PROJECT.md changes
  landed after 01-04, confirmed against 01-06's key-files list.)
result: pass

### 18. delegate-agy-cy5 stays open with its resolution note (D4)
expected: delegate-agy-cy5 carries a resolution note saying none of its three designs was chosen, and stays open.
result: pass
source: automated
coverage_id: 01-04-D4

### 19. Every agy invocation is a run_bounded argument, zero exceptions (D1)
expected: Every agy invocation in both scripts is a run_bounded argument, enforced over the files with zero exceptions and a non-vacuity floor.
result: pass
source: automated
coverage_id: 01-05-D1

### 20. The two run_bounded blocks are byte-identical (D2)
expected: The two duplicated run_bounded blocks are byte-identical and non-empty; a one-sided edit fails the suite.
result: pass
source: automated
coverage_id: 01-05-D2

### 21. Warning literal defined once, matches README, reversed claims can't ship (D3)
expected: Both scripts define the warning literal once with identical bytes, README quotes both literals verbatim, and the reversed claims (deleted startup fatal, "unbounded") cannot come back into what ships.
result: pass
source: automated
coverage_id: 01-05-D3

### 22. Each entry point warns exactly once, ahead of bounded output (D4)
expected: Each entry point warns exactly once per coreutils-less run, ahead of any bounded output, and never when a bounding binary resolves.
result: pass
source: automated
coverage_id: 01-05-D4

### 23. Both entry points bound a SIGTERM-ignoring, forking agy, no-timeout (D1)
expected: With no timeout/gtimeout on PATH, both entry points bound an agy that ignores SIGTERM and has forked, returning 124 and leaving neither process alive (phase criterion 2).
result: pass
source: automated
coverage_id: 01-06-D1

### 24. Both entry points bound the same adversarial fake with coreutils present (D2)
expected: With a bounding binary present, the same holds on both entry points against the same adversarial fake (phase criterion 4, runtime half).
result: pass
source: automated
coverage_id: 01-06-D2

### 25. Descendant guarantee holds with and without a controlling terminal (D3)
expected: The descendant guarantee holds identically without and with a controlling terminal, with the allocator's argument form flavour-probed and both branches pinned, and the terminal itself proven.
result: pass
source: automated
coverage_id: 01-06-D3

### 26. Bridge reaches its own argument handling instead of exiting 2 at startup (D4)
expected: With no bounding binary the bridge reaches its own argument handling instead of exiting 2 at startup (D-03).
result: pass
source: automated
coverage_id: 01-06-D4

### 27. No helper diagnostic leaks into caller stdio; kill marker still emitted (D5)
expected: No helper diagnostic reaches the caller's stdout, the JSON error payload (whose key set is unchanged), or the bounded call's own stderr — while the kill marker is still proven emitted on the entry point's own stderr.
result: pass
source: automated
coverage_id: 01-06-D5

### 28. run_bounded's boundary, adjacency, refusal, argument-boundary contracts (D6)
expected: run_bounded's boundary, adjacency, refusal and argument-boundary contracts pinned by driving the extracted helper directly.
result: pass
source: automated
coverage_id: 01-06-D6

### 29. macOS: no job-control notice on missing coreutils (D7)
expected: |
  On a stock macOS with no coreutils, gemini on a PATH lacking
  timeout/gtimeout emits the RB_NO_TIMEOUT_WARN literal and nothing
  resembling a shell job-control notice (e.g. no "[1]+ Terminated" line).
  No macOS host was available during development — this is the one
  assumption the suite could not settle. No macOS host? Reply "skip" or
  "blocked" — known gap, not a regression.
result: pass
accepted_risk: true
evidence: |
  NOT independently verified — explicitly accepted, not tested. No macOS
  host available to this project (dev host and this session's host are
  both Linux). Mirrors SECURITY.md's disposition:accept pattern (same
  rationale class as T-01-09): the underlying mechanism (bash job-control
  suppression via `disown`/foreground-group handling) is the same code
  path already exercised on Linux by RB06a-d, RB08, and RB25 — only the
  macOS-specific absence of a shell job-control line is unverified. User
  (2026-08-20) explicitly chose "accept the gap" over waiting for a
  macOS host, to unblock phase completion. If this assumption is ever
  found false on a real macOS host, it is a regression against this
  accepted call, not a fresh unknown.

## Summary

total: 29
passed: 29
issues: 0
pending: 0
skipped: 0
blocked: 0
accepted_risks: 1

## Gaps

[none yet]
