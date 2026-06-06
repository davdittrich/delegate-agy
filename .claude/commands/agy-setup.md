---
command: agy-setup
description: One-time setup for agy-delegate — creates agy-bridge symlink in ~/.local/bin
version: 1.0.1
category: ai-delegation
tags: [agy, setup, install, bridge]
---

Create the `agy-bridge` symlink so agy commands work from any directory.

Run this ONCE after installing the plugin.

## Steps

1. Find the plugin scripts directory via `Bash`:

```bash
# Show the plugin install location
claude plugin list --json 2>/dev/null | grep -A2 agy-delegate || \
  ls ~/.claude/plugins/ 2>/dev/null | grep agy
```

2. Create the symlink (replace `<PLUGIN_PATH>` with the path from step 1):

```bash
mkdir -p ~/.local/bin
ln -sf "<PLUGIN_PATH>/scripts/agy_bridge.sh" ~/.local/bin/agy-bridge
chmod +x "<PLUGIN_PATH>/scripts/agy_bridge.sh"
echo "agy-bridge → $(readlink ~/.local/bin/agy-bridge)"
```

3. Verify `~/.local/bin` is in PATH:

```bash
echo $PATH | grep -q "$HOME/.local/bin" && echo "PATH OK" || \
  echo "Add 'export PATH=\"\$HOME/.local/bin:\$PATH\"' to your ~/.bashrc or ~/.zshrc"
```

4. Test the bridge:

```bash
agy-bridge --type search -- "test query: current date"
```

$ARGUMENTS
