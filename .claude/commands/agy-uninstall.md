---
command: agy-uninstall
description: Remove agy-delegate plugin artifacts — only removes agy-bridge symlink if it points to this plugin's script
version: 1.0.2
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
if [[ "$TARGET" == *"/agy_bridge.sh" ]]; then
  rm "$BRIDGE"
  echo "Removed $BRIDGE"
else
  echo "SKIP: $BRIDGE points to '$TARGET' (not agy_bridge.sh) — not removing"
fi
```

2. Reverse shell rc alias patches applied by agy-setup step 3 (idempotent — skips if not patched).
Set AGY_UNINSTALL_PATCH_ALIASES=1 to apply. Shows diff by default (dry-run).

```bash
# Reverse shell rc alias patches made by agy-setup step 3
command -v python3 &>/dev/null || { echo "python3 not found — skipping alias reversal"; exit 0; }

for RC in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_aliases"; do
  [[ -f "$RC" ]] || continue
  if grep -qE "^alias gemini='[^']*/gemini'$" "$RC" 2>/dev/null; then
    old_line=$(grep "^alias gemini=" "$RC" || true)
    new_line=$(echo "$old_line" | sed "s| /[^']*/gemini'$| gemini'|")
    echo "Would restore: $RC"
    echo "  Old: $old_line"
    echo "  New: $new_line"
    if [[ "${AGY_UNINSTALL_PATCH_ALIASES:-0}" != "1" ]]; then
      echo "  Set AGY_UNINSTALL_PATCH_ALIASES=1 to apply."
      continue
    fi
    cp "$RC" "$RC.bak-agy-$(date +%Y%m%d%H%M%S)"
    python3 -c "
import re, sys
rc = sys.argv[1]
txt = open(rc).read()
out = re.sub(r\"^(alias gemini='.*) /[^']+/gemini'$\", r\"\1 gemini'\", txt, flags=re.M)
open(rc, 'w').write(out)
" "$RC"
    echo "Restored $RC"
  fi
done
```

3. Uninstall the plugin via Claude Code:

```bash
claude plugin uninstall agy-delegate
```

4. Verify clean:

```bash
ls ~/.local/bin/agy-bridge 2>/dev/null && echo "WARNING: symlink still present" || echo "Clean"
claude plugin list | grep agy || echo "Plugin removed"
```
