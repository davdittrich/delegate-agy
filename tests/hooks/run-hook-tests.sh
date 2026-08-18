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

# --- WU-3: SubagentStart hook (hooks/agy-subagent-policy.sh) --------------
#
# Real hook under test, invoked exactly as Claude Code would invoke it: a
# JSON payload piped to stdin, stdout/exit code asserted.

_wu3_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_wu3_repo_root="$(cd "${_wu3_script_dir}/../.." && pwd)"
WU3_HOOK="${_wu3_repo_root}/hooks/agy-subagent-policy.sh"

# Stub `agy-bridge` on PATH so "bridge present" cases don't depend on the
# real bridge being installed.
WU3_STUB_DIR="$(mktemp -d)"
cat > "${WU3_STUB_DIR}/agy-bridge" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${WU3_STUB_DIR}/agy-bridge"

# Stub `python3` that always fails, used only for the "python3 unusable"
# case. Kept in its own dir so it never leaks into the other scenarios.
WU3_NOPY_DIR="$(mktemp -d)"
cat > "${WU3_NOPY_DIR}/python3" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "${WU3_NOPY_DIR}/python3"

# Stub `python3` that touches a marker file when invoked, then fails. Used
# only for the "disabled path never forks python3" case: if the hook ever
# invokes python3 while disabled, the marker file will exist afterward.
# Kept in its own dir so it never leaks into the other scenarios.
WU3_TOUCHPY_DIR="$(mktemp -d)"
WU3_TOUCHPY_MARKER="${WU3_TOUCHPY_DIR}/python3-invoked-marker"
cat > "${WU3_TOUCHPY_DIR}/python3" <<EOF
#!/usr/bin/env bash
touch "${WU3_TOUCHPY_MARKER}"
exit 1
EOF
chmod +x "${WU3_TOUCHPY_DIR}/python3"

WU3_DEBUG_FILE="$(mktemp)"

# Dedicated debug-reason capture files -- one per fail-safe branch so their
# reasons can be asserted independently and compared for distinctness.
WU3_DBG_EMPTY="$(mktemp)"
WU3_DBG_MALFORMED="$(mktemp)"
WU3_DBG_NOTALLOWED="$(mktemp)"
WU3_DBG_BROKEN_PY="$(mktemp)"

# Clean up all WU-3 temp artifacts regardless of how this script exits.
trap 'rm -rf "${WU3_STUB_DIR:-}" "${WU3_NOPY_DIR:-}" "${WU3_TOUCHPY_DIR:-}"; rm -f "${WU3_DEBUG_FILE:-}" "${WU3_DBG_EMPTY:-}" "${WU3_DBG_MALFORMED:-}" "${WU3_DBG_NOTALLOWED:-}" "${WU3_DBG_BROKEN_PY:-}"' EXIT

# PATH with the agy-bridge stub present (bridge available), real PATH kept
# behind it so bash/cat/python3 etc. still resolve normally.
WU3_BRIDGE_PATH="${WU3_STUB_DIR}:${PATH}"

# PATH with the python3 stub shadowing any real python3 (python3 "present"
# but unusable) -- exercises the "no crash" contract either way.
WU3_NO_PYTHON_PATH="${WU3_NOPY_DIR}:${PATH}"

# PATH with BOTH the broken-python3 stub and the agy-bridge stub present
# (bridge available, python3 present-but-broken) -- used to prove the
# broken-python3 case is reported distinctly from "malformed json".
WU3_BROKEN_PY_BRIDGE_PATH="${WU3_NOPY_DIR}:${WU3_STUB_DIR}:${PATH}"

# PATH with BOTH the touch-marking python3 stub and the agy-bridge stub
# present -- used to prove the disabled path never forks python3.
WU3_TOUCHPY_BRIDGE_PATH="${WU3_TOUCHPY_DIR}:${WU3_STUB_DIR}:${PATH}"

# PATH with every directory that contains a real `agy-bridge` executable
# stripped out (a real bridge may legitimately be installed on this
# machine's PATH, e.g. ~/.local/bin/agy-bridge -- do not assume otherwise).
WU3_NO_BRIDGE_PATH=""
_wu3_old_ifs="$IFS"
IFS=':'
for _wu3_dir in $PATH; do
  IFS="$_wu3_old_ifs"
  if [[ -n "$_wu3_dir" && -x "${_wu3_dir}/agy-bridge" ]]; then
    continue
  fi
  if [[ -z "$WU3_NO_BRIDGE_PATH" ]]; then
    WU3_NO_BRIDGE_PATH="$_wu3_dir"
  else
    WU3_NO_BRIDGE_PATH="${WU3_NO_BRIDGE_PATH}:${_wu3_dir}"
  fi
  IFS=':'
done
IFS="$_wu3_old_ifs"

# Manual assertion helper for checks the empty/contains matcher can't
# express (e.g. "must NOT contain", or an exact-value comparison). Counts
# toward the same PASS_COUNT/FAIL_COUNT totals as run_case so the suite
# still exits non-zero on any mismatch.
_wu3_manual_assert() {
  local name="$1"
  local ok="$2"
  local reason="$3"
  if [[ "$ok" -eq 0 ]]; then
    echo "PASS: ${name}"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: ${name} -- ${reason}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# 1. enabled + namespaced-allowlisted + bridge present -> emits the advisory.
run_case "wu3-01a-namespaced-allowlisted-emits-bridge-mention" \
  "AGY_HOOKS_ENABLED=1 AGY_HOOKS_AGENT_TYPES='metaswarm:researcher-agent' PATH='${WU3_BRIDGE_PATH}' bash '${WU3_HOOK}'" \
  '{"agent_type":"metaswarm:researcher-agent"}' 0 "contains:agy-bridge"
run_case "wu3-01b-namespaced-allowlisted-emits-hookSpecificOutput" \
  "AGY_HOOKS_ENABLED=1 AGY_HOOKS_AGENT_TYPES='metaswarm:researcher-agent' PATH='${WU3_BRIDGE_PATH}' bash '${WU3_HOOK}'" \
  '{"agent_type":"metaswarm:researcher-agent"}' 0 "contains:hookSpecificOutput"
run_case "wu3-01c-namespaced-allowlisted-emits-SubagentStart" \
  "AGY_HOOKS_ENABLED=1 AGY_HOOKS_AGENT_TYPES='metaswarm:researcher-agent' PATH='${WU3_BRIDGE_PATH}' bash '${WU3_HOOK}'" \
  '{"agent_type":"metaswarm:researcher-agent"}' 0 "contains:SubagentStart"

# 2. enabled + bare-allowlisted + bridge present -> emits.
run_case "wu3-02-bare-allowlisted-emits" \
  "AGY_HOOKS_ENABLED=1 AGY_HOOKS_AGENT_TYPES='general-purpose' PATH='${WU3_BRIDGE_PATH}' bash '${WU3_HOOK}'" \
  '{"agent_type":"general-purpose"}' 0 "contains:agy-bridge"

# 3. namespaced allowlist entry does not cross-match a different namespace.
run_case "wu3-03-namespace-mismatch-silent" \
  "AGY_HOOKS_ENABLED=1 AGY_HOOKS_AGENT_TYPES='metaswarm:researcher-agent' PATH='${WU3_BRIDGE_PATH}' bash '${WU3_HOOK}'" \
  '{"agent_type":"metaswarm:coder-agent"}' 0 empty

# 4. agent_type simply not in the allowlist -> silent.
run_case "wu3-04-not-allowlisted-silent" \
  "AGY_HOOKS_ENABLED=1 AGY_HOOKS_AGENT_TYPES='metaswarm:researcher-agent' PATH='${WU3_BRIDGE_PATH}' bash '${WU3_HOOK}'" \
  '{"agent_type":"totally-unlisted-agent"}' 0 empty

# 5. hook toggled off, otherwise valid -> silent.
run_case "wu3-05-disabled-silent" \
  "AGY_HOOKS_ENABLED=0 AGY_HOOKS_AGENT_TYPES='general-purpose' PATH='${WU3_BRIDGE_PATH}' bash '${WU3_HOOK}'" \
  '{"agent_type":"general-purpose"}' 0 empty

# 6. malformed JSON stdin -> silent, no crash.
run_case "wu3-06-malformed-json-silent" \
  "AGY_HOOKS_ENABLED=1 AGY_HOOKS_AGENT_TYPES='general-purpose' PATH='${WU3_BRIDGE_PATH}' bash '${WU3_HOOK}'" \
  '{not valid json at all' 0 empty

# 7. empty stdin -> silent, no hang.
run_case "wu3-07-empty-stdin-silent-no-hang" \
  "AGY_HOOKS_ENABLED=1 AGY_HOOKS_AGENT_TYPES='general-purpose' PATH='${WU3_BRIDGE_PATH}' bash '${WU3_HOOK}'" \
  '' 0 empty

# 8. python3 unusable -> silent, exit 0, no crash.
run_case "wu3-08-python3-unusable-silent" \
  "AGY_HOOKS_ENABLED=1 AGY_HOOKS_AGENT_TYPES='general-purpose' PATH='${WU3_NO_PYTHON_PATH}' bash '${WU3_HOOK}'" \
  '{"agent_type":"general-purpose"}' 0 empty

# 9. whitespace-padded allowlist entries are trimmed before matching.
run_case "wu3-09-whitespace-padded-allowlist-emits" \
  "AGY_HOOKS_ENABLED=1 AGY_HOOKS_AGENT_TYPES=' general-purpose , Explore ' PATH='${WU3_BRIDGE_PATH}' bash '${WU3_HOOK}'" \
  '{"agent_type":"general-purpose"}' 0 "contains:agy-bridge"

# 10. agy-bridge absent from PATH -> silent even though everything else
#     would otherwise fire. Precondition-check that our filtered PATH truly
#     has no real bridge on it, so this case can't silently pass for the
#     wrong reason.
if command -v agy-bridge >/dev/null 2>&1 && [[ "$(PATH="${WU3_NO_BRIDGE_PATH}" command -v agy-bridge 2>/dev/null)" != "" ]]; then
  _wu3_manual_assert "wu3-10-precondition-no-real-bridge-on-filtered-path" 1 \
    "agy-bridge is still resolvable on WU3_NO_BRIDGE_PATH; the 'bridge absent' case would be invalid"
else
  _wu3_manual_assert "wu3-10-precondition-no-real-bridge-on-filtered-path" 0 ""
fi
run_case "wu3-10-bridge-absent-silent" \
  "AGY_HOOKS_ENABLED=1 AGY_HOOKS_AGENT_TYPES='general-purpose' PATH='${WU3_NO_BRIDGE_PATH}' bash '${WU3_HOOK}'" \
  '{"agent_type":"general-purpose"}' 0 empty

# 11. debug on -> still emits valid JSON containing the advisory, and the
#     incoming prompt text is NEVER echoed to stdout (checked via a sentinel
#     that the `contains`/`empty` matchers can't express as a negative).
run_case "wu3-11a-debug-on-fired-emits-advisory-fragment" \
  "AGY_HOOKS_ENABLED=1 AGY_HOOKS_AGENT_TYPES='general-purpose' AGY_HOOKS_DEBUG=1 AGY_HOOKS_DEBUG_FILE='${WU3_DEBUG_FILE}' PATH='${WU3_BRIDGE_PATH}' bash '${WU3_HOOK}'" \
  '{"agent_type":"general-purpose","prompt":"PROMPTSENTINEL_ZZZ this is the user task"}' 0 "contains:agy-bridge"

_wu3_sentinel_stdout=$(printf '%s' '{"agent_type":"general-purpose","prompt":"PROMPTSENTINEL_ZZZ this is the user task"}' \
  | AGY_HOOKS_ENABLED=1 AGY_HOOKS_AGENT_TYPES='general-purpose' AGY_HOOKS_DEBUG=1 AGY_HOOKS_DEBUG_FILE="${WU3_DEBUG_FILE}" PATH="${WU3_BRIDGE_PATH}" bash "${WU3_HOOK}" 2>/dev/null)
if [[ "$_wu3_sentinel_stdout" == *"PROMPTSENTINEL_ZZZ"* ]]; then
  _wu3_manual_assert "wu3-11b-debug-on-prompt-never-leaked-to-stdout" 1 \
    "stdout leaked the incoming prompt sentinel: ${_wu3_sentinel_stdout}"
else
  _wu3_manual_assert "wu3-11b-debug-on-prompt-never-leaked-to-stdout" 0 ""
fi

# 12. emitted JSON is valid AND additionalContext equals the advisory
#     EXACTLY (verbatim, independently re-verified via python3 json.load).
_wu3_exact_stdout=$(printf '%s' '{"agent_type":"general-purpose"}' \
  | AGY_HOOKS_ENABLED=1 AGY_HOOKS_AGENT_TYPES='general-purpose' PATH="${WU3_BRIDGE_PATH}" bash "${WU3_HOOK}" 2>/dev/null)

# NOTE: the captured stdout is passed via a temp file argument, NOT piped in
# alongside a `python3 - <<HEREDOC` invocation -- a heredoc redirection on
# the same command overrides a pipe for that command's stdin, which would
# silently discard the piped JSON and make this check vacuously fail.
_wu3_exact_stdout_file="$(mktemp)"
printf '%s' "${_wu3_exact_stdout}" > "${_wu3_exact_stdout_file}"

if python3 - "${_wu3_exact_stdout_file}" <<'PYEOF'
import json
import sys

expected = """For general web search, prefer your `WebSearch` tool. For grounded/source-cited search, extended-context reading, or a second opinion you can delegate to agy via the `agy-bridge` command — invoke it through `ctx_shell` (fall back to `Bash` only if `ctx_shell` is unavailable); run `agy-bridge --help`. The judgment stays with you: skip it for small or judgment-heavy tasks, and always verify agy's output."""

with open(sys.argv[1]) as f:
    data = f.read()

try:
    obj = json.loads(data)
    got = obj["hookSpecificOutput"]["additionalContext"]
except Exception:
    sys.exit(1)

sys.exit(0 if got == expected else 1)
PYEOF
then
  _wu3_manual_assert "wu3-12-emitted-additionalContext-exact-match" 0 ""
else
  _wu3_manual_assert "wu3-12-emitted-additionalContext-exact-match" 1 \
    "emitted additionalContext did not exactly equal the fixed advisory text (stdout: ${_wu3_exact_stdout})"
fi
rm -f "${_wu3_exact_stdout_file}"

# 13. Fail-safe branches must emit DISTINCT debug reasons so operators using
#     AGY_HOOKS_DEBUG can tell a broken payload from a not-allowlisted agent.
#     Each branch writes to its own debug file; we assert the expected reason
#     substring per branch, that the three reasons are mutually distinct, and
#     (regression guard) that malformed/empty-stdin stay SILENT + exit 0.

# 13a. empty stdin -> silent, exit 0, debug reason "empty stdin".
run_case "wu3-13a-empty-stdin-silent-exit0" \
  "AGY_HOOKS_ENABLED=1 AGY_HOOKS_AGENT_TYPES='general-purpose' AGY_HOOKS_DEBUG=1 AGY_HOOKS_DEBUG_FILE='${WU3_DBG_EMPTY}' PATH='${WU3_BRIDGE_PATH}' bash '${WU3_HOOK}'" \
  '   ' 0 empty
if grep -q 'empty stdin' "${WU3_DBG_EMPTY}"; then
  _wu3_manual_assert "wu3-13a-empty-stdin-debug-reason" 0 ""
else
  _wu3_manual_assert "wu3-13a-empty-stdin-debug-reason" 1 \
    "debug file did not contain 'empty stdin' (got: $(cat "${WU3_DBG_EMPTY}"))"
fi

# 13b. malformed json -> silent, exit 0, debug reason "malformed json".
run_case "wu3-13b-malformed-json-silent-exit0" \
  "AGY_HOOKS_ENABLED=1 AGY_HOOKS_AGENT_TYPES='general-purpose' AGY_HOOKS_DEBUG=1 AGY_HOOKS_DEBUG_FILE='${WU3_DBG_MALFORMED}' PATH='${WU3_BRIDGE_PATH}' bash '${WU3_HOOK}'" \
  '{not valid json at all' 0 empty
if grep -q 'malformed json' "${WU3_DBG_MALFORMED}"; then
  _wu3_manual_assert "wu3-13b-malformed-json-debug-reason" 0 ""
else
  _wu3_manual_assert "wu3-13b-malformed-json-debug-reason" 1 \
    "debug file did not contain 'malformed json' (got: $(cat "${WU3_DBG_MALFORMED}"))"
fi

# 13c. valid JSON, non-allowlisted type -> debug reason "not allowlisted".
run_case "wu3-13c-not-allowlisted-silent-exit0" \
  "AGY_HOOKS_ENABLED=1 AGY_HOOKS_AGENT_TYPES='general-purpose' AGY_HOOKS_DEBUG=1 AGY_HOOKS_DEBUG_FILE='${WU3_DBG_NOTALLOWED}' PATH='${WU3_BRIDGE_PATH}' bash '${WU3_HOOK}'" \
  '{"agent_type":"totally-unlisted-agent"}' 0 empty
if grep -q 'not allowlisted' "${WU3_DBG_NOTALLOWED}"; then
  _wu3_manual_assert "wu3-13c-not-allowlisted-debug-reason" 0 ""
else
  _wu3_manual_assert "wu3-13c-not-allowlisted-debug-reason" 1 \
    "debug file did not contain 'not allowlisted' (got: $(cat "${WU3_DBG_NOTALLOWED}"))"
fi

# 13d. the three debug reasons must be MUTUALLY DISTINCT (strip the leading
#     timestamp, compare the reason text). This is the assertion that would
#     have caught the original collapse of all three branches into the
#     identical "not allowlisted: '' -> skip" line.
_wu3_reason_empty="$(cat "${WU3_DBG_EMPTY}")";           _wu3_reason_empty="${_wu3_reason_empty##*agy-hooks: }"
_wu3_reason_malformed="$(cat "${WU3_DBG_MALFORMED}")";   _wu3_reason_malformed="${_wu3_reason_malformed##*agy-hooks: }"
_wu3_reason_notallowed="$(cat "${WU3_DBG_NOTALLOWED}")"; _wu3_reason_notallowed="${_wu3_reason_notallowed##*agy-hooks: }"
if [[ "$_wu3_reason_empty" != "$_wu3_reason_malformed" \
   && "$_wu3_reason_empty" != "$_wu3_reason_notallowed" \
   && "$_wu3_reason_malformed" != "$_wu3_reason_notallowed" ]]; then
  _wu3_manual_assert "wu3-13d-three-debug-reasons-mutually-distinct" 0 ""
else
  _wu3_manual_assert "wu3-13d-three-debug-reasons-mutually-distinct" 1 \
    "debug reasons collapsed: empty='${_wu3_reason_empty}' malformed='${_wu3_reason_malformed}' notallowed='${_wu3_reason_notallowed}'"
fi

# 14. Guard reordering regression: a present-but-broken python3 (enabled,
#     allowlisted, bridge present) must be reported as "no python3" by the
#     usability probe, and must NEVER fall through to be misreported as
#     "malformed json" by the later json-validity probe.
run_case "wu3-14a-broken-python3-silent-exit0" \
  "AGY_HOOKS_ENABLED=1 AGY_HOOKS_AGENT_TYPES='general-purpose' AGY_HOOKS_DEBUG=1 AGY_HOOKS_DEBUG_FILE='${WU3_DBG_BROKEN_PY}' PATH='${WU3_BROKEN_PY_BRIDGE_PATH}' bash '${WU3_HOOK}'" \
  '{"agent_type":"general-purpose"}' 0 empty
if grep -q 'no python3' "${WU3_DBG_BROKEN_PY}"; then
  _wu3_manual_assert "wu3-14b-broken-python3-debug-reason-no-python3" 0 ""
else
  _wu3_manual_assert "wu3-14b-broken-python3-debug-reason-no-python3" 1 \
    "debug file did not contain 'no python3' (got: $(cat "${WU3_DBG_BROKEN_PY}"))"
fi
if grep -q 'malformed json' "${WU3_DBG_BROKEN_PY}"; then
  _wu3_manual_assert "wu3-14c-broken-python3-not-misreported-as-malformed-json" 1 \
    "debug file incorrectly contained 'malformed json' for a broken-python3 case (got: $(cat "${WU3_DBG_BROKEN_PY}"))"
else
  _wu3_manual_assert "wu3-14c-broken-python3-not-misreported-as-malformed-json" 0 ""
fi

# 15. Guard reordering regression: the disabled path must never fork python3
#     at all. Uses a stub python3 that touches a marker file when invoked;
#     the marker must NOT exist after running the hook disabled, proving the
#     pure-bash enabled-check gates before any python3 invocation.
rm -f "${WU3_TOUCHPY_MARKER}"
run_case "wu3-15a-disabled-silent-exit0-with-touch-python3-stub" \
  "AGY_HOOKS_ENABLED=0 AGY_HOOKS_AGENT_TYPES='general-purpose' PATH='${WU3_TOUCHPY_BRIDGE_PATH}' bash '${WU3_HOOK}'" \
  '{"agent_type":"general-purpose"}' 0 empty
if [[ -e "${WU3_TOUCHPY_MARKER}" ]]; then
  _wu3_manual_assert "wu3-15b-disabled-path-never-forks-python3" 1 \
    "marker file exists -- python3 stub was invoked on the disabled path (AGY_HOOKS_ENABLED=0)"
else
  _wu3_manual_assert "wu3-15b-disabled-path-never-forks-python3" 0 ""
fi
echo ""

echo "--- summary ---"
echo "pass: ${PASS_COUNT}  fail: ${FAIL_COUNT}"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi

exit 0
