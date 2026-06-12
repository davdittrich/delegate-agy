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
    if grep -qP "^alias gemini='.*[^/]gemini'" "$RC" 2>/dev/null; then
      # Replace the bare 'gemini' at end of alias value with real path
      sed -i "s|^alias gemini='\(.*\) gemini'|alias gemini='\1 $REAL_GEMINI'|g" "$RC"
      echo "Patched recursive gemini alias in $RC → $REAL_GEMINI"
    fi
  done
fi
```

5. Verify `~/.local/bin` is in PATH AND precedes any real `gemini` installation:

```bash
echo "$PATH" | grep -q "$HOME/.local/bin" && echo "PATH contains ~/.local/bin ✓" || \
  echo "Add 'export PATH=\"\$HOME/.local/bin:\$PATH\"' to your ~/.bashrc or ~/.zshrc"
# Confirm shim is picked up before real gemini (if installed):
which gemini && gemini --version
```

6. Test the bridge and shim:

```bash
agy-bridge --types
echo "Say only: shim ok" | gemini -m gemini-2.5-flash -o text --approval-mode yolo
```
