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

- [ ] R11 — every `agy` invocation bounded with `timeout -k`; agy ignores SIGTERM, so a plain `timeout` blocks forever
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
- **Removing the unbounded fallback when no `timeout` binary exists** — documented deliberately: an optional knob must not stop a `gemini` that shadows the system binary. Open question is only whether the bridge and shim should still diverge here.
- **Supporting non-OAuth agy auth** — agy owns its auth; the plugin observes the result.

## Context

Pure bash: 9 shell scripts, an ~89-test hand-rolled harness (`tests/run-tests.sh` plus a 28-test hook suite), no package manifest and no test framework. Published as a Claude Code plugin at `github.com/davdittrich/delegate-agy`.

**The originating incident, because it explains the structural scope.** `agy models` began emitting `id<TAB>display name`. Every `$`-anchored matcher in the bridge silently stopped matching, and all delegation failed. The fix was one line; the lesson was not. This plugin parses two formats it does not control — `agy models` output and Claude Code's `installed_plugins.json` — with `grep` and `sed`, and has no way to detect either drifting until a user reports it.

**A second incident, same week.** A user's launcher was pinned to a superseded plugin version, so a shipped fix sat installed but never executed and an already-fixed bug was re-reported. That produced the version-mismatch refusal in 1.6.0/1.6.2.

**Current state.** `master` merged 1.6.2 and then reverted its *content* at `a001d0e`; the commits are in master's history but the code is not. Completed work sits on `fix/agy-bridge-resilience`. Judge state by reading files, never by the commit graph.

**agy is presently unresponsive** — it ignores SIGTERM and hangs, which is why every bound needs `-k`, and why S5 (contract testing against a real agy) cannot currently be satisfied on this machine.

## Constraints

- **Compatibility**: The `gemini` shim shadows the system binary for all PATH callers — Octopus, Metaswarm, interactive shells. Any change that fails where it previously succeeded breaks unrelated tooling.
- **Security**: The launcher's exec target is an install-time literal. No glob, registry value, or command output may ever feed it, and no registry-supplied string may be printed as a command to run.
- **Dependencies**: bash 4+, coreutils (`timeout`/`gtimeout`), `python3` 3.6+. No package manager, so dependencies are checked at runtime, not resolved.
- **Tech stack**: Pure bash by design. The test harness is hand-rolled — no framework, `set -u` without `set -e`, one shared sandboxed `HOME`.
- **External**: `agy` and Claude Code both own formats this plugin reads and neither is versioned for consumers.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Resolve models from the live list, never a frozen map | A pinned name drifts the moment agy ships a version; that drift caused the 1.6.1 bug | ✓ Good — extended to the shim in 1.6.2 |
| Pin the launcher's exec target at install time | Prevents a planted cache directory from hijacking `gemini` for every PATH caller | ✓ Good — but forces a repin on every plugin update |
| Refuse to run a superseded pin (exit 127) | Silent stale execution let a shipped fix sit unused; a warning had already failed to be noticed | ⚠️ Revisit — hard-breaks `gemini` box-wide until repinned |
| Shim degrades silently, bridge fails loud | The shim must never break a PATH caller; the bridge is explicitly invoked and can be strict | ⚠️ Revisit — the two now diverge on the missing-`timeout` case with no stated rationale |
| Follow-ups discovered during work block the release | A release shipping known defects it surfaced itself misrepresents what it fixes | — Pending — first applied to 1.6.2 |

---
*Last updated: 2026-08-19 after GSD onboarding (codebase map + docs ingest)*
