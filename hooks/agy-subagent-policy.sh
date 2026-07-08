#!/usr/bin/env bash
#
# hooks/agy-subagent-policy.sh
#
# SubagentStart hook. Reads a hook-event JSON payload on stdin describing the
# subagent about to be spawned. When -- and ONLY when -- the hook is enabled,
# the subagent's agent_type is allowlisted, AND `agy-bridge` is available on
# PATH, this hook emits a fixed advisory as SubagentStart additionalContext:
#
#   {"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"<advisory>"}}
#
# In every other case it is completely SILENT (no stdout) and exits 0. This
# hook must never fail, never hang a subagent spawn, and never echo the
# incoming prompt/payload back to stdout.

set -uo pipefail

_hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./agy-hooks-lib.sh
source "${_hook_dir}/agy-hooks-lib.sh"

# Guard 1 (FIRST): python3 is required to safely parse the incoming JSON and
# to safely construct the outgoing JSON. Without it we cannot proceed.
if ! command -v python3 >/dev/null 2>&1; then
  agy_hooks_debug "no python3 -> skip"
  exit 0
fi

# Read the entire hook-event payload from stdin. Safe even if stdin is empty
# or already closed -- never blocks.
input="$(cat)"

# Guard 2: the hook must be explicitly enabled.
if ! agy_hooks_enabled; then
  agy_hooks_debug "disabled -> skip"
  exit 0
fi

# Guard 3: empty or whitespace-only stdin is its own fail-safe branch. A
# missing payload is operationally distinct from a valid-but-not-allowlisted
# agent, so it gets its own debug reason (see AGY_HOOKS_DEBUG allowlist
# discovery UX).
if [[ -z "${input//[[:space:]]/}" ]]; then
  agy_hooks_debug "empty stdin -> skip"
  exit 0
fi

# Guard 4: malformed / non-JSON payload is its own fail-safe branch. One
# python3 validity probe (never eval); a broken payload must be
# distinguishable from a not-allowlisted agent in the debug log.
if ! printf '%s' "$input" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' >/dev/null 2>&1; then
  agy_hooks_debug "malformed json -> skip"
  exit 0
fi

# Parse (never eval) the subagent's agent_type from the payload. Valid JSON
# with an empty/missing agent_type yields an empty string, which legitimately
# falls through to the not-allowlisted branch below.
agent_type="$(agy_hooks_parse_field "$input" agent_type)"

# Guard 5: the subagent's agent_type must be allowlisted.
if ! agy_hooks_agent_allowed "$agent_type"; then
  agy_hooks_debug "not allowlisted: '${agent_type}' -> skip"
  exit 0
fi

# Guard 6: agy-bridge must actually be available on PATH.
if ! command -v agy-bridge >/dev/null 2>&1; then
  agy_hooks_debug "agy-bridge not on PATH -> skip"
  exit 0
fi

# All guards passed: emit the fixed advisory as SubagentStart
# additionalContext. The advisory is a fixed python constant -- it is NEVER
# built via shell string interpolation, and the incoming prompt/payload is
# never echoed.
python3 <<'PYEOF'
import json

advisory = """For bulk, fan-out, or web-search work you can delegate to agy via the `agy-bridge` command (run `agy-bridge --help`; e.g. `echo "<task>" | agy-bridge --type search`). It has grounded web search (with source URLs) and extended-context reading. The judgment stays with you: skip it for small or judgment-heavy tasks, and always verify agy's output."""

output = {
    "hookSpecificOutput": {
        "hookEventName": "SubagentStart",
        "additionalContext": advisory,
    }
}
print(json.dumps(output))
PYEOF

agy_hooks_debug "fired"

exit 0
