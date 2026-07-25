#!/usr/bin/env bash
# agy_bridge.sh — Bridge for Google Antigravity CLI (agy)
#
# Usage:
#   echo "prompt" | agy_bridge.sh [OPTIONS]
#   agy_bridge.sh [OPTIONS] -- "prompt text"

set -euo pipefail

# ── Dependency check ─────────────────────────────────────────────────────────
if ! command -v agy &>/dev/null; then
    echo "ERROR: agy not found in PATH (expected at ~/.local/bin/agy)" >&2; exit 2
fi
AGY_BIN=$(command -v agy)
if command -v timeout &>/dev/null; then
    TIMEOUT_BIN="timeout"
elif command -v gtimeout &>/dev/null; then
    TIMEOUT_BIN="gtimeout"
else
    echo "ERROR: timeout/gtimeout not found in PATH (install coreutils)" >&2; exit 2
fi

# ── Defaults ─────────────────────────────────────────────────────────────────
TYPE="code"
MODEL=""
TIMEOUT=""
STDIN_TIMEOUT=30
LOG_FILE=""
JSON_OUTPUT=0
VERBOSE=0
DIGEST=0
DIGEST_WARN_CHARS=2000
PROMPT_ARGS=()

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --type)
            [[ $# -lt 2 ]] && { echo "ERROR: --type requires a value" >&2; exit 2; }
            TYPE="$2"; shift 2 ;;
        --model)
            [[ $# -lt 2 ]] && { echo "ERROR: --model requires a value" >&2; exit 2; }
            MODEL="$2"; shift 2 ;;
        --timeout)
            [[ $# -lt 2 ]] && { echo "ERROR: --timeout requires a value" >&2; exit 2; }
            [[ "$2" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: --timeout must be a positive integer" >&2; exit 2; }
            TIMEOUT="$2"; shift 2 ;;
        --stdin-timeout)
            [[ $# -lt 2 ]] && { echo "ERROR: --stdin-timeout requires a value" >&2; exit 2; }
            [[ "$2" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: --stdin-timeout must be a positive integer" >&2; exit 2; }
            STDIN_TIMEOUT="$2"; shift 2 ;;
        --log-file)
            [[ $# -lt 2 ]] && { echo "ERROR: --log-file requires a value" >&2; exit 2; }
            LOG_FILE="$2"; shift 2 ;;
        --json)    JSON_OUTPUT=1; shift ;;
        --verbose) VERBOSE=1; shift ;;
        --digest)  DIGEST=1; shift ;;
        --digest-warn-chars)
            [[ $# -lt 2 ]] && { echo "ERROR: --digest-warn-chars requires a value" >&2; exit 2; }
            [[ "$2" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: --digest-warn-chars must be a positive integer" >&2; exit 2; }
            DIGEST_WARN_CHARS="$2"; shift 2 ;;
        --types)
            printf '%-12s %-30s %s\n' 'type' 'model' 'timeout'
            printf '%-12s %-30s %s\n' 'search' 'gemini-*-flash-high (latest)' '300s'
            printf '%-12s %-30s %s\n' 'code' 'gemini-*-pro-high (latest)' '600s'
            printf '%-12s %-30s %s\n' 'analysis' 'gemini-*-pro-high (latest)' '600s'
            printf '%-12s %-30s %s\n' 'review' 'gemini-*-pro-high (latest)' '600s'
            printf '%-12s %-30s %s\n' 'implement' 'gemini-*-pro-high (latest)' '600s'
            exit 0 ;;
        --help)
            cat <<'HELP'
agy_bridge.sh — Bridge for Google Antigravity CLI (agy)

Usage:
  echo "prompt" | agy_bridge.sh [OPTIONS]
  agy_bridge.sh [OPTIONS] -- "prompt text"

Options:
  --type search|code|review|analysis|implement
  --model "model name"       (see: agy models)
  --timeout N                seconds (default: 300 search, 600 other)
  --stdin-timeout N          seconds for stdin read (default: 30)
  --log-file PATH            write verbose metadata to file instead of stderr
  --json                     output JSON envelope
  --digest                   append a digest-only output contract (compressed
                             reply: key findings + file:line, no raw echoes)
  --digest-warn-chars N      warn on stderr if a --digest reply exceeds N chars
                             (default: 2000; never truncates)
  --verbose                  diagnostics to stderr (or --log-file)
  --types                    list type/model/timeout table
  --help                     show this message
  --                         treat remaining args as prompt text

  Optional: ~/.config/agy-delegate/config.json {"lean_ctx":bool,"tokensave":bool}
  (written by /agy-setup) hints MCP availability; live-probed if absent.

HELP
            exit 0 ;;
        --)        shift; PROMPT_ARGS+=("$@"); break ;;
        --*)       echo "ERROR: unknown flag: $1" >&2; exit 2 ;;
        *)         PROMPT_ARGS+=("$1"); shift ;;
    esac
done

# ── Validate type ─────────────────────────────────────────────────────────────
TYPE_SAFE=$(printf '%s' "$TYPE" | tr -dc '[:alnum:]-_')
case "$TYPE_SAFE" in
    search|code|review|analysis|implement) TYPE="$TYPE_SAFE" ;;
    *) echo "ERROR: unknown --type '${TYPE_SAFE}'; expected search|code|review|analysis|implement" >&2; exit 2 ;;
esac

# ── Fetch/cache live model list ───────────────────────────────────────────────
CACHE_FILE="$HOME/.cache/agy-bridge-models"
_agy_models=""
if [[ ! -s "$CACHE_FILE" ]] || [[ -n "$(find "$CACHE_FILE" -mmin +60 2>/dev/null)" ]]; then
    _agy_models=$("$AGY_BIN" models </dev/null 2>/dev/null) || {
        echo "ERROR: failed to retrieve model list from agy" >&2; exit 2
    }
    mkdir -p "${CACHE_FILE%/*}" 2>/dev/null || true
    printf '%s' "$_agy_models" > "$CACHE_FILE.tmp.$$" \
        && mv "$CACHE_FILE.tmp.$$" "$CACHE_FILE" || true
    chmod 600 "$CACHE_FILE" 2>/dev/null || true
fi
VALID_MODELS="${_agy_models:-}"
if [[ -z "$VALID_MODELS" ]]; then
    VALID_MODELS=$(cat "$CACHE_FILE" 2>/dev/null) || true
fi
[[ -n "$VALID_MODELS" ]] || { echo "ERROR: failed to retrieve model list from agy" >&2; exit 2; }

# ── Model auto-selection / validation ─────────────────────────────────────────
if [[ -z "$MODEL" ]]; then
    case "$TYPE" in
        search) MODEL=$(printf '%s\n' "$VALID_MODELS" | grep -E '^gemini-[0-9.]+-flash-high$' | sort -V | tail -1) || true ;;
        *)      MODEL=$(printf '%s\n' "$VALID_MODELS" | grep -E '^gemini-[0-9.]+-pro-high$' | sort -V | tail -1) || true ;;
    esac
    [[ -n "$MODEL" ]] || { echo "ERROR: no gemini model for --type '$TYPE' in agy models" >&2; exit 2; }
else
    if ! printf '%s\n' "$VALID_MODELS" | grep -qxF "$MODEL"; then
        echo "ERROR: unknown --model '${MODEL}'; run 'agy models' for valid names" >&2; exit 2
    fi
fi

# ── Default timeout ───────────────────────────────────────────────────────────
if [[ -z "$TIMEOUT" ]]; then
    case "$TYPE" in
        search) TIMEOUT=300 ;;
        *)      TIMEOUT=600 ;;
    esac
fi

# ── Temp files ───────────────────────────────────────────────────────────────
WORK_DIR=$(mktemp -d -t "agy-bridge.XXXXXX")
PROMPT_FILE="$WORK_DIR/prompt"
STDOUT_FILE="$WORK_DIR/stdout"
STDERR_FILE="$WORK_DIR/stderr"
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT QUIT TERM

# ── Per-type tool restrictions via GEMINI.md ──────────────────────────────────
# agy reads GEMINI.md from CWD as binding instructions. Bridge runs agy from
# WORK_DIR so the restriction file is always the authoritative context source.
# Prompts must be self-contained; orchestrators embed needed code in the prompt.
POLICY_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)/../config/policies"
case "$TYPE" in
    search)        _POLICY_FILE="$POLICY_DIR/search.md" ;;
    review|analysis) _POLICY_FILE="$POLICY_DIR/review-analysis.md" ;;
    code)          _POLICY_FILE="$POLICY_DIR/code.md" ;;
    implement)     _POLICY_FILE="$POLICY_DIR/implement.md" ;;
esac
cat "$_POLICY_FILE" > "$WORK_DIR/GEMINI.md" \
    || { echo "ERROR: policy file missing: $_POLICY_FILE" >&2; exit 2; }

# ── Read prompt ───────────────────────────────────────────────────────────────
if [[ ${#PROMPT_ARGS[@]} -gt 0 ]]; then
    printf '%s\n' "${PROMPT_ARGS[@]}" > "$PROMPT_FILE"
elif [[ ! -t 0 ]]; then
    "$TIMEOUT_BIN" "$STDIN_TIMEOUT" cat > "$PROMPT_FILE" || {
        echo "ERROR: stdin read timed out after ${STDIN_TIMEOUT}s" >&2; exit 2
    }
else
    echo "ERROR: no prompt (no stdin, no -- args)" >&2; exit 2
fi

# ── Search prefix ─────────────────────────────────────────────────────────────
if [[ "$TYPE" == "search" ]] && ! grep -q "search_web" "$PROMPT_FILE"; then
    printf 'Use your search_web tool to answer this query. Cite sources with URLs.\n\n' \
        > "$WORK_DIR/prefix.tmp"
    cat "$PROMPT_FILE" >> "$WORK_DIR/prefix.tmp"
    mv "$WORK_DIR/prefix.tmp" "$PROMPT_FILE"
fi

# ── Digest output contract (appended LAST) ────────────────────────────────────
# Placed after the prompt so the constraint lands at the end — Gemini can drop a
# negative/format constraint that appears too early in a long prompt. The digest
# instruction is the biggest cost lever for bulk delegation: it collapses the reply
# to a compressed digest instead of a raw dump, keeping the caller's context lean.
if [[ "$DIGEST" -eq 1 ]]; then
    printf '\n\n---\nOUTPUT CONTRACT (digest): Return ONLY a compressed digest — key findings, decisions, and file:line references. Do NOT echo file contents or restate the input. Omit preamble and narration.\n' \
        >> "$PROMPT_FILE"
fi

# ── Verbose metadata output (metadata only — no prompt content) ───────────────
if [[ "$VERBOSE" -eq 1 ]]; then
    _verbose_msg=$(printf '[agy_bridge] type=%s model=%s timeout=%ss\n' "$TYPE" "$MODEL" "$TIMEOUT")
    if [[ -n "$LOG_FILE" ]]; then
        printf '%s\n' "$_verbose_msg" >> "$LOG_FILE"
    else
        printf '%s\n' "$_verbose_msg" >&2
    fi
fi

# ── Embed the assembled prompt into GEMINI.md (agy auto-loads it; no read_file
#    tool needed, so this works even under search.md's read_file restriction).
#    Keeps the prompt OFF argv/ps and lifts the ARG_MAX single-arg cap. ──
{ printf '\n\n---\nTASK:\n' >> "$WORK_DIR/GEMINI.md" \
    && cat "$PROMPT_FILE" >> "$WORK_DIR/GEMINI.md" \
    && chmod 600 "$WORK_DIR/GEMINI.md"; } \
    || { echo "ERROR: failed to embed prompt into GEMINI.md" >&2; exit 2; }

# ── MCP-server autodetect (cached 60-min, config-hint fast-path, live fallback) ─
# Bias agy toward lean-ctx/tokensave reads ONLY for MCP-permitted types. The
# stanza is advisory GEMINI.md text — it does NOT relax --sandbox/--add-dir.
_MCP_LEANCTX=0; _MCP_TOKENSAVE=0
if command -v python3 >/dev/null 2>&1; then
    _MCP_CACHE="$HOME/.cache/agy-bridge-mcp"
    if [[ -s "$_MCP_CACHE" ]] && [[ -z "$(find "$_MCP_CACHE" -mmin +60 2>/dev/null)" ]]; then
        _MCP_LEANCTX=$(sed -n '1p' "$_MCP_CACHE" 2>/dev/null)
        _MCP_TOKENSAVE=$(sed -n '2p' "$_MCP_CACHE" 2>/dev/null)
    else
        read _MCP_LEANCTX _MCP_TOKENSAVE < <(python3 - \
            "$HOME/.config/agy-delegate/config.json" \
            "$HOME/.gemini/antigravity-cli/mcp_config.json" <<'PY'
import sys, json, os
hint, live = sys.argv[1], sys.argv[2]
lc = ts = False
def rd(p):
    try: return json.load(open(p))
    except Exception: return None
d = rd(hint) if os.path.exists(hint) else None
if isinstance(d, dict):
    lc = d.get('lean_ctx') is True; ts = d.get('tokensave') is True
else:
    d = rd(live) if os.path.exists(live) else None
    if isinstance(d, dict):
        s = d.get('mcpServers', {}) or {}
        lc = 'lean-ctx' in s; ts = 'tokensave' in s
print(f"{int(lc)} {int(ts)}")
PY
)
        _MCP_LEANCTX="${_MCP_LEANCTX:-0}"; _MCP_TOKENSAVE="${_MCP_TOKENSAVE:-0}"
        mkdir -p "${_MCP_CACHE%/*}" 2>/dev/null || true
        printf '%s\n%s\n' "$_MCP_LEANCTX" "$_MCP_TOKENSAVE" > "$_MCP_CACHE.tmp.$$" \
            && mv "$_MCP_CACHE.tmp.$$" "$_MCP_CACHE" 2>/dev/null || true
        chmod 600 "$_MCP_CACHE" 2>/dev/null || true
    fi
fi
# MCP-permitted types = the SAME $TYPE the policy case uses; search + shim excluded.
if [[ "$TYPE" =~ ^(code|review|analysis|implement)$ ]] \
   && { [[ "$_MCP_LEANCTX" == "1" ]] || [[ "$_MCP_TOKENSAVE" == "1" ]]; }; then
    printf '\n---\nTOOL PREFERENCE: when reading files or inspecting code structure, prefer the lean-ctx tools (ctx_read/ctx_search) and tokensave_context over raw full-file dumps — they are token-efficient. Standard file tools remain available within your sandbox.\n' \
        >> "$WORK_DIR/GEMINI.md"
fi
AGY_POINTER='Complete the TASK described in your GEMINI.md context. Output only the result.'

# ── Run agy ──────────────────────────────────────────────────────────────────
# Run from WORK_DIR so agy reads the type-specific GEMINI.md tool restrictions.
# Prompt is embedded in the 0600 GEMINI.md; only the static pointer is passed as
# the --print value, so it still never appears in ps/proc/cmdline, and there is
# no ARG_MAX single-arg cap on prompt size.
START=$SECONDS
EXIT_CODE=0
set +e
AGY_FLAGS=(--print "$AGY_POINTER" --sandbox --model "$MODEL" --add-dir "$WORK_DIR")
if [[ "${AGY_SKIP_PERMISSIONS:-0}" == "1" ]]; then
    echo "WARNING: AGY_SKIP_PERMISSIONS=1 — running with --dangerously-skip-permissions" >&2
    AGY_FLAGS+=(--dangerously-skip-permissions)
fi
( cd "$WORK_DIR" && "$TIMEOUT_BIN" "$TIMEOUT" "$AGY_BIN" \
    "${AGY_FLAGS[@]}" \
    > "$STDOUT_FILE" \
    2> "$STDERR_FILE" )
EXIT_CODE=$?
set -e
DURATION=$(( SECONDS - START ))

# ── Handle errors ─────────────────────────────────────────────────────────────
if [[ "$EXIT_CODE" -eq 124 ]]; then
    if [[ "$JSON_OUTPUT" -eq 1 ]]; then
        python3 -c "
import json, sys
print(json.dumps({'success':False,'model_used':sys.argv[1],'type':sys.argv[2],'duration_seconds':int(sys.argv[3]),'error':sys.argv[4]}))
" "$MODEL" "$TYPE" "$DURATION" "Timeout after ${TIMEOUT}s"
    else
        printf 'ERROR: agy timeout after %ds\n' "$TIMEOUT" >&2
    fi
    exit 124
elif [[ "$EXIT_CODE" -ne 0 ]]; then
    if [[ "$JSON_OUTPUT" -eq 1 ]]; then
        python3 -c "
import json, sys
print(json.dumps({'success':False,'model_used':sys.argv[1],'type':sys.argv[2],'duration_seconds':int(sys.argv[3]),'error':open(sys.argv[4]).read()}))
" "$MODEL" "$TYPE" "$DURATION" "$STDERR_FILE" || true
    else
        printf 'ERROR: agy exit %d: %s\n' "$EXIT_CODE" "$(cat "$STDERR_FILE" 2>/dev/null || true)" >&2
    fi
    exit "$EXIT_CODE"
elif [[ ! -s "$STDOUT_FILE" ]]; then
    # Hidden failure: agy exited 0 but produced NO output. Most commonly quota
    # exhaustion — agy exits 0 with empty stdout on RESOURCE_EXHAUSTED / 429.
    # Primary signal is empty-stdout itself (cause-independent: also catches silent
    # backend/lock errors). Secondary: the FULL captured stderr becomes the reason;
    # a token match only CLASSIFIES it (never replaces the message, so auth/backend
    # errors aren't swallowed under a "quota" label).
    _reason="$(cat "$STDERR_FILE" 2>/dev/null)"
    [[ -n "$_reason" ]] || _reason="agy returned empty output (exit 0, no stdout)"
    _class="empty_output"
    case "$_reason" in
        *RESOURCE_EXHAUSTED*|*429*|*[Qq]uota*)   _class="quota" ;;
        *[Aa]uth*|*UNAUTHENTICATED*)             _class="auth" ;;
    esac
    if [[ "$JSON_OUTPUT" -eq 1 ]]; then
        python3 -c "
import json, sys
print(json.dumps({'success':False,'model_used':sys.argv[1],'type':sys.argv[2],'duration_seconds':int(sys.argv[3]),'error':sys.argv[4],'error_class':sys.argv[5]}))
" "$MODEL" "$TYPE" "$DURATION" "$_reason" "$_class"
    else
        printf 'ERROR: agy returned empty output [%s]: %s\n' "$_class" "$_reason" >&2
    fi
    exit 3
fi

# ── Digest dump-size warning (metadata only — never truncates) ────────────────
# Only when --digest was requested: a dump-sized reply means the digest contract
# was ignored and the cost lever was lost. Warn (don't alter the response).
if [[ "$DIGEST" -eq 1 ]]; then
    _resp_chars=$(wc -c < "$STDOUT_FILE" | tr -d '[:space:]')
    if [[ "$_resp_chars" -gt "$DIGEST_WARN_CHARS" ]]; then
        printf '[agy_bridge] WARNING: --digest reply is %s chars (> %s) — digest contract may have been ignored\n' \
            "$_resp_chars" "$DIGEST_WARN_CHARS" >&2
    fi
fi

# ── Output ────────────────────────────────────────────────────────────────────
if [[ "$JSON_OUTPUT" -eq 1 ]]; then
    python3 -c "
import json, sys
print(json.dumps({'success':True,'model_used':sys.argv[1],'type':sys.argv[2],'duration_seconds':int(sys.argv[3]),'response':open(sys.argv[4]).read()}))
" "$MODEL" "$TYPE" "$DURATION" "$STDOUT_FILE"
else
    cat "$STDOUT_FILE"
fi
