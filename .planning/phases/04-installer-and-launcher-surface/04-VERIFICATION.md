---
phase: 04-installer-and-launcher-surface
verified: 2026-08-21T17:00:00Z
status: passed
score: 10/10 must-haves verified
behavior_unverified: 0
overrides_applied: 0
re_verification: No — initial verification
---

# Phase 4: Installer and Launcher Surface Verification Report

**Phase Goal:** The registry read stays a version comparison and contributes nothing else, and no install path can abort after the wrappers are written.
**Verified:** 2026-08-21
**Status:** passed
**Re-verification:** No — initial verification

This phase shipped as three plans: `04-01-PLAN.md` and `04-02-PLAN.md` (original scope), plus `04-03-PLAN.md` — a `gap_closure: true` plan added after a deep code review (`04-REVIEW.md`) of the shipped 04-01/04-02 work found a real, reproduced arbitrary-code-execution gap (CR-01/CR-02) and two warning-severity defects (WR-01, WR-02) in the same file surface. All three plans' `must_haves` and the roadmap's five success criteria were checked against the current file contents (not SUMMARY.md claims), and the full suite was executed directly by this verification, not taken on the executors' word.

## Goal Achievement

### Observable Truths

Truths 1-5 are the ROADMAP's five stated success criteria (the contract). Truths 6-9 are the 04-REVIEW.md findings that 04-03 closed — per this verification's brief, "just as binding as the first two [plans]." Truth 10 is the formal R8/S2 requirements-closure this phase's ROADMAP entry names as its evidence obligation.

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | (SC1) A lookalike plugin from another marketplace never matches this plugin's registry key, and an adjacent entry's version is never misattributed | ✓ VERIFIED | `scripts/install.sh:106-115` derives `reg_key="${parent_dir##*/}@${marketplace_dir##*/}"` (exact key, not a prefix match) and BRE-escapes it before use as a `sed` address; unchanged across the whole phase's diff (`git diff 110284a~1..3760368 -- scripts/install.sh` shows only the HOME precondition and the rc-alias python3-guard hunks). `tests/run-tests.sh` case `I16` "(e)" fixtures a `agy-delegate@evil-marketplace` entry claiming version `9.9.9` and asserts the wrapper's stderr never contains `9.9.9` and its rc matches the no-registry case; `I17` fixtures a neighbouring-plugin-adjacent registry shape. Full suite run: `ok - I16 ...`, `ok - I17 ...`, `PASS=160 FAIL=0`. |
| 2 | (SC2) An absent, truncated, or reshaped registry makes the launcher run silently rather than refuse | ✓ VERIFIED | `scripts/install.sh:158` guards the whole comparison on `[[ -r "$_AGY_REGISTRY" ]]`, and the `sed` pipeline ends in `\|\| true` under the wrapper's own `set -euo pipefail` (line 160). `I16` cases (a)-(d) (no registry, matching pin, stale pin, unparseable JSON) and `I17`'s empty-array/compact/semi-compact shapes all degrade to silence or the correct stale-pin path with no crash. `ok - I16`, `ok - I17` in the executed suite. |
| 3 | (SC3) The repin command is assembled from install-time literals plus a version matched against `^[0-9]+(\.[0-9]+)*$`; no registry-supplied string is ever printed as a command; the exec target stays the install-time literal | ✓ VERIFIED | `scripts/install.sh:168-173`: the repin line is only printed if `"$_agy_active" =~ ^[0-9]+(\.[0-9]+)*$` AND the install-time `$_AGY_VERSIONS_ROOT/$_agy_active/scripts/install.sh` exists — the message is built from `$_AGY_VERSIONS_ROOT` (an install-time literal) plus the version-validated string, never from a registry-supplied path. `exec -a "$name" bash "$_AGY_TARGET" "$@"` (line 177) uses `$_AGY_TARGET`, set once at install time (line 132), never reassigned from the registry read. `I16` asserts the sentinel `installPath` from a hostile registry entry never appears in the repin message. |
| 4 | (SC4) `AGY_SETUP_PATCH_ALIASES=1` on a host with no `python3` ends in the same graceful state as every other python3-absent path, rather than hard-failing after the wrappers already exist | ✓ VERIFIED | `scripts/install.sh:241-247`: `_alias_patch_py3_ok`/`_alias_patch_py3_warned` guard skips the `cp -f` backup and the `python3 -` heredoc, warning once, when `AGY_SETUP_PATCH_ALIASES=1` and no `python3`. Case `I19` (nopy curated PATH, real recursive alias, flag set) asserts `install.sh` exits 0 with both wrappers written, exactly one warning naming the alias patch, and the rc file byte-identical with no backup. Executed suite: `ok - I19 python3-absent rc-alias patch fails open: ...`. |
| 5 | (SC5) The documented CLI-fallback one-liner (both `/agy-setup` and `/agy-uninstall` docs) reaches its validating `case` under `set -euo pipefail` instead of aborting when its truncating consumer closes the pipe early | ✓ VERIFIED | Both docs' `python3 -c` expression now selects at most one `installPath` in-producer (`next((...), "")`, `.claude/commands/agy-setup.md:55-61`, `agy-uninstall.md:47-52`) — no `\| head -1` truncating stage exists in either extracted block (`sed -n '/^RESOLVED=.../,/^esac$/p' <file> \| grep -c head` == 0, re-confirmed by direct read). `I21`/`I21b` Test A/B/C/D drive the block under `bash -euo pipefail -c` against an oversized (>131072-byte) multi-match reply and assert rc 0 and no abort. Executed suite: `ok - I21`, `ok - I21b`. |
| 6 | (04-REVIEW CR-01/CR-02) Neither fallback block executes anything by itself; a separate, explicit `bash "$RESOLVED"` line — outside the validating block — is what runs the installer/uninstaller | ✓ VERIFIED | Direct read of both docs: `case`'s success arm now reads `[[ -f "$RESOLVED" ]] && echo "Resolved: $RESOLVED" \|\| echo "ERROR: ..."` (`agy-setup.md:63-66`, `agy-uninstall.md:54-58`) — it prints, never execs. A separate fenced block below (`agy-setup.md:72-74`, `agy-uninstall.md:63-65`) reads `bash "$RESOLVED"` with "Check the printed `Resolved: ...` path looks right, then run:" prose above it. `_md_fallback_case`'s Test A (`tests/run-tests.sh:4123-4136`) feeds a hostile lookalike-first reply and asserts the resolve/validate range alone never prints `TOKEN_` output; Test B (`:4138-4166`) extracts the doc's own second line via exact whole-line `grep -x` (not a substring match, which would collide with a legitimate untouched "e.g." prose mention) and runs it, confirming it actually execs. Executed suite: `ok - I21`, `ok - I21b`. |
| 7 | (04-REVIEW IN-01) A `claude plugin list --json` reply that is empty or invalid JSON degrades to the same `ERROR: refusing to resolve ...` arm as a zero-match reply, with no Python traceback, even under `set -euo pipefail` | ✓ VERIFIED | Both docs' `python3 -c` expression wraps `json.load(sys.stdin)` in `try/except Exception: d = []` (`agy-setup.md:56-60`, `agy-uninstall.md:48-51`). `_md_fallback_case`'s Test D2 (`tests/run-tests.sh:4192-4203`) feeds an empty payload and asserts rc 0, an `ERROR:` arm reached, and no `Traceback`/`JSONDecodeError`/etc. in the output. Executed suite: `ok - I21`, `ok - I21b`. |
| 8 | (04-REVIEW WR-01) The python3-absent rc-alias-patch warning fires only when at least one rc file actually contains a recursive `alias gemini=` entry — never on a fresh HOME with no rc files, or rc files with no such alias | ✓ VERIFIED | `scripts/install.sh:228-247`: the `command -v python3` check moved from unconditional-before-the-loop to inside the loop's own `if grep -qE "^alias gemini=..." "$RC"` match branch (line 233), confirmed by line-number ordering: the check (line 241) sits strictly between the match `if` (233) and the `cp -f` backup (248). Case `I19b` (`tests/run-tests.sh:3903-3920`, fresh HOME, no rc files, python3 absent, flag set) asserts rc 0, both wrappers written, and zero `python3 not found` lines. `I19` (the positive case, real alias present) still asserts exactly one warning. Executed suite: `ok - I19`, `ok - I19b`. |
| 9 | (04-REVIEW WR-02) Neither doc contains the literal placeholder token `<that-path>` as a `bash` argument; every command a reader is told to paste is genuinely paste-able using a real captured shell variable | ✓ VERIFIED | `grep -c '<that-path>' .claude/commands/agy-setup.md .claude/commands/agy-uninstall.md` == 0 in both files (re-run directly, no matches). Both docs' step 1 now captures `AGY_PATH="$(grep -A6 ... \| sed -n ... \| head -1)"` and every subsequent command (`Install`, both opt-in variants, `Uninstall`) reads `bash "$AGY_PATH/scripts/..."`. Case `I22` (`tests/run-tests.sh:4258-4274`) asserts, per file, `<that-path>` count == 0, `AGY_PATH=` declared >= 1, and `bash "$AGY_PATH` used >= 1. Executed suite: `ok - I22`. |
| 10 | R8 and S2 are formally closed in `.planning/REQUIREMENTS.md`, citing `I16`/`I17`/`I18` by case id (not stale line ranges), with the registry-comparison logic explicitly stated and confirmed unchanged | ✓ VERIFIED | `.planning/REQUIREMENTS.md` R8 and S2 rows both read `met` and both carry the exact sentence "formally closed in Phase 4 using previously shipped I16/I17/I18 evidence; registry logic unchanged" (direct read, lines 87/90). No `tests/run-tests.sh` line-range citation appears in either row. The A2 Unicode-normalization residue sits in a separate risk-notes paragraph below the table (line 95), not inside either row. `git diff 110284a~1..f87b445 -- scripts/install.sh` shows the whole phase's diff to that file is exactly the HOME precondition + the rc-alias python3 guard — `write_wrapper`'s registry-comparison heredoc (lines 85-182) has zero added/removed lines across the entire phase. |

**Score:** 10/10 truths verified (0 present, behavior-unverified)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `scripts/install.sh` | HOME precondition after refuse-root; hoisted-then-relocated python3 guard around rc-alias loop; unmodified `write_wrapper` | ✓ VERIFIED | `:42` precondition (`[[ -n "${HOME:-}" ]] \|\| { echo "ERROR: HOME is not set..."; exit 1; }`), sited between refuse-root (`:37-40`) and the first `$HOME` expansion (`:59`). `:228-247` final (WR-01-corrected) guard structure. `write_wrapper` (`:78-183`) byte-identical to pre-phase. |
| `scripts/uninstall.sh` | Mirrored HOME precondition | ✓ VERIFIED | `:20`, identical shape, between refuse-root (`:15-18`) and `BIN_DIR="$HOME/.local/bin"` (`:21`) — the only line this phase's diff adds to the file. |
| `.claude/commands/agy-setup.md` | Two-step resolve/print/exec fallback; try/except JSON parse; `$AGY_PATH` capture, no `<that-path>` | ✓ VERIFIED | All four properties confirmed by direct read (lines 36-96). |
| `.claude/commands/agy-uninstall.md` | Same, targeting `uninstall.sh` | ✓ VERIFIED | Confirmed by direct read (lines 27-77), identical shape. |
| `.claude-plugin/plugin.json` | `version: 1.6.2` | ✓ VERIFIED | Line 3, `"version": "1.6.2"`. |
| `.planning/REQUIREMENTS.md` | R8/S2 rows `met`, case-id evidence, A2 residue outside the table | ✓ VERIFIED | Confirmed by direct read, lines 87/90/95. |
| `tests/run-tests.sh` | `_md_extract`, `_md_fallback_case` (Tests A-D), `_home_unset_case`; cases `I19`, `I19b`, `I20`, `I20b`, `I21`, `I21b`, `I22` | ✓ VERIFIED | All present (`grep -n` confirms each symbol and case id exactly once, at lines 3789, 4016, 4042, plus the case invocations); `I16`/`I17`/`I18` untouched (`git diff` shows zero added/removed lines touching those cases across the whole phase). |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| D-05's branch-tip sync (04-01 Task 1) | D-03's SIGPIPE fix (04-01 Task 2/3) | sync landed strictly first, in its own commit (`110284a`), before the fix commits | ✓ WIRED | Confirmed by commit order in `git log`; `git diff HEAD fix/agy-bridge-resilience -- .claude-plugin/plugin.json` is empty (byte-identical post-sync). |
| `_alias_patch_py3_ok`/`_alias_patch_py3_warned` | the loop's `cp -f`/`python3 -` calls | `continue` gated on the flag, sited after the dry-run advisory's own `continue` and before the backup | ✓ WIRED | `scripts/install.sh:247` (`[[ "$_alias_patch_py3_ok" -eq 1 ]] \|\| continue`) sits between the dry-run `continue` (`:239`) and `cp -f` (`:248`) — confirmed by direct line read, matching both 04-02's original ordering assertion and 04-03's WR-01 relocation. |
| The `case`'s success-arm print (`echo "Resolved: $RESOLVED"`) | the doc's own separate `bash "$RESOLVED"` line | the reader manually runs the second fenced block after reading the first's printed path | ✓ WIRED | Confirmed: exactly one whole-line `bash "$RESOLVED"` per file (`grep -xc`), distinct from the untouched "e.g." prose mention naming the same substring; `_md_fallback_case` Test B executes the extracted line text itself (not a test-invented stand-in) and confirms it resolves+execs the legitimate marker. |
| `AGY_PATH`/`RESOLVED` captured variables | every subsequent `bash "..."` command in both docs | direct shell-variable substitution, same session | ✓ WIRED | `grep -c 'bash "\$AGY_PATH'` >= 1 per file across the primary install/uninstall line and both opt-in variants; `I22` asserts this behaviorally. |
| REQUIREMENTS.md's R8/S2 evidence | `I16`/`I17`/`I18`'s actual case bodies | case-id citation, not line-range citation | ✓ WIRED | No `tests/run-tests.sh:NNNN` range appears in either row; `I19`/`I20`/`I20b` (inserted above `I16`-`I18`) confirm the ranges would have gone stale had they been cited. |

### Data-Flow Trace (Level 4)

Not applicable in the UI-rendering sense — this phase's "data" is shell script control flow and doc text, not a rendered view. The equivalent trace (registry string → comparison-only, never to `exec` or a printed command) is covered under Truth 1/3 and the `write_wrapper` heredoc inspection above; no registry-supplied value was found flowing to any exec site or printed re-run command.

### Behavioral Spot-Checks / Full Suite Execution

The full suite was executed directly by this verification (not taken from SUMMARY.md's reported figures):

```
$ bash tests/run-tests.sh
...
PASS=160 FAIL=0
```

All 160 cases report `ok`, zero `bad`/`FAIL -` lines. This matches 04-03-SUMMARY.md's claimed final figure (158 baseline + `I19b` + `I22`; `I21`/`I21b` redesigned in place, not net-new) — independently reproduced, not trusted.

Spot-checked individually in the raw log: `ST6` (version sync), `I6`/`I6b` (refuse-root, unaffected), `I8`/`I8b` (rc-alias dry-run/flag-set, unaffected), `I12` (one-liner path validation), `I16`/`I17`/`I18` (registry comparison, untouched), `I19`/`I19b`/`I20`/`I20b`/`I21`/`I21b`/`I22` (this phase's new/redesigned cases) — all `ok`.

### Probe Execution

No `scripts/*/tests/probe-*.sh` convention exists in this project; this phase's verification surface is the single `tests/run-tests.sh` harness, executed above. Step 7c: N/A — no separate probe scripts declared or found.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|--------------|--------|----------|
| R8 | 04-01, 04-02, 04-03 | Registry read is comparison-only | ✓ SATISFIED | `.planning/REQUIREMENTS.md` row: `met`, citing `I16`/`I17`/`I18` (criteria 1-3) plus 04-01's `I21`/`I21b` (criterion 5's docs-tier half); `write_wrapper`'s registry-comparison heredoc confirmed unmodified across the whole phase's diff. |
| S2 | 04-02 | Survive a Claude Code registry schema change | ✓ SATISFIED | `.planning/REQUIREMENTS.md` row: `met`, citing `I17` (bounded extraction window) and `I16`'s lookalike-adjacent fixture (no cross-plugin misattribution); A2 (Unicode normalization) residue recorded as an accepted safe-direction risk note, not a defect. |

No orphaned requirements: ROADMAP.md's Phase 4 entry declares `Requirements: R8, S2` and the Requirement Coverage table maps both exclusively to Phase 4 with no open tickets; the union of the three plans' frontmatter `requirements:` fields (`[R8]`, `[R8, S2]`, `[R8]`) covers exactly {R8, S2} with nothing left unmapped.

### Anti-Patterns Found

None. Scanned `scripts/install.sh`, `scripts/uninstall.sh`, both command docs, `.claude-plugin/plugin.json`, `.planning/REQUIREMENTS.md`, and the phase's new/changed regions of `tests/run-tests.sh` for `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/`PLACEHOLDER` and empty-implementation patterns. The only matches were false positives: `mktemp`'s own `XXXXXX` template placeholder (`install.sh:125`, `run-tests.sh:267`) and the variable name `I22_PLACEHOLDER_COUNT`, which is the test asserting the *absence* of the `<that-path>` placeholder — not a debt marker itself.

### Human Verification Required

None. Every truth in this phase is mechanically checkable (shell script control flow, doc text, and a deterministic bash/python test harness) and was independently exercised by running the full suite directly, not inferred from static presence.

### Gaps Summary

No gaps. All ten observable truths (the ROADMAP's five success criteria, the four `04-REVIEW.md` gap-closure findings CR-01/CR-02/WR-01/WR-02/IN-01, and the R8/S2 formal-closure obligation) are verified against current file content, not SUMMARY.md narrative. All seven beads this phase's plans claim to close (`delegate-agy-k0f`, `delegate-agy-4vy`, `delegate-agy-4bp`, `delegate-agy-4xn`, `delegate-agy-5r9.7`, `delegate-agy-5r9.8`, `delegate-agy-5r9.9`) are confirmed `CLOSED` via `bd show`. The full suite, executed directly by this verification, reports `PASS=160 FAIL=0` with zero failures — matching the phase's own stated target figure exactly.

**Minor, non-blocking observation:** the tracking epic `delegate-agy-5r9` ("Phase 4: Installer and launcher surface") itself remains `OPEN` in `bd show`, even though all seven of its constituent bug tickets are closed and `ROADMAP.md`'s Phase 4 checkbox is still `[ ]` (unchecked) with a Progress-table status of "In Progress" and no completion date, unlike Phases 1-3 which show `[x]` and a completion date. This is bookkeeping/process housekeeping, not a code-correctness gap — it does not affect any of the ten observable truths above, all of which are independently verified against the current codebase and a directly-executed test run. It is noted here because it would otherwise silently persist past this phase into the ship gate.

---

*Verified: 2026-08-21*
*Verifier: Claude (gsd-verifier)*
