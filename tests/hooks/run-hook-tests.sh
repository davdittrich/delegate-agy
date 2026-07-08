#!/usr/bin/env bash
#
# tests/hooks/run-hook-tests.sh
#
# Self-contained bash test harness for Claude Code plugin hook scripts.
# Feeds a hook-event JSON payload on stdin to a hook command/script and
# asserts BOTH the process exit code and stdout against expectations.
#
# Public API (for later work units adding real hook test cases):
#
#   run_case <name> <hook_cmd> <stdin_json> <expected_exit> <matcher>
#
#     <name>          Human-readable test case name.
#     <hook_cmd>      Command line to execute (e.g. a path to an executable
#                      hook script, or any shell command string). Invoked via
#                      `eval`, so it may be a bare path or a command with args.
#     <stdin_json>    Literal string piped to <hook_cmd> on stdin.
#     <expected_exit> Expected process exit code (integer).
#     <matcher>       One of:
#                        empty            -- stdout must be exactly ""
#                        contains:SUBSTR  -- stdout must contain SUBSTR
#
#     Prints a PASS/FAIL line and updates the suite's pass/fail counters.
#
# Exit status of this script: 0 iff every real test case (registered via
# run_case) passed. The SELF-CHECK below verifies the harness itself can
# detect a failing assertion; it is isolated from the real suite counters
# so it can never be satisfied by a rubber-stamp harness.

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0

# --- matcher ---------------------------------------------------------------
#
# _match_stdout <matcher> <actual_stdout>
# Returns 0 if actual_stdout satisfies matcher, 1 otherwise.
# Sets MATCH_DESC to a human-readable description of what was checked.
_match_stdout() {
  local matcher="$1"
  local actual="$2"

  case "$matcher" in
    empty)
      MATCH_DESC="stdout is empty"
      [[ -z "$actual" ]]
      return $?
      ;;
    contains:*)
      local needle="${matcher#contains:}"
      MATCH_DESC="stdout contains '${needle}'"
      [[ "$actual" == *"$needle"* ]]
      return $?
      ;;
    *)
      MATCH_DESC="unknown matcher '${matcher}'"
      return 1
      ;;
  esac
}

# --- core assertion (no counters, no printing) ------------------------------
#
# _check_case <name> <hook_cmd> <stdin_json> <expected_exit> <matcher>
# Runs the case. Sets:
#   LAST_RESULT       0 if assertion held (would PASS), 1 if violated (would FAIL)
#   LAST_ACTUAL_EXIT  actual exit code observed
#   LAST_ACTUAL_STDOUT actual stdout observed
#   LAST_REASON       failure description (only meaningful if LAST_RESULT=1)
_check_case() {
  local name="$1"
  local hook_cmd="$2"
  local stdin_json="$3"
  local expected_exit="$4"
  local matcher="$5"

  local actual_stdout
  actual_stdout=$(printf '%s' "$stdin_json" | eval "$hook_cmd" 2>/dev/null)
  local actual_exit=$?

  LAST_ACTUAL_EXIT="$actual_exit"
  LAST_ACTUAL_STDOUT="$actual_stdout"

  local exit_ok=1
  if [[ "$actual_exit" -eq "$expected_exit" ]]; then
    exit_ok=0
  fi

  local stdout_ok=1
  if _match_stdout "$matcher" "$actual_stdout"; then
    stdout_ok=0
  fi

  if [[ "$exit_ok" -eq 0 && "$stdout_ok" -eq 0 ]]; then
    LAST_RESULT=0
    LAST_REASON=""
  else
    LAST_RESULT=1
    local reasons=()
    if [[ "$exit_ok" -ne 0 ]]; then
      reasons+=("expected exit ${expected_exit}, got ${actual_exit}")
    fi
    if [[ "$stdout_ok" -ne 0 ]]; then
      reasons+=("expected ${MATCH_DESC}, got stdout='${actual_stdout}'")
    fi
    LAST_REASON=$(IFS='; '; echo "${reasons[*]}")
  fi
}

# --- public assertion function (counts toward the real suite) --------------
#
# run_case <name> <hook_cmd> <stdin_json> <expected_exit> <matcher>
run_case() {
  local name="$1"
  _check_case "$@"
  if [[ "$LAST_RESULT" -eq 0 ]]; then
    echo "PASS: ${name}"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: ${name} -- ${LAST_REASON}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# --- SELF-CHECK --------------------------------------------------------------
#
# Proves the harness is not a rubber stamp: we deliberately assert a WRONG
# expectation (exit 1) against a trivial stub that actually exits 0 with
# empty stdout. The harness MUST detect this as a violated assertion
# (LAST_RESULT=1). If the harness instead reported the assertion as held
# (a bug making it a rubber stamp), this self-check fails LOUDLY and the
# whole script exits non-zero -- independent of the real suite's results.

# Trivial inline stub: exits 0, emits nothing on stdout.
_self_check_stub_ok() {
  cat >/dev/null
  exit 0
}

self_check() {
  # Deliberately wrong expectation: stub exits 0, but we assert exit 1.
  _check_case "self-check stub" "_self_check_stub_ok" '{"irrelevant":true}' 1 empty

  if [[ "$LAST_RESULT" -eq 1 ]]; then
    echo "SELF-CHECK PASS: harness correctly detected the deliberate wrong expectation (${LAST_REASON})"
    return 0
  else
    echo "SELF-CHECK FAIL: harness reported PASS for a deliberately wrong expectation -- the harness is a rubber stamp and cannot be trusted"
    return 1
  fi
}

if ! self_check; then
  echo ""
  echo "ABORTING: self-check failed, refusing to trust any results from this harness."
  exit 1
fi

echo ""
echo "--- real test cases ---"
echo "(none registered yet in this work unit; WU-3 adds SubagentStart hook cases here)"
echo ""

echo "--- summary ---"
echo "pass: ${PASS_COUNT}  fail: ${FAIL_COUNT}"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi

exit 0
