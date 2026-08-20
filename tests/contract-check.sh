#!/usr/bin/env bash
# contract-check.sh -- interrogates the REAL Antigravity CLI (`agy`) and
# reports which of this plugin's assumptions still hold.
#
# This talks to the real agy binary and spends real quota. `agy --version`
# and `agy models` are free and non-generating; later plans in this phase add
# probes that issue real, billed delegations, and the trailing summary block
# always states how many billed calls a run made. This slice makes zero
# billed calls.
#
# Repo-local operator tool (D-01): not shipped, not installed, no launcher.
# `bash tests/contract-check.sh` is the only way to run it. It is never
# reached by `bash tests/run-tests.sh`, which drives it (when it does) only
# under a sanitized PATH holding no real `agy` (D-02).
#
# Exit codes -- disjoint from R5's 2 / 3 / 124 / 127 / 137 (D-06, D-07):
#   0  every assumption verified
#   10 at least one assumption unverified (could not ask)
#   11 at least one assumption contradicted (outranks 10 when both are present)
# A bounded probe that times out internally sees run_bounded's 124 in its own
# evidence text; that 124 never becomes this script's exit status.
#
# The seven D-09 assumption names this check answers across Phase 1.5 (this
# slice answers only the first; the rest are built in later plans on this
# proven slice):
#   agy-version-shape        the `agy --version` string shape (this slice)
#   models-format             what `agy models` emits
#   model-arg-accepts          whether --model accepts ids, display names, or both
#   gemini-md-binds              whether a per-run GEMINI.md actually binds
#   invalid-model-rejection        the rejection shape for a bogus --model value
#   non-gemini-rows                  non-`gemini-` rows present in the live list
#   sigterm-ignored                    whether agy ignores SIGTERM
#
# AGY_CONTRACT_TIMEOUT  bounds every probe this check makes of agy itself.
#                       Default 30. A value not matching ^[1-9][0-9]*$
#                       (including 0, which coreutils `timeout` reads as *no
#                       timeout*) is corrected to 30 with a warning --
#                       never accepted, never used to disable a bound.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
FIXTURES="$HERE/fixtures"

# Duplicate of this script's ORIGINAL stderr, before any call site redirects
# fd 2 into a capture file. Bounding diagnostics go here and nowhere else.
exec 9>&2

# ── Bounding-binary probe ────────────────────────────────────────────────────
if command -v timeout &>/dev/null; then
    TIMEOUT_BIN="timeout"
elif command -v gtimeout &>/dev/null; then
    TIMEOUT_BIN="gtimeout"
else
    TIMEOUT_BIN=""
    # Same literal as scripts/agy_bridge.sh:36 -- RB03 pins this wording
    # against README, and a paraphrase here would create a second wording of
    # the same operator-visible sentence.
    RB_NO_TIMEOUT_WARN='WARNING: timeout/gtimeout not found -- bounding agy with the bash watchdog fallback; install coreutils for process-group kill'
    echo "$RB_NO_TIMEOUT_WARN" >&2
fi

# AGY_CONTRACT_TIMEOUT: validate-and-correct, never reject, never accept a
# value coreutils `timeout` reads as no-timeout.
AGY_CONTRACT_TIMEOUT="${AGY_CONTRACT_TIMEOUT:-30}"
if ! [[ "$AGY_CONTRACT_TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
    echo "WARNING: AGY_CONTRACT_TIMEOUT='${AGY_CONTRACT_TIMEOUT}' is not a positive integer -- corrected to 30" >&9
    AGY_CONTRACT_TIMEOUT=30
fi

# Bound on the `agy models` fetch, matching scripts/agy_bridge.sh:39-46's
# knob exactly -- same name, same default (20), same ^[1-9][0-9]*$ shape.
# Corrected rather than rejected, same as AGY_CONTRACT_TIMEOUT above: this is
# diagnostic tooling, not the production bridge, and never hard-exits on a
# malformed env var.
AGY_MODELS_TIMEOUT="${AGY_MODELS_TIMEOUT:-20}"
if ! [[ "$AGY_MODELS_TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
    echo "WARNING: AGY_MODELS_TIMEOUT='${AGY_MODELS_TIMEOUT}' is not a positive integer -- corrected to 20" >&9
    AGY_MODELS_TIMEOUT=20
fi

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

# AGY_BIN: resolve exactly as scripts/agy_bridge.sh:23 does, so $0 inside a
# PATH-resolved fake is an absolute path. Absence is a verdict input, not a
# fatal error -- the "could not ask" path is a required deliverable (D-08).
AGY_BIN="$(command -v agy 2>/dev/null || true)"

# ── Exit-code contract (D-06, D-07) ──────────────────────────────────────────
readonly CC_EXIT_OK=0
readonly CC_EXIT_UNVERIFIED=10
readonly CC_EXIT_CONTRADICTED=11

_CC_N_UNVERIFIED=0
_CC_N_CONTRADICTED=0
_CC_GAP_NAMES=()
_CC_AGY_VERSION=""
_CC_BILLED=0
_CC_SIDE_EFFECTS="none"

# _cc_row NAME VERDICT EVIDENCE -- prints one ledger row immediately (rows
# stream as each probe finishes; only the summary trails) and scores it into
# the exit-code counters. Fixed declared call order in the probe-running
# section below is what keeps row order fixed across runs (edge:ordering).
_cc_row() {
    local name="$1" verdict="$2" evidence="$3"
    printf '%-24s %-12s %s\n' "$name" "$verdict" "$evidence"
    case "$verdict" in
        unverified)
            _CC_N_UNVERIFIED=$((_CC_N_UNVERIFIED + 1))
            _CC_GAP_NAMES+=("$name (unverified)")
            ;;
        contradicted)
            _CC_N_CONTRADICTED=$((_CC_N_CONTRADICTED + 1))
            _CC_GAP_NAMES+=("$name (contradicted)")
            ;;
    esac
}

# _cc_row_note NAME VERDICT EVIDENCE -- the non-scoring sibling. Same
# three-column shape, evidence prefixed to mark the row as not one of the
# seven D-09 assumptions. Touches NEITHER counter, by construction: this is
# the F7 fix -- a capture-attempt row (plan 01.5-05's empty-success-capture)
# must be visible in the ledger without moving a healthy run's exit status.
_cc_row_note() {
    local name="$1" verdict="$2" evidence="$3"
    printf '%-24s %-12s %s\n' "$name" "$verdict" "capture attempt (not a D-09 assumption): $evidence"
}

# _cc_fixture NAME CONTENT_FILE VERDICT -- writes $FIXTURES/$NAME atomically:
# header lines first (name, agy version, ISO capture date), then the raw
# captured bytes with no normalization, into $FIXTURES/$NAME.tmp, then `mv`
# into place. Refuses to write when VERDICT is not "verified" (edge:empty).
# The atomic rename is what leaves either the previous fixture or none at
# all on an interrupted capture (edge:concurrency).
_cc_fixture() {
    local name="$1" content_file="$2" verdict="$3"
    [[ "$verdict" == "verified" ]] || return 0
    mkdir -p "$FIXTURES"
    local tmp="$FIXTURES/$name.tmp"
    {
        printf '# %s -- captured by tests/contract-check.sh\n' "$name"
        printf '# agy-version: %s\n' "${_CC_AGY_VERSION:-unknown}"
        printf '# captured: %s\n' "$(date +%F)"
        cat "$content_file"
    } > "$tmp"
    mv "$tmp" "$FIXTURES/$name"
}

# _cc_preflight -- D-13's gate. Runs the two cheapest, non-generating calls
# EXACTLY ONCE for the whole run: bounded `agy --version` (consumed below by
# _cc_probe_agy_version_shape, never called a second time) and bounded
# `agy models` (consumed by _cc_probe_models_format and
# _cc_probe_non_gemini_rows). Captures land in a scratch dir that survives
# for the life of the script (cleaned up via the EXIT trap set here, not
# per-probe) because two later probes both need to read the same models
# capture. Sets _CC_PREFLIGHT_OK; on failure, every delegation-dependent
# probe below reads _CC_PREFLIGHT_REASON instead of attempting its own call
# -- the worst case for an unreachable or unauthenticated agy is two bounded
# failures, never three-plus billed timeouts.
_CC_PREFLIGHT_OK=0
_CC_PREFLIGHT_REASON=""
_CC_VERSION_OUT="" _CC_VERSION_ERR="" _CC_VERSION_RC=1
_CC_MODELS_OUT="" _CC_MODELS_ERR="" _CC_MODELS_RC=1

_cc_preflight() {
    _CC_SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/cc-preflight.XXXXXX")"
    trap '[[ -n "${_CC_SCRATCH:-}" ]] && rm -rf "$_CC_SCRATCH"' EXIT

    _CC_VERSION_OUT="$_CC_SCRATCH/version.stdout"
    _CC_VERSION_ERR="$_CC_SCRATCH/version.stderr"
    _CC_MODELS_OUT="$_CC_SCRATCH/models.stdout"
    _CC_MODELS_ERR="$_CC_SCRATCH/models.stderr"

    if [[ -z "$AGY_BIN" ]]; then
        _CC_PREFLIGHT_REASON="no agy on PATH; command -v agy did not resolve"
        return 0
    fi

    # File capture, never command substitution: fd 9 is inherited by the
    # bounded child, and a surviving descendant under $(...) would hold this
    # capture pipe open forever (tests/run-tests.sh:152-168's rationale).
    run_bounded "$AGY_CONTRACT_TIMEOUT" 5 -- "$AGY_BIN" --version \
        > "$_CC_VERSION_OUT" 2> "$_CC_VERSION_ERR"
    _CC_VERSION_RC=$?

    if [[ "$_CC_VERSION_RC" -ne 0 ]]; then
        _CC_PREFLIGHT_REASON="agy --version failed (run_bounded rc=$_CC_VERSION_RC)"
        return 0
    fi

    # </dev/null: scripts/agy_bridge.sh:476 redirects the models fetch's
    # stdin the same way. Without it agy blocks reading a stdin that a
    # scripted caller never provides -- observed live, not theoretical.
    # Bound and kill-after (3) match the bridge's own fetch exactly.
    run_bounded "$AGY_MODELS_TIMEOUT" 3 -- "$AGY_BIN" models < /dev/null \
        > "$_CC_MODELS_OUT" 2> "$_CC_MODELS_ERR"
    _CC_MODELS_RC=$?

    if [[ "$_CC_MODELS_RC" -ne 0 ]]; then
        _CC_PREFLIGHT_REASON="agy models failed (run_bounded rc=$_CC_MODELS_RC)"
        return 0
    fi

    _CC_PREFLIGHT_OK=1
}

# _cc_probe_agy_version_shape -- D-09's assumption 7. Consumes _cc_preflight's
# already-captured `agy --version` output; never calls run_bounded itself.
_cc_probe_agy_version_shape() {
    local name="agy-version-shape"

    if [[ -z "$AGY_BIN" ]]; then
        _cc_row "$name" unverified "no agy on PATH; command -v agy did not resolve"
        return 0
    fi

    if [[ "$_CC_VERSION_RC" -ne 0 ]]; then
        _cc_row "$name" unverified "run_bounded rc=$_CC_VERSION_RC bounding 'agy --version' (a 124 here is the bound firing, not this check's own exit status)"
        return 0
    fi

    if [[ ! -s "$_CC_VERSION_OUT" ]]; then
        _cc_row "$name" unverified "rc=0 with empty stdout"
        return 0
    fi

    local first_line
    first_line="$(head -n1 "$_CC_VERSION_OUT")"
    # Shape check, not a pinned literal: no known-good version string is
    # compared against agy's answer anywhere in this file.
    if [[ "$first_line" =~ ^[0-9]+(\.[0-9]+)+([[:space:]].*)?$ ]]; then
        _CC_AGY_VERSION="$first_line"
        _cc_row "$name" verified "agy --version -> \"$first_line\""
        _cc_fixture "agy-version.txt" "$_CC_VERSION_OUT" verified
        _CC_SIDE_EFFECTS="wrote tests/fixtures/agy-version.txt"
    else
        _cc_row "$name" contradicted "agy --version -> \"$first_line\" (not version-shaped)"
    fi
}

# _cc_probe_models_format -- D-09's assumption 1: what `agy models` actually
# emits. Verdict from shape (row count, TAB separator), never from equality
# against a remembered list -- this check re-derives, it does not assert.
_cc_probe_models_format() {
    local name="models-format"

    if [[ -z "$AGY_BIN" ]]; then
        _cc_row "$name" unverified "no agy on PATH; command -v agy did not resolve"
        return 0
    fi
    if [[ "$_CC_PREFLIGHT_OK" -ne 1 ]]; then
        _cc_row "$name" unverified "preflight failed: $_CC_PREFLIGHT_REASON"
        return 0
    fi
    if [[ ! -s "$_CC_MODELS_OUT" ]]; then
        _cc_row "$name" unverified "rc=0 with empty stdout"
        return 0
    fi

    local total tabbed notab
    total=$(grep -c . "$_CC_MODELS_OUT")
    if [[ "$total" -eq 0 ]]; then
        _cc_row "$name" unverified "rc=0 but zero data rows"
        return 0
    fi

    # Exactly one TAB per row: id<TAB>display name, the shape
    # scripts/agy_bridge.sh's own `cut -f1` normalization assumes.
    tabbed=$(grep -cE $'^[^\t]+\t[^\t]*$' "$_CC_MODELS_OUT")
    notab=$(( total - tabbed ))

    if [[ "$notab" -gt 0 ]]; then
        local offender
        offender="$(grep -vE $'^[^\t]+\t[^\t]*$' "$_CC_MODELS_OUT" | head -n1)"
        _cc_row "$name" contradicted "$notab of $total rows lack the id<TAB>display-name separator; first offender: \"$offender\""
        return 0
    fi

    _cc_row "$name" verified "$total rows, every row carried exactly one TAB (id<TAB>display name)"
    _cc_fixture "agy-models.tsv" "$_CC_MODELS_OUT" verified
}

# _cc_probe_non_gemini_rows -- D-09's assumption 5: does the shipped anchored
# selection (scripts/agy_bridge.sh's own `cut -f1` normalization plus both
# `grep -E ... | sort -V | tail -1` matchers, re-derived verbatim below)
# actually exclude every non-`gemini-` row. Never widened or loosened here --
# this probe reports what the shipped anchors do, not what would make it pass.
_cc_probe_non_gemini_rows() {
    local name="non-gemini-rows"

    if [[ -z "$AGY_BIN" ]]; then
        _cc_row "$name" unverified "no agy on PATH; command -v agy did not resolve"
        return 0
    fi
    if [[ "$_CC_PREFLIGHT_OK" -ne 1 ]]; then
        _cc_row "$name" unverified "preflight failed: $_CC_PREFLIGHT_REASON"
        return 0
    fi
    if [[ ! -s "$_CC_MODELS_OUT" ]]; then
        _cc_row "$name" unverified "rc=0 with empty stdout"
        return 0
    fi

    local ids
    # cut -f1: byte-identical to scripts/agy_bridge.sh:463-532's own
    # normalization before its anchored matchers run.
    ids="$(cut -f1 "$_CC_MODELS_OUT")"
    if [[ -z "$ids" ]]; then
        _cc_row "$name" unverified "rc=0 but zero data rows"
        return 0
    fi

    local gemini_count nongemini flash_sel pro_sel
    gemini_count=$(printf '%s\n' "$ids" | grep -c '^gemini-')
    nongemini=$(printf '%s\n' "$ids" | grep -vc '^gemini-')
    flash_sel="$(printf '%s\n' "$ids" | grep -E '^gemini-[0-9.]+-flash-high$' | sort -V | tail -1)"
    pro_sel="$(printf '%s\n' "$ids" | grep -E '^gemini-[0-9.]+-pro-high$' | sort -V | tail -1)"

    if [[ "$gemini_count" -eq 0 ]]; then
        _cc_row "$name" contradicted "$nongemini non-gemini rows present; normalized list contains no 'gemini-' id at all (the degraded-list shape the bridge exits 2 on)"
        return 0
    fi

    if [[ ( -n "$flash_sel" && "$flash_sel" != gemini-* ) || ( -n "$pro_sel" && "$pro_sel" != gemini-* ) ]]; then
        _cc_row "$name" contradicted "$nongemini non-gemini rows present; a shipped anchored matcher selected a non-gemini id (flash=\"$flash_sel\" pro=\"$pro_sel\")"
        return 0
    fi

    _cc_row "$name" verified "$nongemini non-gemini rows present; both anchored matchers selected gemini-prefixed ids (flash=\"$flash_sel\" pro=\"$pro_sel\")"
}

# _cc_summary -- the trailing summary block, called ONCE, after every probe
# has returned, and never before. D-04 calls this content "the header"; it is
# emitted LAST here because the billed count and final status are only known
# once the last probe returns -- a leading header could only ever carry a
# guess later plans would have to retract.
_cc_summary() {
    printf '# agy contract check -- agy-version: %s -- captured: %s -- billed delegations: %s -- side effects: %s\n' \
        "${_CC_AGY_VERSION:-unknown}" "$(date +%F 2>/dev/null || echo unknown)" "$_CC_BILLED" "$_CC_SIDE_EFFECTS"
    printf '# exit codes: 0=all verified 10=unverified present 11=contradicted present (outranks 10)\n'
    if [[ "$_CC_N_UNVERIFIED" -gt 0 || "$_CC_N_CONTRADICTED" -gt 0 ]]; then
        local IFS=', '
        printf '# gap: %s\n' "${_CC_GAP_NAMES[*]}"
    else
        printf '# gap: none\n'
    fi
}

# ── Run the probes, in this fixed declared order ────────────────────────────
_cc_preflight
_cc_probe_agy_version_shape
# RED: _cc_probe_models_format / _cc_probe_non_gemini_rows defined above but
# not yet wired in -- GREEN commit adds these two calls.

# ── Summary, exactly once, after every probe has returned ───────────────────
_cc_summary

# ── Exit-code computation, over the scoring rows only (D-06, D-07) ─────────
# Read the counters, never the printed text -- re-parsing stdout would
# silently re-include a _cc_row_note row that never touched a counter.
if [[ "$_CC_N_CONTRADICTED" -gt 0 ]]; then
    exit "$CC_EXIT_CONTRADICTED"
elif [[ "$_CC_N_UNVERIFIED" -gt 0 ]]; then
    exit "$CC_EXIT_UNVERIFIED"
else
    exit "$CC_EXIT_OK"
fi
