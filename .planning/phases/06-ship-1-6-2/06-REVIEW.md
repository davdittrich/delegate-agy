---
phase: 06-ship-1-6-2
reviewed: 2026-08-22T15:12:39Z
depth: deep
files_reviewed: 6
files_reviewed_list:
  - README.md
  - scripts/agy_bridge.sh
  - scripts/gemini_shim.sh
  - tests/contract-check.sh
  - tests/fake-agy.sh
  - tests/run-tests.sh
findings:
  critical: 1
  warning: 2
  info: 2
  total: 5
status: issues_found
---

# Phase 06-ship-1-6-2: Code Review Report

**Reviewed:** 2026-08-22T15:12:39Z
**Depth:** deep
**Files Reviewed:** 6
**Status:** issues_found

## Summary

Reviewed the shipped 1.6.2 bridge/shim pair, the operator contract-check tool, the
mocked test harness and fake-agy stub, and README against the actual code. The two
production entry points (`agy_bridge.sh`, `gemini_shim.sh`) share a duplicated
`run_bounded` implementation that is internally consistent and well-reasoned (SIGTERM
escalation, process-group-aware kill, external-kill vs. own-timeout discrimination).
Most of the exhaustively-commented reasoning in the source holds up under tracing.

One BLOCKER was found by cross-referencing `gemini_shim.sh`'s own prompt-delivery
invariant (documented in its own comments, and enforced/tested for `agy_bridge.sh`,
but never enforced or tested for the shim) against its actual `--include-directories`
handling: the shim's own inline comment claims `$WORK_DIR` is always the terminal
`--add-dir`, but the code appends `--include-directories`-derived dirs *after*
`$WORK_DIR`, breaking that invariant for exactly the call pattern (`--yolo
--include-directories <dir>`) the shim's own header names as the primary supported
Metaswarm pattern. `tests/run-tests.sh` has a regression test (`AD1`) that pins the
WORK_DIR-last invariant for the bridge's `--add-dir`, but no equivalent test exists
for the shim's `--include-directories`, so the suite is green despite the defect.

Two further WARNINGs and two INFO items are documented below.

## Critical Issues

### CR-01: gemini_shim.sh breaks its own WORK_DIR-last invariant when `--include-directories` is used, misdirecting agy's GEMINI.md auto-load

**File:** `scripts/gemini_shim.sh:642-665`

**Issue:**

Per the prompt-delivery contract documented repeatedly in this codebase (see
`tests/fake-agy.sh:4-10` and `tests/run-tests.sh:994-996`), agy auto-loads
`GEMINI.md` — and therefore the embedded `TASK:` prompt — from the directory named
by the **last** `--add-dir` (aliased with `--include-directories`) argument on its
command line. `gemini_shim.sh` embeds the actual prompt in
`$WORK_DIR/GEMINI.md` (lines 635-638) and its own comment at lines 649-650 states:

```
# WORK_DIR is re-granted last so it stays the terminal --add-dir (where GEMINI.md
# is auto-loaded), mirroring agy_bridge.sh's --sandbox …--add-dir "$WORK_DIR" order.
```

But the actual construction order is:

```
642: AGY_ARGS=(--print "$AGY_POINTER" --add-dir "$WORK_DIR")
...
652:     AGY_ARGS+=(--sandbox --add-dir "$PWD" --add-dir "$WORK_DIR")   # only if not yolo
655: [[ -n "$MODEL" ]] && AGY_ARGS+=(--model "$MODEL")
...
659:     AGY_ARGS+=(--dangerously-skip-permissions)                     # only if yolo
663: for dir in "${INCLUDE_DIRS[@]}"; do
664:     AGY_ARGS+=(--add-dir "$dir")
665: done
```

Any caller that passes `--include-directories <dir>` (or its alias
`--add-dir <dir>` is not exposed to the caller, but `--include-directories` is, per
the shim's own supported-patterns comment at lines 10-11: `Metaswarm: gemini --yolo
--output-format json --model <m> --include-directories <dir> <prompt>`) causes the
loop at 663-665 to append `--add-dir <dir>` *after* the `$WORK_DIR` grant. The
terminal `--add-dir` agy sees is now the caller-supplied directory, not `$WORK_DIR`.

Consequences for the exact Metaswarm call pattern this shim exists to support:
- If `<dir>` has no `GEMINI.md`, agy has no `TASK:` to execute — the prompt silently
  never reaches agy (the shim still reports whatever agy emits from an
  un-instructed run as a "success").
- If `<dir>` (a caller project directory — plausible in practice) happens to already
  contain its own `GEMINI.md`, agy auto-loads and executes *that* file's content
  instead of the caller's actual delegated task — the same "decoy GEMINI.md outside
  the granted work dir" failure mode that `tests/contract-check.sh`'s
  `_cc_probe_gemini_md_binds` decoy check exists specifically to catch for the
  bridge, reintroduced here for the shim via ordering, not via a missing grant.

This is untested: `tests/run-tests.sh` has `AD1` (line 991) pinning WORK_DIR-last for
the bridge's `--add-dir`, but grepping the suite for `include-directories` /
`INCLUDE_DIRS` turns up zero assertions — the shim's `--include-directories` path
has no regression coverage at all, so this ships green.

**Fix:**

Append `$WORK_DIR` unconditionally as the *last* step, after every other `--add-dir`
source (mirroring `agy_bridge.sh`'s own pattern of collecting all user dirs first,
then appending its trailing `--add-dir "$WORK_DIR"`):

```bash
AGY_ARGS=(--print "$AGY_POINTER" --add-dir "$WORK_DIR")

if [[ "$YOLO" -ne 1 && "$APPROVAL_MODE" != "yolo" ]]; then
    AGY_ARGS+=(--sandbox --add-dir "$PWD")
fi

[[ -n "$MODEL" ]] && AGY_ARGS+=(--model "$MODEL")

if [[ "$YOLO" -eq 1 || "$APPROVAL_MODE" == "yolo" ]]; then
    AGY_ARGS+=(--dangerously-skip-permissions)
fi

for dir in "${INCLUDE_DIRS[@]}"; do
    AGY_ARGS+=(--add-dir "$dir")
done

# WORK_DIR must be the terminal --add-dir so agy's GEMINI.md auto-load binds here.
AGY_ARGS+=(--add-dir "$WORK_DIR")
```

Add a regression test analogous to `AD1` (bridge) that drives the shim with
`--include-directories <dir>` and asserts (via `FAKE_AGY_DUMP_ARGV`) that the last
`--add-dir` value is `$WORK_DIR`, not the include-directories path.

## Warnings

### WR-01: gemini_shim.sh's error paths don't honor `--output-format json`, only the empty-stdout path does

**File:** `scripts/gemini_shim.sh:681-696`

**Issue:** The three early-return error branches — external-kill 137 (line 681),
own-timeout 124/137 (line 690), and generic nonzero exit (line 693) — all write
plain text to stderr and `exit` without checking `$OUTPUT_FORMAT`. Only the
empty-stdout-with-rc-0 path (line 705 onward) emits a `{"error": {...}}` JSON
envelope when `$OUTPUT_FORMAT == "json"`. `agy_bridge.sh`, by contrast, emits a JSON
envelope on every one of its equivalent error branches (137-external, 124/137-bound,
and generic-nonzero all fork on `$JSON_OUTPUT`). README's own troubleshooting table
documents this exact asymmetry as a known fact ("shim has no JSON arm branch at
all... a caller that asked shim for `--output-format json` still gets no envelope
for a timed-out call"), but documenting a gap doesn't close it: Metaswarm's adapter
is the caller that always passes `--output-format json` (per this shim's own header
comment), so a timeout or external kill during a Metaswarm-driven call hands its
JSON-expecting parser a non-JSON stderr string and empty stdout instead of a
structured error, unlike every other failure mode this shim handles.

**Fix:** Factor the JSON-envelope emission used at line 713-717 into a small helper
(e.g. `_shim_json_error MESSAGE CLASS`) and call it from all four error branches
(137-external, 124/137-timeout, generic-nonzero, and the existing empty-stdout path)
before each corresponding `exit`, so `--output-format json` behavior is uniform
across every failure mode, matching `agy_bridge.sh`'s `--json` coverage.

### WR-02: `--add-dir` broad-grant check does not cover symlink escape from a granted subdirectory

**File:** `scripts/agy_bridge.sh:398-411`

**Issue:** The `--add-dir` guard rejects only an exact `/` or exact `$HOME` (trailing
slash stripped) after `cd`-resolution, overridable via `AGY_ALLOW_BROAD_GRANT=1`.
README's own Security section names the residual gap explicitly: "stop, for
example, a symlink under a granted subdirectory that points back at `$HOME`" — i.e.
a caller can grant a narrow-looking subdirectory that contains a symlink resolving
to `$HOME` (or `/`), and the resolved-path check at grant time does not walk the
directory tree for such symlinks, only checks the grant argument itself. Enforcement
at the `--sandbox` (agy's own API-level floor) layer is the actual backstop here, but
that is an external dependency the review can't verify from this codebase, and the
gap is real and currently undetected by any test in `tests/run-tests.sh` (grepping
for `symlink` in the add-dir test section returns nothing).

**Fix:** Either accept this as a residual, `--sandbox`-mitigated risk and say so
explicitly next to the check (rather than only in the README prose), or add a
symlink-resolution walk (e.g. reject if any path component under the granted dir is
a symlink whose target resolves outside the granted dir) with a corresponding
regression test.

## Info

### IN-01: `--digest-warn-chars` threshold compares against a byte count, not a character count

**File:** `scripts/agy_bridge.sh:815-818`

**Issue:** `_resp_chars=$(wc -c < "$STDOUT_FILE" | tr -d '[:space:]')` counts bytes.
For a multibyte-UTF-8 reply (non-ASCII text, common in Gemini responses), the
byte count overstates the character count, so the digest-oversize warning can fire
earlier than the "chars" name and `--digest-warn-chars` documentation imply.

**Fix:** Either rename the flag/variable to reflect that it's a byte threshold, or
switch to a character-aware count (e.g. `wc -m`) if precise character semantics are
wanted.

### IN-02: gemini_shim.sh's `-p` flag parsing can swallow a following recognized flag as prompt text

**File:** `scripts/gemini_shim.sh:532-542`

**Issue:**

```bash
-p)
    PRINT_FLAG=1
    if [[ $# -ge 2 && -n "${2:-}" ]]; then
        PROMPT_ARGS+=("$2"); shift 2
    else
        shift
        [[ $# -ge 1 && "${1:-}" == "" ]] && shift || true
    fi ;;
```

`-p` followed by any non-empty token — including another recognized flag such as
`-o` or `--sandbox` — is treated as prompt text rather than being re-parsed as a
flag, because the branch only special-cases an explicit empty string (the
documented Octopus `-p ""` pattern). Not reachable by either documented call
pattern today (Octopus always passes `-p ""` or a real prompt value; Metaswarm
never uses `-p`), so this is latent rather than currently triggered.

**Fix:** No action required unless a new caller starts passing `-p` immediately
followed by another flag; if so, special-case values that themselves look like a
recognized flag (leading `-`) to fall through to normal flag re-parsing.

---

_Reviewed: 2026-08-22T15:12:39Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
