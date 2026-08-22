# Phase 3: The exit-code contract - Pattern Map

**Mapped:** 2026-08-20
**Files analyzed:** 4 (all modifications — no new files this phase)
**Analogs found:** 4 / 4 (all internal — sibling branch/sibling script/existing test case; no cross-module analogs needed for an audit-and-close-gaps phase)

**Line numbers below are read directly off `master` at mapping time and may have drifted a few lines from CONTEXT.md's citations (e.g. RB03 is now at `tests/run-tests.sh:2383-2440`, not `:2019-2073` — file grew from Phase 2 work). Always re-locate by `grep`/anchor text, not by trusting either document's line numbers blindly.**

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|-----------------|----------------|
| `scripts/agy_bridge.sh` (error-handling block, `:719-775`) | CLI entry-point / subprocess-wrapper (controller-equivalent) | request-response (invoke `agy`, capture stdout/stderr/exit code, transform to stderr text or JSON envelope) | itself — the block's own 124-branch (`:733-742`, already correctly separator-free) and the exit-3 branch's `_reason`/`_class` empty-fallback logic (`:760-766`) | role-match (same file, sibling branches; the exact "guard a separator on non-empty" shape does not exist yet anywhere — see No Analog Found) |
| `scripts/gemini_shim.sh` (error-handling block, `:667-706`) | CLI entry-point / subprocess-wrapper (controller-equivalent) | request-response, same shape as the bridge but no JSON on the 137/124/generic-nonzero branches | `scripts/agy_bridge.sh`'s mirrored block (structurally paired, D-06 already documents where they diverge) | exact (mirrored file, same defect class per D-01) |
| `README.md` §Troubleshooting (`:220-234`) | docs (config-adjacent, not code) | N/A — static table, but pinned byte-exact against the two scripts by `RB03` | itself — the table's own exit-124 row (`:231`, stable/correct, not touched) as the "already right" reference shape | exact (same table, adjacent rows) |
| `tests/run-tests.sh` (new provenance cases) | test | request-response (drives `bash "$BRIDGE"/"$SHIM"` via the `_run OUTVAR RCVAR cmd...` harness, asserts on `$OUT`/`$RC`) | `RB03` (`:2383-2440`) for byte-exact provenance shape; `R8` (`:497-505`) for the existing exit-2 exemplar already at the bar D-10 wants; `T5`/`SH6` (`:824-833`, `:1138-1147`) for the loose style D-12 explicitly leaves alone | exact (RB03 is named directly in CONTEXT.md as the shape to copy) |

## Pattern Assignments

### `scripts/agy_bridge.sh` — dangling-colon fix sites (D-01, D-02, D-03)

**Analog:** the file's own 124-branch (clean, no bug) contrasted with the two buggy branches it sits between.

**Site 1 — 137 branch, plain text** (`:730`, current buggy form):
```bash
printf 'ERROR: agy killed (signal 9) after %ds, before its %ds bound -- possible OOM or external kill: %s\n' "$DURATION" "$TIMEOUT" "$(cat "$STDERR_FILE" 2>/dev/null || true)" >&2
```
Unconditional `: %s` — empty stderr leaves a dangling `: ` per `delegate-agy-v5a`.

**Site 2 — 137 branch, JSON** (`:725-728`, current buggy form):
```python
print(json.dumps({'success':False,'model_used':sys.argv[1],'type':sys.argv[2],'duration_seconds':int(sys.argv[3]),'error':sys.argv[4] + ': ' + open(sys.argv[5]).read()}))
```
Same defect inside the JSON string — `sys.argv[4] + ': ' + <stderr>` is unconditional (D-02's target).

**Site 3 — generic-nonzero branch, plain text** (`:750`, current buggy form):
```bash
printf 'ERROR: agy exit %d: %s\n' "$EXIT_CODE" "$(cat "$STDERR_FILE" 2>/dev/null || true)" >&2
```

**Site 4 — generic-nonzero branch, JSON** (`:745-748`, current buggy form):
```python
print(json.dumps({'success':False,'model_used':sys.argv[1],'type':sys.argv[2],'duration_seconds':int(sys.argv[3]),'error':open(sys.argv[4]).read()}))
```
Currently no separator at all in JSON here (whole stderr file *is* the error string) — D-02 note: this site does NOT need the colon-drop fix, only Site 2 does. Confirm before touching — do not "fix" a site that isn't broken.

**D-03's target shape (no existing precedent in either script for exactly this — see No Analog Found)** — build the suffix once, guarded, then splice it into both the printf and the python3 call:
```bash
_stderr_content="$(cat "$STDERR_FILE" 2>/dev/null || true)"
_suffix=""
[[ -n "$_stderr_content" ]] && _suffix=": $_stderr_content"
printf 'ERROR: agy killed (signal 9) after %ds, before its %ds bound -- possible OOM or external kill%s\n' "$DURATION" "$TIMEOUT" "$_suffix" >&2
```
For the JSON site, pass the pre-guarded suffix (or empty string) as a separate argv slot to `python3 -c` rather than concatenating inside Python — keeps the guard logic in one place (bash) instead of duplicating the `-n` check in Python too.

**Nearest existing "conditional field" shape in this file** (`:625-633`, VERBOSE/LOG_FILE block — different mechanism, same "only include if present" spirit, cite for style consistency not for copy-paste):
```bash
if [[ -n "$LOG_FILE" ]]; then
    printf '%s\n' "$_verbose_msg" >> "$LOG_FILE"
else
    printf '%s\n' "$_verbose_msg" >&2
fi
```

---

### `scripts/gemini_shim.sh` — dangling-colon fix site (D-01, D-03; D-02 does not apply here)

**Analog:** `scripts/agy_bridge.sh`'s 137 plain-text branch (Site 1 above) — same message shape, same fix.

**Site — 137 branch, plain text only** (`:673-674`, current buggy form):
```bash
printf 'ERROR: agy killed (signal 9) after %ds, before its %ds bound -- possible OOM or external kill: %s\n' \
    "$DURATION" "$SHIM_TIMEOUT" "$(cat "$STDERR_FILE" 2>/dev/null || true)" >&2
```
No JSON path exists on this branch (confirmed: shim's 137/124/generic-nonzero branches, `:668-682`, never check `$OUTPUT_FORMAT` — only the exit-3 branch at `:699-704` does) — so D-02's "fix JSON too" is a no-op for the shim; only the plain-text printf needs the guard.

**Explicitly NOT a fix site** — the shim's generic-nonzero branch (`:679-681`):
```bash
elif [[ "$EXIT_CODE" -ne 0 ]]; then
    cat "$STDERR_FILE" >&2
    exit "$EXIT_CODE"
fi
```
This relays raw stderr with no added separator at all — nothing to guard. This is exactly D-06's documented bridge-vs-shim divergence (bridge prefixes `"ERROR: agy exit N: "`, shim doesn't prefix anything here) — do not "fix" it into matching the bridge; the phase's discretion note says name the asymmetry in README, not unify it.

---

### `README.md` §Troubleshooting — row rewrite (D-05, D-06, D-07)

**Analog:** the table's own existing exit-124 row (`:231`) as the "stays as-is" baseline, and `_RB_WARN_LITERAL`/`_RB_NOTE_LITERAL` in `tests/run-tests.sh:2392-2393` as the exact mechanism by which a README row becomes machine-checked (copy this indirection: define the literal in one place, quote it in the table, pin it in a test — do not just edit the table prose in isolation).

**Row needing rewrite — exit 3** (`:233`, current stale form):
```
| Exit code 3 (`agy returned empty output`) | agy exited 0 with no output — usually quota `RESOURCE_EXHAUSTED (429)`. The reason (full agy stderr) is surfaced; wait for quota reset or re-auth. Both `agy-bridge` and the `gemini` shim fail loud here rather than reporting empty success. |
```
Actual code shape to quote instead (bridge `:773`, shim `:705` — identical text on both scripts):
```
ERROR: agy returned empty output [<class>]: <reason>
```
where `<class>` ∈ `empty_output`/`quota`/`auth` (bridge `:762-766`, shim `:694-698`, identical `case` block on both). Per D-07, also note the differently-shaped JSON envelopes:
- Bridge (`:767-771`): flat `{"success":false,...,"error":<reason>,"error_class":<class>}`
- Shim (`:699-704`): nested `{"error":{"message":<reason>,"class":<class>}}`

**Row needing the D-03 suffix update — exit 137** (`:232`, current form omits the stderr suffix entirely): add the `: <stderr>` (present-when-nonempty) shape from the fixed Site 1/Site-shim above, per D-06's divergence-aside convention if bridge/shim wording differs after the fix (they use identical text on the 137 branch, so likely a single shared row still holds — verify after Sites 1-3 are actually fixed, don't presuppose).

**Rows to re-verify, not rewrite unless found stale** — exit 2 (`:230`, already matches `agy_bridge.sh:539-541`'s literal text — verify byte-for-byte, D-05 says re-audit all 5, not just the 2 originally ticketed), exit 124 (`:231`, simple/stable), exit 127 (`:226`, out-of-scope code in `install.sh` per D-out-of-scope, read-only re-check against `install.sh:137,173`).

---

### `tests/run-tests.sh` — new RB03-style provenance cases (D-11)

**Analog:** `RB03` in full (`tests/run-tests.sh:2383-2440`) — copy this shape exactly, do not invent a new mechanism.

**The pattern to copy** (expected-bytes-defined-HERE, not extracted-then-grepped, per RB03's own comment at `:2385-2391`):
```bash
_RB_WARN_LITERAL='WARNING: timeout/gtimeout not found -- bounding agy with the bash watchdog fallback; install coreutils for process-group kill'
...
RB03_OK=1
RB03_DETAIL=""
for _rb03_f in "$BRIDGE" "$SHIM"; do
    _rb03_n="$(grep -v '^[[:space:]]*#' "$_rb03_f" | grep -cF "RB_NO_TIMEOUT_WARN='$_RB_WARN_LITERAL'")" || _rb03_n=0
    [[ "$_rb03_n" -eq 1 ]] || { RB03_OK=0; RB03_DETAIL="$RB03_DETAIL ${_rb03_f##*/}:defines_${_rb03_n}"; }
done
grep -qF "$_RB_WARN_LITERAL" "$_RB_README" || { RB03_OK=0; RB03_DETAIL="$RB03_DETAIL readme:warning_missing"; }
if [[ "$RB03_OK" -eq 1 ]]; then
    ok "RB03 ..."
else
    bad "RB03 ..." "detail=$RB03_DETAIL"
fi
```
For D-11's new cases: (1) a positive case asserting the fixed message *with* stderr present matches the exact `"...kill: <stderr>"` string, (2) a negative case asserting the fixed message *with empty* stderr contains NO dangling `": "` (i.e. does not match `*"kill: "` / ends the sentence cleanly) — RB03's own file already models a positive+negative pair (`:2409-2434`, the warning/notice literals are the positive half, the deleted-fatal-string and "unbounded" checks are the negative half) — mirror that two-sided structure rather than writing positive-only.

**The harness invocation to build the case on** — `_run OUTVAR RCVAR cmd...` (defined `:216-227`), driven exactly like `T5`/`SH6`:
```bash
FAKE_AGY_PRINT_KILL9=1 _run OUT RC bash "$BRIDGE" --type code --timeout 60 -- "oom check"
```
`FAKE_AGY_STDERR` defaults to empty (`tests/fake-agy.sh:15,292`) — meaning `T5`/`SH6` as they exist today already exercise the *empty-stderr* dangling-colon path, they just don't assert on it byte-exactly (only `*"killed"*`). The new RB03-extension case should add a second invocation with `FAKE_AGY_STDERR` set non-empty to exercise the *present* half, since no existing case does that for the 137/generic-nonzero branches.

**The existing exit-2 exemplar already at D-10's bar — do not duplicate, it already covers the one README row** (`R8`, `:497-505`):
```bash
rm -f "$HOME/.cache/agy-bridge-models"
FAKE_AGY_MODELS_GARBAGE=1 _run OUT RC bash "$BRIDGE" --type code -- "garbage list"
if [[ "$RC" -eq 2 && "$OUT" == *"no 'gemini-' ids"* && "$OUT" != *"for --type"* && "$OUT" == *"FAKE-AGY-DEGRADED"* ]]; then
    ok "R8 model list with no gemini ids reports a degraded list, not a bad --type"
else
    bad "R8 model list with no gemini ids reports a degraded list, not a bad --type" "rc=$RC out=$OUT"
fi
```
This is substring-style (`*"..."*`), not RB03's byte-exact style — per D-12, leave it as-is; it is not one of the messages D-01-D-03/D-07 touch, so it doesn't get upgraded.

**The loose style D-12 says leave alone (do not retrofit)** — `B2`/`S2` (`:238-244`, `:272-278`, `RC -ne 0` only) and `T4`/`T5`/`SH4`-`SH6` (`:812-833`, `:1114-1147`, substring `*"killed"*`/`*"timeout"*` checks). These stay exactly as written; only add new cases beside them.

## Shared Patterns

### JSON envelope construction (bridge only)
**Source:** `scripts/agy_bridge.sh:724-728, 734-738, 744-748, 767-771, 790-794` (five sites, all the same shape)
**Apply to:** any bridge JSON-error-message edit (Site 2 above)
```bash
python3 -c "
import json, sys
print(json.dumps({...python3 dict literal referencing sys.argv[N]...}))
" "$ARG1" "$ARG2" ... || true
```
Args are passed positionally to `python3 -c`, never interpolated into the Python source string directly — preserves this shape when adding a guarded-suffix argv slot for D-03.

### `ERROR:`-prefix convention (bridge, all exit-2 sites + error branches)
**Source:** every exit-2 site found via `awk '/exit 2/' scripts/agy_bridge.sh` (25 sites: `:21,44,371,374,377,378,381,382,385,388,389,397,406,407,451,460,530,542,551,554,585,597,600,604,641`)
**Apply to:** D-09's consistency pass — every site already starts `echo "ERROR: ...` or `printf '...ERROR:...'`, styled consistently (imperative, names the offending flag/value in `'...'` quotes). No inconsistent site found in this read-through; if the planner's own pass finds one, this is the style to match it against.

### README-vs-script byte-exact pinning (the mechanism D-11 extends)
**Source:** `tests/run-tests.sh:2392-2440` (RB03, full)
**Apply to:** every message D-11 names — literal defined once as a bash variable in the test file itself, `grep -cF` count-of-exactly-1 in the source script(s), `grep -qF` presence-check in `README.md`, positive assertion paired with at least one negative/absence assertion.

### Test harness invocation
**Source:** `tests/run-tests.sh:216-227` (`_run OUTVAR RCVAR cmd...`), `ok "..."` / `bad "..." "detail=..."` (used throughout, e.g. `:232-236`)
**Apply to:** every new test case in this phase
```bash
_run OUT RC bash "$BRIDGE" --type code --timeout 60 -- "oom check"
if [[ <condition> ]]; then
    ok "<case-id> <description>"
else
    bad "<case-id> <description>" "rc=$RC out=$OUT"
fi
```

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| the D-03 "guard a separator on non-empty content" shape itself | inline bash logic inside `agy_bridge.sh`/`gemini_shim.sh`'s error branches | request-response | CONTEXT.md states this explicitly (`<code_context>` §Established Patterns): "not yet a pattern in these two scripts for error messages... is the shape D-03 introduces." Closest same-file precedent is the LOG_FILE if/else at `agy_bridge.sh:628-632` (different mechanism — routes to two destinations rather than conditionally including a substring) and the `_reason` empty-fallback at `:760-762`/`gemini_shim.sh:692-693` (different D-03-rejected shape — a placeholder fallback string, not a dropped suffix). The fix is a 2-3 line inline guard, not something requiring an external pattern — trivial enough to write fresh per Site, matching the two-line shape shown under `scripts/agy_bridge.sh` above. |

## Metadata

**Analog search scope:** `scripts/agy_bridge.sh`, `scripts/gemini_shim.sh`, `README.md`, `tests/run-tests.sh`, `tests/fake-agy.sh` (harness reference only) — no other directories searched; this phase's canonical_refs already named the exact files and line ranges, so no broader Glob/Grep sweep was needed.
**Files scanned:** 5 (4 targets + 1 test-harness support file)
**Pattern extraction date:** 2026-08-20
**Note on CONTEXT.md line-number drift:** `RB03` moved from `:2019-2073` (CONTEXT.md's citation) to `:2383-2440` (current `master`) — file grew between context-gathering and this mapping pass. All other CONTEXT.md line citations for `agy_bridge.sh`/`gemini_shim.sh`/`README.md` were re-verified and match exactly.
