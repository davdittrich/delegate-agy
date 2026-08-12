---
command: agy-setup
description: Print the one secure command to install agy-delegate's launcher wrappers (agy-bridge + gemini shim)
version: 1.5.1
category: ai-delegation
tags: [agy, setup, install, bridge, gemini]
---

agy-delegate ships a self-contained, hardened installer that YOU run in your
own terminal (`scripts/install.sh`). This command does NOT run it for you — it
prints the exact, validated one-line command to copy-paste, plus the opt-in
variants and the uninstall command.

## Shadow notice (read before installing)

The installer writes `~/.local/bin/gemini`, a drop-in shim that **shadows the
real `gemini` command for every caller** whose `PATH` includes `~/.local/bin`
first (your interactive shell, Claude Octopus, Metaswarm — all of them will
invoke agy instead). It also writes `~/.local/bin/agy-bridge`. Both are pinned
launchers that exec an absolute path recorded at install time; if the plugin is
updated or moved they fail loud and ask you to re-run this install. To undo
everything, run the uninstall command at the bottom.

## Install (copy-paste this)

The command resolves the plugin's own `scripts/install.sh` from
`claude plugin list --json`, **validates** the resolved string matches
`*/agy-delegate/*/scripts/install.sh` AND is a regular file, and only then
runs it. It refuses anything that does not match — no blind `bash`-ing of an
attacker-controlled path.

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
AGY_SETUP_REGISTER_TOKENSAVE=1 bash "$RESOLVED"
```

Apply the recursive-`gemini` shell-rc alias patch (default is dry-run/advisory)
— prepend `AGY_SETUP_PATCH_ALIASES=1`:

```bash
AGY_SETUP_PATCH_ALIASES=1 bash "$RESOLVED"
```

(Both flags can be combined; `"$RESOLVED"` is the validated installer path from
the install command above.)

## Uninstall

Reverses the install: removes only our signature-marked wrappers (restoring any
shadowed original), and — with `AGY_UNINSTALL_TOKENSAVE=1` — de-registers
tokensave and removes the availability hint.

```bash
bash "$(dirname "$RESOLVED")/uninstall.sh"
```
