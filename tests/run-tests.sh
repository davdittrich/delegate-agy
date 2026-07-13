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
#    stdin, NOT via a single (size-capped, ps/proc-visible) argv string. These
#    tests are written against that target contract. tests/fake-agy.sh already
#    enforces it; scripts/agy_bridge.sh and scripts/gemini_shim.sh do not yet
#    (that wrapper fix is a separate, still-pending work unit).
#
#    EXPECTED-RED STATE (pre-wrapper-fix): because fake-agy.sh now demands the
#    prompt in GEMINI.md, the current wrappers (bare `--print` + prompt piped on
#    stdin) deliver no TASK section, so fake-agy fail-closes with "empty prompt"
#    for EVERY invocation. Consequently the WHOLE bridge/shim suite is red now —
#    not only the new T1-T3 delivery tests but also the ps3.1/ps3.2 behavioural
#    tests (B1,B3,S1,S4,S5,D1-D4), which cannot reach their assertions until the
#    prompt is delivered. All of these flip green once the wrappers embed the
#    prompt in GEMINI.md and set the static --print pointer (T2/T3). This is the
#    intended failing state that proves the fix; no assertion may be weakened to
#    pass early.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
BRIDGE="$ROOT/scripts/agy_bridge.sh"
SHIM="$ROOT/scripts/gemini_shim.sh"

SANDBOX="$(mktemp -d -t agy-tests.XXXXXX)"
cleanup() { rm -rf "$SANDBOX"; }
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
# RC-gate + match the SPECIFIC warning phrase, not a bare "digest" substring
# (bridge arg-parse errors also contain "digest", e.g. --digest-warn-chars errors).
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

# T1 no-stdin + argv-no-leak (combined): wrap fake-agy.sh with a recorder that
# captures the real argv/stdin agy would see, then confirm the prompt (a
# distinctive token) reaches agy via the GEMINI.md TASK section -- never via
# argv (ps/proc leak) and never via stdin (agy's real prompt-delivery contract
# does not read stdin) -- while the static --add-dir pointer (proof of
# directory-based GEMINI.md delivery) IS present in argv.
# The recorder lives in its own PATH-prepended dir, scoped to a subshell so the
# plain fake-agy on PATH is untouched for the rest of the suite.
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
    OUT="$(FAKE_AGY_ECHO_PROMPT=1 bash "$BRIDGE" --type code -- "$TOKEN" 2>/dev/null)"
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

# T2 large-prompt (no ARG_MAX): a prompt well over 131072 bytes, with sentinels
# at both ends, must survive delivery intact -- no "Argument list too long"
# and both sentinels present in the echoed TASK text. Proves the wrapper
# writes the prompt into a file (GEMINI.md) rather than passing it as a
# size-capped argv string to agy (or to any intermediate exec).
FILLER="$(printf 'a%.0s' $(seq 1 131200))"
BIGPROMPT="HEADSENTINEL${FILLER}TAILSENTINEL"
OUT="$(printf '%s' "$BIGPROMPT" | FAKE_AGY_ECHO_PROMPT=1 bash "$BRIDGE" --type code 2>&1)"; RC=$?
if [[ "$RC" -eq 0 && "$OUT" == *"HEADSENTINEL"* && "$OUT" == *"TAILSENTINEL"* && "$OUT" != *"Argument list too long"* ]]; then
    ok "T2 large (>131072B) prompt delivered intact, no ARG_MAX error"
else
    bad "T2 large (>131072B) prompt delivered intact, no ARG_MAX error" "rc=$RC out_len=${#OUT} out=${OUT:0:200}..."
fi

# T3 empty-prompt: an empty prompt must not silently succeed -- either the
# wrapper or agy (fail-closed on an empty TASK section) must reject it.
_run OUT RC bash "$BRIDGE" --type code -- ""
if [[ "$RC" -ne 0 ]]; then
    ok "T3 empty prompt -> non-zero exit (no silent success)"
else
    bad "T3 empty prompt -> non-zero exit (no silent success)" "rc=$RC out=$OUT"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -eq 0 ]]; then
    exit 0
else
    exit 1
fi
