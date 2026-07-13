---
command: agy-setup
description: One-time setup for agy-delegate — creates agy-bridge and gemini (shim) symlinks in ~/.local/bin
version: 1.3.0
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
      echo "WARNING: auto-patching $RC — backup at $RC.bak-agy-*" >&2
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
echo "$PATH" | grep -q "$HOME/.local/bin" && echo "PATH contains ~/.local/bin ✓" || {
  echo "~/.local/bin not in PATH. Add it for your shell:"
  echo "  bash/zsh:  export PATH=\"\$HOME/.local/bin:\$PATH\"  (add to ~/.bashrc or ~/.zshrc)"
  echo "  fish:      fish_add_path ~/.local/bin               (run once, persists)"
  echo "  nushell:   \$env.PATH = (\$env.PATH | prepend (\$env.HOME | path join .local bin))"
}
# Confirm shim is picked up before real gemini (if installed):
which gemini && gemini --version
```

5. Test the bridge and shim:

```bash
agy-bridge --types
echo "Say only: shim ok" | gemini -m gemini-2.5-flash -o text --approval-mode yolo
```

## 6. Register MCP servers for agy (opt-in) + availability hint

Let agy use the same lean-ctx / tokensave MCP tools you use. Registration is **opt-in**
(default **No**) because it grants agy code-graph read **plus local-project mutate** tools.
Set `AGY_SETUP_REGISTER_TOKENSAVE=1` to register non-interactively.

```bash
AGY_MCP_CFG="$HOME/.gemini/antigravity-cli/mcp_config.json"
HINT_DIR="$HOME/.config/agy-delegate"; HINT="$HINT_DIR/config.json"
TOKENSAVE_BIN=$(command -v tokensave 2>/dev/null || echo "$HOME/.local/bin/tokensave")

_agy_detect() { python3 - "$AGY_MCP_CFG" <<'PY'
import sys, json, os
p=sys.argv[1]; lc=ts=False
if os.path.exists(p):
    try:
        s=json.load(open(p)).get('mcpServers',{}); lc='lean-ctx' in s; ts='tokensave' in s
    except Exception: pass
print(f"{int(lc)} {int(ts)}")
PY
}
read AGY_HAS_LEANCTX AGY_HAS_TOKENSAVE < <(_agy_detect)

if [[ -x "$TOKENSAVE_BIN" && "$AGY_HAS_TOKENSAVE" == "0" ]]; then
  DO_REG="${AGY_SETUP_REGISTER_TOKENSAVE:-}"
  if [[ -z "$DO_REG" ]]; then
    if [[ -t 0 ]]; then
      read -rp "Register tokensave as an agy MCP server? Grants agy code-graph READ + local-project MUTATE tools. [y/N] " ans
      [[ "$ans" =~ ^[Yy]$ ]] && DO_REG=1 || DO_REG=0
    else
      echo "tokensave is available but not registered for agy. Re-run with AGY_SETUP_REGISTER_TOKENSAVE=1 to register (grants agy code-graph read + local-project mutate). Skipping."
      DO_REG=0
    fi
  fi
  if [[ "$DO_REG" == "1" ]]; then
    if [[ ! -f "$AGY_MCP_CFG" ]]; then
      echo "ERROR: agy mcp_config not found at $AGY_MCP_CFG — is agy installed/initialised? Skipping registration." >&2
    else
      python3 - "$AGY_MCP_CFG" "$TOKENSAVE_BIN" <<'PY'
import sys, json, os, hashlib, tempfile, time
cfg, tsbin = sys.argv[1], sys.argv[2]
raw = open(cfg, 'rb').read()
try:
    d = json.loads(raw)
except Exception as e:
    print(f"ERROR: agy mcp_config is not valid JSON ({e}); refusing to overwrite a recoverable config. Aborting.", file=sys.stderr); sys.exit(3)
srv = d.setdefault('mcpServers', {})
if 'tokensave' in srv:
    print("tokensave already registered for agy — no change."); sys.exit(0)
bak = cfg + '.bak-agy-' + time.strftime('%Y%m%d%H%M%S')
open(bak, 'wb').write(raw)
if hashlib.sha256(open(bak,'rb').read()).hexdigest() != hashlib.sha256(raw).hexdigest() or os.path.getsize(bak) != len(raw):
    print(f"ERROR: backup verification failed for {bak}; aborting without modifying {cfg}.", file=sys.stderr); sys.exit(4)
srv['tokensave'] = {"command": tsbin, "args": ["serve"]}
dirn = os.path.dirname(cfg) or '.'
fd, tmp = tempfile.mkstemp(prefix='.mcp_config.', dir=dirn); os.close(fd); os.chmod(tmp, 0o600)
try:
    with open(tmp, 'w') as f: json.dump(d, f, indent=2); f.write('\n')
    json.load(open(tmp))
except Exception as e:
    os.unlink(tmp); print(f"ERROR: wrote invalid JSON temp ({e}); removed temp, {cfg} unchanged. Backup at {bak}.", file=sys.stderr); sys.exit(5)
os.replace(tmp, cfg)
print(f"Registered tokensave for agy (backup: {bak}).")
PY
      [[ $? -ne 0 ]] && echo "tokensave registration did not complete (see error above); your existing config is unchanged." >&2
      read AGY_HAS_LEANCTX AGY_HAS_TOKENSAVE < <(_agy_detect)
    fi
  fi
fi

mkdir -p "$HINT_DIR"
python3 - "$HINT" "$AGY_HAS_LEANCTX" "$AGY_HAS_TOKENSAVE" <<'PY'
import sys, json
p, lc, ts = sys.argv[1], sys.argv[2] == '1', sys.argv[3] == '1'
json.dump({"lean_ctx": lc, "tokensave": ts}, open(p, 'w'), indent=2); open(p,'a').write('\n')
print(f"Wrote MCP availability hint {p}: lean_ctx={lc} tokensave={ts}")
PY

echo
echo "NOTE: if you registered tokensave, agy now has code-graph READ plus LOCAL-PROJECT MUTATE (edit/session) tools. Registration happens only on your explicit consent — re-run /agy-setup or edit $AGY_MCP_CFG to change."
```
