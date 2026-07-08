# agy-hooks-lib.sh
#
# Sourced-only bash function library for agy delegation hooks.
# This file MUST NOT be executed directly and MUST NOT produce any
# top-level side effects (no output, no `set -e`/`set -u` leakage into
# the sourcing shell, no unguarded double-source work).
#
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/agy-hooks-lib.sh"

# Include guard: sourcing this file twice must be a cheap no-op.
if [ -n "${_AGY_HOOKS_LIB_SOURCED:-}" ]; then
  return 0
fi
_AGY_HOOKS_LIB_SOURCED=1

# agy_hooks_enabled
#   Returns 0 (true) iff AGY_HOOKS_ENABLED is one of: 1, true, on, yes
#   (case-insensitive). Default (unset/anything else) is disabled.
agy_hooks_enabled() {
  local v="${AGY_HOOKS_ENABLED:-}"
  v="$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]')"
  case "$v" in
    1|true|on|yes)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# agy_hooks_agent_allowed <agent_type>
#   Returns 0 iff <agent_type> is allowed per AGY_HOOKS_AGENT_TYPES (CSV).
#   Entries are trimmed of leading/trailing whitespace before comparison.
#   Matching is exact and case-sensitive:
#     - A namespaced entry (contains ':') matches ONLY an exact full-string
#       equal agent_type (no wildcarding).
#     - A bare entry (no ':') matches an agent_type that is exactly equal
#       to it, OR a namespaced agent_type whose suffix after the last ':'
#       equals it (bare entries act as a cross-namespace suffix wildcard).
agy_hooks_agent_allowed() {
  local agent_type="$1"
  local list="${AGY_HOOKS_AGENT_TYPES:-general-purpose,Explore,metaswarm:researcher-agent,metaswarm:coder-agent,metaswarm:code-review-agent}"
  local -a entries
  IFS=',' read -ra entries <<< "$list"

  local entry suffix
  for entry in "${entries[@]}"; do
    # trim leading whitespace
    entry="${entry#"${entry%%[![:space:]]*}"}"
    # trim trailing whitespace
    entry="${entry%"${entry##*[![:space:]]}"}"

    [ -z "$entry" ] && continue

    if [[ "$entry" == *:* ]]; then
      # Namespaced entry: exact full-string match only, no wildcarding.
      if [ "$entry" = "$agent_type" ]; then
        return 0
      fi
    else
      # Bare entry: exact match, or suffix-after-last-colon match.
      if [ "$entry" = "$agent_type" ]; then
        return 0
      fi
      suffix="${agent_type##*:}"
      if [ "$entry" = "$suffix" ]; then
        return 0
      fi
    fi
  done

  return 1
}

# agy_hooks_parse_field <json_string> <field>
#   Echoes the top-level string value of <field> from <json_string>.
#   Echoes an empty string if the field is missing, not a string, or the
#   JSON is invalid. All parsing goes through python3's json module
#   (never eval). The python process always exits 0.
agy_hooks_parse_field() {
  local json_string="$1"
  local field="$2"

  printf '%s' "$json_string" | python3 -c '
import sys, json

data = sys.stdin.read()
field = sys.argv[1]
try:
    obj = json.loads(data)
    v = obj.get(field, "")
    print(v if isinstance(v, str) else "")
except Exception:
    print("")
' "$field"
}

# agy_hooks_debug <reason>
#   If AGY_HOOKS_DEBUG=1, writes exactly one timestamped line containing
#   <reason> to $AGY_HOOKS_DEBUG_FILE (append) if set, else to stderr.
#   Never includes prompt/prompt-id content (callers must not pass any).
#   No-op if debug is off.
agy_hooks_debug() {
  local reason="$1"

  [ "${AGY_HOOKS_DEBUG:-}" = "1" ] || return 0

  local ts
  ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  local line="[${ts}] agy-hooks: ${reason}"

  if [ -n "${AGY_HOOKS_DEBUG_FILE:-}" ]; then
    printf '%s\n' "$line" >> "$AGY_HOOKS_DEBUG_FILE"
  else
    printf '%s\n' "$line" >&2
  fi
}
