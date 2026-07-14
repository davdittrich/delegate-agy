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
#    floor, exit-3 docs, and the 1.3.0 version bump. The T7 assertions below
#    lock in that shipped behavior.
#
#    SUITE STATE: fully GREEN. The wrapper prompt-delivery fix (T1/T2/T3) and the
#    vfn contract (T4/T5/T6, exercised by the ST*/M*/SH* cases below) have all
#    landed, so every case here passes against the current committed code. New
#    cases must keep the suite green; no assertion may be weakened to pass early.
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

echo "== policy files: fail-closed allowlist (vfn T1) =="

# ST1: the FORBIDDEN (allowlist catch-all) line is byte-identical across the
# search + all three shim policies -- one canonical catch-all, no per-file drift.
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

# ST2: the catch-all names the three MCP leak vectors it must close --
# ctx_call (the invoke-anything gateway), tokensave_, and mcp__.
CATCHALL="$(grep -h 'allowlist catch-all' "$ROOT/config/policies/search.md" | head -1)"
if [[ "$CATCHALL" == *"ctx_call"* && "$CATCHALL" == *"tokensave_"* && "$CATCHALL" == *"mcp__"* ]]; then
    ok "ST2 catch-all covers ctx_call + tokensave_ + mcp__ leak vectors"
else
    bad "ST2 catch-all covers ctx_call + tokensave_ + mcp__ leak vectors" "$CATCHALL"
fi

# ST3: the MCP-permitted policies (code/review-analysis/implement) each PERMIT
# the read-only lean-ctx/tokensave tools...
ST3_PERMIT_OK=1
for f in code review-analysis implement; do
    grep -q 'ctx_read, ctx_search, tokensave_context' "$ROOT/config/policies/$f.md" \
        || ST3_PERMIT_OK=0
done
# ...and no PERMITTED line anywhere grants an exec/edit tool (ctx_shell/ctx_call/
# ctx_edit/ctx_execute) -- the allowlist stays read-only.
ST3_EXEC_LEAK="$(grep -h '^PERMITTED:' "$ROOT"/config/policies/*.md \
    | grep -Ec 'ctx_shell|ctx_call|ctx_edit|ctx_execute')"
if [[ "$ST3_PERMIT_OK" -eq 1 && "$ST3_EXEC_LEAK" -eq 0 ]]; then
    ok "ST3 MCP policies permit read-only ctx/tokensave, never exec/edit tools"
else
    bad "ST3 MCP policies permit read-only ctx/tokensave, never exec/edit tools" "permit_ok=$ST3_PERMIT_OK exec_leak=$ST3_EXEC_LEAK"
fi

echo "== agent + skill docs: exit-3, WebSearch, version (vfn T5/T6) =="

# ST4: both delegate agents document a `| 3 |` error row that classifies the
# exit-3 hidden failure into the REAL error classes (empty_output/quota/auth)
# and does NOT invent a phantom "backend" class.
ST4_OK=1
for f in agents/agy-delegate-code.md agents/agy-delegate-search.md; do
    row="$(grep '| 3 |' "$ROOT/$f")"
    [[ -n "$row" ]] || ST4_OK=0
    [[ "$row" == *"empty_output"* && "$row" == *"quota"* && "$row" == *"auth"* ]] || ST4_OK=0
    [[ "$row" == *"backend"* ]] && ST4_OK=0
done
# SKILL Common Mistakes carries an exit-3 symptom row too.
grep -qi 'exit 3' "$ROOT/skills/agy-delegate/SKILL.md" || ST4_OK=0
if [[ "$ST4_OK" -eq 1 ]]; then
    ok "ST4 exit-3 rows classify empty_output/quota/auth (no invented backend class)"
else
    bad "ST4 exit-3 rows classify empty_output/quota/auth (no invented backend class)" "ok=$ST4_OK"
fi

# ST5: the search agent surfaces WebSearch (in its tools: line), the SKILL has a
# WebSearch-preference Common Mistakes row, and there is ZERO residual agy-first
# framing ("prefer agy over websearch" / "do not use the native websearch")
# across the skill, search agent, /agy-search command, policy hook, and README.
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

# ST6: the version bumped to 1.3.0 in both the plugin manifest and the setup
# command, and NO stale 1.2.0/1.2.1 lingers in tracked json/md (excluding the
# beads DB export and the historical spec archive).
ST6_OK=1
grep -q '1.3.0' "$ROOT/.claude-plugin/plugin.json" || ST6_OK=0
grep -q '1.3.0' "$ROOT/.claude/commands/agy-setup.md" || ST6_OK=0
ST6_STALE="$(cd "$ROOT" && grep -rn '1\.2\.[01]' --include='*.json' --include='*.md' . \
    | grep -v '/.beads/' | grep -v 'docs/superpowers/specs' | wc -l)"
if [[ "$ST6_OK" -eq 1 && "$ST6_STALE" -eq 0 ]]; then
    ok "ST6 version 1.3.0 in manifest+setup, no stale 1.2.x"
else
    bad "ST6 version 1.3.0 in manifest+setup, no stale 1.2.x" "ok=$ST6_OK stale=$ST6_STALE"
fi

echo "== MCP tool-preference stanza gating (vfn T5) =="

# The bridge's stanza probe reads a fresh cache (~/.cache/agy-bridge-mcp), then
# the hint (~/.config/agy-delegate/config.json {"lean_ctx":bool,"tokensave":bool}),
# then the live agy mcp_config. We control it deterministically by writing the
# hint + clearing the cache. SAVE/RESTORE the (sandbox-HOME) hint+cache via an
# EXIT trap so a re-run never leaves stale probe state behind.
_T7_HINT="$HOME/.config/agy-delegate/config.json"; _T7_CACHE="$HOME/.cache/agy-bridge-mcp"
_t7_save(){ [[ -f "$_T7_HINT" ]] && cp "$_T7_HINT" "$_T7_HINT.t7bak"; [[ -f "$_T7_CACHE" ]] && cp "$_T7_CACHE" "$_T7_CACHE.t7bak"; }
_t7_restore(){ if [[ -f "$_T7_HINT.t7bak" ]]; then mv "$_T7_HINT.t7bak" "$_T7_HINT"; else rm -f "$_T7_HINT"; fi; if [[ -f "$_T7_CACHE.t7bak" ]]; then mv "$_T7_CACHE.t7bak" "$_T7_CACHE"; else rm -f "$_T7_CACHE"; fi; }
# Chain onto the existing cleanup trap so the temp sandbox is still removed.
trap '_t7_restore; cleanup' EXIT
_t7_save; mkdir -p "$(dirname "$_T7_HINT")"

# M1: hint says an MCP server is ON (lean_ctx=true) -> code delegation appends
# the TOOL PREFERENCE stanza into the echoed prompt.
printf '%s\n' '{"lean_ctx":true,"tokensave":false}' > "$_T7_HINT"; rm -f "$_T7_CACHE"
FAKE_AGY_ECHO_PROMPT=1 _run OUT RC bash "$BRIDGE" --type code -- "x"
if [[ "$OUT" == *"TOOL PREFERENCE"* ]]; then
    ok "M1 stanza present when an MCP server is on (code)"
else
    bad "M1 stanza present when an MCP server is on (code)" "rc=$RC out=${OUT:0:300}"
fi

# M2: hint says all MCP servers OFF -> no stanza appended (advisory text only
# fires when a server is actually available).
printf '%s\n' '{"lean_ctx":false,"tokensave":false}' > "$_T7_HINT"; rm -f "$_T7_CACHE"
FAKE_AGY_ECHO_PROMPT=1 _run OUT RC bash "$BRIDGE" --type code -- "x"
if [[ "$OUT" != *"TOOL PREFERENCE"* ]]; then
    ok "M2 stanza absent when all MCP servers off (code)"
else
    bad "M2 stanza absent when all MCP servers off (code)" "rc=$RC out=${OUT:0:300}"
fi

# M3: search delegation is excluded from the stanza even when a server is on --
# the search policy forbids every ctx_*/tokensave tool, so biasing toward them
# would be self-contradictory.
printf '%s\n' '{"lean_ctx":true}' > "$_T7_HINT"; rm -f "$_T7_CACHE"
FAKE_AGY_ECHO_PROMPT=1 _run OUT RC bash "$BRIDGE" --type search -- "x"
if [[ "$OUT" != *"TOOL PREFERENCE"* ]]; then
    ok "M3 no stanza for search delegation (excluded)"
else
    bad "M3 no stanza for search delegation (excluded)" "rc=$RC out=${OUT:0:300}"
fi

echo "== gemini_shim.sh: no stanza + --sandbox floor (vfn T4/T5) =="

# SH1: the shim NEVER appends the TOOL PREFERENCE stanza (stanza is a bridge-only
# concern; the shim serves metaswarm/octopus with their own policies).
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

# SH2: --sandbox read-only floor. Use the fake-agy argv-dump mode (env-gated,
# additive) to see the real argv agy is invoked with:
#   - default shim  -> --sandbox present (T4 non-yolo FS floor)
#   - --sandbox     -> --sandbox present
#   - yolo modes    -> --sandbox ABSENT (deliberately unrestricted)
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

# rc 0 = --sandbox found; rc non-0 = absent.
if [[ "$SH2_DEFAULT" -eq 0 && "$SH2_SANDBOX" -eq 0 && "$SH2_YOLO" -ne 0 && "$SH2_APPROVAL_YOLO" -ne 0 ]]; then
    ok "SH2 --sandbox present on read-only shim modes, absent on yolo"
else
    bad "SH2 --sandbox present on read-only shim modes, absent on yolo" "default=$SH2_DEFAULT sandbox=$SH2_SANDBOX yolo=$SH2_YOLO approval_yolo=$SH2_APPROVAL_YOLO"
fi

# SH3: T4 regression -- the shim's --version passthrough still exits 0 and prints
# a version string (fake-agy answers --version deterministically).
_run OUT RC bash "$SHIM" --version
if [[ "$RC" -eq 0 && "$OUT" == *"agy "* ]]; then
    ok "SH3 shim --version still exits 0 + prints version"
else
    bad "SH3 shim --version still exits 0 + prints version" "rc=$RC out=$OUT"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -eq 0 ]]; then
    exit 0
else
    exit 1
fi
