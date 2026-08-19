#!/usr/bin/env bash
# Regression tests for scripts/agy_bridge.sh and scripts/gemini_shim.sh against
# a fake `agy` CLI stub (tests/fake-agy.sh).
#
# Focus areas:
#  - ps3.1: neither agy_bridge.sh nor gemini_shim.sh may report success when
#    agy hides a failure behind exit 0 + empty stdout.
#  - ps3.2: agy_bridge.sh --digest appends an output contract AFTER the user
#    prompt, and warns (without corrupting output) on oversized replies.
#  - 2dc.4: agy's REAL prompt-delivery contract embeds the prompt in a
#    TASK: section of GEMINI.md inside the last --add-dir directory — NOT via
#    stdin, NOT via a single (size-capped, ps/proc-visible) argv string.
#    tests/fake-agy.sh enforces it; scripts/agy_bridge.sh and
#    scripts/gemini_shim.sh now honor it (T1-T3 delivery tests below).
#  - vfn (T1-T6): fail-closed allowlist policies, MCP tool-preference stanza
#    gating (server-on/off, search/shim excluded), the shim --sandbox read-only
#    floor, exit-3 docs, and the version bump. The T7 assertions below lock in
#    that shipped behavior.
#  - vfn.11 (I*): the self-contained installer/uninstaller — pinned-path
#    launcher wrappers (fail-loud-on-break, NO cache glob), non-clobber +
#    full-$PATH shadow scan, refuse-root, idempotency, consent-gated rc patch,
#    atomic tokensave register (exit 3/4/5, leaves original on failure),
#    python3-guard fail-open, decline-hint, the /agy-setup one-liner path
#    validation, uninstall reversal, and repo-untouched.
#
#    SUITE STATE: fully GREEN. New cases must keep the suite green; no assertion
#    may be weakened to pass early.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
BRIDGE="$ROOT/scripts/agy_bridge.sh"
SHIM="$ROOT/scripts/gemini_shim.sh"
INSTALL="$ROOT/scripts/install.sh"
UNINSTALL="$ROOT/scripts/uninstall.sh"

SANDBOX="$(mktemp -d -t agy-tests.XXXXXX)"
# Reap anything a fixture left running before removing the sandbox. Every
# fixture that records a PID writes it to $SANDBOX/<name>.pid; a failing run
# must not leave 300-second sleepers behind on the developer's box.
cleanup() {
    local f p
    for f in "$SANDBOX"/*.pid; do
        [[ -s "$f" ]] || continue
        p="$(cat "$f" 2>/dev/null)" || continue
        [[ "$p" =~ ^[0-9]+$ ]] && kill -KILL "$p" 2>/dev/null
    done
    rm -rf "$SANDBOX"
}
trap cleanup EXIT

mkdir -p "$SANDBOX/bin" "$SANDBOX/home"
cp "$HERE/fake-agy.sh" "$SANDBOX/bin/agy"
chmod +x "$SANDBOX/bin/agy"

export PATH="$SANDBOX/bin:$PATH"
export HOME="$SANDBOX/home"

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
    __rc=$?
    printf -v "$__outvar" '%s' "$__out"
    printf -v "$__rcvar" '%s' "$__rc"
}

# ── Sanitized PATH ────────────────────────────────────────────────────────────
# The suite-wide `export PATH="$SANDBOX/bin:$PATH"` above PREPENDS, so the
# host's timeout/gtimeout stays reachable through every case and the scripts'
# no-bounding-binary branch would never be exercised on a dev box. _purebin
# builds a SECOND bin dir holding the fake agy plus an explicit, named list of
# the external tools the scripts genuinely use -- and nothing else. The list is
# the deliverable, not an implementation detail: it documents the real PATH
# dependency set instead of guessing where the bounding binaries live. A tool
# that cannot be resolved is fatal, never skipped -- a silently-missing tool
# turns every sanitized case into a vacuous pass.
_PUREBIN_TOOLS=(
    mktemp find grep sed sort tail head cat mkdir mv rm chmod cp tr cut awk
    date sleep ps env python3
    # Beyond the baseline set: the scripts resolve their own config/policy dirs
    # through `readlink -f` + `dirname`, and the fake agy's shebang is
    # `#!/usr/bin/env bash`, so env must find bash on the replacement PATH.
    bash readlink dirname
)
_PUREBIN=""
_purebin() {
    if [[ -n "$_PUREBIN" ]]; then printf '%s' "$_PUREBIN"; return 0; fi
    local d t p
    d="$(mktemp -d "$SANDBOX/purebin.XXXXXX")"
    cp "$HERE/fake-agy.sh" "$d/agy"
    chmod +x "$d/agy"
    for t in "${_PUREBIN_TOOLS[@]}"; do
        p="$(command -v "$t" 2>/dev/null)" || p=""
        if [[ -z "$p" ]]; then
            printf 'FATAL: sanitized PATH cannot resolve required tool: %s\n' "$t" >&2
            exit 1
        fi
        ln -sf "$p" "$d/$t"
    done
    _PUREBIN="$d"
    printf '%s' "$d"
}

# The outer bound below is a suite-level safety net, never the mechanism under
# test. `--foreground` is load-bearing and must not be dropped: this tool's
# default mode places its child in a new process group and signals the GROUP,
# which would reap the fake agy and its fork as a side effect and turn a
# genuinely failing descendant assertion into a vacuous pass. `--foreground`
# creates no group and signals only its direct child, so a broken
# implementation leaves the fake alive and the assertion fails as it should.
# `-k` is required for the net to bound anything at all: a script blocked on a
# foreground child DEFERS a SIGTERM until that child returns, so the plain
# SIGTERM form would sit for as long as the fake sleeps -- observed at 300s --
# and a broken implementation would hang the suite instead of failing it. The
# escalation still reaches only the direct child, so the fake and its fork stay
# alive to be asserted on.
# Resolved from the harness's own PATH, before the replacement PATH applies.
_TIMEOUT_NET="$(command -v timeout 2>/dev/null)" || _TIMEOUT_NET=""
if [[ -z "$_TIMEOUT_NET" ]]; then
    echo "FATAL: the harness needs coreutils timeout for its safety net" >&2
    exit 1
fi

# _run_sanitized OUTVAR RCVAR cmd...  -- like _run, but with PATH fully
# REPLACED by _purebin's directory (no ":$PATH" suffix), scoped to this one
# invocation and never exported suite-wide. HOME keeps pointing at the existing
# sandbox home.
_run_sanitized() {
    local __outvar="$1" __rcvar="$2"
    shift 2
    local __dir __out __rc
    __dir="$(_purebin)"
    __out="$(PATH="$__dir" "$_TIMEOUT_NET" --foreground -k 5 30 "$@" 2>&1)"
    __rc=$?
    printf -v "$__outvar" '%s' "$__out"
    printf -v "$__rcvar" '%s' "$__rc"
}

echo "== agy_bridge.sh =="

# B1: normal success passthrough
FAKE_AGY_STDOUT="hello world" _run OUT RC bash "$BRIDGE" --type code -- "do a thing"
if [[ "$RC" -eq 0 && "$OUT" == *"hello world"* ]]; then
    ok "B1 normal success passthrough"
else
    bad "B1 normal success passthrough" "rc=$RC out=$OUT"
fi

# B2: exit-0 empty-stdout must be treated as a hidden failure (non-zero)
FAKE_AGY_EXIT=0 FAKE_AGY_STDOUT="" _run OUT RC bash "$BRIDGE" --type code -- "do a thing"
if [[ "$RC" -ne 0 ]]; then
    ok "B2 exit-0 empty-stdout -> non-zero"
else
    bad "B2 exit-0 empty-stdout -> non-zero" "rc=$RC out=$OUT"
fi

# B3: RESOURCE_EXHAUSTED stderr surfaced
FAKE_AGY_EXIT=1 FAKE_AGY_STDERR="RESOURCE_EXHAUSTED: quota" _run OUT RC bash "$BRIDGE" --type code -- "do a thing"
if [[ "$RC" -ne 0 && "$OUT" == *"RESOURCE_EXHAUSTED"* ]]; then
    ok "B3 RESOURCE_EXHAUSTED stderr surfaced"
else
    bad "B3 RESOURCE_EXHAUSTED stderr surfaced" "rc=$RC out=$OUT"
fi

# B4: --json empty stdout -> success:false envelope
FAKE_AGY_EXIT=0 FAKE_AGY_STDOUT="" _run OUT RC bash "$BRIDGE" --type code --json -- "do a thing"
if [[ "$OUT" == *'"success": false'* ]]; then
    ok "B4 --json empty -> success:false envelope"
else
    bad "B4 --json empty -> success:false envelope" "rc=$RC out=$OUT"
fi

echo "== gemini_shim.sh =="

# S1: normal text passthrough
FAKE_AGY_STDOUT="hello shim" _run OUT RC bash "$SHIM" -p "do a thing"
if [[ "$RC" -eq 0 && "$OUT" == *"hello shim"* ]]; then
    ok "S1 normal text passthrough"
else
    bad "S1 normal text passthrough" "rc=$RC out=$OUT"
fi

# S2: exit-0 empty-stdout -> non-zero
FAKE_AGY_EXIT=0 FAKE_AGY_STDOUT="" _run OUT RC bash "$SHIM" -p "do a thing"
if [[ "$RC" -ne 0 ]]; then
    ok "S2 exit-0 empty-stdout -> non-zero"
else
    bad "S2 exit-0 empty-stdout -> non-zero" "rc=$RC out=$OUT"
fi

# S3: --output-format json empty -> non-zero + no "response" key
FAKE_AGY_EXIT=0 FAKE_AGY_STDOUT="" _run OUT RC bash "$SHIM" --output-format json -p "do a thing"
if [[ "$RC" -ne 0 && "$OUT" != *'"response"'* ]]; then
    ok "S3 json empty -> non-zero + no response key"
else
    bad "S3 json empty -> non-zero + no response key" "rc=$RC out=$OUT"
fi

# S4: json normal -> success envelope with response
FAKE_AGY_STDOUT="the answer" _run OUT RC bash "$SHIM" --output-format json -p "do a thing"
if [[ "$RC" -eq 0 && "$OUT" == *'"response"'* && "$OUT" == *"the answer"* ]]; then
    ok "S4 json normal -> response envelope"
else
    bad "S4 json normal -> response envelope" "rc=$RC out=$OUT"
fi

# S5: RESOURCE_EXHAUSTED stderr surfaced
FAKE_AGY_EXIT=1 FAKE_AGY_STDERR="RESOURCE_EXHAUSTED: quota" _run OUT RC bash "$SHIM" -p "do a thing"
if [[ "$RC" -ne 0 && "$OUT" == *"RESOURCE_EXHAUSTED"* ]]; then
    ok "S5 RESOURCE_EXHAUSTED stderr surfaced"
else
    bad "S5 RESOURCE_EXHAUSTED stderr surfaced" "rc=$RC out=$OUT"
fi

# S6: model-map is alias -> CLASS, never a frozen id or a display name
# (delegate-agy-62x). A value outside the class set is a pinned name that will
# go stale on agy's next release -- the exact drift that broke the bridge in
# delegate-agy-ovu. Key set is pinned too: dropping one breaks a live caller.
S6_OUT="$(python3 - "$ROOT/config/model-map.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
classes = {"pro-high", "pro-low", "flash-high", "flash-medium", "flash-low"}
required = {
    "pro", "gemini-pro", "flash", "gemini-flash",
    "gemini-3.6-flash", "gemini-3.6-flash-high", "gemini-3.6-flash-medium",
    "gemini-3.6-flash-low", "gemini-3.5-flash", "gemini-3.5-flash-high",
    "gemini-3.5-flash-medium", "gemini-3.5-flash-low",
    "gemini-3.1-pro", "gemini-3.1-pro-high", "gemini-3.1-pro-low",
    "gemini-2.5-pro", "gemini-2.5-flash",
    "gemini-2.5-flash-preview-04-17", "gemini-2.5-pro-preview-06-05",
}
frozen = sorted(k for k, v in d.items() if v not in classes)
missing = sorted(required - set(d))
print("flash=%s frozen=%s missing=%s" % (
    d.get("flash"), ",".join(frozen) or "none", ",".join(missing) or "none"))
PY
)"
if [[ "$S6_OUT" == "flash=flash-high frozen=none missing=none" ]]; then
    ok "S6 model-map maps aliases to classes only, all legacy keys preserved"
else
    bad "S6 model-map maps aliases to classes only, all legacy keys preserved" "$S6_OUT"
fi

# S7: whitespace-only prompt via stdin (2dc.7) -- `-p ""` selects the stdin
# path (Octopus pattern, gemini_shim.sh:83-91); a lone newline defeats the
# old `[[ ! -s "$PROMPT_FILE" ]]` guard, so this pins the widened grep guard.
S7_DUMP="$SANDBOX/s7_argv.log"; : > "$S7_DUMP"
OUT="$(printf '\n\n' | FAKE_AGY_DUMP_ARGV="$S7_DUMP" bash "$SHIM" -p "" 2>&1)"; RC=$?
if [[ "$RC" -eq 2 && "$OUT" == *"ERROR: empty prompt"* && ! -s "$S7_DUMP" ]]; then
    ok "S7 whitespace-only prompt via stdin -> exit 2, agy never invoked"
else
    bad "S7 whitespace-only prompt via stdin -> exit 2, agy never invoked" "rc=$RC out=$OUT"
fi

# S8 prompt delivered via GEMINI.md TASK, absent from argv AND stdin (mirrors
# T1: agy_bridge.sh's guarantee -- gemini_shim.sh:172-176 embeds into
# GEMINI.md, :180 passes only --print "$AGY_POINTER").
(
    RECDIR="$SANDBOX/shim_recorder"
    mkdir -p "$RECDIR"
    ARGV_LOG="$SANDBOX/shim_argv2.log"
    STDIN_LOG="$SANDBOX/shim_stdin2.log"
    : > "$ARGV_LOG"; : > "$STDIN_LOG"
    cat > "$RECDIR/agy" <<EOF
#!/usr/bin/env bash
set -u
printf '%s\n' "\$@" >> "$ARGV_LOG"
cat > "$STDIN_LOG"
exec "$HERE/fake-agy.sh" "\$@" < "$STDIN_LOG"
EOF
    chmod +x "$RECDIR/agy"
    export PATH="$RECDIR:$PATH"
    TOKEN="ZZSHIMLEAKTOKEN77"
    OUT="$(FAKE_AGY_ECHO_PROMPT=1 bash "$SHIM" -p "$TOKEN" 2>/dev/null)"
    token_in_out=0;   [[ "$OUT" == *"$TOKEN"* ]] && token_in_out=1
    token_in_argv=0;  grep -q "$TOKEN" "$ARGV_LOG" && token_in_argv=1
    token_in_stdin=0; grep -q "$TOKEN" "$STDIN_LOG" && token_in_stdin=1
    pointer_in_argv=0; grep -q "GEMINI.md context" "$ARGV_LOG" && pointer_in_argv=1
    if [[ "$token_in_out" -eq 1 && "$token_in_argv" -eq 0 && "$token_in_stdin" -eq 0 && "$pointer_in_argv" -eq 1 ]]; then
        echo "S8_RESULT=ok"
    else
        echo "S8_RESULT=fail token_in_out=$token_in_out token_in_argv=$token_in_argv token_in_stdin=$token_in_stdin pointer_in_argv=$pointer_in_argv out=$OUT argv=$(cat "$ARGV_LOG") stdin=$(cat "$STDIN_LOG")"
    fi
) > "$SANDBOX/s8.out" 2>&1
S8_LINE="$(grep '^S8_RESULT=' "$SANDBOX/s8.out")"
if [[ "$S8_LINE" == "S8_RESULT=ok" ]]; then
    ok "S8 shim delivers prompt via GEMINI.md TASK, absent from argv AND stdin"
else
    bad "S8 shim delivers prompt via GEMINI.md TASK, absent from argv AND stdin" "$S8_LINE"
fi

echo "== dynamic bridge model resolution (delegate-agy-xpx.4) =="

# R1: bridge reaches agy for all 5 delegation types AND returns fake-agy's
# actual --print success output (rc=0 + FAKE_AGY_STDOUT marker), not merely
# the absence of an allowlist-rejection error.
R1_OK=1
R1_DETAIL=""
for t in search code review analysis implement; do
    FAKE_AGY_STDOUT="ok" _run OUT RC bash "$BRIDGE" --type "$t" -- "hello $t"
    if [[ "$RC" -ne 0 || "$OUT" != *"ok"* ]]; then
        R1_OK=0
        R1_DETAIL="${R1_DETAIL}type=$t rc=$RC out=$OUT; "
    fi
done
if [[ "$R1_OK" -eq 1 ]]; then
    ok "R1 bridge reaches agy for all 5 delegation types (rc=0 + fake-agy success marker)"
else
    bad "R1 bridge reaches agy for all 5 delegation types (rc=0 + fake-agy success marker)" "$R1_DETAIL"
fi

# R2: search delegation resolves the LATEST gemini-*-flash-high (3.6, not 3.5) via sort -V
FAKE_AGY_STDOUT="ok" _run OUT RC bash "$BRIDGE" --type search --verbose -- "latest check"
if [[ "$OUT" == *"model=gemini-3.6-flash-high"* ]]; then
    ok "R2 --type search --verbose resolves latest flash-high (3.6, not 3.5)"
else
    bad "R2 --type search --verbose resolves latest flash-high (3.6, not 3.5)" "rc=$RC out=$OUT"
fi

# R3: pro-only bridge cache (fresh mtime) -> --type search fails loud with
# "no gemini model" (exit 2), proving auto-select does not silently fall back.
# Reset the cache immediately after so later bridge tests (D1-D4/T1-T3/M1-M3)
# still see the full model list.
_R3_CACHE="$HOME/.cache/agy-bridge-models"
mkdir -p "$(dirname "$_R3_CACHE")"
printf '%s\n' "gemini-3.1-pro-high" > "$_R3_CACHE"
FAKE_AGY_STDOUT="ok" _run OUT RC bash "$BRIDGE" --type search
if [[ "$RC" -eq 2 && "$OUT" == *"no gemini model"* ]]; then
    ok "R3 pro-only cache -> --type search exits 2 with 'no gemini model'"
else
    bad "R3 pro-only cache -> --type search exits 2 with 'no gemini model'" "rc=$RC out=$OUT"
fi
rm -f "$_R3_CACHE"

# R3b: explicit --model is validated against the "id<TAB>display name" list agy
# emits — the id must match even though the line carries a trailing display name.
FAKE_AGY_STDOUT="ok" _run OUT RC bash "$BRIDGE" --type code --model gemini-3.1-pro-high --verbose -- "explicit model"
if [[ "$RC" -eq 0 && "$OUT" == *"model=gemini-3.1-pro-high"* ]]; then
    ok "R3b explicit --model accepted against tab-separated agy models output"
else
    bad "R3b explicit --model accepted against tab-separated agy models output" "rc=$RC out=$OUT"
fi

# R3c: a stale cache written in the "id<TAB>display name" form normalizes on
# load, so auto-select still resolves the id (not the whole tabbed line).
_R3C_CACHE="$HOME/.cache/agy-bridge-models"
mkdir -p "$(dirname "$_R3C_CACHE")"
printf '%s\t%s\n' "gemini-3.1-pro-high" "Gemini 3.1 Pro (High)" > "$_R3C_CACHE"
FAKE_AGY_STDOUT="ok" _run OUT RC bash "$BRIDGE" --type code --verbose -- "cached tabbed list"
if [[ "$RC" -eq 0 && "$OUT" == *"model=gemini-3.1-pro-high"* ]]; then
    ok "R3c tab-separated cache normalizes on load (auto-select gets the id)"
else
    bad "R3c tab-separated cache normalizes on load (auto-select gets the id)" "rc=$RC out=$OUT"
fi
rm -f "$_R3C_CACHE"

# R3d: an unknown --model is still rejected (normalization must not loosen the check).
FAKE_AGY_STDOUT="ok" _run OUT RC bash "$BRIDGE" --type code --model gemini-9.9-pro-high -- "bogus model"
if [[ "$RC" -eq 2 && "$OUT" == *"unknown --model"* ]]; then
    ok "R3d unknown --model still exits 2 after tab normalization"
else
    bad "R3d unknown --model still exits 2 after tab normalization" "rc=$RC out=$OUT"
fi

# R5: a hung `agy models` must not hang the bridge. fake-agy traps SIGTERM in
# hang mode (real agy ignores it too), so this also proves `timeout -k` is what
# does the killing -- plain `timeout` would never return.
_R5_CACHE="$HOME/.cache/agy-bridge-models"
rm -f "$_R5_CACHE"
_R5_START=$(date +%s)
FAKE_AGY_MODELS_HANG=1 AGY_MODELS_TIMEOUT=2 _run OUT RC bash "$BRIDGE" --type code -- "hang check"
_R5_ELAPSED=$(( $(date +%s) - _R5_START ))
if [[ "$RC" -eq 2 && "$_R5_ELAPSED" -lt 30 && "$OUT" == *"timed out"* ]]; then
    ok "R5 hung 'agy models' is killed and reported, does not hang the bridge"
else
    bad "R5 hung 'agy models' is killed and reported, does not hang the bridge" \
        "rc=$RC elapsed=${_R5_ELAPSED}s out=$OUT"
fi

# R6: a stale cache is USED (with a warning) when the live fetch fails, rather
# than the bridge hard-failing while a perfectly usable list sits on disk.
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

# R7: with NO cache to fall back to, the failure is fatal AND agy's own stderr
# is surfaced -- that text is the only diagnostic for an auth/network fault.
rm -f "$HOME/.cache/agy-bridge-models"
FAKE_AGY_MODELS_FAIL=1 _run OUT RC bash "$BRIDGE" --type code -- "no cache"
if [[ "$RC" -eq 2 && "$OUT" == *"FAKE-AGY-AUTH-FAILURE"* ]]; then
    ok "R7 fetch failure with no cache exits 2 and surfaces agy's stderr"
else
    bad "R7 fetch failure with no cache exits 2 and surfaces agy's stderr" "rc=$RC out=$OUT"
fi

# R8: a list with NO gemini ids at all is a degraded/unauthenticated agy, not a
# bad --type. It must say so rather than blaming the type the user picked.
rm -f "$HOME/.cache/agy-bridge-models"
FAKE_AGY_MODELS_GARBAGE=1 _run OUT RC bash "$BRIDGE" --type code -- "garbage list"
if [[ "$RC" -eq 2 && "$OUT" == *"no 'gemini-' ids"* && "$OUT" != *"for --type"* ]]; then
    ok "R8 model list with no gemini ids reports a degraded list, not a bad --type"
else
    bad "R8 model list with no gemini ids reports a degraded list, not a bad --type" "rc=$RC out=$OUT"
fi
# The garbage fetch above exits 0, so the bridge caches it (same shared $HOME
# as every other test in this run). Clear it so later tests still see a full
# model list on their next fetch -- same pattern as R3/R3c/R6.
rm -f "$HOME/.cache/agy-bridge-models"

# R4: gemini_shim.sh -m flash resolves against the LIVE `agy models` list and
# hands agy a real ID (delegate-agy-62x purge-guard). The map used to hold
# DISPLAY NAMES ("Gemini 3.6 Flash (High)") frozen at whatever agy shipped that
# week; agy's canonical identifier is the id, and a frozen literal of either
# kind goes stale on the next agy release. Any display name or hardcoded id
# reappearing on the wire fails here.
# (Reuses the SH2 FAKE_AGY_DUMP_ARGV harness defined below, in the
# "gemini_shim.sh: no stanza + --sandbox floor" section.)
R4_DUMP="$SANDBOX/purge_argv.log"
: > "$R4_DUMP"
rm -f "$HOME/.cache/agy-bridge-models"
FAKE_AGY_DUMP_ARGV="$R4_DUMP" _run OUT RC bash "$SHIM" -m flash -p x
R4_MODEL_VAL="$(awk '/^--model$/{getline; print; exit}' "$R4_DUMP")"
if [[ "$R4_MODEL_VAL" == "gemini-3.6-flash-high" ]]; then
    ok "R4 gemini_shim.sh -m flash resolves to a live agy id, not a display name (purge-guard)"
else
    bad "R4 gemini_shim.sh -m flash resolves to a live agy id, not a display name (purge-guard)" \
        "model=$R4_MODEL_VAL argv=$(cat "$R4_DUMP")"
fi
rm -f "$HOME/.cache/agy-bridge-models"

echo "== agy_bridge.sh --digest (ps3.2) =="

# D1: --digest appends OUTPUT CONTRACT AFTER the user prompt
FAKE_AGY_ECHO_PROMPT=1 _run OUT RC bash "$BRIDGE" --type code --digest -- "analyze this"
SUFFIX="${OUT##*analyze this}"
if [[ "$RC" -eq 0 && "$OUT" == *"analyze this"* && "$SUFFIX" == *"OUTPUT CONTRACT"* ]]; then
    ok "D1 --digest appends OUTPUT CONTRACT after prompt"
else
    bad "D1 --digest appends OUTPUT CONTRACT after prompt" "rc=$RC out=$OUT"
fi

# D2: --digest + oversized reply -> stderr warning mentioning "digest"
BIGREPLY="$(printf 'x%.0s' $(seq 1 20000))"
FAKE_AGY_STDOUT="$BIGREPLY" _run OUT RC bash "$BRIDGE" --type code --digest --digest-warn-chars 100 -- "analyze this"
if [[ "$RC" -eq 0 && "$OUT" == *"--digest reply is"* ]]; then
    ok "D2 --digest oversized reply -> warning mentions digest"
else
    bad "D2 --digest oversized reply -> warning mentions digest" "rc=$RC out=${OUT:0:200}..."
fi

# D3: oversized reply WITHOUT --digest -> no warning, byte-identical passthrough
BIGREPLY="$(printf 'x%.0s' $(seq 1 20000))"
FAKE_AGY_STDOUT="$BIGREPLY" _run OUT RC bash "$BRIDGE" --type code -- "analyze this"
if [[ "$RC" -eq 0 && "$OUT" == "$BIGREPLY" ]]; then
    ok "D3 oversized reply without --digest -> untouched passthrough"
else
    bad "D3 oversized reply without --digest -> untouched passthrough" "rc=$RC len=${#OUT}"
fi

# D4: no --digest -> OUTPUT CONTRACT absent from echoed prompt
FAKE_AGY_ECHO_PROMPT=1 _run OUT RC bash "$BRIDGE" --type code -- "analyze this"
if [[ "$RC" -eq 0 && "$OUT" == *"analyze this"* && "$OUT" != *"OUTPUT CONTRACT"* ]]; then
    ok "D4 no --digest -> OUTPUT CONTRACT absent"
else
    bad "D4 no --digest -> OUTPUT CONTRACT absent" "rc=$RC out=$OUT"
fi

echo "== agy_bridge.sh prompt-delivery contract (2dc.4) =="

# T1 no-stdin + argv-no-leak (combined).
(
    RECDIR="$SANDBOX/recorder"
    mkdir -p "$RECDIR"
    ARGV_LOG="$SANDBOX/argv.log"
    STDIN_LOG="$SANDBOX/stdin.log"
    : > "$ARGV_LOG"; : > "$STDIN_LOG"
    cat > "$RECDIR/agy" <<EOF
#!/usr/bin/env bash
set -u
printf '%s\n' "\$@" >> "$ARGV_LOG"
cat > "$STDIN_LOG"
exec "$HERE/fake-agy.sh" "\$@" < "$STDIN_LOG"
EOF
    chmod +x "$RECDIR/agy"
    export PATH="$RECDIR:$PATH"
    TOKEN="ZZLEAKTOKEN42"
    OUT="$(FAKE_AGY_ECHO_PROMPT=1 bash "$BRIDGE" --type code --timeout 5 -- "$TOKEN" 2>/dev/null)"
    token_in_out=0;   [[ "$OUT" == *"$TOKEN"* ]] && token_in_out=1
    token_in_argv=0;  grep -q "$TOKEN" "$ARGV_LOG" && token_in_argv=1
    token_in_stdin=0; grep -q "$TOKEN" "$STDIN_LOG" && token_in_stdin=1
    pointer_in_argv=0; grep -q "GEMINI.md context" "$ARGV_LOG" && pointer_in_argv=1
    if [[ "$token_in_out" -eq 1 && "$token_in_argv" -eq 0 && "$token_in_stdin" -eq 0 && "$pointer_in_argv" -eq 1 ]]; then
        echo "T1_RESULT=ok"
    else
        echo "T1_RESULT=fail token_in_out=$token_in_out token_in_argv=$token_in_argv token_in_stdin=$token_in_stdin pointer_in_argv=$pointer_in_argv out=$OUT argv=$(cat "$ARGV_LOG") stdin=$(cat "$STDIN_LOG")"
    fi
) > "$SANDBOX/t1.out" 2>&1
T1_LINE="$(grep '^T1_RESULT=' "$SANDBOX/t1.out")"
if [[ "$T1_LINE" == "T1_RESULT=ok" ]]; then
    ok "T1 prompt delivered via GEMINI.md TASK, absent from argv AND stdin"
else
    bad "T1 prompt delivered via GEMINI.md TASK, absent from argv AND stdin" "$T1_LINE"
fi

# T2 large-prompt (no ARG_MAX).
FILLER="$(printf 'a%.0s' $(seq 1 131200))"
BIGPROMPT="HEADSENTINEL${FILLER}TAILSENTINEL"
OUT="$(printf '%s' "$BIGPROMPT" | FAKE_AGY_ECHO_PROMPT=1 bash "$BRIDGE" --type code 2>&1)"; RC=$?
if [[ "$RC" -eq 0 && "$OUT" == *"HEADSENTINEL"* && "$OUT" == *"TAILSENTINEL"* && "$OUT" != *"Argument list too long"* ]]; then
    ok "T2 large (>131072B) prompt delivered intact, no ARG_MAX error"
else
    bad "T2 large (>131072B) prompt delivered intact, no ARG_MAX error" "rc=$RC out_len=${#OUT} out=${OUT:0:200}..."
fi

# T3 empty-prompt. Strengthened (2dc.7): must exit 2 with the exact guard
# message AND leave the argv-dump file empty, proving agy was never invoked
# (the old assertion only checked rc!=0, which the empty-OUTPUT guard at
# agy_bridge.sh:318 also satisfies -- passing for the wrong reason).
T3_DUMP="$SANDBOX/t3_argv.log"; : > "$T3_DUMP"
FAKE_AGY_DUMP_ARGV="$T3_DUMP" _run OUT RC bash "$BRIDGE" --type code -- ""
if [[ "$RC" -eq 2 && "$OUT" == *"ERROR: empty prompt"* ]] && ! grep -q -- '--print' "$T3_DUMP"; then
    ok "T3 empty prompt -> exit 2, ERROR: empty prompt, agy never invoked"
else
    bad "T3 empty prompt -> exit 2, ERROR: empty prompt, agy never invoked" "rc=$RC out=$OUT argv=$(cat "$T3_DUMP" 2>/dev/null)"
fi

# T3b: whitespace-only prompt via args (-- "   ") -- grep -q '[^[:space:]]'
# must reject a prompt of pure whitespace, not just byte-empty.
T3B_DUMP="$SANDBOX/t3b_argv.log"; : > "$T3B_DUMP"
FAKE_AGY_DUMP_ARGV="$T3B_DUMP" _run OUT RC bash "$BRIDGE" --type code -- "   "
if [[ "$RC" -eq 2 && "$OUT" == *"ERROR: empty prompt"* ]] && ! grep -q -- '--print' "$T3B_DUMP"; then
    ok "T3b whitespace-only prompt via args -> exit 2, agy never invoked"
else
    bad "T3b whitespace-only prompt via args -> exit 2, agy never invoked" "rc=$RC out=$OUT"
fi

# T3c: whitespace-only prompt via stdin (printf '\n\n' |).
T3C_DUMP="$SANDBOX/t3c_argv.log"; : > "$T3C_DUMP"
OUT="$(printf '\n\n' | FAKE_AGY_DUMP_ARGV="$T3C_DUMP" bash "$BRIDGE" --type code 2>&1)"; RC=$?
if [[ "$RC" -eq 2 && "$OUT" == *"ERROR: empty prompt"* ]] && ! grep -q -- '--print' "$T3C_DUMP"; then
    ok "T3c whitespace-only prompt via stdin -> exit 2, agy never invoked"
else
    bad "T3c whitespace-only prompt via stdin -> exit 2, agy never invoked" "rc=$RC out=$OUT"
fi

# T3d: --type search -- "" -- proves the guard runs BEFORE the search-prefix
# augmentation (agy_bridge.sh:199-205), which would otherwise make an empty
# user prompt non-empty by prepending the search_web instruction.
T3D_DUMP="$SANDBOX/t3d_argv.log"; : > "$T3D_DUMP"
FAKE_AGY_DUMP_ARGV="$T3D_DUMP" _run OUT RC bash "$BRIDGE" --type search -- ""
if [[ "$RC" -eq 2 && "$OUT" == *"ERROR: empty prompt"* ]] && ! grep -q -- '--print' "$T3D_DUMP"; then
    ok "T3d --type search empty prompt rejected before search-prefix augmentation"
else
    bad "T3d --type search empty prompt rejected before search-prefix augmentation" "rc=$RC out=$OUT"
fi

# T3e: --digest -- "" -- proves the guard runs BEFORE the digest output
# contract append (agy_bridge.sh:216-219), which would otherwise make an
# empty user prompt non-empty by appending the OUTPUT CONTRACT text.
T3E_DUMP="$SANDBOX/t3e_argv.log"; : > "$T3E_DUMP"
FAKE_AGY_DUMP_ARGV="$T3E_DUMP" _run OUT RC bash "$BRIDGE" --type code --digest -- ""
if [[ "$RC" -eq 2 && "$OUT" == *"ERROR: empty prompt"* ]] && ! grep -q -- '--print' "$T3E_DUMP"; then
    ok "T3e --digest empty prompt rejected before digest output-contract append"
else
    bad "T3e --digest empty prompt rejected before digest output-contract append" "rc=$RC out=$OUT"
fi

# T4: a SIGTERM-ignoring agy must not hang the delegation call. The bridge's own
# --timeout has to escalate to SIGKILL, exactly as the model fetch does.
_T4_START=$(date +%s)
FAKE_AGY_PRINT_HANG=1 _run OUT RC bash "$BRIDGE" --type code --timeout 2 -- "delegation hang"
_T4_ELAPSED=$(( $(date +%s) - _T4_START ))
if [[ "$RC" -ne 0 && "$_T4_ELAPSED" -lt 40 && "$OUT" == *"timeout"* ]]; then
    ok "T4 hung delegation call is killed and reported, does not hang the bridge"
else
    bad "T4 hung delegation call is killed and reported, does not hang the bridge" \
        "rc=$RC elapsed=${_T4_ELAPSED}s out=$OUT"
fi

# T5: a 137 that lands well inside the bridge's own --timeout bound is NOT the
# bridge's -k escalation (which can only fire at/after the bound) -- it's an
# external kill (OOM killer, kill -9, cgroup preemption). Must be reported
# distinctly from a timeout, not folded into the timeout message.
FAKE_AGY_PRINT_KILL9=1 _run OUT RC bash "$BRIDGE" --type code --timeout 60 -- "oom check"
if [[ "$RC" -eq 137 && "$OUT" == *"killed"* && "$OUT" != *"timeout after"* ]]; then
    ok "T5 137 well inside --timeout bound reported as killed, not as a timeout"
else
    bad "T5 137 well inside --timeout bound reported as killed, not as a timeout" "rc=$RC out=$OUT"
fi

echo "== agy_bridge.sh --add-dir passthrough (delegate-agy-0i9.2) =="

# AD1: caller --add-dir reaches agy AND stays before the trailing WORK_DIR
# --add-dir. fake-agy.sh resolves GEMINI.md/TASK from the LAST --add-dir seen
# (tests/fake-agy.sh:57-59), so this also pins WORK_DIR-last: if a future edit
# appended caller dirs after WORK_DIR, the TASK would no longer be found and
# this case would fail (rc!=0, no marker in OUT).
AD1_DIR="$SANDBOX/add-dir-target"
mkdir -p "$AD1_DIR"
AD1_ARGV="$SANDBOX/ad1_argv.log"
: > "$AD1_ARGV"
AD1_MARKER="ADDDIRMARKER77"
FAKE_AGY_DUMP_ARGV="$AD1_ARGV" FAKE_AGY_ECHO_PROMPT=1 _run OUT RC bash "$BRIDGE" --type code --add-dir "$AD1_DIR" -- "$AD1_MARKER"
AD1_CALLER_SEEN=0; grep -qF "$AD1_DIR" "$AD1_ARGV" && AD1_CALLER_SEEN=1
AD1_LAST_ADDDIR_VAL="$(awk '/^--add-dir$/{v=""; getline v} END{print v}' "$AD1_ARGV")"
if [[ "$RC" -eq 0 && "$AD1_CALLER_SEEN" -eq 1 && "$AD1_LAST_ADDDIR_VAL" != "$AD1_DIR" && "$OUT" == *"$AD1_MARKER"* ]]; then
    ok "AD1 caller --add-dir reaches agy, stays before trailing WORK_DIR --add-dir"
else
    bad "AD1 caller --add-dir reaches agy, stays before trailing WORK_DIR --add-dir" "rc=$RC caller_seen=$AD1_CALLER_SEEN last=$AD1_LAST_ADDDIR_VAL out=$OUT argv=$(cat "$AD1_ARGV")"
fi

# AD2: --add-dir with a non-directory path is rejected (exit 2) by the
# `cd -- ... 2>/dev/null` guard. Asserted via EXACT output match (not
# substring): if the 2>/dev/null were dropped, `cd`'s own
# "cd: ...: No such file or directory" line would leak to stderr first — an
# exact match catches that, a substring match would not.
AD2_BAD="$SANDBOX/add-dir-missing"
_run OUT RC bash "$BRIDGE" --type code --add-dir "$AD2_BAD" -- "hi"
if [[ "$RC" -eq 2 && "$OUT" == "ERROR: --add-dir '$AD2_BAD' is not a directory" ]]; then
    ok "AD2 --add-dir rejects non-directory path (exit 2, no cd stderr leak)"
else
    bad "AD2 --add-dir rejects non-directory path (exit 2, no cd stderr leak)" "rc=$RC out=$OUT"
fi

# AD3: a directory literally named "-P", passed as a bare relative arg, must
# be granted as itself, not parsed as a `cd` option (which would silently
# land on $HOME and over-grant it). The relative form is required to
# reproduce: an absolute path merely ending in "/-P" never reaches cd's
# option parser.
AD3_ROOT="$SANDBOX/ad3root"
mkdir -p "$AD3_ROOT/-P"
AD3_RESOLVED="$(cd "$AD3_ROOT/-P" && pwd)"
AD3_ARGV="$SANDBOX/ad3_argv.log"
: > "$AD3_ARGV"
AD3_OLDPWD="$PWD"
cd "$AD3_ROOT" || exit 1
FAKE_AGY_DUMP_ARGV="$AD3_ARGV" FAKE_AGY_STDOUT="ok" _run OUT RC bash "$BRIDGE" --type code --add-dir "-P" -- "hi"
cd "$AD3_OLDPWD" || exit 1
AD3_TARGET_SEEN=0; grep -qF "$AD3_RESOLVED" "$AD3_ARGV" && AD3_TARGET_SEEN=1
AD3_HOME_LEAKED=0; grep -qxF "$HOME" "$AD3_ARGV" && AD3_HOME_LEAKED=1
if [[ "$RC" -eq 0 && "$AD3_TARGET_SEEN" -eq 1 && "$AD3_HOME_LEAKED" -eq 0 ]]; then
    ok "AD3 --add-dir named '-P' grants itself, not \$HOME (cd -- / CDPATH= guard)"
else
    bad "AD3 --add-dir named '-P' grants itself, not \$HOME (cd -- / CDPATH= guard)" "rc=$RC target_seen=$AD3_TARGET_SEEN home_leaked=$AD3_HOME_LEAKED argv=$(cat "$AD3_ARGV")"
fi

# AD4: --add-dir "$HOME" is refused with exit 2 and the broad-grant message.
_run OUT RC bash "$BRIDGE" --type code --add-dir "$HOME" -- "hi"
if [[ "$RC" -eq 2 && "$OUT" == "ERROR: --add-dir '$HOME' grants broad filesystem access; set AGY_ALLOW_BROAD_GRANT=1 to override" ]]; then
    ok "AD4 --add-dir \$HOME refused by default (exit 2, message matches)"
else
    bad "AD4 --add-dir \$HOME refused by default (exit 2, message matches)" "rc=$RC out=$OUT"
fi

# AD5: --add-dir / is refused with exit 2.
_run OUT RC bash "$BRIDGE" --type code --add-dir / -- "hi"
if [[ "$RC" -eq 2 && "$OUT" == "ERROR: --add-dir '/' grants broad filesystem access; set AGY_ALLOW_BROAD_GRANT=1 to override" ]]; then
    ok "AD5 --add-dir / refused by default (exit 2)"
else
    bad "AD5 --add-dir / refused by default (exit 2)" "rc=$RC out=$OUT"
fi

# AD6: AGY_ALLOW_BROAD_GRANT=1 overrides the $HOME refusal, warns on stderr,
# and $HOME reaches agy's argv.
AD6_ARGV="$SANDBOX/ad6_argv.log"
: > "$AD6_ARGV"
FAKE_AGY_DUMP_ARGV="$AD6_ARGV" FAKE_AGY_STDOUT="ok" AGY_ALLOW_BROAD_GRANT=1 \
    _run OUT RC bash "$BRIDGE" --type code --add-dir "$HOME" -- "hi"
AD6_WARNED=0; [[ "$OUT" == *"WARNING: AGY_ALLOW_BROAD_GRANT=1"* ]] && AD6_WARNED=1
AD6_HOME_SEEN=0; grep -qxF "$HOME" "$AD6_ARGV" && AD6_HOME_SEEN=1
if [[ "$RC" -eq 0 && "$AD6_WARNED" -eq 1 && "$AD6_HOME_SEEN" -eq 1 ]]; then
    ok "AD6 AGY_ALLOW_BROAD_GRANT=1 overrides \$HOME refusal, warns, grants \$HOME"
else
    bad "AD6 AGY_ALLOW_BROAD_GRANT=1 overrides \$HOME refusal, warns, grants \$HOME" "rc=$RC warned=$AD6_WARNED home_seen=$AD6_HOME_SEEN out=$OUT argv=$(cat "$AD6_ARGV")"
fi

# AD7: --add-dir "$HOME/sub" (a subdirectory) is still granted normally,
# proving the guard is an exact-match refusal, not a prefix match.
AD7_DIR="$HOME/sub"
mkdir -p "$AD7_DIR"
AD7_ARGV="$SANDBOX/ad7_argv.log"
: > "$AD7_ARGV"
FAKE_AGY_DUMP_ARGV="$AD7_ARGV" FAKE_AGY_STDOUT="ok" _run OUT RC bash "$BRIDGE" --type code --add-dir "$AD7_DIR" -- "hi"
AD7_SEEN=0; grep -qxF "$AD7_DIR" "$AD7_ARGV" && AD7_SEEN=1
if [[ "$RC" -eq 0 && "$AD7_SEEN" -eq 1 ]]; then
    ok "AD7 --add-dir \$HOME/sub still granted (exact-match refusal only)"
else
    bad "AD7 --add-dir \$HOME/sub still granted (exact-match refusal only)" "rc=$RC seen=$AD7_SEEN argv=$(cat "$AD7_ARGV")"
fi

# AD8: HOME with a trailing slash must not bypass the broad-grant guard.
# --add-dir "$HOME" resolves without a trailing slash; if the guard compared
# raw "$_d" == "$HOME" it would silently miss this and grant access.
AD8_HOME_NOSLASH="$HOME"
_run OUT RC env HOME="${AD8_HOME_NOSLASH}/" bash "$BRIDGE" --type code --add-dir "$AD8_HOME_NOSLASH" -- "hi"
if [[ "$RC" -eq 2 && "$OUT" == "ERROR: --add-dir '$AD8_HOME_NOSLASH' grants broad filesystem access; set AGY_ALLOW_BROAD_GRANT=1 to override" ]]; then
    ok "AD8 trailing-slash \$HOME does not bypass broad-grant guard"
else
    bad "AD8 trailing-slash \$HOME does not bypass broad-grant guard" "rc=$RC out=$OUT"
fi

echo "== policy files: fail-closed allowlist (vfn T1) =="

# ST1
CATCHALL_UNIQ="$(grep -h 'allowlist catch-all' \
    "$ROOT/config/policies/search.md" \
    "$ROOT/config/policies/shim-sandbox.md" \
    "$ROOT/config/policies/shim-default.md" \
    "$ROOT/config/policies/shim-yolo.md" | sort -u | wc -l)"
if [[ "$CATCHALL_UNIQ" -eq 1 ]]; then
    ok "ST1 catch-all line byte-identical across search+shim policies"
else
    bad "ST1 catch-all line byte-identical across search+shim policies" "distinct=$CATCHALL_UNIQ"
fi

# ST2
CATCHALL="$(grep -h 'allowlist catch-all' "$ROOT/config/policies/search.md" | head -1)"
if [[ "$CATCHALL" == *"ctx_call"* && "$CATCHALL" == *"tokensave_"* && "$CATCHALL" == *"mcp__"* ]]; then
    ok "ST2 catch-all covers ctx_call + tokensave_ + mcp__ leak vectors"
else
    bad "ST2 catch-all covers ctx_call + tokensave_ + mcp__ leak vectors" "$CATCHALL"
fi

# ST3
ST3_PERMIT_OK=1
for f in code review-analysis implement; do
    grep -q 'ctx_read, ctx_search, tokensave_context' "$ROOT/config/policies/$f.md" \
        || ST3_PERMIT_OK=0
done
ST3_EXEC_LEAK="$(grep -h '^PERMITTED:' "$ROOT"/config/policies/*.md \
    | grep -Ec 'ctx_shell|ctx_call|ctx_edit|ctx_execute')"
if [[ "$ST3_PERMIT_OK" -eq 1 && "$ST3_EXEC_LEAK" -eq 0 ]]; then
    ok "ST3 MCP policies permit read-only ctx/tokensave, never exec/edit tools"
else
    bad "ST3 MCP policies permit read-only ctx/tokensave, never exec/edit tools" "permit_ok=$ST3_PERMIT_OK exec_leak=$ST3_EXEC_LEAK"
fi

echo "== agent + skill docs: exit-3, WebSearch, version (vfn T5/T6) =="

# ST4
ST4_OK=1
for f in agents/agy-delegate-code.md agents/agy-delegate-search.md; do
    row="$(grep '| 3 |' "$ROOT/$f")"
    [[ -n "$row" ]] || ST4_OK=0
    [[ "$row" == *"empty_output"* && "$row" == *"quota"* && "$row" == *"auth"* ]] || ST4_OK=0
    [[ "$row" == *"backend"* ]] && ST4_OK=0
done
grep -qi 'exit 3' "$ROOT/skills/agy-delegate/SKILL.md" || ST4_OK=0
if [[ "$ST4_OK" -eq 1 ]]; then
    ok "ST4 exit-3 rows classify empty_output/quota/auth (no invented backend class)"
else
    bad "ST4 exit-3 rows classify empty_output/quota/auth (no invented backend class)" "ok=$ST4_OK"
fi

# ST5
ST5_OK=1
grep -q 'WebSearch' "$ROOT/agents/agy-delegate-search.md" || ST5_OK=0
grep -qi 'websearch' "$ROOT/skills/agy-delegate/SKILL.md" || ST5_OK=0
ST5_RESIDUAL="$(grep -rniE 'prefer.*agy.*over.*websearch|do not use the native websearch' \
    "$ROOT/skills/agy-delegate/SKILL.md" \
    "$ROOT/agents/agy-delegate-search.md" \
    "$ROOT/.claude/commands/agy-search.md" \
    "$ROOT/hooks/agy-subagent-policy.sh" \
    "$ROOT/README.md" 2>/dev/null | wc -l)"
if [[ "$ST5_OK" -eq 1 && "$ST5_RESIDUAL" -eq 0 ]]; then
    ok "ST5 WebSearch surfaced, zero residual agy-first framing"
else
    bad "ST5 WebSearch surfaced, zero residual agy-first framing" "ok=$ST5_OK residual=$ST5_RESIDUAL"
fi

# ST6: .claude-plugin/plugin.json is the single source of truth for the
# plugin version; agy-setup.md and agy-uninstall.md must each declare it
# exactly, anchored line-start-to-line-end so a longer version (1.5.11)
# cannot satisfy a shorter expected one (1.5.1) via substring match.
ST6_VERSION="$(grep -m1 '"version"' "$ROOT/.claude-plugin/plugin.json" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
ST6_OK=1
[[ -n "$ST6_VERSION" ]] || ST6_OK=0
ST6_ESC="${ST6_VERSION//./\\.}"
for f in "$ROOT/.claude/commands/agy-setup.md" "$ROOT/.claude/commands/agy-uninstall.md"; do
    grep -qE "^version: ${ST6_ESC}\$" "$f" || ST6_OK=0
done
if [[ "$ST6_OK" -eq 1 ]]; then
    ok "ST6 version $ST6_VERSION in manifest+both command docs"
else
    bad "ST6 version $ST6_VERSION in manifest+both command docs" "ok=$ST6_OK"
fi

echo "== MCP tool-preference stanza gating (vfn T5) =="

_T7_HINT="$HOME/.config/agy-delegate/config.json"; _T7_CACHE="$HOME/.cache/agy-bridge-mcp"
_t7_save(){ [[ -f "$_T7_HINT" ]] && cp "$_T7_HINT" "$_T7_HINT.t7bak"; [[ -f "$_T7_CACHE" ]] && cp "$_T7_CACHE" "$_T7_CACHE.t7bak"; }
_t7_restore(){ if [[ -f "$_T7_HINT.t7bak" ]]; then mv "$_T7_HINT.t7bak" "$_T7_HINT"; else rm -f "$_T7_HINT"; fi; if [[ -f "$_T7_CACHE.t7bak" ]]; then mv "$_T7_CACHE.t7bak" "$_T7_CACHE"; else rm -f "$_T7_CACHE"; fi; }
trap '_t7_restore; cleanup' EXIT
_t7_save; mkdir -p "$(dirname "$_T7_HINT")"

# M1
printf '%s\n' '{"lean_ctx":true,"tokensave":false}' > "$_T7_HINT"; rm -f "$_T7_CACHE"
FAKE_AGY_ECHO_PROMPT=1 _run OUT RC bash "$BRIDGE" --type code -- "x"
if [[ "$OUT" == *"TOOL PREFERENCE"* ]]; then
    ok "M1 stanza present when an MCP server is on (code)"
else
    bad "M1 stanza present when an MCP server is on (code)" "rc=$RC out=${OUT:0:300}"
fi

# M2
printf '%s\n' '{"lean_ctx":false,"tokensave":false}' > "$_T7_HINT"; rm -f "$_T7_CACHE"
FAKE_AGY_ECHO_PROMPT=1 _run OUT RC bash "$BRIDGE" --type code -- "x"
if [[ "$OUT" != *"TOOL PREFERENCE"* ]]; then
    ok "M2 stanza absent when all MCP servers off (code)"
else
    bad "M2 stanza absent when all MCP servers off (code)" "rc=$RC out=${OUT:0:300}"
fi

# M3
printf '%s\n' '{"lean_ctx":true}' > "$_T7_HINT"; rm -f "$_T7_CACHE"
FAKE_AGY_ECHO_PROMPT=1 _run OUT RC bash "$BRIDGE" --type search -- "x"
if [[ "$OUT" != *"TOOL PREFERENCE"* ]]; then
    ok "M3 no stanza for search delegation (excluded)"
else
    bad "M3 no stanza for search delegation (excluded)" "rc=$RC out=${OUT:0:300}"
fi

echo "== gemini_shim.sh: no stanza + --sandbox floor (vfn T4/T5) =="

# SH1
printf '%s\n' '{"lean_ctx":true,"tokensave":true}' > "$_T7_HINT"; rm -f "$_T7_CACHE"
FAKE_AGY_ECHO_PROMPT=1 _run OUT RC bash "$SHIM" -p "x"
SH1_OK=1
[[ "$OUT" == *"TOOL PREFERENCE"* ]] && SH1_OK=0
FAKE_AGY_ECHO_PROMPT=1 _run OUT RC bash "$SHIM" --sandbox -p "x"
[[ "$OUT" == *"TOOL PREFERENCE"* ]] && SH1_OK=0
FAKE_AGY_ECHO_PROMPT=1 _run OUT RC bash "$SHIM" --yolo -p "x"
[[ "$OUT" == *"TOOL PREFERENCE"* ]] && SH1_OK=0
if [[ "$SH1_OK" -eq 1 ]]; then
    ok "SH1 shim never appends TOOL PREFERENCE stanza (default/--sandbox/--yolo)"
else
    bad "SH1 shim never appends TOOL PREFERENCE stanza (default/--sandbox/--yolo)" "out=${OUT:0:300}"
fi

# SH2
SH2_DUMP="$SANDBOX/shim_argv.log"
: > "$SH2_DUMP"
FAKE_AGY_DUMP_ARGV="$SH2_DUMP" _run OUT RC bash "$SHIM" -p "x"
grep -qx -- '--sandbox' "$SH2_DUMP"; SH2_DEFAULT=$?
: > "$SH2_DUMP"
FAKE_AGY_DUMP_ARGV="$SH2_DUMP" _run OUT RC bash "$SHIM" --sandbox -p "x"
grep -qx -- '--sandbox' "$SH2_DUMP"; SH2_SANDBOX=$?
: > "$SH2_DUMP"
FAKE_AGY_DUMP_ARGV="$SH2_DUMP" _run OUT RC bash "$SHIM" --yolo -p "x"
grep -qx -- '--sandbox' "$SH2_DUMP"; SH2_YOLO=$?
: > "$SH2_DUMP"
FAKE_AGY_DUMP_ARGV="$SH2_DUMP" _run OUT RC bash "$SHIM" --approval-mode yolo -p "x"
grep -qx -- '--sandbox' "$SH2_DUMP"; SH2_APPROVAL_YOLO=$?
if [[ "$SH2_DEFAULT" -eq 0 && "$SH2_SANDBOX" -eq 0 && "$SH2_YOLO" -ne 0 && "$SH2_APPROVAL_YOLO" -ne 0 ]]; then
    ok "SH2 --sandbox present on read-only shim modes, absent on yolo"
else
    bad "SH2 --sandbox present on read-only shim modes, absent on yolo" "default=$SH2_DEFAULT sandbox=$SH2_SANDBOX yolo=$SH2_YOLO approval_yolo=$SH2_APPROVAL_YOLO"
fi

# SH3
_run OUT RC bash "$SHIM" --version
if [[ "$RC" -eq 0 && "$OUT" == *"agy "* ]]; then
    ok "SH3 shim --version still exits 0 + prints version"
else
    bad "SH3 shim --version still exits 0 + prints version" "rc=$RC out=$OUT"
fi

echo "== gemini_shim.sh: unbounded agy calls (delegate-agy-pgx) =="

# SH4: a SIGTERM-ignoring agy must not hang the shim's main --print call. The
# shim's own timeout has to escalate to SIGKILL, exactly as the bridge's does.
_SH4_START=$(date +%s)
FAKE_AGY_PRINT_HANG=1 GEMINI_SHIM_TIMEOUT=2 _run OUT RC bash "$SHIM" -p "hang check"
_SH4_ELAPSED=$(( $(date +%s) - _SH4_START ))
if [[ "$RC" -ne 0 && "$_SH4_ELAPSED" -lt 40 && "$OUT" == *"timeout"* ]]; then
    ok "SH4 hung shim main call is killed and reported, does not hang the shim"
else
    bad "SH4 hung shim main call is killed and reported, does not hang the shim" \
        "rc=$RC elapsed=${_SH4_ELAPSED}s out=$OUT"
fi

# SH5: a SIGTERM-ignoring agy must not hang `gemini --version` either --
# gemini_shim.sh:94 was the shim's other unbounded agy call site.
_SH5_START=$(date +%s)
FAKE_AGY_VERSION_HANG=1 _run OUT RC bash "$SHIM" --version
_SH5_ELAPSED=$(( $(date +%s) - _SH5_START ))
if [[ "$RC" -ne 0 && "$_SH5_ELAPSED" -lt 40 && "$OUT" == *"timeout"* ]]; then
    ok "SH5 hung --version is killed and reported, does not hang the shim"
else
    bad "SH5 hung --version is killed and reported, does not hang the shim" \
        "rc=$RC elapsed=${_SH5_ELAPSED}s out=$OUT"
fi

# SH6: a 137 that lands well inside the shim's own $GEMINI_SHIM_TIMEOUT bound is
# NOT the shim's -k escalation (which can only fire at/after the bound) -- it's
# an external kill (OOM killer, kill -9, cgroup preemption). Must be reported
# distinctly from a timeout, not folded into the timeout message.
FAKE_AGY_PRINT_KILL9=1 GEMINI_SHIM_TIMEOUT=60 _run OUT RC bash "$SHIM" -p "oom check"
if [[ "$RC" -eq 137 && "$OUT" == *"killed"* && "$OUT" != *"timeout after"* ]]; then
    ok "SH6 137 well inside GEMINI_SHIM_TIMEOUT bound reported as killed, not as a timeout"
else
    bad "SH6 137 well inside GEMINI_SHIM_TIMEOUT bound reported as killed, not as a timeout" "rc=$RC out=$OUT"
fi

echo "== gemini_shim.sh: dynamic model resolution (delegate-agy-62x) =="

_SHIM_CACHE="$HOME/.cache/agy-bridge-models"
# _shim_model DUMPVAR -- run the shim with the given args and echo the value the
# shim passed to agy's --model. Every case below asserts on the wire, not on
# the map file: what agy receives is the only thing that matters.
_shim_model() {
    local dump="$SANDBOX/shim_model_argv.log"
    : > "$dump"
    FAKE_AGY_DUMP_ARGV="$dump" bash "$SHIM" "$@" >/dev/null 2>&1 || true
    awk '/^--model$/{getline; print; exit}' "$dump"
}

# SH7: an alias resolves to the NEWEST id in its class from the live list --
# the anti-freeze assertion. The seeded list carries versions (9.8/9.9) that
# appear in no map, no script and no fixture, so only a live `sort -V | tail -1`
# over the actual list can produce 9.9. A map that pins a version cannot.
mkdir -p "$(dirname "$_SHIM_CACHE")"
printf '%s\t%s\n' \
    "gemini-9.8-flash-high" "Gemini 9.8 Flash (High)" \
    "gemini-9.9-flash-high" "Gemini 9.9 Flash (High)" \
    "gemini-9.9-pro-high"   "Gemini 9.9 Pro (High)" > "$_SHIM_CACHE"
SH7_FLASH="$(_shim_model -m flash -p x)"
SH7_PRO="$(_shim_model -m pro -p x)"
if [[ "$SH7_FLASH" == "gemini-9.9-flash-high" && "$SH7_PRO" == "gemini-9.9-pro-high" ]]; then
    ok "SH7 aliases resolve to the newest live id in their class (not a frozen version)"
else
    bad "SH7 aliases resolve to the newest live id in their class (not a frozen version)" \
        "flash=$SH7_FLASH pro=$SH7_PRO"
fi
rm -f "$_SHIM_CACHE"

# SH8: an explicit id that is live RIGHT NOW is honored verbatim. A pinned
# request must never be silently upgraded: gemini-3.5-flash-low is both a live
# id and a map key, so a map-first implementation would rewrite it to 3.6.
SH8_ID="$(_shim_model -m gemini-3.5-flash-low -p x)"
if [[ "$SH8_ID" == "gemini-3.5-flash-low" ]]; then
    ok "SH8 explicit live id passes through unchanged (no silent version upgrade)"
else
    bad "SH8 explicit live id passes through unchanged (no silent version upgrade)" "model=$SH8_ID"
fi
rm -f "$_SHIM_CACHE"

# SH9: an unrecognised name still REACHES agy unchanged. This shim shadows the
# system `gemini` on PATH for Octopus/Metaswarm; rejecting a name it does not
# know would break every caller using a model this map has never heard of. It
# warns (a live list contradicts the name) but must not rewrite or refuse it.
# stdout and stderr are captured SEPARATELY here, not via _run (which merges
# them): the warning must reach stderr and must NOT touch stdout. A regression
# to a plain `echo` would corrupt the --output-format json envelope Metaswarm
# parses, and a merged capture cannot tell the two cases apart.
SH9_DUMP="$SANDBOX/sh9_argv.log"
SH9_OUT="$SANDBOX/sh9.out"
SH9_ERR="$SANDBOX/sh9.err"
: > "$SH9_DUMP"
FAKE_AGY_DUMP_ARGV="$SH9_DUMP" FAKE_AGY_STDOUT="ok" \
    bash "$SHIM" -m zzz-unknown-model -p x > "$SH9_OUT" 2> "$SH9_ERR"
RC=$?
SH9_ID="$(awk '/^--model$/{getline; print; exit}' "$SH9_DUMP")"
if [[ "$RC" -eq 0 && "$SH9_ID" == "zzz-unknown-model" ]] \
   && grep -q 'ok' "$SH9_OUT" \
   && grep -q 'WARNING' "$SH9_ERR" \
   && ! grep -q 'WARNING' "$SH9_OUT"; then
    ok "SH9 unknown model reaches agy unchanged; warning on stderr only, never stdout"
else
    bad "SH9 unknown model reaches agy unchanged; warning on stderr only, never stdout" \
        "rc=$RC model=$SH9_ID stdout=$(cat "$SH9_OUT") stderr=$(cat "$SH9_ERR")"
fi
rm -f "$_SHIM_CACHE"

# SH10: resolution survives a FAILED fetch via the stale cache, silently. The
# bridge shares this cache file; a 2-hour-old entry is past the 60-min refresh
# window, so this exercises fetch -> fail -> stale fallback. 7.7 exists only in
# this cache, so a resolved 7.7 can only have come from it. No WARNING: a
# PATH-shadowing `gemini` degrading to its cache is normal operation, not an
# event every Octopus/Metaswarm log line needs to carry.
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

# SH11: the model fetch is BOUNDED (delegate-agy-pgx). It is the shim's third
# agy call site; agy ignores SIGTERM, so only `timeout -k` ends a hung fetch.
# With no cache to fall back to, the shim must still deliver the prompt with
# the name passed through untouched -- an unreachable model list may not be
# allowed to fail, or stall, a `gemini` that shadows the system binary.
# The invocation is wrapped in `timeout 30` so an unbounded-fetch regression
# fails the suite in 30s instead of stalling it for the fixture's full 300s
# sleep. rc=124 from that outer bound IS the failure signal, and the elapsed
# assertion below still distinguishes "returned fast" from "returned at all".
rm -f "$_SHIM_CACHE"
_SH11_START=$(date +%s)
SH11_DUMP="$SANDBOX/sh11_argv.log"
: > "$SH11_DUMP"
FAKE_AGY_MODELS_HANG=1 AGY_MODELS_TIMEOUT=2 FAKE_AGY_DUMP_ARGV="$SH11_DUMP" FAKE_AGY_STDOUT="ok" \
    _run OUT RC timeout 30 bash "$SHIM" -m flash -p x
_SH11_ELAPSED=$(( $(date +%s) - _SH11_START ))
SH11_ID="$(awk '/^--model$/{getline; print; exit}' "$SH11_DUMP")"
if [[ "$RC" -eq 0 && "$_SH11_ELAPSED" -lt 25 && "$SH11_ID" == "flash" && "$OUT" != *"WARNING"* ]]; then
    ok "SH11 hung 'agy models' is killed; shim degrades to pass-through, does not hang"
else
    bad "SH11 hung 'agy models' is killed; shim degrades to pass-through, does not hang" \
        "rc=$RC elapsed=${_SH11_ELAPSED}s model=$SH11_ID out=$OUT"
fi
rm -f "$_SHIM_CACHE"

# SH12: HOME unset must not break the shim (regression guard). The model cache
# lives under $HOME, but this script runs under `set -u` and shadows the system
# `gemini` for every caller on PATH -- systemd units without User=, `env -i`
# invocations, container entrypoints and CI runners all reach it with no HOME.
# An unresolvable cache path must degrade to fetch-every-time, exactly as every
# other line on this path degrades, and never abort before flag parsing.
# stderr is asserted EMPTY, not merely free of "unbound variable": an
# unwritable cache path makes bash report the failed redirect on every call,
# which would put a scary line into every caller's log for a degradation the
# shim handles fine. Caching is best-effort; failing to cache is not an event.
SH12_RC=0
SH12_OUT="$( unset HOME; bash "$SHIM" --version 2>"$SANDBOX/sh12a.err" )" || SH12_RC=$?
SH12_RC2=0
SH12_OUT2="$( unset HOME; FAKE_AGY_STDOUT="ok" bash "$SHIM" -m flash -p x 2>"$SANDBOX/sh12b.err" )" || SH12_RC2=$?
SH12_ERR="$(cat "$SANDBOX/sh12a.err" "$SANDBOX/sh12b.err")"
if [[ "$SH12_RC" -eq 0 && "$SH12_OUT" == *"agy 0.0.0-fake"* \
      && "$SH12_RC2" -eq 0 && "$SH12_OUT2" == *"ok"* \
      && -z "$SH12_ERR" ]]; then
    ok "SH12 HOME unset still runs (--version and a delegation), silently"
else
    bad "SH12 HOME unset still runs (--version and a delegation), silently" \
        "rc=$SH12_RC out=$SH12_OUT rc2=$SH12_RC2 out2=$SH12_OUT2 stderr=$SH12_ERR"
fi
rm -f "$_SHIM_CACHE"

# SH13: AGY_MODELS_TIMEOUT=0 must NOT disable the bound. coreutils timeout
# documents "A duration of 0 disables the associated timeout", so passing it
# through reintroduces the exact unbounded hang this release exists to fix --
# in the PATH-shadowing script. Every non-positive-integer value falls back to
# the default instead. agy_bridge.sh rejects the same value outright; the shim
# may not hard-exit, so it corrects it. Wrapped in `timeout 30` to fail fast.
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
rm -f "$_SHIM_CACHE"

# SH14: a model list with no gemini ids is a degraded/unauthenticated agy
# (agy_bridge.sh treats it as fatal), NOT evidence about any particular name.
# The shim caches that reply, so an ungated warning would then declare every
# name unknown -- including real aliases like `flash` -- for a full 60 minutes.
rm -f "$_SHIM_CACHE"
SH14_OUT="$SANDBOX/sh14.out"
SH14_ERR="$SANDBOX/sh14.err"
SH14_DUMP="$SANDBOX/sh14_argv.log"
: > "$SH14_DUMP"
FAKE_AGY_MODELS_GARBAGE=1 FAKE_AGY_DUMP_ARGV="$SH14_DUMP" FAKE_AGY_STDOUT="ok" \
    bash "$SHIM" -m flash -p x > "$SH14_OUT" 2> "$SH14_ERR"
SH14_RC=$?
SH14_ID="$(awk '/^--model$/{getline; print; exit}' "$SH14_DUMP")"
if [[ "$SH14_RC" -eq 0 && "$SH14_ID" == "flash" ]] && ! grep -q 'WARNING' "$SH14_ERR"; then
    ok "SH14 a gemini-less model list is not treated as evidence a name is unknown"
else
    bad "SH14 a gemini-less model list is not treated as evidence a name is unknown" \
        "rc=$SH14_RC model=$SH14_ID stderr=$(cat "$SH14_ERR")"
fi
rm -f "$_SHIM_CACHE"

echo "== watchdog fixtures (RB00) =="

# RB00a: the sanitized PATH must genuinely resolve no bounding binary, AND still
# be complete enough to run a real delegation end to end. Both halves matter.
# Without the first, every later RB case silently exercises coreutils and the
# no-bounding-binary branch rots untested. Without the second, a tool missing
# from the explicit list would make later cases fail for a reason that has
# nothing to do with bounding -- which is why the list is asserted complete here
# rather than assumed complete downstream.
_run_sanitized RB00A_TOOLS RB00A_TRC bash -c 'command -v timeout; command -v gtimeout; exit 0'
FAKE_AGY_STDOUT="pure-path ok" _run_sanitized RB00A_OUT RB00A_RC bash "$SHIM" -p "do a thing"
if [[ -z "$RB00A_TOOLS" && "$RB00A_RC" -eq 0 && "$RB00A_OUT" == *"pure-path ok"* ]]; then
    ok "RB00a sanitized PATH resolves no timeout/gtimeout yet still runs a full shim delegation"
else
    bad "RB00a sanitized PATH resolves no timeout/gtimeout yet still runs a full shim delegation" \
        "resolved='$RB00A_TOOLS' rc=$RB00A_RC out=$RB00A_OUT"
fi

# RB00b: the forking fake must be shaped so a kill aimed at its own PID leaves a
# survivor. That is the only shape that tells a process-group kill apart from a
# direct-child kill; if the child died with its parent, every descendant
# assertion in this phase would pass vacuously. Asserted in two steps: SIGTERM
# at the parent's PID leaves the PARENT alive (it ignores the signal, as the
# real agy is observed to), and SIGKILL at the parent's PID leaves the CHILD
# alive.
RB00B_PPF="$SANDBOX/rb00b-parent.pid"
RB00B_CPF="$SANDBOX/rb00b-child.pid"
rm -f "$RB00B_PPF" "$RB00B_CPF"
FAKE_AGY_FORK_HANG=1 FAKE_AGY_PID_FILE="$RB00B_PPF" FAKE_AGY_CHILD_PID_FILE="$RB00B_CPF" \
    bash "$HERE/fake-agy.sh" --print x </dev/null >/dev/null 2>&1 &
# Drop it from the job table: the harness kills it deliberately below, and an
# async-job death notice on the suite's own stdout is noise, not a result.
disown $! 2>/dev/null || true
for _rb00b_i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    [[ -s "$RB00B_PPF" && -s "$RB00B_CPF" ]] && break
    sleep 0.25
done
RB00B_PPID="$(cat "$RB00B_PPF" 2>/dev/null)" || RB00B_PPID=""
RB00B_CPID="$(cat "$RB00B_CPF" 2>/dev/null)" || RB00B_CPID=""
RB00B_TERM_SURVIVED=0
RB00B_CHILD_SURVIVED=0
if [[ "$RB00B_PPID" =~ ^[0-9]+$ && "$RB00B_CPID" =~ ^[0-9]+$ ]]; then
    kill -TERM "$RB00B_PPID" 2>/dev/null
    sleep 1
    kill -0 "$RB00B_PPID" 2>/dev/null && RB00B_TERM_SURVIVED=1
    kill -KILL "$RB00B_PPID" 2>/dev/null
    sleep 1
    kill -0 "$RB00B_CPID" 2>/dev/null && RB00B_CHILD_SURVIVED=1
fi
if [[ "$RB00B_TERM_SURVIVED" -eq 1 && "$RB00B_CHILD_SURVIVED" -eq 1 ]]; then
    ok "RB00b forking fake ignores SIGTERM and its child outlives a direct-PID kill of the parent"
else
    bad "RB00b forking fake ignores SIGTERM and its child outlives a direct-PID kill of the parent" \
        "parent=$RB00B_PPID term_survived=$RB00B_TERM_SURVIVED child=$RB00B_CPID child_survived=$RB00B_CHILD_SURVIVED"
fi
kill -KILL "$RB00B_CPID" 2>/dev/null

echo "== bounded delegation, no bounding binary on PATH (RB04) =="

# The self-kill guard's warning, as it reaches an operator: run_bounded writes it
# to fd 9 (each script's own original stderr). Its presence is how a case tells
# "job control isolated the child" from "it could not", which decides which
# contract the run below is held to.
_RB_GUARD_MSG='has no process group of its own'

# _rb_assert_reaped LABEL RC ELAPSED PARENT_PID_FILE CHILD_PID_FILE [STDERR_TEXT]
#
# The ONE contract every runtime descendant case is held to -- RB04 below, RB05
# and RB13, and both halves of RB06. Written once and parameterised by entry
# point and PATH rather than copied per case, because the whole point of treating
# the BOUNDED INVOCATION as the primary noun is that the coreutils mechanism and
# the bash watchdog owe the caller the SAME contract. Two similar-looking sets of
# assertions would let them drift apart silently; if the two mechanisms ever
# genuinely needed different assertions, that promotion would be a fiction and
# this helper is where it would show.
#
# The weight is carried by the two PID checks, not by the exit code: an entry
# point that bounded nothing at all still shows rc=124 once the outer safety net
# fires -- just 30 seconds later with both processes still running. The elapsed
# cap is what separates "our bound fired" from "the net fired", and it is derived
# rather than tuned: every caller below passes a 3s bound with a 5s kill_after,
# so a working escalation is finished inside ~8s, well under the 20s cap RB04 and
# RB22 already use against a 30s net. The PIDs are required NON-EMPTY so a run
# where the fake never started cannot report both processes "gone".
#
# $6 is the entry point's own stderr, or the merged capture containing it. Where
# it carries the self-kill guard's warning, job control could NOT give the child
# a group of its own, and D-14a/D-06a's documented degradation is what gets
# asserted instead: the direct process still killed, the descendant kill not
# claimed. That outcome is a named, reported branch -- the label says so out loud
# -- never an untested branch and never a silent pass.
_rb_assert_reaped() {
    local label="$1" rc="$2" el="$3" ppf="$4" cpf="$5" errtext="${6:-}"
    local ppid cpid pgone=1 cgone=1 degraded=0 why="" note=""
    ppid="$(cat "$ppf" 2>/dev/null)" || ppid=""
    cpid="$(cat "$cpf" 2>/dev/null)" || cpid=""
    [[ "$ppid" =~ ^[0-9]+$ ]] && kill -0 "$ppid" 2>/dev/null && pgone=0
    [[ "$cpid" =~ ^[0-9]+$ ]] && kill -0 "$cpid" 2>/dev/null && cgone=0
    [[ "$errtext" == *"$_RB_GUARD_MSG"* ]] && degraded=1

    [[ "$rc" -eq 124 ]] || why="$why rc=$rc(want_124)"
    [[ "$el" -lt 20 ]] || why="$why elapsed=${el}s(want_lt_20)"
    [[ "$ppid" =~ ^[0-9]+$ && "$cpid" =~ ^[0-9]+$ ]] \
        || why="$why fake_never_started(parent='$ppid' child='$cpid')"
    [[ "$pgone" -eq 1 ]] || why="$why direct_process_survived($ppid)"
    if [[ "$degraded" -eq 1 ]]; then
        note=" [D-14a degradation: guard warned, so only the direct kill is claimed]"
    else
        [[ "$cgone" -eq 1 ]] || why="$why descendant_survived($cpid)"
    fi

    if [[ -z "$why" ]]; then
        ok "$label$note"
    else
        bad "$label$note" "detail=$why"
    fi
    # Unconditional, tolerating absence: a red run must not leave 300s sleepers
    # behind on the developer's box.
    [[ "$ppid" =~ ^[0-9]+$ ]] && kill -KILL "$ppid" 2>/dev/null
    [[ "$cpid" =~ ^[0-9]+$ ]] && kill -KILL "$cpid" 2>/dev/null
    return 0
}

# RB04: one real shim delegation on a PATH with no timeout/gtimeout, against an
# agy that ignores SIGTERM and has forked a SIGTERM-ignoring child. It must come
# back 124 within its own bound and leave NEITHER process alive.
#
# Held to the shared contract above, not to a private copy of it: the exit code
# alone proves nothing (the outer net also returns 124), the elapsed cap
# separates "our bound fired" from "the net fired", and the two PID checks
# separate a process-group kill from a direct-child kill.
RB04_PPF="$SANDBOX/rb04-parent.pid"
RB04_CPF="$SANDBOX/rb04-child.pid"
rm -f "$RB04_PPF" "$RB04_CPF"
_RB04_START=$(date +%s)
FAKE_AGY_FORK_HANG=1 FAKE_AGY_PID_FILE="$RB04_PPF" FAKE_AGY_CHILD_PID_FILE="$RB04_CPF" \
    GEMINI_SHIM_TIMEOUT=3 _run_sanitized OUT RC bash "$SHIM" -p "do a thing"
_RB04_ELAPSED=$(( $(date +%s) - _RB04_START ))
_rb_assert_reaped \
    "RB04 no bounding binary: shim delegation returns 124 and reaps agy plus its fork" \
    "$RC" "$_RB04_ELAPSED" "$RB04_PPF" "$RB04_CPF" "$OUT"

echo "== watchdog timer leaves nothing behind (RB20) =="

# Case ids: RB01-RB14 are claimed by plans 01-03 through 01-06 and RB00a/RB00b by
# 01-01, so these two defect regressions take RB20/RB21 -- above both ranges,
# leaving RB15-RB19 free as headroom inside the planned series.

# Counts processes whose ENTIRE command line is `sleep <bound>`. Exact-match
# (grep -x) rather than substring is load-bearing: `pgrep -f "sleep 4242"` also
# matches the process carrying the pattern, so a substring counter counts itself
# and a substring pkill kills itself. The bounds below are sentinels, not tuning
# -- values nothing else on the box sleeps for -- so a survivor is unambiguously
# the call under test's, and the default matches all three configurable bounds at
# once so a leak from ANY of the shim's bounded call sites is caught.
_RB_SENTINELS='4242|4243|4244'
_rb_sleepers() {
    ps -A -o args= 2>/dev/null | grep -cxE "sleep (${1:-$_RB_SENTINELS})" || true
}
_rb_reap_sentinels() {
    local b
    for b in 4242 4243 4244; do pkill -x -f "sleep $b" 2>/dev/null; done
    return 0
}

# RB20a: the EARLY-RETURN path -- the bounded child finishes on its own and the
# watchdog timer is cancelled. Cancelling the timer must reap the `sleep` it
# forked, not just the subshell that forked it: the subshell's in-flight sleep is
# a separate process, so a kill aimed at the subshell pid alone orphans it to
# init for the FULL length of the bound. On the shim's real defaults that is one
# resident `sleep 600` per delegation on every coreutils-less host.
#
# The success assertions are not decoration: without them a run where the
# watchdog path never executed a single bounded call would report zero survivors
# and pass vacuously.
_rb_reap_sentinels
_RB20A_BEFORE="$(_rb_sleepers)"
FAKE_AGY_STDOUT="rb20a ok" GEMINI_SHIM_TIMEOUT=4242 AGY_MODELS_TIMEOUT=4243 \
    GEMINI_SHIM_STDIN_TIMEOUT=4244 \
    _run_sanitized RB20A_OUT RB20A_RC bash "$SHIM" -p "do a thing"
sleep 1
_RB20A_AFTER="$(_rb_sleepers)"
if [[ "$RB20A_RC" -eq 0 && "$RB20A_OUT" == *"rb20a ok"* \
      && "$_RB20A_BEFORE" -eq 0 && "$_RB20A_AFTER" -eq 0 ]]; then
    ok "RB20a a completed bounded call leaves no watchdog sleep behind"
else
    bad "RB20a a completed bounded call leaves no watchdog sleep behind" \
        "rc=$RB20A_RC before=$_RB20A_BEFORE after=$_RB20A_AFTER out=${RB20A_OUT:0:200}"
fi
_rb_reap_sentinels

# RB20b: the SIGNAL-RELAY path -- the shim is signalled while a bounded call is
# still in flight, so the TERM trap tears down instead of the normal return. The
# trap must cancel the timer as well; relaying to the child and exiting while
# leaving the timer running leaks the same sleep by a second route.
#
# Driven through the stdin-read call site, not the delegation one, because the
# bounded command there is `cat` -- it must be a child that DIES on the relayed
# SIGTERM. The forking fake used by RB04 deliberately ignores SIGTERM (as the
# real agy does), which would leave the trap's own `wait` blocked and measure the
# harness rather than the fix. A fifo held open by the harness is what keeps
# `cat` blocked: an explicit `<fifo` is also required because bash redirects an
# asynchronous command's stdin from /dev/null otherwise, and an EOF on stdin
# would end the bounded call before the signal could arrive. The fifo is opened
# READ-WRITE (`<>`), not write-only: opening a fifo for writing blocks until a
# reader appears, which would deadlock the suite here rather than the shim.
mkdir -p "$(dirname "$_SHIM_CACHE")"
printf '%s\t%s\n' \
    "gemini-9.9-flash-high" "Gemini 9.9 Flash (High)" \
    "gemini-9.9-pro-high"   "Gemini 9.9 Pro (High)" > "$_SHIM_CACHE"
_RB20B_BIN="$(_purebin)"
RB20B_FIFO="$SANDBOX/rb20b.fifo"
rm -f "$RB20B_FIFO"
mkfifo "$RB20B_FIFO"
exec 7<>"$RB20B_FIFO"
PATH="$_RB20B_BIN" GEMINI_SHIM_TIMEOUT=4242 AGY_MODELS_TIMEOUT=4243 \
    GEMINI_SHIM_STDIN_TIMEOUT=4244 \
    bash "$SHIM" <"$RB20B_FIFO" >/dev/null 2>&1 &
RB20B_SHIM=$!
# Drop it from the job table: the harness signals it deliberately below, and an
# async-job death notice on the suite's own stdout is noise, not a result.
disown $RB20B_SHIM 2>/dev/null || true
RB20B_SEEN=0
for _rb20b_i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24; do
    if [[ "$(_rb_sleepers 4244)" -gt 0 ]]; then RB20B_SEEN=1; break; fi
    sleep 0.25
done
kill -TERM "$RB20B_SHIM" 2>/dev/null
RB20B_EXITED=0
for _rb20b_j in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if ! kill -0 "$RB20B_SHIM" 2>/dev/null; then RB20B_EXITED=1; break; fi
    sleep 0.25
done
_RB20B_AFTER="$(_rb_sleepers)"
exec 7>&-
if [[ "$RB20B_SEEN" -eq 1 && "$RB20B_EXITED" -eq 1 && "$_RB20B_AFTER" -eq 0 ]]; then
    ok "RB20b the TERM relay trap cancels the timer, leaving no watchdog sleep behind"
else
    bad "RB20b the TERM relay trap cancels the timer, leaving no watchdog sleep behind" \
        "timer_seen=$RB20B_SEEN shim_exited=$RB20B_EXITED survivors=$_RB20B_AFTER"
fi
kill -KILL "$RB20B_SHIM" 2>/dev/null
_rb_reap_sentinels
rm -f "$RB20B_FIFO" "$_SHIM_CACHE"

echo "== self-kill guard warns only about a LIVE child (RB21) =="

# Both RB21 cases drive the marker-delimited block directly rather than the whole
# shim. Two reasons, and neither is convenience: the false warning is
# deterministic only for a child that exits before its PGID can be read, which
# end to end is a race; and the genuine branch is reachable only by making the
# child's group match the shell's, which the shipped block offers no switch for
# and must not grow one (it installs as ~/.local/bin/gemini and shadows the real
# gemini for every PATH caller). Extracting with the same sed marker range plan
# 01-03 copies with also keeps the region's self-containment honest -- its only
# host dependencies are $TIMEOUT_BIN and fd 9.
_RB_BLOCK="$SANDBOX/run_bounded.block.sh"
sed -n '/# --- BEGIN run_bounded ---/,/# --- END run_bounded ---/p' "$SHIM" > "$_RB_BLOCK"

# RB21a: a fast SUCCESSFUL bounded call must say nothing on fd 9. Ten instant
# children, because one could pass by luck; the warning was measured firing 10/10
# before the fix.
_RB21A_FD9="$SANDBOX/rb21a-fd9.log"
: > "$_RB21A_FD9"
bash -c '
    set -euo pipefail
    exec 9>"$2"
    TIMEOUT_BIN=""
    . "$1"
    for _i in 1 2 3 4 5 6 7 8 9 10; do run_bounded 5 2 -- true || true; done
' _ "$_RB_BLOCK" "$_RB21A_FD9"; RB21A_RC=$?
RB21A_FD9_BYTES="$(wc -c < "$_RB21A_FD9" | tr -d ' ')"
if [[ "$RB21A_RC" -eq 0 && "$RB21A_FD9_BYTES" -eq 0 ]]; then
    ok "RB21a ten fast successful bounded calls write nothing to fd 9"
else
    bad "RB21a ten fast successful bounded calls write nothing to fd 9" \
        "rc=$RB21A_RC fd9=$(head -c 300 "$_RB21A_FD9")"
fi

# RB21b: the genuine case must stay loud. The stub reports the SAME group for the
# shell and for the child, which is exactly what a host whose job control did not
# give the child a group of its own would report -- and the child here is alive
# for a full second, so descendants really could survive a pid-only kill. The
# override lives in this driver, never in the shipped block.
_RB21B_FD9="$SANDBOX/rb21b-fd9.log"
: > "$_RB21B_FD9"
bash -c '
    set -euo pipefail
    exec 9>"$2"
    TIMEOUT_BIN=""
    . "$1"
    _rb_pgid_of() { printf "%s" 4242; }
    run_bounded 5 2 -- sleep 1 || true
' _ "$_RB_BLOCK" "$_RB21B_FD9"; RB21B_RC=$?
if [[ "$RB21B_RC" -eq 0 ]] && grep -qF "$_RB_GUARD_MSG" "$_RB21B_FD9"; then
    ok "RB21b a live child with no group of its own still warns on fd 9"
else
    bad "RB21b a live child with no group of its own still warns on fd 9" \
        "rc=$RB21B_RC fd9=$(head -c 300 "$_RB21B_FD9")"
fi

echo "== a relayed signal escalates like the bound does (RB22) =="

# RB22: continues the gap-fix range RB20/RB21 opened -- above RB01-RB14 (plans
# 01-03 through 01-06) and clear of RB15-RB19, which stays headroom inside the
# planned series.
#
# One real shim delegation on a PATH with no timeout/gtimeout, against an agy that
# IGNORES SIGTERM and has forked a SIGTERM-ignoring child, interrupted by a
# SIGTERM at the shim itself. The relay must reach the same end state the coreutils
# arm reaches for a forwarded signal: forward, escalate to SIGKILL after the same
# kill_after, then return. An unescalated `wait` hangs for as long as the child
# chooses to live -- 300s here, unbounded in the field.
#
# The bound is set far out of reach (4242s) on purpose: nothing but the relay can
# end this call, so a pass cannot be the watchdog bound firing by luck. The
# assertions that carry the weight are the two PID checks and the elapsed cap, not
# the exit code -- a shim that tore down by some other route would still exit 143.
# The cap is derived, not tuned: kill_after at the delegation site is 5s, so a
# working escalation is done inside ~6s; 15s of polling is 3x that, and the 20s
# elapsed assertion is the one RB04 already uses. The PIDs are required NON-EMPTY
# so a run where the fake never started cannot report both processes "gone".
RB22_PPF="$SANDBOX/rb22-parent.pid"
RB22_CPF="$SANDBOX/rb22-child.pid"
rm -f "$RB22_PPF" "$RB22_CPF"
_rb_reap_sentinels
_RB22_BIN="$(_purebin)"
_RB22_START=$(date +%s)
PATH="$_RB22_BIN" FAKE_AGY_FORK_HANG=1 FAKE_AGY_PID_FILE="$RB22_PPF" \
    FAKE_AGY_CHILD_PID_FILE="$RB22_CPF" GEMINI_SHIM_TIMEOUT=4242 \
    AGY_MODELS_TIMEOUT=4243 GEMINI_SHIM_STDIN_TIMEOUT=4244 \
    bash "$SHIM" -p "do a thing" >/dev/null 2>&1 &
RB22_SHIM=$!
for _rb22_i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24; do
    [[ -s "$RB22_PPF" && -s "$RB22_CPF" ]] && break
    sleep 0.25
done
kill -TERM "$RB22_SHIM" 2>/dev/null
RB22_EXITED=0
for ((_rb22_j = 0; _rb22_j < 60; _rb22_j++)); do
    if ! kill -0 "$RB22_SHIM" 2>/dev/null; then RB22_EXITED=1; break; fi
    sleep 0.25
done
_RB22_ELAPSED=$(( $(date +%s) - _RB22_START ))
RB22_RC=""
if [[ "$RB22_EXITED" -eq 1 ]]; then wait "$RB22_SHIM" 2>/dev/null; RB22_RC=$?; fi
RB22_PPID="$(cat "$RB22_PPF" 2>/dev/null)" || RB22_PPID=""
RB22_CPID="$(cat "$RB22_CPF" 2>/dev/null)" || RB22_CPID=""
RB22_PARENT_GONE=1
RB22_CHILD_GONE=1
[[ "$RB22_PPID" =~ ^[0-9]+$ ]] && kill -0 "$RB22_PPID" 2>/dev/null && RB22_PARENT_GONE=0
[[ "$RB22_CPID" =~ ^[0-9]+$ ]] && kill -0 "$RB22_CPID" 2>/dev/null && RB22_CHILD_GONE=0
_RB22_SLEEPERS="$(_rb_sleepers)"
if [[ "$RB22_EXITED" -eq 1 && "$RB22_RC" -eq 143 && "$_RB22_ELAPSED" -lt 20 \
      && "$RB22_PPID" =~ ^[0-9]+$ && "$RB22_CPID" =~ ^[0-9]+$ \
      && "$RB22_PARENT_GONE" -eq 1 && "$RB22_CHILD_GONE" -eq 1 \
      && "$_RB22_SLEEPERS" -eq 0 ]]; then
    ok "RB22 a relayed SIGTERM escalates to SIGKILL and returns 143 instead of waiting out the child"
else
    bad "RB22 a relayed SIGTERM escalates to SIGKILL and returns 143 instead of waiting out the child" \
        "exited=$RB22_EXITED rc=$RB22_RC elapsed=${_RB22_ELAPSED}s parent=$RB22_PPID parent_gone=$RB22_PARENT_GONE child=$RB22_CPID child_gone=$RB22_CHILD_GONE sleepers=$_RB22_SLEEPERS"
fi
# Only on the failure path, and disowned first: killing a job still in the table
# makes bash print a "Killed" notice on the suite's own stdout, which is noise
# rather than a result. On the passing path `wait` above has already reaped it.
if [[ "$RB22_EXITED" -eq 0 ]]; then
    disown "$RB22_SHIM" 2>/dev/null || true
    kill -KILL "$RB22_SHIM" 2>/dev/null
fi
kill -KILL "$RB22_PPID" 2>/dev/null
kill -KILL "$RB22_CPID" 2>/dev/null
_rb_reap_sentinels

echo "== the bounding invariant, asserted over the files (RB01) =="

# RB01 is the only case in this suite that asserts something about code nobody
# has written yet. Every other case drives a path and checks what came back; a
# call site added six months from now is on no path, so no behavioural test can
# see it -- and an unbounded call site is exactly what survived the last release
# and hangs the box. So the property is asserted over the FILE: every expansion
# of the agy binary in either script is an argument to run_bounded.
#
# No count is asserted. The number of call sites has been stated wrong three
# times (two, then four, now five, the last because this project's own work
# added one), so a criterion naming a number is correct only until the next
# commit. The only number below is a floor of one occurrence, which exists so
# that renaming the variable turns this case red instead of silently green.
#
# Zero exceptions, by design: no allowlist, no skip list, no escape-hatch
# comment. run_bounded takes its command as arguments and never names the agy
# binary itself, so nothing legitimate needs an exception today; a site that
# genuinely cannot be bounded has to change this rule in the open. An inline
# escape hatch is cheaper to add than a decision is to revisit, which is how the
# unbounded call survived the release built to eliminate unbounded calls.
#
# Known ceiling: a line that merely MENTIONS the variable outside a run_bounded
# call -- printing it in a diagnostic, say -- is reported as a violation. That
# is deliberate rather than an oversight; separating "invokes" from "mentions"
# needs a shell parser, and the cheap approximation errs toward failing loudly.

# Comment-only lines dropped first (a comment naming the variable is neither an
# occurrence nor a violation), then backslash-continued lines joined into one
# logical line each. The join is load-bearing, not tidiness: the bridge's
# delegation call puts `run_bounded` on one physical line and the invocation on
# the next, so a per-physical-line scan reports a false violation -- and the
# cheapest way to silence a false violation is to invent the allowlist this case
# forbids.
_rb_logical_lines() {
    sed -e 's/[[:space:]]*$//' "$1" \
        | grep -v '^[[:space:]]*#' \
        | sed -e :a -e '/\\$/{N; s/\\\n[[:space:]]*/ /; ta' -e '}'
}

# _rb_agy_scan FILE -> "<violations> <occurrences>". An occurrence is any
# expansion of AGY_BIN in any form -- "$AGY_BIN", "${AGY_BIN}", or bare
# $AGY_BIN. Matching only the doubly-quoted form would let a brace or an
# unquoted rewrite walk straight past a scan that still reported zero
# violations, which is the one way this case could fail silently. The
# assignment line (`AGY_BIN=...`) carries no `$` and is not an occurrence.
_rb_agy_scan() {
    local lines occ viol
    lines="$(_rb_logical_lines "$1")"
    occ="$(printf '%s\n' "$lines" | grep -cE '\$\{?AGY_BIN\}?')" || occ=0
    viol="$(printf '%s\n' "$lines" | grep -E '\$\{?AGY_BIN\}?' \
            | grep -cvE 'run_bounded[[:space:]].*[[:space:]]--[[:space:]].*\$\{?AGY_BIN\}?')" || viol=0
    printf '%s %s' "$viol" "$occ"
}

# RB01: the real scripts. `bash -n` first -- a file that does not parse cannot
# be scanned meaningfully, and a scan of an unparseable file would report zero
# violations for the wrong reason.
RB01_OK=1
RB01_DETAIL=""
RB01_TOTAL=0
for _rb01_f in "$BRIDGE" "$SHIM"; do
    if ! bash -n "$_rb01_f" 2>"$SANDBOX/rb01-syntax.log"; then
        RB01_OK=0
        RB01_DETAIL="$RB01_DETAIL ${_rb01_f##*/}:unparseable"
        continue
    fi
    read -r _rb01_v _rb01_o <<<"$(_rb_agy_scan "$_rb01_f")"
    RB01_TOTAL=$(( RB01_TOTAL + _rb01_o ))
    if [[ "$_rb01_v" -ne 0 ]]; then
        RB01_OK=0
        RB01_DETAIL="$RB01_DETAIL ${_rb01_f##*/}:${_rb01_v}_unbounded_of_${_rb01_o}"
        RB01_DETAIL="$RB01_DETAIL[$(_rb_logical_lines "$_rb01_f" | grep -E '\$\{?AGY_BIN\}?' \
            | grep -vE 'run_bounded[[:space:]].*[[:space:]]--[[:space:]].*\$\{?AGY_BIN\}?' | head -3 | tr '\n' ';')]"
    fi
done
if [[ "$RB01_TOTAL" -lt 1 ]]; then
    RB01_OK=0
    RB01_DETAIL="$RB01_DETAIL no-occurrence-at-all(scan matched nothing; a rename would empty it)"
fi
if [[ "$RB01_OK" -eq 1 ]]; then
    ok "RB01 every agy invocation in both scripts is a run_bounded argument, no exceptions"
else
    bad "RB01 every agy invocation in both scripts is a run_bounded argument, no exceptions" \
        "occurrences=$RB01_TOTAL detail=$RB01_DETAIL"
fi

# RB01m: the scan is proven capable of failing before it is trusted. A copy of
# the shim gains one directly-invoked agy line -- on a path no test drives,
# which is the whole point -- and the SAME helper must report it. A scan never
# shown to fail is a scan that passes forever.
RB01M_DIR="$SANDBOX/rb01m"
mkdir -p "$RB01M_DIR"
cp "$SHIM" "$RB01M_DIR/mutated.sh"
printf '%s\n' 'if [[ "${RB01M_NEVER:-0}" == "1" ]]; then "$AGY_BIN" --version; fi' >> "$RB01M_DIR/mutated.sh"
read -r RB01M_V RB01M_O <<<"$(_rb_agy_scan "$RB01M_DIR/mutated.sh")"
# And a copy whose only addition is a COMMENT naming the variable must stay
# clean, so the scan's own noise floor is pinned alongside its sensitivity.
cp "$SHIM" "$RB01M_DIR/commented.sh"
printf '%s\n' '# a comment mentioning "$AGY_BIN" is not a call site' >> "$RB01M_DIR/commented.sh"
read -r RB01M_CV RB01M_CO <<<"$(_rb_agy_scan "$RB01M_DIR/commented.sh")"
if [[ "$RB01M_V" -ge 1 && "$RB01M_CV" -eq 0 && "$RB01M_CO" -ge 1 ]]; then
    ok "RB01m the scan reports an injected unbounded call site and ignores a comment"
else
    bad "RB01m the scan reports an injected unbounded call site and ignores a comment" \
        "mutated=${RB01M_V}/${RB01M_O} commented=${RB01M_CV}/${RB01M_CO}"
fi
rm -rf "$RB01M_DIR"

echo "== the helper is one artifact in two files (RB02) =="

# RB02: run_bounded is duplicated verbatim into both scripts on purpose -- each
# is installed as a standalone launcher and neither may source the other -- so
# the two copies are one artifact living in two files. Three defects were found
# inside that helper AFTER it was first written; the hazard this case guards is
# the fourth being fixed in one copy and not the other, which nothing else in
# the suite would notice. Same one-sided-fix hazard delegate-agy-8ph names for
# the two model-cache writers.
_rb_extract() {
    sed -n '/^# --- BEGIN run_bounded ---$/,/^# --- END run_bounded ---$/p' "$1"
}

RB02_B="$(_rb_extract "$BRIDGE")"
RB02_S="$(_rb_extract "$SHIM")"
# Both ranges must be non-empty AND must actually contain the definition, so two
# absent or two truncated blocks cannot pass trivially by both being nothing.
if [[ -n "$RB02_B" && -n "$RB02_S" \
      && "$RB02_B" == *"run_bounded() {"* && "$RB02_S" == *"run_bounded() {"* \
      && "$RB02_B" == "$RB02_S" ]]; then
    ok "RB02 the two run_bounded blocks are byte-identical and non-empty"
else
    bad "RB02 the two run_bounded blocks are byte-identical and non-empty" \
        "bridge_lines=$(printf '%s' "$RB02_B" | grep -c '' ) shim_lines=$(printf '%s' "$RB02_S" | grep -c '') diff=$(diff <(printf '%s\n' "$RB02_B") <(printf '%s\n' "$RB02_S") | head -6 | tr '\n' ';')"
fi

# RB02m: prove the comparison can fail before trusting it. One character changed
# inside a copy of the bridge's block must be reported, and an empty block must
# not compare equal to a real one.
RB02M_DIR="$SANDBOX/rb02m"
mkdir -p "$RB02M_DIR"
sed 's/^# Bounded invocation, redirect-transparent:/# bounded invocation, redirect-transparent:/' \
    "$BRIDGE" > "$RB02M_DIR/mutated.sh"
RB02M_M="$(_rb_extract "$RB02M_DIR/mutated.sh")"
printf 'echo no markers here\n' > "$RB02M_DIR/empty.sh"
RB02M_E="$(_rb_extract "$RB02M_DIR/empty.sh")"
if [[ -n "$RB02M_M" && "$RB02M_M" != "$RB02_B" && -z "$RB02M_E" ]]; then
    ok "RB02m a one-character edit inside a copied block is reported, and a markerless file extracts nothing"
else
    bad "RB02m a one-character edit inside a copied block is reported, and a markerless file extracts nothing" \
        "mutated_empty=$([[ -z "$RB02M_M" ]] && echo yes) mutated_equal=$([[ "$RB02M_M" == "$RB02_B" ]] && echo yes) markerless_len=${#RB02M_E}"
fi
rm -rf "$RB02M_DIR"

echo "== the strings an operator actually sees (RB03) =="

# RB03: README's troubleshooting table is matched by hand against real output,
# so a paraphrase there is a defect even though nothing crashes. The expected
# bytes are written HERE, not extracted from one file and grepped for in
# another -- extracting from the source and searching the source with it is a
# tautology that passes whatever the strings become. Fixed-string matching
# throughout, so a drifted hyphen, quote or semicolon is caught; note the `--`,
# which is not an em dash.
_RB_WARN_LITERAL='WARNING: timeout/gtimeout not found -- bounding agy with the bash watchdog fallback; install coreutils for process-group kill'
_RB_NOTE_LITERAL='NOTICE: bash watchdog fallback killed the bounded call after its bound (exit 124)'
# The startup fatal the bridge used to print before this phase decided to
# degrade instead of refuse. It must not come back anywhere that ships.
_RB_DEAD_FATAL='ERROR: timeout/gtimeout not found in PATH (install coreutils)'
_RB_README="$ROOT/README.md"

RB03_OK=1
RB03_DETAIL=""
# Defined exactly once per script, with the same bytes in both. Comment lines
# are filtered out before counting so a comment naming the constant cannot
# inflate the count.
for _rb03_f in "$BRIDGE" "$SHIM"; do
    _rb03_n="$(grep -v '^[[:space:]]*#' "$_rb03_f" | grep -cF "RB_NO_TIMEOUT_WARN='$_RB_WARN_LITERAL'")" || _rb03_n=0
    [[ "$_rb03_n" -eq 1 ]] || { RB03_OK=0; RB03_DETAIL="$RB03_DETAIL ${_rb03_f##*/}:defines_${_rb03_n}"; }
done
# README quotes both literals verbatim.
grep -qF "$_RB_WARN_LITERAL" "$_RB_README" || { RB03_OK=0; RB03_DETAIL="$RB03_DETAIL readme:warning_missing"; }
grep -qF "$_RB_NOTE_LITERAL" "$_RB_README" || { RB03_OK=0; RB03_DETAIL="$RB03_DETAIL readme:notice_missing"; }
# Negative half (delegate-agy-6f6). Every other assertion in this phase is
# positive, so a stale sentence reintroduced BESIDE a correct one would keep the
# suite green. Two absences are pinned:
#
#  - the deleted startup fatal, in either shipped script and in README. It is a
#    fixed string that named a behaviour this phase reversed, so any reappearance
#    is stale by construction.
#  - the word "unbounded" in README. Ceiling, stated rather than hidden: the
#    property worth pinning is "no present-tense claim that either entry point
#    runs agy unbounded", and that is not mechanically separable from a
#    legitimate historical or contrast mention. README carries zero occurrences
#    today, so the blanket form is what can be pinned exactly; a future
#    legitimate mention has to change this rule in the open. The two scripts are
#    deliberately NOT subject to it -- they use the word correctly in three
#    hazard comments, which is precisely the case that cannot be separated.
#
# Scope is what ships: README and the two scripts. .planning/PROJECT.md and
# .planning/REQUIREMENTS.md are checked by neither, because they live in the
# main tree while this suite runs from the worktree and must also pass from a
# release tarball that contains no .planning/ at all.
for _rb03_f in "$BRIDGE" "$SHIM" "$_RB_README"; do
    grep -qF "$_RB_DEAD_FATAL" "$_rb03_f" && { RB03_OK=0; RB03_DETAIL="$RB03_DETAIL ${_rb03_f##*/}:deleted_fatal_returned"; }
done
grep -qiF 'unbounded' "$_RB_README" && { RB03_OK=0; RB03_DETAIL="$RB03_DETAIL readme:unbounded_claim($(grep -niF unbounded "$_RB_README" | head -2 | tr '\n' ';'))"; }
if [[ "$RB03_OK" -eq 1 ]]; then
    ok "RB03 both scripts define the warning once, README quotes both literals, and the reversed claims are gone"
else
    bad "RB03 both scripts define the warning once, README quotes both literals, and the reversed claims are gone" \
        "detail=$RB03_DETAIL"
fi

echo "== one warning per run, before any bounded output (RB08) =="

# RB08: the missing-binary warning is announced at the PROBE, which runs once
# per invocation, and never inside run_bounded, which runs two or more times in
# a delegating run. Both halves of that are observable and neither is implied by
# the other: the count says the emission has not migrated into the helper, and
# the ordering says it still happens before any call site is reached. A warning
# that appeared after a bounded call's output would mean exactly that migration
# even if some other path kept the count at one.
#
# Each run is driven with the model cache cleared, so the fetch actually happens
# instead of being served from cache, and with the prompt arriving on STDIN
# rather than as an argument, so all three bounded sites run: the model fetch,
# the stdin `cat`, and the delegation.
#
# Feeding the prompt through stdin is load-bearing, not incidental. The fetch
# and the delegation both redirect their stderr into files or /dev/null, so a
# warning migrated into the helper would be swallowed at those two sites and the
# count would stay at one -- verified: a mutated shim emitting the warning per
# bounded call still passed an argument-driven version of this case. The stdin
# `cat` site is the one whose stderr reaches the captured stream, which is what
# gives the count something to see. Ceiling, stated rather than hidden: a
# migration that somehow touched only the two redirect-into-a-file sites would
# still be invisible here, and would have to be caught by reading those files.
RB08_MARK="RB08-delegation-output"
RB08_OK=1
RB08_DETAIL=""

for _rb08_entry in bridge shim; do
    if [[ "$_rb08_entry" == "bridge" ]]; then
        _rb08_cmd=("$BRIDGE" --type code)
    else
        _rb08_cmd=("$SHIM" -m flash)
    fi

    # No bounding binary on PATH: exactly one warning, ahead of the delegation.
    rm -f "$_SHIM_CACHE"
    FAKE_AGY_STDOUT="$RB08_MARK" _run_sanitized RB08_OUT RB08_RC bash "${_rb08_cmd[@]}" \
        < <(printf 'do a thing\n')
    _rb08_n="$(printf '%s\n' "$RB08_OUT" | grep -cF "$_RB_WARN_LITERAL")" || _rb08_n=0
    _rb08_head="${RB08_OUT%%"$RB08_MARK"*}"
    if [[ "$RB08_RC" -ne 0 || "$RB08_OUT" != *"$RB08_MARK"* ]]; then
        # Without this the two assertions below could both hold on a run that
        # never delegated at all.
        RB08_OK=0
        RB08_DETAIL="$RB08_DETAIL $_rb08_entry:no_delegation(rc=$RB08_RC out=${RB08_OUT:0:120})"
    fi
    [[ "$_rb08_n" -eq 1 ]] || { RB08_OK=0; RB08_DETAIL="$RB08_DETAIL $_rb08_entry:emitted_${_rb08_n}"; }
    [[ "$_rb08_head" == *"$_RB_WARN_LITERAL"* ]] || { RB08_OK=0; RB08_DETAIL="$RB08_DETAIL $_rb08_entry:warning_after_bounded_output"; }

    # Ordinary suite PATH, where a bounding binary resolves: never emitted.
    rm -f "$_SHIM_CACHE"
    FAKE_AGY_STDOUT="$RB08_MARK" _run RB08_OUT2 RB08_RC2 bash "${_rb08_cmd[@]}" \
        < <(printf 'do a thing\n')
    _rb08_n2="$(printf '%s\n' "$RB08_OUT2" | grep -cF "$_RB_WARN_LITERAL")" || _rb08_n2=0
    [[ "$RB08_RC2" -eq 0 && "$RB08_OUT2" == *"$RB08_MARK"* ]] \
        || { RB08_OK=0; RB08_DETAIL="$RB08_DETAIL $_rb08_entry:coreutils_run_failed(rc=$RB08_RC2)"; }
    [[ "$_rb08_n2" -eq 0 ]] || { RB08_OK=0; RB08_DETAIL="$RB08_DETAIL $_rb08_entry:emitted_${_rb08_n2}_with_coreutils"; }
done
rm -f "$_SHIM_CACHE"
if [[ "$RB08_OK" -eq 1 ]]; then
    ok "RB08 each entry point warns exactly once per coreutils-less run, ahead of any bounded output, and never with coreutils"
else
    bad "RB08 each entry point warns exactly once per coreutils-less run, ahead of any bounded output, and never with coreutils" \
        "detail=$RB08_DETAIL"
fi

echo "== one contract, two entry points, two mechanisms (RB05, RB07, RB13) =="

# RB05: the BRIDGE half of phase criterion 2. RB04 proved the shim on a host with
# no bounding binary; the criterion asks for a test per ENTRY POINT, so this is
# the same adversarial fake and the same shared assertions pointed at the other
# script.
#
# RUN_BOUNDED_KILLED is deliberately NOT read here. The bridge's delegation runs
# inside a `( cd "$WORK_DIR" && run_bounded ... )` subshell, so the flag never
# reaches this scope; a case that asserted it at this site would be reading a
# stale value and passing for the wrong reason. What crosses that boundary is the
# exit code and the two recorded PIDs, and those are what is asserted.
# Captured into a FILE rather than through `_run_sanitized`'s command
# substitution, and this is not style. Each entry point opens fd 9 on its own
# original stderr, and every child inherits it -- including the fake and the fake's
# fork. Under a command substitution that descriptor IS the capture pipe, so a run
# where the descendant assertion would FAIL leaves an orphan holding the pipe and
# the read blocks for the fake's full 300s sleep instead of failing. Measured: a
# mutated shim turned a ~10s red case into a ~5min one. A file cannot be held
# open against us, so a broken implementation fails in ~35s, bounded by the net.
RB05_PPF="$SANDBOX/rb05-parent.pid"
RB05_CPF="$SANDBOX/rb05-child.pid"
RB05_CAP="$SANDBOX/rb05-capture.log"
rm -f "$RB05_PPF" "$RB05_CPF"
_RB05_BIN="$(_purebin)"
_RB05_START=$(date +%s)
PATH="$_RB05_BIN" FAKE_AGY_FORK_HANG=1 FAKE_AGY_PID_FILE="$RB05_PPF" \
    FAKE_AGY_CHILD_PID_FILE="$RB05_CPF" \
    "$_TIMEOUT_NET" --foreground -k 5 30 \
    bash "$BRIDGE" --type code --timeout 3 -- "do a thing" > "$RB05_CAP" 2>&1
RB05_RC=$?
_RB05_ELAPSED=$(( $(date +%s) - _RB05_START ))
_rb_assert_reaped \
    "RB05 no bounding binary: bridge delegation returns 124 and reaps agy plus its fork" \
    "$RB05_RC" "$_RB05_ELAPSED" "$RB05_PPF" "$RB05_CPF" "$(cat "$RB05_CAP")"

# RB07: with no bounding binary on PATH the bridge must reach its OWN argument
# handling instead of exiting 2 at startup -- the behaviour this phase reversed
# (D-03). Before the phase it printed a fatal and exited 2 before parsing a
# single flag.
#
# Two assertions, and the second is what makes the first mean anything: a non-2
# exit would also be produced by a bridge that never ran the probe at all, so the
# warning literal on stderr is what pins that the probe DID run and chose to
# degrade. `--types` is the cheapest deterministic path that produces the
# bridge's own output without going anywhere near agy.
_run_sanitized RB07_OUT RB07_RC bash "$BRIDGE" --types
if [[ "$RB07_RC" -eq 0 && "$RB07_OUT" == *"$_RB_WARN_LITERAL"* \
      && "$RB07_OUT" == *"search"* && "$RB07_OUT" == *"300s"* ]]; then
    ok "RB07 no bounding binary: the bridge degrades past its startup probe instead of exiting 2"
else
    bad "RB07 no bounding binary: the bridge degrades past its startup probe instead of exiting 2" \
        "rc=$RB07_RC out=${RB07_OUT:0:300}"
fi

# RB13: criterion 4's runtime half -- with a bounding binary PRESENT, no agy
# invocation on either entry point outlives its bound against a SIGTERM-ignoring
# fake that has forked. Same fake, same shared assertions, ordinary suite PATH.
# Proven rather than assumed: the coreutils mechanism has never been driven
# against the forking fake before this case.
#
# The outer net is added explicitly because `_run` carries none, and it uses the
# same `--foreground` form `_run_sanitized` does. That form is load-bearing: the
# default mode places its child in a new process group and signals the GROUP,
# which would reap the fake and its fork as a side effect and turn a genuinely
# failing descendant assertion into a vacuous pass.
#
# Measured on this host: the SCRIPT's own `timeout -k` returns 137 here, not 124,
# because the SIGKILL it sends to its own process group reaches itself. run_bounded
# flags 124 and 137 alike as its own kill and both entry points map both to 124,
# which is the unified code the caller is owed. So this asserts 124 at the ENTRY
# POINT and makes no claim about which of the two the mechanism returned -- the
# contract is the caller's, not the mechanism's.
for _rb13_entry in bridge shim; do
    RB13_PPF="$SANDBOX/rb13-$_rb13_entry-parent.pid"
    RB13_CPF="$SANDBOX/rb13-$_rb13_entry-child.pid"
    rm -f "$RB13_PPF" "$RB13_CPF"
    if [[ "$_rb13_entry" == "bridge" ]]; then
        _rb13_cmd=(bash "$BRIDGE" --type code --timeout 3 -- "do a thing")
    else
        _rb13_cmd=(bash "$SHIM" -p "do a thing")
    fi
    RB13_CAP="$SANDBOX/rb13-$_rb13_entry-capture.log"
    _RB13_START=$(date +%s)
    FAKE_AGY_FORK_HANG=1 FAKE_AGY_PID_FILE="$RB13_PPF" FAKE_AGY_CHILD_PID_FILE="$RB13_CPF" \
        GEMINI_SHIM_TIMEOUT=3 \
        "$_TIMEOUT_NET" --foreground -k 5 30 "${_rb13_cmd[@]}" > "$RB13_CAP" 2>&1
    RB13_RC=$?
    _RB13_ELAPSED=$(( $(date +%s) - _RB13_START ))
    _rb_assert_reaped \
        "RB13 bounding binary present: $_rb13_entry delegation returns 124 and reaps agy plus its fork" \
        "$RB13_RC" "$_RB13_ELAPSED" "$RB13_PPF" "$RB13_CPF" "$(cat "$RB13_CAP")"
done

echo "== install.sh / uninstall.sh (vfn.11) =="

_MARKER='# agy-delegate-wrapper'

# _fresh_home -> prints a new temp HOME dir with bin/agy (fake) + bin on PATH.
_fresh_home() {
    local h; h="$(mktemp -d "$SANDBOX/ihome.XXXXXX")"
    mkdir -p "$h/.local/bin" "$h/bin"
    cp "$HERE/fake-agy.sh" "$h/bin/agy"
    chmod +x "$h/bin/agy"
    printf '%s' "$h"
}

# _install_in HOMEDIR EXTRA_ENV... -> run install.sh in a clean, isolated env.
_install_in() {
    local h="$1"; shift
    env -i HOME="$h" PATH="$h/bin:$h/.local/bin:/usr/bin:/bin" \
        AGY_PLUGIN_DIR="$ROOT" "$@" \
        bash "$INSTALL" > "$SANDBOX/last-install.log" 2>&1
}

# I1: pinned wrapper carries marker, records the abs path, and execs it (no glob).
IH="$(_fresh_home)"
if _install_in "$IH"; then I1_RC=0; else I1_RC=$?; fi
I1_OK=1
[[ "$I1_RC" -eq 0 ]] || I1_OK=0
[[ -f "$IH/.local/bin/agy-bridge" ]] || I1_OK=0
grep -qF "$_MARKER" "$IH/.local/bin/agy-bridge" 2>/dev/null || I1_OK=0
grep -qF "$ROOT/scripts/agy_bridge.sh" "$IH/.local/bin/agy-bridge" 2>/dev/null || I1_OK=0
grep -q 'plugins/cache' "$IH/.local/bin/agy-bridge" 2>/dev/null && I1_OK=0
grep -q 'claude plugin list' "$IH/.local/bin/agy-bridge" 2>/dev/null && I1_OK=0
WOUT="$(env -i HOME="$IH" PATH="$IH/bin:$IH/.local/bin:/usr/bin:/bin" \
    bash "$IH/.local/bin/agy-bridge" --types 2>&1)"; WRC=$?
[[ "$WRC" -eq 0 && "$WOUT" == *"model"* ]] || I1_OK=0
if [[ "$I1_OK" -eq 1 ]]; then
    ok "I1 pinned wrapper carries marker, records abs path, execs it (no glob/list)"
else
    bad "I1 pinned wrapper carries marker, records abs path, execs it (no glob/list)" "rc=$I1_RC wrc=$WRC log=$(tail -3 "$SANDBOX/last-install.log")"
fi

# I2: FAIL LOUD on broken pin.
IH="$(_fresh_home)"
_install_in "$IH" >/dev/null 2>&1
BW="$IH/.local/bin/agy-bridge"
sed -i "s#_AGY_TARGET='.*'#_AGY_TARGET='$IH/nonexistent/agy_bridge.sh'#" "$BW"
WOUT="$(env -i HOME="$IH" PATH="$IH/bin:$IH/.local/bin:/usr/bin:/bin" \
    bash "$BW" --types 2>&1)"; WRC=$?
if [[ "$WRC" -ne 0 && ( "$WOUT" == *"moved"* || "$WOUT" == *"re-run"* ) && "$WOUT" != *"model"* ]]; then
    ok "I2 wrapper FAILS LOUD (nonzero + re-run msg) on missing pinned path"
else
    bad "I2 wrapper FAILS LOUD (nonzero + re-run msg) on missing pinned path" "wrc=$WRC out=${WOUT:0:200}"
fi

# I3: non-clobber backs up a NON-agy target.
IH="$(_fresh_home)"
printf '#!/bin/sh\necho i am not agy\n' > "$IH/.local/bin/gemini"
chmod +x "$IH/.local/bin/gemini"
_install_in "$IH" >/dev/null 2>&1
I3_OK=1
grep -qF "$_MARKER" "$IH/.local/bin/gemini" 2>/dev/null || I3_OK=0
ls "$IH/.local/bin/gemini".bak-agy-* >/dev/null 2>&1 || I3_OK=0
grep -qi 'not an agy-delegate wrapper' "$SANDBOX/last-install.log" || I3_OK=0
_bak="$(ls "$IH/.local/bin/gemini".bak-agy-* 2>/dev/null | head -1)"
grep -q 'i am not agy' "$_bak" 2>/dev/null || I3_OK=0
if [[ "$I3_OK" -eq 1 ]]; then
    ok "I3 non-clobber backs up a non-agy target before overwriting"
else
    bad "I3 non-clobber backs up a non-agy target before overwriting" "log=$(tail -5 "$SANDBOX/last-install.log")"
fi

# I4: full-$PATH shadow scan warns which real gemini is shadowed.
IH="$(_fresh_home)"
mkdir -p "$IH/otherbin"
printf '#!/bin/sh\necho real gemini\n' > "$IH/otherbin/gemini"
chmod +x "$IH/otherbin/gemini"
env -i HOME="$IH" PATH="$IH/bin:$IH/otherbin:$IH/.local/bin:/usr/bin:/bin" \
    AGY_PLUGIN_DIR="$ROOT" bash "$INSTALL" > "$SANDBOX/last-install.log" 2>&1
if grep -qF "$IH/otherbin/gemini" "$SANDBOX/last-install.log" \
   && grep -qi 'shadow' "$SANDBOX/last-install.log"; then
    ok "I4 full-\$PATH shadow scan warns which real gemini is shadowed"
else
    bad "I4 full-\$PATH shadow scan warns which real gemini is shadowed" "log=$(grep -i gemini "$SANDBOX/last-install.log" | head -3)"
fi

# I5: disclosure notice names the shadow blast radius.
IH="$(_fresh_home)"
_install_in "$IH" >/dev/null 2>&1
if grep -qi 'shadow' "$SANDBOX/last-install.log" \
   && grep -qi 'blast radius' "$SANDBOX/last-install.log"; then
    ok "I5 disclosure notice states the gemini shadow blast radius"
else
    bad "I5 disclosure notice states the gemini shadow blast radius" "log=$(tail -8 "$SANDBOX/last-install.log")"
fi

# I6: refuse-root via SUDO_USER.
IH="$(_fresh_home)"
env -i HOME="$IH" PATH="$IH/bin:$IH/.local/bin:/usr/bin:/bin" \
    AGY_PLUGIN_DIR="$ROOT" SUDO_USER="someone" \
    bash "$INSTALL" > "$SANDBOX/last-install.log" 2>&1; I6_RC=$?
if [[ "$I6_RC" -ne 0 ]] && grep -qi 'root' "$SANDBOX/last-install.log" \
   && [[ ! -e "$IH/.local/bin/agy-bridge" ]]; then
    ok "I6 refuse-root (SUDO_USER set) aborts without installing"
else
    bad "I6 refuse-root (SUDO_USER set) aborts without installing" "rc=$I6_RC log=$(tail -2 "$SANDBOX/last-install.log")"
fi

# I6b: uninstall.sh also refuses root.
IH="$(_fresh_home)"
env -i HOME="$IH" PATH="$IH/bin:$IH/.local/bin:/usr/bin:/bin" SUDO_USER="someone" \
    bash "$UNINSTALL" > "$SANDBOX/last-uninstall.log" 2>&1; I6B_RC=$?
if [[ "$I6B_RC" -ne 0 ]] && grep -qi 'root' "$SANDBOX/last-uninstall.log"; then
    ok "I6b uninstall.sh refuses root"
else
    bad "I6b uninstall.sh refuses root" "rc=$I6B_RC log=$(tail -2 "$SANDBOX/last-uninstall.log")"
fi

# I7: idempotent re-run: no duplicate/backup of our own wrapper.
IH="$(_fresh_home)"
_install_in "$IH" >/dev/null 2>&1
_install_in "$IH" >/dev/null 2>&1
NBRIDGE_BAK="$(ls "$IH/.local/bin/agy-bridge".bak-agy-* 2>/dev/null | wc -l)"
NGEMINI_BAK="$(ls "$IH/.local/bin/gemini".bak-agy-* 2>/dev/null | wc -l)"
if [[ -f "$IH/.local/bin/agy-bridge" && -f "$IH/.local/bin/gemini" \
      && "$NBRIDGE_BAK" -eq 0 && "$NGEMINI_BAK" -eq 0 ]]; then
    ok "I7 idempotent re-run: no duplicate/backup of our own wrapper"
else
    bad "I7 idempotent re-run: no duplicate/backup of our own wrapper" "bridge_bak=$NBRIDGE_BAK gemini_bak=$NGEMINI_BAK"
fi

# I8: rc-alias patch writes NOTHING without AGY_SETUP_PATCH_ALIASES=1.
IH="$(_fresh_home)"
mkdir -p "$IH/otherbin"
printf '#!/bin/sh\necho real\n' > "$IH/otherbin/gemini"; chmod +x "$IH/otherbin/gemini"
printf "%s\n" "alias gemini='GEMINI_API_KEY=x gemini'" > "$IH/.bashrc"
_RCHASH_BEFORE="$(cksum "$IH/.bashrc")"
env -i HOME="$IH" PATH="$IH/bin:$IH/otherbin:$IH/.local/bin:/usr/bin:/bin" \
    AGY_PLUGIN_DIR="$ROOT" bash "$INSTALL" > "$SANDBOX/last-install.log" 2>&1
_RCHASH_AFTER="$(cksum "$IH/.bashrc")"
NRC_BAK="$(ls "$IH/.bashrc".bak-agy-* 2>/dev/null | wc -l)"
if [[ "$_RCHASH_BEFORE" == "$_RCHASH_AFTER" && "$NRC_BAK" -eq 0 ]]; then
    ok "I8 rc-alias patch is dry-run without AGY_SETUP_PATCH_ALIASES=1"
else
    bad "I8 rc-alias patch is dry-run without AGY_SETUP_PATCH_ALIASES=1" "changed=$([[ "$_RCHASH_BEFORE" != "$_RCHASH_AFTER" ]] && echo yes) baks=$NRC_BAK"
fi

# I8b: with the flag set, the rc alias IS rewritten + a .bak is written.
IH="$(_fresh_home)"
mkdir -p "$IH/otherbin"
printf '#!/bin/sh\necho real\n' > "$IH/otherbin/gemini"; chmod +x "$IH/otherbin/gemini"
printf "%s\n" "alias gemini='GEMINI_API_KEY=x gemini'" > "$IH/.bashrc"
env -i HOME="$IH" PATH="$IH/bin:$IH/otherbin:$IH/.local/bin:/usr/bin:/bin" \
    AGY_PLUGIN_DIR="$ROOT" AGY_SETUP_PATCH_ALIASES=1 \
    bash "$INSTALL" > "$SANDBOX/last-install.log" 2>&1
NRC_BAK="$(ls "$IH/.bashrc".bak-agy-* 2>/dev/null | wc -l)"
if grep -qF "$IH/otherbin/gemini'" "$IH/.bashrc" \
   && ! grep -qE "^alias gemini='[^']* gemini'\$" "$IH/.bashrc" \
   && [[ "$NRC_BAK" -ge 1 ]]; then
    ok "I8b rc-alias patch rewrites recursion + backs up (flag set)"
else
    bad "I8b rc-alias patch rewrites recursion + backs up (flag set)" "bashrc=$(cat "$IH/.bashrc") baks=$NRC_BAK"
fi

# I9: register on invalid JSON -> original untouched, temp cleaned, exit-3 msg.
IH="$(_fresh_home)"
mkdir -p "$IH/.gemini/antigravity-cli"
printf '%s' 'NOT VALID JSON {{{' > "$IH/.gemini/antigravity-cli/mcp_config.json"
_ORIG="$(cat "$IH/.gemini/antigravity-cli/mcp_config.json")"
printf '#!/bin/sh\nexit 0\n' > "$IH/bin/tokensave"; chmod +x "$IH/bin/tokensave"
env -i HOME="$IH" PATH="$IH/bin:$IH/.local/bin:/usr/bin:/bin" \
    AGY_PLUGIN_DIR="$ROOT" AGY_SETUP_REGISTER_TOKENSAVE=1 \
    bash "$INSTALL" > "$SANDBOX/last-install.log" 2>&1
_NOW="$(cat "$IH/.gemini/antigravity-cli/mcp_config.json")"
NTMP="$(ls "$IH/.gemini/antigravity-cli/".mcp_config.* 2>/dev/null | wc -l)"
if [[ "$_ORIG" == "$_NOW" ]] && grep -qi 'not valid JSON\|refusing to overwrite' "$SANDBOX/last-install.log" \
   && [[ "$NTMP" -eq 0 ]]; then
    ok "I9 register on invalid JSON: original untouched, temp cleaned, error surfaced"
else
    bad "I9 register on invalid JSON: original untouched, temp cleaned, error surfaced" "same=$([[ "$_ORIG" == "$_NOW" ]] && echo yes) ntmp=$NTMP log=$(grep -i json "$SANDBOX/last-install.log" | head -2)"
fi

# I9b: register happy-path.
IH="$(_fresh_home)"
mkdir -p "$IH/.gemini/antigravity-cli"
printf '%s\n' '{"mcpServers":{"lean-ctx":{"command":"lean-ctx"}}}' > "$IH/.gemini/antigravity-cli/mcp_config.json"
printf '#!/bin/sh\nexit 0\n' > "$IH/bin/tokensave"; chmod +x "$IH/bin/tokensave"
env -i HOME="$IH" PATH="$IH/bin:$IH/.local/bin:/usr/bin:/bin" \
    AGY_PLUGIN_DIR="$ROOT" AGY_SETUP_REGISTER_TOKENSAVE=1 \
    bash "$INSTALL" > "$SANDBOX/last-install.log" 2>&1
NCFG_BAK="$(ls "$IH/.gemini/antigravity-cli/mcp_config.json".bak-agy-* 2>/dev/null | wc -l)"
if grep -q '"tokensave"' "$IH/.gemini/antigravity-cli/mcp_config.json" \
   && grep -q '"lean-ctx"' "$IH/.gemini/antigravity-cli/mcp_config.json" \
   && [[ "$NCFG_BAK" -ge 1 ]]; then
    ok "I9b register happy-path: tokensave added, lean-ctx preserved, backup made"
else
    bad "I9b register happy-path: tokensave added, lean-ctx preserved, backup made" "cfg=$(cat "$IH/.gemini/antigravity-cli/mcp_config.json") baks=$NCFG_BAK"
fi

# I10: python3-absent register fails open (skips, install completes).
IH="$(_fresh_home)"
mkdir -p "$IH/.gemini/antigravity-cli" "$IH/nopy"
for b in bash cat grep sed date mktemp mkdir rm mv cp chmod ls readlink id printf command env; do
    _src="$(command -v "$b" 2>/dev/null)"; [[ -n "$_src" ]] && ln -sf "$_src" "$IH/nopy/$b" 2>/dev/null || true
done
cp "$HERE/fake-agy.sh" "$IH/nopy/agy"; chmod +x "$IH/nopy/agy"
printf '#!/bin/sh\nexit 0\n' > "$IH/nopy/tokensave"; chmod +x "$IH/nopy/tokensave"
printf '%s\n' '{"mcpServers":{}}' > "$IH/.gemini/antigravity-cli/mcp_config.json"
env -i HOME="$IH" PATH="$IH/nopy" AGY_PLUGIN_DIR="$ROOT" \
    AGY_SETUP_REGISTER_TOKENSAVE=1 \
    bash "$INSTALL" > "$SANDBOX/last-install.log" 2>&1; I10_RC=$?
if [[ "$I10_RC" -eq 0 && -f "$IH/.local/bin/agy-bridge" ]] \
   && ! grep -q '"tokensave"' "$IH/.gemini/antigravity-cli/mcp_config.json" \
   && grep -qi 'python3 not found' "$SANDBOX/last-install.log"; then
    ok "I10 python3-absent register fails open (skips, install completes)"
else
    bad "I10 python3-absent register fails open (skips, install completes)" "rc=$I10_RC log=$(tail -4 "$SANDBOX/last-install.log")"
fi

# I11: decline -> availability hint records tokensave:false.
IH="$(_fresh_home)"
_install_in "$IH" >/dev/null 2>&1
HINT="$IH/.config/agy-delegate/config.json"
if [[ -f "$HINT" ]] && grep -q '"tokensave": false' "$HINT"; then
    ok "I11 decline -> availability hint has tokensave:false"
else
    bad "I11 decline -> availability hint has tokensave:false" "hint=$(cat "$HINT" 2>/dev/null)"
fi

# I12: /agy-setup one-liner rejects non-matching/nonexistent resolved path.
SETUP_MD="$ROOT/.claude/commands/agy-setup.md"
_validate() {
    local RESOLVED="$1"
    case "$RESOLVED" in
        */agy-delegate/*/scripts/install.sh) ;;
        *) return 1 ;;
    esac
    [[ -f "$RESOLVED" ]] || return 1
    return 0
}
I12_OK=1
_validate "/tmp/evil/install.sh" && I12_OK=0
_validate "/x/agy-delegate/1.0/scripts/install.sh" && I12_OK=0
_realpath="$SANDBOX/agy-delegate/1.5.0/scripts"
mkdir -p "$_realpath"; : > "$_realpath/install.sh"
_validate "$_realpath/install.sh" || I12_OK=0
grep -q 'agy-delegate/\*/scripts/install.sh' "$SETUP_MD" || I12_OK=0
grep -qE '\-f ' "$SETUP_MD" || I12_OK=0
if [[ "$I12_OK" -eq 1 ]]; then
    ok "I12 one-liner rejects non-matching/nonexistent resolved path"
else
    bad "I12 one-liner rejects non-matching/nonexistent resolved path" "ok=$I12_OK"
fi

# I13: uninstall reverses install (wrappers gone, shadowed original restored).
IH="$(_fresh_home)"
printf '#!/bin/sh\necho original gemini\n' > "$IH/.local/bin/gemini"; chmod +x "$IH/.local/bin/gemini"
_install_in "$IH" >/dev/null 2>&1
env -i HOME="$IH" PATH="$IH/bin:$IH/.local/bin:/usr/bin:/bin" \
    bash "$UNINSTALL" > "$SANDBOX/last-uninstall.log" 2>&1; I13_RC=$?
I13_OK=1
[[ "$I13_RC" -eq 0 ]] || I13_OK=0
[[ -e "$IH/.local/bin/agy-bridge" ]] && I13_OK=0
grep -qF "$_MARKER" "$IH/.local/bin/gemini" 2>/dev/null && I13_OK=0
grep -q 'original gemini' "$IH/.local/bin/gemini" 2>/dev/null || I13_OK=0
if [[ "$I13_OK" -eq 1 ]]; then
    ok "I13 uninstall reverses install (wrappers gone, shadowed original restored)"
else
    bad "I13 uninstall reverses install (wrappers gone, shadowed original restored)" "rc=$I13_RC log=$(tail -4 "$SANDBOX/last-uninstall.log")"
fi

# I13b: uninstall de-registers tokensave + removes hint (flag set).
IH="$(_fresh_home)"
mkdir -p "$IH/.gemini/antigravity-cli"
printf '%s\n' '{"mcpServers":{}}' > "$IH/.gemini/antigravity-cli/mcp_config.json"
printf '#!/bin/sh\nexit 0\n' > "$IH/bin/tokensave"; chmod +x "$IH/bin/tokensave"
env -i HOME="$IH" PATH="$IH/bin:$IH/.local/bin:/usr/bin:/bin" \
    AGY_PLUGIN_DIR="$ROOT" AGY_SETUP_REGISTER_TOKENSAVE=1 \
    bash "$INSTALL" > "$SANDBOX/last-install.log" 2>&1
env -i HOME="$IH" PATH="$IH/bin:$IH/.local/bin:/usr/bin:/bin" \
    AGY_UNINSTALL_TOKENSAVE=1 \
    bash "$UNINSTALL" > "$SANDBOX/last-uninstall.log" 2>&1
if ! grep -q '"tokensave"' "$IH/.gemini/antigravity-cli/mcp_config.json" \
   && [[ ! -f "$IH/.config/agy-delegate/config.json" ]]; then
    ok "I13b uninstall de-registers tokensave + removes hint (flag set)"
else
    bad "I13b uninstall de-registers tokensave + removes hint (flag set)" "cfg=$(cat "$IH/.gemini/antigravity-cli/mcp_config.json") hint=$([[ -f "$IH/.config/agy-delegate/config.json" ]] && echo present)"
fi

# I14: uninstall is idempotent (second run exits 0).
IH="$(_fresh_home)"
_install_in "$IH" >/dev/null 2>&1
env -i HOME="$IH" PATH="$IH/bin:$IH/.local/bin:/usr/bin:/bin" bash "$UNINSTALL" >/dev/null 2>&1
env -i HOME="$IH" PATH="$IH/bin:$IH/.local/bin:/usr/bin:/bin" bash "$UNINSTALL" > "$SANDBOX/last-uninstall.log" 2>&1; I14_RC=$?
if [[ "$I14_RC" -eq 0 ]]; then
    ok "I14 uninstall is idempotent (second run exits 0)"
else
    bad "I14 uninstall is idempotent (second run exits 0)" "rc=$I14_RC log=$(tail -3 "$SANDBOX/last-uninstall.log")"
fi

# I15: install+uninstall touch NO repo file (git status unchanged).
if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse >/dev/null 2>&1; then
    _GIT_BEFORE="$(cd "$ROOT" && git status --porcelain)"
    IH="$(_fresh_home)"
    _install_in "$IH" >/dev/null 2>&1
    env -i HOME="$IH" PATH="$IH/bin:$IH/.local/bin:/usr/bin:/bin" bash "$UNINSTALL" >/dev/null 2>&1
    _GIT_AFTER="$(cd "$ROOT" && git status --porcelain)"
    if [[ "$_GIT_BEFORE" == "$_GIT_AFTER" ]]; then
        ok "I15 install+uninstall touch no repo file (git status unchanged)"
    else
        bad "I15 install+uninstall touch no repo file (git status unchanged)" "git status changed"
    fi
else
    ok "I15 (skipped: no git repo) install/uninstall repo-untouched"
fi

# I16: a stale pin FAILS LOUD. The launcher compares its install-time pinned
# version against the active version in Claude Code's install registry and
# refuses to exec when they differ, naming the repin command. A missing or
# unparseable registry degrades to silence (dev installs must keep working),
# and the exec target stays the install-time literal in every case.
IH="$(_fresh_home)"
VROOT="$(mktemp -d "$SANDBOX/vfake.XXXXXX")"
mkdir -p "$VROOT/agy-delegate/1.0.0/scripts"
cp "$ROOT/scripts/agy_bridge.sh" "$ROOT/scripts/gemini_shim.sh" "$VROOT/agy-delegate/1.0.0/scripts/"
env -i HOME="$IH" PATH="$IH/bin:$IH/.local/bin:/usr/bin:/bin" \
    AGY_PLUGIN_DIR="$VROOT/agy-delegate/1.0.0" \
    bash "$INSTALL" > "$SANDBOX/last-install.log" 2>&1
BW="$IH/.local/bin/agy-bridge"

# (a) no registry at all -> silent, works normally
OUT_NOREG="$(env -i HOME="$IH" PATH="$IH/bin:$IH/.local/bin:/usr/bin:/bin" bash "$BW" --types 2>"$SANDBOX/err-noreg.log")"
RC_NOREG=$?
ERR_NOREG="$(cat "$SANDBOX/err-noreg.log")"

# install.sh derives the registry key "<plugin>@<marketplace>" from the cache
# layout cache/<marketplace>/<plugin>/<version>, so under this fake root the
# marketplace segment is $VROOT's own basename.
REG_KEY="agy-delegate@$(basename "$VROOT")"
# Every fixture carries a sentinel installPath. The launcher must never echo it:
# a registry-supplied path in the repin hint would tell the user to bash an
# attacker-controlled location.
SENTINEL="/tmp/AGY-REGISTRY-PATH-SENTINEL"

# (b) registry agreeing with the pin -> silent, byte-identical to (a)
mkdir -p "$IH/.claude/plugins"
cat > "$IH/.claude/plugins/installed_plugins.json" <<REGJSON
{
  "version": 2,
  "plugins": {
    "$REG_KEY": [
      {
        "scope": "user",
        "installPath": "$SENTINEL",
        "version": "1.0.0"
      }
    ]
  }
}
REGJSON
OUT_MATCH="$(env -i HOME="$IH" PATH="$IH/bin:$IH/.local/bin:/usr/bin:/bin" bash "$BW" --types 2>"$SANDBOX/err-match.log")"
RC_MATCH=$?
ERR_MATCH="$(cat "$SANDBOX/err-match.log")"

# (c) registry naming a NEWER active version -> exit 127, names both versions
#     and a CONSTRUCTED repin command, and produces no stdout. The 1.1.0 tree
#     must exist for the constructed path to be printed.
mkdir -p "$VROOT/agy-delegate/1.1.0/scripts"
: > "$VROOT/agy-delegate/1.1.0/scripts/install.sh"
cat > "$IH/.claude/plugins/installed_plugins.json" <<REGJSON
{
  "version": 2,
  "plugins": {
    "$REG_KEY": [
      {
        "scope": "user",
        "installPath": "$SENTINEL",
        "version": "1.1.0"
      }
    ]
  }
}
REGJSON
OUT_STALE="$(env -i HOME="$IH" PATH="$IH/bin:$IH/.local/bin:/usr/bin:/bin" bash "$BW" --types 2>"$SANDBOX/err-stale.log")"
RC_STALE=$?
ERR_STALE="$(cat "$SANDBOX/err-stale.log")"

# (d) unparseable registry -> silent, still runs
printf '%s' '{ this is not json' > "$IH/.claude/plugins/installed_plugins.json"
OUT_BADJSON="$(env -i HOME="$IH" PATH="$IH/bin:$IH/.local/bin:/usr/bin:/bin" bash "$BW" --types 2>"$SANDBOX/err-badjson.log")"
RC_BADJSON=$?
ERR_BADJSON="$(cat "$SANDBOX/err-badjson.log")"

# (e) a LOOKALIKE plugin from a different marketplace must not match. Same
#     plugin name, different marketplace segment, listed first, claiming a much
#     newer version. A prefix match on '"agy-delegate@' would fire on this and
#     hand the user an attacker-chosen path; the exact-key match must ignore it.
cat > "$IH/.claude/plugins/installed_plugins.json" <<REGJSON
{
  "version": 2,
  "plugins": {
    "agy-delegate@evil-marketplace": [
      {
        "scope": "user",
        "installPath": "$SENTINEL",
        "version": "9.9.9"
      }
    ]
  }
}
REGJSON
OUT_EVIL="$(env -i HOME="$IH" PATH="$IH/bin:$IH/.local/bin:/usr/bin:/bin" bash "$BW" --types 2>"$SANDBOX/err-evil.log")"
RC_EVIL=$?
ERR_EVIL="$(cat "$SANDBOX/err-evil.log")"

I16_OK=1
[[ "$ERR_NOREG"   != *"ERROR"* ]]            || I16_OK=0
[[ "$ERR_MATCH"   != *"ERROR"* ]]            || I16_OK=0
[[ "$OUT_NOREG"   == "$OUT_MATCH" ]]         || I16_OK=0
[[ "$RC_NOREG"    -eq "$RC_MATCH" ]]         || I16_OK=0
[[ "$RC_STALE"    -eq 127 ]]                 || I16_OK=0
[[ -z "$OUT_STALE" ]]                        || I16_OK=0
case "$ERR_STALE" in *"1.0.0"*"1.1.0"*|*"1.1.0"*"1.0.0"*) :;; *) I16_OK=0;; esac
# repin hint is CONSTRUCTED from the trusted versions root, never the registry's
# own installPath -- the sentinel must not appear anywhere in the message
[[ "$ERR_STALE"   == *"$VROOT/agy-delegate/1.1.0/scripts/install.sh"* ]] || I16_OK=0
[[ "$ERR_STALE"   != *"$SENTINEL"* ]]        || I16_OK=0
[[ "$ERR_BADJSON" != *"ERROR"* ]]            || I16_OK=0
[[ "$RC_BADJSON"  -eq "$RC_NOREG" ]]         || I16_OK=0
# lookalike from another marketplace is ignored entirely
[[ "$ERR_EVIL"    != *"ERROR"* ]]            || I16_OK=0
[[ "$ERR_EVIL"    != *"9.9.9"* ]]            || I16_OK=0
[[ "$RC_EVIL"     -eq "$RC_NOREG" ]]         || I16_OK=0
grep -qF "_AGY_TARGET='$VROOT/agy-delegate/1.0.0/scripts/agy_bridge.sh'" "$BW" || I16_OK=0
[[ "$(grep -c '^_AGY_TARGET=' "$BW")" -eq 1 ]] || I16_OK=0
grep -qE '^exec -a "[^"]+" bash "\$_AGY_TARGET" "\$@"$' "$BW" || I16_OK=0
if [[ "$I16_OK" -eq 1 ]]; then
    ok "I16 stale pin vs install registry -> exit 127; absent/bad registry silent; exec target pinned"
else
    bad "I16 stale pin vs install registry -> exit 127; absent/bad registry silent; exec target pinned" \
        "rc_noreg=$RC_NOREG rc_match=$RC_MATCH rc_stale=$RC_STALE rc_badjson=$RC_BADJSON rc_evil=$RC_EVIL err_stale=${ERR_STALE:0:200}"
fi

# I17: the stale-pin extraction window is bounded to OUR OWN registry entry.
# Two registry shapes mis-attribute a neighbouring plugin's version when the
# window is a fixed line count and the version match is greedy/unanchored:
#   (f) our key present but with an EMPTY array -- a `grep -A6` window runs
#       past it into the next plugin's entry;
#   (g) a COMPACT (single-line) registry -- an unanchored greedy `.*"version"`
#       selects the LAST version in the whole file;
#   (h) a SEMI-COMPACT registry -- the window matches but the entry body is one
#       line, so only the line-start anchor stops the same greedy selection.
# All three must stay SILENT and exec normally. Neither can reach exec or print an
# attacker path, but a spurious exit 127 would break every caller on PATH,
# because ~/.local/bin/gemini shadows the real gemini command.
IH="$(_fresh_home)"
VROOT2="$(mktemp -d "$SANDBOX/vfake2.XXXXXX")"
mkdir -p "$VROOT2/agy-delegate/1.0.0/scripts"
cp "$ROOT/scripts/agy_bridge.sh" "$ROOT/scripts/gemini_shim.sh" "$VROOT2/agy-delegate/1.0.0/scripts/"
env -i HOME="$IH" PATH="$IH/bin:$IH/.local/bin:/usr/bin:/bin" \
    AGY_PLUGIN_DIR="$VROOT2/agy-delegate/1.0.0" \
    bash "$INSTALL" > "$SANDBOX/last-install.log" 2>&1
BW="$IH/.local/bin/agy-bridge"
REG_KEY2="agy-delegate@$(basename "$VROOT2")"
NEIGHBOUR="/tmp/AGY-NEIGHBOUR-PATH-SENTINEL"

# baseline: no registry file yet -> silent, works normally
OUT_BASE="$(env -i HOME="$IH" PATH="$IH/bin:$IH/.local/bin:/usr/bin:/bin" bash "$BW" --types 2>"$SANDBOX/err-base.log")"
RC_BASE=$?
ERR_BASE="$(cat "$SANDBOX/err-base.log")"

# (f) our key is an EMPTY array; a populated third-party entry follows it
mkdir -p "$IH/.claude/plugins"
cat > "$IH/.claude/plugins/installed_plugins.json" <<REGJSON
{
  "version": 2,
  "plugins": {
    "$REG_KEY2": [],
    "other-plugin@other-marketplace": [
      {
        "scope": "user",
        "installPath": "$NEIGHBOUR",
        "version": "9.9.9"
      }
    ]
  }
}
REGJSON
OUT_EMPTY="$(env -i HOME="$IH" PATH="$IH/bin:$IH/.local/bin:/usr/bin:/bin" bash "$BW" --types 2>"$SANDBOX/err-empty.log")"
RC_EMPTY=$?
ERR_EMPTY="$(cat "$SANDBOX/err-empty.log")"

# (g) COMPACT registry: our key first AT the pinned version, a third-party
#     entry later on the SAME line carrying a different version
printf '%s' "{\"version\":2,\"plugins\":{\"$REG_KEY2\":[{\"scope\":\"user\",\"installPath\":\"$NEIGHBOUR\",\"version\":\"1.0.0\"}],\"other-plugin@other-marketplace\":[{\"scope\":\"user\",\"installPath\":\"$NEIGHBOUR\",\"version\":\"9.9.9\"}]}}" \
    > "$IH/.claude/plugins/installed_plugins.json"
OUT_COMPACT="$(env -i HOME="$IH" PATH="$IH/bin:$IH/.local/bin:/usr/bin:/bin" bash "$BW" --types 2>"$SANDBOX/err-compact.log")"
RC_COMPACT=$?
ERR_COMPACT="$(cat "$SANDBOX/err-compact.log")"

# (h) SEMI-COMPACT registry: our array opens on its own line, so the window
#     DOES match, but the entry body is a single line carrying two version
#     fields. Only the line-start anchor on the version match stops the greedy
#     tail from selecting the neighbouring object's version.
{
    printf '%s\n' '{' '  "version": 2,' '  "plugins": {' "    \"$REG_KEY2\": ["
    printf '%s\n' "{\"scope\":\"user\",\"installPath\":\"$NEIGHBOUR\",\"version\":\"1.0.0\"},{\"scope\":\"user\",\"installPath\":\"$NEIGHBOUR\",\"version\":\"9.9.9\"}"
    printf '%s\n' '    ]' '  }' '}'
} > "$IH/.claude/plugins/installed_plugins.json"
OUT_SEMI="$(env -i HOME="$IH" PATH="$IH/bin:$IH/.local/bin:/usr/bin:/bin" bash "$BW" --types 2>"$SANDBOX/err-semi.log")"
RC_SEMI=$?
ERR_SEMI="$(cat "$SANDBOX/err-semi.log")"

I17_OK=1
[[ "$ERR_EMPTY"   != *"ERROR"* ]]       || I17_OK=0
[[ "$ERR_EMPTY"   != *"9.9.9"* ]]       || I17_OK=0
[[ "$RC_EMPTY"    -eq "$RC_BASE" ]]     || I17_OK=0
[[ "$OUT_EMPTY"   == "$OUT_BASE" ]]     || I17_OK=0
[[ "$ERR_COMPACT" != *"ERROR"* ]]       || I17_OK=0
[[ "$ERR_COMPACT" != *"9.9.9"* ]]       || I17_OK=0
[[ "$RC_COMPACT"  -eq "$RC_BASE" ]]     || I17_OK=0
[[ "$OUT_COMPACT" == "$OUT_BASE" ]]     || I17_OK=0
[[ "$ERR_SEMI"    != *"ERROR"* ]]       || I17_OK=0
[[ "$ERR_SEMI"    != *"9.9.9"* ]]       || I17_OK=0
[[ "$RC_SEMI"     -eq "$RC_BASE" ]]     || I17_OK=0
[[ "$OUT_SEMI"    == "$OUT_BASE" ]]     || I17_OK=0
if [[ "$I17_OK" -eq 1 ]]; then
    ok "I17 registry window bounded to our entry (empty/compact/semi-compact -> silent)"
else
    bad "I17 registry window bounded to our entry (empty/compact/semi-compact -> silent)" \
        "rc_base=$RC_BASE rc_empty=$RC_EMPTY rc_compact=$RC_COMPACT rc_semi=$RC_SEMI err_empty=${ERR_EMPTY:0:120} err_compact=${ERR_COMPACT:0:120} err_semi=${ERR_SEMI:0:120}"
fi

# I18: an apostrophe anywhere in the plugin cache path must not break the
# generated wrapper. install.sh interpolates install-time values into
# single-quoted contexts in the heredoc -- _AGY_TARGET, _AGY_VERSION,
# _AGY_VERSIONS_ROOT, and reg_key_re inside a single-quoted sed script -- and
# an unescaped apostrophe in any of them terminates the quoting early,
# producing a syntactically broken wrapper. That wrapper shadows the real
# `gemini` for every caller on PATH, so a broken quote breaks every one of
# them, not just this install.
IH="$(_fresh_home)"
# Apostrophes in BOTH the marketplace segment (-> reg_key/reg_key_re, and via
# the shared prefix _AGY_TARGET/_AGY_VERSIONS_ROOT) and the version segment
# (-> _AGY_VERSION, otherwise unexercised since the marketplace apostrophe
# alone already forces target/parent_dir to carry one) -- so a regression in
# ANY single interpolation site is caught, not just the first one hit.
VROOT3="$SANDBOX/dd's-plugins.$$"
PDIR3="$VROOT3/agy-delegate/1.0.0's-beta"
mkdir -p "$PDIR3/scripts"
cp "$ROOT/scripts/agy_bridge.sh" "$ROOT/scripts/gemini_shim.sh" "$PDIR3/scripts/"
env -i HOME="$IH" PATH="$IH/bin:$IH/.local/bin:/usr/bin:/bin" \
    AGY_PLUGIN_DIR="$PDIR3" \
    bash "$INSTALL" > "$SANDBOX/last-install.log" 2>&1
BW="$IH/.local/bin/agy-bridge"

# Expected wrapper-visible forms: the same '->'\'' escape the fix applies,
# computed independently here so these assertions catch a missing/wrong
# escape rather than just echoing install.sh's own output.
TARGET_PATH="$PDIR3/scripts/agy_bridge.sh"
TARGET_SQ="${TARGET_PATH//\'/\'\\\'\'}"
VERSION_SQ="${PDIR3##*/}"; VERSION_SQ="${VERSION_SQ//\'/\'\\\'\'}"

I18_OK=1
bash -n "$BW" 2>"$SANDBOX/err-i18-syntax.log" || I18_OK=0
grep -qF "_AGY_TARGET='$TARGET_SQ'" "$BW" || I18_OK=0
grep -qF "_AGY_VERSION='$VERSION_SQ'" "$BW" || I18_OK=0
[[ "$(grep -c '^_AGY_TARGET=' "$BW")" -eq 1 ]] || I18_OK=0
grep -qE '^exec -a "[^"]+" bash "\$_AGY_TARGET" "\$@"$' "$BW" || I18_OK=0
WOUT="$(env -i HOME="$IH" PATH="$IH/bin:$IH/.local/bin:/usr/bin:/bin" bash "$BW" --types 2>&1)"; WRC=$?
[[ "$WRC" -eq 0 && "$WOUT" == *"model"* ]] || I18_OK=0
if [[ "$I18_OK" -eq 1 ]]; then
    ok "I18 apostrophe in plugin cache path does not break the generated wrapper"
else
    bad "I18 apostrophe in plugin cache path does not break the generated wrapper" \
        "syntax_err=$(cat "$SANDBOX/err-i18-syntax.log") wrc=$WRC wout=${WOUT:0:200} log=$(tail -5 "$SANDBOX/last-install.log")"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -eq 0 ]]; then
    exit 0
else
    exit 1
fi
