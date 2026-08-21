---
command: agy-setup
description: Print the plugin's install path and the command to install agy-delegate's launcher wrappers (agy-bridge + gemini shim)
version: 1.6.2
category: ai-delegation
tags: [agy, setup, install, bridge, gemini]
---

agy-delegate ships a self-contained, hardened installer that YOU run in your
own terminal (`scripts/install.sh`). This command does NOT run it for you — it
prints two commands to copy-paste: one to find the plugin's install path so
you can read it yourself, and one to run the installer against that path —
plus the opt-in variants and the uninstall command.

## Shadow notice (read before installing)

The installer writes `~/.local/bin/gemini`, a drop-in shim that **shadows the
real `gemini` command for every caller** whose `PATH` includes `~/.local/bin`
first (your interactive shell, Claude Octopus, Metaswarm — all of them will
invoke agy instead). It also writes `~/.local/bin/agy-bridge`. Both are pinned
launchers that exec an absolute path recorded at install time; if the plugin is
moved (pinned path gone) they fail loud and ask you to re-run this install. If
the plugin is updated but Claude Code's cache leaves the old version directory
in place too (observed behavior), the pinned path still resolves — so the
wrapper compares its pinned version against the version Claude Code reports as
installed and refuses to run the stale copy, exiting `127` with both versions
and the repin command. Re-run this install to repin. To undo everything, run
the uninstall command at the bottom.

## Install (copy-paste this)

Find the plugin's install path, then run its installer. Both steps print a path
you can read before anything executes:

```bash
grep -A6 '"agy-delegate@' ~/.claude/plugins/installed_plugins.json \
  | sed -n 's/.*"installPath"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
```

That prints something like
`/home/you/.claude/plugins/cache/agy-delegate/agy-delegate/1.6.2`. Check it
looks right, then run:

```bash
bash <that-path>/scripts/install.sh
```

If the registry file is missing (older Claude Code, or a non-standard config
dir), fall back to resolving it through the CLI — this form validates the
resolved string before executing it, because it comes from command output
rather than your own eyes:

```bash
RESOLVED="$(claude plugin list --json 2>/dev/null \
  | python3 -c 'import sys,json;[print(x.get("installPath","")) for x in json.load(sys.stdin) if x.get("id","").startswith("agy-delegate@")]' \
  | head -1)/scripts/install.sh"; \
case "$RESOLVED" in \
  */agy-delegate/*/scripts/install.sh) [[ -f "$RESOLVED" ]] \
    && bash "$RESOLVED" \
    || echo "ERROR: resolved installer '$RESOLVED' is not a regular file — is agy-delegate installed?" >&2 ;; \
  *) echo "ERROR: refusing to run '$RESOLVED' — does not match */agy-delegate/*/scripts/install.sh" >&2 ;; \
esac
```

## Opt-in variants

Register tokensave as an agy MCP server (grants agy code-graph READ + local
project MUTATE tools) without the interactive prompt — prepend
`AGY_SETUP_REGISTER_TOKENSAVE=1`:

```bash
AGY_SETUP_REGISTER_TOKENSAVE=1 bash <that-path>/scripts/install.sh
```

Apply the recursive-`gemini` shell-rc alias patch (default is dry-run/advisory)
— prepend `AGY_SETUP_PATCH_ALIASES=1`:

```bash
AGY_SETUP_PATCH_ALIASES=1 bash <that-path>/scripts/install.sh
```

(Both flags can be combined. `<that-path>` is the install path you printed
above; if you used the CLI fallback, replace the whole
`<that-path>/scripts/install.sh` in each command above with `"$RESOLVED"` —
e.g. `AGY_SETUP_REGISTER_TOKENSAVE=1 bash "$RESOLVED"`.)

## Uninstall

Reverses the install: removes only our signature-marked wrappers (restoring any
shadowed original), and — with `AGY_UNINSTALL_TOKENSAVE=1` — de-registers
tokensave and removes the availability hint.

```bash
bash <that-path>/scripts/uninstall.sh
```

(`<that-path>` is the install path from the Install section above. If the
registry file was missing there and you used the CLI fallback instead, run
`/agy-uninstall` — it resolves and validates the uninstaller path the same
way.)
