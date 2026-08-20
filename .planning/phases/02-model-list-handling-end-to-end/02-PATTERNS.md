# Phase 2: Model-list handling, end to end - Pattern Map

**Mapped:** 2026-08-20
**Files analyzed:** 3 (2 production, 1 test suite touched in two places + a same-file synthetic-fixture option)
**Analogs found:** 3 / 3

Note on scope: this phase modifies two existing shell scripts in place — there
are no brand-new files. The closest "analog" for each changed block is
therefore the sibling script's equivalent block (bridge <-> shim mirror each
other almost line-for-line) plus each file's own neighboring branch that
already implements the shape the new code must reuse (D-04 explicitly reuses
the existing fetch-failure fallback branch rather than adding a new one).

All line numbers below are from `.worktrees/agy-1.6.2` (branch
`fix/agy-bridge-resilience`), **not** `master`.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `scripts/agy_bridge.sh` (fetch/cache block, `:471-499`) | CLI script / cache writer | request-response + file-I/O (fetch, gate, cache, fallback) | `scripts/gemini_shim.sh`'s `load_models()` (`:404-429`) | exact (same shape, same cache file, same TTL) |
| `scripts/gemini_shim.sh`'s `load_models()` (`:404-429`) | shell function / cache writer | request-response + file-I/O | `scripts/agy_bridge.sh`'s fetch/cache block (`:471-499`) | exact |
| `tests/run-tests.sh` (new D-03/D-04/D-06 cases) | test | request-response (subprocess capture + assert) | `tests/run-tests.sh` R6/R7/R8 (bridge) and SH10/SH14 (shim) | exact |

## Pattern Assignments

### `scripts/agy_bridge.sh` fetch/cache block (`:463-519`)

**Analog:** `scripts/gemini_shim.sh`'s `load_models()` (`:404-429`) — same
cache file (`~/.cache/agy-bridge-models`), same `${HOME:-/nonexistent}`
guard, same 60-min `find -mmin +60` staleness check, same atomic
tmp-then-`mv` write, same `cut -f1` normalization. Treat the two files as
mirrors of each other; whatever shape D-03/D-04 take in one must be applied
identically in the other.

**Current shape — the exact block D-03/D-04 change** (`:463-519`):
```bash
CACHE_FILE="${HOME:-/nonexistent}/.cache/agy-bridge-models"
_agy_models=""
if [[ ! -s "$CACHE_FILE" ]] || [[ -n "$(find "$CACHE_FILE" -mmin +60 2>/dev/null)" ]]; then
    _agy_err="$(mktemp -t agy-models-err.XXXXXX)"
    if _agy_models=$(run_bounded "$AGY_MODELS_TIMEOUT" 3 -- \
                     "$AGY_BIN" models </dev/null 2>"$_agy_err"); then
        # D-03 gate goes HERE: this write is currently unconditional.
        mkdir -p "${CACHE_FILE%/*}" 2>/dev/null || true
        { printf '%s' "$_agy_models" > "$CACHE_FILE.tmp.$$" \
            && mv "$CACHE_FILE.tmp.$$" "$CACHE_FILE"; } 2>/dev/null || true
        chmod 600 "$CACHE_FILE" 2>/dev/null || true
    else
        # D-04 reuse target: the existing fetch-FAILURE fallback branch.
        _agy_rc=$?
        _agy_models=""
        if [[ "$_agy_rc" -eq 124 || "$_agy_rc" -eq 137 ]]; then
            _agy_why="timed out after ${AGY_MODELS_TIMEOUT}s"
        else
            _agy_why="exited $_agy_rc"
        fi
        if [[ -s "$CACHE_FILE" ]]; then
            echo "WARNING: 'agy models' $_agy_why; using the stale cached list." >&2
        else
            echo "ERROR: 'agy models' $_agy_why and no cached list is available." >&2
        fi
        [[ -s "$_agy_err" ]] && sed 's/^/       agy: /' "$_agy_err" >&2
    fi
    rm -f "$_agy_err"
fi
VALID_MODELS="${_agy_models:-}"
if [[ -z "$VALID_MODELS" ]]; then
    VALID_MODELS=$(cat "$CACHE_FILE" 2>/dev/null) || true
fi
[[ -n "$VALID_MODELS" ]] || { echo "ERROR: failed to retrieve model list from agy" >&2; exit 2; }
# criterion-3's normalization step D-06 proves, unchanged:
VALID_MODELS=$(printf '%s\n' "$VALID_MODELS" | cut -f1)

# criterion-3's degraded-list check — the GATE CONDITION D-03/D-04 reuse:
if ! printf '%s\n' "$VALID_MODELS" | grep -q '^gemini-'; then
    echo "ERROR: agy model list contains no 'gemini-' ids; agy may be unauthenticated" >&2
    echo "       or its 'agy models' output format changed. Run 'agy models' to inspect." >&2
    exit 2
fi
```

**What D-03/D-04 require, mechanically:** the `grep -q '^gemini-'` test at
`:515` (currently run only on the already-cached `VALID_MODELS`, post-write,
post-normalization) must additionally gate the write at `:482-483` — a
degraded `_agy_models` (successful fetch, zero `gemini-` ids after `cut -f1`)
takes the *same path* as the existing `else` (failed-fetch) branch at
`:485-499`: `_agy_models=""` so the code below falls through to the stale
`CACHE_FILE` read, and the cache file itself is left untouched (not
overwritten with the degraded reply). No new branch, no new state variable —
route the success-but-degraded case into the existing failure branch's body
(or a shared block both jump to), reusing `_agy_why`/`WARNING`/`ERROR`
messaging verbatim since the user-facing shape ("stale cache with a warning"
vs "no cache, fatal") is unchanged by D-04.

**Import/header pattern** (`:1-9`, applies to both files, no changes needed
here — cited for `set -euo pipefail` and `exec 9>&2` conventions any new
helper must respect):
```bash
#!/usr/bin/env bash
# agy_bridge.sh — Bridge for Google Antigravity CLI (agy)
...
set -euo pipefail
exec 9>&2
```

**Comment convention to preserve:** every non-obvious guard in this codebase
carries a *why*-comment immediately above it (see `:477-480`,
`:507-509`, `:512-514`). The D-03 gate needs the same treatment — state why
the check moved to write-time, not just what it does.

---

### `scripts/gemini_shim.sh`'s `load_models()` (`:404-429`)

**Analog:** `scripts/agy_bridge.sh`'s fetch/cache block above (mirror, exact
same fix shape) — and this function's own docstring at `:380-385` explicitly
says the ~20 duplicated lines are deliberate (not factored into a shared
lib because this script shadows `gemini` on PATH), so the D-03/D-04 fix must
be applied to **both** files independently, not refactored into a shared
helper.

**Current shape** (`:404-429`):
```bash
load_models() {
    local raw=""
    if [[ ! -s "$MODELS_CACHE" ]] || [[ -n "$(find "$MODELS_CACHE" -mmin +60 2>/dev/null)" ]]; then
        raw=$(run_bounded "$AGY_MODELS_TIMEOUT" 3 -- "$AGY_BIN" models </dev/null 2>/dev/null) || raw=""
        if [[ -n "$raw" ]]; then
            # D-03 gate goes HERE too: unconditional on non-empty, not on
            # having a gemini- id.
            mkdir -p "${MODELS_CACHE%/*}" 2>/dev/null || true
            { printf '%s' "$raw" > "$MODELS_CACHE.tmp.$$" \
                && mv "$MODELS_CACHE.tmp.$$" "$MODELS_CACHE"; } 2>/dev/null || true
            chmod 600 "$MODELS_CACHE" 2>/dev/null || true
        fi
    fi
    # D-04 reuse target: the existing fetch-failure/empty-raw fallback.
    [[ -n "$raw" ]] || raw=$(cat "$MODELS_CACHE" 2>/dev/null) || true
    [[ -n "$raw" ]] && printf '%s\n' "$raw" | cut -f1
    return 0
}
```

**What changes:** the `if [[ -n "$raw" ]]` write-gate (`:413`) must become
`if [[ -n "$raw" ]] && printf '%s\n' "$raw" | cut -f1 | grep -q '^gemini-'`
(or equivalent — compute the normalized id list once, reuse it both for the
gate and for the final `cut -f1` emission, since D-06 already proves `cut -f1`
is column-count-agnostic and this function performs that exact cut at
`:428`). If the check fails, `raw` must be treated as empty so the existing
`[[ -n "$raw" ]] || raw=$(cat "$MODELS_CACHE" ...)` fallback at `:427`
naturally engages — same reuse-not-duplicate shape as the bridge. Per D-05
(deferred), **no new stderr line** here — this function is silent-by-design
(`:424-426`'s comment: "a warning here would land in every Octopus/Metaswarm
log line").

---

### `tests/run-tests.sh` — new D-03/D-04/D-06 cases

**Analog (bridge, cache-poisoning + fallback shape):** R6 (`:474-483`, stale
cache used with WARNING on fetch failure), R7 (`:487-491`, no cache is
fatal), R8 (`:495-501`, degraded list reported distinctly — **and R8's own
cleanup comment at `:501-503` names the exact D-03 bug**: *"The garbage fetch
above exits 0, so the bridge caches it... Clear it so later tests still see
a full model list"* — this is the current unconditional-write behavior the
new tests must now assert is FIXED, i.e. the new test should assert the
cache file is *not* written/overwritten by a garbage fetch, replacing the
"clear it because it got poisoned" workaround).

```bash
# tests/run-tests.sh:474-503 (R6/R7/R8), the pattern to extend for D-03/D-04:
_R6_CACHE="$HOME/.cache/agy-bridge-models"
mkdir -p "$(dirname "$_R6_CACHE")"
printf '%s\t%s\n' "gemini-3.1-pro-high" "Gemini 3.1 Pro (High)" > "$_R6_CACHE"
touch -d '2 hours ago' "$_R6_CACHE"
FAKE_AGY_MODELS_FAIL=1 FAKE_AGY_STDOUT="ok" _run OUT RC bash "$BRIDGE" --type code --verbose -- "stale fallback"
if [[ "$RC" -eq 0 && "$OUT" == *"model=gemini-3.1-pro-high"* && "$OUT" == *"WARNING"* ]]; then
    ok "R6 failed fetch falls back to stale cache with a warning"
else
    bad "R6 failed fetch falls back to stale cache with a warning" "rc=$RC out=$OUT"
fi
rm -f "$_R6_CACHE"

rm -f "$HOME/.cache/agy-bridge-models"
FAKE_AGY_MODELS_GARBAGE=1 _run OUT RC bash "$BRIDGE" --type code -- "garbage list"
if [[ "$RC" -eq 2 && "$OUT" == *"no 'gemini-' ids"* && "$OUT" != *"for --type"* ]]; then
    ok "R8 model list with no gemini ids reports a degraded list, not a bad --type"
else
    bad "R8 model list with no gemini ids reports a degraded list, not a bad --type" "rc=$RC out=$OUT"
fi
```

**Analog (shim, same shape):** SH10 (`:1078-1096`, stale cache fallback,
silent — no WARNING, since the shim is silent-by-design) and SH14
(`:1168-1183`, degraded list, no false "unknown name" warning).

```bash
# tests/run-tests.sh:1084-1096 (SH10), the shim-side mirror pattern:
mkdir -p "$(dirname "$_SHIM_CACHE")"
printf '%s\t%s\n' "gemini-7.7-flash-high" "Gemini 7.7 Flash (High)" > "$_SHIM_CACHE"
touch -d '2 hours ago' "$_SHIM_CACHE"
SH10_DUMP="$SANDBOX/sh10_argv.log"
: > "$SH10_DUMP"
FAKE_AGY_MODELS_FAIL=1 FAKE_AGY_DUMP_ARGV="$SH10_DUMP" FAKE_AGY_STDOUT="ok" \
    _run OUT RC bash "$SHIM" -m flash -p x
SH10_ID="$(awk '/^--model$/{getline; print; exit}' "$SH10_DUMP")"
if [[ "$RC" -eq 0 && "$SH10_ID" == "gemini-7.7-flash-high" && "$OUT" != *"WARNING"* ]]; then
    ok "SH10 failed model fetch falls back to the stale cache, quietly"
else
    bad "SH10 failed model fetch falls back to the stale cache, quietly" "rc=$RC model=$SH10_ID out=$OUT"
fi
rm -f "$_SHIM_CACHE"
```

**New assertion CONTEXT.md calls out explicitly:** existing R8/SH14 check
only the call's *output*, not the cache file's *contents* afterward. The new
D-03 test must additionally read `$CACHE_FILE`/`$MODELS_CACHE` post-call and
assert it was NOT overwritten with the degraded reply (still holds its prior
good contents, or remains absent if there was none) — extend the R8/SH14
shape with a `cat "$_R8_CACHE"` (or `[[ ! -s ... ]]`) check, don't invent a
new harness.

**Garbage-fetch knob (reuse, don't add a second one):**
`tests/fake-agy.sh:164-168`:
```bash
if [[ -n "${FAKE_AGY_MODELS_GARBAGE:-}" ]]; then
    printf '%s\n' "Please run 'agy auth login' first." "no models available"
    exit 0
fi
```
This is exactly the "successful fetch, zero gemini- ids" shape D-03/D-04
target — already wired into both `_fake_fixture`-based `agy models` stub
call sites, no fake-agy.sh change needed.

**Test helper conventions** (`tests/run-tests.sh:91-113`):
```bash
ok() { PASS=$((PASS + 1)); printf 'ok   - %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1"; [[ $# -ge 2 ]] && printf '       %s\n' "$2"; }
_run() {  # _run OUTVAR RCVAR cmd...
    local __outvar="$1" __rcvar="$2"; shift 2
    local __out __rc
    __out="$("$@" 2>&1)"; __rc=$?
    printf -v "$__outvar" '%s' "$__out"; printf -v "$__rcvar" '%s' "$__rc"
}
```
New D-03/D-04/D-06 cases must use `_run`/`ok`/`bad` exactly as R6-R8/SH10/SH14
do — no new test framework.

---

### D-06 — synthetic 3-column normalization test

**Analog:** real fixture shape at `tests/fixtures/agy-models.tsv:4` —
`gemini-3.7-flash-high<TAB>Gemini 3.7 Flash (High)` (2 columns). D-06's
synthetic row extends this to 3 columns (`id<TAB>display name<TAB>extra`)
and must NOT be added to this file (Phase 1.5's D-14/D-14a rule: captured
fixtures vs. synthetic test payloads stay in separate files). Construct it
inline in the new test case, e.g. following the R6/SH10 pattern of writing a
literal row straight into a sandbox cache file with `printf`, or as a
standalone small fixture file under `tests/fixtures/` if a real `agy models`
subprocess call is needed rather than a pre-seeded cache. Assert `cut -f1`
resolves it identically on both `agy_bridge.sh` (`VALID_MODELS` assembly)
and `gemini_shim.sh` (`load_models()`'s `cut -f1` at `:428`) — the anchored
matchers themselves (`^gemini-[0-9.]+-flash-high$` etc.) are unchanged.

## Shared Patterns

### `${HOME:-/nonexistent}` cache-path guard + best-effort write
**Source:** `scripts/agy_bridge.sh:468`, `scripts/gemini_shim.sh:398`
**Apply to:** any new cache-adjacent code in either file — never reintroduce
a bare `$HOME`.
```bash
CACHE_FILE="${HOME:-/nonexistent}/.cache/agy-bridge-models"   # bridge
MODELS_CACHE="${HOME:-/nonexistent}/.cache/agy-bridge-models" # shim, same file
```

### Atomic tmp-then-mv cache write, stderr-suppressed
**Source:** `scripts/agy_bridge.sh:481-484`, `scripts/gemini_shim.sh:418-421`
**Apply to:** the D-03 gate — wrap the (now-conditional) write, keep this
exact shape unchanged:
```bash
mkdir -p "${CACHE_FILE%/*}" 2>/dev/null || true
{ printf '%s' "$_agy_models" > "$CACHE_FILE.tmp.$$" \
    && mv "$CACHE_FILE.tmp.$$" "$CACHE_FILE"; } 2>/dev/null || true
chmod 600 "$CACHE_FILE" 2>/dev/null || true
```

### `cut -f1` id-only normalization (column-count-agnostic)
**Source:** `scripts/agy_bridge.sh` (`VALID_MODELS` assembly, `:510`),
`scripts/gemini_shim.sh:428`
**Apply to:** the D-03 gate condition (normalize before grepping for
`^gemini-`) and D-06's synthetic-row test.
```bash
VALID_MODELS=$(printf '%s\n' "$VALID_MODELS" | cut -f1)
```

### Degraded-list detection (the gate condition D-03/D-04 reuse)
**Source:** `scripts/agy_bridge.sh:515-517`
**Apply to:** move this check (or an equivalent normalized-then-grep check)
earlier, to write-time, in both files:
```bash
if ! printf '%s\n' "$VALID_MODELS" | grep -q '^gemini-'; then
```

### Fetch-failure fallback branch (D-04's reuse target)
**Source:** `scripts/agy_bridge.sh:485-499` (bridge, WARNING-on-stale /
ERROR-on-empty), `scripts/gemini_shim.sh:427` (shim, silent)
**Apply to:** route a degraded-but-successful fetch into this same branch
rather than adding a parallel one — set the local result var (`_agy_models`
/ `raw`) empty and let existing control flow fall through unchanged.

## No Analog Found

None — both target files are self-mirroring, and every code path D-03/D-04/D-06
touch already has an adjacent, directly reusable shape in the same file or its
sibling.

## Metadata

**Analog search scope:** `.worktrees/agy-1.6.2/scripts/agy_bridge.sh`,
`.worktrees/agy-1.6.2/scripts/gemini_shim.sh`, `.worktrees/agy-1.6.2/tests/run-tests.sh`,
`.worktrees/agy-1.6.2/tests/fake-agy.sh`, `.worktrees/agy-1.6.2/tests/fixtures/agy-models.tsv`
**Files scanned:** 5 (all read in full or via targeted non-overlapping ranges; both
production scripts are < 800 lines each, read whole)
**Pattern extraction date:** 2026-08-20
</content>
