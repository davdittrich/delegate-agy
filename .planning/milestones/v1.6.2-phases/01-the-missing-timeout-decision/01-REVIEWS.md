---
phase: 1
reviewers: [antigravity]
reviewed_at: 2026-08-19T02:54:09+02:00
plans_reviewed:
  - 01-01-PLAN.md
  - 01-02-PLAN.md
  - 01-03-PLAN.md
  - 01-04-PLAN.md
  - 01-05-PLAN.md
  - 01-06-PLAN.md
---

# Cross-AI Plan Review — Phase 1

## Antigravity Review

# Phase 1 Implementation Plan Review: The Missing-`timeout` Decision

## 1. Summary

The Phase 1 plans (`01-01` through `01-06`) establish an airtight, resilient, and elegant solution for eliminating unbounded execution across both `scripts/agy_bridge.sh` and `scripts/gemini_shim.sh`. By adopting Decision D-01 (replacing unbounded fallbacks with an in-process native bash watchdog utilizing job control and process group signaling via `set -m` / `kill -- -$pgid`), the plans dissolve the historical bridge-versus-shim divergence rather than merely documenting it. The planning is exceptionally thorough: it incorporates rigorous adversarial findings, addresses concrete race conditions (such as fast-child PGID lookup races under `set -euo pipefail`), enforces process-tree descendant cleanup with and without PTYs, separates internal diagnostic descriptors (`fd 9`) to prevent JSON payload corruption, and locks the architectural invariants via zero-exception static linting and multi-scenario mutation tests.

---

## 2. Strengths

- **Dissolving Divergence over Patchwork (D-01, D-04):** Rather than accepting an unsafe unbounded path or a broken caller when coreutils is missing on stock macOS/BSD hosts, creating a unified `run_bounded` helper eliminates 6 fragile `if [[ -n "$TIMEOUT_BIN" ]]` branch pairs across [gemini_shim.sh:88-92, 189-193, 262-268, 316-326](file:///home/dd/Gemini/delegate-agy/.worktrees/agy-1.6.2/scripts/gemini_shim.sh#L88-L92) and [agy_bridge.sh:143-145, 231-233, 342-347](file:///home/dd/Gemini/delegate-agy/.worktrees/agy-1.6.2/scripts/agy_bridge.sh#L143-L145), reducing net lines of code while enforcing a single, uniform exit-code contract (exit 124).
- **Process Group Isolation & Descendant Reaping (D-06, D-14):** A naive shell watchdog only kills the direct PID, leaving background subprocesses/grandchildren orphaned. The design scopes `set -m`, extracts PGID, and issues `kill -- -$child_pgid`, ensuring rogue forked processes are reaped even when `timeout` is missing.
- **Defensive Pitfall Engineering (D-06a, D-06b, D-06c, D-07):**
  - *Self-Kill Guard (D-06a):* Compares child PGID against `$BASHPID` (avoiding stale `$$` inside `$(...)` subshells) to prevent the script from signaling its own process group.
  - *Guarded `/proc` + `ps` Fallback:* Prevents `set -euo pipefail` from tripping `errexit` if the child exits before PGID inspection.
  - *Signal Forwarding (D-06b):* Traps INT/TERM to relay signals to the child group on user cancellation.
  - *Clean Diagnostic Separation (D-07, D-11):* Duplicates script stderr to `fd 9` so internal watchdog diagnostics never pollute captured stdout/stderr files that feed caller-visible errors or JSON envelopes.
- **Architectural Invariant Enforcement (D-12, D-13, Plan 01-05):** Plan 01-05 case `RB01` scans logical joined lines for `"$AGY_BIN"` to guarantee every call site routes through `run_bounded`, admitting zero escape hatches or allowlists, and proves the scan's violation detection against synthetic mutations.
- **Byte-Identical Duplication Discipline (D-08, Case RB02):** Preserves standalone drop-in portability for `~/.local/bin/gemini` without runtime sourcing dependencies, mechanically locking the helper block via diff assertions between markers.

---

## 3. Concerns

- **[LOW] Pre-existing File Descriptor Collision Risk on `fd 9`:**
  - *Mechanism:* Both scripts run `exec 9>&2` at initialization to establish an unpolluted diagnostic channel. If an external caller (e.g. an orchestrator, wrapper script, or embedded subshell) already uses `fd 9` for its own pipes/redirections when invoking `gemini` or `agy-bridge`, reassignment will clobber the caller's descriptor inside that subshell process.
  - *Evidence:* In standard POSIX shells, file descriptors 3–9 are user-allocatable. However, because `gemini_shim.sh` and `agy_bridge.sh` execute in their own process boundary (unless sourced, which is prohibited), `exec 9>&2` only affects the child process table. The only edge case is if the caller passed open inherited fds expecting child inheritance. In this standalone CLI context, `fd 9` is standard and safe.
- **[LOW] Subshell PGID Race on Ultra-Fast Commands in Unit Fixtures:**
  - *Mechanism:* As noted in Research Pitfall 1, `_rb_pgid_of` can return empty if a test command terminates in sub-millisecond time before `/proc/$child/stat` or `ps` can inspect it.
  - *Mitigation in Plan:* Plan 01-06 specifies that tests asserting watchdog functionality (e.g. `RB04`, `RB05`, `RB10`) must use forking sleepers/stubs with sufficient duration rather than instantaneous `true`/`echo` commands.
- **[LOW] Dependency on `script` utility for PTY Testing (`RB06`):**
  - *Mechanism:* Plan 01-06 Task 2 introduces `RB06` testing terminal vs non-terminal behavior using `script -qc`. While `script` is common on Linux (`util-linux`) and macOS (`bsdutils`), flag syntax diverges (`script -q /dev/null ...` on macOS vs `script -qc ...` on Linux).
  - *Mitigation in Plan:* The plan includes a precondition check (`command -v script`) and fails with a clear message if unavailable, but care should be taken with cross-platform `script` flag compatibility.

---

## 4. Suggestions

1. **Portable PGID Extraction in `_rb_pgid_of`:** Ensure the macOS fallback (`ps -o pgid= -p "$p"`) strips whitespace cleanly using parameter expansion or `tr -dc '0-9'` to avoid comparison errors against `$BASHPID`.
2. **`script` Invocation Normalization for PTY Fixture:** When implementing `_run_sanitized` PTY mode in `tests/run-tests.sh`, handle GNU vs BSD `script` CLI differences gracefully (e.g. `script -q -c "cmd" /dev/null` on Linux vs `script -q /dev/null cmd` on BSD/macOS), or detect OS flavor before invoking `script`.
3. **Explicit Close of FD 9 on Subprocess Invocations (Minor Hygiene):** Where `AGY_BIN` is invoked, `fd 9` is automatically inherited unless `FD_CLOEXEC` is set. While `agy` ignores unknown file descriptors, explicitly redirecting `9>&-` when spawning `$AGY_BIN` is clean defense-in-depth.

---

## 5. Risk Assessment: LOW

The implementation plan is exceptionally well-structured, mathematically and mechanically rigorous, and strictly scoped. It solves the exact root cause of the missing-`timeout` defect without compromising the core project invariant ("Delegation must never break the caller"). The transition across Waves 1–4 is logically sequenced, heavily gated by TDD and mutation tests, and introduces zero regressions or unbounded paths.

---

## Consensus Summary

**Single-reviewer run.** `review.default_reviewers` is `["antigravity"]` and no reviewer flags were
passed, so one lane ran. There is no cross-model agreement to report — every finding below is one
system's opinion, and the "2+ reviewers" thresholds this section normally applies are not
satisfiable. Weight accordingly: this is a second opinion, not a consensus.

Detected but not invoked: `gemini` (this project's own shim — it routes to agy, so it would have
been the same model reviewing through the artifact under review), `claude` (skipped for
independence: `CLAUDE_CODE_ENTRYPOINT=cli`, this session's own runtime), `opencode`. Not installed:
`codex`, `coderabbit`, `qwen`, `cursor-agent`, `kimi`. Add `--opencode` for a genuinely independent
second lane if cross-model agreement matters before execution.

### Agreed Strengths

Not applicable with one reviewer. Antigravity's own list, unweighted:

- Dissolving the divergence rather than documenting it (D-01, D-04) — six `if [[ -n "$TIMEOUT_BIN" ]]`
  branch pairs collapse into one helper, net LOC reduction alongside a uniform exit-124 contract.
- Process-group isolation and descendant reaping (D-06, D-14) — a naive watchdog kills only the
  direct PID; the scoped `set -m` plus `kill -- -$pgid` reaps grandchildren.
- The defensive pitfall set (D-06a/b/c, D-07) — self-kill guard against `$BASHPID`, the guarded
  `/proc`+`ps` lookup that keeps `errexit` from tripping, signal forwarding, and fd 9 separation.
- Invariant enforcement with zero escape hatches (D-12, D-13, case RB01), proven against synthetic
  mutations rather than asserted.
- Byte-identical duplication pinned by a diff test (D-08, RB02), preserving the standalone-drop-in
  property.

### Agreed Concerns

Not applicable with one reviewer. All three findings are LOW and none blocks execution:

| Severity | Finding | Disposition |
|---|---|---|
| LOW | `fd 9` collision if a caller already uses fd 9 | **Self-resolving.** The reviewer worked through its own concern and concluded the scripts execute in their own process boundary (sourcing is prohibited), so `exec 9>&2` cannot clobber a caller. Raised and withdrawn in the same bullet. |
| LOW | `_rb_pgid_of` can return empty against a sub-millisecond child | **Already mitigated.** RESEARCH Pitfall 1 identified it; plan `01-06` already requires forking sleepers rather than instantaneous `true`/`echo` in the fixtures. The reviewer confirms the mitigation is present. |
| LOW | `script -qc` flag syntax diverges between GNU and BSD/macOS | **Genuinely new.** The plan has a `command -v script` precondition but not a flavour check. Linux wants `script -q -c "cmd" /dev/null`; BSD/macOS wants `script -q /dev/null cmd`. Since D-14a's PTY half is the only consumer and macOS is already the platform this phase's fallback exists for, this is worth fixing in `01-06` rather than discovering on a Mac. |

Two of the three suggestions are worth folding in; one is not:

- **Fold in — normalize the `script` invocation** for GNU vs BSD in `01-06`'s `_run_sanitized` PTY
  mode. This is the same finding as the LOW above and the only one that changes plan content.
- **Fold in — strip whitespace from the `ps -o pgid=` fallback** (`tr -dc '0-9'` or parameter
  expansion) before comparing against `$BASHPID`. `ps` pads its output; an unstripped compare
  silently never matches, which would disable the self-kill guard rather than fail loudly.
- **Decline — explicit `9>&-` when spawning `$AGY_BIN`.** Offered as defence-in-depth, and the
  reviewer notes agy ignores unknown descriptors. It adds a token to every one of the call sites
  D-04 exists to simplify, for no failure mode either the plan or the research identifies. Ponytail
  rung 1: the need is speculative. Recorded here as considered-and-declined rather than dropped.

### Divergent Views

None possible with one reviewer.

**Where this review did not push back, and it was asked to.** The prompt named four questions
directly, including the two the orchestrator was least sure of: whether the static scan's floor of
≥1 occurrence is genuinely different in kind from the count the roadmap forbids, and whether byte-
identical duplication is the right trade. Antigravity endorsed both without argument — it called the
scan "zero escape hatches" and the duplication "discipline". That is agreement, but it is not
independent confirmation: a reviewer that returns LOW risk on every question it was asked to stress
has not been shown to be capable of returning anything else on this material. The floor-vs-count
judgment in particular now rests on two agreeing opinions (this review and the plan-checker), not on
a mechanical check.

## Verdict

**Risk: LOW.** No BLOCKER or HIGH findings. Nothing here invalidates a plan, a wave ordering, or a
locked decision. Two mechanical fixes (`script` portability, `ps` whitespace) are worth applying to
`01-06` and the `_rb_pgid_of` helper spec before execution; neither requires replanning, and both
are small enough to apply as plan edits rather than a `--reviews` cycle.
