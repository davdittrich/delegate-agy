#!/usr/bin/env bash
# agy_bridge.sh — Bridge for Google Antigravity CLI (agy)
#
# Usage:
#   echo "prompt" | agy_bridge.sh [OPTIONS]
#   agy_bridge.sh [OPTIONS] -- "prompt text"
#
# Options:
#   --type search|code|review|analysis
#   --model "model name"       (see: agy models)
#   --timeout N                seconds (default: 300 search, 600 other)
#   --json                     output JSON envelope
#   --verbose                  diagnostics to stderr
#   --help                     show this message
#   --                         treat remaining args as prompt text

set -euo pipefail

# ── Dependency check ─────────────────────────────────────────────────────────
if ! command -v agy &>/dev/null; then
    echo "ERROR: agy not found in PATH (expected at ~/.local/bin/agy)" >&2; exit 2
fi
_require_jq() {
    command -v jq &>/dev/null || {
        echo "ERROR: jq not found in PATH (required for --json output)" >&2; exit 2
    }
}

# ── Defaults ─────────────────────────────────────────────────────────────────
TYPE="code"
MODEL=""
TIMEOUT=""
JSON_OUTPUT=0
VERBOSE=0
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
        --json)    JSON_OUTPUT=1; shift ;;
        --verbose) VERBOSE=1; shift ;;
        --types)
            printf '%-12s %-30s %s\n' 'type' 'model' 'timeout'
            printf '%-12s %-30s %s\n' 'search' 'Gemini 3.5 Flash (High)' '300s'
            printf '%-12s %-30s %s\n' 'code' 'Gemini 3.1 Pro (High)' '600s'
            printf '%-12s %-30s %s\n' 'analysis' 'Gemini 3.1 Pro (High)' '600s'
            printf '%-12s %-30s %s\n' 'review' 'Gemini 3.1 Pro (High)' '600s'
            exit 0 ;;
        --help)
            grep '^#' "$0" | head -20 | sed 's/^# \?//'
            exit 0 ;;
        --)        shift; PROMPT_ARGS+=("$@"); break ;;
        --*)       echo "ERROR: unknown flag: $1" >&2; exit 2 ;;
        *)         PROMPT_ARGS+=("$1"); shift ;;
    esac
done

# ── Validate type ─────────────────────────────────────────────────────────────
case "$TYPE" in
    search|code|review|analysis) ;;
    *) echo "WARNING: unknown --type '$TYPE'; defaulting to code" >&2; TYPE="code" ;;
esac

# ── Model auto-selection ──────────────────────────────────────────────────────
if [[ -z "$MODEL" ]]; then
    case "$TYPE" in
        search)   MODEL="Gemini 3.5 Flash (High)" ;;
        review)   MODEL="Gemini 3.1 Pro (High)" ;;
        analysis) MODEL="Gemini 3.1 Pro (High)" ;;
        code)     MODEL="Gemini 3.1 Pro (High)" ;;
    esac
fi

# ── Default timeout ───────────────────────────────────────────────────────────
if [[ -z "$TIMEOUT" ]]; then
    case "$TYPE" in
        search) TIMEOUT=300 ;;
        *)      TIMEOUT=600 ;;
    esac
fi

# ── Temp files (one dir, one trap) ────────────────────────────────────────────
WORK_DIR=$(mktemp -d -t "agy-bridge.XXXXXX")
PROMPT_FILE="$WORK_DIR/prompt"
STDOUT_FILE="$WORK_DIR/stdout"
STDERR_FILE="$WORK_DIR/stderr"
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT QUIT TERM

# ── Read prompt ───────────────────────────────────────────────────────────────
if [[ ${#PROMPT_ARGS[@]} -gt 0 ]]; then
    # Each positional arg becomes its own line (natural for multi-arg prompts).
    printf '%s\n' "${PROMPT_ARGS[@]}" > "$PROMPT_FILE"
elif [[ ! -t 0 ]]; then
    # timeout guard: hanging stdin (e.g. stalled pipe) kills early
    timeout 30 cat > "$PROMPT_FILE" || {
        echo "ERROR: stdin read timed out after 30s" >&2; exit 2
    }
else
    echo "ERROR: no prompt (no stdin, no -- args)" >&2; exit 2
fi

# ── ARG_MAX guard (~2 MiB kernel limit) ──────────────────────────────────────
PROMPT_SIZE=$(wc -c < "$PROMPT_FILE")
if [[ $PROMPT_SIZE -gt 1500000 ]]; then
    echo "ERROR: prompt too large (${PROMPT_SIZE} bytes; max ~1.5 MB for --print arg)" >&2
    exit 2
fi

# ── Search prefix ─────────────────────────────────────────────────────────────
if [[ "$TYPE" == "search" ]] && ! grep -q "search_web" "$PROMPT_FILE"; then
    ORIG=$(cat "$PROMPT_FILE")
    printf 'Use your search_web tool to answer this query. Cite sources with URLs.\n\n%s\n' \
        "$ORIG" > "$PROMPT_FILE"
fi

[[ "$VERBOSE" -eq 1 ]] && printf '[agy_bridge] type=%s model=%s timeout=%ss\n' \
    "$TYPE" "$MODEL" "$TIMEOUT" >&2

PROMPT_TEXT=$(cat "$PROMPT_FILE")

# ── Run agy ──────────────────────────────────────────────────────────────────
# Note: prompt passed as --print arg; visible in ps for local processes.
# Alternative (stdin) causes Claude Code's Bash tool to background the process.
START=$SECONDS
EXIT_CODE=0
set +e
timeout --foreground "$TIMEOUT" agy \
    --print "$PROMPT_TEXT" \
    --model "$MODEL" \
    --dangerously-skip-permissions \
    > "$STDOUT_FILE" \
    2> "$STDERR_FILE"
EXIT_CODE=$?
set -e
DURATION=$(( SECONDS - START ))

# ── Handle errors ─────────────────────────────────────────────────────────────
if [[ "$EXIT_CODE" -eq 124 ]]; then
    if [[ "$JSON_OUTPUT" -eq 1 ]]; then
        _require_jq
        jq -n --arg m "$MODEL" --arg t "$TYPE" --argjson d "$DURATION" \
            --arg e "Timeout after ${TIMEOUT}s" \
            '{success:false,model_used:$m,type:$t,duration_seconds:$d,error:$e}'
    else
        printf 'ERROR: agy timeout after %ds\n' "$TIMEOUT" >&2
    fi
    exit 124
elif [[ "$EXIT_CODE" -ne 0 ]]; then
    ERR=$(cat "$STDERR_FILE")
    if [[ "$JSON_OUTPUT" -eq 1 ]]; then
        _require_jq
        jq -n --arg m "$MODEL" --arg t "$TYPE" --argjson d "$DURATION" \
            --arg e "$ERR" \
            '{success:false,model_used:$m,type:$t,duration_seconds:$d,error:$e}'
    else
        printf 'ERROR: agy exit %d: %s\n' "$EXIT_CODE" "$ERR" >&2
    fi
    exit "$EXIT_CODE"
fi

# ── Output ────────────────────────────────────────────────────────────────────
# Use printf to preserve trailing newlines (cat strips them)
RESPONSE=$(cat "$STDOUT_FILE"; printf x); RESPONSE="${RESPONSE%x}"

if [[ "$JSON_OUTPUT" -eq 1 ]]; then
    _require_jq
    jq -n --arg m "$MODEL" --arg t "$TYPE" --argjson d "$DURATION" \
        --arg r "$RESPONSE" \
        '{success:true,model_used:$m,type:$t,duration_seconds:$d,response:$r}'
else
    printf '%s' "$RESPONSE"
fi
