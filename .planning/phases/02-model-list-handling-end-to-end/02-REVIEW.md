---
phase: 02-model-list-handling-end-to-end
reviewed: 2026-08-20T13:57:20Z
depth: deep
files_reviewed: 4
files_reviewed_list:
  - scripts/agy_bridge.sh
  - scripts/gemini_shim.sh
  - tests/run-tests.sh
  - tests/fake-agy.sh
findings:
  critical: 1
  warning: 3
  info: 2
  total: 6
status: issues_found
---

# Phase 02: Code Review Report

**Reviewed:** 2026-08-20T13:57:20Z
**Depth:** deep
**Files Reviewed:** 4
**Status:** issues_found

## Summary

Reviewed the model-list cache write-gate + stale-cache fallback added to
`agy_bridge.sh` (plan 02-01) and mirrored into `gemini_shim.sh`'s
`load_models()`/`map_model()` (plan 02-02), plus the R9/R9b/R9c and
SH15/SH15b/SH15c tests that pin the mechanism, and `fake-agy.sh`'s support for
those tests.

The write-gate and stale-cache fallback themselves are correct: traced both
scripts line-by-line against every test in scope (R8, R9, R9b, R9c, SH14,
SH15, SH15b, SH15c) and the cache-poisoning gate, the byte-for-byte
preservation of a stale-but-good cache, the mtime-untouched invariant, and the
`cut -f1` normalization of extra-column/trailing-tab rows all hold. The
atomic tmp-then-`mv` write is race-free against torn reads by either script.

One real gap survived the D-08 pipefail/SIGPIPE hardening pass that this same
phase applied to the write-gate and the degraded-list use-time check: two
sibling `grep -qxF` sites reading the *same* untrusted, externally-sized model
list were deliberately left as `printf | grep -q` pipes ("a different
mechanism, not named by the user's directive" — `02-01-PLAN.md:42`,
`02-02-PLAN.md:42`). `grep -q` exits on first match regardless of `-x`/`-F`,
so the identical SIGPIPE/pipefail hazard the team empirically reproduced and
fixed at the other two sites still applies here; I re-reproduced it (6/6) on
the same class of input. It is currently dormant only because the real
model-list fixture is 744 bytes — nowhere near the ~64 KiB pipe-buffer
threshold the reproduction needed — which is exactly the "correctness that
depends on the size of agy's reply" the plan itself says this project does not
control (`02-01-PLAN.md:137`).

Also found: an unguarded `mktemp` assignment inside the reviewed fetch block
that silently kills the whole script under `set -e` if `mktemp` ever fails,
and (out of the two-mechanism scope, noted for completeness at `deep` depth) a
pre-existing flag-parser bug in `gemini_shim.sh` that can silently drop the
user's prompt.

## Critical Issues

### CR-01: `agy_bridge.sh`'s explicit `--model` validation has the same SIGPIPE/pipefail hazard the phase just fixed two lines away

**File:** `scripts/agy_bridge.sh:549`
**Issue:**
```bash
    if ! printf '%s\n' "$VALID_MODELS" | grep -qxF "$MODEL"; then
        echo "ERROR: unknown --model '${MODEL}'; run 'agy models' for valid names" >&2; exit 2
    fi
```
`grep -q` (regardless of `-x`/`-F`) exits as soon as it finds the match. If
`$VALID_MODELS` is large enough that `printf` is still writing when `grep`
closes its read end, `printf` is SIGPIPE'd (exit 141) and, under
`set -o pipefail` (line 8 of this file), the pipeline's reported status is
141 — not `grep`'s 0 — even though the model **was** found. `! pipeline` then
evaluates true and a perfectly valid, live `--model` value is rejected with a
hard `exit 2`.

This is not speculative: it is the exact hazard class the phase's own D-08 fix
(`agy_bridge.sh:483`, `:535`) was written to close, empirically reproduced by
the team at ~500 KB input with an early match (bash 5.3.15, 5/5, pipe form →
`rc=141`, herestring form → `rc=0`; `02-01-PLAN.md:133`). I re-ran the same
reproduction against `grep -qxF` specifically (6/6, `/tmp/repro_sigpipe.sh`):
```
pipe-form rc=141
herestring-form rc=0
```
repeated identically across 6 runs. The two use-time checks 14/72 lines away
were converted to the SIGPIPE-safe herestring form; this one, reading the
identical `$VALID_MODELS` variable, was deliberately left as a pipe
(`02-01-PLAN.md:42`: "does not touch `:529`'s `grep -qxF` exact-id validation
… a different mechanism, not named by the user's directive"). That reasoning
distinguishes *why the fix was scoped out*, not *why the hazard doesn't
apply* — `-x`/`-F` do not change `grep -q`'s early-exit behavior.

Currently dormant only because the real `agy models` reply is 744 bytes
(`tests/fixtures/agy-models.tsv`), far under the pipe-buffer threshold needed
to trigger it. Any future growth in agy's model catalog (more entries, longer
display-name columns) reintroduces the exact 1.6.1-incident shape this whole
phase exists to close, this time as a false "unknown --model" rejection
instead of a false-degraded verdict.
**Fix:** Mirror the sibling conversion exactly:
```bash
    if ! grep -qxF "$MODEL" <<< "$VALID_MODELS"; then
        echo "ERROR: unknown --model '${MODEL}'; run 'agy models' for valid names" >&2; exit 2
    fi
```

## Warnings

### WR-01: `gemini_shim.sh`'s live-id pass-through check has the same hazard, producing a spurious "did not resolve" warning for a valid pinned model

**File:** `scripts/gemini_shim.sh:457`
**Issue:**
```bash
    if [[ -n "$LIVE_MODELS" ]] && printf '%s\n' "$LIVE_MODELS" | grep -qxF "$m"; then
        printf '%s\n' "$m"; return 0
    fi
```
Same mechanism as CR-01 (this is `map_model`'s "is `$m` already a live id"
check, explicitly noted as untouched by D-08 — `02-02-PLAN.md:42`). If
`$LIVE_MODELS` is large enough and `$m` is an exact, already-live model id
that appears early enough in the list, the pipe can SIGPIPE `printf` and the
`&&` short-circuits to false even though the id *is* live. Unlike CR-01 this
does not hard-fail: execution falls through to class-mapping, which finds no
key for a literal id in `config/model-map.json`, so `map_model` still passes
`$m` through unchanged at the end — same final output, but only after
printing a misleading
`WARNING: model '$m' did not resolve against the agy model list; passing it
through unchanged` for a model that in fact did resolve. Since this shim
shadows `gemini` for every process on PATH, that spurious warning lands in
every caller's log. Same dormancy caveat as CR-01 (current list is 744 bytes).
**Fix:**
```bash
    if [[ -n "$LIVE_MODELS" ]] && grep -qxF "$m" <<< "$LIVE_MODELS"; then
        printf '%s\n' "$m"; return 0
    fi
```

### WR-02: Unguarded `mktemp` assignment inside the reviewed fetch block can silently kill the whole script under `set -e`

**File:** `scripts/agy_bridge.sh:474`
**Issue:**
```bash
    _agy_err="$(mktemp -t agy-models-err.XXXXXX)"
```
This is a bare assignment, not part of an `if`/`while`/`&&`/`||`. Under
`set -euo pipefail` (line 8), if `mktemp` fails for any reason (unwritable
`/tmp`, misconfigured `TMPDIR`, disk full — plausible in a locked-down
container/sandbox, which this script's own comments repeatedly say it must
survive: "systemd units without `User=`, `env -i`, container entrypoints"),
the assignment's own exit status is non-zero and `set -e` terminates the
entire script immediately, with no diagnostic — not the graceful
best-effort degradation every other line in this exact block (`mkdir -p ...
2>/dev/null || true`, the tmp-then-`mv` write, `chmod`) is careful to provide.
Verified empirically that a failing command substitution in a bare assignment
aborts under `set -e`:
```bash
set -euo pipefail
x="$(false)"   # script never reaches the next line
```
`scripts/gemini_shim.sh:572` and `scripts/agy_bridge.sh:563` (`WORK_DIR=$(mktemp
-d ...)`) share the identical pattern; pre-existing and out of this phase's
diff, noted here because it is the same class of gap immediately adjacent to
the reviewed mechanism.
**Fix:**
```bash
_agy_err="$(mktemp -t agy-models-err.XXXXXX)" || _agy_err=""
```
and guard the two downstream uses (`2>"$_agy_err"`, `[[ -s "$_agy_err" ]] &&
...`) with `-n "$_agy_err"` so a failed mktemp degrades to "no stderr capture
this run" instead of terminating the bridge.

### WR-03 (info-adjacent, out of the two-mechanism scope): `gemini_shim.sh`'s unknown-flag handling can silently swallow the actual prompt

**File:** `scripts/gemini_shim.sh:556`
**Issue:**
```bash
--[a-z]*)             [[ $# -ge 2 && "${2:-}" != -* ]] && shift 2 || shift ;;
```
Documented as "silently skip unknown flags to maximise compatibility," but
this consumes the *next* argument as the unknown flag's value whenever it
doesn't itself look like a flag. `gemini --unknown-flag "my actual prompt"`
therefore drops the prompt entirely (consumed as `--unknown-flag`'s value) and
falls through to the empty-prompt guard or, worse, to whatever `PROMPT_ARGS`
happened to already contain. Unrelated to the model-list write-gate/fallback
under review and pre-existing (not touched by 02-01/02-02); flagged because
`deep` depth extends to the whole file and this sits in the same argument
pipeline the model flag (`-m`/`--model`) is parsed from.
**Fix:** Either require `--flag=value` form for unrecognized long flags (never
consume a bare following token), or maintain an explicit allowlist of the
flags known to take a value.

## Info

### IN-01: Cache file briefly world/group-readable between `mv` and `chmod`

**File:** `scripts/agy_bridge.sh:487-489`, `scripts/gemini_shim.sh:427-429`
**Issue:** The tmp-then-`mv` write leaves the new cache file with whatever
permissions the temp file got from the process umask (typically `644`) until
`chmod 600` runs on the next line. A process killed between the `mv` and the
`chmod` (or a concurrent reader) would see the file at default permissions.
Low impact: cached content is public model IDs, not a secret.
**Fix:** `umask 077` before the temp-file write (or write via `install -m
600`), removing the window entirely.

### IN-02: Duplicated write-gate/fallback block invites drift despite "mirrors, not sources" rationale

**File:** `scripts/agy_bridge.sh:465-527`, `scripts/gemini_shim.sh:404-449`
**Issue:** Both files' comments explicitly justify duplicating (not sourcing)
this ~50-line block because the shim shadows the system `gemini` box-wide and
a missing helper would break it. That's a reasonable call given the same
shape already exists for `run_bounded`, but it does mean CR-01/WR-01 above are
now the *second* instance of "the two twin sites disagree" this phase had to
fix (the first being the SIGPIPE gap itself before D-08). Worth a standing
`grep -cF` structural-equality check (as the plans already do for the
herestring conversions) extended to cover the `grep -qxF` sites too, so a
future edit to one twin can't silently diverge from the other without a red
test.
**Fix:** No code change requested; consider adding a CI/test assertion
mirroring `02-01-PLAN.md:228`'s `grep -cF` check across both files as a
standing regression guard.

---

_Reviewed: 2026-08-20T13:57:20Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
