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

# S6: model-map mappings (flash -> Gemini 3.6 Flash (High); sonnet key purged)
S6_FLASH="$(python3 -c 'import json; d=json.load(open("config/model-map.json")); print(d.get("flash"))')"
if [[ "$S6_FLASH" == "Gemini 3.6 Flash (High)" ]]; then
    ok "S6 model-map resolves flash alias correctly"
else
    bad "S6 model-map resolves flash alias correctly" "flash=$S6_FLASH"
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

# R4: gemini_shim.sh -m flash still maps to "Gemini 3.6 Flash (High)" post map-purge
# (reuses the SH2 FAKE_AGY_DUMP_ARGV harness defined below, in the
# "gemini_shim.sh: no stanza + --sandbox floor" section).
R4_DUMP="$SANDBOX/purge_argv.log"
: > "$R4_DUMP"
FAKE_AGY_DUMP_ARGV="$R4_DUMP" _run OUT RC bash "$SHIM" -m flash -p x
R4_MODEL_VAL="$(awk '/^--model$/{getline; print; exit}' "$R4_DUMP")"
if [[ "$R4_MODEL_VAL" == "Gemini 3.6 Flash (High)" ]]; then
    ok "R4 gemini_shim.sh -m flash still maps to Gemini 3.6 Flash (High) (purge-guard)"
else
    bad "R4 gemini_shim.sh -m flash still maps to Gemini 3.6 Flash (High) (purge-guard)" "argv=$(cat "$R4_DUMP")"
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

# T2 large-prompt (no ARG_MAX).
FILLER="$(printf 'a%.0s' $(seq 1 131200))"
BIGPROMPT="HEADSENTINEL${FILLER}TAILSENTINEL"
OUT="$(printf '%s' "$BIGPROMPT" | FAKE_AGY_ECHO_PROMPT=1 bash "$BRIDGE" --type code 2>&1)"; RC=$?
if [[ "$RC" -eq 0 && "$OUT" == *"HEADSENTINEL"* && "$OUT" == *"TAILSENTINEL"* && "$OUT" != *"Argument list too long"* ]]; then
    ok "T2 large (>131072B) prompt delivered intact, no ARG_MAX error"
else
    bad "T2 large (>131072B) prompt delivered intact, no ARG_MAX error" "rc=$RC out_len=${#OUT} out=${OUT:0:200}..."
fi

# T3 empty-prompt.
_run OUT RC bash "$BRIDGE" --type code -- ""
if [[ "$RC" -ne 0 ]]; then
    ok "T3 empty prompt -> non-zero exit (no silent success)"
else
    bad "T3 empty prompt -> non-zero exit (no silent success)" "rc=$RC out=$OUT"
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

# AD2: --add-dir with a non-directory path is rejected at parse time (exit 2)
# by the -d guard BEFORE the cd fallback ever runs. Asserted via EXACT output
# match (not substring): if the -d guard is dropped, the cd fallback still
# rejects the path but leaks an extra "cd: ...: No such file or directory"
# line to stderr first — an exact match catches that, a substring match would not.
AD2_BAD="$SANDBOX/add-dir-missing"
_run OUT RC bash "$BRIDGE" --type code --add-dir "$AD2_BAD" -- "hi"
if [[ "$RC" -eq 2 && "$OUT" == "ERROR: --add-dir '$AD2_BAD' is not a directory" ]]; then
    ok "AD2 --add-dir rejects non-directory path via -d guard (exit 2, no cd leak)"
else
    bad "AD2 --add-dir rejects non-directory path via -d guard (exit 2, no cd leak)" "rc=$RC out=$OUT"
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

# ST6: version bumped to 1.5.0 in manifest+setup; no stale 1.2.x/1.3.x/1.4.x in
# tracked json/md (excluding beads export, spec archive, and the legacy
# agy-uninstall.md command doc which keeps its own version line).
ST6_OK=1
grep -q '1.5.0' "$ROOT/.claude-plugin/plugin.json" || ST6_OK=0
grep -q '1.5.0' "$ROOT/.claude/commands/agy-setup.md" || ST6_OK=0
ST6_STALE="$(cd "$ROOT" && grep -rn '1\.[234]\.[0-9]' --include='*.json' --include='*.md' . \
    | grep -v '/.beads/' | grep -v 'docs/superpowers/specs' \
    | grep -v 'agy-uninstall.md' | wc -l)"
if [[ "$ST6_OK" -eq 1 && "$ST6_STALE" -eq 0 ]]; then
    ok "ST6 version 1.5.0 in manifest+setup, no stale 1.2.x/1.3.x/1.4.x"
else
    bad "ST6 version 1.5.0 in manifest+setup, no stale 1.2.x/1.3.x/1.4.x" "ok=$ST6_OK stale=$ST6_STALE"
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

echo
echo "PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -eq 0 ]]; then
    exit 0
else
    exit 1
fi
