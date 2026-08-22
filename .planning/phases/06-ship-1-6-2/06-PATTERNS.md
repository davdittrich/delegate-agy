# Phase 6: Ship 1.6.2 - Pattern Map

**Mapped:** 2026-08-21
**Files analyzed:** 6 (modified) + 1 (read-only verification target)
**Analogs found:** 6 / 6 — every analog is same-file, sibling code. This is a closed bash-CLI bug-fix/release-gate phase with no new frameworks; the closest pattern for each fix is always the surrounding code in the same file, never a cross-file abstraction.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|-----------------|---------------|
| `scripts/gemini_shim.sh` (D-04) | controller (CLI argv dispatcher) | request-response | same file, sibling `case` arms lines 569 & 572 | exact (same file, same construct) |
| `scripts/agy_bridge.sh` (D-07) | service (model-fetch/cache) | request-response | same file, R9's existing degraded-list message, lines 509-510 & 547-548 | exact (same file, same message-routing convention) |
| `scripts/agy_bridge.sh` (D-08) | service (bounded-execution helper) | request-response | same file, `run_bounded`'s own coreutils arm (lines 241-260, no trap manipulation) + save block (lines 330-335) it must mirror in reverse | exact (same function, statement-order fix) |
| `tests/run-tests.sh` (D-05 new case) | test | assertion | same file, `IN01` cross-file structural-equality block, lines 1591-1599 | exact (same shape, same file) |
| `tests/run-tests.sh` (D-06 loop widen) | test | assertion | same file, `RB01`'s own loop line 2372 + `RB01m` mutation-proof block lines 2412-2436 | exact (extend existing loop, reuse existing mutation-proof pattern) |
| `tests/run-tests.sh` (D-08 forcing test) | test | assertion | same file, `RB24` block lines 2074-2133 | exact (same file, same test being repaired) |
| `tests/run-tests.sh` (D-04/D-07 new cases) | test | assertion | same file, `ok`/`bad` helpers lines 91-102 + `_run` helper line 105+ | exact (standard harness idiom) |
| `tests/contract-check.sh` (D-06 guard restructure) | test-side script (static-scan target) | request-response | same file, the 7 sibling `if [[ -z "$AGY_BIN" ]]; then` guards, lines 527, 565, 600, 644, 698, 829, 1008 | exact (self-referential — restructure all 7 identically) |
| `README.md` (D-09) | docs | — | same file, existing `### 1.6.2` bullets, lines 407-414 | exact (same section, same bullet style) |
| `.planning/PROJECT.md` (D-02, D-03) | docs | — | same file, `## Key Decisions` table rows, lines 69-83 | exact (same table, same row shape) |

**Not modified, read-only verification target:** `scripts/install.sh` (D-10) — CONTEXT.md and RESEARCH.md both confirm D-06/D-08 touch no shared helper it sources; no analog needed, no code change.

---

## Pattern Assignments

### `scripts/gemini_shim.sh` — D-04 (unknown-long-flag branch)

**Analog:** same file, the two sibling catch-all arms that already do it correctly.

**Current buggy code** (`scripts/gemini_shim.sh:568-572`, verified read this session):
```bash
        # Silently skip unknown flags to maximise compatibility
        --no-*)               shift ;;
        --[a-z]*)             [[ $# -ge 2 && "${2:-}" != -* ]] && shift 2 || shift ;;
        --)                   shift; PROMPT_ARGS+=("$@"); break ;;
        -*)                   shift ;;
```
Line 570 is the only arm in this `case` that conditionally consumes a second token. Its two neighbors (`--no-*` at 569, `-*` at 572) never do — that is the analog to copy.

**Fix, matching the sibling arms' shape exactly:**
```bash
        --[a-z]*)             shift ;;   # never consume next token; unknown flags ignored, not "eaten with value"
```

**Why this is provably safe (read this session, `gemini_shim.sh:508-528`):** every currently-known flag that legitimately takes a separate value (`-m`/`--model`, `-o`/`--output-format`, `--approval-mode`, `--include-directories`) already has its own explicit `case` arm earlier in the same statement (lines 508-528), each guarded by `[[ $# -lt 2 ]] && { echo "ERROR: $1 requires a value" >&2; exit 2; }` before its own `shift 2`. Bash's first-match `case` semantics mean none of those ever reach line 570 — this catch-all only ever fires for genuinely unrecognized flags, so CONTEXT.md's "except an explicit allowlist of flags already known to take a separate value" carve-out currently has zero members. No allowlist array needed today.

**Auth/error pattern reused by every value-taking arm above** (copy this shape if a future flag ever needs the allowlist):
```bash
        -m|--model)
            [[ $# -lt 2 ]] && { echo "ERROR: $1 requires a value" >&2; exit 2; }
            MODEL="$2"; shift 2 ;;
```

---

### `scripts/agy_bridge.sh` — D-07 (degraded-empty-reply message)

**Analog:** same file, R9's existing degraded-list message path — reuse the message text and the "defer to existing exit choke point" convention, do not add a new `exit`.

**Current code, exact structure** (`scripts/agy_bridge.sh:490-511`, verified read this session):
```bash
        _agy_ids="$(printf '%s\n' "$_agy_models" | cut -f1)"
        if grep -q '^gemini-' <<< "$_agy_ids"; then
            mkdir -p "${CACHE_FILE%/*}" 2>/dev/null || true
            { ( umask 077; printf '%s' "$_agy_models" > "$CACHE_FILE.tmp.$$" ) \
                && mv "$CACHE_FILE.tmp.$$" "$CACHE_FILE"; } 2>/dev/null || true
            chmod 600 "$CACHE_FILE" 2>/dev/null || true
        elif [[ -s "$CACHE_FILE" ]]; then
            # Treat a degraded-but-successful fetch like a fetch failure for
            # THIS call (D-04): fall back to the stale cache read below rather
            # than delegating off a garbage list. The cache file itself is
            # never touched here, so its mtime -- and the TTL window -- stay
            # exactly as they were.
            echo "WARNING: 'agy models' returned a list with no 'gemini-' ids (agy may be unauthenticated); using the stale cached list." >&2
            _agy_models=""
        fi
```
Bug: on a truly zero-byte, no-cache reply, neither the `if` nor the `elif` fires — no `else` exists — so it falls straight through to the generic bail two blocks later, dropping diagnostic specificity.

**Stderr passthrough that must keep running unconditionally after this block** (`scripts/agy_bridge.sh:526-528`):
```bash
    # Relocated (not duplicated): agy's own stderr is the only diagnostic for
    # an auth/network fault ... It now fires unconditionally whenever agy wrote anything ...
    [[ -n "$_agy_err" && -s "$_agy_err" ]] && sed 's/^/       agy: /' "$_agy_err" >&2
    [[ -n "$_agy_err" ]] && rm -f "$_agy_err"
fi
```
This is why the fix must NOT `exit` inside the `if/elif` block — that would skip this passthrough. Set a flag instead, consumed at the existing single choke point below.

**Existing generic-bail choke point to extend, not replace** (`scripts/agy_bridge.sh:537`):
```bash
[[ -n "$VALID_MODELS" ]] || { echo "ERROR: failed to retrieve model list from agy" >&2; exit 2; }
```

**The exact message text to reuse verbatim** — already exists twice in this file (the degraded-with-cache warning at line 509, and R9's degraded-with-no-fallback error at lines 547-548):
```bash
# scripts/agy_bridge.sh:547-548 — the message D-07's fix must reach for the no-cache case too
    echo "ERROR: agy model list contains no 'gemini-' ids; agy may be unauthenticated" >&2
    echo "       or its 'agy models' output format changed. Run 'agy models' to inspect." >&2
```

**Recommended patch (from RESEARCH.md, verified against current line numbers this session):**
```bash
# add sibling else to the existing if/elif, right before its closing fi (line 511):
        elif [[ -s "$CACHE_FILE" ]]; then
            echo "WARNING: 'agy models' returned a list with no 'gemini-' ids (agy may be unauthenticated); using the stale cached list." >&2
            _agy_models=""
        else
            # D-07 (delegate-agy-b7g): rc=0 but no gemini- ids and no cache to
            # fall back on. Not "fetch failed" -- fetch succeeded and returned
            # nothing usable. Defer to the exit at line 537; the stderr
            # passthrough two lines below still runs on this path.
            _agy_degraded_no_cache=1
        fi

# change the generic bail at line 537 from:
[[ -n "$VALID_MODELS" ]] || { echo "ERROR: failed to retrieve model list from agy" >&2; exit 2; }
# to (reusing the exact R9 message text from lines 547-548):
if [[ -z "$VALID_MODELS" ]]; then
    if [[ "${_agy_degraded_no_cache:-0}" -eq 1 ]]; then
        echo "ERROR: agy model list contains no 'gemini-' ids; agy may be unauthenticated" >&2
        echo "       or its 'agy models' output format changed. Run 'agy models' to inspect." >&2
    else
        echo "ERROR: failed to retrieve model list from agy" >&2
    fi
    exit 2
fi
```

**`gemini_shim.sh` needs no change for D-07** — confirmed reading `load_models()`: its `[[ -n "$raw" ]]` guard already skips the whole degraded-detection block on a truly-empty raw reply, falling straight to the cache read, which already matches the shim's own established (already-fixed) `SH15`/`SH15b` behavior.

---

### `scripts/agy_bridge.sh` — D-08 (`run_bounded` trap save/restore race)

**Analog:** same function, the coreutils arm just above (which never touches traps at all) proves the watchdog arm's trap dance is optional complexity, not load-bearing structure — and the save block (lines 330-335) is the mirror this fix must restore-before-cancel against.

**Full current watchdog-arm trap sequence** (`scripts/agy_bridge.sh:330-343`, verified read this session, byte-identical in `gemini_shim.sh` per `RB02`'s own check):
```bash
    rb_trap_term="$(trap -p TERM)"
    rb_trap_int="$(trap -p INT)"
    rb_trap_hup="$(trap -p HUP)"
    trap '_rb_relay TERM 143' TERM
    trap '_rb_relay INT 130' INT
    trap '_rb_relay HUP 129' HUP

    _rb_start_timer "$secs" TERM
    wait "$child" 2>/dev/null || rc=$?
    _rb_cancel_timer "$timer" "$timer_pgid"
    trap - TERM INT HUP
    eval "${rb_trap_term:-}"
    eval "${rb_trap_int:-}"
    eval "${rb_trap_hup:-}"
```

**Coreutils arm, for contrast — proves the fix direction is sound** (`scripts/agy_bridge.sh:241-260`): never calls `trap -p`, `trap`, or `eval` at all. The watchdog arm's whole trap save/restore exists only to give the host back exactly what it had before, once the bounded command has already finished.

**Recommended fix (RESEARCH.md, `[ASSUMED]` root cause, verified line numbers this session — reorder so restore happens before the signal-sending cancel call):**
```bash
    _rb_start_timer "$secs" TERM
    wait "$child" 2>/dev/null || rc=$?
    trap - TERM INT HUP                 # restore/disarm BEFORE cancel-timer's signal
    eval "${rb_trap_term:-}"
    eval "${rb_trap_int:-}"
    eval "${rb_trap_hup:-}"
    _rb_cancel_timer "$timer" "$timer_pgid"   # moved last
```
Must apply this identically in both `scripts/agy_bridge.sh` (lines 337-343) and `scripts/gemini_shim.sh`'s copy of the same block (RB02 asserts byte-identity between the two — breaking that assertion is a regression, not a variant fix).

---

### `tests/run-tests.sh` — D-05 (new twin-site structural-equality case)

**Analog:** same file, `IN01`'s existing cross-file structural-equality block — copy this exact shape for the new `grep -qxF` twin-site check.

**Exact analog to copy** (`tests/run-tests.sh:1591-1599`, verified read this session):
```bash
IN01_BRIDGE_PATTERN=$'( umask 077; printf \'%s\' "$_agy_models" > "$CACHE_FILE.tmp.$$" )'
IN01_SHIM_PATTERN=$'( umask 077; printf \'%s\' "$raw" > "$MODELS_CACHE.tmp.$$" )'
IN01_BRIDGE="$(grep -cF "$IN01_BRIDGE_PATTERN" "$BRIDGE")" || IN01_BRIDGE=0
IN01_SHIM="$(grep -cF "$IN01_SHIM_PATTERN" "$SHIM")" || IN01_SHIM=0
if [[ "$IN01_BRIDGE" -eq 1 && "$IN01_SHIM" -eq 1 ]]; then
    ok "IN01 the cache-file write is umask-guarded in both scripts, closing the perm window (IN-01)"
else
    bad "IN01 the cache-file write is umask-guarded in both scripts, closing the perm window (IN-01)" \
        "bridge_guard_count=$IN01_BRIDGE shim_guard_count=$IN01_SHIM"
fi
```

**The two twin sites this new case targets** (`[VERIFIED: grep -n session]`):
```bash
scripts/agy_bridge.sh:560:  grep -qxF "$MODEL" <<< "$VALID_MODELS"
scripts/gemini_shim.sh:471:  grep -qxF "$m" <<< "$LIVE_MODELS"
```

**Precedent D-05's own decision text points to explicitly — the herestring-count single-file check** (`tests/run-tests.sh:625-627`, this is what `IN01` generalized to two files):
```bash
R9D_PIPE="$(grep -cF '"$VALID_MODELS" | grep -qxF "$MODEL"' "$BRIDGE")" || R9D_PIPE=0
R9D_HERE="$(grep -cF 'grep -qxF "$MODEL" <<< "$VALID_MODELS"' "$BRIDGE")" || R9D_HERE=0
```
Its byte-identical twin against `$SHIM` is at `tests/run-tests.sh:1575-1578` (`SH15D_PIPE`/`SH15D_HERE`). D-05 adds a presence-count assertion in the `IN01` shape; it does not touch `R9d`/`SH15d`.

---

### `tests/run-tests.sh` (D-06 loop widen) + `tests/contract-check.sh` (D-06 guard restructure)

**Analog for the loop widen:** the loop itself, one token change.

**Current** (`tests/run-tests.sh:2372`, verified read this session):
```bash
for _rb01_f in "$BRIDGE" "$SHIM"; do
```
**Fix:**
```bash
for _rb01_f in "$BRIDGE" "$SHIM" "$CONTRACT_CHECK"; do
```
`$CONTRACT_CHECK` is already defined at `tests/run-tests.sh:36` (`CONTRACT_CHECK="$HERE/contract-check.sh"`) — no new variable needed.

**Why the loop widen alone breaks the suite, and the required companion fix — analog is the 7 sibling guard sites in `tests/contract-check.sh`, all structurally identical:**
```bash
# tests/contract-check.sh:527 (one of 7 identical sites: 527, 565, 600, 644, 698, 829, 1008)
    if [[ -z "$AGY_BIN" ]]; then
```
`RB01`'s scan flags any bare mention of `$AGY_BIN` outside a `run_bounded` call as a violation — these 7 preflight guards mention it without invoking it, producing 7 false positives. `RB01`'s own comment (`tests/run-tests.sh:2300-2306`, referenced in RESEARCH.md) forbids fixing this with an allowlist/skip-list/escape-hatch regex in the scanner — the fix must restructure `contract-check.sh` so the guards no longer contain the substring `AGY_BIN` at all.

**Fix — compute the "agy absent" condition once, right after `AGY_BIN` is resolved** (`tests/contract-check.sh:413`, verified read this session — `AGY_BIN="$(command -v agy 2>/dev/null || true)"` already lives here):
```bash
AGY_BIN="$(command -v agy 2>/dev/null || true)"
_CC_NO_AGY=0; [[ -z "$AGY_BIN" ]] && _CC_NO_AGY=1
```
Then each of the 7 sites changes from:
```bash
    if [[ -z "$AGY_BIN" ]]; then
```
to:
```bash
    if [[ "$_CC_NO_AGY" -eq 1 ]]; then
```
Semantics unchanged (still one source of truth for "is `agy` on PATH"); the guard clauses become invisible to a textual `$AGY_BIN` scan because the lines never invoke `agy`, only test its absence via the precomputed flag.

**Mutation-proof pattern to follow if D-06's own extension needs a new proof it can fail (this codebase's standing convention — "prove a check can fail before trusting it"):**
```bash
# tests/run-tests.sh:2417-2430 (RB01m) — copy this shape for an RB01-covers-contract-check.sh proof
_rb01m_probe() {
    local name="$1" want="$2" line="$3" v o
    cp "$SHIM" "$RB01M_DIR/$name.sh"
    printf '%s\n' "$line" >> "$RB01M_DIR/$name.sh"
    read -r v o <<<"$(_rb_agy_scan "$RB01M_DIR/$name.sh")"
    [[ "$o" -ge 1 ]] || { RB01M_OK=0; RB01M_DETAIL="$RB01M_DETAIL $name:no_occurrences"; }
    if [[ "$want" -eq 1 ]]; then
        [[ "$v" -ge 1 ]] || { RB01M_OK=0; RB01M_DETAIL="$RB01M_DETAIL $name:missed(${v}/${o})"; }
    else
        [[ "$v" -eq 0 ]] || { RB01M_OK=0; RB01M_DETAIL="$RB01M_DETAIL $name:false_positive(${v}/${o})"; }
    fi
}
```

---

### `tests/run-tests.sh` — D-08 (RB24 + deterministic forcing test)

**Analog:** the existing `RB24` block itself — reuse its driver-script shape (source the block, install `HOST_CLEANUP_RAN` traps, print before/after `trap -p` state) for the new forcing test.

**Current `RB24`** (`tests/run-tests.sh:2074-2133`, verified read this session):
```bash
echo "== helper gives the host's traps back (RB24) =="

RB24_OUT="$SANDBOX/rb24-out.log"
RB24_OK=1
RB24_DETAIL=""
for _rb24_mech in watchdog coreutils; do
    if [[ "$_rb24_mech" == "watchdog" ]]; then _rb24_bin=""; else _rb24_bin="$_TIMEOUT_NET"; fi
    : > "$RB24_OUT"
    bash -c '
        set -euo pipefail
        exec 9>/dev/null
        TIMEOUT_BIN="$2"
        . "$1"
        trap "echo HOST_CLEANUP_RAN" TERM
        trap "echo HOST_CLEANUP_RAN" INT
        trap "echo HOST_CLEANUP_RAN" HUP
        for _s in TERM INT HUP; do printf "before %s %s\n" "$_s" "$(trap -p $_s)"; done
        run_bounded 5 2 -- true || true
        for _s in TERM INT HUP; do printf "after %s %s\n" "$_s" "$(trap -p $_s)"; done
    ' _ "$_RB_BLOCK" "$_rb24_bin" > "$RB24_OUT" 2>&1 || { ...
```
`$_RB_BLOCK` is set at `tests/run-tests.sh:1873` (`_RB_BLOCK="$SANDBOX/run_bounded.block.sh"`) — the extracted `run_bounded` source, sourced fresh into each isolated `bash -c`.

**Why `RB24` alone is not deterministic proof (RESEARCH.md, this session's 82 clean reruns/isolated attempts):** the flake needs a signal delivered to the watchdog shell inside the narrow window between `_rb_cancel_timer`'s signal send and `trap - ...`'s restore, which idle-host natural scheduling rarely triggers. RESEARCH.md's recommendation (which the planner must decide, per CONTEXT.md's Claude's-Discretion note): add a new forcing case using the same `bash -c '... . "$1" ...'` sourcing idiom as `RB24`, but have the bounded command itself send a signal to its own parent's pgid at the moment it exits, synchronizing delivery to land at the cancel/restore boundary — then assert `HOST_CLEANUP_RAN` still fires on the `after` trap line, both before-fix-red and after-fix-green.

---

### `tests/run-tests.sh` — D-04 / D-07 new test cases

**Analog:** the harness's own `ok`/`bad`/`_run` idiom, used identically by every existing case.

**Core harness helpers to reuse verbatim** (`tests/run-tests.sh:88-109`, verified read this session):
```bash
PASS=0
FAIL=0

ok() {
    PASS=$((PASS + 1))
    printf 'ok   - %s\n' "$1"
}

bad() {
    FAIL=$((FAIL + 1))
    printf 'FAIL - %s\n' "$1"
    if [[ $# -ge 2 ]]; then
        printf '       %s\n' "$2"
    fi
}

# _run OUTVAR RCVAR cmd...  -- capture stdout+exit code of an arbitrary command.
_run() {
    local __outvar="$1" __rcvar="$2"
    shift 2
    local __out __rc
    __out="$("$@" 2>&1)"
```
New D-04 case: invoke `$SHIM` with an unrecognized `--foo` flag followed by a prompt-shaped token that does not start with `-`, assert the prompt token still reaches `PROMPT_ARGS` (i.e. is not silently dropped) — same `_run`/`ok`/`bad` shape as every neighboring `SH`-prefixed case.
New D-07 case: drive `$BRIDGE`'s model-fetch path with a fake `agy` that exits 0 with a zero-byte reply and no pre-existing cache file, assert the specific "agy model list contains no 'gemini-' ids" message appears on stderr (not the generic "failed to retrieve model list" message) — reuse the `fake-agy.sh`/`FAKE_AGY_*` env-var driving convention already used by `RB25`'s block (`tests/run-tests.sh:2174-2190`) for constructing a scripted fake-agy scenario.

---

### `README.md` — D-09 (Changelog)

**Analog:** same file, the existing `### 1.6.2` section's own bullets — same style, same file, append only.

**Exact insertion point** (`README.md:414-416`, verified read this session):
```markdown
- `/agy-setup` leads with a readable two-step install (print the path, run it) instead of the 9-line resolve-and-validate pipeline; the pipeline remains as fallback where no registry file exists.

### 1.6.1
```
New bullets go between these two lines — never touch the `### 1.6.1`/`### 1.6.0` sections below.

**Existing bullet style to match exactly** (`README.md:409-414`, verified read this session — one bullet per defect, backtick-quoted identifiers, plain language, past-tense description of the fix, no ticket IDs inline):
```markdown
- A failed `agy models` call now surfaces agy's own stderr instead of discarding it. This text is the only diagnostic available when the real fault is auth or the network.
- A model list carrying no `gemini-` ids now reports a degraded/unauthenticated agy rather than blaming the `--type` the user picked.
```
CONTEXT.md's Claude's-Discretion note locks this bullet style explicitly (no ticket IDs inline). Per CONTEXT.md D-09: 4 fix-bullets (ltf, u1z, d4t, b7g) + a closure-note line for xfa/i43 + the mandatory "every existing installation must re-run the installer" notice — count is planner's call (RESEARCH.md flags this ambiguity explicitly), but bullet shape must match the excerpt above.

---

### `.planning/PROJECT.md` — D-02 / D-03 (ticket-closure documentation)

**Analog:** same file, the `## Key Decisions` table's existing row shape.

**Exact table shape to add rows to** (`.planning/PROJECT.md:71-72`, verified read this session):
```markdown
| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Every agy call is bounded on every host, by coreutils `timeout` where it exists and a native bash watchdog where it does not | `delegate-agy-cy5` asked whether the bridge should hard-fail, degrade with a warning, or refuse only the delegation call. ... | ✓ Good — both entry points now warn once per run and proceed bounded; the bridge's startup fatal is deleted (Phase 1) |
```
D-02 (`delegate-agy-xfa`) needs a row recording the verified isolation result plus its one-run caveat (one prompt shape, one model, one agy version); D-03 (`delegate-agy-i43`) needs a row recording the SIGTERM-alone contradiction as a noted discrepancy — outcome column uses the same `✓ Good` / `⚠️ Revisit` / `✗ Superseded` glyph convention already visible in every existing row.

---

## Shared Patterns

### "Fold review Minors into the fix round" (project convention)
**Source:** `.planning/PROJECT.md`'s own Key Decisions row: "Follow-ups discovered during work block the release."
**Apply to:** D-06 and D-07 — both are explicit user overrides of "defer," per CONTEXT.md's own text ("User's explicit choice — overrides 'defer'").

### "Prove a check can fail before trusting it" (project convention)
**Source:** `tests/run-tests.sh`'s `RB01m` (lines 2412-2436), `RB25`/`RB26`.
**Apply to:** any new structural/statistical assertion added by D-05 or D-06 — pair it with a mutation/decoy case proving it is not vacuously green, following `RB01m`'s exact probe shape quoted above.

### `ok`/`bad`/`_run` harness idiom
**Source:** `tests/run-tests.sh:88-109`.
**Apply to:** every new test case added for D-04, D-05, D-07, D-08.

### Never `exit` inside a fetch `if/elif`; defer to the single generic choke point
**Source:** `scripts/agy_bridge.sh:526-528`'s stderr-passthrough comment, and its existing choke point at line 537.
**Apply to:** D-07's fix specifically — this is the exact pitfall RESEARCH.md calls out (Pitfall 2).

### No allowlist / skip-list / escape-hatch regex in scan logic
**Source:** `RB01`'s own comment, `tests/run-tests.sh:2300-2306`.
**Apply to:** D-06 — the fix restructures `contract-check.sh`'s guard clauses (the scanned file), never `RB01`'s scan regex (the scanner).

## No Analog Found

None. Every file in scope for this phase already contains the exact pattern its fix must extend or repair — this is a closed, dependency-free bash bug-fix phase with no new capability and no new file.

## Metadata

**Analog search scope:** `scripts/gemini_shim.sh`, `scripts/agy_bridge.sh`, `tests/run-tests.sh`, `tests/contract-check.sh`, `README.md`, `.planning/PROJECT.md` (all read directly this session at the specific line ranges cited above; line numbers independently re-verified via `sed -n`/`grep -n` against current `master`, not copied unchecked from RESEARCH.md).
**Files scanned:** 6 modified + 1 read-only (`scripts/install.sh`, confirmed untouched by any fix in scope).
**Pattern extraction date:** 2026-08-21
