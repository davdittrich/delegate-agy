---
command: agy-setup
description: One-time setup for agy-delegate — creates agy-bridge symlink in ~/.local/bin
version: 1.0.2
category: ai-delegation
tags: [agy, setup, install, bridge]
---

Create the `agy-bridge` symlink so agy commands work from any directory.

Run this ONCE after installing the plugin. Safe to re-run — skips if already correct.

## Steps

1. Resolve the plugin install path automatically:

```bash
PLUGIN_PATH=$(claude plugin list --json 2>/dev/null | \
  python3 -c "
import sys, json
data = json.load(sys.stdin)
m = [x for x in data if x.get('id','').startswith('agy-delegate@')]
print(m[0].get('installPath','')) if m else print('')
")
if [[ -z "$PLUGIN_PATH" ]]; then
  echo "ERROR: agy-delegate plugin not found in 'claude plugin list'" >&2
  exit 1
fi
echo "Plugin path: $PLUGIN_PATH"
```

2. Create the symlink (idempotent — skips if already correct):

```bash
BRIDGE="$HOME/.local/bin/agy-bridge"
SCRIPT="$PLUGIN_PATH/scripts/agy_bridge.sh"
mkdir -p ~/.local/bin
if [[ -L "$BRIDGE" && "$(readlink "$BRIDGE")" == "$SCRIPT" ]]; then
  echo "agy-bridge already correct — nothing to do"
else
  ln -sf "$SCRIPT" "$BRIDGE"
  chmod +x "$SCRIPT"
  echo "agy-bridge → $(readlink "$BRIDGE")"
fi
```

3. Verify `~/.local/bin` is in PATH:

```bash
echo "$PATH" | grep -q "$HOME/.local/bin" && echo "PATH OK" || \
  echo "Add 'export PATH=\"\$HOME/.local/bin:\$PATH\"' to your ~/.bashrc or ~/.zshrc"
```

4. Test the bridge:

```bash
agy-bridge --types
```
