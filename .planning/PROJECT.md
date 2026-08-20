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
- ✓ R11 — every `agy` invocation bounded through `run_bounded`, on every host, with or without a coreutils binary — Phase 1 (UAT 28/29 direct pass + 1 explicitly accepted gap, 15/15 threats closed)
  - Caveat: R11's stated premise ("agy ignores SIGTERM, so every bound escalates to SIGKILL") is the worst-case design assumption the mechanism is built and tested against (proven via a fake agy that ignores SIGTERM). Phase 1.5's real-agy probe *contradicted* the premise for agy 1.1.13 — it died on SIGTERM alone, rc=124, under a strict 8s bound; the `-k` escalation rationale was not reproduced. Tracked as `delegate-agy-i43`, deliberately left open at the Phase 1/1.5 boundary rather than rewriting R11 or `run_bounded` mid-phase. The escalation ladder itself is still correct defense-in-depth (it's what any *future* SIGTERM-ignoring agy version, or a wedged descendant process, needs) — it just isn't proven necessary for the specific agy version currently observed.
  - Accepted gap: UAT test 29 (does a stock macOS host print no shell job-control notice when it hits this same code path?) was explicitly accepted unverified rather than tested — no macOS host is available to this project. See `01-UAT.md` test 29 and `01-SECURITY.md`'s disposition:accept pattern (same rationale class as T-01-09).
- ✓ S1 — survive an `agy models` output-format change without silent breakage — Phase 2 (both writers gate a degraded/`gemini-`-less reply behind a `cut -f1` + `^gemini-` match before caching; a tab-suffixed/extra-column reply still normalizes and resolves; UAT 1/1 pass, 11/11 threats closed)
- ✓ S4 — the shared model cache must be safe with two independent writers — Phase 2 (`delegate-agy-8ph` closed: `scripts/agy_bridge.sh` and `scripts/gemini_shim.sh` both gate their cache write the same way and both fall back to a good stale cache on a degraded reply — bridge warns, shim stays silent by design since it shadows `gemini` box-wide; per-file atomic `mv` write accepted as sufficient for the two-writer property, live concurrency untested — see `AR-02-02`)

### Active

<!-- 1.6.2 and the structural work underneath it. -->

**Finish 1.6.2** — the release is written and reverted from `master` pending these:

- [ ] R5 — exit codes are a contract: 2, 3, 124, 127, 137 each mean exactly one thing and say so
- [ ] R6 — never report empty success; agy exiting 0 with no stdout is a failure
- [ ] R8 — registry read is comparison-only: exact key match, repin path built from install-time literals

**Structural — the coupling that produced the 1.6.x bug cluster:**

- [ ] S2 — survive a Claude Code registry schema change the same way
- [ ] S3 — a shim defect must not escape into unrelated PATH callers
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

**Current state.** `master` merged 1.6.2 at `1a0051c`, content-reverted it at `a001d0e` (8 files, holding the release for its own follow-ups), then re-merged `fix/agy-bridge-resilience` at `54d4772` once Phase 2 closed those follow-ups — a 5-file conflict (`README.md`, `scripts/agy_bridge.sh`, `scripts/install.sh`, `tests/fake-agy.sh`, `tests/run-tests.sh`) resolved in the branch's favor, full suite re-run clean (`PASS=145 FAIL=0`). Those 5 files plus `scripts/gemini_shim.sh` (never reverted — added after `a001d0e`) are current on `master`. Three of `a001d0e`'s 8 reverted files fell outside that conflict and are still stale on `master`: `.claude-plugin/plugin.json` (version string reads `1.6.1`) and `.claude/commands/agy-setup.md`/`agy-uninstall.md` (describe the pre-fix install/uninstall flow) — tracked as `delegate-agy-k0f`. Judge state by reading files, never by the commit graph.

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
| Follow-ups discovered during work block the release | A release shipping known defects it surfaced itself misrepresents what it fixes | ✓ Good — applied to 1.6.2; Phase 2's own code review (4 findings) was folded into the phase before it closed rather than deferred |
| Gate the cache write behind `cut -f1` + `^gemini-` match (not a rewrite of the write itself), mirrored identically on both `agy_bridge.sh` and `gemini_shim.sh` | A degraded `agy models` reply must never poison the cache the other tool reads for up to an hour; the two writers share one file so a one-sided fix leaves the other exposed | ✓ Good — `delegate-agy-8ph` closed, both writers verified byte-identical in gate shape |
| On a degraded-but-successful reply, fall back to a good stale cache instead of failing: the bridge warns (`stderr`), the shim stays silent | The bridge is a watched, explicit delegation call; the shim shadows `gemini` for every PATH caller, so a warning there is box-wide log noise | ✓ Good — same mechanism, deliberately different message policy, both pinned by tests |
| `printf ... \| grep -q` converted to the herestring form (`grep -q ... <<< "$var"`) at every site reading an untrusted, externally-sized list | `grep -q` exits on first match; under `set -o pipefail` an early match can SIGPIPE the upstream `printf`, and bash reports the pipeline's status as the SIGPIPE'd producer's 141, not `grep`'s 0 — reproduced empirically, bash 5.3.15 | ✓ Good — narrow, user-approved exception to the phase's closed-criteria boundary; applied to every matching site across both scripts, not just the two the plan started with |

---
*Last updated: 2026-08-20 after Phase 2 (model-list-handling-end-to-end) — UAT + security verification*
