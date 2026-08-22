#!/usr/bin/env bash
# uninstall.sh — reverse scripts/install.sh for agy-delegate.
#
#   - Removes ~/.local/bin/{agy-bridge,gemini} ONLY if they carry our signature
#     marker; restores any shadowed original from its .bak-agy-* backup.
#   - Removes the MCP availability hint written by install.sh.
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

# ── remove the MCP availability hint ─────────────────────────────────────────
HINT="$HOME/.config/agy-delegate/config.json"

if [[ -f "$HINT" ]]; then
    rm -f "$HINT"
    echo "Removed availability hint '$HINT'."
fi

echo "Done."
