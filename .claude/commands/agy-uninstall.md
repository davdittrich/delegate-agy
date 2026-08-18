---
command: agy-uninstall
description: Print the one validated command to remove agy-delegate's launcher wrappers (agy-bridge + gemini shim) and optionally de-register tokensave
version: 1.6.1
category: ai-delegation
tags: [agy, uninstall, cleanup]
---

agy-delegate ships a self-contained uninstaller that YOU run in your own
terminal (`scripts/uninstall.sh`). This command does NOT run it for you — it
prints the exact, validated one-line command to copy-paste.

The uninstaller reverses `scripts/install.sh`: it removes **only** our
signature-marked wrappers `~/.local/bin/agy-bridge` and `~/.local/bin/gemini`
(restoring any original binary that was shadowed and backed up at install
time), and — with `AGY_UNINSTALL_TOKENSAVE=1` — de-registers the `tokensave`
MCP server and removes the availability hint. It is idempotent and refuses to
run as root.

## Uninstall (copy-paste this)

Find the plugin's install path, then run its uninstaller. Both steps print a
path you can read before anything executes:

```bash
grep -A6 '"agy-delegate@' ~/.claude/plugins/installed_plugins.json \
  | sed -n 's/.*"installPath"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
```

That prints something like
`/home/you/.claude/plugins/cache/agy-delegate/agy-delegate/1.6.2`. Check it
looks right, then run:

```bash
bash <that-path>/scripts/uninstall.sh
```

If the registry file is missing (older Claude Code, or a non-standard config
dir), fall back to resolving it through the CLI — this form validates the
resolved string before executing it, because it comes from command output
rather than your own eyes:

```bash
RESOLVED="$(claude plugin list --json 2>/dev/null \
  | python3 -c 'import sys,json;[print(x.get("installPath","")) for x in json.load(sys.stdin) if x.get("id","").startswith("agy-delegate@")]' \
  | head -1)/scripts/uninstall.sh"; \
case "$RESOLVED" in \
  */agy-delegate/*/scripts/uninstall.sh) [[ -f "$RESOLVED" ]] \
    && bash "$RESOLVED" \
    || echo "ERROR: resolved uninstaller '$RESOLVED' is not a regular file — is agy-delegate installed?" >&2 ;; \
  *) echo "ERROR: refusing to run '$RESOLVED' — does not match */agy-delegate/*/scripts/uninstall.sh" >&2 ;; \
esac
```

## Also de-register tokensave + remove the availability hint

Prepend `AGY_UNINSTALL_TOKENSAVE=1`:

```bash
AGY_UNINSTALL_TOKENSAVE=1 bash <that-path>/scripts/uninstall.sh
```

(`<that-path>` is the uninstall path you printed above; if you used the CLI
fallback, replace `<that-path>/scripts/uninstall.sh` with `"$RESOLVED"` —
e.g. `AGY_UNINSTALL_TOKENSAVE=1 bash "$RESOLVED"`.)
