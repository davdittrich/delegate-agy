# agy-delegate

## What This Is

A Claude Code plugin that routes tasks to `agy` (Google's Antigravity CLI), giving Claude sessions access to Gemini and grounded web search with source citations. It ships two entry points: `agy-bridge` for explicit delegation, and a drop-in `gemini` shim that lets frameworks calling the retired Gemini CLI keep working unchanged.

## Core Value

**Delegation must never break the caller.** The shim installs as `~/.local/bin/gemini` and shadows the real `gemini` for every process on PATH — interactive shells, Claude Octopus, Metaswarm. A hang, a crash, or a silent empty-success in this plugin is not scoped to this plugin. Everything else is negotiable; this is not.

## Requirements

### Validated

<!-- Shipped in 1.6.1 or earlier and confirmed working. -->

- ✓ Type routing with five types, each carrying its own tool restrictions — 1.5.x
- ✓ Prompt embedded in a 0600 per-run `GEMINI.md`, never in `ps`/`/proc/cmdline` — 1.5.x
- ✓ Drop-in `gemini` shim: Octopus and Metaswarm work with no config change — 1.5.x
- ✓ Pinned-path launchers; exec target never a glob, registry value, or `claude plugin list` output — 1.6.0
- ✓ Installer refuses root, writes only under `~/.local/bin`, `~` (rc backups), `~/.config/agy-delegate`, `~/.gemini` — 1.6.0
- ✓ SubagentStart hook: opt-in, default off, advisory-only, never changes routing — 1.6.0
- ✓ Model resolution from the live `agy models` list rather than a pinned name — 1.5.1, corrected 1.6.1

### Active

<!-- 1.6.2 and the structural work underneath it. -->

**Finish 1.6.2** — the release is written and reverted from `master` pending these:

- [ ] R11 — every `agy` invocation bounded through `run_bounded`, with or without a coreutils binary; agy ignores SIGTERM, so every bound escalates to SIGKILL
- [ ] R5 — exit codes are a contract: 2, 3, 124, 127, 137 each mean exactly one thing and say so
- [ ] R6 — never report empty success; agy exiting 0 with no stdout is a failure
- [ ] R8 — registry read is comparison-only: exact key match, repin path built from install-time literals

**Structural — the coupling that produced the 1.6.x bug cluster:**

- [ ] S1 — survive an `agy models` output-format change without silent breakage
- [ ] S2 — survive a Claude Code registry schema change the same way
- [ ] S3 — a shim defect must not escape into unrelated PATH callers
- [ ] S4 — the shared model cache must be safe with two independent writers
- [ ] S5 — the plugin must be verifiable against a real `agy`, not only a fake

### Out of Scope

- **Replacing `grep`/`sed` parsing with a real JSON parser everywhere** — `python3` is already a dependency, but the exec-target invariant means the installer's registry read must stay minimal and auditable. Bounded, evidence-backed parsing is the goal, not a parser rewrite.
- **Making the shim a full Gemini CLI** — it maps the flags Octopus and Metaswarm actually use. Chasing full parity invites drift against a CLI Google is retiring.
- **Matching coreutils' process-group kill where bash cannot** — as of Phase 1 every agy call is bounded on every host, so this is a question of *which* kill, not whether one happens. The bash watchdog reaps the child's process group through job control; where job control cannot give the child a group of its own it kills the direct process only, so something agy forked can survive. Installing coreutils closes that gap. Chasing it further in bash does not.
- **Supporting non-OAuth agy auth** — agy owns its auth; the plugin observes the result.

## Context

Pure bash: 9 shell scripts, an ~89-test hand-rolled harness (`tests/run-tests.sh` plus a 28-test hook suite), no package manifest and no test framework. Published as a Claude Code plugin at `github.com/davdittrich/delegate-agy`.

**The originating incident, because it explains the structural scope.** `agy models` began emitting `id<TAB>display name`. Every `$`-anchored matcher in the bridge silently stopped matching, and all delegation failed. The fix was one line; the lesson was not. This plugin parses two formats it does not control — `agy models` output and Claude Code's `installed_plugins.json` — with `grep` and `sed`, and has no way to detect either drifting until a user reports it.

**A second incident, same week.** A user's launcher was pinned to a superseded plugin version, so a shipped fix sat installed but never executed and an already-fixed bug was re-reported. That produced the version-mismatch refusal in 1.6.0/1.6.2.

**Current state.** `master` merged 1.6.2 and then reverted its *content* at `a001d0e`; the commits are in master's history but the code is not. Completed work sits on `fix/agy-bridge-resilience`. Judge state by reading files, never by the commit graph.

**agy responds as of 2026-08-19** (version 1.1.13), reversing the note that stood here. A bounded read-only probe that day got `--version` and `agy models` back in seconds and a real `--type review` delegation back in 4721 bytes; `agy models` emits 14 lines of `id<TAB>display name`, and `--model` accepts **both** ids and display names — settling `delegate-agy-62x`, which was closed without ever being verified. S5 is therefore no longer externally blocked, and its phase moved from 7 to 1.5 so the phases reasoning about agy's output build on fixtures instead of hypotheses.

What the probe did **not** establish: whether agy ignores SIGTERM. Every call returned on its own, so no bound ever fired. That observation (`timeout 25 agy models` still running after 3+ minutes, recorded in `agy_bridge.sh`) stands unretested, and every bound keeps its `-k` escalation on its original evidence.

## Constraints

- **Compatibility**: The `gemini` shim shadows the system binary for all PATH callers — Octopus, Metaswarm, interactive shells. Any change that fails where it previously succeeded breaks unrelated tooling.
- **Security**: The launcher's exec target is an install-time literal. No glob, registry value, or command output may ever feed it, and no registry-supplied string may be printed as a command to run.
- **Dependencies**: bash 4+ and `python3` 3.6+ are required; coreutils (`timeout`/`gtimeout`) is optional as of Phase 1 — it buys a process-group kill, not the bound itself. No package manager, so dependencies are checked at runtime, not resolved.
- **Tech stack**: Pure bash by design. The test harness is hand-rolled — no framework, `set -u` without `set -e`, one shared sandboxed `HOME`.
- **External**: `agy` and Claude Code both own formats this plugin reads and neither is versioned for consumers.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Resolve models from the live list, never a frozen map | A pinned name drifts the moment agy ships a version; that drift caused the 1.6.1 bug | ✓ Good — extended to the shim in 1.6.2 |
| Pin the launcher's exec target at install time | Prevents a planted cache directory from hijacking `gemini` for every PATH caller | ✓ Good — but forces a repin on every plugin update |
| Refuse to run a superseded pin (exit 127) | Silent stale execution let a shipped fix sit unused; a warning had already failed to be noticed | ⚠️ Revisit — hard-breaks `gemini` box-wide until repinned |
| Shim degrades silently, bridge fails loud | The shim must never break a PATH caller; the bridge is explicitly invoked and can be strict | ✗ Superseded by the row below — Phase 1 dissolved the missing-`timeout` divergence instead of documenting it |
| Every agy call is bounded on every host, by coreutils `timeout` where it exists and a native bash watchdog where it does not | `delegate-agy-cy5` asked whether the bridge should hard-fail, degrade with a warning, or refuse only the delegation call. Each of the three buys either a call with no bound or a caller broken at startup, and the core value forbids both — a `gemini` that refuses to run is the same failure as one that hangs, moved one step earlier. Bash bounds a call natively with no external binary, so the premise that a missing binary forces the trade is what was rejected; the recorded decision is *always bounded*, none of the three | ✓ Good — both entry points now warn once per run and proceed bounded; the bridge's startup fatal is deleted (Phase 1) |
| Follow-ups discovered during work block the release | A release shipping known defects it surfaced itself misrepresents what it fixes | — Pending — first applied to 1.6.2 |

---
*Last updated: 2026-08-19 after GSD onboarding (codebase map + docs ingest)*
