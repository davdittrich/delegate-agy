#!/usr/bin/env bash
# uninstall.sh — reverse scripts/install.sh for agy-delegate.
#
#   - Removes ~/.local/bin/{agy-bridge,gemini} ONLY if they carry our signature
#     marker; restores any shadowed original from its .bak-agy-* backup.
#   - Optionally de-registers tokensave from the agy MCP config and removes the
#     availability hint (AGY_UNINSTALL_TOKENSAVE=1).
#   - Idempotent; refuses root; writes only under ~ subpaths, never the repo.

set -euo pipefail

WRAPPER_MARKER='# agy-delegate-wrapper'

# ── refuse root ──────────────────────────────────────────────────────────────
if [[ "${EUID:-$(id -u)}" -eq 0 || -n "${SUDO_USER:-}" ]]; then
    echo "ERROR: refusing to run as root (or via sudo). Run as your normal user." >&2
    exit 1
fi

[[ -n "${HOME:-}" ]] || { echo "ERROR: HOME is not set; run as a normal user with a home directory." >&2; exit 1; }
BIN_DIR="$HOME/.local/bin"

is_our_wrapper() {
    local f="$1"
    [[ -f "$f" ]] && grep -qF "$WRAPPER_MARKER" "$f"
}

# remove_wrapper NAME DEST — remove only if it is ours; restore newest backup.
remove_wrapper() {
    local name="$1" dest="$2"
    if [[ ! -e "$dest" && ! -L "$dest" ]]; then
        echo "'$name': nothing at '$dest' — skipping."
        return 0
    fi
    if ! is_our_wrapper "$dest"; then
        echo "'$name': '$dest' is not an agy-delegate wrapper — leaving it alone."
        return 0
    fi
    rm -f "$dest"
    echo "Removed '$dest'."
    # Restore the most recent backup we made, if any.
    local newest=""
    local b
    for b in "$dest".bak-agy-*; do
        [[ -e "$b" ]] || continue
        if [[ -z "$newest" || "$b" > "$newest" ]]; then
            newest="$b"
        fi
    done
    if [[ -n "$newest" ]]; then
        mv -f "$newest" "$dest"
        echo "Restored shadowed original from '$newest' -> '$dest'."
    fi
}

echo "== agy-delegate uninstaller =="
remove_wrapper "agy-bridge" "$BIN_DIR/agy-bridge"
remove_wrapper "gemini" "$BIN_DIR/gemini"

# ── optional: de-register tokensave + remove hint ────────────────────────────
AGY_MCP_CFG="$HOME/.gemini/antigravity-cli/mcp_config.json"
HINT="$HOME/.config/agy-delegate/config.json"

if [[ "${AGY_UNINSTALL_TOKENSAVE:-0}" == "1" ]]; then
    if command -v python3 >/dev/null 2>&1 && [[ -f "$AGY_MCP_CFG" ]]; then
        python3 - "$AGY_MCP_CFG" <<'PY'
import sys, json, os, tempfile, time
cfg = sys.argv[1]
raw = open(cfg, 'rb').read()
try:
    d = json.loads(raw)
except Exception as e:
    print(f"ERROR: agy mcp_config is not valid JSON ({e}); leaving it untouched.",
          file=sys.stderr)
    sys.exit(0)
srv = d.get('mcpServers', {})
if 'tokensave' not in srv:
    print("tokensave not registered — no change.")
    sys.exit(0)
bak = cfg + '.bak-agy-' + time.strftime('%Y%m%d%H%M%S')
open(bak, 'wb').write(raw)
del srv['tokensave']
dirn = os.path.dirname(cfg) or '.'
fd, tmp = tempfile.mkstemp(prefix='.mcp_config.', dir=dirn)
os.close(fd); os.chmod(tmp, 0o600)
try:
    with open(tmp, 'w') as f:
        json.dump(d, f, indent=2); f.write('\n')
    json.load(open(tmp))
except Exception as e:
    os.unlink(tmp)
    print(f"ERROR: wrote invalid temp ({e}); {cfg} unchanged.", file=sys.stderr)
    sys.exit(1)
os.replace(tmp, cfg)
print(f"De-registered tokensave from agy (backup: {bak}).")
PY
    fi
    if [[ -f "$HINT" ]]; then
        rm -f "$HINT"
        echo "Removed availability hint '$HINT'."
    fi
fi

echo "Done."
