---
command: agy-setup
description: One-time setup for agy-delegate — creates agy-bridge and gemini (shim) symlinks in ~/.local/bin
version: 1.2.0
category: ai-delegation
tags: [agy, setup, install, bridge, gemini]
---

Create the `agy-bridge` and `gemini` symlinks so agy commands work from any directory, and
so frameworks that call `gemini` (Claude Octopus, Metaswarm) automatically use agy instead.

Run this ONCE after installing the plugin. Safe to re-run — skips if already correct.

## Steps

1. Resolve the plugin install path automatically:

```bash
command -v python3 &>/dev/null || { echo "ERROR: python3 required for plugin path resolution" >&2; exit 2; }

CLAUDE_JSON=$(claude plugin list --json 2>&1)
if [[ $? -ne 0 ]]; then
  echo "ERROR: 'claude plugin list' failed: $CLAUDE_JSON" >&2
  exit 1
fi
PLUGIN_PATH=$(printf '%s' "$CLAUDE_JSON" | python3 -c "
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

2. Create symlinks (idempotent — skips if already correct):

```bash
mkdir -p ~/.local/bin

# agy-bridge
BRIDGE="$HOME/.local/bin/agy-bridge"
BRIDGE_SCRIPT="$PLUGIN_PATH/scripts/agy_bridge.sh"
if [[ -L "$BRIDGE" && "$(readlink "$BRIDGE")" == "$BRIDGE_SCRIPT" ]]; then
  echo "agy-bridge already correct — skipping"
else
  ln -sf "$BRIDGE_SCRIPT" "$BRIDGE"
  chmod +x "$BRIDGE_SCRIPT"
  echo "agy-bridge → $(readlink "$BRIDGE")"
fi

# gemini shim — lets Octopus + Metaswarm use agy automatically
GEMINI_SHIM="$HOME/.local/bin/gemini"
SHIM_SCRIPT="$PLUGIN_PATH/scripts/gemini_shim.sh"
if [[ -L "$GEMINI_SHIM" && "$(readlink "$GEMINI_SHIM")" == "$SHIM_SCRIPT" ]]; then
  echo "gemini shim already correct — skipping"
else
  ln -sf "$SHIM_SCRIPT" "$GEMINI_SHIM"
  chmod +x "$SHIM_SCRIPT"
  echo "gemini (shim) → $(readlink "$GEMINI_SHIM")"
fi
```

3. Fix recursive `gemini` alias in shell rc files (idempotent):

If a shell alias wraps `gemini` with env vars but calls `gemini` recursively (e.g. lean-ctx
agent aliases), it must be patched to call the real binary — otherwise the alias loops
infinitely when invoked interactively while the shim intercepts non-interactive callers.

By default this step is **dry-run only** — it shows what would change but does NOT write
any file. To apply changes, set `AGY_SETUP_PATCH_ALIASES=1` before running. A timestamped
`.bak-agy-*` backup is written beside each rc file before any modification.

```bash
# Find real gemini binary (not ~/.local/bin shim)
REAL_GEMINI=$(PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "$HOME/.local/bin" | tr '\n' ':') command -v gemini 2>/dev/null || true)
if [[ -z "$REAL_GEMINI" ]]; then
  echo "No real gemini binary found outside ~/.local/bin — skipping alias fix"
else
  echo "Real gemini binary: $REAL_GEMINI"
  for RC in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_aliases"; do
    [[ -f "$RC" ]] || continue
    # Match alias lines that contain 'gemini' but call 'gemini' without a path
    # Pattern: alias gemini='...' where the value contains ' gemini' (recursive)
    if grep -qE "^alias gemini='[^']* gemini'$" "$RC" 2>/dev/null; then
      old_line=$(grep "^alias gemini=" "$RC" || true)
      new_line=$(echo "$old_line" | python3 -c "
import sys
line = sys.stdin.read().rstrip()
import re
print(re.sub(r\"(alias gemini='.*) gemini'$\", r\"\1 $REAL_GEMINI'\", line))
")
      echo "Would patch: $RC"
      echo "  Old: $old_line"
      echo "  New: $new_line"
      if [[ "${AGY_SETUP_PATCH_ALIASES:-0}" != "1" ]]; then
        echo "  Set AGY_SETUP_PATCH_ALIASES=1 to apply."
        continue
      fi
      cp "$RC" "$RC.bak-agy-$(date +%Y%m%d%H%M%S)"
      python3 -c "
import re, sys
rc, real = sys.argv[1], sys.argv[2]
txt = open(rc).read()
out = re.sub(r\"^(alias gemini='.*) gemini'$\", lambda m: m.group(1) + ' ' + real + \"'\", txt, flags=re.M)
open(rc, 'w').write(out)
" "$RC" "$REAL_GEMINI"
      echo "Patched $RC"
    fi
  done
fi
```

4. Verify `~/.local/bin` is in PATH AND precedes any real `gemini` installation:

```bash
echo "$PATH" | grep -q "$HOME/.local/bin" && echo "PATH contains ~/.local/bin ✓" || \
  echo "Add 'export PATH=\"\$HOME/.local/bin:\$PATH\"' to your ~/.bashrc or ~/.zshrc"
# Confirm shim is picked up before real gemini (if installed):
which gemini && gemini --version
```

5. Test the bridge and shim:

```bash
agy-bridge --types
echo "Say only: shim ok" | gemini -m gemini-2.5-flash -o text --approval-mode yolo
```
