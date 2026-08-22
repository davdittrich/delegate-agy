---
phase: 04-installer-and-launcher-surface
reviewed: 2026-08-21T13:23:42Z
depth: deep
files_reviewed: 6
files_reviewed_list:
  - .claude-plugin/plugin.json
  - .claude/commands/agy-setup.md
  - .claude/commands/agy-uninstall.md
  - scripts/install.sh
  - scripts/uninstall.sh
  - tests/run-tests.sh
findings:
  critical: 2
  warning: 2
  info: 1
  total: 5
status: issues_found
---

# Phase 04: Code Review Report

**Reviewed:** 2026-08-21T13:23:42Z
**Depth:** deep
**Files Reviewed:** 6
**Status:** issues_found

## Summary

Reviewed the installer/uninstaller pair, the two command docs that hand the
user copy-paste one-liners, `plugin.json`'s version bump, and the regression
suite that pins all of it down (I19/I20/I20b/I21/I21b). To go beyond static
reading, I extracted the exact I19/I20/I20b/I21/I21b logic into a standalone
harness and ran it against the real `scripts/install.sh` / `scripts/uninstall.sh`
/ doc files — all six pass as claimed (see command output in this review's
supporting work). That confirms the two specific mechanisms this phase set
out to fix (the HOME-unset precondition, and the hoisted python3 guard around
the rc-alias loop) do what the plan says.

The deep pass surfaced two things the stated scope didn't cover, both in the
**CLI-fallback one-liner** shared by `agy-setup.md` and `agy-uninstall.md`
(the block this phase touched to fix the SIGPIPE hazard):

1. **A real, empirically-reproduced arbitrary-code-execution gap** (CR-01/
   CR-02): the fallback block resolves and `bash`-execs the **first**
   `claude plugin list --json` entry whose `id` merely starts with
   `agy-delegate@`, with no chance for the user to review the path before it
   runs. A lookalike plugin installed from a different (e.g. attacker- or
   compromised-) marketplace, if listed first, gets executed. I proved this
   by feeding the extracted block a two-entry payload with the evil entry
   first — it printed `EVIL_RAN`. This is the *exact* attack class the same
   codebase already hardened the wrapper itself against (see `write_wrapper`'s
   exact-key `reg_key`/`reg_key_re` derivation and the `I16` "(e)" lookalike-
   marketplace test/comment) — that hardening was never carried over to the
   doc's fallback mechanism, and the doc's own prose overclaims what the
   "validation" actually checks.

2. **A confirmed false-positive warning** (WR-01) in the just-added python3
   guard: it prints "python3 not found — skipping the recursive-gemini rc
   alias patch" even when there is nothing to skip (no `.bashrc`/`.zshrc`/
   `.bash_aliases` contains a recursive alias at all). Reproduced with a
   from-scratch HOME containing no rc files.

Also flagged: a doc regression (WR-02) where this phase's rewrite introduced
`<that-path>` bracket-placeholder syntax under a "copy-paste this" heading —
`<` and `>` are shell redirection metacharacters, and a literal paste fails
immediately (confirmed: `bash: line 1: that-path: No such file or directory`)
rather than doing what the heading promises.

## Critical Issues

### CR-01: agy-setup.md's CLI-fallback one-liner executes the first `agy-delegate@*` match with no review — lookalike-marketplace plugin gets bash-executed

**File:** `.claude/commands/agy-setup.md:53-60`
**Issue:**

```bash
RESOLVED="$(claude plugin list --json 2>/dev/null \
  | python3 -c 'import sys,json;print(next((x.get("installPath","") for x in json.load(sys.stdin) if x.get("id","").startswith("agy-delegate@")), ""))')/scripts/install.sh"; \
case "$RESOLVED" in \
  */agy-delegate/*/scripts/install.sh) [[ -f "$RESOLVED" ]] \
    && bash "$RESOLVED" \
    || echo "ERROR: resolved installer '$RESOLVED' is not a regular file — is agy-delegate installed?" >&2 ;; \
  *) echo "ERROR: refusing to run '$RESOLVED' — does not match */agy-delegate/*/scripts/install.sh" >&2 ;; \
esac
```

`x.get("id","").startswith("agy-delegate@")` matches *any* marketplace, and
`next(...)` takes whichever such entry appears **first** in
`claude plugin list --json`'s output — there is no check that it's the
marketplace the user actually intended. The subsequent `case` glob
(`*/agy-delegate/*/scripts/install.sh`) only checks path *shape*, not which
marketplace segment sits in the middle of it, so it does not catch this
either. The whole block resolves **and executes** in one paste with no pause
for the user to look at the path — unlike the primary `grep`/`sed` flow above
it in the same doc, which explicitly separates "print the path" from "check
it looks right, then run" into two steps.

I reproduced this end-to-end: extracted the exact block from the doc, fed it
a `claude plugin list --json` stub returning
`[{"id":"agy-delegate@evil-marketplace","installPath":".../evil/1.0.0"},{"id":"agy-delegate@real-marketplace","installPath":".../real/9.9.9"}]`
(evil listed first, evil's `install.sh` prints `EVIL_RAN`, real's prints
`LEGIT_RAN`), and ran it unmodified:

```
=== running with evil-first payload ===
EVIL_RAN
rc=0
```

This is the identical threat class the same phase's/codebase's own tests
document and defend against elsewhere: `write_wrapper`'s `reg_key`/`reg_key_re`
derivation in `scripts/install.sh` (and the `tests/run-tests.sh` "(e)"
lookalike-marketplace case, comment: *"A prefix match on '"agy-delegate@'
would fire on this and hand the user an attacker-chosen path; the exact-key
match must ignore it."*) — but that fix was never applied to this doc's
fallback mechanism, which still uses exactly the vulnerable prefix match, and
still hands the resolved (possibly attacker-chosen) path straight to `bash`.

The doc's own framing overclaims what's happening here: *"this form validates
the resolved string before executing it, because it comes from command output
rather than your own eyes"* — the validation is shape-only, not identity, and
provides zero protection against this scenario.

**Fix:** Stop resolving-and-executing in one paste. Split the fallback block
the same way the primary flow above it already is: print `$RESOLVED` and
`case`-validate it, but do **not** `bash` it in the same step — require a
second, explicit `bash "$RESOLVED"` line the user runs after reading the
printed path, mirroring "Check it looks right, then run" for the primary
`grep`/`sed` tool. As a secondary hardening, if you want automated identity
checking rather than relying purely on eyeballing, print (don't silently
discard) every `id` that matches the `agy-delegate@` prefix when there's more
than one, instead of picking `next()`'s first match silently.

### CR-02: agy-uninstall.md has the identical unreviewed-exec gap

**File:** `.claude/commands/agy-uninstall.md:45-52`
**Issue:** Same code, same defect, same proof as CR-01 (verified by re-running
the extraction against this file with `uninstall.sh` in place of `install.sh`
— identical `EVIL_RAN` result). Per this phase's own precedent (D-03 in
`tests/run-tests.sh`: "fix both, not just the one literally ticketed" — the
reason I21b exists as a sibling of I21), this needs the same fix as CR-01
applied here too, not just in `agy-setup.md`.
**Fix:** Same as CR-01, applied to this file's fallback block.

## Warnings

### WR-01: python3-absent rc-alias guard warns even when there is nothing to patch

**File:** `scripts/install.sh:228-234`
**Issue:**

```bash
if [[ -n "$_real_gemini" ]]; then
    _alias_patch_py3_ok=1
    if [[ "${AGY_SETUP_PATCH_ALIASES:-0}" == "1" ]] && ! command -v python3 >/dev/null 2>&1; then
        _alias_patch_py3_ok=0
        echo "WARNING: python3 not found — skipping the recursive-gemini rc alias patch (fail-open)." >&2
    fi
    for RC in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_aliases"; do
```

The guard fires as soon as `_real_gemini` is set, `AGY_SETUP_PATCH_ALIASES=1`,
and `python3` is missing — **before** the loop has checked whether any of the
three rc files actually contain a recursive `alias gemini=`. If none do,
there was never anything to patch, yet the user still sees "skipping the
recursive-gemini rc alias patch," implying a real action was skipped.
Reproduced: fresh `HOME` with no `.bashrc`/`.zshrc`/`.bash_aliases` at all,
`AGY_SETUP_PATCH_ALIASES=1`, no `python3` on `PATH` →

```
rc=0
WARNING: python3 not found — skipping the recursive-gemini rc alias patch (fail-open).
```

printed despite there being nothing to skip. This is a false-positive, not a
correctness bug in what the script *does* (it still correctly does nothing to
rc files and completes normally) — but it can mislead a user into thinking
their setup needs attention when it doesn't.
**Fix:** Only warn once an rc file with an actual recursive alias has been
found, e.g. track a `_found_alias=0` flag set inside the loop's existing
`grep -qE ... alias gemini=` branch, and emit the python3 warning there
(still just once, on first match) instead of unconditionally before the loop:

```bash
_alias_patch_py3_warned=0
for RC in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_aliases"; do
    [[ -f "$RC" ]] || continue
    if grep -qE "^alias gemini='[^']* gemini'\$" "$RC" 2>/dev/null; then
        ...
        if [[ "${AGY_SETUP_PATCH_ALIASES:-0}" == "1" ]] && ! command -v python3 >/dev/null 2>&1; then
            [[ "$_alias_patch_py3_warned" -eq 1 ]] || \
                echo "WARNING: python3 not found — skipping the recursive-gemini rc alias patch (fail-open)." >&2
            _alias_patch_py3_warned=1
            continue
        fi
        ...
    fi
done
```

### WR-02: `<that-path>` bracket placeholders under a "copy-paste this" heading fail on literal paste (new in this phase's rewrite)

**File:** `.claude/commands/agy-setup.md:45` (also 71, 78, 93); `.claude/commands/agy-uninstall.md:34` (also 60)
**Issue:** The old text (pre-phase) used a real, safe bash expression
(`bash "$RESOLVED"`) for every command in this section. This phase's rewrite
replaced it with a literal-looking placeholder, `<that-path>`, presented
under headings literally titled "Install (copy-paste this)" /
"Uninstall (copy-paste this)". `<` and `>` are shell redirection
metacharacters; pasted verbatim, `bash <that-path>/scripts/install.sh` is not
"run install.sh with a bad argument," it's "redirect stdin from a file named
`that-path`," which fails before bash ever looks at `/scripts/install.sh`.
Confirmed:

```
$ bash -x -c 'bash <that-path>/scripts/install.sh'
+ bash
bash: line 1: that-path: No such file or directory
```

The failure is loud and non-destructive (it never reaches the `>` half of
the token), so this isn't a safety issue — but it directly contradicts the
"copy-paste this" framing for a section that, unlike the `grep`/`sed` command
above it, is **not** meant to be copied verbatim.
**Fix:** Either (a) make the second command self-contained by capturing the
path into a real shell variable in the first step (e.g.
`AGY_PATH="$(grep -A6 ... | ...)"` then `bash "$AGY_PATH/scripts/install.sh"`),
so both commands genuinely are copy-paste-able as written, or (b) explicitly
tell the reader to replace `<that-path>` (angle brackets included) rather than
implying the whole block is paste-ready.

## Info

### IN-01: fallback block's `json.load` has no exception handling for a non-JSON `claude plugin list --json` reply

**File:** `.claude/commands/agy-setup.md:54`; `.claude/commands/agy-uninstall.md:46`
**Issue:** The `next(..., "")` default correctly handles "valid JSON, zero
matches" (this phase's own Test 4 covers exactly that). It does not cover
"`claude plugin list --json` produced empty/invalid output" (e.g. `claude`
itself failing) — `json.load(sys.stdin)` raises `JSONDecodeError` in that
case. Reproduced: with a `claude` stub producing no output, the block still
falls through to the correct `ERROR: refusing to run` message when run as a
bare paste (no `set -e`) — but under `set -euo pipefail` (exactly how this
phase's own test harness invokes the block) the whole statement aborts with
a raw Python traceback and `rc=1`, never reaching the friendly error branch.
Low real-world impact for an interactive paste (interactive shells don't run
under `set -e` by default), but worth closing given how cheap it is.
**Fix:** Wrap the load in a try/except returning the same empty-string
default, e.g. `json.load(sys.stdin) if True else None` → replace with
`(lambda: (json.load(sys.stdin)))()` guarded, or simplest: catch broadly —
`import sys,json\ntry:\n  d=json.load(sys.stdin)\nexcept Exception:\n  d=[]\nprint(next((x.get("installPath","") for x in d if x.get("id","").startswith("agy-delegate@")), ""))`
(as a `-c` one-liner, keep it on as few lines as the current inline form
allows).

---

_Reviewed: 2026-08-21T13:23:42Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
