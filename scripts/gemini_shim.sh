#!/usr/bin/env bash
# gemini_shim.sh — Drop-in replacement for Google Gemini CLI, backed by agy (Antigravity CLI)
#
# Translates gemini CLI flags to agy invocations so that frameworks
# (Claude Octopus, Metaswarm) that call `gemini` automatically use agy instead.
#
# Supported call patterns:
#   Octopus:    gemini -m <model> -o text --approval-mode yolo [< stdin]
#               gemini -m <model> -p "" -o text --approval-mode yolo [< stdin]
#   Metaswarm:  gemini --yolo --output-format json --model <m> --include-directories <dir> <prompt>
#               gemini --sandbox --output-format json --model <m> <prompt>
#   Direct:     gemini -m <model> <prompt>  OR  echo <prompt> | gemini -m <model>
#
# Installation (as drop-in):
#   ln -sf /path/to/gemini_shim.sh ~/bin/gemini
#   # Ensure ~/bin precedes the real gemini on PATH

set -euo pipefail

if ! command -v agy &>/dev/null; then
    echo "ERROR: agy not found in PATH" >&2; exit 2
fi
AGY_BIN=$(command -v agy)
if command -v timeout &>/dev/null; then
    TIMEOUT_BIN="timeout"
elif command -v gtimeout &>/dev/null; then
    TIMEOUT_BIN="gtimeout"
else
    TIMEOUT_BIN=""
fi
STDIN_TIMEOUT="${GEMINI_SHIM_STDIN_TIMEOUT:-30}"
[[ "$STDIN_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || {
    echo "ERROR: GEMINI_SHIM_STDIN_TIMEOUT must be a positive integer (got '$STDIN_TIMEOUT')" >&2
    exit 2
}
# Bound on the main agy call (gemini_shim.sh's --version call gets its own
# short, non-configurable 10s bound — see below). agy ignores SIGTERM
# (observed, see scripts/agy_bridge.sh), so every bounded call below escalates
# via `-k 5` to SIGKILL; plain `timeout` would send the signal and then block
# forever waiting for a child that never dies.
SHIM_TIMEOUT="${GEMINI_SHIM_TIMEOUT:-600}"
[[ "$SHIM_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || {
    echo "ERROR: GEMINI_SHIM_TIMEOUT must be a positive integer (got '$SHIM_TIMEOUT')" >&2
    exit 2
}

# ── Model name mapping ────────────────────────────────────────────────────────
# Maps gemini CLI model names/aliases → agy model names.
# Mappings are in config/model-map.json — update there without touching scripts.
# Run `agy models` to see current agy model list.
map_model() {
    local m="$1"
    local map_file
    map_file="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)/../config/model-map.json"
    python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
print(d.get(sys.argv[2], sys.argv[2]))
" "$map_file" "$m"
}

# ── Parse gemini flags ────────────────────────────────────────────────────────
MODEL=""
OUTPUT_FORMAT="text"
APPROVAL_MODE=""
YOLO=0
SANDBOX=0
PRINT_FLAG=0
INCLUDE_DIRS=()
PROMPT_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--model)
            [[ $# -lt 2 ]] && { echo "ERROR: $1 requires a value" >&2; exit 2; }
            MODEL="$2"; shift 2 ;;
        --model=*)            MODEL="${1#--model=}"; shift ;;
        -o|--output-format)
            [[ $# -lt 2 ]] && { echo "ERROR: $1 requires a value" >&2; exit 2; }
            OUTPUT_FORMAT="$2"; shift 2 ;;
        --output-format=*)    OUTPUT_FORMAT="${1#--output-format=}"; shift ;;
        --approval-mode)
            [[ $# -lt 2 ]] && { echo "ERROR: $1 requires a value" >&2; exit 2; }
            APPROVAL_MODE="$2"; shift 2 ;;
        --approval-mode=*)    APPROVAL_MODE="${1#--approval-mode=}"; shift ;;
        --yolo)               YOLO=1; shift ;;
        --sandbox)            SANDBOX=1; shift ;;
        --include-directories)
            [[ $# -lt 2 ]] && { echo "ERROR: $1 requires a value" >&2; exit 2; }
            INCLUDE_DIRS+=("$2"); shift 2 ;;
        --include-directories=*) INCLUDE_DIRS+=("${1#--include-directories=}"); shift ;;
        -p)
            # -p "" means "print mode reading from stdin" (Octopus pattern)
            # -p <prompt> means prompt as value
            PRINT_FLAG=1
            if [[ $# -ge 2 && -n "${2:-}" ]]; then
                PROMPT_ARGS+=("$2"); shift 2
            else
                shift
                # consume the empty string arg if present
                [[ $# -ge 1 && "${1:-}" == "" ]] && shift || true
            fi ;;
        --print)              PRINT_FLAG=1; shift ;;
        --version)
            _V_RC=0
            if [[ -n "$TIMEOUT_BIN" ]]; then
                "$TIMEOUT_BIN" -k 5 10 "$AGY_BIN" --version || _V_RC=$?
            else
                "$AGY_BIN" --version || _V_RC=$?
            fi
            if [[ "$_V_RC" -eq 124 || "$_V_RC" -eq 137 ]]; then
                echo "ERROR: agy --version timeout after 10s" >&2
                exit 124
            fi
            exit "$_V_RC" ;;
        --help|-h)
            cat <<'HELP'
gemini (agy shim) — drop-in Gemini CLI backed by agy (Antigravity CLI)

Usage:
  gemini [OPTIONS] [prompt]
  echo "prompt" | gemini [OPTIONS]

Options (translated to agy equivalents):
  -m / --model <name>              Model name (mapped to agy model list)
  -o / --output-format text|json   Output format (json wraps in usageMetadata envelope)
  --approval-mode yolo             Auto-approve all tools (→ --dangerously-skip-permissions)
  --yolo                           Same as --approval-mode yolo
  --sandbox                        Read-only mode (omits --dangerously-skip-permissions)
  --include-directories <dir>      Add directory to agy workspace (→ --add-dir)
  -p [prompt]                      Print mode (non-interactive)
  --version                        Show agy version

HELP
            exit 0 ;;
        # Silently skip unknown flags to maximise compatibility
        --no-*)               shift ;;
        --[a-z]*)             [[ $# -ge 2 && "${2:-}" != -* ]] && shift 2 || shift ;;
        --)                   shift; PROMPT_ARGS+=("$@"); break ;;
        -*)                   shift ;;
        *)                    PROMPT_ARGS+=("$1"); shift ;;
    esac
done

# ── Map model name ────────────────────────────────────────────────────────────
if [[ -n "$MODEL" ]]; then
    MODEL=$(map_model "$MODEL")
fi

# ── Temp workspace (isolates session, avoids conversation bleed) ──────────────
WORK_DIR=$(mktemp -d -t "gemini-shim.XXXXXX")
PROMPT_FILE="$WORK_DIR/prompt"
STDOUT_FILE="$WORK_DIR/stdout"
STDERR_FILE="$WORK_DIR/stderr"
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT QUIT TERM

# ── Tool restriction policy via GEMINI.md ────────────────────────────────────
# --yolo / --approval-mode yolo: full tool access (implement mode)
# --sandbox: read-only tools only (review mode)
# default: read + search (code analysis)
_SHIM_POLICY_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)/../config/policies"
if [[ "$YOLO" -eq 1 || "$APPROVAL_MODE" == "yolo" ]]; then
    _SHIM_POLICY="$_SHIM_POLICY_DIR/shim-yolo.md"
elif [[ "$SANDBOX" -eq 1 ]]; then
    _SHIM_POLICY="$_SHIM_POLICY_DIR/shim-sandbox.md"
else
    _SHIM_POLICY="$_SHIM_POLICY_DIR/shim-default.md"
fi
cat "$_SHIM_POLICY" > "$WORK_DIR/GEMINI.md" \
    || { echo "ERROR: policy file missing: $_SHIM_POLICY" >&2; exit 2; }

# ── Read prompt ───────────────────────────────────────────────────────────────
if [[ ${#PROMPT_ARGS[@]} -gt 0 ]]; then
    printf '%s\n' "${PROMPT_ARGS[@]}" > "$PROMPT_FILE"
elif [[ ! -t 0 ]]; then
    if [[ -n "$TIMEOUT_BIN" ]]; then
        "$TIMEOUT_BIN" "$STDIN_TIMEOUT" cat > "$PROMPT_FILE" || {
            echo "ERROR: stdin read timed out after ${STDIN_TIMEOUT}s" >&2; exit 2
        }
    else
        cat > "$PROMPT_FILE"
    fi
else
    echo "ERROR: no prompt (no stdin and no positional args)" >&2; exit 2
fi

if ! grep -q '[^[:space:]]' "$PROMPT_FILE"; then
    echo "ERROR: empty prompt" >&2; exit 2
fi

# ── Embed the prompt into GEMINI.md (agy auto-loads it; no read_file tool,
#    off argv/ps, no ARG_MAX cap) — mirrors scripts/agy_bridge.sh. ──
{ printf '\n\n---\nTASK:\n' >> "$WORK_DIR/GEMINI.md" \
    && cat "$PROMPT_FILE" >> "$WORK_DIR/GEMINI.md" \
    && chmod 600 "$WORK_DIR/GEMINI.md"; } \
    || { echo "ERROR: failed to embed prompt into GEMINI.md" >&2; exit 2; }
AGY_POINTER='Complete the TASK described in your GEMINI.md context. Output only the result.'

# ── Build agy command ─────────────────────────────────────────────────────────
AGY_ARGS=(--print "$AGY_POINTER" --add-dir "$WORK_DIR")

# WU0(B): --sandbox is a real API-level FS floor (path-confinement to --add-dir).
# Add it to the read-only shim modes (sandbox/default), granting the CWD so
# workspace reads still work; yolo stays unrestricted (--dangerously-skip-permissions).
# Read-only-ness itself remains prompt-side (the shim-* policies permit no write tool);
# --sandbox blocks ESCAPE outside the granted dirs.
# WORK_DIR is re-granted last so it stays the terminal --add-dir (where GEMINI.md
# is auto-loaded), mirroring agy_bridge.sh's --sandbox …--add-dir "$WORK_DIR" order.
if [[ "$YOLO" -ne 1 && "$APPROVAL_MODE" != "yolo" ]]; then
    AGY_ARGS+=(--sandbox --add-dir "$PWD" --add-dir "$WORK_DIR")
fi

[[ -n "$MODEL" ]] && AGY_ARGS+=(--model "$MODEL")

# --yolo or --approval-mode yolo → auto-approve all tool calls
if [[ "$YOLO" -eq 1 || "$APPROVAL_MODE" == "yolo" ]]; then
    AGY_ARGS+=(--dangerously-skip-permissions)
fi

# --include-directories → --add-dir (one per directory)
for dir in "${INCLUDE_DIRS[@]}"; do
    AGY_ARGS+=(--add-dir "$dir")
done

# ── Run agy (prompt embedded in the 0600 GEMINI.md; only the static pointer
#    is passed as --print's value — avoids ARG_MAX and keeps ps/argv clean) ──
START=$SECONDS
EXIT_CODE=0
set +e
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
set -e
DURATION=$(( SECONDS - START ))

# ── Handle errors ─────────────────────────────────────────────────────────────
if [[ "$EXIT_CODE" -eq 137 && "$DURATION" -lt "$SHIM_TIMEOUT" ]]; then
    # A 137 (SIGKILL) landing BEFORE our own $SHIM_TIMEOUT bound cannot be the -k
    # escalation above -- that can only fire at/after $SHIM_TIMEOUT elapses. It's
    # an external kill (OOM killer, `kill -9`, cgroup/container preemption).
    # Report it distinctly: "raise the timeout" is useless advice against an OOM.
    printf 'ERROR: agy killed (signal 9) after %ds, before its %ds bound -- possible OOM or external kill: %s\n' \
        "$DURATION" "$SHIM_TIMEOUT" "$(cat "$STDERR_FILE" 2>/dev/null || true)" >&2
    exit "$EXIT_CODE"
elif [[ "$EXIT_CODE" -eq 124 || "$EXIT_CODE" -eq 137 ]]; then
    echo "ERROR: agy timeout after ${SHIM_TIMEOUT}s" >&2
    exit 124
elif [[ "$EXIT_CODE" -ne 0 ]]; then
    cat "$STDERR_FILE" >&2
    exit "$EXIT_CODE"
fi

# Hidden failure: agy exited 0 but produced NO output. agy exits 0 with empty stdout
# on quota RESOURCE_EXHAUSTED / 429 (and silent backend/lock errors). Metaswarm reads
# this shim's exit code — fail loud so its gate trips instead of consuming an empty
# "success" envelope and merging unchanged state. The failure payload is NEVER
# success-shaped: on JSON we emit an {"error":...} envelope (no "response" key); on
# text the reason goes to stderr with 0-byte stdout. Full stderr is the reason; a
# token match only CLASSIFIES it (auth/backend errors are not swallowed as "quota").
if [[ ! -s "$STDOUT_FILE" ]]; then
    _reason="$(cat "$STDERR_FILE" 2>/dev/null)"
    [[ -n "$_reason" ]] || _reason="agy returned empty output (exit 0, no stdout)"
    _class="empty_output"
    case "$_reason" in
        *RESOURCE_EXHAUSTED*|*429*|*[Qq]uota*)   _class="quota" ;;
        *[Aa]uth*|*UNAUTHENTICATED*)             _class="auth" ;;
    esac
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        python3 -c "
import json, sys
print(json.dumps({'error': {'message': sys.argv[1], 'class': sys.argv[2]}}))
" "$_reason" "$_class"
    fi
    printf 'ERROR: agy returned empty output [%s]: %s\n' "$_class" "$_reason" >&2
    exit 3
fi

RESPONSE=$(cat "$STDOUT_FILE")

# ── Output ────────────────────────────────────────────────────────────────────
# JSON envelope emitted via python3 (not jq): the bridge dropped jq in b4b7503, and a
# limited `jq` shim on PATH (rejecting --arg) would otherwise break metaswarm's JSON.
if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    # usageMetadata token counts are null — agy does not expose real usage (see 73f931c).
    python3 -c "
import json, sys
print(json.dumps({
    'response': sys.stdin.read(),
    'usageMetadata': {'promptTokenCount': None, 'candidatesTokenCount': None, 'totalTokenCount': None},
    'model': 'agy',
    'duration_seconds': int(sys.argv[1]),
}))
" "$DURATION" < "$STDOUT_FILE"
else
    printf '%s\n' "$RESPONSE"
fi
