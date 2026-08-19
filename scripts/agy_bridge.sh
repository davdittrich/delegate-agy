#!/usr/bin/env bash
# agy_bridge.sh — Bridge for Google Antigravity CLI (agy)
#
# Usage:
#   echo "prompt" | agy_bridge.sh [OPTIONS]
#   agy_bridge.sh [OPTIONS] -- "prompt text"

set -euo pipefail

# Duplicate of this script's ORIGINAL stderr, before any call site redirects
# fd 2 into a capture file. Bounding diagnostics go here and nowhere else: at
# the delegation site below, fd 2 is captured and its contents are interpolated
# into the caller-visible error string and the JSON envelope, so a diagnostic
# written to plain stderr would corrupt a payload that must stay untouched.
# Numeric form on purpose -- the fallback this serves exists for stock macOS,
# whose shipped bash predates named descriptors.
exec 9>&2

# ── Dependency check ─────────────────────────────────────────────────────────
if ! command -v agy &>/dev/null; then
    echo "ERROR: agy not found in PATH (expected at ~/.local/bin/agy)" >&2; exit 2
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

# Bound on the `agy models` fetch. Separate from --timeout (which bounds the
# delegation call) because a hung model list must fail fast, not after 600s.
AGY_MODELS_TIMEOUT="${AGY_MODELS_TIMEOUT:-20}"
[[ "$AGY_MODELS_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || {
    echo "ERROR: AGY_MODELS_TIMEOUT must be a positive integer" >&2; exit 2
}

# --- BEGIN run_bounded ---
# Bounded invocation, redirect-transparent: the command runs in the caller's own
# stdio, so command substitution, direct file redirects, a cd-subshell and a
# piped stdin all keep exactly the capture semantics they had before.
#
# Everything between these two markers is duplicated BYTE-FOR-BYTE into
# scripts/agy_bridge.sh and never edited in one copy alone -- the two blocks are
# pinned byte-identical by the suite. What it takes from its host script, stated
# in full because the earlier "exactly two things" claim was not true and the
# gap is where three defects lived:
#   $TIMEOUT_BIN  set by the probe above; chooses the mechanism.
#   fd 9          the script's own original stderr, opened at the top. Written
#                 to, never handed on: it is closed for the bounded command.
#   fd 8          borrowed on the watchdog arm to restore the child's stderr
#                 across the job-control redirect, then CLOSED -- a caller that
#                 passed fd 8 in loses it after the first watchdog-arm call.
#   $TERM/$INT/$HUP traps  borrowed for the length of a bounded call and given
#                 back exactly as found.
#   ps            ONLY where /proc is unreadable, i.e. macOS. The procfs path
#                 needs no external binary at all.
# Add no sixth. The two-item version of this list was written when it was true
# and never revisited, which is precisely how an undeclared dependency ships.
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
    local p="$1" v="" line=""
    if [[ -r "/proc/$p/stat" ]]; then
        # Read in bash, not through awk. Two reasons, and the second is why the
        # first one matters. /proc/<pid>/stat is
        # `pid (comm) state ppid pgrp ...` and comm may contain BOTH spaces and
        # `)`, so whitespace-splitting to field 5 yields the pgrp only for a
        # single-token comm -- for a two-word comm it yields the PPID, a number
        # that survives the sanitiser below, differs from our own group, and is
        # therefore installed as a `kill -- -<pgid>` operand aimed at somebody
        # else's process group. Splitting after the LAST `") "` is correct for
        # every comm, because no field after comm can contain one. And doing it
        # here removes the external binary: without awk and without ps this
        # lookup used to return empty, the escalation degraded to a pid-only
        # kill, and the bound still reported 124 while everything agy forked
        # survived it -- silent, in the `env -i` / systemd / container contexts
        # this script's own comments name as the ones it must survive.
        read -r line < "/proc/$p/stat" 2>/dev/null || line=""
        line="${line##*') '}"
        v="${line#* }"; v="${v#* }"; v="${v%% *}"
    else
        # No procfs: macOS, and the only remaining external dependency. Declared
        # in the block header rather than left implicit.
        v=$(ps -o pgid= -p "$p" 2>/dev/null) || v=""
    fi
    # `ps -o pgid=` right-pads its one-row output; a padded value would fail
    # OPEN, both stopping the self-group comparison from matching and landing as
    # a kill operand whose embedded blank makes the target invalid -- a
    # rejection the kill's failure-tolerant suffix swallows. It also fails the
    # procfs branch closed rather than open if that branch is ever wrong again.
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

# $1=timer pid, EMPTY before the timer has started (a no-op) $2=the timer's own
# process group id, or EMPTY when it could not be confirmed distinct from ours.
# Cancelling the timer has to reap what the timer FORKED, not just the timer: the
# `sleep` it is blocked on is a separate process, so a kill aimed at the subshell
# pid alone leaves that sleep reparented to init for the rest of the bound. Both
# exits from the wait below cancel through here -- the normal return and the
# signal-relay traps -- because a timer left running past either one leaks the
# same process.
_rb_cancel_timer() {
    if [[ -z "$1" ]]; then return 0; fi
    _rb_signal TERM "$1" "$2"
    wait "$1" 2>/dev/null || true
}

# Starts the two-stage escalation ladder in the background.
#   $1 = delay before the first signal: the bound for a timeout, 0 for a relay,
#        whose signal has already arrived and is only being forwarded
#   $2 = that first signal: a timeout sends TERM, a relay forwards what it got
# Two stages because the child may ignore the first one -- agy is observed to,
# which is the whole reason every bounded site passes a positive kill_after -- so
# the second stage escalates to SIGKILL after $kill_after in both cases. That is
# the coreutils binary's behaviour for its own bound AND for a signal forwarded to
# it, and this path claims parity with it.
#
# Reads $kill_after, $child, $kill_pgid and $self_pgid from run_bounded's frame and
# publishes $timer and $timer_pgid back into it -- the same dynamic scope the trap
# strings below already resolve their $child and $kill_pgid through. Deliberate:
# returning two values any other way costs a subshell, which is precisely the job
# that must survive.
#
# The ladder's stdio is detached on purpose: an orphaned `sleep` holding the
# caller's stdout open would block a caller that captured it for the rest of the
# bound -- a 600s hang in a script that shadows `gemini` box-wide.
#
# Backgrounded under `set -m` for exactly the reason the bounded child is, and
# against the same failure: job control makes the subshell a process-group leader,
# so the `sleep` it forks inherits that group and _rb_cancel_timer reaps BOTH.
# Without it the subshell shares this script's group, the cancel reaches the
# subshell alone, and every bounded call leaks one `sleep <bound>` to init for the
# full length of its bound.
_rb_start_timer() {
    local restore=0
    case "$-" in *m*) : ;; *) restore=1 ;; esac
    {
        set -m
        ( sleep "$1";          _rb_signal "$2"  "$child" "$kill_pgid"
          sleep "$kill_after"; _rb_signal KILL "$child" "$kill_pgid"
        ) </dev/null >/dev/null 2>&1 9>&- &
        timer=$!
        if [[ "$restore" -eq 1 ]]; then set +m; fi
    } 2>/dev/null
    # The bounded child's self-kill guard, applied to the ladder for the same
    # reason: an unconfirmed or shared group must never become a `kill -- -<pgid>`
    # operand. Empty degrades _rb_cancel_timer to a direct-pid kill, which still
    # cancels the subshell -- it just cannot reap the sleep.
    timer_pgid=$(_rb_pgid_of "$timer")
    if [[ "$timer_pgid" == "$self_pgid" ]]; then timer_pgid=""; fi
}

# $1=the signal we received and are forwarding $2=the status to leave with.
# A relay is a bound teardown on a shorter fuse, not a different mechanism: the
# running ladder is replaced by one whose first stage fires immediately, so the
# child is forwarded the signal and then SIGKILLed after the same $kill_after it
# would have been given at the bound. Forwarding without escalating would park
# this `wait` for as long as the child chooses to live, which for a SIGTERM-
# ignoring agy is unbounded -- the same hang this helper exists to prevent,
# reached by the cancellation path instead of the timeout path.
#
# The status is the relay's own -- 143, 130 or 129, each the conventional
# 128 + signum. A caller-interrupted call is NOT a call the bound killed, so it
# is never relabelled 124 and RUN_BOUNDED_KILLED stays untouched -- that flag is
# set only by the branch that fired the bound. The exit here is also what keeps
# the host's cleanup honest on a relayed HUP: the host's own HUP handler does
# not exit, but our exit runs its EXIT trap, so the work directory is removed
# either way.
_rb_relay() {
    _rb_cancel_timer "$timer" "$timer_pgid"
    _rb_start_timer 0 "$1"
    wait "$child" 2>/dev/null || true
    _rb_cancel_timer "$timer" "$timer_pgid"
    exit "$2"
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
        # 9>&- and not merely tidiness: fd 9 is OUR diagnostic descriptor, and
        # under `out=$(gemini ... 2>&1)` it IS the caller's capture pipe. A
        # bounded command that inherits it hands it to everything it forks, and
        # any descendant agy leaves behind then holds that pipe open forever --
        # on a run that exited 0 in under a second. The redirection is
        # command-local, so the writes to >&9 below are unaffected.
        "$TIMEOUT_BIN" -k "$kill_after" "$secs" "$@" 9>&- || rc=$?
        # rc goes back UNCHANGED, 137 included. "Returns 124 if and only if
        # RUN_BOUNDED_KILLED is 1" is a property of the WATCHDOG arm below and
        # never of this helper -- this arm sets the flag on either code and
        # returns whichever it got, and has done since the block was written.
        # Normalising 137 to 124 here would delete the input to both hosts'
        # external-kill discriminator (137 with DURATION < the bound is an OOM
        # or an outside `kill -9`, not our escalation), so the single 124 the
        # CALLER is owed is produced at the call sites, not here.
        if [[ "$rc" -eq 124 || "$rc" -eq 137 ]]; then RUN_BOUNDED_KILLED=1; fi
        return "$rc"
    fi

    # ── bash watchdog fallback: no external binary at all ────────────────────
    local self_pgid child child_pgid kill_pgid="" restore_m=0 timer="" timer_pgid=""
    local rb_trap_term rb_trap_int rb_trap_hup
    # $BASHPID, never $$: inside a command substitution $$ still reports the
    # top-level shell, which would make the comparison below meaningless.
    self_pgid=$(_rb_pgid_of "$BASHPID")

    case "$-" in *m*) : ;; *) restore_m=1 ;; esac
    # Job control makes the shell announce background jobs. Only the enclosing
    # group's OWN stderr goes to the bit bucket; the command's stderr is
    # explicitly restored from the caller's, so an immediate fatal startup error
    # (permission denied, exec format error) is never swallowed. A blanket
    # redirect around the backgrounding construct would be a worse failure than
    # the noise it suppresses. fd 9 travels the opposite way for the opposite
    # reason -- it is closed for the child, see the coreutils arm above.
    exec 8>&2
    {
        set -m
        "$@" 2>&8 8>&- 9>&- &
        child=$!
        if [[ "$restore_m" -eq 1 ]]; then set +m; fi
    } 2>/dev/null
    exec 8>&-

    child_pgid=$(_rb_pgid_of "$child")
    if [[ -n "$child_pgid" && "$child_pgid" != "$self_pgid" ]]; then
        kill_pgid="$child_pgid"
    elif kill -0 "$child" 2>/dev/null; then
        # Gated on the child being STILL LIVE, and `kill -0` is the discriminator
        # precisely because a child that exited but has not been reaped is still
        # signalable and still has its procfs entry -- so this branch is reached
        # only once the child is fully gone, or once it is genuinely sharing our
        # group. A child that finished before the read above has no group left to
        # find, needs no kill, and left no descendant behind; warning about it
        # would fire on every fast success and make the case the warning exists
        # for -- a live child whose descendants really can survive a pid-only
        # kill -- indistinguishable from routine operation.
        echo "WARNING: run_bounded: child $child has no process group of its own; bounding it by pid only, descendants may survive" >&9
    fi

    # Relay a signal we receive ourselves to the same target the timer would use,
    # matching the coreutils binary's own forwarding contract: without this a
    # Ctrl-C leaves the child alive in a group detached from the terminal. $timer
    # is still empty while these traps are installed, which _rb_relay's own cancel
    # reads as "nothing to cancel"; installing them before the timer starts is
    # deliberate, because the reverse order would leave a window where a signal
    # kills the shell outright and leaks the whole timer instead of just the narrow
    # fork-to-assignment gap inside _rb_start_timer.
    #
    # HUP is relayed for a reason the other two do not have. Both hosts trap it
    # with a cleanup handler that DOES NOT EXIT, so bash returns from the wait
    # below with 129 the instant one arrives; the cancel then removes the only
    # thing that would still have killed the child, 129 is neither 143 nor 137 so
    # nothing escalates, and a SIGTERM-ignoring agy is left running with no bound
    # on it at all -- while the coreutils arm, which forwards whatever it was
    # sent, reaps. Measured before this line existed: hup-watchdog left both the
    # child and its fork alive 8s past a 3+2 bound, hup-coreutils left neither.
    # SIGQUIT is trapped by both hosts too and was probed the same way 5x; it
    # does not interrupt this wait on this bash, so it is deliberately not
    # relayed. The set is what was demonstrated, not what was imagined.
    #
    # Saved and restored, never cleared: `trap -` resets to DEFAULT disposition,
    # which DELETES the host's own handlers rather than giving them back -- and
    # since both hosts install their cleanup trap before the first bounded call,
    # clearing meant every later Ctrl-C killed the script with its temp directory,
    # holding the user's full prompt, still on disk. `trap -p` output is already
    # requoted by bash for re-eval and is the host's own string, never caller
    # data. The save is unconditional so an absent host trap restores as absent.
    rb_trap_term="$(trap -p TERM)"
    rb_trap_int="$(trap -p INT)"
    rb_trap_hup="$(trap -p HUP)"
    trap '_rb_relay TERM 143' TERM
    trap '_rb_relay INT 130' INT
    trap '_rb_relay HUP 129' HUP

    _rb_start_timer "$secs" TERM
    wait "$child" 2>/dev/null || rc=$?
    _rb_cancel_timer "$timer" "$timer_pgid"
    trap - TERM INT HUP
    eval "${rb_trap_term:-}"
    eval "${rb_trap_int:-}"
    eval "${rb_trap_hup:-}"

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

# ── Defaults ─────────────────────────────────────────────────────────────────
TYPE="code"
MODEL=""
TIMEOUT=""
STDIN_TIMEOUT=30
LOG_FILE=""
JSON_OUTPUT=0
VERBOSE=0
DIGEST=0
DIGEST_WARN_CHARS=2000
PROMPT_ARGS=()
ADD_DIRS=()

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
        --stdin-timeout)
            [[ $# -lt 2 ]] && { echo "ERROR: --stdin-timeout requires a value" >&2; exit 2; }
            [[ "$2" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: --stdin-timeout must be a positive integer" >&2; exit 2; }
            STDIN_TIMEOUT="$2"; shift 2 ;;
        --log-file)
            [[ $# -lt 2 ]] && { echo "ERROR: --log-file requires a value" >&2; exit 2; }
            LOG_FILE="$2"; shift 2 ;;
        --add-dir)
            [[ $# -lt 2 ]] && { echo "ERROR: --add-dir requires a value" >&2; exit 2; }
            _d=$(CDPATH='' cd -- "$2" 2>/dev/null && pwd) || { echo "ERROR: --add-dir '$2' is not a directory" >&2; exit 2; }
            # Empty fallback, not the /nonexistent one the cache paths below
            # use: this is a path COMPARISON, and a stand-in root would be a
            # directory nobody can pass as --add-dir. With HOME unset there is
            # simply no home to over-grant, which the -n guard says exactly.
            _home="${HOME:-}"
            if [[ "$_d" == "/" || ( -n "$_home" && "$_d" == "${_home%/}" ) ]]; then
                if [[ "${AGY_ALLOW_BROAD_GRANT:-0}" != "1" ]]; then
                    echo "ERROR: --add-dir '$_d' grants broad filesystem access; set AGY_ALLOW_BROAD_GRANT=1 to override" >&2; exit 2
                fi
                echo "WARNING: AGY_ALLOW_BROAD_GRANT=1 — granting broad --add-dir access to '$_d'" >&2
            fi
            ADD_DIRS+=("$_d"); shift 2 ;;
        --json)    JSON_OUTPUT=1; shift ;;
        --verbose) VERBOSE=1; shift ;;
        --digest)  DIGEST=1; shift ;;
        --digest-warn-chars)
            [[ $# -lt 2 ]] && { echo "ERROR: --digest-warn-chars requires a value" >&2; exit 2; }
            [[ "$2" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: --digest-warn-chars must be a positive integer" >&2; exit 2; }
            DIGEST_WARN_CHARS="$2"; shift 2 ;;
        --types)
            printf '%-12s %-30s %s\n' 'type' 'model' 'timeout'
            printf '%-12s %-30s %s\n' 'search' 'gemini-*-flash-high (latest)' '300s'
            printf '%-12s %-30s %s\n' 'code' 'gemini-*-pro-high (latest)' '600s'
            printf '%-12s %-30s %s\n' 'analysis' 'gemini-*-pro-high (latest)' '600s'
            printf '%-12s %-30s %s\n' 'review' 'gemini-*-pro-high (latest)' '600s'
            printf '%-12s %-30s %s\n' 'implement' 'gemini-*-pro-high (latest)' '600s'
            exit 0 ;;
        --help)
            cat <<'HELP'
agy_bridge.sh — Bridge for Google Antigravity CLI (agy)

Usage:
  echo "prompt" | agy_bridge.sh [OPTIONS]
  agy_bridge.sh [OPTIONS] -- "prompt text"

Options:
  --type search|code|review|analysis|implement
  --model "model name"       (see: agy models)
  --timeout N                seconds (default: 300 search, 600 other)
  --stdin-timeout N          seconds for stdin read (default: 30)
  --log-file PATH            write verbose metadata to file instead of stderr
  --add-dir PATH             grant agy read access to PATH (repeatable; pass
                             the narrowest sufficient directory). / and $HOME
                             refused with exit 2 unless AGY_ALLOW_BROAD_GRANT=1
                             is set (speed bump, not a containment boundary).
  --json                     output JSON envelope
  --digest                   append a digest-only output contract (compressed
                             reply: key findings + file:line, no raw echoes)
  --digest-warn-chars N      warn on stderr if a --digest reply exceeds N chars
                             (default: 2000; never truncates)
  --verbose                  diagnostics to stderr (or --log-file)
  --types                    list type/model/timeout table
  --help                     show this message
  --                         treat remaining args as prompt text

  Optional: ~/.config/agy-delegate/config.json {"lean_ctx":bool,"tokensave":bool}
  (written by /agy-setup) hints MCP availability; live-probed if absent.

HELP
            exit 0 ;;
        --)        shift; PROMPT_ARGS+=("$@"); break ;;
        --*)       echo "ERROR: unknown flag: $1" >&2; exit 2 ;;
        *)         PROMPT_ARGS+=("$1"); shift ;;
    esac
done

# ── Validate type ─────────────────────────────────────────────────────────────
TYPE_SAFE=$(printf '%s' "$TYPE" | tr -dc '[:alnum:]-_')
case "$TYPE_SAFE" in
    search|code|review|analysis|implement) TYPE="$TYPE_SAFE" ;;
    *) echo "ERROR: unknown --type '${TYPE_SAFE}'; expected search|code|review|analysis|implement" >&2; exit 2 ;;
esac

# ── Fetch/cache live model list ───────────────────────────────────────────────
# ${HOME:-} — this runs under `set -u` and the bridge is reached with HOME unset
# by systemd units without User=, `env -i`, container entrypoints and CI
# runners. An unwritable cache path degrades to fetch-every-time via the guards
# below; it may never abort the bridge. Same shape as gemini_shim.sh's.
CACHE_FILE="${HOME:-/nonexistent}/.cache/agy-bridge-models"
_agy_models=""
if [[ ! -s "$CACHE_FILE" ]] || [[ -n "$(find "$CACHE_FILE" -mmin +60 2>/dev/null)" ]]; then
    # agy ignores SIGTERM (observed: `timeout 25 agy models` still running after
    # 3+ min), so -k escalates to SIGKILL. Its stderr is kept, not discarded --
    # it is the only diagnostic when auth or the network is the real fault.
    _agy_err="$(mktemp -t agy-models-err.XXXXXX)"
    if _agy_models=$(run_bounded "$AGY_MODELS_TIMEOUT" 3 -- \
                     "$AGY_BIN" models </dev/null 2>"$_agy_err"); then
        # stderr suppressed across the whole write: an unwritable cache dir
        # (HOME unset, read-only FS) otherwise makes bash print the failed
        # redirect on every single invocation. Caching is best-effort — the
        # fetched list in $_agy_models is already usable without it.
        mkdir -p "${CACHE_FILE%/*}" 2>/dev/null || true
        { printf '%s' "$_agy_models" > "$CACHE_FILE.tmp.$$" \
            && mv "$CACHE_FILE.tmp.$$" "$CACHE_FILE"; } 2>/dev/null || true
        chmod 600 "$CACHE_FILE" 2>/dev/null || true
    else
        _agy_rc=$?
        _agy_models=""
        if [[ "$_agy_rc" -eq 124 || "$_agy_rc" -eq 137 ]]; then
            _agy_why="timed out after ${AGY_MODELS_TIMEOUT}s"
        else
            _agy_why="exited $_agy_rc"
        fi
        if [[ -s "$CACHE_FILE" ]]; then
            echo "WARNING: 'agy models' $_agy_why; using the stale cached list." >&2
        else
            echo "ERROR: 'agy models' $_agy_why and no cached list is available." >&2
        fi
        [[ -s "$_agy_err" ]] && sed 's/^/       agy: /' "$_agy_err" >&2
    fi
    rm -f "$_agy_err"
fi
VALID_MODELS="${_agy_models:-}"
if [[ -z "$VALID_MODELS" ]]; then
    VALID_MODELS=$(cat "$CACHE_FILE" 2>/dev/null) || true
fi
[[ -n "$VALID_MODELS" ]] || { echo "ERROR: failed to retrieve model list from agy" >&2; exit 2; }
# agy models emits "id<TAB>display name". Keep only the id so the anchored
# matches below (both '$'-anchored) still hold. Applied after the cache read too,
# so caches written by an older bridge normalize on load. Tab-free lines pass through.
VALID_MODELS=$(printf '%s\n' "$VALID_MODELS" | cut -f1)

# A list with no gemini ids at all is a degraded agy (unauthenticated, or an
# output format change), NOT a bad --type. Say which, so the next reader does
# not go hunting through --type and --model flags.
if ! printf '%s\n' "$VALID_MODELS" | grep -q '^gemini-'; then
    echo "ERROR: agy model list contains no 'gemini-' ids; agy may be unauthenticated" >&2
    echo "       or its 'agy models' output format changed. Run 'agy models' to inspect." >&2
    exit 2
fi

# ── Model auto-selection / validation ─────────────────────────────────────────
if [[ -z "$MODEL" ]]; then
    case "$TYPE" in
        search) MODEL=$(printf '%s\n' "$VALID_MODELS" | grep -E '^gemini-[0-9.]+-flash-high$' | sort -V | tail -1) || true ;;
        *)      MODEL=$(printf '%s\n' "$VALID_MODELS" | grep -E '^gemini-[0-9.]+-pro-high$' | sort -V | tail -1) || true ;;
    esac
    [[ -n "$MODEL" ]] || { echo "ERROR: no gemini model for --type '$TYPE' in agy models" >&2; exit 2; }
else
    if ! printf '%s\n' "$VALID_MODELS" | grep -qxF "$MODEL"; then
        echo "ERROR: unknown --model '${MODEL}'; run 'agy models' for valid names" >&2; exit 2
    fi
fi

# ── Default timeout ───────────────────────────────────────────────────────────
if [[ -z "$TIMEOUT" ]]; then
    case "$TYPE" in
        search) TIMEOUT=300 ;;
        *)      TIMEOUT=600 ;;
    esac
fi

# ── Temp files ───────────────────────────────────────────────────────────────
WORK_DIR=$(mktemp -d -t "agy-bridge.XXXXXX")
PROMPT_FILE="$WORK_DIR/prompt"
STDOUT_FILE="$WORK_DIR/stdout"
STDERR_FILE="$WORK_DIR/stderr"
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT QUIT TERM

# ── Per-type tool restrictions via GEMINI.md ──────────────────────────────────
# agy reads GEMINI.md from CWD as binding instructions. Bridge runs agy from
# WORK_DIR so the restriction file is always the authoritative context source.
# Prompts must be self-contained; orchestrators embed needed code in the prompt.
POLICY_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)/../config/policies"
case "$TYPE" in
    search)        _POLICY_FILE="$POLICY_DIR/search.md" ;;
    review|analysis) _POLICY_FILE="$POLICY_DIR/review-analysis.md" ;;
    code)          _POLICY_FILE="$POLICY_DIR/code.md" ;;
    implement)     _POLICY_FILE="$POLICY_DIR/implement.md" ;;
esac
cat "$_POLICY_FILE" > "$WORK_DIR/GEMINI.md" \
    || { echo "ERROR: policy file missing: $_POLICY_FILE" >&2; exit 2; }

# ── Read prompt ───────────────────────────────────────────────────────────────
if [[ ${#PROMPT_ARGS[@]} -gt 0 ]]; then
    printf '%s\n' "${PROMPT_ARGS[@]}" > "$PROMPT_FILE"
elif [[ ! -t 0 ]]; then
    # kill_after is 1, not the 5 the agy calls use: it is a positive integer
    # because the helper requires one -- a zero would disable bounding -- and no
    # larger, because the escalation those 5s exist for is agy ignoring SIGTERM
    # and `cat` does not ignore it. This is the guard interval before SIGKILL,
    # not a grace period anything here needs.
    run_bounded "$STDIN_TIMEOUT" 1 -- cat > "$PROMPT_FILE" || {
        echo "ERROR: stdin read timed out after ${STDIN_TIMEOUT}s" >&2; exit 2
    }
else
    echo "ERROR: no prompt (no stdin, no -- args)" >&2; exit 2
fi

if ! grep -q '[^[:space:]]' "$PROMPT_FILE"; then
    echo "ERROR: empty prompt" >&2; exit 2
fi

# ── Search prefix ─────────────────────────────────────────────────────────────
if [[ "$TYPE" == "search" ]] && ! grep -q "search_web" "$PROMPT_FILE"; then
    printf 'Use your search_web tool to answer this query. Cite sources with URLs.\n\n' \
        > "$WORK_DIR/prefix.tmp"
    cat "$PROMPT_FILE" >> "$WORK_DIR/prefix.tmp"
    mv "$WORK_DIR/prefix.tmp" "$PROMPT_FILE"
fi

# ── Digest output contract (appended LAST) ────────────────────────────────────
# Placed after the prompt so the constraint lands at the end — Gemini can drop a
# negative/format constraint that appears too early in a long prompt. The digest
# instruction is the biggest cost lever for bulk delegation: it collapses the reply
# to a compressed digest instead of a raw dump, keeping the caller's context lean.
if [[ "$DIGEST" -eq 1 ]]; then
    printf '\n\n---\nOUTPUT CONTRACT (digest): Return ONLY a compressed digest — key findings, decisions, and file:line references. Do NOT echo file contents or restate the input. Omit preamble and narration.\n' \
        >> "$PROMPT_FILE"
fi

# ── Verbose metadata output (metadata only — no prompt content) ───────────────
if [[ "$VERBOSE" -eq 1 ]]; then
    _verbose_msg=$(printf '[agy_bridge] type=%s model=%s timeout=%ss\n' "$TYPE" "$MODEL" "$TIMEOUT")
    if [[ -n "$LOG_FILE" ]]; then
        printf '%s\n' "$_verbose_msg" >> "$LOG_FILE"
    else
        printf '%s\n' "$_verbose_msg" >&2
    fi
fi

# ── Embed the assembled prompt into GEMINI.md (agy auto-loads it; no read_file
#    tool needed, so this works even under search.md's read_file restriction).
#    Keeps the prompt OFF argv/ps and lifts the ARG_MAX single-arg cap. ──
{ printf '\n\n---\nTASK:\n' >> "$WORK_DIR/GEMINI.md" \
    && cat "$PROMPT_FILE" >> "$WORK_DIR/GEMINI.md" \
    && chmod 600 "$WORK_DIR/GEMINI.md"; } \
    || { echo "ERROR: failed to embed prompt into GEMINI.md" >&2; exit 2; }

# ── MCP-server autodetect (cached 60-min, config-hint fast-path, live fallback) ─
# Bias agy toward lean-ctx/tokensave reads ONLY for MCP-permitted types. The
# stanza is advisory GEMINI.md text — it does NOT relax --sandbox/--add-dir.
_MCP_LEANCTX=0; _MCP_TOKENSAVE=0
if command -v python3 >/dev/null 2>&1; then
    # Guarded like CACHE_FILE above: HOME may be unset, and this block runs on
    # every delegation. A missing home degrades to autodetect-every-time.
    _MCP_CACHE="${HOME:-/nonexistent}/.cache/agy-bridge-mcp"
    if [[ -s "$_MCP_CACHE" ]] && [[ -z "$(find "$_MCP_CACHE" -mmin +60 2>/dev/null)" ]]; then
        _MCP_LEANCTX=$(sed -n '1p' "$_MCP_CACHE" 2>/dev/null)
        _MCP_TOKENSAVE=$(sed -n '2p' "$_MCP_CACHE" 2>/dev/null)
    else
        read _MCP_LEANCTX _MCP_TOKENSAVE < <(python3 - \
            "${HOME:-/nonexistent}/.config/agy-delegate/config.json" \
            "${HOME:-/nonexistent}/.gemini/antigravity-cli/mcp_config.json" <<'PY'
import sys, json, os
hint, live = sys.argv[1], sys.argv[2]
lc = ts = False
def rd(p):
    try: return json.load(open(p))
    except Exception: return None
d = rd(hint) if os.path.exists(hint) else None
if isinstance(d, dict):
    lc = d.get('lean_ctx') is True; ts = d.get('tokensave') is True
else:
    d = rd(live) if os.path.exists(live) else None
    if isinstance(d, dict):
        s = d.get('mcpServers', {}) or {}
        lc = 'lean-ctx' in s; ts = 'tokensave' in s
print(f"{int(lc)} {int(ts)}")
PY
)
        _MCP_LEANCTX="${_MCP_LEANCTX:-0}"; _MCP_TOKENSAVE="${_MCP_TOKENSAVE:-0}"
        mkdir -p "${_MCP_CACHE%/*}" 2>/dev/null || true
        { printf '%s\n%s\n' "$_MCP_LEANCTX" "$_MCP_TOKENSAVE" > "$_MCP_CACHE.tmp.$$" \
            && mv "$_MCP_CACHE.tmp.$$" "$_MCP_CACHE"; } 2>/dev/null || true
        chmod 600 "$_MCP_CACHE" 2>/dev/null || true
    fi
fi
# MCP-permitted types = the SAME $TYPE the policy case uses; search + shim excluded.
if [[ "$TYPE" =~ ^(code|review|analysis|implement)$ ]] \
   && { [[ "$_MCP_LEANCTX" == "1" ]] || [[ "$_MCP_TOKENSAVE" == "1" ]]; }; then
    printf '\n---\nTOOL PREFERENCE: when reading files or inspecting code structure, prefer the lean-ctx tools (ctx_read/ctx_search) and tokensave_context over raw full-file dumps — they are token-efficient. Standard file tools remain available within your sandbox.\n' \
        >> "$WORK_DIR/GEMINI.md"
fi
AGY_POINTER='Complete the TASK described in your GEMINI.md context. Output only the result.'

# ── Run agy ──────────────────────────────────────────────────────────────────
# Run from WORK_DIR so agy reads the type-specific GEMINI.md tool restrictions.
# Prompt is embedded in the 0600 GEMINI.md; only the static pointer is passed as
# the --print value, so it still never appears in ps/proc/cmdline, and there is
# no ARG_MAX single-arg cap on prompt size.
START=$SECONDS
EXIT_CODE=0
set +e
AGY_FLAGS=(--print "$AGY_POINTER" --sandbox --model "$MODEL")
for _d in ${ADD_DIRS[@]+"${ADD_DIRS[@]}"}; do
    AGY_FLAGS+=(--add-dir "$_d")
done
AGY_FLAGS+=(--add-dir "$WORK_DIR")
if [[ "${AGY_SKIP_PERMISSIONS:-0}" == "1" ]]; then
    echo "WARNING: AGY_SKIP_PERMISSIONS=1 — running with --dangerously-skip-permissions" >&2
    AGY_FLAGS+=(--dangerously-skip-permissions)
fi
# -k 5: agy ignores SIGTERM (observed), so plain `timeout` would send the
# signal and then block forever waiting for a child that never dies.
( cd "$WORK_DIR" && run_bounded "$TIMEOUT" 5 -- "$AGY_BIN" \
    "${AGY_FLAGS[@]}" \
    > "$STDOUT_FILE" \
    2> "$STDERR_FILE" \
    < /dev/null )
EXIT_CODE=$?
set -e
DURATION=$(( SECONDS - START ))

# ── Handle errors ─────────────────────────────────────────────────────────────
if [[ "$EXIT_CODE" -eq 137 && "$DURATION" -lt "$TIMEOUT" ]]; then
    # A 137 (SIGKILL) landing BEFORE our own $TIMEOUT bound cannot be the -k
    # escalation above -- that can only fire at/after $TIMEOUT elapses. It's an
    # external kill (OOM killer, `kill -9`, cgroup/container preemption).
    # Report it distinctly: "raise --timeout" is useless advice against an OOM.
    if [[ "$JSON_OUTPUT" -eq 1 ]]; then
        python3 -c "
import json, sys
print(json.dumps({'success':False,'model_used':sys.argv[1],'type':sys.argv[2],'duration_seconds':int(sys.argv[3]),'error':sys.argv[4] + ': ' + open(sys.argv[5]).read()}))
" "$MODEL" "$TYPE" "$DURATION" "Killed (signal 9) after ${DURATION}s, before its ${TIMEOUT}s bound -- possible OOM or external kill" "$STDERR_FILE" || true
    else
        printf 'ERROR: agy killed (signal 9) after %ds, before its %ds bound -- possible OOM or external kill: %s\n' "$DURATION" "$TIMEOUT" "$(cat "$STDERR_FILE" 2>/dev/null || true)" >&2
    fi
    exit "$EXIT_CODE"
elif [[ "$EXIT_CODE" -eq 124 || "$EXIT_CODE" -eq 137 ]]; then
    if [[ "$JSON_OUTPUT" -eq 1 ]]; then
        python3 -c "
import json, sys
print(json.dumps({'success':False,'model_used':sys.argv[1],'type':sys.argv[2],'duration_seconds':int(sys.argv[3]),'error':sys.argv[4]}))
" "$MODEL" "$TYPE" "$DURATION" "Timeout after ${TIMEOUT}s"
    else
        printf 'ERROR: agy timeout after %ds\n' "$TIMEOUT" >&2
    fi
    exit 124
elif [[ "$EXIT_CODE" -ne 0 ]]; then
    if [[ "$JSON_OUTPUT" -eq 1 ]]; then
        python3 -c "
import json, sys
print(json.dumps({'success':False,'model_used':sys.argv[1],'type':sys.argv[2],'duration_seconds':int(sys.argv[3]),'error':open(sys.argv[4]).read()}))
" "$MODEL" "$TYPE" "$DURATION" "$STDERR_FILE" || true
    else
        printf 'ERROR: agy exit %d: %s\n' "$EXIT_CODE" "$(cat "$STDERR_FILE" 2>/dev/null || true)" >&2
    fi
    exit "$EXIT_CODE"
elif [[ ! -s "$STDOUT_FILE" ]]; then
    # Hidden failure: agy exited 0 but produced NO output. Most commonly quota
    # exhaustion — agy exits 0 with empty stdout on RESOURCE_EXHAUSTED / 429.
    # Primary signal is empty-stdout itself (cause-independent: also catches silent
    # backend/lock errors). Secondary: the FULL captured stderr becomes the reason;
    # a token match only CLASSIFIES it (never replaces the message, so auth/backend
    # errors aren't swallowed under a "quota" label).
    _reason="$(cat "$STDERR_FILE" 2>/dev/null)"
    [[ -n "$_reason" ]] || _reason="agy returned empty output (exit 0, no stdout)"
    _class="empty_output"
    case "$_reason" in
        *RESOURCE_EXHAUSTED*|*429*|*[Qq]uota*)   _class="quota" ;;
        *[Aa]uth*|*UNAUTHENTICATED*)             _class="auth" ;;
    esac
    if [[ "$JSON_OUTPUT" -eq 1 ]]; then
        python3 -c "
import json, sys
print(json.dumps({'success':False,'model_used':sys.argv[1],'type':sys.argv[2],'duration_seconds':int(sys.argv[3]),'error':sys.argv[4],'error_class':sys.argv[5]}))
" "$MODEL" "$TYPE" "$DURATION" "$_reason" "$_class"
    else
        printf 'ERROR: agy returned empty output [%s]: %s\n' "$_class" "$_reason" >&2
    fi
    exit 3
fi

# ── Digest dump-size warning (metadata only — never truncates) ────────────────
# Only when --digest was requested: a dump-sized reply means the digest contract
# was ignored and the cost lever was lost. Warn (don't alter the response).
if [[ "$DIGEST" -eq 1 ]]; then
    _resp_chars=$(wc -c < "$STDOUT_FILE" | tr -d '[:space:]')
    if [[ "$_resp_chars" -gt "$DIGEST_WARN_CHARS" ]]; then
        printf '[agy_bridge] WARNING: --digest reply is %s chars (> %s) — digest contract may have been ignored\n' \
            "$_resp_chars" "$DIGEST_WARN_CHARS" >&2
    fi
fi

# ── Output ────────────────────────────────────────────────────────────────────
if [[ "$JSON_OUTPUT" -eq 1 ]]; then
    python3 -c "
import json, sys
print(json.dumps({'success':True,'model_used':sys.argv[1],'type':sys.argv[2],'duration_seconds':int(sys.argv[3]),'response':open(sys.argv[4]).read()}))
" "$MODEL" "$TYPE" "$DURATION" "$STDOUT_FILE"
else
    cat "$STDOUT_FILE"
fi
