# Ingest Synthesis Summary

Ingest mode: `new`. Source: 6 classification JSONs in `.planning/intel/classifications/`,
cross-checked against their source documents and against current repo state
(`git log`, `bd list --status open`, `tests/run-tests.sh`, `tests/hooks/run-hook-tests.sh`) as
of 2026-08-19.

## Doc counts by type

- ADR: 0
- SPEC: 6 (all high confidence, manifest-typed, `precedence: 1` uniformly)
  - `docs/superpowers/specs/2026-07-08-agy-delegation-hooks-design.md` — design
  - `docs/superpowers/specs/ps3.6-probe-results.md` — empirical results
  - `docs/superpowers/specs/2026-07-13-agy-delegate-leanctx-optimization-design.md` — design
  - `docs/superpowers/specs/2026-07-13-agy-delegate-leanctx-optimization-spike-results.md` — empirical results
  - `docs/superpowers/plans/2026-08-18-agy-bridge-resilience.md` — implementation plan (executed on an unmerged branch; reverted from master pending follow-ups; partially stale claims)
  - `docs/superpowers/plans/2026-08-18-blocking-followups.md` — implementation plan (partially executed; embedded ticket list stale)
- PRD: 0
- DOC: 0

## Decisions locked

0. No ADRs in this ingest set. See `intel/decisions.md`.

## Requirements extracted

0. No PRDs in this ingest set. See `intel/requirements.md`. Pending work lives in bd, not in
   documents — 7 open tickets as of 2026-08-19: `delegate-agy-30m`, `-cy5`, `-8ph`, `-4vy`,
   `-4xn`, `-6q1`, `-v5a` (run `bd list --status open` for current state; do not trust any
   ticket list embedded in a plan document — see conflict report).

## Constraints

20 entries in `intel/constraints.md`, spanning: `protocol` (hook wiring, agent_type form,
allowlist matching, web-search precedence), `nfr` (fail-safe/security invariants, sandbox
posture, shim PATH-shadowing, timeout/SIGTERM handling, installer safety), and `api-contract`
(bridge invocation timing, model resolution). Two architectural facts recur across the set and
are load-bearing for any downstream roadmap:

1. The installed `gemini` shim shadows the real `gemini` for every PATH caller (interactive
   shells, Claude Octopus, Metaswarm) — a shim defect escapes this plugin's scope entirely.
2. `agy` ignores SIGTERM and hangs; every call site must be `timeout -k`, not plain `timeout`.
   **As of 2026-08-19, current `master` does NOT satisfy this** at `gemini_shim.sh:94`/`:209`
   (fully unbounded) or with `-k` at `agy_bridge.sh:305` (plain `timeout`) — the completed fix
   lives only on the unmerged `fix/agy-bridge-resilience` branch.

## Context topics

0. No DOC-type sources in this ingest set. See `intel/context.md`.

## Conflicts

- Blockers: 0
- Competing variants (warnings): 0
- Auto-resolved (info): 4 — one doc-vs-doc content supersession (recency + shipped code), three
  doc-vs-current-reality corrections (bd tracker and current code override stale plan claims)

Full detail: `../INGEST-CONFLICTS.md`

## Per-type intel files

- `intel/decisions.md` (empty — no ADRs)
- `intel/requirements.md` (empty — no PRDs)
- `intel/constraints.md` (20 entries — primary content of this ingest)
- `intel/context.md` (empty — no DOC sources)

## Status

READY — no blockers, no unresolved variants. `gsd-roadmapper` should read this file plus
`intel/constraints.md` and `../INGEST-CONFLICTS.md`, and should independently confirm current
`bd list --status open` state before drafting a roadmap, since none of the ingested documents
are authoritative for pending work.
