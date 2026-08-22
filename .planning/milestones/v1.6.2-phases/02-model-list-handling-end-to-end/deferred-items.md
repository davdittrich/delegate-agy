# Deferred Items — Phase 02

Out-of-scope discoveries found during execution, not fixed per the
SCOPE BOUNDARY rule (only auto-fix issues directly caused by the current
task's changes).

## RB24 intermittent flake (found during 02-03 fix round)

**Test:** `RB24 (unit) a bounded call leaves the host's TERM, INT and HUP traps
exactly as it found them, on both mechanisms`
**File:** `tests/run-tests.sh`
**Observed:** Intermittently fails in isolation (no other concurrent process),
roughly every other full-suite run during the 02-03 fix round (5 runs: 1 clean
pass, 4 failures).
**Confirmed pre-existing:** Reproduced on `a7ab6bd` (the tip of plan 02-02,
before any 02-03 change) via `git archive a7ab6bd` into a scratch directory —
same intermittent failure, unrelated to any of the 4 fixes in this round
(CR-01, WR-01, WR-02, IN-01 touch `--model` validation, `map_model`'s live-id
check, the stderr-capture `mktemp`, and the cache-write `umask` — none of
which touch `run_bounded`'s trap save/restore).
**Not fixed here:** Out of this fix round's scope (not caused by any of the 4
reviewed findings). Worth its own investigation — likely a timing race in the
trap save/restore around `run_bounded`'s two mechanisms, not a data-dependent
bug.
