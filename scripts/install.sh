#!/usr/bin/env bash
# install.sh — self-contained, hardened installer for agy-delegate (Option D).
#
# The USER runs this in their real terminal (zero ctx_shell/Bash allowlist
# constraints). It installs two launcher wrappers into ~/.local/bin:
#   - agy-bridge : execs this plugin's scripts/agy_bridge.sh
#   - gemini     : execs this plugin's scripts/gemini_shim.sh (drop-in shim)
#
# SECURITY MODEL
#   - Wrappers exec a PINNED ABSOLUTE PATH recorded at install time. The EXEC
#     TARGET is never derived from a cache glob (user-writable = exec-hijack)
#     and never from `claude plugin list` per invocation — only from the
#     install-time literal. (The wrapper does read Claude Code's install
#     registry, installed_plugins.json, but for COMPARISON ONLY: it matches its
#     own exact "<plugin>@<marketplace>" key, bounds the read to that entry, and
#     uses the result solely to detect a stale pin. No registry-supplied value
#     ever reaches exec or is printed as a path.) If the pinned target vanishes
#     (plugin updated/moved) the wrapper FAILS LOUD and tells the user to re-run
#     install; a stale pin likewise FAILS LOUD (exit 127) instead of running the
#     superseded copy.
#   - refuse-root; set -euo pipefail; every expansion quoted; [[ ]] not [ ].
#   - writes ONLY under ~/.local/bin, ~ (rc backups), ~/.config/agy-delegate,
#     ~/.gemini. NEVER touches the repo.
#
# Env flags (opt-in, default off):
#   AGY_SETUP_PATCH_ALIASES=1       apply the recursive-gemini rc alias patch
#
# Override the installer's self-resolved plugin dir (used by tests / manual
# installs from a clone) with AGY_PLUGIN_DIR=/abs/path/to/plugin-root.

set -euo pipefail

WRAPPER_MARKER='# agy-delegate-wrapper'

# ── refuse root ──────────────────────────────────────────────────────────────
if [[ "${EUID:-$(id -u)}" -eq 0 || -n "${SUDO_USER:-}" ]]; then
    echo "ERROR: refusing to run as root (or via sudo). Run as your normal user." >&2
    exit 1
fi

[[ -n "${HOME:-}" ]] || { echo "ERROR: HOME is not set; run as a normal user with a home directory." >&2; exit 1; }
# ── resolve this plugin's root (dir containing scripts/) ─────────────────────
if [[ -n "${AGY_PLUGIN_DIR:-}" ]]; then
    PLUGIN_DIR="$AGY_PLUGIN_DIR"
else
    _self="$(readlink -f "${BASH_SOURCE[0]}")"
    PLUGIN_DIR="$(cd "$(dirname "$_self")/.." && pwd)"
fi
BRIDGE_TARGET="$PLUGIN_DIR/scripts/agy_bridge.sh"
SHIM_TARGET="$PLUGIN_DIR/scripts/gemini_shim.sh"

if [[ ! -f "$BRIDGE_TARGET" || ! -f "$SHIM_TARGET" ]]; then
    echo "ERROR: could not locate plugin scripts under '$PLUGIN_DIR/scripts'." >&2
    echo "       Set AGY_PLUGIN_DIR to the agy-delegate plugin root and re-run." >&2
    exit 1
fi

BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"

_ts() { date +%Y%m%d%H%M%S; }

# _sq VALUE -> VALUE safe to embed inside a single-quoted shell string: each
# embedded ' becomes '\'' (close quote, escaped literal quote, reopen quote).
# Every install-time value interpolated into the single-quoted contexts of
# the generated wrapper heredoc below MUST go through this first -- an
# apostrophe anywhere in the plugin cache path (e.g. a $HOME with one)
# otherwise terminates the quoting early and emits a broken wrapper.
_sq() { printf '%s' "${1//\'/\'\\\'\'}"; }

# is_our_wrapper PATH -> 0 if the file exists and carries our signature marker.
is_our_wrapper() {
    local f="$1"
    [[ -f "$f" ]] && grep -qF "$WRAPPER_MARKER" "$f"
}

# write_wrapper NAME PINNED_TARGET DEST
# Emits a pinned-path launcher: fail-loud on missing target, validate regular
# file, exec -a sets the launcher argv0; the shim resolves its own path via BASH_SOURCE. NO cache glob, claude list, or install registry feeds the EXEC TARGET.
# The exec target is always the pinned literal below. The stale-pin check reads
# Claude Code's install registry for COMPARISON ONLY: when the active version
# differs from the pin it exits 127 instead of running the stale copy, and the
# repin path it prints is constructed from install-time literals, never from
# anything the registry supplied.
write_wrapper() {
    local name="$1" target="$2" dest="$3"
    # Non-clobber: back up a pre-existing NON-agy file at dest.
    if [[ -e "$dest" || -L "$dest" ]] && ! is_our_wrapper "$dest"; then
        local bak
        bak="$dest.bak-agy-$(_ts)"
        cp -Pf "$dest" "$bak"
        echo "WARNING: '$dest' already exists and is not an agy-delegate wrapper." >&2
        echo "         Backed it up to '$bak' before overwriting." >&2
    fi
    # Derive the pinned version dir's own basename, its parent (the versions
    # root, e.g. .../agy-delegate/agy-delegate/) and this install's registry
    # key, so the generated wrapper can detect a stale pin. All are
    # install-time literals baked into the heredoc below, same as _AGY_TARGET.
    local scripts_dir version_dir version parent_dir marketplace_dir reg_key reg_key_re
    scripts_dir="${target%/*}"
    version_dir="${scripts_dir%/*}"
    version="${version_dir##*/}"
    parent_dir="${version_dir%/*}"        # .../plugins/cache/<marketplace>/<plugin>
    marketplace_dir="${parent_dir%/*}"    # .../plugins/cache/<marketplace>
    # Registry key is "<plugin>@<marketplace>", and the cache layout is
    # cache/<marketplace>/<plugin>/<version>/ -- so both halves come from the
    # pinned path itself. Deriving the EXACT key (rather than matching a
    # "agy-delegate@" prefix) means a lookalike plugin installed from a
    # different marketplace cannot match this address.
    reg_key="${parent_dir##*/}@${marketplace_dir##*/}"
    # The wrapper matches that key as a sed ADDRESS, so escape the BRE
    # metacharacters a directory name could legally contain; without this an
    # unlucky (or hostile) name would widen the match beyond our own entry.
    reg_key_re="$(printf '%s' "$reg_key" | sed 's|[][\.*^$]|\\&|g')"
    # Every value above is now baked into the heredoc's single-quoted
    # contexts below; run each through _sq first, together, so an apostrophe
    # anywhere in the plugin cache path can't reopen a quote early.
    local target_sq version_sq parent_dir_sq reg_key_re_sq
    target_sq="$(_sq "$target")"
    version_sq="$(_sq "$version")"
    parent_dir_sq="$(_sq "$parent_dir")"
    reg_key_re_sq="$(_sq "$reg_key_re")"
    local tmp
    tmp="$(mktemp "$dest.agy-tmp.XXXXXX")"
    cat > "$tmp" <<WRAP
#!/usr/bin/env bash
$WRAPPER_MARKER
# Pinned launcher for agy-delegate '$name'. Generated by install.sh — do not edit.
# Execs a PINNED ABSOLUTE PATH; fails loud if the plugin moved/was updated.
set -euo pipefail
_AGY_TARGET='$target_sq'
_AGY_VERSION='$version_sq'
_AGY_VERSIONS_ROOT='$parent_dir_sq'
if [[ ! -f "\$_AGY_TARGET" ]]; then
    echo "ERROR: agy-delegate moved or was updated; '\$_AGY_TARGET' is gone." >&2
    echo "       Re-run the install one-liner (see /agy-setup) to repin it." >&2
    exit 127
fi
# Stale-pin check: compare the install-time pinned version against the version
# Claude Code currently reports as installed. COMPARISON ONLY -- nothing read
# here reaches exec; \$_AGY_TARGET stays the install-time literal above.
# A missing or unparseable registry is silence, not an error: dev and test
# installs have no registry and must keep working; the pipeline ends in
# '|| true' because this wrapper runs under 'set -euo pipefail'.
# The window is bounded to OUR OWN entry, not a fixed line count: the range
# starts only on a line ending in '[' (so an empty '"key": [],' entry matches
# nothing rather than running on into the next plugin) and ends at that
# array's own ']'. The version match is anchored at line start so a compact,
# single-line registry cannot hand back a later entry's version. Both shapes
# otherwise mis-attribute a NEIGHBOURING plugin's version and refuse to run.
# HOME is guarded because bash expands the ':-' default word whenever
# CLAUDE_CONFIG_DIR is unset, and this wrapper runs under 'set -u': an unset
# HOME would abort it here, before the exec below. With neither variable set the
# registry is genuinely unreadable, so the '-r' guard skips the check and the
# wrapper runs -- the same degradation as a dev install with no registry.
_AGY_REGISTRY="\${CLAUDE_CONFIG_DIR:-\${HOME:-/nonexistent}/.claude}/plugins/installed_plugins.json"
if [[ -r "\$_AGY_REGISTRY" ]]; then
    _agy_active="\$(sed -n '/"$reg_key_re_sq":[[:space:]]*\[\$/,/^[[:space:]]*\]/p' "\$_AGY_REGISTRY" 2>/dev/null \
        | sed -nE 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' | head -1 || true)"
    if [[ -n "\$_agy_active" && "\$_agy_active" != "\$_AGY_VERSION" ]]; then
        echo "ERROR: agy-delegate \$_agy_active is installed, but this launcher is pinned to \$_AGY_VERSION." >&2
        echo "       Refusing to run the stale \$_AGY_VERSION copy." >&2
        # The repin path is CONSTRUCTED from the install-time versions root plus
        # a version string validated as numeric. No registry-supplied path is
        # ever printed: a hostile plugin that got its entry matched could
        # otherwise make this line tell the user to bash an attacker path.
        if [[ "\$_agy_active" =~ ^[0-9]+(\.[0-9]+)*\$ ]] \
           && [[ -f "\$_AGY_VERSIONS_ROOT/\$_agy_active/scripts/install.sh" ]]; then
            echo "       Re-run: bash \$_AGY_VERSIONS_ROOT/\$_agy_active/scripts/install.sh" >&2
        else
            echo "       Re-run the installer (see /agy-setup) to repin." >&2
        fi
        exit 127
    fi
fi
exec -a "$name" bash "\$_AGY_TARGET" "\$@"
WRAP
    chmod +x "$tmp"
    chmod +x "$target" 2>/dev/null || true
    mv -f "$tmp" "$dest"
    echo "Installed '$name' -> $target"
}

echo "== agy-delegate installer =="
echo "Plugin root: $PLUGIN_DIR"

# ── full-$PATH shadow scan (before writing the gemini wrapper) ───────────────
_real_gemini=""
IFS=':' read -r -a _path_parts <<< "${PATH:-}"
for _d in "${_path_parts[@]}"; do
    [[ -z "$_d" ]] && continue
    [[ "$_d" == "$BIN_DIR" ]] && continue
    _cand="$_d/gemini"
    if [[ -x "$_cand" && ! -d "$_cand" ]] && ! is_our_wrapper "$_cand"; then
        _real_gemini="$_cand"
        break
    fi
done
if [[ -n "$_real_gemini" ]]; then
    echo "WARNING: a real 'gemini' exists at '$_real_gemini'." >&2
    echo "         The agy shim in '$BIN_DIR/gemini' will SHADOW it for every PATH caller." >&2
fi

# ── write the two pinned wrappers ────────────────────────────────────────────
write_wrapper "agy-bridge" "$BRIDGE_TARGET" "$BIN_DIR/agy-bridge"
write_wrapper "gemini" "$SHIM_TARGET" "$BIN_DIR/gemini"

# ── shadow disclosure notice ─────────────────────────────────────────────────
echo
echo "NOTICE: '$BIN_DIR/gemini' now shadows the 'gemini' command for ALL callers"
echo "        whose PATH includes '$BIN_DIR' before any real gemini install."
echo "        Blast radius: every tool that runs 'gemini' (Claude Octopus,"
echo "        Metaswarm, your interactive shell) will invoke agy instead."
echo "        To undo: run scripts/uninstall.sh (removes only our wrappers and"
echo "        restores any backed-up original)."

# ── PATH-in-place check ──────────────────────────────────────────────────────
if [[ ":${PATH:-}:" == *":$BIN_DIR:"* ]]; then
    echo "PATH contains '$BIN_DIR' — good."
else
    echo "WARNING: '$BIN_DIR' is not in PATH. Add it for your shell:" >&2
    echo "  bash/zsh:  export PATH=\"\$HOME/.local/bin:\$PATH\"  (add to your rc file)" >&2
    echo "  fish:      fish_add_path ~/.local/bin" >&2
fi

# ── consent-gated recursive-gemini rc alias patch (dry-run unless flag) ───────
if [[ -n "$_real_gemini" ]]; then
    _alias_patch_py3_ok=1
    _alias_patch_py3_warned=0
    for RC in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_aliases"; do
        [[ -f "$RC" ]] || continue
        if grep -qE "^alias gemini='[^']* gemini'\$" "$RC" 2>/dev/null; then
            old_line="$(grep "^alias gemini=" "$RC" || true)"
            echo "Recursive 'gemini' alias found in $RC:"
            echo "  $old_line"
            if [[ "${AGY_SETUP_PATCH_ALIASES:-0}" != "1" ]]; then
                echo "  (dry-run) set AGY_SETUP_PATCH_ALIASES=1 to rewrite it to call $_real_gemini."
                continue
            fi
            if [[ "${AGY_SETUP_PATCH_ALIASES:-0}" == "1" ]] && ! command -v python3 >/dev/null 2>&1; then
                _alias_patch_py3_ok=0
                [[ "$_alias_patch_py3_warned" -eq 1 ]] || \
                    echo "WARNING: python3 not found — skipping the recursive-gemini rc alias patch (fail-open)." >&2
                _alias_patch_py3_warned=1
            fi
            [[ "$_alias_patch_py3_ok" -eq 1 ]] || continue
            cp -f "$RC" "$RC.bak-agy-$(_ts)"
            python3 - "$RC" "$_real_gemini" <<'PY'
import re, sys
rc, real = sys.argv[1], sys.argv[2]
txt = open(rc).read()
out = re.sub(r"^(alias gemini='.*) gemini'$",
             lambda m: m.group(1) + ' ' + real + "'", txt, flags=re.M)
open(rc, 'w').write(out)
PY
            echo "Patched $RC (backup written)."
        fi
    done
fi

# ── detect lean-ctx MCP availability + write hint (read-only; never mutates
# the agy MCP config) ─────────────────────────────────────────────────────────
AGY_MCP_CFG="$HOME/.gemini/antigravity-cli/mcp_config.json"
HINT_DIR="$HOME/.config/agy-delegate"
HINT="$HINT_DIR/config.json"

_agy_detect() {
    if ! command -v python3 >/dev/null 2>&1; then
        echo "0"
        return 0
    fi
    python3 - "$AGY_MCP_CFG" <<'PY'
import sys, json, os
p = sys.argv[1]; lc = False
if os.path.exists(p):
    try:
        s = json.load(open(p)).get('mcpServers', {})
        lc = 'lean-ctx' in s
    except Exception:
        pass
print(f"{int(lc)}")
PY
}
read -r AGY_HAS_LEANCTX < <(_agy_detect)

mkdir -p "$HINT_DIR"
if command -v python3 >/dev/null 2>&1; then
    python3 - "$HINT" "$AGY_HAS_LEANCTX" <<'PY'
import sys, json
p, lc = sys.argv[1], sys.argv[2] == '1'
json.dump({"lean_ctx": lc}, open(p, 'w'), indent=2)
open(p, 'a').write('\n')
print(f"Wrote MCP availability hint {p}: lean_ctx={lc}")
PY
fi

# ── final LIVE verify (non-fatal) ────────────────────────────────────────────
# `--types` prints a static table and exits inside the bridge's argument loop,
# before it ever reaches agy, so it needs no bound of its own.
echo
echo "== live verify (non-fatal) =="
if "$BIN_DIR/agy-bridge" --types >/dev/null 2>&1; then
    echo "agy-bridge --types: ok"
else
    echo "agy-bridge --types: could not run (agy may not be installed/authed yet)."
fi
# The smoke call is a REAL delegation, so unbounded it inherits the shim's 600s
# default -- ten minutes of silence under a line that says "non-fatal". The
# assignment prefix hands the shim its own smoke-test bound instead, overriding
# whatever the user set for work calls: this is one flash sentence, so 20s is
# already generous, and on expiry the shim exits 124 into the "could not run"
# branch below. Deliberately NOT a third copy of run_bounded, and deliberately
# not `timeout` (which is exactly what may be missing on the hosts this
# protects) -- the shim's own bound already carries the SIGKILL escalation and
# the pure-bash fallback, and reusing it costs one assignment.
if printf 'Say only: shim ok\n' | GEMINI_SHIM_TIMEOUT=20 "$BIN_DIR/gemini" -m gemini-2.5-flash -o text --approval-mode yolo >/dev/null 2>&1; then
    echo "gemini shim smoke: ok"
else
    echo "gemini shim smoke: could not run (agy may not be installed/authed yet)."
fi

echo
echo "Done. If '$BIN_DIR' is on your PATH, 'agy-bridge' and 'gemini' are ready."
