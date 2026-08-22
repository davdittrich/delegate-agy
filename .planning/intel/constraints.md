# Constraints (SPEC intel)

All six classified documents are typed SPEC at equal declared precedence (manifest-assigned,
per-doc `precedence: 1`). Two are empirical results documents (evidence, not forward design);
four are design/plan documents. Where an Aug-18-2026 plan's factual claim about the current
codebase disagrees with the codebase itself, the codebase wins — see the `[INFO]` entries in
`../INGEST-CONFLICTS.md` for the specific disagreements found and how each was resolved.

---

## SubagentStart fires before a subagent's first prompt; additionalContext delivery confirmed
- source: docs/superpowers/specs/ps3.6-probe-results.md
- type: protocol
- content: Empirical (2026-07-08). `SubagentStart` fires for Task-spawned subagents (12:04:36,
  before `SubagentStop` at 12:04:42) — the installed plugin-dev docs list `SubagentStop` but
  not `SubagentStart`; docs are stale, the event is real. Emitted `additionalContext` reaches
  and is obeyed by the subagent (verified with a unique marker token). `SessionStart` does
  NOT fire per-subagent.

## Canonical `agent_type` literal form
- source: docs/superpowers/specs/ps3.6-probe-results.md
- type: protocol
- content: Bare form for built-in agents (e.g. `"general-purpose"`); `plugin:name` form for
  plugin/metaswarm agents (e.g. `agy-delegate:agy-delegate-code`, `metaswarm:researcher-agent`).
  This is the canonical form any allowlist matcher must use.

## Hook manifest wiring: auto-discovery + observability transport
- source: docs/superpowers/specs/ps3.6-probe-results.md
- type: protocol
- content: `hooks/hooks.json` is auto-discovered without a manifest `hooks` key (metaswarm
  convention); a top-level `hooks` key in `plugin.json` is also accepted (caveman uses it);
  `userConfig` is unused by sampled plugins — use an env-var toggle instead. Hook-path
  reference syntax: `${CLAUDE_PLUGIN_ROOT}/hooks/<script>.sh`. `AGY_HOOKS_DEBUG_FILE` is a
  valid, reliable observability channel (file-based; subagent stderr observability to the
  operator was not separately confirmed).

## SubagentStart hook v1 scope: advisory injection only
- source: docs/superpowers/specs/2026-07-08-agy-delegation-hooks-design.md
- type: nfr
- content: Approved design (design-review-gate 5/5, 2026-07-08). v1 ships only Component 1
  (SubagentStart `additionalContext` injection). `PreToolUse(Task)` nudge (ticket ps3.8) and
  `PreToolUse(Bash)` delegate gate (ticket ps3.9, security-sensitive, needs its own threat
  model) are explicitly deferred, not built. Opt-in, default OFF. Advisory only — judgment
  stays with the subagent, never forced. Fail-safe: never break a subagent spawn.

## Allowlist match rule (asymmetric)
- source: docs/superpowers/specs/2026-07-08-agy-delegation-hooks-design.md
- type: api-contract
- content: A namespaced allowlist entry (contains `:`) matches ONLY the exact full
  `agent_type` string — no suffix wildcard. A bare entry matches a bare runtime `agent_type`
  exactly, AND (documented footgun) the suffix-after-last-`:` of any namespaced runtime type —
  i.e. a bare entry is a cross-namespace wildcard for that agent name. CSV entries are
  whitespace-trimmed; matching is exact and case-sensitive. Default allowlist:
  `general-purpose,Explore,metaswarm:researcher-agent,metaswarm:coder-agent,metaswarm:code-review-agent`
  — this plugin's own `agy-delegate:*` agents are excluded (they already delegate by
  definition).

## Hook fail-safe / no-eval / no-echo invariant
- source: docs/superpowers/specs/2026-07-08-agy-delegation-hooks-design.md
- type: nfr
- content: Hooks never `eval`/`sh -c` any JSON-extracted value; output JSON is built only via
  `python3 json.dumps` (never bash string interpolation). Hook always exits 0 (disabled,
  not-allowlisted, malformed input, missing python3, or `agy-bridge` absent from PATH — all
  degrade to silent `exit 0`, optionally a debug line). Never echoes the subagent's prompt.
  `AGY_HOOKS_ENABLED` env var, default OFF.

## SubagentStart advisory text — SUPERSEDED, current text confirmed in shipped code
- source: docs/superpowers/specs/2026-07-08-agy-delegation-hooks-design.md (original text,
  superseded — see docs/superpowers/specs/2026-07-13-agy-delegate-leanctx-optimization-design.md
  §3.2 and ../INGEST-CONFLICTS.md [INFO])
- type: protocol
- content: The July 8 design's fixed advisory text (steering allowlisted subagents to
  `agy-bridge` broadly for "bulk, fan-out, or web-search work") is superseded by the July 13
  design's WebSearch-first revision. Do not treat the July 8 wording as current spec.

## Host tool-rights degradation (lean-ctx/tokensave-first, graceful-off)
- source: docs/superpowers/specs/2026-07-13-agy-delegate-leanctx-optimization-design.md
- type: nfr
- content: `agy-delegate` must work correctly in a Claude Code host where native
  `Read/Grep/Glob/Bash` are globally denied and redirected to lean-ctx/tokensave MCP tools,
  while remaining byte-identical for users WITHOUT lean-ctx/tokensave (public plugin must
  degrade gracefully). Root cause (verified): global `permissions.deny` on
  `Read/Grep/Glob/Bash` makes `agy-bridge` uninvokable via native `Bash` — primary breakage.
  Mechanism: tool grants are a minimal superset (native + ≤4 MCP tool schemas: `ctx_shell`,
  `ctx_read`, `ctx_search`, `tokensave_context`); agent body carries an imperative ordered
  rule ("use `ctx_shell`; only if unavailable, use `Bash`") — availability is the switch, no
  runtime branching.

## Bridge invocation mechanism: blocking wins, no async, no poll loop
- source: docs/superpowers/specs/2026-07-13-agy-delegate-leanctx-optimization-design.md;
  corroborated by docs/superpowers/specs/2026-07-13-agy-delegate-leanctx-optimization-spike-results.md
- type: api-contract
- content: WU0(A) spike verdict (measured, not assumed): a single blocking `ctx_shell` call
  completes real bridge runs when `timeout_ms` >= bridge TIMEOUT + startup budget. No async
  mode, no poll loop is built. `timeout_ms = bridge_TIMEOUT_s*1000 + 30000` (startup budget
  measured at 3s, set to 30s with 10x margin). Bridge TIMEOUT: 600s for code/analysis/review,
  300s for search. `ctx_shell`'s own default cap (120s) is BELOW the bridge's 600s TIMEOUT —
  root cause of user-reported "agy often times out" when `timeout_ms` isn't raised explicitly.

## `--sandbox` is an agy API-level FS floor, not prompt text
- source: docs/superpowers/specs/2026-07-13-agy-delegate-leanctx-optimization-spike-results.md;
  corroborated by docs/superpowers/specs/2026-07-13-agy-delegate-leanctx-optimization-design.md
- type: nfr
- content: WU0(B) spike verdict (measured). agy's `--sandbox` flag confines both reads and
  writes to `--add-dir`'d directories at the API level, independent of GEMINI.md prompt
  policy (confirmed: a policy that PERMITS `read_file` still could not escape `--sandbox`
  confinement). Two independent layers: (1) `--sandbox` API floor = scope to WORK_DIR: (2)
  GEMINI.md allowlist/FORBID = prompt-advisory within that scope. Bridge always passes
  `--sandbox --add-dir "$WORK_DIR"`; shim historically did not (see next entry — since
  fixed in shipped code, confirmed 2026-08-19).

## Bridge vs shim sandbox enforcement asymmetry
- source: docs/superpowers/specs/2026-07-13-agy-delegate-leanctx-optimization-spike-results.md;
  docs/superpowers/specs/2026-07-13-agy-delegate-leanctx-optimization-design.md §3.3/§5
- type: nfr
- content: Design commitment: if the spike confirms `--sandbox` is a real API floor (it did),
  add `--sandbox` to the shim's read-only branches (`shim-sandbox`/`shim-default`) for parity
  with the bridge; `shim-yolo` cannot (deliberately unrestricted under
  `--dangerously-skip-permissions`) — disclosed as best-effort prompt-level only. Confirmed
  implemented in shipped code (2026-08-19): `scripts/gemini_shim.sh:189` passes
  `--sandbox --add-dir "$PWD" --add-dir "$WORK_DIR"` on the sandboxed path, with an inline
  comment citing this WU0(B) verdict directly.

## Sandbox posture: fail-closed allowlist, not denylist
- source: docs/superpowers/specs/2026-07-13-agy-delegate-leanctx-optimization-design.md
- type: nfr
- content: All four agy-side sandbox policies (`search.md`, `shim-sandbox.md`,
  `shim-default.md`, `shim-yolo.md`) use PERMIT-list + identical catch-all clause text
  explicitly naming the `ctx_call` gateway and `ctx_edit` as forbidden — a denylist over an
  extensible MCP surface with a gateway is unprovable-complete. `shim-yolo` keeps its write
  PERMITs but explicitly forbids shell-equivalent MCP tools.

## cc-websearch / WebSearch precedence across every web-search surface
- source: docs/superpowers/specs/2026-07-13-agy-delegate-leanctx-optimization-design.md §3.2
- type: protocol
- content: Prefer the `WebSearch` tool (cc-websearch-served when the PreToolUse hook is
  installed, native DDG-drop-in otherwise) over invoking agy for general web search, across
  SKILL.md, the search agent, the `/agy-search` command, and the SubagentStart hook advisory.
  Reserve `agy-bridge --type search` for source-cited/grounded/current/Gemini-specific
  queries or when `WebSearch` is unavailable. All edits are no-ops for hosts without
  cc-websearch (WebSearch falls back to native). Confirmed shipped in
  `hooks/agy-subagent-policy.sh:87` (2026-08-19).

## tokensave→agy MCP registration: opt-in only, atomic/safe installer mutation
- source: docs/superpowers/specs/2026-07-13-agy-delegate-leanctx-optimization-design.md §3.5
- type: nfr
- content: Registering tokensave as an agy MCP server (grants agy code-graph read + local
  project mutate tools) requires explicit consent at setup (prompt, default No, or
  `AGY_SETUP_REGISTER_TOKENSAVE=1` for non-interactive callers) — never auto-registered.
  Mutation must be atomic and safe: abort on unparseable existing config (never overwrite a
  recoverable config); timestamped `.bak` before any write, verified; write to a same-dir
  0600 temp, `jq .` validate; remove temp + exit non-zero on validation failure; merge into
  `mcpServers` without clobbering `lean-ctx`; atomic `mv`; idempotent.

## No agy invocation may outlive its bound; `-k` escalation is mandatory
- source: docs/superpowers/plans/2026-08-18-agy-bridge-resilience.md;
  docs/superpowers/plans/2026-08-18-blocking-followups.md (independently reverified same day)
- type: nfr
- content: agy ignores SIGTERM (both plans independently verified this: bridge-resilience
  observed `timeout 25 agy models` still running after 3+ minutes; blocking-followups
  reverified `timeout -k 5 25 agy models` returns 124 while agy stays unresponsive). A plain
  `timeout` (no `-k`) signals and then blocks forever — every wrapped call needs `-k`.
  blocking-followups' inventory (four call sites total: `agy_bridge.sh:143`,
  `agy_bridge.sh:342`, `gemini_shim.sh:94`, `gemini_shim.sh:209`) supersedes
  bridge-resilience's original "both call sites" claim — bridge-resilience's own text
  contains a same-day in-document correction to four. **That four-count is itself now
  stale: there are five, the fifth added by the shim's dynamic model resolution
  (`gemini_shim.sh:89`). Three successive inventories, three wrong numbers — treat any
  stated count here as history, and the invariant in REQUIREMENTS.md R11 as the
  requirement.** **Current code state (verified
  2026-08-19, master branch): NOT yet satisfied.** `scripts/gemini_shim.sh:94` and `:209`
  have no `timeout` wrapper at all (fully unbounded); `scripts/agy_bridge.sh:305` uses plain
  `timeout` with no `-k`; only the model-fetch `-k`-bounding and the launcher/installer work
  are absent from master too. The completed fix work exists only on the unmerged
  `fix/agy-bridge-resilience` branch — master reverted it at `a001d0e` pending
  the blocking-followups tickets. See `../INGEST-CONFLICTS.md` [INFO].

  **On counting this branch:** "commits ahead" is misleading here and easy to get wrong.
  The branch holds 15 commits since `3b443a8`, but only **5 are exclusive to it** —
  `1a0051c` (the 1.6.2 merge) *is* in master's history, because master merged the work and
  then reverted its **content** with `a001d0e` rather than rewriting history. So master
  contains the commits while lacking the code: `git log` shows the fixes, `git show HEAD:file`
  does not. Verify state by reading the file, never by the commit graph — confirmed live:
  `scripts/gemini_shim.sh` has zero `SHIM_TIMEOUT` references on master and nine on the branch.

## `gemini` shim shadows the real `gemini` for every PATH caller — architectural fact
- source: docs/superpowers/plans/2026-08-18-blocking-followups.md
- type: nfr
- content: The single most important architectural fact about this project (per ingest
  brief). The installed shim shadows the real `gemini` binary for every caller on PATH —
  interactive shells, Claude Octopus, Metaswarm — not just this plugin's own call sites. Any
  defect in the shim (unbounded call, hard rejection, changed exit semantics) escapes this
  plugin's scope entirely and breaks unrelated tools. Design consequence: prefer lenient
  pass-through with a warning over hard rejection; never loosen the anchored model matchers
  (`^gemini-[0-9.]+-<class>$`) — normalize input, never the pattern. `TIMEOUT_BIN` may
  legitimately be empty (no `timeout`/`gtimeout` installed) and that degradation path must be
  preserved, not hard-failed.

## Model resolution must be dynamic (live list), not a frozen display-name map
- source: docs/superpowers/plans/2026-08-18-blocking-followups.md (Task 2)
- type: api-contract
- content: `config/model-map.json` mapped aliases to frozen display names; agy's live
  `agy models` output uses IDs as the canonical identifier and the map goes stale (observed:
  newest mapped flash was 3.6, agy now serves `gemini-3.7-flash-*` — same drift class as the
  bug that started this work, `delegate-agy-ovu`). Fix direction: alias→class (`pro-high`,
  `pro-low`, `flash-high`, `flash-medium`, `flash-low`), resolved against the live list the
  same way `agy_bridge.sh` already does — newest ID matching an anchored class pattern,
  60-minute cache, tab-normalized (`cut -f1`), stale-cache fallback. Unrecognized names pass
  through unchanged (leniency preserved — the shim shadows `gemini`, hard rejection breaks
  callers).

## No glob/registry-value/CLI-output may ever feed an exec target
- source: docs/superpowers/plans/2026-08-18-agy-bridge-resilience.md
- type: nfr
- content: Security invariant stated at `scripts/install.sh:66`. Generated launchers must
  keep the install-time literal (`_AGY_TARGET`) as the sole exec target; any registry/CLI
  read used for version-comparison or repin-hint purposes is comparison-only, never
  substituted into the exec path. A pinned launcher that detects a version mismatch against
  Claude Code's install registry must refuse to exec (fail loud) rather than silently run a
  superseded pin, and must construct any printed repin path from a trusted install-time root
  plus a version string validated against `^[0-9]+(\.[0-9]+)*$` — never echo a
  registry-supplied path verbatim (closes an attacker-controlled-path hazard an earlier
  design draft had).

## Wrapper scripts run under `set -euo pipefail`
- source: docs/superpowers/plans/2026-08-18-agy-bridge-resilience.md;
  docs/superpowers/plans/2026-08-18-blocking-followups.md
- type: nfr
- content: Any `grep`/`sed` pipeline in a generated wrapper whose no-match exit status could
  abort the wrapper under `errexit` must be suffixed `|| true`. Applies equally to the shim's
  unguarded `$HOME` reference under the same shell mode (an unset `HOME` under
  `set -euo pipefail` aborts before the script does anything) and to a poisoned shared-cache
  write (`$HOME/.cache/agy-bridge-models`, written by both `agy_bridge.sh` and
  `gemini_shim.sh`): a gemini-less agy reply (unauthenticated / format-changed) must never be
  cached, since one poisoned fetch degrades both tools for the full 60-minute TTL, and the
  two writers' handling of this must stay identical — divergence in shared state is itself
  the hazard.

## bd/beads issue tracker is authoritative for pending work, not any plan snapshot
- source: docs/superpowers/plans/2026-08-18-blocking-followups.md (illustrates the failure
  mode: its own embedded ticket list is stale)
- type: nfr
- content: A plan document's embedded ticket-status list is a point-in-time snapshot and
  degrades the moment work continues after it was written. Ground truth is `bd list`. Verified
  2026-08-19: this document's Global Constraints section lists `delegate-agy-pgx`, `-62x`,
  `-b8x` among remaining/tracked tickets in a way that reads as still-open — all three are
  CLOSED. The actual 7 open tickets are `delegate-agy-30m`, `-cy5`, `-8ph`, `-4vy`, `-4xn`,
  `-6q1`, `-v5a` (one of which, `-4xn`, is not mentioned in any document in this ingest set at
  all). See `../INGEST-CONFLICTS.md` [INFO].
