# Phase 1: The missing-`timeout` decision - Pattern Map

**Mapped:** 2026-08-19
**Files analyzed:** 6 (2 modified scripts, 2 test files, README.md, PROJECT.md)
**Analogs found:** 4 / 6 (README/PROJECT.md are doc edits with no code analog needed)

All code read from `.worktrees/agy-1.6.2` (branch `fix/agy-bridge-resilience` @ `56be103`) — `master`'s scripts lag its history (content-reverted at `a001d0e`). Line numbers below are from that worktree, not `master`.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `scripts/agy_bridge.sh` (add `run_bounded`, rewrite 3 call sites, remove `exit 2` probe) | controller/CLI entrypoint | request-response (subprocess exec + capture) | `scripts/gemini_shim.sh` (sibling script, same problem, one call site ahead in the `if/else` pattern being replaced) | exact — same repo, same problem shape |
| `scripts/gemini_shim.sh` (add byte-identical `run_bounded`, rewrite 4 call sites) | controller/CLI entrypoint | request-response (subprocess exec + capture) | `scripts/agy_bridge.sh` (delegation site `:342` is the most fully-worked bounded-call example: `-k`, `cd`-subshell, EXIT_CODE capture) | exact |
| `tests/run-tests.sh` (new static scan case, byte-identity case, warning-literal case, runtime PTY/no-PTY + sanitized-PATH cases) | test | event-driven (drives fake binary, asserts process state) | Case `SH13` (bound-semantics, ~line 990) for runtime shape; Case `I18` (~line 1561) for static/lint-shaped assertion shape | exact — both cases live in the same file being modified |
| `tests/fake-agy.sh` (new forking, SIGTERM-ignoring mode) | test fixture / stub | event-driven (signal handling, env-var-switched behavior) | `FAKE_AGY_PRINT_HANG` mode (`:101-108`) — same file, same switch pattern, missing only the fork+child-survives behavior | role-match — needs extension, not a new pattern |
| `README.md` (rows :233, :269-271, :43/:54-57) | doc | n/a | itself (existing prose being rewritten in place) | n/a — no code analog needed |
| `.planning/PROJECT.md` (Key Decisions table rows) | doc | n/a | itself | n/a — no code analog needed |

## Pattern Assignments

### `scripts/agy_bridge.sh` / `scripts/gemini_shim.sh` — the `run_bounded` helper

**No existing wrapper-function analog exists in either script.** Both scripts currently inline the bound logic at each call site via repeated `if [[ -n "$TIMEOUT_BIN" ]] … else …` pairs — there is no prior instance of a shell function that wraps a command while preserving the caller's stdio in this codebase. State this explicitly to the planner: **`run_bounded` is a new pattern, not a refactor-in-place of an existing helper.** The closest precedent is structural, not literal: the six `if/else` pairs it replaces, shown below, and the general "standalone, nothing sourced, duplicate verbatim with marker comments" convention already established for other duplicated logic (D-08 cites `delegate-agy-8ph`'s cache-writer precedent, not present in-scope here).

**The bounded-invocation shape to collapse** — `agy_bridge.sh:143-144` (models fetch, direct form, no `if/else` — TIMEOUT_BIN presence was enforced fatally so this site never had a fallback branch):
```bash
if _agy_models=$("$TIMEOUT_BIN" -k 3 "$AGY_MODELS_TIMEOUT" \
                 "$AGY_BIN" models </dev/null 2>"$_agy_err"); then
```

`agy_bridge.sh:231` (stdin read, same — no fallback branch, since the bridge fatals on missing `TIMEOUT_BIN` at startup today):
```bash
"$TIMEOUT_BIN" "$STDIN_TIMEOUT" cat > "$PROMPT_FILE" || {
    echo "ERROR: stdin read timed out after ${STDIN_TIMEOUT}s" >&2; exit 2
}
```

`agy_bridge.sh:340-346` (delegation, inside a `cd`-subshell — the most complex site, with a rationale comment for `-k 5` that must not be duplicated in the watchdog's own comment per RESEARCH.md's note):
```bash
# -k 5: agy ignores SIGTERM (observed), so plain `timeout` would send the
# signal and then block forever waiting for a child that never dies.
( cd "$WORK_DIR" && "$TIMEOUT_BIN" -k 5 "$TIMEOUT" "$AGY_BIN" \
    "${AGY_FLAGS[@]}" \
    > "$STDOUT_FILE" \
    2> "$STDERR_FILE" \
    < /dev/null )
EXIT_CODE=$?
```

`gemini_shim.sh:88-92` (models fetch, WITH the `if/else` fallback the shim already has, since its probe never fatals):
```bash
if [[ -n "$TIMEOUT_BIN" ]]; then
    raw=$("$TIMEOUT_BIN" -k 3 "$AGY_MODELS_TIMEOUT" "$AGY_BIN" models </dev/null 2>/dev/null) || raw=""
else
    raw=$("$AGY_BIN" models </dev/null 2>/dev/null) || raw=""
fi
```

`gemini_shim.sh:189-193` (`--version`):
```bash
if [[ -n "$TIMEOUT_BIN" ]]; then
    "$TIMEOUT_BIN" -k 5 10 "$AGY_BIN" --version || _V_RC=$?
else
    "$AGY_BIN" --version || _V_RC=$?
fi
```

`gemini_shim.sh:262-268` (stdin read):
```bash
if [[ -n "$TIMEOUT_BIN" ]]; then
    "$TIMEOUT_BIN" "$STDIN_TIMEOUT" cat > "$PROMPT_FILE" || {
        echo "ERROR: stdin read timed out after ${STDIN_TIMEOUT}s" >&2; exit 2
    }
else
    cat > "$PROMPT_FILE"
fi
```

`gemini_shim.sh:316-326` (delegation):
```bash
if [[ -n "$TIMEOUT_BIN" ]]; then
    "$TIMEOUT_BIN" -k 5 "$SHIM_TIMEOUT" "$AGY_BIN" "${AGY_ARGS[@]}" \
        > "$STDOUT_FILE" \
        2> "$STDERR_FILE" \
        < /dev/null
else
    "$AGY_BIN" "${AGY_ARGS[@]}" \
        > "$STDOUT_FILE" \
        2> "$STDERR_FILE" \
        < /dev/null
fi
EXIT_CODE=$?
```

**The `EXIT_CODE` capture idiom the helper must not disturb** — `agy_bridge.sh:328-330,347-348` (identical shape at `gemini_shim.sh:313-315,327-328`):
```bash
START=$SECONDS
EXIT_CODE=0
set +e
# ... invocation ...
EXIT_CODE=$?
set -e
DURATION=$(( SECONDS - START ))
```
`run_bounded` is called INSIDE this `set +e` window (or must itself return the wrapped command's exit code faithfully as `$?` after it returns) — a wrapper function that itself trips `set -e` mid-body, or swallows `$?` behind its own cleanup trap, breaks this idiom. Any excerpt shown as a model to the planner must flag that both scripts run `set -euo pipefail`, unlike the test harness (`tests/run-tests.sh:22` uses `set -u` only, no `-e`) — a `run_bounded` internal that relies on a command failing without aborting the script (e.g. probing `$pgid`) needs its own `|| true`/`if` guard, it cannot rely on harness-style tolerance.

**The `TIMEOUT_BIN` probe sites being changed:**

`agy_bridge.sh:14-21` (the `exit 2` D-03 removes):
```bash
AGY_BIN=$(command -v agy)
if command -v timeout &>/dev/null; then
    TIMEOUT_BIN="timeout"
elif command -v gtimeout &>/dev/null; then
    TIMEOUT_BIN="gtimeout"
else
    echo "ERROR: timeout/gtimeout not found in PATH (install coreutils)" >&2; exit 2
fi
```

`gemini_shim.sh:23-30` (already the target shape — sets empty, no fatal — this is the pattern D-01 makes both scripts converge on, except the empty-string case now also gets the D-09 warning, one time, here):
```bash
AGY_BIN=$(command -v agy)
if command -v timeout &>/dev/null; then
    TIMEOUT_BIN="timeout"
elif command -v gtimeout &>/dev/null; then
    TIMEOUT_BIN="gtimeout"
else
    TIMEOUT_BIN=""
fi
```
D-09's warning goes here (in both scripts now, since the bridge's probe converges on the shim's shape), NOT inside `run_bounded` — confirmed by the multi-call-site count above (bridge calls it 3x, shim calls it 4x; a helper-sited warning would print 3-4x per run).

---

### `tests/run-tests.sh` — new cases

**Analog for the static scan (I18-style, ~`:1561-1581`):**
```bash
# I18: an apostrophe anywhere in the plugin cache path must not break the
# generated wrapper. ...
IH="$(_fresh_home)"
VROOT3="$SANDBOX/dd's-plugins.$$"
...
```
I18's shape worth copying: a comment block stating WHY the property must hold ("that wrapper shadows the real `gemini` for every caller on PATH, so a broken quote breaks every one of them"), then a deterministic setup, then an assertion against computed-independently expected forms — not against the script's own output. For the new static scan (D-12/D-13), the equivalent is: grep both scripts for every `"$AGY_BIN"` occurrence, assert each one is inside a `run_bounded … --` argument list, with **zero exceptions/allowlist** (D-13) — this is closer in spirit to a grep-based lint than I18's string-escaping check, but the "assert a structural invariant nothing else in the suite would catch" framing is what to copy.

**Analog for runtime bound-semantics (`SH13`, `:990-1007`):**
```bash
rm -f "$_SHIM_CACHE"
_SH13_START=$(date +%s)
FAKE_AGY_MODELS_HANG=1 AGY_MODELS_TIMEOUT=0 FAKE_AGY_STDOUT="ok" \
    _run OUT RC timeout 30 bash "$SHIM" -m flash -p x
_SH13_ELAPSED=$(( $(date +%s) - _SH13_START ))
if [[ "$RC" -eq 0 && "$_SH13_ELAPSED" -lt 29 && "$OUT" == *"ok"* ]]; then
    ok "SH13 AGY_MODELS_TIMEOUT=0 does not disable the fetch bound"
else
    bad "SH13 AGY_MODELS_TIMEOUT=0 does not disable the fetch bound" \
        "rc=$RC elapsed=${_SH13_ELAPSED}s out=$OUT"
fi
```
Shape to copy for D-14/D-14a: timestamp before, invoke the wrapped script under `_run` with a fake-agy env-var switch and an outer `timeout N` as a suite-level safety net (not the mechanism under test), timestamp after, assert both RC and elapsed bound. The new cases differ in what they assert — not "did it return by N seconds" but "is the PID file's recorded child PID gone" (D-14) — so `ok()`/`bad()` usage is identical but the assertion body needs a `kill -0 "$(cat "$pidfile")" 2>/dev/null` check post-invocation instead of (or in addition to) elapsed time.

**The `ok()` / `bad()` / `_run` helpers (`:47-64`):**
```bash
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
_run() {
    local __outvar="$1" __rcvar="$2"
    shift 2
    local __out __rc
    __out="$("$@" 2>&1)"
    __rc=$?
    printf -v "$__outvar" '%s' "$__out"
    printf -v "$__rcvar" '%s' "$__rc"
}
```
Every new case uses these three verbatim — no new test infra needed.

**Sandbox setup the new sanitized-PATH test must DIVERGE from (`:26-33`):**
```bash
SANDBOX="$(mktemp -d -t agy-tests.XXXXXX)"
...
mkdir -p "$SANDBOX/bin" "$SANDBOX/home"
cp "$HERE/fake-agy.sh" "$SANDBOX/bin/agy"
chmod +x "$SANDBOX/bin/agy"

export PATH="$SANDBOX/bin:$PATH"
export HOME="$SANDBOX/home"
```
Critical: this **prepends** `$SANDBOX/bin` to the real `$PATH`, so the real `timeout` stays reachable through every existing case — this is exactly why it is unsuitable for D-15's sanitized-PATH test as-is. The new test needs a **fully replaced** `PATH`, scoped to that one case only (not the suite-wide export), e.g. a second scratch dir containing only the copied fake-agy plus whatever else the scripts genuinely need on PATH (D-15 requires documenting that set explicitly, not guessing it) — `PATH="$SANDBOX2/bin"` (no `:$PATH` suffix), invoked per-case so it doesn't leak into subsequent cases that expect the real `timeout`.

---

### `tests/fake-agy.sh` — new forking, SIGTERM-ignoring mode

**Existing switch pattern to extend (`FAKE_AGY_PRINT_HANG`, `:101-108`):**
```bash
if [[ -n "${FAKE_AGY_PRINT_HANG:-}" ]]; then
    trap '' TERM
    sleep 300
    exit 0
fi
```
And the doc-comment convention above each mode (`:27-41`) — every mode is documented in the file header with its env var, what it does, and what only stops it. The new forking mode (D-14) needs: (1) `trap '' TERM` as above so the parent ignores the signal same as today, (2) spawn a background child that also ignores TERM and sleeps, (3) write the child's PID to a path the test can read (`FAKE_AGY_PID_FILE` following the existing `FAKE_AGY_DUMP_ARGV`-style "write to a path, purely observational" convention at `:21-26`), (4) parent itself also sleeps/waits so it too must be killed. This is a net-new mode but follows the file's existing env-var-per-behavior switch shape exactly — no new dispatch mechanism needed, just another `if [[ -n "${FAKE_AGY_...}" ]]` block alongside the five that exist.

**Observational-file convention to copy for the PID file (`:21-26,56-58`):**
```bash
#   FAKE_AGY_DUMP_ARGV    if set to a path, write the full argv agy was invoked
#                         with (one arg per line) to that path BEFORE any normal
#                         behavior. Purely additive/observational — does not
#                         alter parsing, output, or exit code.
...
if [[ -n "${FAKE_AGY_DUMP_ARGV:-}" ]]; then
    printf '%s\n' "$@" > "$FAKE_AGY_DUMP_ARGV"
fi
```

---

## Shared Patterns

### The `if/else` TIMEOUT_BIN branch — being deleted, not extended
**Source:** both scripts, 6 sites total (listed above)
**Apply to:** both `agy_bridge.sh` and `gemini_shim.sh`
This is net deletion per D-04; the planner should not look for a way to "reuse" this pattern — `run_bounded` replaces it entirely at all 6 sites, and the bridge's 3 sites gain a fallback branch they never had (since D-03 removes the bridge's fatal probe).

### `EXIT_CODE`/`set +e`/`SECONDS` idiom
**Source:** `agy_bridge.sh:328-330,347-348`; `gemini_shim.sh:313-315,327-328` (byte-for-byte parallel structure)
**Apply to:** both scripts' delegation call sites — `run_bounded` must compose with this, not replace it.

### Standalone-scripts-duplicated-verbatim convention
**Source:** the model-name-mapping code comment at `gemini_shim.sh:58-61` ("Deliberately NOT factored into a sourced library... ~20 duplicated lines is the cheaper failure mode... Behavior is pinned by tests either way")
**Apply to:** `run_bounded`'s duplication across both scripts (D-08) — this is the established precedent in this exact codebase for "why duplicate rather than share," directly reusable as the rationale comment for the new helper.

### Doc-comment-above-mode convention in fake-agy.sh
**Source:** `tests/fake-agy.sh:12-48` (header block enumerating every `FAKE_AGY_*` var)
**Apply to:** the new forking mode — add its entry to this same list, same format.

## No Analog Found

| File/Pattern | Role | Data Flow | Reason |
|---|---|---|---|
| `run_bounded` helper itself | utility (process-group-aware subprocess wrapper) | request-response | No prior redirect-transparent wrapper function exists in either script — this is genuinely new code, not a refactor of an existing helper. The closest thing is the inlined `if/else` shape it replaces (shown above), and the general bash idiom of `set -m` + `kill -- -$pgid` has no precedent anywhere in this repo; RESEARCH.md is the only source for that mechanism, not the codebase. |
| Sanitized (non-prepending) PATH test construction | test | request-response | The existing sandbox setup (`:26-33`) always prepends, so a test needing a PATH with no `timeout` reachable has no existing case to copy structurally, only to diverge from (documented above). |

## Metadata

**Analog search scope:** `.worktrees/agy-1.6.2/scripts/`, `.worktrees/agy-1.6.2/tests/`, `.worktrees/agy-1.6.2/README.md`
**Files scanned:** `agy_bridge.sh` (431 lines), `gemini_shim.sh` (392 lines), `run-tests.sh` (1612 lines, targeted reads only), `fake-agy.sh` (169 lines, read in full), `README.md` (targeted reads)
**Pattern extraction date:** 2026-08-19
