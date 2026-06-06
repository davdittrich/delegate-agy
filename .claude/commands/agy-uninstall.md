---
command: agy-uninstall
description: Remove agy-delegate plugin artifacts — only removes agy-bridge symlink if it points to this plugin's script
version: 1.0.1
category: ai-delegation
tags: [agy, uninstall, cleanup]
---

Remove agy-delegate plugin artifacts safely.

$ARGUMENTS

## Steps

1. Check if `agy-bridge` symlink exists and verify it points into the plugin before touching anything:

```bash
BRIDGE="$HOME/.local/bin/agy-bridge"
if [[ ! -L "$BRIDGE" ]]; then
  echo "agy-bridge not found at $BRIDGE — nothing to remove"
  exit 0
fi
TARGET=$(readlink "$BRIDGE")
echo "agy-bridge → $TARGET"
if echo "$TARGET" | grep -q "agy-delegate"; then
  rm "$BRIDGE"
  echo "Removed $BRIDGE"
else
  echo "SKIP: $BRIDGE points to '$TARGET' (not an agy-delegate path) — not removing"
fi
```

2. Uninstall the plugin via Claude Code:

```bash
claude plugin uninstall agy-delegate
```

3. Verify clean:

```bash
ls ~/.local/bin/agy-bridge 2>/dev/null && echo "WARNING: symlink still present" || echo "Clean"
claude plugin list | grep agy || echo "Plugin removed"
```
