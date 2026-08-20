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
CONTRACT_CHECK="$HERE/contract-check.sh"

SANDBOX="$(mktemp -d -t agy-tests.XXXXXX)"
# Reap anything a fixture left running before removing the sandbox. Every
# fixture that records a PID writes it to $SANDBOX/<name>.pid; a failing run
# must not leave 300-second sleepers behind on the developer's box.
#
# It is a net for the cases that did NOT get that far, and only those: every
# case empties its own pid files once it has reaped them, because a pid recorded
# in the first seconds of a two-and-a-half-minute run may belong to something
# else entirely by the time this runs. On Linux with pid_max at 4194304 that is
# remote; on macOS, where pid_max is 99998 and this phase's watchdog is the
# reason the suite exists, recycling inside one run is ordinary. A test harness
# that SIGKILLs a developer's unrelated process is a defect regardless of
# probability, so the emptying is the fix and this is what is left over.
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

# _cc_fixtures_beside DIR -- copy tests/fixtures/ next to a copied fake `agy`
# in DIR, so tier 2 of fake-agy.sh's `_fake_fixture` resolution
# (`$(dirname "$0")/fixtures`) finds the real captured data wherever the fake
# was copied. Tier 3 (AGY_PLUGIN_DIR) is not a substitute for this: where a
# case's environment is deliberately bare (RB27), the fixtures travel with
# the binary or the case is destroyed by the fix. A missing source directory
# is FATAL, not silent -- the same discipline _purebin() applies to a missing
# whitelisted tool: a silently-absent fixtures directory would turn every
# case that resolves a model into a vacuous pass.
_cc_fixtures_beside() {
    local dir="$1"
    if [[ ! -d "$HERE/fixtures" ]]; then
        printf 'FATAL: tests/fixtures/ missing, cannot plumb fixtures beside copied fake at %s\n' "$dir" >&2
        exit 1
    fi
    cp -R "$HERE/fixtures" "$dir/fixtures"
}

mkdir -p "$SANDBOX/bin" "$SANDBOX/home"
cp "$HERE/fake-agy.sh" "$SANDBOX/bin/agy"
chmod +x "$SANDBOX/bin/agy"
_cc_fixtures_beside "$SANDBOX/bin"

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

# _cc_expect_model CLASS [FIXTURE_PATH] -- derive the expected model id for
# CLASS (e.g. flash-high, pro-high) from a fixture with the shipped rule,
# byte-for-byte: scripts/agy_bridge.sh's
# grep -E '^gemini-[0-9.]+-<class>$' | sort -V | tail -1. FIXTURE_PATH is
# optional and defaults to $HERE/fixtures/agy-models.tsv, so R2 and R4 read
# the real capture while task 3's derivation-edges case drives this same
# byte-identical derivation over synthetic lists it writes into the sandbox
# (F3) -- one parameter, two callers, no override variable and no
# reimplementation of the rule at either call site. An unreadable fixture or
# an empty result is FATAL naming the path read, following _purebin()'s
# missing-tool discipline -- a vacuous expectation would make every caller
# compare nothing to nothing.
_cc_expect_model() {
    local class="$1" fixture="${2:-$HERE/fixtures/agy-models.tsv}" id
    if [[ ! -r "$fixture" ]]; then
        printf 'FATAL: _cc_expect_model cannot read fixture %s\n' "$fixture" >&2
        exit 1
    fi
    id="$(grep -v '^#' "$fixture" | cut -f1 | grep -E "^gemini-[0-9.]+-${class}\$" | sort -V | tail -1)"
    if [[ -z "$id" ]]; then
        printf 'FATAL: _cc_expect_model found no gemini-*-%s id in %s\n' "$class" "$fixture" >&2
        exit 1
    fi
    printf '%s' "$id"
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
    _cc_fixtures_beside "$d"
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
#
# Captured through a FILE and read back afterwards, never through a live command
# substitution, and that is not style. Each entry point opens fd 9 on its own
# original stderr and every child inherits what it is given; under a command
# substitution such a descriptor IS the capture pipe, so a run whose assertions
# ought to FAIL instead leaves a survivor holding the pipe and blocks for the
# fixture's full sleep -- measured on this suite, a ~10s red case became a ~5min
# one, which is why RB05 and the RB09-RB14 drivers were moved to files. RB04 and
# RB08 reach the mechanism through here and were not. The shipped scripts now
# close fd 9 for the bounded command (RB23), so this is the second line of
# defence rather than the first: a file cannot be held open against us, whatever
# a future child inherits. The outer net bounds the entry point; this bounds the
# read.
_run_sanitized() {
    local __outvar="$1" __rcvar="$2"
    shift 2
    local __dir __rc __f
    __dir="$(_purebin)"
    __f="$SANDBOX/run-sanitized.out"
    PATH="$__dir" "$_TIMEOUT_NET" --foreground -k 5 30 "$@" > "$__f" 2>&1
    __rc=$?
    printf -v "$__outvar" '%s' "$(cat "$__f" 2>/dev/null)"
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

# R2: search delegation resolves the latest matching flash-high from the
# fixture via sort -V -- derived with the shipped rule, never a pinned
# version, so a recapture cannot leave a stale expectation passing silently.
R2_EXPECT="$(_cc_expect_model flash-high)"
FAKE_AGY_STDOUT="ok" _run OUT RC bash "$BRIDGE" --type search --verbose -- "latest check"
if [[ "$OUT" == *"model=$R2_EXPECT"* ]]; then
    ok "R2 --type search --verbose resolves the latest matching flash-high from the fixture"
else
    bad "R2 --type search --verbose resolves the latest matching flash-high from the fixture" \
        "expected=$R2_EXPECT rc=$RC out=$OUT"
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
if [[ "$RC" -eq 2 && "$OUT" == *"no 'gemini-' ids"* && "$OUT" != *"for --type"* && "$OUT" == *"FAKE-AGY-DEGRADED"* ]]; then
    ok "R8 model list with no gemini ids reports a degraded list, not a bad --type"
else
    bad "R8 model list with no gemini ids reports a degraded list, not a bad --type" "rc=$RC out=$OUT"
fi
# Under D-03 the bridge no longer caches a degraded (gemini--less) reply, so
# this is now defensive cleanup rather than a required undo -- kept so a
# later regression in the write gate still leaves later tests seeing a full
# model list on their next fetch. Same pattern as R3/R3c/R6.
rm -f "$HOME/.cache/agy-bridge-models"

# R9: a degraded (gemini--less) agy models reply must never reach the cache
# file the shim also reads (D-03, delegate-agy-8ph) -- absent stays absent,
# present stays byte-identical, regardless of the outcome of the call itself.
_R9_CACHE="$HOME/.cache/agy-bridge-models"
R9_OK=1
R9_DETAIL=""

# First half: no cache on disk -- outcome unchanged (rc=2, degraded message),
# and nothing gets created.
rm -f "$_R9_CACHE"
FAKE_AGY_MODELS_GARBAGE=1 _run OUT RC bash "$BRIDGE" --type code -- "garbage no cache"
if [[ "$RC" -ne 2 || "$OUT" != *"no 'gemini-' ids"* || -s "$_R9_CACHE" ]]; then
    R9_OK=0
    R9_DETAIL="${R9_DETAIL}absent-half: rc=$RC cache_exists=$( [[ -s "$_R9_CACHE" ]] && echo yes || echo no ) out=$OUT; "
fi

# Second half: a good cache already on disk survives a degraded reply
# byte-for-byte -- this is what a poisoned cache would otherwise break.
mkdir -p "$(dirname "$_R9_CACHE")"
printf '%s\t%s\n' "gemini-3.1-pro-high" "Gemini 3.1 Pro (High)" > "$_R9_CACHE"
touch -d '2 hours ago' "$_R9_CACHE"
_R9_BEFORE="$(cat "$_R9_CACHE")"
FAKE_AGY_MODELS_GARBAGE=1 _run OUT RC bash "$BRIDGE" --type code -- "garbage with cache"
_R9_AFTER="$(cat "$_R9_CACHE" 2>/dev/null)"
if [[ "$_R9_AFTER" != "$_R9_BEFORE" ]]; then
    R9_OK=0
    R9_DETAIL="${R9_DETAIL}preservation-half: before=[$_R9_BEFORE] after=[$_R9_AFTER]; "
fi
rm -f "$_R9_CACHE"

if [[ "$R9_OK" -eq 1 ]]; then
    ok "R9 a degraded agy models reply never reaches the cache file, absent or present"
else
    bad "R9 a degraded agy models reply never reaches the cache file, absent or present" "$R9_DETAIL"
fi

# R9b: a degraded (gemini--less) reply with a good stale cache present falls
# back to that cache and completes at rc 0 (D-04), with a warning an operator
# can tell apart from a fetch-failure warning (D-05), and now also shows
# agy's own stderr diagnostic on this same path too (D-07).
_R9B_EXPECT="gemini-3.1-pro-high"
_R9B_CACHE="$HOME/.cache/agy-bridge-models"
mkdir -p "$(dirname "$_R9B_CACHE")"
printf '%s\t%s\n' "$_R9B_EXPECT" "Gemini 3.1 Pro (High)" > "$_R9B_CACHE"
touch -d '2 hours ago' "$_R9B_CACHE"
FAKE_AGY_MODELS_GARBAGE=1 FAKE_AGY_STDOUT="ok" _run OUT RC bash "$BRIDGE" --type code --verbose -- "stale fallback, degraded"
R9B_OK=1
R9B_DETAIL=""
[[ "$RC" -eq 0 ]] || { R9B_OK=0; R9B_DETAIL="${R9B_DETAIL}rc=$RC (want 0); "; }
[[ "$OUT" == *"model=$_R9B_EXPECT"* ]] || { R9B_OK=0; R9B_DETAIL="${R9B_DETAIL}model not resolved from cache, out=$OUT; "; }
[[ "$OUT" == *"WARNING"* ]] || { R9B_OK=0; R9B_DETAIL="${R9B_DETAIL}no WARNING in out=$OUT; "; }
[[ "$OUT" == *"no 'gemini-' ids"* ]] || { R9B_OK=0; R9B_DETAIL="${R9B_DETAIL}degraded-cause wording absent, out=$OUT; "; }
[[ "$OUT" != *"'agy models' exited"* && "$OUT" != *"'agy models' timed out"* ]] || { R9B_OK=0; R9B_DETAIL="${R9B_DETAIL}fetch-failure wording leaked into degraded warning, out=$OUT; "; }
[[ -n "$(find "$_R9B_CACHE" -mmin +60 2>/dev/null)" ]] || { R9B_OK=0; R9B_DETAIL="${R9B_DETAIL}cache mtime was refreshed by the fallback; "; }
[[ "$OUT" == *"FAKE-AGY-DEGRADED"* ]] || { R9B_OK=0; R9B_DETAIL="${R9B_DETAIL}agy's own stderr (FAKE-AGY-DEGRADED) not shown, out=$OUT; "; }
rm -f "$_R9B_CACHE"
if [[ "$R9B_OK" -eq 1 ]]; then
    ok "R9b a degraded reply with a stale cache falls back at rc 0, warns distinctly, shows agy's stderr, mtime untouched"
else
    bad "R9b a degraded reply with a stale cache falls back at rc 0, warns distinctly, shows agy's stderr, mtime untouched" "$R9B_DETAIL"
fi

# R9c: an extra column and a trailing tab both normalize through cut -f1 on
# the REAL fetch path (D-06), with the anchored matchers byte-identical --
# a real agy models reply through the bridge's whole fetch -> gate -> normalize
# -> match path, not the cache-read normalization R3c already proves.
# Synthetic rows, never added to tests/fixtures/agy-models.tsv (D-14/D-14a):
# ids below appear nowhere else, in different classes so version-sort in one
# class cannot mask the other.
R9C_DIR="$(mktemp -d "$SANDBOX/r9c.XXXXXX")"
printf '%s\n' \
    "# synthetic R9c fixture -- not captured evidence, see D-06/D-14a" \
    "$(printf '%s\t%s\t%s' "gemini-9.4-flash-high" "R9c Flash" "extra-column")" \
    "$(printf '%s\t' "gemini-9.3-pro-high")" \
    > "$R9C_DIR/agy-models.tsv"
R9C_OK=1
R9C_DETAIL=""

rm -f "$HOME/.cache/agy-bridge-models"
AGY_FIXTURES_DIR="$R9C_DIR" FAKE_AGY_STDOUT="ok" _run OUT RC bash "$BRIDGE" --type search --verbose -- "extra column"
if [[ "$RC" -ne 0 || "$OUT" != *"model=gemini-9.4-flash-high"* ]]; then
    R9C_OK=0
    R9C_DETAIL="${R9C_DETAIL}extra-column: rc=$RC out=$OUT; "
fi

rm -f "$HOME/.cache/agy-bridge-models"
AGY_FIXTURES_DIR="$R9C_DIR" FAKE_AGY_STDOUT="ok" _run OUT RC bash "$BRIDGE" --type code --verbose -- "trailing tab"
if [[ "$RC" -ne 0 || "$OUT" != *"model=gemini-9.3-pro-high"* ]]; then
    R9C_OK=0
    R9C_DETAIL="${R9C_DETAIL}trailing-tab: rc=$RC out=$OUT; "
fi

# The synthetic ids above are well-formed gemini ids, so the write gate lets
# them land in the shared $HOME's cache -- clean up so no later case sees a
# model version that does not exist.
rm -f "$HOME/.cache/agy-bridge-models"
rm -rf "$R9C_DIR"

if [[ "$R9C_OK" -eq 1 ]]; then
    ok "R9c an extra column and a trailing tab both normalize through the real fetch path"
else
    bad "R9c an extra column and a trailing tab both normalize through the real fetch path" "$R9C_DETAIL"
fi

# R9d (CR-01): --model validation reads the same untrusted $VALID_MODELS as
# D-08's herestring-converted write-gate/use-time checks, but was deliberately
# left as a `printf | grep -qxF` pipe ("a different mechanism" -- 02-01-PLAN.md
# :42). `grep -q` (any of -x/-F) exits on first match regardless, so a large
# enough VALID_MODELS can SIGPIPE the upstream printf and, under `set -o
# pipefail`, report the pipeline's status as 141 (not grep's 0) -- rejecting a
# perfectly valid --model with a false "unknown --model". Structural, not
# behavioral: reproducing the SIGPIPE race needs a multi-hundred-KB fixture,
# not worth the flakiness here. Mirrors this same herestring-count convention.
R9D_PIPE="$(grep -cF '"$VALID_MODELS" | grep -qxF "$MODEL"' "$BRIDGE")" || R9D_PIPE=0
R9D_HERE="$(grep -cF 'grep -qxF "$MODEL" <<< "$VALID_MODELS"' "$BRIDGE")" || R9D_HERE=0
if [[ "$R9D_PIPE" -eq 0 && "$R9D_HERE" -eq 1 ]]; then
    ok "R9d --model validation uses the SIGPIPE-safe herestring form, not printf|grep (CR-01)"
else
    bad "R9d --model validation uses the SIGPIPE-safe herestring form, not printf|grep (CR-01)" \
        "pipe_form_count=$R9D_PIPE herestring_form_count=$R9D_HERE"
fi

# R9e (WR-02): the fetch block's `_agy_err="$(mktemp ...)"` is a bare
# assignment under `set -euo pipefail` -- if mktemp ever fails (unwritable
# /tmp, misconfigured TMPDIR, disk full), the assignment's own non-zero exit
# terminates the whole script with no diagnostic, unlike every other line in
# this block (mkdir -p ... || true, the tmp-then-mv write, chmod), which
# degrade gracefully. Structural: reproducing a real mktemp failure needs a
# faked-out PATH; the assertion instead pins the guarded shape by name.
R9E_ASSIGN="$(grep -cF '_agy_err="$(mktemp -t agy-models-err.XXXXXX)" || _agy_err=""' "$BRIDGE")" || R9E_ASSIGN=0
R9E_REDIRECT="$(grep -cF '2>"${_agy_err:-/dev/null}"' "$BRIDGE")" || R9E_REDIRECT=0
R9E_RELAY_GUARD="$(grep -cF '[[ -n "$_agy_err" && -s "$_agy_err" ]]' "$BRIDGE")" || R9E_RELAY_GUARD=0
R9E_RM_GUARD="$(grep -cF '[[ -n "$_agy_err" ]] && rm -f "$_agy_err"' "$BRIDGE")" || R9E_RM_GUARD=0
if [[ "$R9E_ASSIGN" -eq 1 && "$R9E_REDIRECT" -eq 1 && "$R9E_RELAY_GUARD" -eq 1 && "$R9E_RM_GUARD" -eq 1 ]]; then
    ok "R9e a failed mktemp for the stderr-capture file degrades gracefully, not aborting the script (WR-02)"
else
    bad "R9e a failed mktemp for the stderr-capture file degrades gracefully, not aborting the script (WR-02)" \
        "assign_guard=$R9E_ASSIGN redirect_guard=$R9E_REDIRECT relay_guard=$R9E_RELAY_GUARD rm_guard=$R9E_RM_GUARD"
fi

# R4: gemini_shim.sh -m flash resolves against the LIVE `agy models` list and
# hands agy a real ID (delegate-agy-62x purge-guard). The map used to hold
# DISPLAY NAMES ("Gemini 3.6 Flash (High)") frozen at whatever agy shipped that
# week; agy's canonical identifier is the id, and a frozen literal of either
# kind goes stale on the next agy release. Any display name or hardcoded id
# reappearing on the wire fails here. Expected id is now derived from the
# captured fixture with the shipped rule, not pinned.
# (Reuses the SH2 FAKE_AGY_DUMP_ARGV harness defined below, in the
# "gemini_shim.sh: no stanza + --sandbox floor" section.)
R4_EXPECT="$(_cc_expect_model flash-high)"
R4_DUMP="$SANDBOX/purge_argv.log"
: > "$R4_DUMP"
rm -f "$HOME/.cache/agy-bridge-models"
FAKE_AGY_DUMP_ARGV="$R4_DUMP" _run OUT RC bash "$SHIM" -m flash -p x
R4_MODEL_VAL="$(awk '/^--model$/{getline; print; exit}' "$R4_DUMP")"
if [[ "$R4_MODEL_VAL" == "$R4_EXPECT" ]]; then
    ok "R4 gemini_shim.sh -m flash resolves to a live agy id, not a display name (purge-guard)"
else
    bad "R4 gemini_shim.sh -m flash resolves to a live agy id, not a display name (purge-guard)" \
        "expected=$R4_EXPECT model=$R4_MODEL_VAL argv=$(cat "$R4_DUMP")"
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

# EC01 (delegate-agy-v5a): the external-kill (137, well inside --timeout)
# plain-text message must never trail off into a dangling separator. Empty
# stderr -> the message ends right after the word "kill"; non-empty stderr
# -> it ends with an exact ": <stderr>" suffix. Both are EXACT-suffix glob
# matches (no trailing `*`), not substring checks -- a substring check would
# pass on a dangling "kill: " just as readily as the defect this pins.
FAKE_AGY_PRINT_KILL9=1 FAKE_AGY_STDERR="" _run OUT RC bash "$BRIDGE" --type code --timeout 60 -- "oom check"
EC01_EMPTY_OK=0
[[ "$RC" -eq 137 && "$OUT" == *"or external kill" ]] && EC01_EMPTY_OK=1
FAKE_AGY_PRINT_KILL9=1 FAKE_AGY_STDERR="boom" _run OUT RC bash "$BRIDGE" --type code --timeout 60 -- "oom check"
EC01_NONEMPTY_OK=0
[[ "$RC" -eq 137 && "$OUT" == *"or external kill: boom" ]] && EC01_NONEMPTY_OK=1
if [[ "$EC01_EMPTY_OK" -eq 1 && "$EC01_NONEMPTY_OK" -eq 1 ]]; then
    ok "EC01 external-kill plain-text message: no dangling separator empty, exact suffix non-empty"
else
    bad "EC01 external-kill plain-text message: no dangling separator empty, exact suffix non-empty" \
        "empty_ok=$EC01_EMPTY_OK nonempty_ok=$EC01_NONEMPTY_OK rc=$RC out=$OUT"
fi

# EC02 (delegate-agy-v5a): the same guard, JSON envelope form. stdout and
# stderr are captured SEPARATELY into files (not via _run's combined 2>&1),
# so the JSON payload is parsed with python3's json module rather than
# substring-matched -- a structurally broken envelope fails the case rather
# than passing on a lucky substring (RB09 precedent).
EC02_OUTF="$SANDBOX/ec02-out.json"
FAKE_AGY_PRINT_KILL9=1 FAKE_AGY_STDERR="" bash "$BRIDGE" --type code --timeout 60 --json -- "oom check" > "$EC02_OUTF" 2>/dev/null
EC02_EMPTY_RC=$?
EC02_EMPTY_ERR="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["error"])' "$EC02_OUTF" 2>/dev/null)" || EC02_EMPTY_ERR="UNPARSEABLE"
EC02_EMPTY_OK=0
[[ "$EC02_EMPTY_RC" -eq 137 && "$EC02_EMPTY_ERR" == *"or external kill" ]] && EC02_EMPTY_OK=1

FAKE_AGY_PRINT_KILL9=1 FAKE_AGY_STDERR="boom" bash "$BRIDGE" --type code --timeout 60 --json -- "oom check" > "$EC02_OUTF" 2>/dev/null
EC02_NONEMPTY_RC=$?
EC02_NONEMPTY_ERR="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["error"])' "$EC02_OUTF" 2>/dev/null)" || EC02_NONEMPTY_ERR="UNPARSEABLE"
EC02_NONEMPTY_OK=0
[[ "$EC02_NONEMPTY_RC" -eq 137 && "$EC02_NONEMPTY_ERR" == *"or external kill: boom" ]] && EC02_NONEMPTY_OK=1

if [[ "$EC02_EMPTY_OK" -eq 1 && "$EC02_NONEMPTY_OK" -eq 1 ]]; then
    ok "EC02 external-kill JSON message: no dangling separator empty, exact suffix non-empty"
else
    bad "EC02 external-kill JSON message: no dangling separator empty, exact suffix non-empty" \
        "empty_ok=$EC02_EMPTY_OK empty_err=$EC02_EMPTY_ERR nonempty_ok=$EC02_NONEMPTY_OK nonempty_err=$EC02_NONEMPTY_ERR"
fi

# EC03 (delegate-agy-v5a, 03-CONTEXT.md D-01): the shim's external-kill branch
# carries the identical dangling-separator defect the bridge had -- the
# box-wide PATH-shadowing entry point, not just the bridge. Guarded with the
# same EC_KILL9_TAIL constant and _err_txt pattern EC01 already proved.
# Byte-identity is asserted directly against the bridge's OWN line (not a
# separately-written expected string) across 4 stderr scenarios -- same
# 60s bound and near-zero DURATION on both scripts, so nothing besides the
# guard shape can make the two lines diverge. Scenario 4 (a printf format
# string) additionally pins T-03-04: agy's stderr must reach neither script's
# printf format string.
EC03_OK=1
EC03_FAIL_DETAIL=""
EC03_LAST_BLINE=""
_ec03_check() {
    # _ec03_check NAME STDERR_VALUE -- sets EC03_LAST_BLINE (bridge's own
    # line) for the T-03-04 format-literal assertion below.
    local _name="$1" _val="$2" _sline
    FAKE_AGY_PRINT_KILL9=1 FAKE_AGY_STDERR="$_val" \
        _run EC03_BOUT EC03_BRC bash "$BRIDGE" --type code --timeout 60 -- "oom check"
    FAKE_AGY_PRINT_KILL9=1 FAKE_AGY_STDERR="$_val" GEMINI_SHIM_TIMEOUT=60 \
        _run EC03_SOUT EC03_SRC bash "$SHIM" -p "oom check"
    EC03_LAST_BLINE="$(printf '%s\n' "$EC03_BOUT" | grep '^ERROR: agy killed' | head -1)"
    _sline="$(printf '%s\n' "$EC03_SOUT" | grep '^ERROR: agy killed' | head -1)"
    if [[ "$EC03_BRC" -eq 137 && "$EC03_SRC" -eq 137 \
          && -n "$EC03_LAST_BLINE" && "$EC03_LAST_BLINE" == "$_sline" ]]; then
        return 0
    fi
    EC03_FAIL_DETAIL="$EC03_FAIL_DETAIL $_name:brc=$EC03_BRC:src=$EC03_SRC:bline=[$EC03_LAST_BLINE]:sline=[$_sline];"
    return 1
}
_ec03_check empty "" || EC03_OK=0
_ec03_check nonempty "boom" || EC03_OK=0
_ec03_check newline-only $'\n\n' || EC03_OK=0
_ec03_check format-specifier '100%s%d' || EC03_OK=0
EC03_FMT_LITERAL_OK=0
[[ "$EC03_LAST_BLINE" == *"100%s%d" ]] && EC03_FMT_LITERAL_OK=1
if [[ "$EC03_OK" -eq 1 && "$EC03_FMT_LITERAL_OK" -eq 1 ]]; then
    ok "EC03 shim external-kill message: byte-identical to the bridge's across 4 stderr scenarios, format-specifier rendered literally"
else
    bad "EC03 shim external-kill message: byte-identical to the bridge's across 4 stderr scenarios, format-specifier rendered literally" \
        "detail=$EC03_FAIL_DETAIL fmt_ok=$EC03_FMT_LITERAL_OK last_bline=[$EC03_LAST_BLINE]"
fi

# EC04 (delegate-agy-v5a, 03-CONTEXT.md D-01/D-03): the bridge's
# GENERIC-nonzero plain-text branch (agy_bridge.sh's `elif [[ "$EXIT_CODE"
# -ne 0 ]]` arm, the mirror of EC01's external-kill arm) carries the same
# unconditional-suffix defect: an exit code with empty stderr must not trail
# off into a bare "exit N: ". The JSON arm at that same branch is a DIFFERENT
# output form (raw stderr, no "ERROR: agy exit N:" context -- see
# 03-02-PLAN.md must_haves.truths) and is deliberately untouched by this
# case and this plan. A 3rd scenario (a printf format string) pins T-03-04
# on this second call site, same as EC03's 4th scenario did on the first.
FAKE_AGY_EXIT=5 FAKE_AGY_STDERR="" _run OUT RC bash "$BRIDGE" --type code -- "generic nonzero"
EC04_EMPTY_OK=0
[[ "$RC" -eq 5 && "$OUT" == *"ERROR: agy exit 5" ]] && EC04_EMPTY_OK=1

FAKE_AGY_EXIT=5 FAKE_AGY_STDERR="boom" _run OUT RC bash "$BRIDGE" --type code -- "generic nonzero"
EC04_NONEMPTY_OK=0
[[ "$RC" -eq 5 && "$OUT" == *"ERROR: agy exit 5: boom" ]] && EC04_NONEMPTY_OK=1

FAKE_AGY_EXIT=5 FAKE_AGY_STDERR='100%s%d' _run OUT RC bash "$BRIDGE" --type code -- "generic nonzero"
EC04_FMT_OK=0
[[ "$RC" -eq 5 && "$OUT" == *"ERROR: agy exit 5: 100%s%d" ]] && EC04_FMT_OK=1

if [[ "$EC04_EMPTY_OK" -eq 1 && "$EC04_NONEMPTY_OK" -eq 1 && "$EC04_FMT_OK" -eq 1 ]]; then
    ok "EC04 bridge generic-nonzero plain-text message: no dangling separator empty, exact suffix non-empty, format-specifier literal"
else
    bad "EC04 bridge generic-nonzero plain-text message: no dangling separator empty, exact suffix non-empty, format-specifier literal" \
        "empty_ok=$EC04_EMPTY_OK nonempty_ok=$EC04_NONEMPTY_OK fmt_ok=$EC04_FMT_OK rc=$RC out=$OUT"
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

# SH15: a degraded (gemini--less) agy models reply must never reach the cache
# file the bridge also reads (D-03, delegate-agy-8ph) -- absent stays absent,
# present stays byte-identical, regardless of the outcome of the call itself.
_SH15_CACHE="$HOME/.cache/agy-bridge-models"
SH15_OK=1
SH15_DETAIL=""

# First half: no cache on disk -- outcome unchanged from SH14 (rc=0, name
# passed through, no warning), and nothing gets created.
rm -f "$_SH15_CACHE"
SH15_DUMP="$SANDBOX/sh15_argv.log"
: > "$SH15_DUMP"
FAKE_AGY_MODELS_GARBAGE=1 FAKE_AGY_DUMP_ARGV="$SH15_DUMP" FAKE_AGY_STDOUT="ok" \
    _run OUT RC bash "$SHIM" -m flash -p x
SH15_ID="$(awk '/^--model$/{getline; print; exit}' "$SH15_DUMP")"
if [[ "$RC" -ne 0 || "$SH15_ID" != "flash" || "$OUT" == *"WARNING"* || -s "$_SH15_CACHE" ]]; then
    SH15_OK=0
    SH15_DETAIL="${SH15_DETAIL}absent-half: rc=$RC model=$SH15_ID cache_exists=$( [[ -s "$_SH15_CACHE" ]] && echo yes || echo no ) out=$OUT; "
fi

# Second half: a good cache already on disk survives a degraded reply
# byte-for-byte -- this is what a poisoned cache would otherwise break.
mkdir -p "$(dirname "$_SH15_CACHE")"
printf '%s\t%s\n' "gemini-3.1-pro-high" "Gemini 3.1 Pro (High)" > "$_SH15_CACHE"
touch -d '2 hours ago' "$_SH15_CACHE"
_SH15_BEFORE="$(cat "$_SH15_CACHE")"
FAKE_AGY_MODELS_GARBAGE=1 FAKE_AGY_STDOUT="ok" _run OUT RC bash "$SHIM" -m flash -p x
_SH15_AFTER="$(cat "$_SH15_CACHE" 2>/dev/null)"
if [[ "$_SH15_AFTER" != "$_SH15_BEFORE" ]]; then
    SH15_OK=0
    SH15_DETAIL="${SH15_DETAIL}preservation-half: before=[$_SH15_BEFORE] after=[$_SH15_AFTER]; "
fi
rm -f "$_SH15_CACHE"

if [[ "$SH15_OK" -eq 1 ]]; then
    ok "SH15 a degraded agy models reply never reaches the cache file, absent or present"
else
    bad "SH15 a degraded agy models reply never reaches the cache file, absent or present" "$SH15_DETAIL"
fi

# SH15b: a degraded (gemini--less) reply with a good stale cache present falls
# back to that cache and completes at rc 0 (D-04), silently -- no new stderr
# line (D-05): this shim shadows `gemini` on PATH, so a warning on this path
# would land in every Octopus/Metaswarm log line. gemini-7.7-flash-high exists
# in no fixture and no other case, so a resolved 7.7 can only have come from
# the cache (SH10's shape). The cache's mtime is left untouched by the
# fallback, so the TTL window is unaffected.
_SH15B_CACHE="$HOME/.cache/agy-bridge-models"
mkdir -p "$(dirname "$_SH15B_CACHE")"
printf '%s\t%s\n' "gemini-7.7-flash-high" "Gemini 7.7 Flash (High)" > "$_SH15B_CACHE"
touch -d '2 hours ago' "$_SH15B_CACHE"
_SH15B_BEFORE="$(cat "$_SH15B_CACHE")"
SH15B_DUMP="$SANDBOX/sh15b_argv.log"
: > "$SH15B_DUMP"
FAKE_AGY_MODELS_GARBAGE=1 FAKE_AGY_DUMP_ARGV="$SH15B_DUMP" FAKE_AGY_STDOUT="ok" \
    _run OUT RC bash "$SHIM" -m flash -p x
SH15B_ID="$(awk '/^--model$/{getline; print; exit}' "$SH15B_DUMP")"
_SH15B_AFTER="$(cat "$_SH15B_CACHE" 2>/dev/null)"
SH15B_OK=1
SH15B_DETAIL=""
[[ "$RC" -eq 0 ]] || { SH15B_OK=0; SH15B_DETAIL="${SH15B_DETAIL}rc=$RC (want 0); "; }
[[ "$SH15B_ID" == "gemini-7.7-flash-high" ]] || { SH15B_OK=0; SH15B_DETAIL="${SH15B_DETAIL}model not resolved from cache, got=$SH15B_ID; "; }
[[ "$OUT" != *"WARNING"* ]] || { SH15B_OK=0; SH15B_DETAIL="${SH15B_DETAIL}unexpected WARNING in out=$OUT; "; }
[[ "$_SH15B_AFTER" == "$_SH15B_BEFORE" ]] || { SH15B_OK=0; SH15B_DETAIL="${SH15B_DETAIL}cache mutated: before=[$_SH15B_BEFORE] after=[$_SH15B_AFTER]; "; }
[[ -n "$(find "$_SH15B_CACHE" -mmin +60 2>/dev/null)" ]] || { SH15B_OK=0; SH15B_DETAIL="${SH15B_DETAIL}cache mtime was refreshed by the fallback; "; }
rm -f "$_SH15B_CACHE"
if [[ "$SH15B_OK" -eq 1 ]]; then
    ok "SH15b a degraded reply falls back to a good stale cache, silently, mtime untouched"
else
    bad "SH15b a degraded reply falls back to a good stale cache, silently, mtime untouched" "$SH15B_DETAIL"
fi

# SH15c: an extra column and a trailing tab both normalize through cut -f1 on
# the REAL fetch path (D-06), through the shim's own fetch -> gate -> normalize
# -> match path -- not merely R9c's proof on the bridge, and not the cache-read
# normalization SH7/SH10 already exercise via a pre-seeded cache. Synthetic
# rows, never added to tests/fixtures/agy-models.tsv (D-14/D-14a): ids below
# appear nowhere else, in different classes so version-sort in one class
# cannot mask the other. Same three lines as R9c, so the two cases read as
# twins. Test-only: no production changes in this task.
SH15C_DIR="$(mktemp -d "$SANDBOX/sh15c.XXXXXX")"
printf '%s\n' \
    "# synthetic SH15c fixture -- not captured evidence, see D-06/D-14a" \
    "$(printf '%s\t%s\t%s' "gemini-9.4-flash-high" "SH15c Flash" "extra-column")" \
    "$(printf '%s\t' "gemini-9.3-pro-high")" \
    > "$SH15C_DIR/agy-models.tsv"
SH15C_OK=1
SH15C_DETAIL=""

rm -f "$_SHIM_CACHE"
SH15C_DUMP="$SANDBOX/sh15c_argv.log"
: > "$SH15C_DUMP"
AGY_FIXTURES_DIR="$SH15C_DIR" FAKE_AGY_DUMP_ARGV="$SH15C_DUMP" FAKE_AGY_STDOUT="ok" \
    _run OUT RC bash "$SHIM" -m flash -p x
SH15C_FLASH="$(awk '/^--model$/{getline; print; exit}' "$SH15C_DUMP")"
if [[ "$RC" -ne 0 || "$SH15C_FLASH" != "gemini-9.4-flash-high" ]]; then
    SH15C_OK=0
    SH15C_DETAIL="${SH15C_DETAIL}extra-column: rc=$RC model=$SH15C_FLASH; "
fi

rm -f "$_SHIM_CACHE"
SH15C_DUMP2="$SANDBOX/sh15c_argv2.log"
: > "$SH15C_DUMP2"
AGY_FIXTURES_DIR="$SH15C_DIR" FAKE_AGY_DUMP_ARGV="$SH15C_DUMP2" FAKE_AGY_STDOUT="ok" \
    _run OUT RC bash "$SHIM" -m pro -p x
SH15C_PRO="$(awk '/^--model$/{getline; print; exit}' "$SH15C_DUMP2")"
if [[ "$RC" -ne 0 || "$SH15C_PRO" != "gemini-9.3-pro-high" ]]; then
    SH15C_OK=0
    SH15C_DETAIL="${SH15C_DETAIL}trailing-tab: rc=$RC model=$SH15C_PRO; "
fi

# The synthetic ids above are well-formed gemini ids, so the write gate lets
# them land in the shared $HOME's cache -- clean up so no later case sees a
# model version that does not exist.
rm -f "$_SHIM_CACHE"
rm -rf "$SH15C_DIR"

if [[ "$SH15C_OK" -eq 1 ]]; then
    ok "SH15c an extra column and a trailing tab both normalize through the real fetch path"
else
    bad "SH15c an extra column and a trailing tab both normalize through the real fetch path" "$SH15C_DETAIL"
fi

# SH15d (WR-01): map_model's "is $m already a live id" check reads the same
# untrusted $LIVE_MODELS as SH15/SH15b's herestring-converted write-gate, but
# was deliberately left as a `printf | grep -qxF` pipe (same "different
# mechanism" carve-out as CR-01's twin on the bridge -- 02-02-PLAN.md:42). A
# SIGPIPE'd printf under `&&` short-circuits to false even when $m IS live,
# producing a spurious "did not resolve" warning for a model that in fact
# resolved. Structural twin of R9d.
SH15D_PIPE="$(grep -cF '"$LIVE_MODELS" | grep -qxF "$m"' "$SHIM")" || SH15D_PIPE=0
SH15D_HERE="$(grep -cF 'grep -qxF "$m" <<< "$LIVE_MODELS"' "$SHIM")" || SH15D_HERE=0
if [[ "$SH15D_PIPE" -eq 0 && "$SH15D_HERE" -eq 1 ]]; then
    ok "SH15d map_model's live-id check uses the SIGPIPE-safe herestring form, not printf|grep (WR-01)"
else
    bad "SH15d map_model's live-id check uses the SIGPIPE-safe herestring form, not printf|grep (WR-01)" \
        "pipe_form_count=$SH15D_PIPE herestring_form_count=$SH15D_HERE"
fi

# IN01 (IN-01): the tmp-then-mv cache write in both scripts leaves the new
# file at process-umask permissions (typically 644) until the chmod 600 two
# lines later runs -- a process killed between mv and chmod, or a concurrent
# reader, sees the file world/group-readable. Low impact (public model IDs),
# so a light structural assertion is enough: the temp-file write must run
# inside a `( umask 077; ... )` subshell in both files, closing the window
# without leaking the stricter umask onto the rest of either script.
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
: > "$RB00B_PPF"; : > "$RB00B_CPF"

echo "== bounded delegation, no bounding binary on PATH (RB04) =="

# The self-kill guard's warning, as it reaches an operator: run_bounded writes it
# to fd 9 (each script's own original stderr). Its presence is how a case tells
# "job control isolated the child" from "it could not", which decides which
# contract the run below is held to.
_RB_GUARD_MSG='has no process group of its own'

# _rb_extract FILE -> the marker-delimited run_bounded block on stdout. RB02
# compares three copies with it (bridge, shim, and tests/contract-check.sh, the
# check's own third consumer of the block, D-03); RB21 and the unit cases below
# source what it produces. Defined here, ahead of its first use, so there is a
# single expression to keep right -- a second copy of this sed is exactly the
# drift RB02 exists to catch, one level up. Anchored at both ends so an
# indented or embedded lookalike line cannot open or close the range.
_rb_extract() {
    sed -n '/^# --- BEGIN run_bounded ---$/,/^# --- END run_bounded ---$/p' "$1"
}

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
    # behind on the developer's box. Then EMPTIED, so the suite's EXIT net has
    # nothing left to re-kill minutes later, when the number may name something
    # else.
    [[ "$ppid" =~ ^[0-9]+$ ]] && kill -KILL "$ppid" 2>/dev/null
    [[ "$cpid" =~ ^[0-9]+$ ]] && kill -KILL "$cpid" 2>/dev/null
    : > "$ppf"; : > "$cpf"
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
_rb_extract "$SHIM" > "$_RB_BLOCK"

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
# IGNORES the signal and has forked a child that ignores it too, interrupted by a
# signal at the shim itself. The relay must reach the same end state the coreutils
# arm reaches for a forwarded signal: forward, escalate to SIGKILL after the same
# kill_after, then return. An unescalated `wait` hangs for as long as the child
# chooses to live -- 300s here, unbounded in the field.
#
# Parameterised over TERM and HUP, and the second one is not symmetry for its own
# sake. The host traps HUP with a handler that CLEANS UP AND DOES NOT EXIT, so a
# HUP that the helper does not relay returns from `wait` as 129, the timer is
# cancelled as if the call had ended normally, and the child is left running with
# nothing bound to it ever again. Measured before the fix, bound 3s + 2s, checked
# 8s later: hup-watchdog left BOTH processes alive while hup-coreutils reaped
# both -- a direct break of the parity this whole phase rests on. SIGQUIT was
# probed the same way, 5x, and does not reproduce (the host's QUIT trap never
# interrupts this wait on this bash), so it is deliberately not covered: the
# relay set is what was demonstrated, not what was imagined.
#
# The bound is set far out of reach (4242s) on purpose: nothing but the relay can
# end this call, so a pass cannot be the watchdog bound firing by luck. The
# assertions that carry the weight are the two PID checks and the elapsed cap, not
# the exit code -- a shim that tore down by some other route would still exit 143.
# The cap is derived, not tuned: kill_after at the delegation site is 5s, so a
# working escalation is done inside ~6s; 15s of polling is 3x that, and the 20s
# elapsed assertion is the one RB04 already uses. The PIDs are required NON-EMPTY
# so a run where the fake never started cannot report both processes "gone".
for _rb22_sig in TERM HUP; do
    # 128 + signum, the conventional status for a process that leaves on that
    # signal, and the one the relay is required to report rather than 124: a
    # caller-interrupted call is not a call the bound killed.
    case "$_rb22_sig" in
        TERM) _rb22_want=143 ;;
        HUP)  _rb22_want=129 ;;
    esac
    RB22_PPF="$SANDBOX/rb22-$_rb22_sig-parent.pid"
    RB22_CPF="$SANDBOX/rb22-$_rb22_sig-child.pid"
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
    kill -"$_rb22_sig" "$RB22_SHIM" 2>/dev/null
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
    # Read AFTER the shim has gone: a signal the helper does not relay lets the
    # entry point exit while the bounded child runs on, which is the failure this
    # arm exists to see.
    sleep 1
    [[ "$RB22_PPID" =~ ^[0-9]+$ ]] && kill -0 "$RB22_PPID" 2>/dev/null && RB22_PARENT_GONE=0
    [[ "$RB22_CPID" =~ ^[0-9]+$ ]] && kill -0 "$RB22_CPID" 2>/dev/null && RB22_CHILD_GONE=0
    _RB22_SLEEPERS="$(_rb_sleepers)"
    if [[ "$RB22_EXITED" -eq 1 && "$RB22_RC" -eq "$_rb22_want" && "$_RB22_ELAPSED" -lt 20 \
          && "$RB22_PPID" =~ ^[0-9]+$ && "$RB22_CPID" =~ ^[0-9]+$ \
          && "$RB22_PARENT_GONE" -eq 1 && "$RB22_CHILD_GONE" -eq 1 \
          && "$_RB22_SLEEPERS" -eq 0 ]]; then
        ok "RB22 a relayed SIG$_rb22_sig escalates to SIGKILL and returns $_rb22_want instead of leaving the child running"
    else
        bad "RB22 a relayed SIG$_rb22_sig escalates to SIGKILL and returns $_rb22_want instead of leaving the child running" \
            "exited=$RB22_EXITED rc=$RB22_RC(want $_rb22_want) elapsed=${_RB22_ELAPSED}s parent=$RB22_PPID parent_gone=$RB22_PARENT_GONE child=$RB22_CPID child_gone=$RB22_CHILD_GONE sleepers=$_RB22_SLEEPERS"
    fi
    # Only on the failure path, and disowned first: killing a job still in the
    # table makes bash print a "Killed" notice on the suite's own stdout, which is
    # noise rather than a result. On the passing path `wait` above reaped it.
    if [[ "$RB22_EXITED" -eq 0 ]]; then
        disown "$RB22_SHIM" 2>/dev/null || true
        kill -KILL "$RB22_SHIM" 2>/dev/null
    fi
    kill -KILL "$RB22_PPID" 2>/dev/null
    kill -KILL "$RB22_CPID" 2>/dev/null
    # Emptied, not just reaped: the suite's EXIT cleanup re-kills every recorded
    # pid, and a pid recorded minutes earlier may belong to something else by then.
    : > "$RB22_PPF"; : > "$RB22_CPF"
    _rb_reap_sentinels
done

echo "== the bounded child inherits none of our descriptors (RB23) =="

# RB23: fd 9 is the helper's own diagnostic descriptor -- each entry point's
# ORIGINAL stderr -- and it must never reach the bounded command. Under the
# commonest capture shape for a CLI that shadows `gemini` box-wide,
# `out=$(gemini ... 2>&1)`, that descriptor IS the caller's capture pipe: any
# descendant agy leaves behind holds the pipe open, so `$( )` never reaches EOF
# and never returns -- on a run that exited 0 in under a second. Nothing timed
# out; the run SUCCEEDED and the caller hangs anyway.
#
# Driven through a real capturing caller rather than by reading the child's
# /proc/self/fd, and that choice is the case. This suite already met this
# mechanism once and moved ITSELF to file capture for it (RB05's note, and the
# fake's own child stdio) -- the shipped scripts never got the fix, so a case
# that pins the harness's defence proves nothing about a caller's. This one
# fails the way a caller fails.
#
# Both arms, because the descriptor survives the bound rather than being freed
# by it: the coreutils binary leaks it exactly as the watchdog does.
#
# The leak's lifetime is what bounds a red run: a regression fails in ~12s per
# arm instead of hanging the suite for the fake's usual 300s. The elapsed cap
# separates "the entry point returned" from "the pipe finally drained", and
# asserting the leaked child was ALIVE when the capture returned is what stops a
# fixture that forked nothing from passing vacuously.
RB23_CPF="$SANDBOX/rb23-child.pid"
RB23_LEAK=12
RB23_OK=1
RB23_DETAIL=""
for _rb23_mech in watchdog coreutils; do
    rm -f "$RB23_CPF"
    if [[ "$_rb23_mech" == "watchdog" ]]; then _rb23_path="$(_purebin)"; else _rb23_path="$PATH"; fi
    _RB23_START=$(date +%s)
    RB23_OUT="$(PATH="$_rb23_path" FAKE_AGY_LEAK_CHILD="$RB23_LEAK" \
        FAKE_AGY_CHILD_PID_FILE="$RB23_CPF" FAKE_AGY_STDOUT="RB23-reply" \
        "$_TIMEOUT_NET" --foreground -k 5 30 bash "$SHIM" -p "do a thing" 2>&1)"
    RB23_RC=$?
    _RB23_ELAPSED=$(( $(date +%s) - _RB23_START ))
    RB23_CPID="$(cat "$RB23_CPF" 2>/dev/null)" || RB23_CPID=""
    RB23_CALIVE=0
    [[ "$RB23_CPID" =~ ^[0-9]+$ ]] && kill -0 "$RB23_CPID" 2>/dev/null && RB23_CALIVE=1
    [[ "$RB23_RC" -eq 0 && "$RB23_OUT" == *"RB23-reply"* ]] \
        || { RB23_OK=0; RB23_DETAIL="$RB23_DETAIL $_rb23_mech:no_successful_run(rc=$RB23_RC out=${RB23_OUT:0:120})"; }
    [[ "$RB23_CALIVE" -eq 1 ]] \
        || { RB23_OK=0; RB23_DETAIL="$RB23_DETAIL $_rb23_mech:nothing_leaked(child='$RB23_CPID')"; }
    [[ "$_RB23_ELAPSED" -lt 10 ]] \
        || { RB23_OK=0; RB23_DETAIL="$RB23_DETAIL $_rb23_mech:capture_held_open(${_RB23_ELAPSED}s)"; }
    [[ "$RB23_CPID" =~ ^[0-9]+$ ]] && kill -KILL "$RB23_CPID" 2>/dev/null
    : > "$RB23_CPF"
done
if [[ "$RB23_OK" -eq 1 ]]; then
    ok "RB23 a capturing caller is not held open by a descendant of the bounded call, on either mechanism"
else
    bad "RB23 a capturing caller is not held open by a descendant of the bounded call, on either mechanism" \
        "detail=$RB23_DETAIL"
fi

echo "== the helper gives the host's traps back (RB24) =="

# RB24: `trap -` resets a signal to its DEFAULT disposition; it does not restore
# whatever the host had installed. Both entry points install their cleanup trap
# before the first bounded call, so on the watchdog arm that first call was
# permanently deleting the host's TERM and INT handlers -- measured
# `after TERM: []`, with the coreutils arm as the control that keeps them.
#
# The consequence is not untidiness. Bash runs no EXIT trap for a process killed
# by an uncaught signal, so from the stdin read onward a Ctrl-C left
# /tmp/gemini-shim.XXXXXX/GEMINI.md -- the full user prompt -- on disk, and
# repeated interrupted runs accumulate prompt-bearing temp dirs. The bridge's
# window is wider still.
#
# Asserted at the block rather than end to end, and the ceiling is stated rather
# than hidden: reaching the /tmp consequence needs a signal delivered in the few
# milliseconds BETWEEN two bounded calls, which is a race no assertion can drive
# deterministically. What is deterministic is the trap table the consequence
# follows from, so that is what is pinned -- byte-identical before and after,
# for every signal the helper touches, on both mechanisms. This is the assertion
# whose absence let the defect ship.
#
# HUP is in the set because the relay now takes it (RB22): a signal the helper
# borrows is a signal it must hand back.
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
    ' _ "$_RB_BLOCK" "$_rb24_bin" > "$RB24_OUT" 2>&1 || {
        RB24_OK=0; RB24_DETAIL="$RB24_DETAIL $_rb24_mech:driver_failed"; }
    for _rb24_s in TERM INT HUP; do
        _rb24_b="$(grep "^before $_rb24_s " "$RB24_OUT")" || _rb24_b=""
        _rb24_a="$(grep "^after $_rb24_s " "$RB24_OUT")" || _rb24_a=""
        # The host trap must have been THERE to begin with, or "unchanged" is a
        # statement about nothing.
        [[ "$_rb24_b" == *"HOST_CLEANUP_RAN"* ]] \
            || { RB24_OK=0; RB24_DETAIL="$RB24_DETAIL $_rb24_mech:$_rb24_s:not_installed"; }
        [[ "${_rb24_b#before }" == "${_rb24_a#after }" ]] \
            || { RB24_OK=0; RB24_DETAIL="$RB24_DETAIL $_rb24_mech:$_rb24_s:destroyed[${_rb24_a:0:60}]"; }
    done
done
if [[ "$RB24_OK" -eq 1 ]]; then
    ok "RB24 (unit) a bounded call leaves the host's TERM, INT and HUP traps exactly as it found them, on both mechanisms"
else
    bad "RB24 (unit) a bounded call leaves the host's TERM, INT and HUP traps exactly as it found them, on both mechanisms" \
        "detail=$RB24_DETAIL"
fi

echo "== the pgid lookup depends on nothing (RB25, RB26) =="

# RB25 and RB26 both aim at `_rb_pgid_of`, from the two directions the suite
# could not see it from: the tools it shells out to, and the file it parses.
#
# The blind spot was structural, not accidental. _PUREBIN_TOOLS hardcodes awk
# and ps into the sanitized PATH -- correctly, as documentation of the real
# dependency set -- so no case could ever ask what happens without them.

# A second sanitized bin dir: everything _purebin resolves EXCEPT the two
# binaries the pgid lookup used to shell out to. Built by subtraction from
# _purebin rather than by a second explicit list, so it cannot drift from it and
# so a case that fails here fails for the missing binaries and nothing else.
_PUREBIN_NOAWK=""
_purebin_noawk() {
    if [[ -n "$_PUREBIN_NOAWK" ]]; then printf '%s' "$_PUREBIN_NOAWK"; return 0; fi
    local d
    d="$(mktemp -d "$SANDBOX/purebin-noawk.XXXXXX")"
    cp -a "$(_purebin)/." "$d/"
    rm -f "$d/awk" "$d/ps"
    _PUREBIN_NOAWK="$d"
    printf '%s' "$d"
}

# RB25: with neither awk nor ps resolvable, the lookup returned empty, kill_pgid
# stayed empty, and the escalation degraded to a pid-only kill -- so the bound
# still fired, still reported 124, and everything agy had forked survived it.
# Silent by construction: the operator's only signal is the guard's warning, and
# four of the six bounded sites have already redirected the stream it would land
# on. The shim installs at ~/.local/bin/gemini and is reached from systemd units,
# `env -i` wrappers, container entrypoints and CI runners -- the contexts its own
# ${HOME:-} comment names as the ones it must survive -- where a PATH this thin
# is ordinary.
#
# The guard's warning is asserted ABSENT rather than passed to
# _rb_assert_reaped: that helper treats the warning as the documented D-14a
# degradation and stops claiming the descendant kill, which is exactly the
# branch this case must refuse. A degradation caused by a missing binary is not
# a host whose job control could not isolate the child.
RB25_PPF="$SANDBOX/rb25-parent.pid"
RB25_CPF="$SANDBOX/rb25-child.pid"
RB25_FD9="$SANDBOX/rb25-fd9.log"
RB25_OUT="$SANDBOX/rb25-out.log"
rm -f "$RB25_PPF" "$RB25_CPF"; : > "$RB25_FD9"; : > "$RB25_OUT"
_RB25_BIN="$(_purebin_noawk)"
FAKE_AGY_FORK_HANG=1 FAKE_AGY_PID_FILE="$RB25_PPF" FAKE_AGY_CHILD_PID_FILE="$RB25_CPF" \
    "$_TIMEOUT_NET" --foreground -k 5 30 env "PATH=$_RB25_BIN" bash -c '
    set -euo pipefail
    exec 9>"$2"
    TIMEOUT_BIN=""
    . "$1"
    rc=0
    run_bounded 3 2 -- bash "$3" --print x || rc=$?
    printf "%s\n" "$rc"
' _ "$_RB_BLOCK" "$RB25_FD9" "$HERE/fake-agy.sh" > "$RB25_OUT" 2>&1
RB25_SEEN="$(cat "$RB25_OUT" 2>/dev/null)"
RB25_PPID="$(cat "$RB25_PPF" 2>/dev/null)" || RB25_PPID=""
RB25_CPID="$(cat "$RB25_CPF" 2>/dev/null)" || RB25_CPID=""
RB25_PGONE=1; RB25_CGONE=1
[[ "$RB25_PPID" =~ ^[0-9]+$ ]] && kill -0 "$RB25_PPID" 2>/dev/null && RB25_PGONE=0
[[ "$RB25_CPID" =~ ^[0-9]+$ ]] && kill -0 "$RB25_CPID" 2>/dev/null && RB25_CGONE=0
RB25_OK=1
RB25_DETAIL=""
[[ "$RB25_SEEN" == "124" ]] || { RB25_OK=0; RB25_DETAIL="$RB25_DETAIL rc='$RB25_SEEN'(want 124)"; }
[[ "$RB25_PPID" =~ ^[0-9]+$ && "$RB25_CPID" =~ ^[0-9]+$ ]] \
    || { RB25_OK=0; RB25_DETAIL="$RB25_DETAIL fake_never_started(parent='$RB25_PPID' child='$RB25_CPID')"; }
[[ "$RB25_PGONE" -eq 1 ]] || { RB25_OK=0; RB25_DETAIL="$RB25_DETAIL direct_process_survived($RB25_PPID)"; }
[[ "$RB25_CGONE" -eq 1 ]] || { RB25_OK=0; RB25_DETAIL="$RB25_DETAIL descendant_survived($RB25_CPID)"; }
grep -qF "$_RB_GUARD_MSG" "$RB25_FD9" \
    && { RB25_OK=0; RB25_DETAIL="$RB25_DETAIL degraded_to_pid_only"; }
if [[ "$RB25_OK" -eq 1 ]]; then
    ok "RB25 (unit) on a PATH with neither awk nor ps, the bound still reaps agy AND its fork, with no degradation"
else
    bad "RB25 (unit) on a PATH with neither awk nor ps, the bound still reaps agy AND its fork, with no degradation" \
        "detail=$RB25_DETAIL fd9=$(head -c 200 "$RB25_FD9")"
fi
[[ "$RB25_PPID" =~ ^[0-9]+$ ]] && kill -KILL "$RB25_PPID" 2>/dev/null
[[ "$RB25_CPID" =~ ^[0-9]+$ ]] && kill -KILL "$RB25_CPID" 2>/dev/null
: > "$RB25_PPF"; : > "$RB25_CPF"

# RB26: /proc/<pid>/stat is `pid (comm) state ppid pgrp ...` and comm may contain
# BOTH spaces and `)`. Whitespace-splitting to field 5 is the pgrp only for a
# single-token comm; for a two-word comm it is the PPID -- a number, so it
# survives the digit sanitiser, differs from our own group, and is installed as
# kill_pgid. The ladder then sends TERM and then KILL to `-<ppid>`: a real
# process group, belonging to something else. `_rb_signal`'s failure-tolerant
# suffix swallows the outcome either way.
#
# Measured on this host, one process per shape:
#   comm='a b'    field5=1046709 (the PPID)  true pgid=1046698
#   comm='a b c'  field5=S -> sanitises to empty (fails closed, no kill at all)
#   comm='a)b c'  field5=1046709 (the PPID)
#
# Not reachable from the shipped call sites, whose commands are `agy` and `cat`;
# reachable the moment anything else is bounded, which is why it is pinned here
# rather than left to the next caller to discover.
#
# Asserted against `ps -o pgid=` as ground truth, so the case means the same
# thing on a host with no procfs (where the helper's own fallback IS ps, and the
# agreement is trivial). The ppid != pgid precondition is the anti-vacuity half:
# where they coincide, the broken parse would agree by accident.
RB26_DIR="$SANDBOX/rb26"
RB26_OUT="$SANDBOX/rb26-out.log"
rm -rf "$RB26_DIR"; mkdir -p "$RB26_DIR"; : > "$RB26_OUT"
RB26_OK=1
RB26_DETAIL=""
_rb26_sleep="$(command -v sleep 2>/dev/null)" || _rb26_sleep=""
if [[ -z "$_rb26_sleep" ]]; then
    bad "RB26 (unit) the pgid of a process whose comm contains whitespace is read correctly" "no sleep binary to copy"
else
    for _rb26_comm in "a b" "a b c" "a)b c"; do
        cp "$_rb26_sleep" "$RB26_DIR/$_rb26_comm"
        : > "$RB26_OUT"
        bash -c '
            set -euo pipefail
            exec 9>/dev/null
            TIMEOUT_BIN=""
            . "$1"
            ( exec "$2" 5 ) &
            p=$!
            sleep 0.5
            saw="$(_rb_pgid_of "$p")"
            pgid="$(ps -o pgid= -p "$p" 2>/dev/null | tr -cd "[:digit:]")" || pgid=""
            ppid="$(ps -o ppid= -p "$p" 2>/dev/null | tr -cd "[:digit:]")" || ppid=""
            printf "%s %s %s\n" "${saw:-EMPTY}" "${pgid:-EMPTY}" "${ppid:-EMPTY}"
            kill -KILL "$p" 2>/dev/null || true
        ' _ "$_RB_BLOCK" "$RB26_DIR/$_rb26_comm" > "$RB26_OUT" 2>&1 \
            || { RB26_OK=0; RB26_DETAIL="$RB26_DETAIL [$_rb26_comm]driver_failed"; }
        read -r _rb26_saw _rb26_pgid _rb26_ppid < "$RB26_OUT"
        [[ "$_rb26_pgid" =~ ^[0-9]+$ && "$_rb26_ppid" =~ ^[0-9]+$ && "$_rb26_ppid" != "$_rb26_pgid" ]] \
            || { RB26_OK=0; RB26_DETAIL="$RB26_DETAIL [$_rb26_comm]cannot_discriminate(pgid=$_rb26_pgid ppid=$_rb26_ppid)"; }
        [[ "$_rb26_saw" == "$_rb26_pgid" ]] \
            || { RB26_OK=0; RB26_DETAIL="$RB26_DETAIL [$_rb26_comm]saw=$_rb26_saw(want $_rb26_pgid, ppid=$_rb26_ppid)"; }
    done
    if [[ "$RB26_OK" -eq 1 ]]; then
        ok "RB26 (unit) the pgid of a process whose comm contains whitespace is read correctly"
    else
        bad "RB26 (unit) the pgid of a process whose comm contains whitespace is read correctly" \
            "detail=$RB26_DETAIL"
    fi
fi
rm -rf "$RB26_DIR"

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
# Known ceiling: a segment that merely MENTIONS the variable outside a
# run_bounded call -- printing it in a diagnostic, say -- is reported as a
# violation. That is deliberate rather than an oversight; separating "invokes"
# from "mentions" needs a shell parser, and the cheap approximation errs toward
# failing loudly. Second ceiling, stated for the same reason: a second
# occurrence inside one bounded segment (`run_bounded 5 2 -- "$AGY_BIN"
# "$AGY_BIN"`) counts as bounded, which it is.

# Comment-only lines dropped first (a comment naming the variable is neither an
# occurrence nor a violation), then backslash-continued lines joined into one
# logical line each -- which _rb_agy_segments below then splits back apart at
# the command separators, so the unit of judgement is a command and not a line. The join is load-bearing, not tidiness: the bridge's
# delegation call puts `run_bounded` on one physical line and the invocation on
# the next, so a per-physical-line scan reports a false violation -- and the
# cheapest way to silence a false violation is to invent the allowlist this case
# forbids.
_rb_logical_lines() {
    sed -e 's/[[:space:]]*$//' "$1" \
        | grep -v '^[[:space:]]*#' \
        | sed -e :a -e '/\\$/{N; s/\\\n[[:space:]]*/ /; ta' -e '}'
}

# _rb_agy_segments FILE -> one COMMAND per line. Logical lines first, then split
# at the separators that end a command (`;`, `|`, `&`, and so `&&`/`||` too),
# then the leading noise stripped off what remains until a command word is at
# the front: a grouping paren, a control keyword, an assignment prefix, a
# command substitution's `$(`.
#
# The split is what makes the scan count OCCURRENCES rather than LINES. Per
# line, `run_bounded 5 2 -- "$AGY_BIN" foo; "$AGY_BIN" --version` reads as
# bounded, because one match anywhere on the line satisfied the bounded regex
# for every occurrence on it. Per command it reads as one bounded call and one
# violation, which is what it is.
#
# The strip is what closes the other half. Anchoring `run_bounded` at the front
# of a command means a decoy -- `echo "run_bounded x -- $AGY_BIN"` -- can no
# longer launder an expansion by quoting the words of a call, while the shipped
# sites keep passing: they sit behind `raw=$(`, `if _agy_models=$(` and
# `( cd "$WORK_DIR" && `, each of which the strip removes. `tr`, not a sed
# newline escape, because BSD sed does not read `\n` in a replacement and this
# suite must mean the same thing on the platform the fallback exists for.
_rb_agy_segments() {
    _rb_logical_lines "$1" \
        | tr ';|&' '\n\n\n' \
        | sed -E -e :a \
            -e 's/^[[:space:]]*(if|then|elif|while|until|do|!|\{|\(|\$\(|[A-Za-z_][A-Za-z0-9_]*=)//' \
            -e ta \
            -e 's/^[[:space:]]+//'
}

# _rb_agy_scan FILE -> "<violations> <occurrences>". An occurrence is any
# expansion of AGY_BIN in any form -- "$AGY_BIN", "${AGY_BIN}", or bare
# $AGY_BIN. Matching only the doubly-quoted form would let a brace or an
# unquoted rewrite walk straight past a scan that still reported zero
# violations, which is the one way this case could fail silently. The
# assignment line (`AGY_BIN=...`) carries no `$` and is not an occurrence.
# Counted with `grep -o`, so two expansions in one command are two occurrences.
_rb_agy_scan() {
    local segs occ viol
    segs="$(_rb_agy_segments "$1")"
    occ="$(printf '%s\n' "$segs" | grep -oE '\$\{?AGY_BIN\}?' | grep -c '')" || occ=0
    viol="$(printf '%s\n' "$segs" | grep -vE '^run_bounded[[:space:]].*[[:space:]]--([[:space:]]|$)' \
            | grep -oE '\$\{?AGY_BIN\}?' | grep -c '')" || viol=0
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
        RB01_DETAIL="$RB01_DETAIL[$(_rb_agy_segments "$_rb01_f" \
            | grep -vE '^run_bounded[[:space:]].*[[:space:]]--([[:space:]]|$)' \
            | grep -E '\$\{?AGY_BIN\}?' | head -3 | tr '\n' ';')]"
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

# RB01m: the scan is proven capable of failing before it is trusted. Copies of
# the shim each gain one line -- on a path no test drives, which is the whole
# point -- and the SAME helper must report it, or must not. A scan never shown
# to fail is a scan that passes forever.
#
# The last two shapes are the ones that walked past the per-LINE version of this
# scan. A line was counted violating or not; two occurrences on one logical
# line, one bounded and one not, made the whole line look bounded, and a decoy
# string that merely CONTAINED `run_bounded ... --` made an unbounded expansion
# look like an argument. Both reported zero violations against a shim carrying a
# live unbounded call. RB01's stated ceiling claims it "errs toward failing
# loudly"; these two erred the other way, which is the one direction an
# enforcement mechanism must not err in.
RB01M_DIR="$SANDBOX/rb01m"
rm -rf "$RB01M_DIR"; mkdir -p "$RB01M_DIR"
RB01M_OK=1
RB01M_DETAIL=""
# _rb01m_probe NAME WANT_VIOLATION APPENDED_LINE
_rb01m_probe() {
    local name="$1" want="$2" line="$3" v o
    cp "$SHIM" "$RB01M_DIR/$name.sh"
    printf '%s\n' "$line" >> "$RB01M_DIR/$name.sh"
    read -r v o <<<"$(_rb_agy_scan "$RB01M_DIR/$name.sh")"
    # The occurrence floor is asserted on every probe, not just the clean ones:
    # a scan that matched nothing at all would report zero violations too.
    [[ "$o" -ge 1 ]] || { RB01M_OK=0; RB01M_DETAIL="$RB01M_DETAIL $name:no_occurrences"; }
    if [[ "$want" -eq 1 ]]; then
        [[ "$v" -ge 1 ]] || { RB01M_OK=0; RB01M_DETAIL="$RB01M_DETAIL $name:missed(${v}/${o})"; }
    else
        [[ "$v" -eq 0 ]] || { RB01M_OK=0; RB01M_DETAIL="$RB01M_DETAIL $name:false_positive(${v}/${o})"; }
    fi
}
_rb01m_probe mutated   1 'if [[ "${RB01M_NEVER:-0}" == "1" ]]; then "$AGY_BIN" --version; fi'
_rb01m_probe commented 0 '# a comment mentioning "$AGY_BIN" is not a call site'
_rb01m_probe twoonone  1 'run_bounded 5 2 -- "$AGY_BIN" foo; "$AGY_BIN" --version'
_rb01m_probe decoy     1 'echo "run_bounded x -- $AGY_BIN"'
if [[ "$RB01M_OK" -eq 1 ]]; then
    ok "RB01m the scan reports every injected unbounded call site, including a second one on a bounded line and a decoy string, and ignores a comment"
else
    bad "RB01m the scan reports every injected unbounded call site, including a second one on a bounded line and a decoy string, and ignores a comment" \
        "detail=$RB01M_DETAIL"
fi
rm -rf "$RB01M_DIR"

echo "== the helper is one artifact in three files (RB02) =="

# RB02: run_bounded is duplicated verbatim into both shipped scripts on purpose
# -- each is installed as a standalone launcher and neither may source the
# other -- so the copies are one artifact living in multiple files. Three
# defects were found inside that helper AFTER it was first written; the hazard
# this case guards is the fourth being fixed in one copy and not the others,
# which nothing else in the suite would notice. Same one-sided-fix hazard
# delegate-agy-8ph names for the two model-cache writers. (_rb_extract itself
# is defined once, up at RB04.)
#
# tests/contract-check.sh (Phase 1.5, D-03) is a third consumer of the same
# block: the check bounds agy by exactly the mechanism it audits. It is a
# test-side artifact, not a shipped standalone launcher, but it still cannot
# source the block -- sourcing would cost gemini_shim.sh its standalone
# property, the reason D-08 chose duplication in the first place -- so it
# carries its own verbatim copy too, and this case widens to compare all three.

RB02_B="$(_rb_extract "$BRIDGE")"
RB02_S="$(_rb_extract "$SHIM")"
RB02_C="$(_rb_extract "$CONTRACT_CHECK")"
# All three ranges must be non-empty AND must actually contain the definition,
# so any absent or truncated block cannot pass trivially by all being nothing.
if [[ -n "$RB02_B" && -n "$RB02_S" && -n "$RB02_C" \
      && "$RB02_B" == *"run_bounded() {"* && "$RB02_S" == *"run_bounded() {"* \
      && "$RB02_C" == *"run_bounded() {"* \
      && "$RB02_B" == "$RB02_S" && "$RB02_S" == "$RB02_C" ]]; then
    ok "RB02 the three run_bounded blocks (bridge, shim, contract-check) are byte-identical and non-empty"
else
    RB02_WHICH=""
    [[ "$RB02_B" != "$RB02_S" ]] && RB02_WHICH="$RB02_WHICH bridge!=shim"
    [[ "$RB02_S" != "$RB02_C" ]] && RB02_WHICH="$RB02_WHICH shim!=contract-check"
    [[ "$RB02_B" != "$RB02_C" ]] && RB02_WHICH="$RB02_WHICH bridge!=contract-check"
    bad "RB02 the three run_bounded blocks (bridge, shim, contract-check) are byte-identical and non-empty" \
        "bridge_lines=$(printf '%s' "$RB02_B" | grep -c '' ) shim_lines=$(printf '%s' "$RB02_S" | grep -c '') cc_lines=$(printf '%s' "$RB02_C" | grep -c '') mismatched=$RB02_WHICH diff=$(diff <(printf '%s\n' "$RB02_B") <(printf '%s\n' "$RB02_S") | head -6 | tr '\n' ';')"
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

# EC05 (delegate-agy-6q1, D-11): EC_KILL9_TAIL -- the tail literal EC01/EC03
# pin as shared byte-for-byte between the bridge's and the shim's
# external-kill messages -- is defined exactly ONCE per script (comment lines
# filtered, RB03 precedent above) and quoted VERBATIM in README's exit-137
# row. This is the exact seam that let delegate-agy-6q1 happen: code moved,
# docs didn't. Assignment count is exactly 1, not "at least one" (Codex LOW,
# accepted) -- a second definition trips this even where every reference
# still resolves; the reference count is asserted separately (>=1) so a
# refactor that adds a second USE does not.
_EC_KILL9_LITERAL=' -- possible OOM or external kill'

EC05_OK=1
EC05_DETAIL=""
for _ec05_f in "$BRIDGE" "$SHIM"; do
    _ec05_defs="$(grep -v '^[[:space:]]*#' "$_ec05_f" | grep -cF "EC_KILL9_TAIL='$_EC_KILL9_LITERAL'")" || _ec05_defs=0
    [[ "$_ec05_defs" -eq 1 ]] || { EC05_OK=0; EC05_DETAIL="$EC05_DETAIL ${_ec05_f##*/}:defines_${_ec05_defs}"; }
    _ec05_refs="$(grep -cE '\$EC_KILL9_TAIL|\$\{EC_KILL9_TAIL' "$_ec05_f")" || _ec05_refs=0
    [[ "$_ec05_refs" -ge 1 ]] || { EC05_OK=0; EC05_DETAIL="$EC05_DETAIL ${_ec05_f##*/}:refs_${_ec05_refs}"; }
done
grep -qF "$_EC_KILL9_LITERAL" "$_RB_README" || { EC05_OK=0; EC05_DETAIL="$EC05_DETAIL readme:literal_missing"; }
if [[ "$EC05_OK" -eq 1 ]]; then
    ok "EC05 EC_KILL9_TAIL defined exactly once per script, referenced, and quoted verbatim in README"
else
    bad "EC05 EC_KILL9_TAIL defined exactly once per script, referenced, and quoted verbatim in README" \
        "detail=$EC05_DETAIL"
fi

echo "== the docs are held to the captured evidence (CC05) =="

# CC05: README's dated --model fact is a claim about the model list captured in
# tests/fixtures/agy-models.tsv, so that fixture's header is the evidence the
# document is pinned against. RB03 (above) is the shape copied here: expected
# bytes are written HERE, not extracted from one file and grepped for in the
# other -- extracting a string from a file and then searching that same file
# for it is a tautology that passes whatever the string becomes. This case is
# the seam between the captured evidence and the document quoting it.
_CC_AGY_VERSION='1.1.13'
_CC_CAPTURE_DATE='2026-08-20'
# The pre-phase troubleshooting advice task 1 removed, pinned as an absence.
_CC_DEAD_EXACT_STRING='exact string required'
# The one fixture README's dated fact is pinned against -- not every fixture
# under tests/fixtures/ (F8, review round; see below).
_CC_PINNED_FIXTURE="$HERE/fixtures/agy-models.tsv"
# The required-fixture manifest: files that must exist and carry a well-formed
# provenance header. tests/fixtures/empty-success.txt is deliberately absent --
# D-11 makes it conditional on the headless permission gate actually firing
# during a real run, and a fixture that may legitimately not exist cannot be
# required to.
_CC_REQUIRED_FIXTURES=(
    "$HERE/fixtures/agy-version.txt"
    "$HERE/fixtures/agy-models.tsv"
    "$HERE/fixtures/invalid-model.txt"
)

CC05_OK=1
CC05_DETAIL=""

# Non-vacuity (RB01's occurrence-floor discipline, applied to an explicit list
# instead of a scan): a manifest with fewer than three entries would clear
# every per-file assertion below by vacuous iteration and report success for
# the wrong reason.
[[ "${#_CC_REQUIRED_FIXTURES[@]}" -ge 3 ]] \
    || { CC05_OK=0; CC05_DETAIL="$CC05_DETAIL manifest_too_short(${#_CC_REQUIRED_FIXTURES[@]})"; }

# Two assertions of different strengths, deliberately (F8). README's dated fact
# is a claim about what --model accepts, and the captured model list is its
# evidence -- so equality is pinned against _CC_PINNED_FIXTURE alone. The other
# required fixtures are captured by different probes across different plans and
# may legitimately be recaptured independently (a retry, an exhausted quota, an
# agy version bump mid-phase); a rule that turns a truthful partial recapture
# red would teach the next contributor to hand-edit a provenance stamp, which is
# the one thing this case exists to prevent. So those get a header SHAPE
# assertion only, no cross-file equality.

# Equality, over _CC_PINNED_FIXTURE and README only.
[[ -f "$_CC_PINNED_FIXTURE" ]] \
    || { CC05_OK=0; CC05_DETAIL="$CC05_DETAIL ${_CC_PINNED_FIXTURE##*/}:missing"; }
[[ "$(grep -cF "# agy-version: $_CC_AGY_VERSION" "$_CC_PINNED_FIXTURE" 2>/dev/null)" -eq 1 ]] \
    || { CC05_OK=0; CC05_DETAIL="$CC05_DETAIL ${_CC_PINNED_FIXTURE##*/}:version_mismatch"; }
[[ "$(grep -cF "# captured: $_CC_CAPTURE_DATE" "$_CC_PINNED_FIXTURE" 2>/dev/null)" -eq 1 ]] \
    || { CC05_OK=0; CC05_DETAIL="$CC05_DETAIL ${_CC_PINNED_FIXTURE##*/}:date_mismatch"; }
grep -qF "$_CC_AGY_VERSION" "$_RB_README" \
    || { CC05_OK=0; CC05_DETAIL="$CC05_DETAIL readme:version_missing"; }
grep -qF "$_CC_CAPTURE_DATE" "$_RB_README" \
    || { CC05_OK=0; CC05_DETAIL="$CC05_DETAIL readme:date_missing"; }

# Shape, over every entry in _CC_REQUIRED_FIXTURES: must exist (checked first,
# so a manifest whose files are all missing cannot pass this loop vacuously)
# and carry exactly one well-formed line of each provenance field. No
# cross-file equality -- a probe may legitimately be re-run alone, and this is
# the F8 fix.
for _cc05_f in "${_CC_REQUIRED_FIXTURES[@]}"; do
    if [[ ! -f "$_cc05_f" ]]; then
        CC05_OK=0
        CC05_DETAIL="$CC05_DETAIL ${_cc05_f##*/}:missing"
        continue
    fi
    [[ "$(grep -cE '^# agy-version: .+' "$_cc05_f")" -eq 1 ]] \
        || { CC05_OK=0; CC05_DETAIL="$CC05_DETAIL ${_cc05_f##*/}:no_version_header"; }
    [[ "$(grep -cE '^# captured: [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$_cc05_f")" -eq 1 ]] \
        || { CC05_OK=0; CC05_DETAIL="$CC05_DETAIL ${_cc05_f##*/}:no_captured_header"; }
done

# Negative half (RB03's own precedent, above: "equally load-bearing"). Every
# other assertion here is positive, so a stale sentence reintroduced beside a
# correct one would keep the suite green.
grep -qiF "$_CC_DEAD_EXACT_STRING" "$_RB_README" \
    && { CC05_OK=0; CC05_DETAIL="$CC05_DETAIL readme:dead_claim_returned"; }

# Scope: README and tests/fixtures/ only, matching RB03's own scope comment
# above -- the requirements and roadmap records live outside this worktree,
# in the tree this suite does not run from, and the suite must also pass from
# a release tarball that carries neither. Their D-18 correction is verified by
# human read, per the phase's validation record.

if [[ "$CC05_OK" -eq 1 ]]; then
    ok "CC05 README's dated --model fact matches the captured fixture header, and the pre-phase claim stays gone"
else
    bad "CC05 README's dated --model fact matches the captured fixture header, and the pre-phase claim stays gone" \
        "detail=$CC05_DETAIL"
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

echo "== the guarantee holds with and without a controlling terminal (RB06) =="

# Job control degrades in a terminal-less runner, so a suite that only ever runs
# under a developer's terminal can pass locally and pass vacuously in CI. RESEARCH
# found that on THIS host job control does allocate a distinct process group even
# inside a command substitution with no terminal, which makes the guard's fallback
# a rare edge rather than the common path -- but "rare on this host" is not "never
# anywhere", and D-14a is explicit that where isolation fails, the guard's
# degradation is what must be asserted rather than a green tick. Both outcomes are
# named assertions inside _rb_assert_reaped; neither is an untested branch.
#
# The with-terminal half only means something because the forking fake ignores
# SIGHUP: allocating a pseudo-terminal means the kernel HUPs the session when the
# terminal goes away, which reaps the fake and its fork for a reason that has
# nothing to do with the bounding mechanism. Measured before the fixture was
# hardened -- a shim mutated to kill by pid alone left the fork alive in the
# terminal-LESS half and was reaped anyway in the with-terminal half, so this case
# passed while asserting nothing. See tests/fake-agy.sh's FAKE_AGY_FORK_HANG note.
#
# Resolved from the harness's OWN PATH, before any replacement PATH applies --
# the same discipline $_TIMEOUT_NET follows, and for the same reason: the
# sanitized PATH deliberately resolves almost nothing.
_PTY_BIN="$(command -v script 2>/dev/null)" || _PTY_BIN=""
# Flavour probed from the BINARY, never from `uname`. The util-linux build takes
# the command through an option; the BSD build macOS ships takes it as trailing
# operands after the typescript file. Handing one build the other's form is not
# reliably loud: a mis-parsed form can run the command with NO terminal at all and
# report the D-14a half green on exactly the platform this phase's fallback exists
# for. `uname` was rejected against a feature probe because it misreads a Mac
# carrying a brew-installed util-linux `script` earlier on PATH -- what decides the
# argv is a property of the binary that will actually run, not of the OS.
_PTY_FLAVOUR=""
if [[ -n "$_PTY_BIN" ]]; then
    _PTY_FLAVOUR="$("$_PTY_BIN" --version 2>&1)" || _PTY_FLAVOUR=""
fi

# _rb_pty_argv FLAVOUR TYPESCRIPT CMDSTRING -> fills _RB_PTY_ARGV.
# Both builds are handed the command as ONE string, which is what lets the two
# branches be compared against each other on a single host.
_rb_pty_argv() {
    if [[ "$1" == *util-linux* ]]; then
        _RB_PTY_ARGV=(-q -c "$3" "$2")
    else
        _RB_PTY_ARGV=(-q "$2" bash -c "$3")
    fi
}

# RB06a: both flavour branches pinned HERE, on this one host, by driving the
# selector with a stubbed probe result rather than with the real tool. The branch
# this host cannot execute is exactly the branch the portability finding is about,
# so leaving it to be discovered on a Mac is the failure being closed.
RB06A_OK=1
RB06A_DETAIL=""
_RB_PTY_ARGV=()
_rb_pty_argv 'script from util-linux 2.42.2' /dev/null 'true'
[[ "${_RB_PTY_ARGV[*]}" == "-q -c true /dev/null" ]] \
    || { RB06A_OK=0; RB06A_DETAIL="$RB06A_DETAIL util_linux=[${_RB_PTY_ARGV[*]}]"; }
_rb_pty_argv 'usage: script [-adfkpqr] [file]' /dev/null 'true'
[[ "${_RB_PTY_ARGV[*]}" == "-q /dev/null bash -c true" ]] \
    || { RB06A_OK=0; RB06A_DETAIL="$RB06A_DETAIL bsd=[${_RB_PTY_ARGV[*]}]"; }
if [[ "$RB06A_OK" -eq 1 ]]; then
    ok "RB06a the PTY allocator's argument form is chosen by flavour probe, both branches pinned"
else
    bad "RB06a the PTY allocator's argument form is chosen by flavour probe, both branches pinned" \
        "detail=$RB06A_DETAIL"
fi

# The command both halves run. Written to a file rather than squeezed into a
# quoted string so the two invocation forms differ ONLY in how the allocator
# takes the command. It records whether it saw stdout on a tty before doing
# anything else, and its own exit code afterwards -- read from files because
# the two `script` builds do not agree on propagating the command's status.
RB06_RUNNER="$SANDBOX/rb06-run.sh"
cat > "$RB06_RUNNER" <<'RB06EOF'
#!/usr/bin/env bash
# $1=replacement PATH $2=shim $3=parent pid file $4=child pid file
# $5=the shim's own stderr $6=tty flag file $7=rc file
if [ -t 1 ]; then printf 'tty\n' > "$6"; else printf 'notty\n' > "$6"; fi
PATH="$1" FAKE_AGY_FORK_HANG=1 FAKE_AGY_PID_FILE="$3" FAKE_AGY_CHILD_PID_FILE="$4" \
    GEMINI_SHIM_TIMEOUT=3 bash "$2" -p "do a thing" >/dev/null 2>"$5"
printf '%s\n' "$?" > "$7"
RB06EOF

_RB06_BIN="$(_purebin)"
RB06_TTY_OK=1
RB06_TTY_DETAIL=""
for _rb06_mode in plain pty; do
    RB06_PPF="$SANDBOX/rb06-$_rb06_mode-parent.pid"
    RB06_CPF="$SANDBOX/rb06-$_rb06_mode-child.pid"
    RB06_ERR="$SANDBOX/rb06-$_rb06_mode-stderr.log"
    RB06_TTYF="$SANDBOX/rb06-$_rb06_mode-tty.flag"
    RB06_RCF="$SANDBOX/rb06-$_rb06_mode-rc"
    rm -f "$RB06_PPF" "$RB06_CPF" "$RB06_ERR" "$RB06_TTYF" "$RB06_RCF"

    if [[ "$_rb06_mode" == "pty" && -z "$_PTY_BIN" ]]; then
        # An environment that cannot make this assertion has not made it. No skip
        # that reads as a pass, and the tool is named.
        bad "RB06c the descendant guarantee holds with a controlling terminal" \
            "the PTY allocator 'script' is not on PATH, so the D-14a with-terminal half could not be asserted"
        RB06_TTY_OK=0
        RB06_TTY_DETAIL="$RB06_TTY_DETAIL pty:allocator_missing(script)"
        continue
    fi

    _RB06_START=$(date +%s)
    if [[ "$_rb06_mode" == "plain" ]]; then
        "$_TIMEOUT_NET" --foreground -k 5 30 \
            bash "$RB06_RUNNER" "$_RB06_BIN" "$SHIM" "$RB06_PPF" "$RB06_CPF" \
            "$RB06_ERR" "$RB06_TTYF" "$RB06_RCF" >/dev/null 2>&1
    else
        _RB_PTY_ARGV=()
        _rb_pty_argv "$_PTY_FLAVOUR" "$SANDBOX/rb06.typescript" \
            "bash '$RB06_RUNNER' '$_RB06_BIN' '$SHIM' '$RB06_PPF' '$RB06_CPF' '$RB06_ERR' '$RB06_TTYF' '$RB06_RCF'"
        "$_TIMEOUT_NET" --foreground -k 5 30 \
            "$_PTY_BIN" "${_RB_PTY_ARGV[@]}" >/dev/null 2>&1
    fi
    _RB06_ELAPSED=$(( $(date +%s) - _RB06_START ))
    RB06_RC="$(cat "$RB06_RCF" 2>/dev/null)" || RB06_RC=""
    [[ "$RB06_RC" =~ ^[0-9]+$ ]] || RB06_RC=-1
    RB06_SAW="$(cat "$RB06_TTYF" 2>/dev/null)" || RB06_SAW=""

    # The terminal state is asserted, never inferred from a zero exit status: an
    # allocator invocation that silently degraded to no terminal would otherwise
    # report the with-terminal half green without ever having allocated one.
    if [[ "$_rb06_mode" == "plain" ]]; then
        [[ "$RB06_SAW" == "notty" ]] \
            || { RB06_TTY_OK=0; RB06_TTY_DETAIL="$RB06_TTY_DETAIL plain:saw='$RB06_SAW'(want notty)"; }
    else
        [[ "$RB06_SAW" == "tty" ]] \
            || { RB06_TTY_OK=0; RB06_TTY_DETAIL="$RB06_TTY_DETAIL pty:saw='$RB06_SAW'(want tty)"; }
    fi

    if [[ "$_rb06_mode" == "plain" ]]; then
        _rb06_label="RB06b the descendant guarantee holds with no controlling terminal"
    else
        _rb06_label="RB06c the descendant guarantee holds with a controlling terminal"
    fi
    _rb_assert_reaped "$_rb06_label" "$RB06_RC" "$_RB06_ELAPSED" \
        "$RB06_PPF" "$RB06_CPF" "$(cat "$RB06_ERR" 2>/dev/null)"
done
if [[ "$RB06_TTY_OK" -eq 1 ]]; then
    ok "RB06d the two halves genuinely ran without and with a terminal (notty then tty)"
else
    bad "RB06d the two halves genuinely ran without and with a terminal (notty then tty)" \
        "detail=$RB06_TTY_DETAIL"
fi
rm -f "$SANDBOX/rb06.typescript"

echo "== the helper's diagnostics never reach the caller's payload (RB09) =="

# RB09 is the assertion that justifies the separate descriptor run_bounded writes
# its diagnostics to. Four of the six bounded sites have already redirected the
# process's stderr by the time the helper runs, and at the DELEGATION site that
# redirection target is what the bridge interpolates into both its plain-text
# error and its JSON `error` value -- so a marker on plain stderr would land
# inside a payload Phase 3 is freezing in this same release.

# RB09a, end to end: what the CALLER actually received from a watchdog-killed
# delegation. stdout and stderr are captured SEPARATELY -- merging them would
# make the whole case meaningless, since the marker legitimately belongs on one
# and must never appear on the other.
RB09_PPF="$SANDBOX/rb09-parent.pid"
RB09_CPF="$SANDBOX/rb09-child.pid"
RB09_OUTF="$SANDBOX/rb09-stdout.json"
RB09_ERRF="$SANDBOX/rb09-stderr.log"
rm -f "$RB09_PPF" "$RB09_CPF" "$RB09_OUTF" "$RB09_ERRF"
_RB09_BIN="$(_purebin)"
PATH="$_RB09_BIN" FAKE_AGY_FORK_HANG=1 FAKE_AGY_PID_FILE="$RB09_PPF" \
    FAKE_AGY_CHILD_PID_FILE="$RB09_CPF" \
    "$_TIMEOUT_NET" --foreground -k 5 30 \
    bash "$BRIDGE" --type code --timeout 3 --json -- "do a thing" \
    > "$RB09_OUTF" 2> "$RB09_ERRF"
RB09_RC=$?
RB09_OK=1
RB09_DETAIL=""
# Without this the absence assertions below could all hold on a run that never
# reached a bounded call at all.
[[ "$RB09_RC" -eq 124 ]] || { RB09_OK=0; RB09_DETAIL="$RB09_DETAIL not_a_bounded_kill(rc=$RB09_RC)"; }
# Nothing the helper says may reach the caller's stdout, which on --json is the
# entire machine-readable payload.
for _rb09_s in "$_RB_NOTE_LITERAL" "$_RB_GUARD_MSG" "$_RB_WARN_LITERAL"; do
    grep -qF "$_rb09_s" "$RB09_OUTF" && { RB09_OK=0; RB09_DETAIL="$RB09_DETAIL diagnostic_in_payload"; }
done
# The payload's key set is asserted, not just its text: this phase adds no key to
# the envelope, and a case that only grepped for strings would not notice one.
RB09_KEYS="$(python3 -c 'import json,sys; print(",".join(sorted(json.load(open(sys.argv[1])).keys())))' "$RB09_OUTF" 2>/dev/null)" || RB09_KEYS="UNPARSEABLE"
[[ "$RB09_KEYS" == "duration_seconds,error,model_used,success,type" ]] \
    || { RB09_OK=0; RB09_DETAIL="$RB09_DETAIL keys=[$RB09_KEYS]"; }
# And the marker WAS emitted, on the entry point's own stderr. Without this half a
# run in which the marker was never produced at all would pass every absence
# assertion above -- absence-by-silence, which is the way this case could rot.
grep -qF "$_RB_NOTE_LITERAL" "$RB09_ERRF" \
    || { RB09_OK=0; RB09_DETAIL="$RB09_DETAIL marker_never_emitted(stderr=$(head -c 200 "$RB09_ERRF"))"; }
if [[ "$RB09_OK" -eq 1 ]]; then
    ok "RB09a a watchdog-killed delegation: no helper diagnostic in the JSON payload, unchanged key set, marker on the entry point's own stderr"
else
    bad "RB09a a watchdog-killed delegation: no helper diagnostic in the JSON payload, unchanged key set, marker on the entry point's own stderr" \
        "detail=$RB09_DETAIL"
fi
kill -KILL "$(cat "$RB09_PPF" 2>/dev/null)" 2>/dev/null
kill -KILL "$(cat "$RB09_CPF" 2>/dev/null)" 2>/dev/null
: > "$RB09_PPF"; : > "$RB09_CPF"

# RB09b: the captured-stderr half. Stated ceiling rather than hidden: the bridge
# unlinks its work directory from an EXIT trap, so the real $STDERR_FILE cannot be
# read after the run. What CAN be pinned exactly is the property that file's
# cleanliness depends on -- so the delegation site's redirect shape is reproduced
# against the extracted block, and the two descriptors the bridge would later
# interpolate are asserted clean while fd 9 carries the marker. The child ignores
# SIGTERM (`trap "" TERM` survives `exec`), so the escalation genuinely fires and
# the marker genuinely has to be emitted somewhere.
RB09B_FD9="$SANDBOX/rb09b-fd9.log"
RB09B_OUT="$SANDBOX/rb09b-stdout.log"
RB09B_ERR="$SANDBOX/rb09b-stderr.log"
: > "$RB09B_FD9"; : > "$RB09B_OUT"; : > "$RB09B_ERR"
bash -c '
    set -euo pipefail
    exec 9>"$2"
    TIMEOUT_BIN=""
    . "$1"
    run_bounded 2 1 -- bash -c "trap \"\" TERM; exec sleep 30" > "$3" 2> "$4" < /dev/null || true
' _ "$_RB_BLOCK" "$RB09B_FD9" "$RB09B_OUT" "$RB09B_ERR"; RB09B_RC=$?
RB09B_OK=1
RB09B_DETAIL=""
[[ "$RB09B_RC" -eq 0 ]] || { RB09B_OK=0; RB09B_DETAIL="$RB09B_DETAIL driver_rc=$RB09B_RC"; }
grep -qF "$_RB_NOTE_LITERAL" "$RB09B_FD9" \
    || { RB09B_OK=0; RB09B_DETAIL="$RB09B_DETAIL marker_never_emitted(fd9=$(head -c 200 "$RB09B_FD9"))"; }
for _rb09b_f in "$RB09B_OUT" "$RB09B_ERR"; do
    for _rb09b_s in "$_RB_NOTE_LITERAL" "$_RB_GUARD_MSG"; do
        grep -qF "$_rb09b_s" "$_rb09b_f" \
            && { RB09B_OK=0; RB09B_DETAIL="$RB09B_DETAIL diagnostic_in_${_rb09b_f##*/}"; }
    done
done
if [[ "$RB09B_OK" -eq 1 ]]; then
    ok "RB09b at the delegation site's redirect shape, the bounded call's own stdout and stderr stay free of helper diagnostics while fd 9 carries the marker"
else
    bad "RB09b at the delegation site's redirect shape, the bounded call's own stdout and stderr stay free of helper diagnostics while fd 9 carries the marker" \
        "detail=$RB09B_DETAIL"
fi

echo "== the helper's own contract at its edges (RB10-RB14, unit) =="

# These four exercise run_bounded DIRECTLY rather than through an entry point,
# because the contracts they pin are not reachable from a call site: every call
# site passes bounds the script has already validated, so the refusal branch
# would ship untested, and the early-versus-late boundary would need a real agy
# timed to the second. Extraction costs nothing -- the D-08 duplication markers
# already delimit the block, and _rb_extract already reads them for RB02.
#
# The block is taken from the shim; RB02 pins the two copies byte-identical, so
# what is asserted here holds for the bridge's copy too.
#
# Each driver sets up the two -- and only the two -- things the block declares it
# needs from a host script: $TIMEOUT_BIN and fd 9. And each runs under the same
# `set -euo pipefail` the shipped scripts use, not this harness's laxer `set -u`:
# the helper's guarded-lookup behaviour only matters under the stricter setting,
# so a relaxed driver would be testing a shape that never ships.
#
# Every driver's stdout goes to a FILE rather than through a command
# substitution, for the reason RB05 documents: a surviving fake inherits fd 9 and
# would hold a capture pipe open for its full 300s sleep on exactly the runs that
# ought to fail fast.

# RB10a -- the EARLY side of the boundary. A child that exits on its own well
# inside `secs` hands its own code straight back: no relabelling, no flag, no
# marker. 1s against a 5s bound is a 5x margin, and bounds are integer seconds,
# so this is the coarsest-grained "comfortably inside" the contract can express.
RB10A_FD9="$SANDBOX/rb10a-fd9.log"
RB10A_OUT="$SANDBOX/rb10a-out.log"
: > "$RB10A_FD9"; : > "$RB10A_OUT"
bash -c '
    set -euo pipefail
    exec 9>"$2"
    TIMEOUT_BIN=""
    . "$1"
    rc=0
    run_bounded 5 2 -- bash -c "sleep 1; exit 42" || rc=$?
    printf "%s %s\n" "$rc" "$RUN_BOUNDED_KILLED"
' _ "$_RB_BLOCK" "$RB10A_FD9" > "$RB10A_OUT" 2>&1; RB10A_RC=$?
RB10A_SEEN="$(cat "$RB10A_OUT" 2>/dev/null)"
if [[ "$RB10A_RC" -eq 0 && "$RB10A_SEEN" == "42 0" ]] \
   && ! grep -qF "$_RB_NOTE_LITERAL" "$RB10A_FD9"; then
    ok "RB10a (unit) a child that exits inside its bound returns its own code untouched, flag clear, no marker"
else
    bad "RB10a (unit) a child that exits inside its bound returns its own code untouched, flag clear, no marker" \
        "driver_rc=$RB10A_RC saw='$RB10A_SEEN'(want '42 0') fd9=$(head -c 200 "$RB10A_FD9")"
fi

# RB10b -- the LATE side. A child still alive at secs + kill_after is gone, and
# so is anything it forked. Reuses the forking fake rather than growing a second
# adversarial stub: it already ignores SIGTERM and SIGHUP, records both PIDs
# before either process blocks, and sleeps far past any bound here.
RB10B_FD9="$SANDBOX/rb10b-fd9.log"
RB10B_OUT="$SANDBOX/rb10b-out.log"
RB10B_PPF="$SANDBOX/rb10b-parent.pid"
RB10B_CPF="$SANDBOX/rb10b-child.pid"
: > "$RB10B_FD9"; : > "$RB10B_OUT"; rm -f "$RB10B_PPF" "$RB10B_CPF"
FAKE_AGY_FORK_HANG=1 FAKE_AGY_PID_FILE="$RB10B_PPF" FAKE_AGY_CHILD_PID_FILE="$RB10B_CPF" \
    "$_TIMEOUT_NET" --foreground -k 5 30 bash -c '
    set -euo pipefail
    exec 9>"$2"
    TIMEOUT_BIN=""
    . "$1"
    rc=0
    run_bounded 3 2 -- bash "$3" --print x || rc=$?
    printf "%s %s\n" "$rc" "$RUN_BOUNDED_KILLED"
' _ "$_RB_BLOCK" "$RB10B_FD9" "$HERE/fake-agy.sh" > "$RB10B_OUT" 2>&1
RB10B_SEEN="$(cat "$RB10B_OUT" 2>/dev/null)"
RB10B_PPID="$(cat "$RB10B_PPF" 2>/dev/null)" || RB10B_PPID=""
RB10B_CPID="$(cat "$RB10B_CPF" 2>/dev/null)" || RB10B_CPID=""
RB10B_PGONE=1; RB10B_CGONE=1
[[ "$RB10B_PPID" =~ ^[0-9]+$ ]] && kill -0 "$RB10B_PPID" 2>/dev/null && RB10B_PGONE=0
[[ "$RB10B_CPID" =~ ^[0-9]+$ ]] && kill -0 "$RB10B_CPID" 2>/dev/null && RB10B_CGONE=0
if [[ "$RB10B_SEEN" == "124 1" \
      && "$RB10B_PPID" =~ ^[0-9]+$ && "$RB10B_CPID" =~ ^[0-9]+$ \
      && "$RB10B_PGONE" -eq 1 && "$RB10B_CGONE" -eq 1 ]] \
   && grep -qF "$_RB_NOTE_LITERAL" "$RB10B_FD9"; then
    ok "RB10b (unit) a child alive past secs + kill_after is gone, and so is its fork; returns 124 with the flag set"
else
    bad "RB10b (unit) a child alive past secs + kill_after is gone, and so is its fork; returns 124 with the flag set" \
        "saw='$RB10B_SEEN'(want '124 1') parent=$RB10B_PPID gone=$RB10B_PGONE child=$RB10B_CPID gone=$RB10B_CGONE fd9=$(head -c 200 "$RB10B_FD9")"
fi
[[ "$RB10B_PPID" =~ ^[0-9]+$ ]] && kill -KILL "$RB10B_PPID" 2>/dev/null
[[ "$RB10B_CPID" =~ ^[0-9]+$ ]] && kill -KILL "$RB10B_CPID" 2>/dev/null
: > "$RB10B_PPF"; : > "$RB10B_CPF"

# RB12 -- adjacency. A child whose own exit is timed to land AT the bound, run a
# few times so the race is actually exercised. What is asserted is the
# BICONDITIONAL D-02 states -- the return is 124 exactly when the flag is set,
# and the child's own code exactly when it is not -- never which side won. The
# race is real and asserting a winner would be flaky by construction; the pair
# can never disagree, and that is stable. `124 0` (a self-exited child relabelled
# a timeout) and `55 1` (a killed call reporting the child's code) are precisely
# the two states that must be impossible, and both are rejected below.
#
# secs=1 with kill_after=1 is the tightest adjacency the contract can express at
# all, since bounds are integer seconds. Three iterations, because the whole
# point is that EITHER outcome is legal, so repetition buys coverage of the race
# rather than confidence in one answer.
#
# A FOURTH observation follows, and it is what stops this case being a tautology.
# Measured: against a helper mutated to never set the kill flag, three at-the-bound
# observations all landed on the self-exited side and the case stayed green -- it
# would have passed against a helper with no kill logic at all. The fourth child
# ignores SIGTERM and sleeps far past the bound, so it cannot win the race; it is
# held to the SAME biconditional, not to a hand-picked answer, and the batch is
# additionally required to contain at least one flag-set observation. That
# requirement is not flaky, because it is satisfied by the child that cannot win
# rather than by the three that might.
RB12_FD9="$SANDBOX/rb12-fd9.log"
RB12_OUT="$SANDBOX/rb12-out.log"
: > "$RB12_FD9"; : > "$RB12_OUT"
"$_TIMEOUT_NET" --foreground -k 5 30 bash -c '
    set -euo pipefail
    exec 9>"$2"
    TIMEOUT_BIN=""
    . "$1"
    for _i in 1 2 3; do
        rc=0
        run_bounded 1 1 -- bash -c "sleep 1; exit 55" || rc=$?
        printf "%s %s\n" "$rc" "$RUN_BOUNDED_KILLED"
    done
    rc=0
    run_bounded 1 1 -- bash -c "trap \"\" TERM HUP; exec sleep 30" || rc=$?
    printf "%s %s\n" "$rc" "$RUN_BOUNDED_KILLED"
' _ "$_RB_BLOCK" "$RB12_FD9" > "$RB12_OUT" 2>&1; RB12_RC=$?
RB12_OK=1
RB12_DETAIL=""
[[ "$RB12_RC" -eq 0 ]] || { RB12_OK=0; RB12_DETAIL="$RB12_DETAIL driver_rc=$RB12_RC"; }
RB12_N=0
RB12_KILLS=0
while read -r _rb12_line; do
    RB12_N=$(( RB12_N + 1 ))
    case "$_rb12_line" in
        "124 1") RB12_KILLS=$(( RB12_KILLS + 1 )) ;;
        "55 0")  : ;;
        *) RB12_OK=0; RB12_DETAIL="$RB12_DETAIL violated[$_rb12_line]" ;;
    esac
done < "$RB12_OUT"
[[ "$RB12_N" -eq 4 ]] || { RB12_OK=0; RB12_DETAIL="$RB12_DETAIL observations=$RB12_N(want 4)"; }
[[ "$RB12_KILLS" -ge 1 ]] || { RB12_OK=0; RB12_DETAIL="$RB12_DETAIL no_kill_observed(the TERM-ignoring child must be one)"; }
if [[ "$RB12_OK" -eq 1 ]]; then
    ok "RB12 (unit) the return is 124 if and only if the kill flag is set -- never 124 for a self-exited child"
else
    bad "RB12 (unit) the return is 124 if and only if the kill flag is set -- never 124 for a self-exited child" \
        "detail=$RB12_DETAIL out=$(tr '\n' ';' < "$RB12_OUT")"
fi

# RB11 -- the empty edge and refusal. A bound that is empty, zero or non-numeric,
# and a call with no command after the separator, are all refused with a fixed
# error on the helper's own descriptor and a return of 2. The assertion that
# actually matters is the third one: that the command DID NOT RUN, observed
# through a sentinel the command would have created. A refusal that still
# executes the command is worse than no refusal.
#
# A zero is the dangerous member of that set, not an odd one: the coreutils
# binary documents a zero duration as NO TIMEOUT, so an unvalidated zero is a
# bound that silently disables bounding -- the exact hang this helper exists to
# prevent (T-01-04).
#
# The last probe is a VALID call, and it is not decoration: without it every
# `norun` above could be reported because the sentinel mechanism itself is
# broken, and the case would pass while observing nothing.
RB11_FD9="$SANDBOX/rb11-fd9.log"
RB11_OUT="$SANDBOX/rb11-out.log"
RB11_SENT="$SANDBOX/rb11-sentinel"
: > "$RB11_FD9"; : > "$RB11_OUT"; rm -f "$RB11_SENT"
bash -c '
    set -euo pipefail
    exec 9>"$2"
    TIMEOUT_BIN=""
    . "$1"
    SENT="$3"
    probe() {
        local rc=0
        rm -f "$SENT"
        run_bounded "$@" || rc=$?
        if [[ -e "$SENT" ]]; then printf "%s ran\n" "$rc"; else printf "%s norun\n" "$rc"; fi
    }
    probe ""  2  -- bash -c "touch \"$SENT\""
    probe 0   2  -- bash -c "touch \"$SENT\""
    probe abc 2  -- bash -c "touch \"$SENT\""
    probe 5   "" -- bash -c "touch \"$SENT\""
    probe 5   0  -- bash -c "touch \"$SENT\""
    probe 5   x  -- bash -c "touch \"$SENT\""
    probe 5   2  --
    probe 5   2  -- bash -c "touch \"$SENT\""
' _ "$_RB_BLOCK" "$RB11_FD9" "$RB11_SENT" > "$RB11_OUT" 2>&1; RB11_RC=$?
_RB_REFUSAL='ERROR: run_bounded needs positive integer secs and kill_after, then -- and a command'
RB11_OK=1
RB11_DETAIL=""
[[ "$RB11_RC" -eq 0 ]] || { RB11_OK=0; RB11_DETAIL="$RB11_DETAIL driver_rc=$RB11_RC"; }
RB11_REFUSED="$(grep -cxF '2 norun' "$RB11_OUT")" || RB11_REFUSED=0
RB11_RAN="$(grep -cxF '0 ran' "$RB11_OUT")" || RB11_RAN=0
RB11_ERRS="$(grep -cF "$_RB_REFUSAL" "$RB11_FD9")" || RB11_ERRS=0
[[ "$RB11_REFUSED" -eq 7 ]] || { RB11_OK=0; RB11_DETAIL="$RB11_DETAIL refused=$RB11_REFUSED(want 7)"; }
[[ "$RB11_RAN" -eq 1 ]] || { RB11_OK=0; RB11_DETAIL="$RB11_DETAIL control_ran=$RB11_RAN(want 1)"; }
[[ "$RB11_ERRS" -eq 7 ]] || { RB11_OK=0; RB11_DETAIL="$RB11_DETAIL fixed_errors=$RB11_ERRS(want 7)"; }
if [[ "$RB11_OK" -eq 1 ]]; then
    ok "RB11 (unit) every empty/zero/non-numeric bound and a missing command are refused with 2, the fixed error, and nothing run"
else
    bad "RB11 (unit) every empty/zero/non-numeric bound and a missing command are refused with 2, the fixed error, and nothing run" \
        "detail=$RB11_DETAIL out=$(tr '\n' ';' < "$RB11_OUT")"
fi
rm -f "$RB11_SENT"

# RB14 -- argument boundaries (T-01-03). An argument containing spaces must reach
# the command as ONE argv element. Driven through BOTH mechanisms, because that
# symmetry is what the helper's promotion to primary claims: the coreutils arm
# and the watchdog arm are two implementations of one contract, and argv is part
# of it. The fake's existing observational argv dump is the recording command --
# no new stub. It exits non-zero here (no --add-dir), which is irrelevant: the
# dump is written before any parsing.
RB14_OK=1
RB14_DETAIL=""
for _rb14_mech in watchdog coreutils; do
    RB14_DUMP="$SANDBOX/rb14-$_rb14_mech.argv"
    RB14_FD9="$SANDBOX/rb14-$_rb14_mech-fd9.log"
    rm -f "$RB14_DUMP"; : > "$RB14_FD9"
    if [[ "$_rb14_mech" == "watchdog" ]]; then _rb14_bin=""; else _rb14_bin="$_TIMEOUT_NET"; fi
    FAKE_AGY_DUMP_ARGV="$RB14_DUMP" bash -c '
        set -euo pipefail
        exec 9>"$2"
        TIMEOUT_BIN="$4"
        . "$1"
        run_bounded 5 2 -- bash "$3" --print "one two three" || true
    ' _ "$_RB_BLOCK" "$RB14_FD9" "$HERE/fake-agy.sh" "$_rb14_bin" >/dev/null 2>&1
    _rb14_n="$(grep -c '' "$RB14_DUMP" 2>/dev/null)" || _rb14_n=0
    _rb14_one="$(grep -cxF 'one two three' "$RB14_DUMP" 2>/dev/null)" || _rb14_one=0
    [[ "$_rb14_n" -eq 2 ]] || { RB14_OK=0; RB14_DETAIL="$RB14_DETAIL $_rb14_mech:argc=$_rb14_n(want 2)"; }
    [[ "$_rb14_one" -eq 1 ]] || { RB14_OK=0; RB14_DETAIL="$RB14_DETAIL $_rb14_mech:not_one_element"; }
done
if [[ "$RB14_OK" -eq 1 ]]; then
    ok "RB14 (unit) a space-containing argument crosses the helper as one argv element, on both mechanisms"
else
    bad "RB14 (unit) a space-containing argument crosses the helper as one argv element, on both mechanisms" \
        "detail=$RB14_DETAIL"
fi

echo "== install.sh / uninstall.sh (vfn.11) =="

_MARKER='# agy-delegate-wrapper'

# _fresh_home -> prints a new temp HOME dir with bin/agy (fake) + bin on PATH.
_fresh_home() {
    local h; h="$(mktemp -d "$SANDBOX/ihome.XXXXXX")"
    mkdir -p "$h/.local/bin" "$h/bin"
    cp "$HERE/fake-agy.sh" "$h/bin/agy"
    chmod +x "$h/bin/agy"
    _cc_fixtures_beside "$h/bin"
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
_cc_fixtures_beside "$IH/nopy"
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

echo "== bridge survives a bare environment, HOME unset (RB27) =="

# Both launchers run under `set -euo pipefail`, so ONE unguarded $HOME aborts
# the script before it does anything -- and they are reached with HOME unset by
# `env -i`, systemd units without User=, container entrypoints and CI runners.
# gemini_shim.sh was hardened for this at 2c78194; agy_bridge.sh carried FOUR
# unguarded expansions (the models cache, the MCP cache, and the two config
# paths handed to python3), so a guard on the first alone leaves three live
# crashes on exactly the hosts this defect is about.
#
# Driven through a REAL delegation, which is the only path that reaches all
# four: --types exits inside the argument loop, well before the first of them.
RB27_BIN="$(mktemp -d "$SANDBOX/rb27bin.XXXXXX")"
cp "$HERE/fake-agy.sh" "$RB27_BIN/agy"
chmod +x "$RB27_BIN/agy"
_cc_fixtures_beside "$RB27_BIN"
RB27_ERRF="$SANDBOX/rb27.err"
RB27_OUT="$(env -i PATH="$RB27_BIN:/usr/bin:/bin" FAKE_AGY_STDOUT="rb27 bare ok" \
    bash "$BRIDGE" --type code -- "no home here" 2>"$RB27_ERRF")" && RB27_RC=0 || RB27_RC=$?
RB27_ERR="$(cat "$RB27_ERRF" 2>/dev/null || true)"

RB27_OK=1
[[ "$RB27_RC" -eq 0 ]]                       || RB27_OK=0
# Non-vacuity: the delegation really ran end to end under the bare env, so a
# pass cannot come from the bridge bailing out early for some other reason.
[[ "$RB27_OUT" == *"rb27 bare ok"* ]]        || RB27_OK=0
[[ "$RB27_ERR" != *"unbound variable"* ]]    || RB27_OK=0
# Second half of the same defect: with HOME unset the cache paths land under the
# fallback root, which does not exist. Both cache writes must swallow the failed
# redirect the way the shim's does -- caching is best-effort, and a per-call
# "No such file or directory" on stderr corrupts nothing but pollutes every
# caller's log.
[[ "$RB27_ERR" != *"No such file or directory"* ]] || RB27_OK=0

# Per-site, not per-symptom: every $HOME used as a PATH PREFIX in either shipped
# launcher must carry a fallback. The run above proves today's four sites; this
# catches a fifth added later on a branch that delegation does not take.
RB27_UNGUARDED="$(grep -n '\$HOME/' "$BRIDGE" "$SHIM" | grep -v '\${HOME:-' || true)"
[[ -z "$RB27_UNGUARDED" ]] || RB27_OK=0

if [[ "$RB27_OK" -eq 1 ]]; then
    ok "RB27 bridge completes a delegation with HOME unset, and no \$HOME path expansion is unguarded"
else
    bad "RB27 bridge completes a delegation with HOME unset, and no \$HOME path expansion is unguarded" \
        "rc=$RB27_RC out=${RB27_OUT:0:120} err=${RB27_ERR:0:200} unguarded=${RB27_UNGUARDED:0:200}"
fi

echo "== installer live verify is bounded against a hung agy (RB28) =="

# install.sh's live verify pipes a REAL delegation through the shim. With no
# installer-side bound it inherits GEMINI_SHIM_TIMEOUT's 600s default -- a work
# bound, not a smoke-test one -- so a hung agy parks the installer for ten
# minutes under a line that reads "non-fatal". The installer must impose its own
# short bound and fall into the existing "could not run" branch on expiry.
#
# The limit here is the OBSERVATION window, not the contract: it exists so the
# unbounded regression is caught in a minute instead of ten. FORK_HANG (rather
# than PRINT_HANG) is used purely because it records the fake agy's PIDs, which
# is what lets this case reap them deterministically instead of leaving a
# 300-second sleeper behind on the unbounded path.
RB28_LIMIT=60
RB28_HOME="$(_fresh_home)"
RB28_LOG="$SANDBOX/rb28-install.log"
RB28_PPF="$SANDBOX/rb28-agy-parent.pid"
RB28_CPF="$SANDBOX/rb28-agy-child.pid"
: > "$RB28_PPF"; : > "$RB28_CPF"
RB28_START=$(date +%s)
env -i HOME="$RB28_HOME" PATH="$RB28_HOME/bin:$RB28_HOME/.local/bin:/usr/bin:/bin" \
    AGY_PLUGIN_DIR="$ROOT" FAKE_AGY_FORK_HANG=1 \
    FAKE_AGY_PID_FILE="$RB28_PPF" FAKE_AGY_CHILD_PID_FILE="$RB28_CPF" \
    bash "$INSTALL" > "$RB28_LOG" 2>&1 &
RB28_PID=$!
RB28_DONE=0
for _ in $(seq 1 "$RB28_LIMIT"); do
    kill -0 "$RB28_PID" 2>/dev/null || { RB28_DONE=1; break; }
    sleep 1
done
RB28_ELAPSED=$(( $(date +%s) - RB28_START ))
if [[ "$RB28_DONE" -eq 0 ]]; then
    # Unbounded: release the installer by killing the agy it is waiting on, then
    # let it finish normally. Killing the installer itself would orphan the shim
    # and its agy for the rest of their 600s bound.
    for _f in "$RB28_PPF" "$RB28_CPF"; do
        _p="$(cat "$_f" 2>/dev/null)" || _p=""
        [[ "$_p" =~ ^[0-9]+$ ]] && kill -KILL "$_p" 2>/dev/null
    done
fi
wait "$RB28_PID" 2>/dev/null && RB28_RC=0 || RB28_RC=$?
RB28_AGY_PID="$(cat "$RB28_PPF" 2>/dev/null || true)"
: > "$RB28_PPF"; : > "$RB28_CPF"
RB28_LOGTXT="$(cat "$RB28_LOG" 2>/dev/null || true)"

RB28_OK=1
[[ "$RB28_DONE" -eq 1 ]] || RB28_OK=0
[[ "$RB28_RC" -eq 0 ]]   || RB28_OK=0
# Non-vacuity: the smoke call must have actually reached agy and hung there, so
# a pass cannot come from the shim erroring out before it ever delegated. The
# fake records its own PID immediately before it blocks.
[[ "$RB28_AGY_PID" =~ ^[0-9]+$ ]] || RB28_OK=0
[[ "$RB28_LOGTXT" == *"gemini shim smoke: could not run"* ]] || RB28_OK=0
[[ "$RB28_LOGTXT" == *"Done."* ]] || RB28_OK=0
if [[ "$RB28_OK" -eq 1 ]]; then
    ok "RB28 installer live verify bounds its own smoke call and reports 'could not run' on a hung agy"
else
    bad "RB28 installer live verify bounds its own smoke call and reports 'could not run' on a hung agy" \
        "done=$RB28_DONE elapsed=${RB28_ELAPSED}s limit=${RB28_LIMIT}s rc=$RB28_RC agy_pid=${RB28_AGY_PID:-none} log=$(tail -4 "$RB28_LOG" 2>/dev/null)"
fi

echo "== the GENERATED wrapper survives a bare environment (RB29) =="

# RB27 hardened the bridge itself, but users never invoke the bridge: they
# invoke the wrapper install.sh generates, which carries its own
# `set -euo pipefail` and, in front of every exec, an unguarded $HOME inside the
# registry path's `:-` default. With CLAUDE_CONFIG_DIR unset bash expands that
# default word, so an unset HOME aborts the wrapper before it reaches the
# guarded bridge -- nullifying RB27 on the only path an installed user has.
#
# The suite's blind spot was that every other case drives the SCRIPTS, or drives
# the wrapper with HOME set; nothing exercised the GENERATED ARTIFACT bare. This
# case does, and asserts both halves: the wrapper runs with HOME and
# CLAUDE_CONFIG_DIR both unset, AND the version-pin check it feeds still refuses
# a stale pin when the registry is readable -- so the guard cannot be "fixed" by
# quietly disabling the lookup.
RB29_IH="$(_fresh_home)"
RB29_VROOT="$(mktemp -d "$SANDBOX/rb29root.XXXXXX")"
mkdir -p "$RB29_VROOT/agy-delegate/1.0.0/scripts"
cp "$ROOT/scripts/agy_bridge.sh" "$ROOT/scripts/gemini_shim.sh" "$RB29_VROOT/agy-delegate/1.0.0/scripts/"
env -i HOME="$RB29_IH" PATH="$RB29_IH/bin:$RB29_IH/.local/bin:/usr/bin:/bin" \
    AGY_PLUGIN_DIR="$RB29_VROOT/agy-delegate/1.0.0" \
    bash "$INSTALL" > "$SANDBOX/rb29-install.log" 2>&1
RB29_BW="$RB29_IH/.local/bin/agy-bridge"
RB29_BARE_PATH="$RB29_IH/bin:/usr/bin:/bin"

# (a) bare env: neither HOME nor CLAUDE_CONFIG_DIR set.
RB29_OUT="$(env -i PATH="$RB29_BARE_PATH" bash "$RB29_BW" --types 2>"$SANDBOX/rb29-bare.err")" \
    && RB29_RC=0 || RB29_RC=$?
RB29_ERR="$(cat "$SANDBOX/rb29-bare.err" 2>/dev/null || true)"

# (b) registry readable via CLAUDE_CONFIG_DIR, still with HOME unset, naming a
#     NEWER active version -> the pin check must still fire. A fix that made the
#     wrapper survive by dropping the lookup would pass (a) and fail here.
RB29_CFG="$(mktemp -d "$SANDBOX/rb29cfg.XXXXXX")"
mkdir -p "$RB29_CFG/plugins"
RB29_KEY="agy-delegate@$(basename "$RB29_VROOT")"
cat > "$RB29_CFG/plugins/installed_plugins.json" <<REGJSON
{
  "version": 2,
  "plugins": {
    "$RB29_KEY": [
      {
        "scope": "user",
        "installPath": "/tmp/AGY-REGISTRY-PATH-SENTINEL",
        "version": "1.1.0"
      }
    ]
  }
}
REGJSON
RB29_SOUT="$(env -i PATH="$RB29_BARE_PATH" CLAUDE_CONFIG_DIR="$RB29_CFG" \
    bash "$RB29_BW" --types 2>"$SANDBOX/rb29-stale.err")" && RB29_SRC=0 || RB29_SRC=$?
RB29_SERR="$(cat "$SANDBOX/rb29-stale.err" 2>/dev/null || true)"

RB29_OK=1
[[ "$RB29_RC" -eq 0 ]]                    || RB29_OK=0
# Non-vacuity: the wrapper really execed the bridge, so a pass cannot come from
# it exiting 0 somewhere earlier.
[[ "$RB29_OUT" == *"model"* ]]            || RB29_OK=0
[[ "$RB29_ERR" != *"unbound variable"* ]] || RB29_OK=0
# The pin check still works when the registry IS readable.
[[ "$RB29_SRC" -eq 127 ]]                 || RB29_OK=0
[[ -z "$RB29_SOUT" ]]                     || RB29_OK=0
case "$RB29_SERR" in *"1.0.0"*"1.1.0"*|*"1.1.0"*"1.0.0"*) :;; *) RB29_OK=0;; esac
# The guard must expand at WRAPPER RUN TIME. Getting the heredoc escaping
# backwards would bake the installing user's HOME into every wrapper -- a worse
# bug than the crash, and one that (a) and (b) both pass.
grep -q '\${HOME:-' "$RB29_BW"             || RB29_OK=0
grep -qF "$RB29_IH/.claude" "$RB29_BW"    && RB29_OK=0
# Per-site, on the GENERATED artifacts: any $HOME used as a path prefix in
# either emitted wrapper must carry a fallback, including one added later.
RB29_UNGUARDED="$(grep -n '\$HOME/' "$RB29_BW" "$RB29_IH/.local/bin/gemini" 2>/dev/null | grep -v '\${HOME:-' || true)"
[[ -z "$RB29_UNGUARDED" ]]                || RB29_OK=0

if [[ "$RB29_OK" -eq 1 ]]; then
    ok "RB29 generated wrapper runs with HOME and CLAUDE_CONFIG_DIR unset, and still refuses a stale pin"
else
    bad "RB29 generated wrapper runs with HOME and CLAUDE_CONFIG_DIR unset, and still refuses a stale pin" \
        "rc=$RB29_RC out=${RB29_OUT:0:80} err=${RB29_ERR:0:200} stale_rc=$RB29_SRC stale_err=${RB29_SERR:0:200} unguarded=${RB29_UNGUARDED:0:200}"
fi

echo "== the check answers 'could not ask' (CC01, CC02) =="

# CC01: with no agy anywhere on PATH -- not the fake, not the real binary --
# tests/contract-check.sh must return inside its own bound, report the
# distinct unverified exit code, and name the assumption it could not settle
# (D-02, D-08b). A directory built from _PUREBIN_TOOLS's exact whitelist,
# with no agy entry added, is the entire PATH for the invocation (full
# replacement, no ":$PATH" suffix) -- deliberately not _purebin(), which
# always adds the fake as "agy".
#
# Wrapped in an EXTERNAL 30-second `timeout` -- SH11's shape, not T4/T5's: a
# regression to unbounded inside contract-check.sh must be caught from
# outside in seconds, not by trusting the check's own internal bound, which
# is exactly the thing a regression here would have broken.
# AGY_CONTRACT_TIMEOUT=2 so a working bound (the case this run expects) still
# returns fast; it is irrelevant to this path in practice since AGY_BIN never
# resolves and run_bounded is never called, but it documents the intent for
# a reader and costs nothing.
#
# Captured through a FILE and read back afterward, never through a command
# substitution -- the same fd-9 rationale as _run_sanitized (tests/run-tests.sh
# :152-168): contract-check.sh opens its own fd 9 on its original stderr, and
# a live command substitution wrapping the whole invocation would leave any
# surviving descendant holding that capture pipe open.
CC01_DIR="$(mktemp -d "$SANDBOX/cc01-noagy.XXXXXX")"
# _PUREBIN_TOOLS plus "timeout" itself: unlike _purebin()'s other callers,
# this invocation replaces PATH wholesale for the outer 30-second bounding
# wrapper too (there is no harness PATH left to fall back on for it), so the
# bounding binary must be resolvable inside the replacement directory or the
# wrapper itself fails to start rather than bounding anything.
for _cc01_t in "${_PUREBIN_TOOLS[@]}" timeout; do
    _cc01_p="$(command -v "$_cc01_t" 2>/dev/null)" || _cc01_p=""
    if [[ -z "$_cc01_p" ]]; then
        printf 'FATAL: CC01 sanitized PATH cannot resolve required tool: %s\n' "$_cc01_t" >&2
        exit 1
    fi
    ln -sf "$_cc01_p" "$CC01_DIR/$_cc01_t"
done

CC01_OUT="$SANDBOX/cc01.out"
CC01_START="$(date +%s)"
PATH="$CC01_DIR" HOME="$HOME" AGY_CONTRACT_TIMEOUT=2 \
    timeout 30 bash "$CONTRACT_CHECK" > "$CC01_OUT" 2>&1
CC01_RC=$?
_CC01_ELAPSED=$(( $(date +%s) - CC01_START ))
CC01_TEXT="$(cat "$CC01_OUT" 2>/dev/null)"

rm -f "$HOME/.cache/agy-bridge-models"

CC01_OK=1
[[ "$CC01_RC" -eq 10 ]] || CC01_OK=0
[[ "$CC01_TEXT" =~ ^agy-version-shape[[:space:]]+unverified[[:space:]]+[^[:space:]] ]] || CC01_OK=0
[[ "$_CC01_ELAPSED" -lt 30 ]] || CC01_OK=0
# Negative half: no ROW line (lines not starting with the "#" summary
# prefix) reports a bare "verified" verdict -- "unverified" must not be
# mistaken for a pass by this assertion, so the boundary requires whitespace
# on both sides of the word.
CC01_VERIFIED_ROWS="$(printf '%s\n' "$CC01_TEXT" | grep -v '^#' | grep -cE '[[:space:]]verified([[:space:]]|$)')"
[[ "$CC01_VERIFIED_ROWS" -eq 0 ]] || CC01_OK=0

if [[ "$CC01_OK" -eq 1 ]]; then
    ok "CC01 with no agy on PATH, the check exits 10 inside its bound and names agy-version-shape unverified"
else
    CC01_DETAIL="rc=$CC01_RC elapsed=${_CC01_ELAPSED}s verified_rows=$CC01_VERIFIED_ROWS first_two=$(printf '%s\n' "$CC01_TEXT" | head -2 | tr '\n' '|')"
    bad "CC01 with no agy on PATH, the check exits 10 inside its bound and names agy-version-shape unverified" \
        "$CC01_DETAIL"
fi

# CC02: a SIGTERM-ignoring `agy` that sleeps 300s on --version must not hang
# the operator who ran the check (D-08's hang shape, D-08a criterion 2).
# `_purebin()`'s directory holds the fake `agy` (copied there at :118) as the
# entire PATH -- the fake-present counterpart to CC01's fake-absent case,
# same isolation machinery. Setting FAKE_AGY_VERSION_HANG makes the fake
# trap SIGTERM and sleep 300s on the --version path -- the only probe the
# check makes at this point in the phase. AGY_CONTRACT_TIMEOUT=2 so the
# check's own internal bound fires quickly.
#
# Wrapped in a plain external `timeout 30` -- SH11's shape at :1060, not
# T4/T5's internal-flag shape, and deliberately not `_run_sanitized`'s
# `--foreground -k 5 30` net (that net is a suite-level safety belt, never
# the mechanism under test; composing CC02's own bound directly on top of it
# would blur that line). `env PATH=...` scopes the sanitized PATH to the
# check invocation alone, so the outer `timeout` word itself still resolves
# through the harness's own PATH -- `_purebin()`'s directory holds no
# timeout/gtimeout on purpose (RB00a), and CC01 already hit the rc=127 a
# fully-replaced PATH causes when the outer wrapper cannot resolve itself.
#
# Captured through a FILE and read back afterward, never through a command
# substitution -- the same fd-9 rationale as _run_sanitized
# (tests/run-tests.sh:152-168): contract-check.sh opens its own fd 9 on its
# original stderr, and a live command substitution wrapping the whole
# invocation would leave any surviving descendant holding that capture pipe
# open.
CC02_DIR="$(_purebin)"
CC02_OUT="$SANDBOX/cc02.out"
CC02_ERR="$SANDBOX/cc02.err"
CC02_START="$(date +%s)"
timeout 30 env PATH="$CC02_DIR" HOME="$HOME" AGY_CONTRACT_TIMEOUT=2 FAKE_AGY_VERSION_HANG=1 \
    bash "$CONTRACT_CHECK" > "$CC02_OUT" 2> "$CC02_ERR"
CC02_RC=$?
_CC02_ELAPSED=$(( $(date +%s) - CC02_START ))
# stdout and stderr captured SEPARATELY, not merged: _purebin()'s directory
# holds no timeout/gtimeout on purpose (RB00a), so contract-check.sh's own
# TIMEOUT_BIN probe prints its WARNING to stderr before the ledger row --
# CC01's scratch PATH adds an explicit timeout entry and never hits this,
# but CC02 must not let that diagnostic land ahead of the row on stdout.
CC02_TEXT="$(cat "$CC02_OUT" 2>/dev/null)"
CC02_ROW1="$(printf '%s\n' "$CC02_TEXT" | head -n1)"

rm -f "$HOME/.cache/agy-bridge-models"

CC02_OK=1
[[ "$CC02_RC" -eq 10 ]] || CC02_OK=0
[[ "$CC02_ROW1" =~ ^agy-version-shape[[:space:]]+unverified[[:space:]]+[^[:space:]] ]] || CC02_OK=0
if [[ "$CC02_ROW1" =~ ^agy-version-shape[[:space:]]+unverified[[:space:]]+(.+)$ ]]; then
    CC02_EVIDENCE="${BASH_REMATCH[1]}"
else
    CC02_EVIDENCE=""
fi
# The evidence must record the attempt (D-12a): non-empty, and naming either
# the bound or the rc run_bounded returned internally.
[[ -n "$CC02_EVIDENCE" ]] || CC02_OK=0
[[ "$CC02_EVIDENCE" == *"rc="* || "$CC02_EVIDENCE" == *bound* ]] || CC02_OK=0
# Negative half, same boundary rule as CC01: no row reports a bare "verified"
# verdict anywhere in the ledger.
CC02_VERIFIED_ROWS="$(printf '%s\n' "$CC02_TEXT" | grep -v '^#' | grep -cE '[[:space:]]verified([[:space:]]|$)')"
[[ "$CC02_VERIFIED_ROWS" -eq 0 ]] || CC02_OK=0
# "Returned on its own" distinguished from "was reaped by the net" -- SH11's
# own margin against its 30s wrapper.
[[ "$_CC02_ELAPSED" -lt 25 ]] || CC02_OK=0

if [[ "$CC02_OK" -eq 1 ]]; then
    ok "CC02 a hung agy (SIGTERM-ignoring --version) makes the check exit 10 inside its bound, never verified"
else
    CC02_DETAIL="rc=$CC02_RC elapsed=${_CC02_ELAPSED}s evidence=$CC02_EVIDENCE verified_rows=$CC02_VERIFIED_ROWS row1=$CC02_ROW1 stderr=$(cat "$CC02_ERR" 2>/dev/null | tr '\n' '|')"
    bad "CC02 a hung agy (SIGTERM-ignoring --version) makes the check exit 10 inside its bound, never verified" \
        "$CC02_DETAIL"
fi

echo "== the suite never reaches a real agy through the check (CC03) =="

# D-02's narrowing, recorded here as well as in the phase's own decision log:
# criterion 1 (ROADMAP.md, an open item for the user, left unedited by this
# case) reads "separate from the unit suite and never invoked by it". Taken
# literally that collides head-on with criterion 2, which requires the
# "could not ask" path (CC01, CC02 above) to be a TESTED deliverable, and
# testing it means driving the command. D-02 resolves the collision by
# narrowing what this suite enforces to the property that actually matters:
# the unit suite never reaches a real agy through the check. CC03 is that
# narrower property, asserted mechanically over run-tests.sh's OWN SOURCE --
# the same self-referential shape RB01 (:1813 above) uses on the shipped
# scripts, because a call site added six months from now is on no path any
# behavioural test can see.
#
# _cc_check_scan FILE -> "<violations> <occurrences>", the same two-number
# contract _rb_agy_scan (:1892) returns. Every invocation of the harness's
# own $CONTRACT_CHECK -- in any expansion form, plus a literal
# contract-check.sh path used as a command -- is an occurrence. Split into
# two independently-cleared regions around the cc03-self-exempt bracket
# (the review round's F4 fix, see 01.5-02-PLAN.md "Alternatives Considered"
# -- CC03m's own probe payload strings below sit inside the very file CC03
# scans, unlike RB01m's payloads which live in a file RB01 never reads):
#   production -- everything outside the bracket. Cleared only when the
#     SAME segment also carries a PATH= assignment that does not end in
#     :$PATH/${PATH} (the direct PATH="$(_purebin)"/PATH="$dir" form CC01
#     and CC02 use), or when the segment's command word is _run_sanitized
#     (which fully replaces PATH internally for whatever it drives), or
#     when the segment mentions _rb_extract -- a static sed READ of
#     contract-check.sh's own source for RB02's byte-identity check
#     (:1998), never an invocation; D-02 is about reaching a real agy, and
#     reading source text structurally cannot.
#   exempt -- the bracketed range, inclusive of both marker lines. Cleared
#     only when the segment's FIRST WORD is _cc03m_probe -- a payload
#     argument to the mutation harness, not a real invocation. Anything
#     else inside the bracket is still a violation, so the bracket narrows
#     rather than opens an escape hatch.
# occurrences reports the PRODUCTION region's count only: counting the
# exempt region's payload strings toward the floor would let the floor be
# satisfied by the mutation fixtures alone. Reuses _rb_agy_segments (:1876)
# unchanged, so the unit of judgement stays "one command", never "one
# line" -- the same reason RB01 needs it for its own twoonone hole.
# Comment lines are already dropped by _rb_logical_lines before this ever
# sees them, so a comment naming the variable cannot inflate either count.
#
# The marker pair is also asserted here, not only by direct grep in the
# plan's acceptance criteria: a duplicated or deleted marker forces a
# violation regardless of what the region split produces, so a widened
# exemption fails loudly instead of silently passing (the plan's own
# "delete the END marker" manual proof).
# _cc_raw_segments FILE -> one COMMAND per line, split at the SAME points
# _rb_agy_segments uses (the same _rb_logical_lines join, then the same
# `;|&` split) but WITHOUT that helper's leading-noise-stripping step.
# CC03's clearing rule needs a segment's OWN leading PATH= assignment
# intact, and _rb_agy_segments strips exactly that as leading noise -- the
# same treatment it gives `if`/`VAR=$(` ahead of a bounded call, correct
# for RB01's "does this segment START WITH run_bounded" check, but it would
# silently erase the one signal CC03's PATH= rule depends on (CC01 and
# CC02's invocations both open with a bare `PATH=... cmd`, which is
# syntactically identical to a plain assignment statement and so is
# indistinguishable "noise" to that stripping regex). Occurrence counting
# is unaffected either way -- a `contains` check, not a `starts with` one --
# and the exempt region's "first word is _cc03m_probe" check never has
# leading noise to strip in the first place, so this changes nothing but
# what CC03 specifically needs to see.
_cc_raw_segments() {
    _rb_logical_lines "$1" | tr ';|&' '\n\n\n'
}

_cc_check_scan() {
    local file="$1"
    local begin='# --- BEGIN cc03-self-exempt ---'
    local end='# --- END cc03-self-exempt ---'
    local prod_f exempt_f
    prod_f="$(mktemp "$SANDBOX/cc03-prod.XXXXXX")"
    exempt_f="$(mktemp "$SANDBOX/cc03-exempt.XXXXXX")"
    sed "/^${begin}\$/,/^${end}\$/d" "$file" > "$prod_f"
    sed -n "/^${begin}\$/,/^${end}\$/p" "$file" > "$exempt_f"

    # Second alternative excludes a preceding `/` so a PATH FRAGMENT such as
    # the CONTRACT_CHECK assignment's own "$HERE/contract-check.sh" (a
    # value being built, never a command) is not mistaken for the literal
    # path used AS a command; a bare word or one preceded by whitespace/a
    # quote still matches.
    local occ_re='\$\{?CONTRACT_CHECK\}?|(^|[^/])contract-check\.sh'
    local raw_segs seg val
    local o_prod v_prod v_exempt n_begin n_end marker_viol=0

    # Occurrence floor: the same two-step grep -oE | grep -c '' idiom
    # _rb_agy_scan (:1892) uses, over _rb_agy_segments' own stripped
    # output -- noise-agnostic, since an occurrence is a `contains` check,
    # so reusing that helper here costs nothing and satisfies D-02's "in
    # any expansion form" over the widest reasonable text.
    o_prod="$(_rb_agy_segments "$prod_f" | grep -oE "$occ_re" | grep -c '')" || o_prod=0

    # Violations, over the RAW (unstripped) split -- see _cc_raw_segments.
    raw_segs="$(_cc_raw_segments "$prod_f")"
    local prod_uncleared=""
    while IFS= read -r seg; do
        [[ "$seg" =~ $occ_re ]] || continue
        # _run_sanitized fully replaces PATH internally for whatever it
        # drives (no current call site uses this form for CONTRACT_CHECK;
        # recognised so a future direct call through the helper is cleared
        # too, per the plan's explicit "recognise both forms").
        if [[ "$seg" =~ ^[[:space:]]*_run_sanitized([[:space:]]|$) ]]; then continue; fi
        # A static sed READ of contract-check.sh's own source for RB02's
        # byte-identity check (:1998) -- never an invocation.
        if [[ "$seg" == *_rb_extract* ]]; then continue; fi
        if [[ "$seg" =~ (^|[[:space:];])PATH=([^[:space:]]*) ]]; then
            val="${BASH_REMATCH[2]}"
            val="${val%\"}"; val="${val#\"}"
            case "$val" in
                *':$PATH'|*':${PATH}') prod_uncleared="$prod_uncleared
$seg" ;;
                *) : ;;  # full replacement -- cleared
            esac
        else
            prod_uncleared="$prod_uncleared
$seg"
        fi
    done <<<"$raw_segs"
    v_prod="$(printf '%s\n' "$prod_uncleared" | grep -oE "$occ_re" | grep -c '')" || v_prod=0

    raw_segs="$(_cc_raw_segments "$exempt_f")"
    local exempt_uncleared=""
    while IFS= read -r seg; do
        [[ "$seg" =~ $occ_re ]] || continue
        [[ "$seg" =~ ^[[:space:]]*_cc03m_probe([[:space:]]|$) ]] && continue
        exempt_uncleared="$exempt_uncleared
$seg"
    done <<<"$raw_segs"
    v_exempt="$(printf '%s\n' "$exempt_uncleared" | grep -oE "$occ_re" | grep -c '')" || v_exempt=0

    n_begin="$(grep -cx "$begin" "$file")" || n_begin=0
    n_end="$(grep -cx "$end" "$file")" || n_end=0
    [[ "$n_begin" -eq 1 && "$n_end" -eq 1 ]] || marker_viol=1

    rm -f "$prod_f" "$exempt_f"
    printf '%s %s' "$((v_prod + v_exempt + marker_viol))" "$o_prod"
}

# --- BEGIN cc03-self-exempt ---
# CC03: the real file. No occurrence floor number is asserted beyond "at
# least one" -- RB01's own reasoning, restated here rather than re-derived:
# a criterion naming an exact count is correct only until the next commit,
# and the floor exists so a rename empties the scan loudly rather than
# quietly.
CC03_V=""; CC03_O=""
read -r CC03_V CC03_O <<<"$(_cc_check_scan "$HERE/run-tests.sh")"
CC03_OK=1
[[ "$CC03_V" -eq 0 ]] || CC03_OK=0
[[ "$CC03_O" -ge 1 ]] || CC03_OK=0
if [[ "$CC03_OK" -eq 1 ]]; then
    ok "CC03 no case in the suite reaches a real agy through the check (isolation scan)"
else
    bad "CC03 no case in the suite reaches a real agy through the check (isolation scan)" \
        "violations=$CC03_V production_occurrences=$CC03_O(floor >=1; exempt region excluded)"
fi

# CC03m: the scan is proven capable of failing before it is trusted, RB01m's
# own discipline (:1934) applied to _cc_check_scan. Five probes: RB01m's
# four holes (mutated/ambient here, commented, twoonone, decoy/appended
# here) plus the one the exempt region itself introduces (smuggled).
#
# _cc03m_probe NAME WANT_VIOLATION LINE [MODE] [EXTRA] -- copies
# run-tests.sh and injects LINE either appended at the copy's end (MODE
# "append", the default: the cc03-self-exempt bracket sits earlier in the
# file, so an appended line always lands in the production region) or,
# when MODE is the literal word "smuggle", immediately after the BEGIN
# marker via sed's `r` command -- INSIDE the bracket -- proving the exempt
# region narrows rather than opens an escape hatch. When EXTRA is given,
# LINE and EXTRA are joined with a literal `;` HERE, inside this function's
# own code, rather than in any probe's own payload argument: the twoonone
# shape needs one raw semicolon-joined logical line in the copy, but a `;`
# character sitting in the CALL SITE's own text (which is itself part of
# the file CC03 scans) would split THAT call across two segments and trip
# a false violation on the real, correct source -- proven live during this
# plan's own implementation. Neither half-string here ever contains
# CONTRACT_CHECK text once separated, so joining them here is exactly as
# safe as _rb_agy_segments' own control-flow stripping. Runs the SAME
# _cc_check_scan CC03 itself uses and asserts the expected verdict, plus
# the occurrence floor on every probe (not only the clean ones), exactly
# as _rb01m_probe does.
CC03M_DIR="$SANDBOX/cc03m"
rm -rf "$CC03M_DIR"; mkdir -p "$CC03M_DIR"
CC03M_OK=1
CC03M_DETAIL=""
_cc03m_probe() {
    local name="$1" want="$2" line="$3" mode="${4:-append}" extra="${5:-}" v o copy inj
    if [[ -n "$extra" ]]; then line="${line};${extra}"; fi
    copy="$CC03M_DIR/$name.sh"
    cp "$HERE/run-tests.sh" "$copy"
    if [[ "$mode" == "smuggle" ]]; then
        inj="$CC03M_DIR/$name.inject"
        printf '%s\n' "$line" > "$inj"
        sed -i "/^# --- BEGIN cc03-self-exempt ---\$/r $inj" "$copy"
        rm -f "$inj"
    else
        printf '%s\n' "$line" >> "$copy"
    fi
    read -r v o <<<"$(_cc_check_scan "$copy")"
    [[ "$o" -ge 1 ]] || { CC03M_OK=0; CC03M_DETAIL="$CC03M_DETAIL $name:no_occurrences"; }
    if [[ "$want" -eq 1 ]]; then
        [[ "$v" -ge 1 ]] || { CC03M_OK=0; CC03M_DETAIL="$CC03M_DETAIL $name:missed(${v}/${o})"; }
    else
        [[ "$v" -eq 0 ]] || { CC03M_OK=0; CC03M_DETAIL="$CC03M_DETAIL $name:false_positive(${v}/${o})"; }
    fi
}
_cc03m_probe ambient   1 'bash "$CONTRACT_CHECK" --version'
_cc03m_probe appended  1 'PATH="/tmp/cc03m-fake:$PATH" bash "$CONTRACT_CHECK"'
_cc03m_probe commented 0 '# a comment mentioning "$CONTRACT_CHECK" is not a call site'
_cc03m_probe twoonone  1 'PATH="$(_purebin)" bash "$CONTRACT_CHECK"' append 'bash "$CONTRACT_CHECK"'
_cc03m_probe smuggled  1 'bash "$CONTRACT_CHECK" --smuggled' smuggle
if [[ "$CC03M_OK" -eq 1 ]]; then
    ok "CC03m the scan reports every injected shape, including one smuggled inside the exempt bracket, and ignores a comment"
else
    bad "CC03m the scan reports every injected shape, including one smuggled inside the exempt bracket, and ignores a comment" \
        "detail=$CC03M_DETAIL"
fi
rm -rf "$CC03M_DIR"
# --- END cc03-self-exempt ---

echo "== the fake resolves its fixtures, or fails loudly (CC04) =="

# CC04a: tier 1 (AGY_FIXTURES_DIR) wins over tier 2 (a fixtures/ sibling),
# proven with two DISTINGUISHABLE synthetic variants -- the only way to show
# tier 1 specifically resolved, not merely that some tier did.
CC04A_DIR="$(mktemp -d "$SANDBOX/cc04a.XXXXXX")"
cp "$HERE/fake-agy.sh" "$CC04A_DIR/agy"; chmod +x "$CC04A_DIR/agy"
mkdir -p "$CC04A_DIR/fixtures"
printf '%s\n' "# sibling variant" "gemini-9.1-flash-high	Sibling Variant" \
    > "$CC04A_DIR/fixtures/agy-models.tsv"
CC04A_OVERRIDE="$(mktemp -d "$SANDBOX/cc04a-override.XXXXXX")"
printf '%s\n' "# override variant" "gemini-9.2-flash-high	Override Variant" \
    > "$CC04A_OVERRIDE/agy-models.tsv"
CC04A_OUT="$(AGY_FIXTURES_DIR="$CC04A_OVERRIDE" "$CC04A_DIR/agy" models)"
if [[ "$CC04A_OUT" == *"gemini-9.2-flash-high"* && "$CC04A_OUT" != *"gemini-9.1-flash-high"* ]]; then
    ok "CC04a AGY_FIXTURES_DIR (tier 1) wins over a fixtures/ sibling (tier 2)"
else
    bad "CC04a AGY_FIXTURES_DIR (tier 1) wins over a fixtures/ sibling (tier 2)" "out=$CC04A_OUT"
fi
rm -rf "$CC04A_DIR" "$CC04A_OVERRIDE"

# CC04b: tier 2 after a copy -- RB27's shape reduced to its resolution
# question, and the case that would have caught D-14a's original defect.
CC04B_DIR="$(mktemp -d "$SANDBOX/cc04b.XXXXXX")"
cp "$HERE/fake-agy.sh" "$CC04B_DIR/agy"; chmod +x "$CC04B_DIR/agy"
_cc_fixtures_beside "$CC04B_DIR"
CC04B_OUT="$(env -u AGY_FIXTURES_DIR -u AGY_PLUGIN_DIR "$CC04B_DIR/agy" models)"
CC04B_EXPECT="$(grep -v '^#' "$HERE/fixtures/agy-models.tsv")"
if [[ "$CC04B_OUT" == "$CC04B_EXPECT" ]]; then
    ok "CC04b tier 2 (fixtures/ copied beside the fake) resolves the real fixture"
else
    bad "CC04b tier 2 (fixtures/ copied beside the fake) resolves the real fixture" "out=${CC04B_OUT:0:200}"
fi
rm -rf "$CC04B_DIR"

# CC04c: no tier resolves, and a zero-row fixture -- both must fail LOUD,
# never silently empty. Streams captured SEPARATELY, SH9's pattern
# (tests/run-tests.sh, "gemini_shim.sh: dynamic model resolution" section),
# not _run, which merges them and would let an empty stdout pass while the
# diagnostic sat in the same buffer. The emptiness assertion is the
# important half: an empty list is the degraded shape S1 exists to catch, so
# "fails loudly" and "emits nothing" must be provably different outcomes.
CC04C_DIR="$(mktemp -d "$SANDBOX/cc04c.XXXXXX")"
cp "$HERE/fake-agy.sh" "$CC04C_DIR/agy"; chmod +x "$CC04C_DIR/agy"
CC04C_OK=1
CC04C_DETAIL=""

CC04C_OUT1F="$SANDBOX/cc04c-1.out"; CC04C_ERR1F="$SANDBOX/cc04c-1.err"
env -u AGY_FIXTURES_DIR -u AGY_PLUGIN_DIR \
    "$CC04C_DIR/agy" models > "$CC04C_OUT1F" 2> "$CC04C_ERR1F"
CC04C_RC1=$?
CC04C_OUT1="$(cat "$CC04C_OUT1F")"
CC04C_ERR1="$(cat "$CC04C_ERR1F")"
[[ "$CC04C_RC1" -ne 0 ]] || { CC04C_OK=0; CC04C_DETAIL="$CC04C_DETAIL no_tier:rc=$CC04C_RC1"; }
[[ -z "$CC04C_OUT1" ]] || { CC04C_OK=0; CC04C_DETAIL="$CC04C_DETAIL no_tier:stdout_not_empty"; }
[[ "$CC04C_ERR1" == *"AGY_FIXTURES_DIR"* ]] || { CC04C_OK=0; CC04C_DETAIL="$CC04C_DETAIL no_tier:tier1_not_named"; }
[[ "$CC04C_ERR1" == *"$CC04C_DIR/fixtures"* ]] || { CC04C_OK=0; CC04C_DETAIL="$CC04C_DETAIL no_tier:tier2_not_named"; }
[[ "$CC04C_ERR1" == *"tests/fixtures"* ]] || { CC04C_OK=0; CC04C_DETAIL="$CC04C_DETAIL no_tier:tier3_not_named"; }

mkdir -p "$CC04C_DIR/fixtures"
printf '%s\n' "# header only, zero data rows" > "$CC04C_DIR/fixtures/agy-models.tsv"
CC04C_OUT2F="$SANDBOX/cc04c-2.out"; CC04C_ERR2F="$SANDBOX/cc04c-2.err"
env -u AGY_FIXTURES_DIR -u AGY_PLUGIN_DIR \
    "$CC04C_DIR/agy" models > "$CC04C_OUT2F" 2> "$CC04C_ERR2F"
CC04C_RC2=$?
CC04C_OUT2="$(cat "$CC04C_OUT2F")"
[[ "$CC04C_RC2" -ne 0 ]] || { CC04C_OK=0; CC04C_DETAIL="$CC04C_DETAIL zero_row:rc=$CC04C_RC2"; }
[[ -z "$CC04C_OUT2" ]] || { CC04C_OK=0; CC04C_DETAIL="$CC04C_DETAIL zero_row:stdout_not_empty"; }
grep -qF "$CC04C_DIR/fixtures/agy-models.tsv" "$CC04C_ERR2F" \
    || { CC04C_OK=0; CC04C_DETAIL="$CC04C_DETAIL zero_row:file_not_named"; }

if [[ "$CC04C_OK" -eq 1 ]]; then
    ok "CC04c no tier resolving, and a zero-row fixture, both fail loud: non-zero, byte-empty stdout, paths named"
else
    bad "CC04c no tier resolving, and a zero-row fixture, both fail loud: non-zero, byte-empty stdout, paths named" \
        "$CC04C_DETAIL"
fi
rm -rf "$CC04C_DIR"

echo "== the shipped model derivation at its edges (CC06) =="

# CC06 exercises _cc_expect_model's rule -- the byte-identical shipped
# derivation -- against synthetic lists written into the sandbox, reached
# through the helper's own optional second parameter (F3). Reimplementing
# the grep|sort -V|tail -1 rule here would be a second definition of
# "newest matching id" able to disagree with the shipped one; the version
# sort exists once, in the helper.
CC06_OK=1
CC06_DETAIL=""

# precision: a 3.10 id beside a 3.7 id -- version ordering must be sort -V's,
# not lexical, which would pick 3.7.
CC06_PREC="$SANDBOX/cc06-precision.tsv"
printf '%s\n' "# synthetic" \
    "gemini-3.7-flash-high	Gemini 3.7 Flash (High)" \
    "gemini-3.10-flash-high	Gemini 3.10 Flash (High)" > "$CC06_PREC"
CC06_PREC_GOT="$(_cc_expect_model flash-high "$CC06_PREC")"
[[ "$CC06_PREC_GOT" == "gemini-3.10-flash-high" ]] \
    || { CC06_OK=0; CC06_DETAIL="$CC06_DETAIL precision:got=$CC06_PREC_GOT"; }

# adjacency: a well-formed id and the same string with an extra trailing
# segment -- the matcher is $-anchored, so the exact match wins whether or
# not the longer id is present.
CC06_ADJ="$SANDBOX/cc06-adjacency.tsv"
printf '%s\n' "# synthetic" "gemini-3.8-flash-high	Gemini 3.8 Flash (High)" > "$CC06_ADJ"
CC06_ADJ_BASE="$(_cc_expect_model flash-high "$CC06_ADJ")"
printf '%s\n' "gemini-3.8-flash-high-extra	Gemini 3.8 Flash (High Extra)" >> "$CC06_ADJ"
CC06_ADJ_WITH_LONGER="$(_cc_expect_model flash-high "$CC06_ADJ")"
[[ "$CC06_ADJ_BASE" == "gemini-3.8-flash-high" ]] \
    || { CC06_OK=0; CC06_DETAIL="$CC06_DETAIL adjacency:base=$CC06_ADJ_BASE"; }
[[ "$CC06_ADJ_WITH_LONGER" == "gemini-3.8-flash-high" ]] \
    || { CC06_OK=0; CC06_DETAIL="$CC06_DETAIL adjacency:with_longer=$CC06_ADJ_WITH_LONGER"; }

# determinism: two runs over the same list return the same, non-empty id.
CC06_DET1="$(_cc_expect_model flash-high "$CC06_PREC")"
CC06_DET2="$(_cc_expect_model flash-high "$CC06_PREC")"
[[ -n "$CC06_DET1" && "$CC06_DET1" == "$CC06_DET2" ]] \
    || { CC06_OK=0; CC06_DETAIL="$CC06_DETAIL determinism:run1=$CC06_DET1 run2=$CC06_DET2"; }

if [[ "$CC06_OK" -eq 1 ]]; then
    ok "CC06 shipped derivation: version-sort precision, \$-anchored adjacency, deterministic"
else
    bad "CC06 shipped derivation: version-sort precision, \$-anchored adjacency, deterministic" "$CC06_DETAIL"
fi
rm -rf "$CC06_PREC" "$CC06_ADJ"

echo
echo "PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -eq 0 ]]; then
    exit 0
else
    exit 1
fi
