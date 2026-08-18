# External Integrations

**Analysis Date:** 2026-08-18

## The `agy` CLI (primary integration — read this first)

Everything in this repo exists to wrap one external binary: Google's Antigravity CLI (`agy`), expected on PATH at `~/.local/bin/agy` (`scripts/agy_bridge.sh:11-14`).

**Known-hung/unresponsive behavior — the single most important fact about this integration:**
`agy` **ignores SIGTERM**. This was directly observed by the maintainer: `timeout 25 agy models` was "still running after 3+ min" (comment at `scripts/agy_bridge.sh:139-140`, repeated at `scripts/gemini_shim.sh:36-40` and `:83-87`). Because of this, **every single call site to `agy` in this repo uses `timeout -k N T` (or `gtimeout -k N T`), never a plain `timeout T`**, so the SIGTERM-then-wait sequence escalates to SIGKILL instead of hanging forever waiting on a child that will never die:
- `scripts/agy_bridge.sh:143` — `agy models` fetch, `-k 3` escalation, `$AGY_MODELS_TIMEOUT` (default 20s) bound.
- `scripts/agy_bridge.sh:342` — the main delegation call, `-k 5` escalation, `$TIMEOUT` bound (default 300s search / 600s other).
- `scripts/gemini_shim.sh:89` — `agy models` fetch inside `load_models()`, `-k 3`, `$AGY_MODELS_TIMEOUT` bound.
- `scripts/gemini_shim.sh:190` — `agy --version`, `-k 5`, hardcoded 10s (not configurable — comment at `scripts/gemini_shim.sh:36-38`).
- `scripts/gemini_shim.sh:317` — the main delegation call, `-k 5`, `$SHIM_TIMEOUT` bound (default 600s, env `GEMINI_SHIM_TIMEOUT`).

Both scripts distinguish an exit 137 that lands **before** their own timeout bound elapsed (an external SIGKILL — OOM killer, `kill -9`, cgroup preemption) from one that lands **at/after** the bound (their own `-k` escalation firing): `scripts/agy_bridge.sh:352-365`, `scripts/gemini_shim.sh:332-339`. This distinction exists because "raise --timeout" is useless advice against an external OOM kill.

**Silent-failure mode:** `agy` can exit 0 with empty stdout on quota exhaustion (`RESOURCE_EXHAUSTED`/429) or other silent backend/lock errors. Both scripts treat empty stdout after exit 0 as a hard failure (`scripts/agy_bridge.sh:386-409`, `scripts/gemini_shim.sh:355-371`), classifying the reason into `quota`/`auth`/`empty_output` by pattern-matching the full captured stderr — never truncating the raw message, only using the pattern match to *label* it.

**Model discovery:** `agy models` is the only source of valid model ids — there is no hardcoded model list. Output format is `id<TAB>display name`; both scripts normalize with `cut -f1` (`scripts/agy_bridge.sh:174`, `scripts/gemini_shim.sh:108`). If the returned list contains no `gemini-` prefixed ids at all, that's treated as agy being unauthenticated or having changed output format, not a bad user-supplied `--type`/`--model` (`scripts/agy_bridge.sh:176-183`).

**Invocation shape:** `agy --print "<static pointer>" --sandbox --model <id> --add-dir <workdir> ...` — the actual task prompt is never passed as a CLI argument. It's written into a `GEMINI.md` file (mode 600) inside a per-call `mktemp -d` workdir, which `agy` auto-loads as context; only a fixed pointer string ("Complete the TASK described in your GEMINI.md context...") is passed via `--print` (`scripts/agy_bridge.sh:270-276`, `:321-335`; `scripts/gemini_shim.sh:277-286`). This keeps the prompt off `ps`/`/proc/*/cmdline` and avoids `ARG_MAX`.

## Claude Code Plugin Cache & Install Registry

`scripts/install.sh` reads (never writes) `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json` — but **only for comparison**, inside the generated wrapper scripts, to detect a stale plugin-version pin (`scripts/install.sh:135-154`). The wrapper's actual exec target is a pinned absolute path baked into the wrapper at install time (`_AGY_TARGET` in the heredoc, `scripts/install.sh:115`), never derived from the registry or a cache glob — the security-model comment at `scripts/install.sh:9-20` is explicit that a registry-supplied value must never reach `exec` or be printed as a path. The registry read is bounded to the installing plugin's own exact `"<plugin>@<marketplace>"` key via a `sed` address range anchored on that key (`scripts/install.sh:96-106`, `:136-138`).

If the pinned target file no longer exists, or the registry reports a different active version, the wrapper fails loud with exit 127 and tells the user to re-run install (`scripts/install.sh:118-122`, `:139-153`).

## `~/.local/bin` Wrapper Generation — `gemini` shadowing (single most consequential fact)

`scripts/install.sh` writes two pinned launcher wrappers into `~/.local/bin`: `agy-bridge` (execs `scripts/agy_bridge.sh`) and **`gemini`** (execs `scripts/gemini_shim.sh`) — `scripts/install.sh:184-185`.

**The `gemini` wrapper shadows the real `gemini` command for every caller on PATH** that has `~/.local/bin` ahead of wherever the real `gemini` lives. The installer explicitly scans the *entire* `$PATH` (not just checking for an existing file at the destination) before writing, looking for a real `gemini` binary elsewhere on PATH (`scripts/install.sh:166-181`), and prints an unmissable notice regardless of outcome:

> "NOTICE: '$BIN_DIR/gemini' now shadows the 'gemini' command for ALL callers whose PATH includes '$BIN_DIR' before any real gemini install. Blast radius: every tool that runs 'gemini' (Claude Octopus, Metaswarm, your interactive shell) will invoke agy instead." (`scripts/install.sh:187-194`)

This means any tool that shells out to `gemini` — Claude Octopus, Metaswarm, or a bare interactive shell alias — silently gets routed through `agy` instead, translated by `scripts/gemini_shim.sh`'s flag-translation layer (`-m`/`--model`, `-o`/`--output-format`, `--approval-mode yolo`→`--dangerously-skip-permissions`, `--sandbox`, `--include-directories`→`--add-dir`; see `scripts/gemini_shim.sh:145-309`). The installer offers an opt-in, consent-gated rc-alias patch (`AGY_SETUP_PATCH_ALIASES=1`) that rewrites a pre-existing recursive `alias gemini='... gemini'` in the user's shell rc to point at the *real* gemini binary it discovered, so that alias doesn't infinitely recurse into the shim (`scripts/install.sh:205-227`). Uninstall is `scripts/uninstall.sh`, described as removing only the agy-delegate wrappers and restoring any backed-up original (`scripts/install.sh:193-194`).

Wrapper non-clobber behavior: if a destination file already exists and is not one of this project's own wrappers (detected via a marker string `# agy-delegate-wrapper`), it's backed up to `<dest>.bak-agy-<timestamp>` before being overwritten (`scripts/install.sh:64-86`).

## MCP Servers Referenced by the Bridge

Two MCP servers are referenced, but neither is installed/managed by this repo — it only *detects* and *advertises* their presence:

- **lean-ctx** — detection only. `agy_bridge.sh` checks whether `lean-ctx` appears as a key under `mcpServers` in either the local hint file or agy's live MCP config (`scripts/agy_bridge.sh:294-304`; `scripts/install.sh:246-254`). Never registered/written by this repo.
- **tokensave** — detection AND opt-in registration. `install.sh` can register `tokensave` as an agy MCP server by writing `{"command": <tokensave-bin>, "args": ["serve"]}` into `~/.gemini/antigravity-cli/mcp_config.json`'s `mcpServers` map (`scripts/install.sh:258-304`), gated behind `AGY_SETUP_REGISTER_TOKENSAVE=1` or an interactive y/N prompt (`scripts/install.sh:307-327`). This mutation is defensively written: reads raw bytes immediately before write (TOCTOU minimization), writes+verifies a byte-identical backup via SHA-256 hash comparison before touching the original, writes to a `tempfile.mkstemp` sibling with mode 0600, validates the JSON round-trips, then `os.replace`s atomically (`scripts/install.sh:268-304`).

When either is detected/enabled, `agy_bridge.sh` appends an advisory (non-enforcing) `GEMINI.md` stanza telling `agy` to prefer `ctx_read`/`ctx_search`/`tokensave_context` over raw file dumps, for `code|review|analysis|implement` types only — explicitly not for `search` or the `gemini_shim.sh` path (`scripts/agy_bridge.sh:278-320`). This is prompt-level guidance only; it does not relax `--sandbox`/`--add-dir` scoping.

## Shared Model-List Cache — `~/.cache/agy-bridge-models`

Both `scripts/agy_bridge.sh` (`CACHE_FILE` at `:136`) and `scripts/gemini_shim.sh` (`MODELS_CACHE` at `:74`) read AND write the **same** cache file path, `$HOME/.cache/agy-bridge-models`, independently:

- Same 60-minute freshness window, checked via `find "$CACHE_FILE" -mmin +60` (`scripts/agy_bridge.sh:138`, `scripts/gemini_shim.sh:82`).
- Same write pattern: write to `$CACHE_FILE.tmp.$$`, `mv` into place, `chmod 600` (`scripts/agy_bridge.sh:145-148`, `scripts/gemini_shim.sh:98-101`) — atomic rename, but each script uses its own `$$` (its own PID) as the tmp suffix, so two processes racing the same 60-minute expiry can both fetch and both write without corrupting each other's read (last writer wins; no lock).
- Same fallback: stale cache is used (with a WARNING to stderr in `agy_bridge.sh`; silently in `gemini_shim.sh` — deliberate, per comment at `scripts/gemini_shim.sh:104-106`, "a shadowing `gemini` running off its cache is normal operation, and a warning here would land in every Octopus/Metaswarm log line").
- Same raw-format normalization (`cut -f1` on `id<TAB>display name`) and same `sort -V | tail -1` "newest wins" version pick when auto-selecting a model class (`scripts/agy_bridge.sh:174`, `:188-190`; `scripts/gemini_shim.sh:108`, `:127`).

There is also a second, smaller shared cache: `~/.cache/agy-bridge-mcp`, written/read only by `agy_bridge.sh` (`scripts/agy_bridge.sh:283-313`) to remember the lean-ctx/tokensave detection result for 60 minutes — not shared with `gemini_shim.sh` (the shim does not do MCP-preference advertising at all).

## Filesystem Write Surface (install-time)

Per the security-model comment (`scripts/install.sh:22-23`), `install.sh` writes ONLY under: `~/.local/bin` (wrappers), `~` (rc file backups for the alias patch), `~/.config/agy-delegate` (the MCP-availability hint JSON), and `~/.gemini` (agy's own MCP config, opt-in tokensave registration only). It never touches the plugin repo itself.

## No Other External Services

No network calls originate directly from this repo's own code (no `curl`/`wget` to any API) — all network activity, including the actual Gemini model calls, happens inside the external `agy` binary, which this repo treats as an opaque black box. No database, no cloud SDK, no CI-integration script beyond the hand-rolled `tests/run-tests.sh`.

---

*Integration audit: 2026-08-18*
