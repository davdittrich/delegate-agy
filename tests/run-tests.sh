#!/usr/bin/env bash
# run-tests.sh — behavioral tests for agy_bridge.sh + gemini_shim.sh error handling.
# Focus (ps3.1): neither script may report success when agy hides a failure behind
# exit 0 with empty stdout (quota RESOURCE_EXHAUSTED 429). Stubs `agy` via fake-agy.sh.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
BRIDGE="$ROOT/scripts/agy_bridge.sh"
SHIM="$ROOT/scripts/gemini_shim.sh"

# Isolated sandbox: fake agy on PATH, fresh HOME so the bridge model cache is clean.
SANDBOX="$(mktemp -d -t agy-tests.XXXXXX)"
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/bin" "$SANDBOX/home"
cp "$HERE/fake-agy.sh" "$SANDBOX/bin/agy"
chmod +x "$SANDBOX/bin/agy"
export PATH="$SANDBOX/bin:$PATH"
export HOME="$SANDBOX/home"

PASS=0; FAIL=0
ok()   { printf '  ok   - %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  FAIL - %s\n' "$1"; printf '         %s\n' "${2:-}"; FAIL=$((FAIL+1)); }

# run <script> <exit-var> <out-var> — runs "$@" (after 3), captures exit + stdout.
# Usage: _run OUT RC  <cmd...>  (with FAKE_AGY_* exported by caller)
_run() {
    local __out __rc
    __out="$("${@:3}" 2>/dev/null)"; __rc=$?
    printf -v "$1" '%s' "$__out"
    printf -v "$2" '%s' "$__rc"
}

echo "== agy_bridge.sh =="

# B1 normal success (regression): non-empty stdout, exit 0 → success passthrough.
FAKE_AGY_EXIT=0 FAKE_AGY_STDOUT="hello world" FAKE_AGY_STDERR="" \
  _run OUT RC bash "$BRIDGE" --type code -- "prompt"
if [[ "$RC" -eq 0 && "$OUT" == *"hello world"* ]]; then ok "B1 normal run returns success + output";
else bad "B1 normal run returns success + output" "rc=$RC out=$OUT"; fi

# B2 hidden failure: exit 0 + EMPTY stdout must become a FAILURE (non-zero exit).
FAKE_AGY_EXIT=0 FAKE_AGY_STDOUT="" FAKE_AGY_STDERR="" \
  _run OUT RC bash "$BRIDGE" --type code -- "prompt"
if [[ "$RC" -ne 0 ]]; then ok "B2 exit-0 empty-stdout → non-zero exit";
else bad "B2 exit-0 empty-stdout → non-zero exit" "rc=$RC (expected non-zero) out=$OUT"; fi

# B3 quota reason: exit 0 + empty stdout + RESOURCE_EXHAUSTED on stderr → surfaced.
# (env must be set INSIDE the command substitution so it reaches the agy child.)
ERRTXT="$(FAKE_AGY_EXIT=0 FAKE_AGY_STDOUT="" FAKE_AGY_STDERR="RESOURCE_EXHAUSTED: 429 quota, Resets in 152h" \
  bash "$BRIDGE" --type code -- "prompt" 2>&1 1>/dev/null)"; RC=$?
if [[ "$RC" -ne 0 && "$ERRTXT" == *"RESOURCE_EXHAUSTED"* ]]; then ok "B3 429 stderr surfaced in reason";
else bad "B3 429 stderr surfaced in reason" "rc=$RC err=$ERRTXT"; fi

# B4 json empty: --json + exit-0-empty → success:false envelope.
FAKE_AGY_EXIT=0 FAKE_AGY_STDOUT="" FAKE_AGY_STDERR="" \
  _run OUT RC bash "$BRIDGE" --type code --json -- "prompt"
if [[ "$RC" -ne 0 && "$OUT" == *'"success": false'* || "$OUT" == *'"success":false'* ]]; then ok "B4 json empty → success:false";
else bad "B4 json empty → success:false" "rc=$RC out=$OUT"; fi

echo "== gemini_shim.sh =="

# S1 normal text (regression): exit 0 + output → passthrough.
FAKE_AGY_EXIT=0 FAKE_AGY_STDOUT="hi there" FAKE_AGY_STDERR="" \
  _run OUT RC bash "$SHIM" -m flash "prompt"
if [[ "$RC" -eq 0 && "$OUT" == *"hi there"* ]]; then ok "S1 normal text run passthrough";
else bad "S1 normal text run passthrough" "rc=$RC out=$OUT"; fi

# S2 empty text: exit 0 + empty stdout → non-zero exit (not silent success).
FAKE_AGY_EXIT=0 FAKE_AGY_STDOUT="" FAKE_AGY_STDERR="" \
  _run OUT RC bash "$SHIM" -m flash "prompt"
if [[ "$RC" -ne 0 ]]; then ok "S2 exit-0 empty-stdout → non-zero exit";
else bad "S2 exit-0 empty-stdout → non-zero exit" "rc=$RC out=$OUT"; fi

# S3 json empty: exit 0 + empty stdout + json → non-zero AND payload NOT success-shaped.
FAKE_AGY_EXIT=0 FAKE_AGY_STDOUT="" FAKE_AGY_STDERR="" \
  _run OUT RC bash "$SHIM" -m flash --output-format json "prompt"
if [[ "$RC" -ne 0 ]] && ! grep -q '"response"' <<<"$OUT"; then ok "S3 json empty → non-zero + no success envelope";
else bad "S3 json empty → non-zero + no success envelope" "rc=$RC out=$OUT"; fi

# S4 json normal (regression): exit 0 + output + json → success envelope with response.
FAKE_AGY_EXIT=0 FAKE_AGY_STDOUT="answer" FAKE_AGY_STDERR="" \
  _run OUT RC bash "$SHIM" -m flash --output-format json "prompt"
if [[ "$RC" -eq 0 && "$OUT" == *'"response"'* && "$OUT" == *"answer"* ]]; then ok "S4 json normal → success envelope";
else bad "S4 json normal → success envelope" "rc=$RC out=$OUT"; fi

# S5 quota reason: exit 0 + empty + RESOURCE_EXHAUSTED stderr → surfaced.
ERRTXT="$(FAKE_AGY_EXIT=0 FAKE_AGY_STDOUT="" FAKE_AGY_STDERR="RESOURCE_EXHAUSTED 429" bash "$SHIM" -m flash "prompt" 2>&1 1>/dev/null)"; RC=$?
if [[ "$RC" -ne 0 && "$ERRTXT" == *"RESOURCE_EXHAUSTED"* ]]; then ok "S5 429 stderr surfaced";
else bad "S5 429 stderr surfaced" "rc=$RC err=$ERRTXT"; fi

echo "== agy_bridge.sh --digest (ps3.2) =="

# D1 --digest appends the digest contract at the END of the prompt sent to agy.
OUT="$(FAKE_AGY_ECHO_PROMPT=1 bash "$BRIDGE" --type code --digest -- "analyze this")"; RC=$?
if [[ "$RC" -eq 0 && "$OUT" == *"analyze this"* && "$OUT" == *"OUTPUT CONTRACT"* ]]; then
    # contract must come AFTER the user prompt (constraints-last)
    if [[ "${OUT##*analyze this}" == *"OUTPUT CONTRACT"* ]]; then ok "D1 --digest appends contract LAST";
    else bad "D1 --digest appends contract LAST" "contract not after prompt: $OUT"; fi
else bad "D1 --digest appends contract LAST" "rc=$RC out=$OUT"; fi

# D2 --digest + oversized reply → stderr warning fires.
WARN="$(FAKE_AGY_EXIT=0 FAKE_AGY_STDOUT="$(printf 'x%.0s' {1..5000})" \
  bash "$BRIDGE" --type code --digest --digest-warn-chars 100 -- "p" 2>&1 1>/dev/null)"; RC=$?
if [[ "$RC" -eq 0 && "$WARN" == *"digest"* ]]; then ok "D2 oversized + --digest → warning";
else bad "D2 oversized + --digest → warning" "rc=$RC warn=$WARN"; fi

# D3 oversized reply WITHOUT --digest → NO warning (byte-identical behavior).
WARN="$(FAKE_AGY_EXIT=0 FAKE_AGY_STDOUT="$(printf 'x%.0s' {1..5000})" \
  bash "$BRIDGE" --type code --digest-warn-chars 100 -- "p" 2>&1 1>/dev/null)"; RC=$?
if [[ "$RC" -eq 0 && -z "$WARN" ]]; then ok "D3 oversized w/o --digest → no warning";
else bad "D3 oversized w/o --digest → no warning" "rc=$RC warn=$WARN"; fi

# D4 no --digest → prompt is NOT modified (no contract appended).
OUT="$(FAKE_AGY_ECHO_PROMPT=1 bash "$BRIDGE" --type code -- "analyze this")"; RC=$?
if [[ "$RC" -eq 0 && "$OUT" != *"OUTPUT CONTRACT"* ]]; then ok "D4 no --digest → prompt unchanged";
else bad "D4 no --digest → prompt unchanged" "rc=$RC out=$OUT"; fi

echo
echo "== summary: $PASS passed, $FAIL failed =="
[[ "$FAIL" -eq 0 ]]
