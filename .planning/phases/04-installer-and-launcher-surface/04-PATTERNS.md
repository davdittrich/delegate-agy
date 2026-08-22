# Phase 4: Installer and launcher surface - Pattern Map

**Mapped:** 2026-08-21
**Files analyzed:** 6 (all modified, zero new files — this is an audit-and-close-gaps phase)
**Analogs found:** 6 / 6 (every fix has an in-repo, already-shipped sibling pattern to copy — no external-pattern fallback needed)

## Context note

This phase adds no new files and no new architectural surface. Every one of D-01/D-03/D-05/D-06 (plus the D-04 test) is "copy an existing pattern that already lives a few lines away in the same file, to a new call site." The table below therefore points at analogs **within the same file being modified** wherever one exists — that is the strongest possible match for this phase, stronger than reaching to a different file.

## File Classification

| Modified File | Fix(es) | Role | Data Flow | Closest Analog | Match Quality |
|----------------|---------|------|-----------|-----------------|---------------|
| `scripts/install.sh` | D-01 (python3 guard before rc-alias loop) | utility / precondition guard | file-I/O (guards a file-patching loop) | `scripts/install.sh:279-283` `_register_tokensave`'s own python3-absent guard | exact — same file, same fail-open shape |
| `scripts/install.sh` | D-06 (HOME precondition) | utility / precondition guard | request-response (validate env → exit 1 or continue) | `scripts/install.sh:37-40` the existing refuse-root check | exact — same file, same site, same `[[ ]] || { ...; exit 1; }` shape |
| `scripts/uninstall.sh` | D-06 (HOME precondition) | utility / precondition guard | request-response | `scripts/uninstall.sh:15-17` the existing refuse-root check (mirrors `install.sh`'s) | exact |
| `.claude/commands/agy-setup.md` | D-05 (content sync), then D-03 (SIGPIPE fix on the post-sync block) | docs (static) + embedded user-run one-liner | file-I/O (D-05: whole-file replace) / request-response (D-03: the one-liner itself) | D-05: `fix/agy-bridge-resilience:.claude/commands/agy-setup.md` (branch tip, byte-for-byte sync source). D-03: `scripts/install.sh`'s own `python3 -c`/`python3 -` JSON idioms (`_agy_detect` `:260-274`, `_register_tokensave` `:279-322`) | D-05: exact (direct copy). D-03: role-match (same JSON-parsing idiom, different file, needs list-truncation rewrite) |
| `.claude/commands/agy-uninstall.md` | D-05, D-03 (identical shape to agy-setup.md) | same | same | Mirror of the row above, targeting `uninstall.sh` instead of `install.sh` | D-05: exact. D-03: role-match |
| `.claude-plugin/plugin.json` | D-05 (version string sync) | config | file-I/O (static value edit) | `fix/agy-bridge-resilience:.claude-plugin/plugin.json` (branch tip) | exact — the diff is one field (`"version": "1.6.1"` → `"1.6.2"`); no design decision |
| `tests/run-tests.sh` | new case for D-01 | test | integration (isolated `env -i` subprocess + assertion) | `tests/run-tests.sh:3810-3825` (I8b, real recursive alias + flag) composed with `:3862-3881` (I10, `nopy`-style python3-absent `PATH`) | exact — both source patterns already exist inline in this same file, composition only |
| `tests/run-tests.sh` | new case(s) for D-06 | test | integration | `tests/run-tests.sh:3759-3765` (I6, install.sh refuse-root) + `:3771-3778` (I6b, uninstall.sh refuse-root) | role-match — same harness shape, swap the `SUDO_USER` precondition trigger for an absent-`HOME` trigger |
| `tests/run-tests.sh` | new extractor + case for D-04 | test | integration / file-I/O (extract a fenced block from a `.md` file, exec it as a subprocess) | `tests/run-tests.sh:1675-1677` (`_rb_extract`, marker-anchored block extraction) + `:1874-1897` (RB21, extract-then-exec-under-`bash -c`-with-a-fake-stub-on-PATH usage pattern) | role-match — same extraction/exec technique, first application to a `.md` file instead of `agy_bridge.sh`/`gemini_shim.sh` |

## Pattern Assignments

### `scripts/install.sh` — D-01: python3 guard before the rc-alias-patch loop

**Analog (same file):** `scripts/install.sh:279-283` — `_register_tokensave`'s existing fail-open guard.

**Pattern to copy verbatim (shape, not literal message):**
```bash
# Source: scripts/install.sh:279-283 (current, read this session)
_register_tokensave() {
    if ! command -v python3 >/dev/null 2>&1; then
        echo "WARNING: python3 not found — skipping tokensave registration (fail-open)." >&2
        return 0
    fi
```

**Exact insertion site — current code (verified this session, line numbers match RESEARCH.md):**
```bash
# Source: scripts/install.sh:226-250
# ── consent-gated recursive-gemini rc alias patch (dry-run unless flag) ───────
if [[ -n "$_real_gemini" ]]; then                                    # line 227
    for RC in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_aliases"; do   # line 228
        [[ -f "$RC" ]] || continue
        if grep -qE "^alias gemini='[^']* gemini'\$" "$RC" 2>/dev/null; then
            old_line="$(grep "^alias gemini=" "$RC" || true)"
            echo "Recursive 'gemini' alias found in $RC:"
            echo "  $old_line"
            if [[ "${AGY_SETUP_PATCH_ALIASES:-0}" != "1" ]]; then       # line 234
                echo "  (dry-run) set AGY_SETUP_PATCH_ALIASES=1 to rewrite it to call $_real_gemini."
                continue
            fi
            cp -f "$RC" "$RC.bak-agy-$(_ts)"
            python3 - "$RC" "$_real_gemini" <<'PY'                       # line 239
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
```

**Where D-01's guard goes:** immediately after `if [[ -n "$_real_gemini" ]]; then` (line 227), before the `for RC in ...` loop (line 228) — a single `command -v python3` check, not one per matched RC file. Naming the feature specifically (per D-01), mirroring `_register_tokensave`'s wording pattern (`"WARNING: python3 not found — skipping <feature> (fail-open)."`).

**Open structural question (flagged in RESEARCH.md, not resolved there — planner must pick one reading):** the ticket's two anchors ("after the flag gate is confirmed true" AND "before the loop starts") don't coincide today because `AGY_SETUP_PATCH_ALIASES` is currently checked per-RC-file *inside* the loop (line 234), not hoisted. RESEARCH.md's recommended reading: gate the new guard on `[[ "${AGY_SETUP_PATCH_ALIASES:-0}" == "1" ]] && ! command -v python3 ...` evaluated once before the loop, leaving the existing per-file dry-run advisory (line 234-236) untouched for the flag-off case; carry a boolean so the loop's existing `python3 -` call (line 239) is skipped once the warning fired.

---

### `scripts/install.sh` + `scripts/uninstall.sh` — D-06: HOME precondition

**Analog (same file, in both cases):** the existing refuse-root check, immediately above the insertion point in each file.

**`install.sh` analog + insertion site (verified this session):**
```bash
# Source: scripts/install.sh:37-41 (current)
if [[ "${EUID:-$(id -u)}" -eq 0 || -n "${SUDO_USER:-}" ]]; then
    echo "ERROR: refusing to run as root (or via sudo). Run as your normal user." >&2
    exit 1
fi
# <-- D-06's HOME precondition goes here (new code), before line 58's first $HOME use:
#     BIN_DIR="$HOME/.local/bin"
```

**`uninstall.sh` analog + insertion site (verified this session):**
```bash
# Source: scripts/uninstall.sh:15-19 (current)
if [[ "${EUID:-$(id -u)}" -eq 0 || -n "${SUDO_USER:-}" ]]; then
    echo "ERROR: refusing to run as root (or via sudo). Run as your normal user." >&2
    exit 1
fi
# <-- D-06's HOME precondition goes here (new code), before line 20's first $HOME use:
#     BIN_DIR="$HOME/.local/bin"
```

**Exact new code, locked verbatim by D-06 (not discretionary):**
```bash
[[ -n "${HOME:-}" ]] || { echo "ERROR: HOME is not set; run as a normal user with a home directory." >&2; exit 1; }
```

**Every remaining unguarded `$HOME` site this precondition must precede (verified this session, current line numbers — do not use the ticket's own stale citations):**
- `install.sh:58, 228, 253, 254, 256`
- `uninstall.sh:20, 60, 61`

**Anti-pattern explicitly forbidden by D-06** (do not copy this shape from the generated-wrapper heredoc even though it looks similar): `scripts/install.sh`'s `write_wrapper` heredoc uses `"${HOME:-/nonexistent}"` internally (inside the *generated* wrapper, not in `install.sh` itself) — that fallback is correct for the wrapper (degrade to silence at every invocation) but wrong for `install.sh`/`uninstall.sh` themselves, which must refuse outright.

---

### `.claude/commands/agy-setup.md` + `.claude/commands/agy-uninstall.md` — D-05 (sync) then D-03 (SIGPIPE fix)

**D-05 analog:** `fix/agy-bridge-resilience` branch tip. Read in full this session via `git show`; sync mechanism is a straight copy, not a hand-rewrite.

**Current (pre-sync) content, `agy-setup.md`** (fenced hazard block at lines 36-46, verified this session):
```bash
# Source: .claude/commands/agy-setup.md:37-45 (current master)
RESOLVED="$(claude plugin list --json 2>/dev/null \
  | python3 -c 'import sys,json;[print(x.get("installPath","")) for x in json.load(sys.stdin) if x.get("id","").startswith("agy-delegate@")]' \
  | head -1)/scripts/install.sh"; \
case "$RESOLVED" in \
  */agy-delegate/*/scripts/install.sh) [[ -f "$RESOLVED" ]] \
    && bash "$RESOLVED" \
    || echo "ERROR: resolved installer '$RESOLVED' is not a regular file — is agy-delegate installed?" >&2 ;; \
  *) echo "ERROR: refusing to run '$RESOLVED' — does not match */agy-delegate/*/scripts/install.sh" >&2 ;; \
esac
```

**Current (pre-sync) content, `agy-uninstall.md`** (fenced hazard block at lines 27-37, verified this session): byte-identical shape, `install.sh`→`uninstall.sh` substitution only.

**Post-D-05-sync content (branch-tip, verified via `git show` this session — this is the exact text D-05 copies in, and the block D-03 then patches):**
```bash
# Source: fix/agy-bridge-resilience:.claude/commands/agy-setup.md (branch tip)
RESOLVED="$(claude plugin list --json 2>/dev/null \
  | python3 -c 'import sys,json;[print(x.get("installPath","")) for x in json.load(sys.stdin) if x.get("id","").startswith("agy-delegate@")]' \
  | head -1)/scripts/install.sh"; \
case "$RESOLVED" in \
  */agy-delegate/*/scripts/install.sh) [[ -f "$RESOLVED" ]] \
    && bash "$RESOLVED" \
    || echo "ERROR: resolved installer '$RESOLVED' is not a regular file — is agy-delegate installed?" >&2 ;; \
  *) echo "ERROR: refusing to run '$RESOLVED' — does not match */agy-delegate/*/scripts/install.sh" >&2 ;; \
esac
```
(Same `| head -1` hazard survives the sync — confirmed via `git diff HEAD fix/agy-bridge-resilience` this session. D-05 must land first; D-03 patches this post-sync text, not the pre-sync text above.)

**D-03 analog for the python3 rewrite:** `scripts/install.sh`'s own `python3 -c`/`python3 -` JSON idioms — same stdlib `json` pattern, same project convention:
```python
# Source: scripts/install.sh:265-273 (_agy_detect, current) — the project's established
# "python3 -c / python3 - <<'PY' reading stdin/argv, printing exactly what's needed" idiom
import sys, json, os
p = sys.argv[1]; lc = ts = False
if os.path.exists(p):
    try:
        s = json.load(open(p)).get('mcpServers', {})
        lc = 'lean-ctx' in s; ts = 'tokensave' in s
    except Exception:
        pass
print(f"{int(lc)} {int(ts)}")
```

**D-03's required rewrite shape** (locked outcome, discretionary mechanism per CONTEXT.md): eliminate ` | head -1` from the pipeline; make the `python3 -c '...'` one-liner itself print only the first `installPath` match — e.g. index `[0]` of the filtered list (guard the empty-list case to still print nothing, not raise `IndexError`), an early `break`, or a `next(..., "")`-style expression. Must produce byte-identical stdout to the current `| head -1` behavior on a single-match input, and empty stdout (not a traceback) on zero matches. Apply identically to both `.md` files (mirrors Phase 3 D-01's "fix both, not just the one literally ticketed").

---

### `.claude-plugin/plugin.json` — D-05 (version sync)

**Analog:** `fix/agy-bridge-resilience:.claude-plugin/plugin.json` (branch tip, verified via `git show` this session) — single-field diff, `"version": "1.6.1"` → `"1.6.2"`; every other field is already identical between `master` and the branch tip. No design decision, pure content sync.

---

### `tests/run-tests.sh` — new regression cases

All three new cases live in the same file and reuse its own established harness — no new fixture files, no new test framework.

**Shared isolation harness (verified this session, unchanged by this phase):**
```bash
# Source: tests/run-tests.sh:3669-3684
_fresh_home() {
    local h; h="$(mktemp -d "$SANDBOX/ihome.XXXXXX")"
    mkdir -p "$h/.local/bin" "$h/bin"
    cp "$HERE/fake-agy.sh" "$h/bin/agy"
    chmod +x "$h/bin/agy"
    _cc_fixtures_beside "$h/bin"
    printf '%s' "$h"
}

_install_in() {
    local h="$1"; shift
    env -i HOME="$h" PATH="$h/bin:$h/.local/bin:/usr/bin:/bin" \
        AGY_PLUGIN_DIR="$ROOT" "$@" \
        bash "$INSTALL" > "$SANDBOX/last-install.log" 2>&1
}
```

**D-01's case — compose these two existing cases (both read in full this session):**

`I8b` (`tests/run-tests.sh:3810-3825`) — real recursive alias + flag set:
```bash
IH="$(_fresh_home)"
mkdir -p "$IH/otherbin"
printf '#!/bin/sh\necho real\n' > "$IH/otherbin/gemini"; chmod +x "$IH/otherbin/gemini"
printf "%s\n" "alias gemini='GEMINI_API_KEY=x gemini'" > "$IH/.bashrc"
env -i HOME="$IH" PATH="$IH/bin:$IH/otherbin:$IH/.local/bin:/usr/bin:/bin" \
    AGY_PLUGIN_DIR="$ROOT" AGY_SETUP_PATCH_ALIASES=1 \
    bash "$INSTALL" > "$SANDBOX/last-install.log" 2>&1
```

`I10` (`tests/run-tests.sh:3862-3881`) — `nopy`-style python3-absent `PATH` (whitelist recipe, not a blocklist):
```bash
IH="$(_fresh_home)"
mkdir -p "$IH/.gemini/antigravity-cli" "$IH/nopy"
for b in bash cat grep sed date mktemp mkdir rm mv cp chmod ls readlink id printf command env; do
    _src="$(command -v "$b" 2>/dev/null)"; [[ -n "$_src" ]] && ln -sf "$_src" "$IH/nopy/$b" 2>/dev/null || true
done
cp "$HERE/fake-agy.sh" "$IH/nopy/agy"; chmod +x "$IH/nopy/agy"
_cc_fixtures_beside "$IH/nopy"
env -i HOME="$IH" PATH="$IH/nopy" AGY_PLUGIN_DIR="$ROOT" \
    AGY_SETUP_REGISTER_TOKENSAVE=1 \
    bash "$INSTALL" > "$SANDBOX/last-install.log" 2>&1; I10_RC=$?
if [[ "$I10_RC" -eq 0 && -f "$IH/.local/bin/agy-bridge" ]] \
   && ! grep -q '"tokensave"' "$IH/.gemini/antigravity-cli/mcp_config.json" \
   && grep -qi 'python3 not found' "$SANDBOX/last-install.log"; then
```
New D-01 case: `I8b`'s setup (real `gemini` + matching `.bashrc` alias + `AGY_SETUP_PATCH_ALIASES=1`) run against `I10`'s `$IH/nopy` `PATH`. Assert: exit 0, both wrappers exist, a `WARNING:` naming the alias-patch feature on stderr, and `$IH/.bashrc` byte-identical pre/post (`cksum`, same no-op-detection idiom `I8` already uses at `tests/run-tests.sh:3794-3803`).

**D-06's case(s) — same shape as the existing root-refusal cases, swap the trigger:**

`I6` (`tests/run-tests.sh:3759-3770`, install.sh) and `I6b` (`:3771-3778`, uninstall.sh) are the precedent for "same behavior, two scripts, two IDs" per CONTEXT.md's discretion note:
```bash
# I6: refuse-root via SUDO_USER.
IH="$(_fresh_home)"
env -i HOME="$IH" PATH="$IH/bin:$IH/.local/bin:/usr/bin:/bin" \
    AGY_PLUGIN_DIR="$ROOT" SUDO_USER="someone" \
    bash "$INSTALL" > "$SANDBOX/last-install.log" 2>&1; I6_RC=$?
if [[ "$I6_RC" -ne 0 ]] && grep -qi 'root' "$SANDBOX/last-install.log" \
   && [[ ! -e "$IH/.local/bin/agy-bridge" ]]; then
```
New D-06 case(s): same `env -i` shape but **omit `HOME=` entirely** (distinct from every existing case, which always sets `HOME="$IH"`) — `env -i PATH=<curated dir> bash "$INSTALL"` / `bash "$UNINSTALL"`. Assert stderr contains the exact D-06 message, stdout/stderr never contains `unbound variable`, `rc=1`.

**D-04's extractor + case — reuse the marker-extraction + extract-then-exec-under-fake-stub technique:**

`_rb_extract` (`tests/run-tests.sh:1675-1677`) — content-anchored, not line-number-anchored, block extraction:
```bash
_rb_extract() {
    sed -n '/^# --- BEGIN run_bounded ---$/,/^# --- END run_bounded ---$/p' "$1"
}
```
The `.md` files carry no `BEGIN`/`END` sentinel comments (user-facing docs, not scripts) — D-04's extractor must anchor on the block's own first/last line content instead, e.g. `/^RESOLVED="\$(claude plugin list/,/^esac$/` (both ends content-anchored, same "anchored at both ends" discipline `_rb_extract` uses, since each `.md` file has six fenced bash blocks post-sync and only one is the hazard block).

RB21 usage pattern (`tests/run-tests.sh:1874-1897`) — extract a block, then run it under `bash -c` with an env var/fake stub override supplied only in the test driver, never in the shipped block:
```bash
_RB_BLOCK="$SANDBOX/run_bounded.block.sh"
_rb_extract "$SHIM" > "$_RB_BLOCK"
...
bash -c '
    set -euo pipefail
    exec 9>"$2"
    TIMEOUT_BIN=""
    . "$1"
    ...
' _ "$_RB_BLOCK" "$_RB21A_FD9"; RB21A_RC=$?
```
D-04's case differs in one respect: the extracted `.md` block is a full standalone script (assignment + `case` statement), not a function to `source` — so the runner is `bash -euo pipefail -c "$(cat "$_BLOCK")"` with a fake `claude` on `PATH`, not a `. "$1"` source-then-call. The inline-fake-stub convention to reuse for `claude` (Claude's Discretion, per CONTEXT.md — matches every other one-off CLI fake in this suite, e.g. `tokensave` at `I9`/`I9b`/`I10`):
```bash
# Source: tests/run-tests.sh:3900 (I9b) — the suite's established inline-fake idiom
printf '#!/bin/sh\nexit 0\n' > "$IH/bin/tokensave"; chmod +x "$IH/bin/tokensave"
```
The fake `claude` must emit a JSON array with **two or more** `agy-delegate@...`-prefixed `id` entries — the exact multi-match shape that triggered the old SIGPIPE. Assert the extracted block does not exit 141 and reaches its `case` statement (either the `bash "$RESOLVED"` arm or one of the two `echo "ERROR: ..."` arms counts as "reached, did not abort").

## Shared Patterns

### Fail-open on a missing optional dependency
**Source:** `scripts/install.sh:279-283` (`_register_tokensave`), also `:260-264` (`_agy_detect`)
**Apply to:** D-01's new python3 guard — same file, same shape, same "print one `WARNING: ...` line naming the feature, `return`/skip, leave everything already-written intact" contract.

### Explicit precondition check before a `set -u` expansion, not a silent fallback
**Source:** `scripts/install.sh:37-40` / `scripts/uninstall.sh:15-18` (existing refuse-root checks)
**Apply to:** D-06's HOME precondition in both files — same `[[ ... ]] || { echo "ERROR: ..." >&2; exit 1; }` shape, sited immediately after refuse-root.
**Do NOT apply:** the generated wrapper's `"${HOME:-/nonexistent}"` fallback (`install.sh`'s `write_wrapper` heredoc, internal to the *generated* file, not `install.sh` itself) — D-06 explicitly forbids this shape for `install.sh`/`uninstall.sh` themselves.

### Fix a SIGPIPE-hazard class at its source
**Source:** Phase 2 D-08 precedent (cited in RESEARCH.md; not re-quoted here — no code in this repo to excerpt since it's a prior-phase decision record, not a file)
**Apply to:** D-03 — remove `| head -1` from both `.md` files' fallback one-liners by making the python3 producer stop after its first match, rather than appending `|| true`.

### Content-anchored (not line-number-anchored) block extraction for tests
**Source:** `tests/run-tests.sh:1675-1677` (`_rb_extract`)
**Apply to:** D-04's new `.md`-block extractor — anchor on the block's own first/last line text, not a fenced-block index, because line numbers in this codebase are proven to drift (see Common Pitfalls in RESEARCH.md).

### `env -i` + curated `PATH` isolation harness
**Source:** `tests/run-tests.sh:3669-3684` (`_fresh_home`, `_install_in`)
**Apply to:** all three new test cases (D-01, D-06, D-04) — every existing `I*` case in this suite already uses this harness; no new isolation mechanism should be invented.

## No Analog Found

None. Every file this phase touches has an exact or role-match analog already in the same file or its immediate sibling (`install.sh` ↔ `uninstall.sh`, `agy-setup.md` ↔ `agy-uninstall.md`), confirming RESEARCH.md's own finding: "every problem this phase touches already has an established, working pattern somewhere else in this same file."

## Metadata

**Analog search scope:** `scripts/install.sh`, `scripts/uninstall.sh`, `.claude/commands/agy-setup.md`, `.claude/commands/agy-uninstall.md`, `.claude-plugin/plugin.json`, `tests/run-tests.sh` (targeted ranges: 1-101, 1660-1920, 3660-4030, 4900-4924), plus `fix/agy-bridge-resilience` branch-tip versions of the three D-05 sync targets (via `git show`).
**Files scanned:** 6 modified files + 1 branch-tip comparison set (3 files) — all read directly this session, no re-reads of overlapping ranges.
**Pattern extraction date:** 2026-08-21
