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

if ! command -v jq &>/dev/null; then
    _JQ_OK=0
else
    _JQ_OK=1
fi

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
        --version)            "$AGY_BIN" --version; exit 0 ;;
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
if [[ "$YOLO" -eq 1 || "$APPROVAL_MODE" == "yolo" ]]; then
    cat > "$WORK_DIR/GEMINI.md" <<'RESTRICTIONS'
TOOL RESTRICTIONS (gemini-shim orchestrator):
PERMITTED: read_file, view_file, grep_search, search_web, read_url,
  write_file, write_to_file, replace_file_content, multi_replace_file_content
FORBIDDEN: run_shell_command, run_command,
  invoke_subagent, spawn_agent, define_subagent, manage_subagents, schedule
RESTRICTIONS
elif [[ "$SANDBOX" -eq 1 ]]; then
    cat > "$WORK_DIR/GEMINI.md" <<'RESTRICTIONS'
TOOL RESTRICTIONS (gemini-shim orchestrator — sandbox/read-only):
PERMITTED: read_file, view_file, grep_search, search_web, read_url
FORBIDDEN: run_shell_command, run_command, write_file, write_to_file,
  replace_file_content, multi_replace_file_content,
  invoke_subagent, spawn_agent, define_subagent, manage_subagents, schedule
RESTRICTIONS
else
    cat > "$WORK_DIR/GEMINI.md" <<'RESTRICTIONS'
TOOL RESTRICTIONS (gemini-shim orchestrator):
PERMITTED: read_file, view_file, grep_search, search_web, read_url
FORBIDDEN: run_shell_command, run_command, write_file, write_to_file,
  replace_file_content, multi_replace_file_content,
  invoke_subagent, spawn_agent, define_subagent, manage_subagents, schedule
RESTRICTIONS
fi

# ── Read prompt ───────────────────────────────────────────────────────────────
if [[ ${#PROMPT_ARGS[@]} -gt 0 ]]; then
    printf '%s\n' "${PROMPT_ARGS[@]}" > "$PROMPT_FILE"
elif [[ ! -t 0 ]]; then
    cat > "$PROMPT_FILE"
else
    echo "ERROR: no prompt (no stdin and no positional args)" >&2; exit 2
fi

if [[ ! -s "$PROMPT_FILE" ]]; then
    echo "ERROR: empty prompt" >&2; exit 2
fi

# ── Build agy command ─────────────────────────────────────────────────────────
AGY_ARGS=(--print --add-dir "$WORK_DIR")

[[ -n "$MODEL" ]] && AGY_ARGS+=(--model "$MODEL")

# --yolo or --approval-mode yolo → auto-approve all tool calls
if [[ "$YOLO" -eq 1 || "$APPROVAL_MODE" == "yolo" ]]; then
    AGY_ARGS+=(--dangerously-skip-permissions)
fi

# --include-directories → --add-dir (one per directory)
for dir in "${INCLUDE_DIRS[@]}"; do
    AGY_ARGS+=(--add-dir "$dir")
done

# ── Run agy (prompt via stdin, never in cmdline — avoids ARG_MAX and leaks) ──
START=$SECONDS
EXIT_CODE=0
set +e
"$AGY_BIN" "${AGY_ARGS[@]}" \
    < "$PROMPT_FILE" \
    > "$STDOUT_FILE" \
    2> "$STDERR_FILE"
EXIT_CODE=$?
set -e
DURATION=$(( SECONDS - START ))

# ── Handle errors ─────────────────────────────────────────────────────────────
if [[ "$EXIT_CODE" -ne 0 ]]; then
    cat "$STDERR_FILE" >&2
    exit "$EXIT_CODE"
fi

RESPONSE=$(cat "$STDOUT_FILE")

# ── Output ────────────────────────────────────────────────────────────────────
if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    # Wrap in a usageMetadata envelope compatible with extract_cost_gemini()
    # (metaswarm _common.sh reads .usageMetadata.promptTokenCount etc.)
    # Token counts are null — agy does not expose real token usage.
    if [[ "$_JQ_OK" -eq 1 ]]; then
        jq -n \
            --arg response "$RESPONSE" \
            --argjson duration "$DURATION" \
            '{
                "response": $response,
                "usageMetadata": {
                    "promptTokenCount": null,
                    "candidatesTokenCount": null,
                    "totalTokenCount": null
                },
                "model": "agy",
                "duration_seconds": $duration
            }'
    else
        # jq not available — emit minimal JSON manually
        printf '{"response":%s,"usageMetadata":{"promptTokenCount":null,"candidatesTokenCount":null,"totalTokenCount":null}}\n' \
            "$(printf '%s' "$RESPONSE" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
    fi
else
    printf '%s\n' "$RESPONSE"
fi
