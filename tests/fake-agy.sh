#!/usr/bin/env bash
# fake-agy.sh -- test stub for the Antigravity CLI `agy`.
#
# Models the REAL agy (>=1.1.1) prompt-delivery contract: agy does NOT read
# the prompt from stdin and does NOT take the prompt as the --print value
# (--print is only a short static pointer). The actual prompt is delivered
# by the caller embedding it in a `GEMINI.md` file, under a line that reads
# exactly `TASK:` (itself preceded by a `---` separator line), inside the
# directory passed via the LAST `--add-dir <dir>` argument. agy auto-loads
# that GEMINI.md and executes the TASK section.
#
# Behavior controlled via env vars so tests can simulate agy outcomes:
#   FAKE_AGY_EXIT         exit code for a --print run (default 0)
#   FAKE_AGY_STDOUT       bytes written to stdout for a --print run (default empty)
#   FAKE_AGY_STDERR       bytes written to stderr for a --print run (default empty)
#   FAKE_AGY_ECHO_PROMPT  if "1", echo ONLY the extracted TASK text (everything
#                         after the `TASK:` marker line in GEMINI.md) to stdout,
#                         instead of the STDOUT/STDERR/EXIT triple above. Lets a
#                         test assert what the wrapper actually embedded (incl.
#                         any appended digest contract).
#   FAKE_AGY_DUMP_ARGV    if set to a path, write the full argv agy was invoked
#                         with (one arg per line) to that path BEFORE any normal
#                         behavior. Purely additive/observational — does not
#                         alter parsing, output, or exit code. Lets a test assert
#                         the exact flags the wrapper passed to agy (e.g. the
#                         --sandbox read-only floor).
#   FAKE_AGY_MODELS_HANG  `agy models` traps SIGTERM and sleeps 300s, emulating
#                         the observed real-agy hang. Only `timeout -k`
#                         (SIGKILL) ends it. Ignored outside `models`.
#   FAKE_AGY_PRINT_HANG   same as FAKE_AGY_MODELS_HANG but on the --print
#                         (delegation) path. Traps SIGTERM and sleeps 300s;
#                         only `timeout -k` (SIGKILL) ends it.
#   FAKE_AGY_PRINT_KILL9  the --print (delegation) path exits 137 quickly,
#                         well inside any --timeout bound -- emulating an
#                         external SIGKILL (OOM killer, manual `kill -9`,
#                         cgroup/container preemption) unrelated to the
#                         bridge's own `-k` escalation.
#   FAKE_AGY_MODELS_FAIL  `agy models` exits 1 with a FAKE-AGY-AUTH-FAILURE
#                         diagnostic on stderr, simulating an auth/network
#                         fault. Ignored outside `models`.
#   FAKE_AGY_MODELS_GARBAGE
#                         `agy models` exits 0 but with no gemini ids in its
#                         output. Ignored outside `models`.
#
# The `models` and `--version` subcommands are answered deterministically so the
# bridge's model-allowlist check and the shim's --version path work under test.
set -u

# Observational argv dump (env-gated, additive). Runs first so it captures the
# real argv for every invocation kind (models/--version/--print) without
# changing any downstream behavior.
if [[ -n "${FAKE_AGY_DUMP_ARGV:-}" ]]; then
    printf '%s\n' "$@" > "$FAKE_AGY_DUMP_ARGV"
fi

case "${1:-}" in
    models)
        # Hang mode: trap SIGTERM and sleep, emulating the observed real-agy
        # behavior where `timeout 25 agy models` never returns. Only `timeout -k`
        # (SIGKILL) can end this.
        if [[ -n "${FAKE_AGY_MODELS_HANG:-}" ]]; then
            trap '' TERM
            sleep 300
            exit 0
        fi
        # Failure mode: non-zero exit with a diagnostic on stderr, the shape a
        # real auth/network fault takes.
        if [[ -n "${FAKE_AGY_MODELS_FAIL:-}" ]]; then
            echo "FAKE-AGY-AUTH-FAILURE: not authenticated" >&2
            exit 1
        fi
        # Garbage mode: exit 0 with output carrying no gemini ids at all.
        if [[ -n "${FAKE_AGY_MODELS_GARBAGE:-}" ]]; then
            printf '%s\n' "Please run 'agy auth login' first." "no models available"
            exit 0
        fi
        # Real agy emits "id<TAB>display name" per line (header goes to stderr).
        printf '%s\t%s\n' \
            "gemini-3.6-flash-high" "Gemini 3.6 Flash (High)" \
            "gemini-3.6-flash-medium" "Gemini 3.6 Flash (Medium)" \
            "gemini-3.6-flash-low" "Gemini 3.6 Flash (Low)" \
            "gemini-3.5-flash-high" "Gemini 3.5 Flash (High)" \
            "gemini-3.5-flash-medium" "Gemini 3.5 Flash (Medium)" \
            "gemini-3.5-flash-low" "Gemini 3.5 Flash (Low)" \
            "gemini-3.1-pro-high" "Gemini 3.1 Pro (High)" \
            "gemini-3.1-pro-low" "Gemini 3.1 Pro (Low)"
        exit 0 ;;
    --version)
        echo "agy 0.0.0-fake"; exit 0 ;;
esac

# Delegation hang mode: same shape as FAKE_AGY_MODELS_HANG, but on the --print
# path. Traps SIGTERM and sleeps, emulating agy ignoring the signal, so only a
# `timeout -k` escalation can end it.
if [[ -n "${FAKE_AGY_PRINT_HANG:-}" ]]; then
    trap '' TERM
    sleep 300
    exit 0
fi

# Delegation "killed early" mode: exits 137 quickly, well inside any --timeout
# bound, emulating an external SIGKILL that has nothing to do with the
# bridge's own -k escalation (which can only fire at/after the bound).
if [[ -n "${FAKE_AGY_PRINT_KILL9:-}" ]]; then
    exit 137
fi

# Otherwise this is a real --print run. Parse the real agy flag set:
#   --print <value> --sandbox --model <value> --add-dir <dir> (repeatable)
#   --dangerously-skip-permissions --include-directories <dir> (repeatable, alias of --add-dir)
have_print=0
add_dir=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --print)
            have_print=1
            shift; [[ $# -gt 0 ]] && shift || true ;;
        --add-dir|--include-directories)
            add_dir="${2:-}"
            shift; [[ $# -gt 0 ]] && shift || true ;;
        --model)
            shift; [[ $# -gt 0 ]] && shift || true ;;
        --sandbox)
            shift 1 ;;
        --dangerously-skip-permissions)
            shift 1 ;;
        *)
            shift 1 ;;
    esac
done

fail_empty_prompt() {
    echo 'Error: Error: empty prompt. Usage: agy --print "your prompt here"' >&2
    exit 1
}

[[ "$have_print" -eq 1 ]] || fail_empty_prompt

gemini_md="${add_dir%/}/GEMINI.md"
[[ -n "$add_dir" && -f "$gemini_md" ]] || fail_empty_prompt

# Extract everything after the line that is exactly `TASK:` (the marker line
# following a `---` separator). Robust to blank lines within the prompt body.
task_text="$(awk '
    found { print; next }
    $0 == "TASK:" { found=1 }
' "$gemini_md")"

# Emptiness check: strip all whitespace/newlines; if nothing remains, error.
stripped="$(printf '%s' "$task_text" | tr -d '[:space:]')"
[[ -n "$stripped" ]] || fail_empty_prompt

if [[ "${FAKE_AGY_ECHO_PROMPT:-0}" == "1" ]]; then
    printf '%s\n' "$task_text"
    exit "${FAKE_AGY_EXIT:-0}"
fi

[[ -n "${FAKE_AGY_STDOUT:-}" ]] && printf '%s' "$FAKE_AGY_STDOUT"
[[ -n "${FAKE_AGY_STDERR:-}" ]] && printf '%s' "$FAKE_AGY_STDERR" >&2
exit "${FAKE_AGY_EXIT:-0}"
