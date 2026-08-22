# Codebase Structure

**Analysis Date:** 2026-08-18

**Source mapped:** `.worktrees/agy-1.6.2` (branch `fix/agy-bridge-resilience`). The main checkout at the repo root is on `master`, reverted to a pre-release state — do not treat its file layout as current.

## Directory Layout

```
agy-delegate/                          # plugin root (name from .claude-plugin/plugin.json:2)
├── .claude-plugin/
│   ├── plugin.json                    # plugin manifest: name, version, skills/commands lists
│   └── marketplace.json               # marketplace listing metadata
├── .claude/
│   └── commands/                      # slash commands, thin wrappers over the bridge
│       ├── agy.md
│       ├── agy-search.md
│       ├── agy-review.md
│       ├── agy-setup.md
│       └── agy-uninstall.md
├── agents/                            # subagent definitions that call agy-bridge
│   ├── agy-delegate-code.md
│   └── agy-delegate-search.md
├── skills/
│   ├── agy-delegate/SKILL.md          # delegation usage guidance
│   └── gemini-3-prompting/SKILL.md    # Gemini 3 prompting technique guidance
├── scripts/                           # all executable logic — pure bash
│   ├── agy_bridge.sh                  # explicit `--type` delegation entry point
│   ├── gemini_shim.sh                 # drop-in `gemini` shadow entry point
│   ├── install.sh                     # generates pinned launchers in ~/.local/bin
│   └── uninstall.sh                   # removes the generated launchers
├── hooks/
│   ├── hooks.json                     # registers SubagentStart -> agy-subagent-policy.sh
│   ├── agy-subagent-policy.sh         # the hook itself (guard chain + fixed advisory)
│   └── agy-hooks-lib.sh               # sourced-only helper functions (include-guarded)
├── config/
│   ├── model-map.json                 # gemini-CLI alias -> agy model CLASS (not version)
│   ├── provider.md                    # provider-level notes
│   └── policies/                      # GEMINI.md tool-restriction text, one per mode
│       ├── code.md                    # agy_bridge.sh --type code
│       ├── implement.md               # agy_bridge.sh --type implement
│       ├── review-analysis.md         # agy_bridge.sh --type review|analysis
│       ├── search.md                  # agy_bridge.sh --type search
│       ├── shim-default.md            # gemini_shim.sh, no --yolo/--sandbox flag
│       ├── shim-sandbox.md            # gemini_shim.sh --sandbox
│       └── shim-yolo.md               # gemini_shim.sh --yolo / --approval-mode yolo
├── tests/
│   ├── run-tests.sh                   # main test runner
│   ├── fake-agy.sh                    # fake `agy` binary test double
│   └── hooks/run-hook-tests.sh        # hook-specific test runner
├── README.md
└── .gitignore
```

Everything under this tree is flat and shallow — no nested source directories, no build output directories, because there is nothing to build.

## Directory Purposes

**`scripts/`:**
- Purpose: all runtime logic. Every file here is directly executable bash, `set -euo pipefail`, no shared sourced library (deliberate — see `ARCHITECTURE.md` Architectural Constraints on why `gemini_shim.sh` duplicates rather than sources bridge logic).
- Contains: 4 scripts, ~430 lines (`agy_bridge.sh`), ~391 lines (`gemini_shim.sh`), ~380+ lines (`install.sh`), plus `uninstall.sh`.
- Key files: `scripts/agy_bridge.sh`, `scripts/gemini_shim.sh`, `scripts/install.sh`.

**`hooks/`:**
- Purpose: Claude Code lifecycle hook integration, independent of the delegation runtime (does not call `agy`).
- Contains: one event registration (`hooks/hooks.json`), one hook script, one sourced-only function library.
- Key files: `hooks/agy-subagent-policy.sh`, `hooks/agy-hooks-lib.sh` (must never be executed directly, has an include guard at `hooks/agy-hooks-lib.sh:11-14`).

**`config/`:**
- Purpose: all data that changes behavior without changing code — tool-restriction policy text and the model-alias map.
- Contains: `config/policies/*.md` (7 files, one per mode/type combination), `config/model-map.json` (alias → class, never a pinned version — see `config/model-map.json` header comment in `gemini_shim.sh:48-53`).
- Key files: `config/policies/code.md`, `config/model-map.json`.

**`skills/`, `agents/`, `.claude/commands/`:**
- Purpose: the Claude Code-facing surface that end users and other agents actually invoke; each is a thin markdown wrapper documenting how/when to call `agy-bridge` or the `gemini` shim.
- Contains: markdown instruction files only, no logic.

**`.claude-plugin/`:**
- Purpose: plugin manifest consumed by Claude Code's plugin loader.
- Contains: `plugin.json` (name/version/skills/commands manifest), `marketplace.json`.

**`tests/`:**
- Purpose: bash-based test suite exercising both entry points against a fake `agy` binary (never the real one — the real `agy` hangs and is explicitly excluded from automated runs per repo convention).
- Contains: `tests/fake-agy.sh` (test double), `tests/run-tests.sh`, `tests/hooks/run-hook-tests.sh`.

**`docs/`:**
- Purpose: internal design specs / probe notes, e.g. `docs/superpowers/plans/2026-08-18-agy-bridge-resilience.md`.
- Tracked: **no** — `.gitignore:8` excludes `docs/superpowers/` ("Internal design specs / probe notes (not for publication)").

## Key File Locations

**Entry Points:**
- `scripts/agy_bridge.sh`: explicit delegation, installed as `~/.local/bin/agy-bridge`.
- `scripts/gemini_shim.sh`: drop-in `gemini` replacement, installed as `~/.local/bin/gemini` (shadows any real `gemini` earlier/absent on PATH).

**Configuration:**
- `config/policies/*.md`: per-mode tool restriction text, copied verbatim into each invocation's `GEMINI.md`.
- `config/model-map.json`: static alias→class map, re-resolved against the live `agy models` output at call time.
- `.claude-plugin/plugin.json`: plugin identity/version/manifest.

**Core Logic:**
- `scripts/agy_bridge.sh:135-196`: live model-list fetch, cache, and auto-selection.
- `scripts/agy_bridge.sh:206-320`: per-invocation `GEMINI.md` assembly (policy + prompt + MCP hint).
- `scripts/install.sh:85-169`: `write_wrapper()` — the pinned-launcher generator, the security-sensitive core of the installer.

**Testing:**
- `tests/run-tests.sh`, `tests/hooks/run-hook-tests.sh`, `tests/fake-agy.sh`.

## Naming Conventions

**Files:**
- Executable scripts: `verb_noun.sh` or `noun-verb.sh` in `snake_case`/`kebab-case` mixed by directory (`scripts/` uses `agy_bridge.sh`, `gemini_shim.sh`; `hooks/` uses `agy-subagent-policy.sh`, `agy-hooks-lib.sh`).
- Policy files: `<type>.md` under `config/policies/`, with the shim's three modes prefixed `shim-` to distinguish from the bridge's `--type` policies (`shim-yolo.md` vs. `code.md`).
- Command/skill/agent markdown: `agy*.md` prefix ties every user-facing file back to the plugin name.

**Directories:**
- Flat, one level deep, named after Claude Code's own convention categories (`commands/`, `agents/`, `skills/`, `hooks/`) plus two plugin-specific ones (`scripts/`, `config/`).

## Where to Add New Code

**New `--type` for `agy_bridge.sh`:**
- Add the type to the `TYPE_SAFE` case validation (`scripts/agy_bridge.sh:130-133`).
- Add its default model-selection regex branch (`scripts/agy_bridge.sh:187-190`) and default timeout branch (`scripts/agy_bridge.sh:200-203`) if it needs non-default values.
- Add a new policy file under `config/policies/` and wire it into the `case "$TYPE"` policy-selection block (`scripts/agy_bridge.sh:218-223`).
- Update the `--types` help table (`scripts/agy_bridge.sh:81-88`) and `--help` text (`scripts/agy_bridge.sh:90-120`).

**New gemini-shim flag translation:**
- Add a case arm to the flag-parsing loop (`scripts/gemini_shim.sh:155-226`); unknown `--flag`/`--flag value` pairs are already silently skipped for forward-compatibility (`scripts/gemini_shim.sh:219-221`), so only flags needing real translation require new code.

**New model alias:**
- Add a `"alias": "class"` entry to `config/model-map.json`; classes must match agy's own `-<class>$` suffix convention (`pro-high`, `flash-medium`, etc.) since `map_model()` regex-matches `^gemini-[0-9.]+-${class}\$` against the live list (`scripts/gemini_shim.sh:127`).

**New hook:**
- Register the event in `hooks/hooks.json`; if it needs the same enable/allowlist/debug guard pattern, source `hooks/agy-hooks-lib.sh` (include-guarded, safe to double-source) rather than reimplementing guards.

**Tests:**
- Extend `tests/run-tests.sh` (bridge/shim behavior) or `tests/hooks/run-hook-tests.sh` (hook guard chain); drive both against `tests/fake-agy.sh`, never the real `agy` binary.

## Special Directories

**`docs/superpowers/`:**
- Purpose: internal design/plan notes (e.g., the resilience-fix plan this worktree implements).
- Generated: no (hand-authored planning docs).
- Committed: **no** — excluded via `.gitignore:8`.

**`.planning/`, `.beads/`, `.claude-octopus/`, `.metaswarm/`, `.agents/`, `.codex/`, `.headroom/`, `.tokensave/`, `.dolt/`:**
- Purpose: local tooling working directories (GSD planning artifacts, beads issue DB, agent caches, Dolt sync state).
- Generated: yes, by their respective tools.
- Committed: **no** — all excluded via `.gitignore:1-27`. `.beads/proxieddb/`, `*.db`, `.beads-credential-key`, `.claude/settings.json`, and `.claude/settings.local.json` are separately excluded too.

**`.worktrees/`:**
- Purpose: git worktree checkouts (this analysis's source, `agy-1.6.2`, lives here).
- Generated: yes, by `git worktree add`.
- Committed: no (not in `.gitignore` explicitly, but never tracked as file content — a worktree is a separate checkout, not a subtree).

**`AGENTS.md` / `CLAUDE.md` (repo-local):**
- Purpose: local agent-instruction overrides.
- Committed: **no** — both files exist on disk, are read by the agent harness as local instructions, and are gitignored by design via `.gitignore:12-13` ("Local agent-instruction files (not for publication)"); confirmed untracked via `git ls-files` (zero matches for both).

---

*Structure analysis: 2026-08-18*
</content>
