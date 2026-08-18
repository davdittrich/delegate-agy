## Conflict Detection Report

### BLOCKERS (0)

None. No documents in this ingest set are typed ADR (no LOCKED-vs-LOCKED possibility). No
UNKNOWN/low-confidence classifications (all six are SPEC, confidence: high). No cross-ref
cycles detected among the six classified documents (the only cross-doc edge in the
classified set is `2026-07-08-agy-delegation-hooks-design.md` → `ps3.6-probe-results.md`,
one-directional). MODE=new, so there is no existing locked CONTEXT.md to contradict.

### WARNINGS (0)

None. All six documents are typed SPEC at equal declared precedence (manifest-assigned
`precedence: 1` on every doc) — there are no PRDs in this set, so no competing-acceptance-
variant case arises. The one genuine content supersession found (see INFO below) resolved
cleanly via recency + corroborating shipped code, with no residual ambiguity requiring a
user pick.

### INFO (4)

[INFO] Auto-resolved: July 13 web-search advisory supersedes July 8 advisory
  Note: docs/superpowers/specs/2026-07-08-agy-delegation-hooks-design.md (WU-3) specifies a
  fixed SubagentStart advisory that steers allowlisted subagents to `agy-bridge` broadly for
  "bulk, fan-out, or web-search work." docs/superpowers/specs/2026-07-13-agy-delegate-leanctx-optimization-design.md
  (§3.2) explicitly revises that same advisory to prefer the `WebSearch` tool for general
  search and reserve `agy-bridge --type search` for grounded/second-opinion queries — same
  file (`hooks/agy-subagent-policy.sh`), same "fixed advisory" text, contradictory content.
  Resolved by recency (July 13 postdates and explicitly amends July 8) and confirmed by
  shipped code: `hooks/agy-subagent-policy.sh:87` (checked 2026-08-19) contains the July 13
  wording verbatim. The July 8 version is recorded in `intel/constraints.md` as superseded,
  not current.

[INFO] Auto-resolved: bd issue tracker overrides blocking-followups' embedded ticket list
  Note: docs/superpowers/plans/2026-08-18-blocking-followups.md's Global Constraints section
  lists `delegate-agy-pgx`, `-62x`, `-b8x` in a way that reads as still-tracked/open work.
  `bd list --status open` (run 2026-08-19 from the repo root) shows all three CLOSED. The
  actual 7 open tickets are `delegate-agy-30m`, `-cy5`, `-8ph`, `-4vy`, `-4xn`, `-6q1`,
  `-v5a` — one of which (`-4xn`) is not referenced by any document in this ingest set at
  all. Per this ingest's explicit precedence rule, the tracker is authoritative for pending
  work; the plan document's list is a stale point-in-time snapshot and is not propagated.

[INFO] Auto-resolved: current code overrides bridge-resilience plan's call-site inventory and status
  Note: docs/superpowers/plans/2026-08-18-agy-bridge-resilience.md's Global Constraints
  section contains its own same-day in-document correction from "both call sites" to four
  (`agy_bridge.sh:143`, `agy_bridge.sh:342`, `gemini_shim.sh:94`, `gemini_shim.sh:209`).
  Verified directly against current code (2026-08-19, `master` branch): all four sites
  exist as named, and `gemini_shim.sh:94` / `gemini_shim.sh:209` currently have NO timeout
  wrapper at all (fully unbounded), while `agy_bridge.sh:305` uses a plain `timeout` with no
  `-k`. The plan's own Task 5/6 text implies these are fixed by end-of-plan, and
  blocking-followups' baseline assumes a 1.6.2 already carrying the resilience fixes — but
  `git log` shows master reverted the entire feature set at `a001d0e` ("hold 1.6.2 until the
  follow-up tickets are done"), after merging it at `e0e5197`/`1a0051c`. The completed work
  for both plans exists only on the unmerged `fix/agy-bridge-resilience` branch (134
  commits). Downstream synthesis treats current `master` as the ground truth for "what
  ships today," per this ingest's explicit code-is-authoritative rule — not either plan's
  narrative of completion.

[INFO] Auto-resolved: current code overrides stale test-count claims
  Note: docs/superpowers/plans/2026-08-18-agy-bridge-resilience.md projects a final
  `PASS=77 FAIL=0`; docs/superpowers/plans/2026-08-18-blocking-followups.md states that same
  `PASS=77 FAIL=0` as its starting baseline. Verified directly (2026-08-19): current `master`
  gives `bash tests/run-tests.sh` → `PASS=70 FAIL=0` and
  `bash tests/hooks/run-hook-tests.sh` → `pass: 28 fail: 0`. The discrepancy is explained by
  the same revert noted above (master's test count reflects the reverted state, not either
  plan's end state). Current master counts are recorded in `intel/constraints.md` and should
  be treated as the actual baseline for any downstream roadmap.
