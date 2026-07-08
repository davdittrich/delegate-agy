#!/usr/bin/env bash
# fake-agy.sh — test stub for the Antigravity CLI `agy`.
# Behavior controlled via env vars so tests can simulate agy outcomes:
#   FAKE_AGY_EXIT    exit code for a --print run (default 0)
#   FAKE_AGY_STDOUT  bytes written to stdout for a --print run (default empty)
#   FAKE_AGY_STDERR  bytes written to stderr for a --print run (default empty)
# The `models` and `--version` subcommands are answered deterministically so the
# bridge's model-allowlist check and the shim's --version path work under test.
set -u

case "${1:-}" in
    models)
        printf '%s\n' "Gemini 3.1 Pro (High)" "Gemini 3.5 Flash (High)" "Gemini 3.5 Flash (Low)"
        exit 0 ;;
    --version)
        echo "agy 0.0.0-fake"; exit 0 ;;
esac

# Otherwise this is a real --print run: emit the controlled fixtures.
[[ -n "${FAKE_AGY_STDOUT:-}" ]] && printf '%s' "$FAKE_AGY_STDOUT"
[[ -n "${FAKE_AGY_STDERR:-}" ]] && printf '%s' "$FAKE_AGY_STDERR" >&2
exit "${FAKE_AGY_EXIT:-0}"
