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

# Duplicate of this script's ORIGINAL stderr, before any call site redirects
# fd 2 into a capture file. Bounding diagnostics go here and nowhere else: at
# the delegation site below, fd 2 is captured and its contents are interpolated
# into the caller-visible error string and the JSON envelope, so a diagnostic
# written to plain stderr would corrupt a payload that must stay untouched.
# Numeric form on purpose -- the fallback this serves exists for stock macOS,
# whose shipped bash predates named descriptors.
exec 9>&2

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
    # Announced here and nowhere else: this probe runs once per invocation, while
    # run_bounded runs three times in a delegating run, so a warning living in
    # the helper would repeat per call. Plain stderr, not fd 9 -- the probe runs
    # before any call site has redirected anything, which is also what puts this
    # line ahead of every bounded call's output. Held in a variable because README
    # quotes these bytes verbatim and the suite pins them.
    RB_NO_TIMEOUT_WARN='WARNING: timeout/gtimeout not found -- bounding agy with the bash watchdog fallback; install coreutils for process-group kill'
    echo "$RB_NO_TIMEOUT_WARN" >&2
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

# --- BEGIN run_bounded ---
# Bounded invocation, redirect-transparent: the command runs in the caller's own
# stdio, so command substitution, direct file redirects, a cd-subshell and a
# piped stdin all keep exactly the capture semantics they had before.
#
# Everything between these two markers is duplicated BYTE-FOR-BYTE into
# scripts/agy_bridge.sh and depends on exactly two things from its host script:
# $TIMEOUT_BIN (set by the probe above) and file descriptor 9 (the script's own
# original stderr, opened at the top). Add no third dependency, and never edit
# one copy alone -- the two blocks are pinned byte-identical by the suite.
# Duplicated rather than sourced for the same reason the model-mapping code
# below is: this script installs as ~/.local/bin/gemini and shadows the real
# gemini for every caller on PATH, so a missing helper would break `gemini`
# box-wide.
#
# The coreutils binary is preferred where it exists, because it isolates its
# child in a new process group and signals the GROUP, reaping descendants. Where
# it does not exist, bash's own job control does the same job with no external
# binary at all -- which is what makes this work on a stock macOS that has
# neither coreutils nor setsid. The escalation rationale is the one already
# stated at the bound declarations above; it is not restated here.
RB_WATCHDOG_KILLED_NOTE='NOTICE: bash watchdog fallback killed the bounded call after its bound (exit 124)'
RUN_BOUNDED_KILLED=0

# $1=pid -> prints a bare digit string, or nothing. NEVER fails its caller: an
# unguarded lookup under `set -euo pipefail` aborts the whole calling script
# rather than degrading, so this body swallows its own failures and the caller
# checks for an empty result instead.
_rb_pgid_of() {
    local p="$1" v=""
    if [[ -r "/proc/$p/stat" ]]; then
        v=$(awk '{print $5}' "/proc/$p/stat" 2>/dev/null) || v=""
    else
        v=$(ps -o pgid= -p "$p" 2>/dev/null) || v=""
    fi
    # One normalisation point, deliberately at the single exit: `ps -o pgid='
    # right-pads its one-row output and procfs field 5 does not. A padded value
    # fails OPEN twice over -- the self-group comparison below stops matching,
    # and the same value lands as a process-group kill operand whose embedded
    # blank makes the target invalid, a rejection the kill's own
    # failure-tolerant suffix swallows. The result would be a reported kill that
    # never happened, on the one platform without procfs, which is exactly the
    # platform this path exists for.
    v="${v//[![:digit:]]/}"
    if [[ -n "$v" ]]; then printf '%s' "$v"; fi
    return 0
}

# $1=signal $2=direct pid $3=process group id, or EMPTY when the child's group
# could not be confirmed distinct from our own. Never signals a group we may be
# a member of; degrades to the direct pid instead.
_rb_signal() {
    if [[ -n "$3" ]]; then
        kill -s "$1" -- "-$3" 2>/dev/null || true
    else
        kill -s "$1" "$2" 2>/dev/null || true
    fi
}

# run_bounded <secs> <kill_after> -- cmd args...
run_bounded() {
    RUN_BOUNDED_KILLED=0
    local secs="${1:-}" kill_after="${2:-}"
    if [[ $# -ge 2 ]]; then shift 2; fi
    if [[ "${1:-}" == "--" ]]; then shift; fi
    # Bounds are operands of sleep, kill and the coreutils binary -- never
    # eval'd, never expanded into a command string -- and are validated here as
    # well as at their env-var source. That second check is not redundant: the
    # coreutils binary documents a zero duration as "no timeout", so an
    # unvalidated bound is a bound that silently disables bounding, which is the
    # exact hang this helper exists to prevent.
    if ! [[ "$secs" =~ ^[1-9][0-9]*$ ]] || ! [[ "$kill_after" =~ ^[1-9][0-9]*$ ]] \
       || [[ $# -eq 0 ]]; then
        echo "ERROR: run_bounded needs positive integer secs and kill_after, then -- and a command" >&9
        return 2
    fi

    local rc=0
    if [[ -n "$TIMEOUT_BIN" ]]; then
        "$TIMEOUT_BIN" -k "$kill_after" "$secs" "$@" || rc=$?
        if [[ "$rc" -eq 124 || "$rc" -eq 137 ]]; then RUN_BOUNDED_KILLED=1; fi
        return "$rc"
    fi

    # ── bash watchdog fallback: no external binary at all ────────────────────
    local self_pgid child child_pgid kill_pgid="" restore_m=0 timer
    # $BASHPID, never $$: inside a command substitution $$ still reports the
    # top-level shell, which would make the comparison below meaningless.
    self_pgid=$(_rb_pgid_of "$BASHPID")

    case "$-" in *m*) : ;; *) restore_m=1 ;; esac
    # Job control makes the shell announce background jobs. Only the enclosing
    # group's OWN stderr goes to the bit bucket; the command's stderr is
    # explicitly restored from the caller's, so an immediate fatal startup error
    # (permission denied, exec format error) is never swallowed. A blanket
    # redirect around the backgrounding construct would be a worse failure than
    # the noise it suppresses.
    exec 8>&2
    {
        set -m
        "$@" 2>&8 8>&- &
        child=$!
        if [[ "$restore_m" -eq 1 ]]; then set +m; fi
    } 2>/dev/null
    exec 8>&-

    child_pgid=$(_rb_pgid_of "$child")
    if [[ -n "$child_pgid" && "$child_pgid" != "$self_pgid" ]]; then
        kill_pgid="$child_pgid"
    else
        echo "WARNING: run_bounded: child $child has no process group of its own; bounding it by pid only, descendants may survive" >&9
    fi

    # Relay a signal we receive ourselves to the same target the timer would
    # use, matching the coreutils binary's own forwarding contract: without this
    # a Ctrl-C leaves the child alive in a group detached from the terminal.
    trap '_rb_signal TERM "$child" "$kill_pgid"; wait "$child" 2>/dev/null || true; exit 143' TERM
    trap '_rb_signal INT "$child" "$kill_pgid"; wait "$child" 2>/dev/null || true; exit 130' INT

    # The timer's stdio is detached on purpose. Cancelling it below kills the
    # subshell but orphans its current `sleep`, and an orphan holding the
    # caller's stdout open would block a caller that captured it for the rest of
    # the bound -- a 600s hang in a script that shadows `gemini` box-wide.
    ( sleep "$secs";       _rb_signal TERM "$child" "$kill_pgid"
      sleep "$kill_after"; _rb_signal KILL "$child" "$kill_pgid"
    ) </dev/null >/dev/null 2>&1 9>&- &
    timer=$!

    wait "$child" 2>/dev/null || rc=$?
    kill "$timer" 2>/dev/null || true
    wait "$timer" 2>/dev/null || true
    trap - TERM INT

    # Authoritative, never inferred from elapsed time: this branch is the one
    # that fired, so it is the one that says so. Deriving the fact from
    # elapsed-versus-bound would report an orchestrator-level cancellation that
    # happens to land at the bound as our own timeout.
    # ponytail: a child killed externally with SIGKILL is indistinguishable from
    # our own escalation here, exactly as it is with the coreutils binary; the
    # host script's duration-based discriminator is what separates the two.
    if [[ "$rc" -eq 143 || "$rc" -eq 137 ]]; then
        RUN_BOUNDED_KILLED=1
        rc=124
        echo "$RB_WATCHDOG_KILLED_NOTE" >&9
    fi
    return "$rc"
}
# --- END run_bounded ---

# ── Model name mapping ────────────────────────────────────────────────────────
# Maps gemini CLI model names/aliases → agy model ids, resolved against the LIVE
# `agy models` list. config/model-map.json holds alias → model CLASS (pro-high,
# flash-high, …); the version is never written down anywhere, it is read from
# agy. A map pinning "gemini-3.6-flash-high" — or its display name — is stale the
# day agy ships 3.7: that is delegate-agy-ovu, the drift bug this whole release
# exists to kill (delegate-agy-62x).
#
# The live list is shared with scripts/agy_bridge.sh: same cache file, same
# 60-minute refresh window, same `cut -f1` normalisation of agy's
# "id<TAB>display name" output, same `sort -V | tail -1` newest-wins pick.
# Deliberately NOT factored into a sourced library: this script installs as
# ~/.local/bin/gemini and shadows the real gemini for every caller on PATH, so a
# missing helper would break `gemini` box-wide. ~20 duplicated lines is the
# cheaper failure mode. Behavior is pinned by tests (R4, SH7-SH11) either way.
# A non-positive-integer bound is CORRECTED, not rejected: coreutils timeout
# documents "A duration of 0 disables the associated timeout", so passing 0
# through would reintroduce the unbounded hang this release exists to fix.
# agy_bridge.sh exits 2 on the same value; this script shadows `gemini` for
# every caller on PATH and must not hard-exit over an optional knob, so it
# falls back to the default instead.
AGY_MODELS_TIMEOUT="${AGY_MODELS_TIMEOUT:-20}"
[[ "$AGY_MODELS_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || AGY_MODELS_TIMEOUT=20
# ${HOME:-} — this runs under `set -u` before any flag is parsed, and the shim
# is reached with HOME unset by systemd units without User=, `env -i`, container
# entrypoints and CI runners. An unwritable cache path degrades to
# fetch-every-time via the || true guards below; it may never abort `gemini`.
MODELS_CACHE="${HOME:-/nonexistent}/.cache/agy-bridge-models"
LIVE_MODELS=""

# Echo the live model ids, one per line, or nothing if agy is unreachable and no
# cache exists. Never fails the script: an unresolvable list degrades to
# pass-through (see map_model), never to a hard error.
load_models() {
    local raw=""
    if [[ ! -s "$MODELS_CACHE" ]] || [[ -n "$(find "$MODELS_CACHE" -mmin +60 2>/dev/null)" ]]; then
        # Third agy call site in this script, bounded like the other three. agy
        # ignores SIGTERM (observed, see scripts/agy_bridge.sh), so the second
        # bound escalates to SIGKILL; a bound without that escalation would hand
        # the shim the very hang this release exists to fix. AGY_MODELS_TIMEOUT
        # is guaranteed a positive integer by the check above.
        raw=$(run_bounded "$AGY_MODELS_TIMEOUT" 3 -- "$AGY_BIN" models </dev/null 2>/dev/null) || raw=""
        if [[ -n "$raw" ]]; then
            # stderr suppressed across the whole write: an unwritable cache dir
            # (HOME unset, read-only FS) otherwise makes bash print the failed
            # redirect on every single invocation. Caching is best-effort — the
            # fetched list in $raw is already usable without it.
            mkdir -p "${MODELS_CACHE%/*}" 2>/dev/null || true
            { printf '%s' "$raw" > "$MODELS_CACHE.tmp.$$" \
                && mv "$MODELS_CACHE.tmp.$$" "$MODELS_CACHE"; } 2>/dev/null || true
            chmod 600 "$MODELS_CACHE" 2>/dev/null || true
        fi
    fi
    # Failed or hung fetch → fall back to the cache, however stale. Silently:
    # a shadowing `gemini` running off its cache is normal operation, and a
    # warning here would land in every Octopus/Metaswarm log line.
    [[ -n "$raw" ]] || raw=$(cat "$MODELS_CACHE" 2>/dev/null) || true
    [[ -n "$raw" ]] && printf '%s\n' "$raw" | cut -f1
    return 0
}

map_model() {
    local m="$1" map_file class resolved=""
    # A name that is a live id RIGHT NOW is honored verbatim — an explicit pin
    # must never be silently upgraded to a newer version. Checked before the
    # map, so map keys that are also live ids (gemini-3.1-pro-high …) stay
    # pass-through while they exist and only fall to their class once retired.
    if [[ -n "$LIVE_MODELS" ]] && printf '%s\n' "$LIVE_MODELS" | grep -qxF "$m"; then
        printf '%s\n' "$m"; return 0
    fi
    map_file="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)/../config/model-map.json"
    class=$(python3 -c "
import json, sys
print(json.load(open(sys.argv[1])).get(sys.argv[2], ''))
" "$map_file" "$m" 2>/dev/null) || class=""
    if [[ -n "$class" && -n "$LIVE_MODELS" ]]; then
        resolved=$(printf '%s\n' "$LIVE_MODELS" | grep -E "^gemini-[0-9.]+-${class}\$" | sort -V | tail -1) || resolved=""
    fi
    if [[ -n "$resolved" ]]; then
        printf '%s\n' "$resolved"; return 0
    fi
    # Unresolvable: pass through unchanged. This shim shadows the system
    # `gemini`, so refusing a name it does not recognise would break callers
    # using models this map has never heard of. Warn only on a list that
    # actually contains gemini ids: with no list, or with the gemini-less reply
    # a degraded/unauthenticated agy returns (agy_bridge.sh treats that as
    # fatal), every name looks unknown — including real aliases — and the
    # warning would be noise on an already-degraded path, cached for 60 minutes.
    if printf '%s\n' "$LIVE_MODELS" | grep -q '^gemini-'; then
        echo "WARNING: model '$m' did not resolve against the agy model list; passing it through unchanged" >&2
    fi
    printf '%s\n' "$m"
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
            run_bounded 10 5 -- "$AGY_BIN" --version || _V_RC=$?
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
# Fetched lazily, only when a model was actually requested: --help, --version
# and model-less invocations must not pay for a model-list round trip.
if [[ -n "$MODEL" ]]; then
    LIVE_MODELS=$(load_models)
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
    # An explicit POSITIVE kill_after, not the zero that would mirror the bare
    # `timeout <secs> cat` this replaces: one validation rule then covers every
    # bounded site, so none of them can pass a value the coreutils binary reads
    # as "no timeout". `cat` never needs the escalation, so admitting it changes
    # nothing observable -- it only removes the one shape that needed an
    # exception. This path is guarded by `! -t 0`, so `cat` never reads a TTY and
    # backgrounding it in its own process group cannot stop on SIGTTIN.
    run_bounded "$STDIN_TIMEOUT" 5 -- cat > "$PROMPT_FILE" || {
        echo "ERROR: stdin read timed out after ${STDIN_TIMEOUT}s" >&2; exit 2
    }
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
run_bounded "$SHIM_TIMEOUT" 5 -- "$AGY_BIN" "${AGY_ARGS[@]}" \
    > "$STDOUT_FILE" \
    2> "$STDERR_FILE" \
    < /dev/null
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
