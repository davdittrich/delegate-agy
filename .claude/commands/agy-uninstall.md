---
command: agy-uninstall
description: Print the one validated command to remove agy-delegate's launcher wrappers (agy-bridge + gemini shim) and optionally de-register tokensave
version: 1.6.0
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

The command resolves the plugin's own `scripts/uninstall.sh` from
`claude plugin list --json`, **validates** the resolved string matches
`*/agy-delegate/*/scripts/uninstall.sh` AND is a regular file, and only then
runs it — no blind `bash`-ing of an attacker-controlled path.

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
AGY_UNINSTALL_TOKENSAVE=1 bash "$RESOLVED"
```

(`"$RESOLVED"` is the validated uninstaller path from the command above.)
