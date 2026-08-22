# Phase 6: Ship 1.6.2 - Research

**Researched:** 2026-08-21
**Domain:** Closed bash CLI wrapper codebase — bug-fix / release-gate phase (no new frameworks, no new packages)
**Confidence:** HIGH for all code-location and mechanism findings (all read on `master` this session, exact line numbers cited); MEDIUM/LOW only for D-08's root cause (could not reproduce the flake live)

## Summary

This phase closes 8 open `bd` tickets and ships 1.6.2. Six of eight have their fix mechanism **locked verbatim in CONTEXT.md** (D-02 through D-07, D-09, D-10) — this research does not re-litigate those, it locates their exact code sites and, in two cases (D-06, D-07), surfaces a **real correctness problem with the locked mechanism's naive literal reading** that the planner must design around. D-08 (`delegate-agy-sup`, the `RB24` trap-preservation flake) is the one genuinely open technical question; I read `run_bounded`'s full implementation and `RB24`'s test, traced the exact code path, and attempted live reproduction (2 full `tests/run-tests.sh` runs + 80 isolated iterations — all green, flake did not reproduce). I could not observe the race directly; what follows is a grounded static-analysis hypothesis, tagged `[ASSUMED]`, not a verified root cause.

Two findings change what the planner should write into the plan, beyond what CONTEXT.md's ticket summaries suggest:

1. **D-06 (`delegate-agy-d4t`) is not a one-line loop-widen.** I ran `RB01`'s actual scan function (`_rb_agy_segments`/`_rb_agy_scan`, `tests/run-tests.sh:2298-2360`) against `tests/contract-check.sh` empirically. Result: **7 false-positive violations**, all from `[[ -z "$AGY_BIN" ]]` preflight guards (7 sites: lines 527, 565, 600, 644, 698, 829, 1008) that mention `$AGY_BIN` outside a `run_bounded` call. `RB01`'s own comment states this is "deliberate rather than an oversight" — mentioning the variable outside a bounded call is *always* a reported violation, by design, with "no allowlist, no skip list, no escape-hatch." Naively adding `"$CONTRACT_CHECK"` to the scan loop (`tests/run-tests.sh:2372`) will break the suite. The real fix must also touch `tests/contract-check.sh` itself (see Code Examples).

2. **D-07 (`delegate-agy-b7g`)'s two suggested fix shapes both have a hidden regression.** Naively exiting early inside the fetch block (the more obvious reading of "route through the degraded-message path") skips the unconditional `agy` stderr passthrough two lines later — the exact diagnostic the code's own comment calls "the only diagnostic when the real fault is auth or the network." The correct minimal patch defers the `exit` to the existing generic-bail site (`agy_bridge.sh:537`) and only changes *which message* prints there, via a one-line flag set inside the fetch block. Full patch given in Code Examples.

Both criterion-2 verification steps I was asked to check mechanically now have exact commands and expected output (Runtime State Inventory section is N/A — this is not a rename phase, see explicit note below).

**Primary recommendation:** Treat D-04/D-05/D-09/D-10 as CONTEXT.md already specifies — locate-and-patch. Treat D-06 and D-07 as two-file patches, not one-file patches, using the exact diffs below. Treat D-08 as "implement the reorder fix below, then add one *deterministic* forcing test" rather than "rerun RB24 N times and hope" — the observed flake rate is too low relative to my 82 clean attempts this session for reruns alone to prove a fix.

## Architectural Responsibility Map

This phase touches only the existing single-tier CLI-wrapper architecture; no new capability, no new tier.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Flag parsing / arg dispatch (D-04) | CLI script (`gemini_shim.sh`) | — | Pure argv handling, no I/O boundary |
| Duplicated write-gate structural guard (D-05) | Test harness (`tests/run-tests.sh`) | Shared code (`agy_bridge.sh`/`gemini_shim.sh`) | New assertion lives in the test file; the code under test is unchanged |
| Static unbounded-call scan (D-06) | Test harness (`tests/run-tests.sh`) | Test-side script (`tests/contract-check.sh`) | Scan logic in the harness; the scanned file's own guard clauses must be restructured to stay scan-clean |
| Degraded model-list message (D-07) | CLI script (`agy_bridge.sh`) | — | Diagnostic-message routing inside the existing fetch/cache block |
| `run_bounded` trap save/restore (D-08) | Shared helper, duplicated verbatim (`agy_bridge.sh`/`gemini_shim.sh`) | Test harness (`RB24`) | Fix in the shared helper block; new regression test in the harness |
| Release notes (D-09) | Docs (`README.md`) | — | No code |
| Fresh-install proof (D-10) | Installer (`scripts/install.sh`) — read-only this phase | Test harnesses (both suites) | Manual verification pass, no automated infra added |

## Package Legitimacy Audit

**Not applicable.** This phase installs no new external packages. It is a pure bash bug-fix release gate against an existing, already-audited dependency set (coreutils `timeout`, `python3` stdlib only, `agy` binary itself — all pre-existing, none touched by this phase's tickets). No `npm view` / `pip index` / `cargo search` calls are needed.

## Standard Stack

**Not applicable in the conventional sense.** This is a closed, dependency-free bash codebase (no package manifest, no CI, confirmed via `gh release list` returning empty and no `package.json`/`requirements.txt`/`Cargo.toml` in the repo). The "stack" for this phase is:

| Tool | Verified version (this session) | Role |
|------|-------|------|
| `bash` | (system default on this host) | All scripts, `set -euo pipefail` throughout |
| GNU coreutils `timeout` | `/usr/bin/timeout` present | `run_bounded`'s coreutils arm |
| `python3` | 3.14.7 `[VERIFIED: python3 --version, this session]` | JSON envelope construction (`json.dumps`) in `agy_bridge.sh` |
| `agy` (Google Antigravity CLI) | 1.1.17 on this dev host `[VERIFIED: agy --version, this session]` | The delegated binary itself |
| `gh` CLI | 2.98.0 `[VERIFIED: gh --version, this session]` | Used only for the criterion-2/`gh release list` check, not shipped |
| `bd` (beads) | 1.2.2 `[VERIFIED: bd --version, this session]` | Ticket tracking, not shipped |

Note: README's Troubleshooting/Configuration prose says "`--model` ... verified against `agy` 1.1.13 (2026-08-20)"; this dev host actually has `agy` 1.1.17. This is not a phase blocker (D-10's manual verification pass should note the live version it ran against, whatever it is) but the planner should be aware the README's specific version citation is already one version stale relative to at least this host.

## Architecture Patterns

### Recommended Project Structure
No new files. All 8 tickets touch a fixed, already-existing file set:
```
scripts/gemini_shim.sh    — D-04 (flag parsing), D-05 (twin site, no code change, test only)
scripts/agy_bridge.sh     — D-05 (twin site, no code change), D-07 (degraded-message routing), D-08 (run_bounded fix)
tests/run-tests.sh        — D-05 (new assertion), D-06 (scan-loop widen), D-08 (new/updated RB24 handling)
tests/contract-check.sh   — D-06 (guard-clause restructure so the widened scan stays clean)
README.md                 — D-09 (Changelog section)
scripts/install.sh        — D-10, read-only unless D-06/D-08 touch shared helpers it also sources (they don't)
```

### Pattern: "Fold review Minors into the running fix round"
**What:** This project's own standing convention (per `PROJECT.md` and `REQUIREMENTS.md`'s traceability notes) — a defect discovered as a side effect of one phase's work gets fixed in that phase's own fix round rather than filed-and-deferred.
**When to use:** D-06 and D-07 are both explicit instances of this — CONTEXT.md's D-06/D-07 entries both say "User's explicit choice — overrides 'defer'."
**Evidence:** `[VERIFIED: .planning/phases/06-ship-1-6-2/06-CONTEXT.md]` — D-06/D-07 decision text quoted verbatim below.

### Pattern: "Prove the check can fail before trusting it"
**What:** Every structural/statistical assertion in `tests/run-tests.sh` has a companion mutation test proving the assertion is capable of failing (not vacuously green). Examples read this session: `RB01` (the unbounded-call scan) has `RB01m` immediately after it (`tests/run-tests.sh:2399+`), which injects a decoy unbounded call into a copy of the script and asserts the scan *catches* it. `RB25`/`RB26` follow the same shape for the pgid-lookup blind spots.
**When to use:** Directly informs D-08's discretion question ("does the root-cause fix need a new regression case?"). Given this project's own established convention, a bare "fix `run_bounded`, rerun `RB24` N times" approach is inconsistent with how every other structural fix in this codebase was proven — and, per my own reproduction attempts (below), rerunning is weak evidence anyway.
**Example:** `[VERIFIED: tests/run-tests.sh:2399]` — `# RB01m: the scan is proven capable of failing before it is trusted.`

### Anti-Patterns to Avoid
- **Trusting a ticket's stated call-site count.** `REQUIREMENTS.md`'s own R11 traceability entry states the "every `$AGY_BIN` call site" count has "been wrong three times — two, four, now five." `delegate-agy-d4t`'s ticket text says "3" call sites in `tests/contract-check.sh`; my own `grep -n '"\$AGY_BIN"'` this session found **4** real invocation sites (lines 535, 548, 742, 1059) plus 7 non-invocation mention sites. Don't restate a headline count in the plan; assert the invariant (scan passes with zero violations), not a number.
- **Fixing D-06/D-07 by adding an allowlist/skip-list.** `RB01`'s own comment forbids this explicitly for D-06 ("no allowlist, no skip list, no escape-hatch comment... a site that genuinely cannot be bounded has to change this rule in the open"). The correct D-06 fix restructures `contract-check.sh`'s guard clauses, not `RB01`'s exclusion regex.
- **Exiting early inside `agy_bridge.sh`'s fetch `if/elif` block for D-07.** Skips the unconditional stderr passthrough two lines below the block that the code's own comment marks load-bearing.

## Don't Hand-Roll

Not applicable to this phase's problem domain — every fix is a small, local patch to existing hand-rolled bash (which is itself the codebase's deliberate choice; there is no library to reach for instead of, e.g., a positive-integer regex guard or a `grep -cF` structural-equality check — these patterns are this codebase's own established idiom, not something a dependency would replace).

## Common Pitfalls

### Pitfall 1: D-06's naive loop-widen breaks the suite
**What goes wrong:** Adding `"$CONTRACT_CHECK"` to `tests/run-tests.sh:2372`'s `for _rb01_f in "$BRIDGE" "$SHIM"; do` loop, alone, makes `RB01` fail immediately.
**Why it happens:** `contract-check.sh` has 7 `[[ -z "$AGY_BIN" ]]` preflight guards that textually mention `$AGY_BIN` outside a `run_bounded ... --` command. `RB01`'s scan (`_rb_agy_scan`, `tests/run-tests.sh:2357-2360`) counts *any* mention of `$AGY_BIN` outside the bounded-call regex as a violation — no exceptions, by design.
**How to avoid:** See Code Examples for the exact restructure (compute the "agy absent" boolean once into a variable that doesn't contain the literal substring `$AGY_BIN`, e.g. `_CC_NO_AGY`, and have all 7 guards test that instead).
**Warning signs:** `RB01`'s failure detail string reports `contract-check.sh:7_unbounded_of_11` (verified this session via direct invocation of the scan functions against the real file).

### Pitfall 2: D-07's obvious fix drops the stderr diagnostic
**What goes wrong:** Adding an `exit 2` with the specific message directly inside the fetch block's `if/elif` (right after `_agy_models=""` in the `elif [[ -s "$CACHE_FILE" ]]` arm's sibling `else`) skips the unconditional `[[ -n "$_agy_err" && -s "$_agy_err" ]] && sed 's/^/       agy: /' "$_agy_err" >&2` passthrough at `agy_bridge.sh:527-528`, which runs *after* the whole `if/elif` block, not inside it.
**Why it happens:** The passthrough was deliberately "relocated (not duplicated)" outside the if/elif (per the comment at that line) specifically so it fires on every path. An early `exit` inside the block bypasses that relocation's whole purpose.
**How to avoid:** Set a flag inside the block, exit at the existing single choke point (`agy_bridge.sh:537`) after the passthrough has already run. Exact patch in Code Examples.
**Warning signs:** A future test asserting "agy's stderr always appears before exit 2 on a degraded/empty list" (there isn't one today, but D-07's own diagnostic-specificity intent implies this should hold) would go red silently if this pitfall isn't avoided.

### Pitfall 3: assuming `run_bounded`'s coreutils arm can be part of D-08's race
**What goes wrong:** Spending investigation time looking for a trap-handling race inside the coreutils (`timeout -k`) arm.
**Why it happens:** CONTEXT.md's own D-08 framing says "a timing race in `run_bounded`'s trap save/restore around its two mechanisms," which reads as if both mechanisms touch traps.
**How to avoid:** Read `run_bounded`'s actual code (`agy_bridge.sh:241-260`): the coreutils arm never calls `trap -p`, `trap`, or `eval` — it execs `timeout` directly and returns. `RB24`'s own test comment explicitly calls the coreutils arm "the control" that is expected to always keep the host's traps unchanged (the mechanism can't corrupt what it never touches). Any real race can only live in the watchdog arm's 27 lines (`agy_bridge.sh:330-357`).
**Warning signs:** If a future `RB24` failure detail ever names `coreutils` rather than `watchdog` as the failing mechanism, that would be a different, higher-priority bug (evidence the "coreutils never touches traps" invariant itself broke) — not this ticket's race.

## Code Examples

### D-04 — `delegate-agy-ltf`: `gemini_shim.sh`'s unknown-long-flag branch

Current code, verified this session (line numbers current on `master`, not the ticket's stale `:556` citation):

```bash
# scripts/gemini_shim.sh:568-572 [VERIFIED: read this session]
        # Silently skip unknown flags to maximise compatibility
        --no-*)    ;;
        --[a-z]*)  [[ $# -ge 2 && "${2:-}" != -* ]] && shift 2 || shift ;;
        --*=*)     ;;
        -*)        ;;
```

The bug: for any unrecognized `--foo` followed by a token that doesn't itself start with `-` (e.g. the prompt text), the branch `shift 2`s — dropping the prompt.

**Verified fact that shapes the fix:** every currently-known flag that legitimately takes a separate value (`-m`/`--model`, `-o`/`--output-format`, `--approval-mode`, `--include-directories`) already has its own explicit `case` arm *earlier* in the same `case` statement (confirmed by reading the full arm list, `gemini_shim.sh:520-567`), so bash's first-match `case` semantics mean **none of those ever reach line 570** — the catch-all only ever fires for genuinely unrecognized flags. This means CONTEXT.md's "except for an explicit allowlist of flags already known to take a separate value" carve-out currently has **zero members** — a fix at line 570 alone (never `shift 2`) is sufficient today; an allowlist array is only needed if a *future* flag both (a) needs a separate value and (b) is deliberately left unrecognized by this shim (an unusual combination). Flag this tradeoff for the planner rather than silently picking one.

**Recommended fix (D-04):**
```bash
        --[a-z]*)  shift ;;   # never consume the next token; unknown flags are ignored, not "eaten with their value"
```

### D-05 — `delegate-agy-u1z`: twin `grep -qxF` sites

Exact locations, both `[VERIFIED: read this session]`:
```
scripts/agy_bridge.sh:560:    if ! grep -qxF "$MODEL" <<< "$VALID_MODELS"; then
scripts/gemini_shim.sh:471:    if [[ -n "$LIVE_MODELS" ]] && grep -qxF "$m" <<< "$LIVE_MODELS"; then
```

Two existing precedents in `tests/run-tests.sh` for the "mirror the herestring-count assertion pattern" instruction — both from Phase 2 (`02-01-PLAN.md`/`02-02-PLAN.md`) as CONTEXT.md cites:

**Precedent A — single-file form-check (`R9d`/`SH15d`, guards regression *back to* the unsafe pipe form):**
```bash
# tests/run-tests.sh:625-627 [VERIFIED: read this session]
R9D_PIPE="$(grep -cF '"$VALID_MODELS" | grep -qxF "$MODEL"' "$BRIDGE")" || R9D_PIPE=0
R9D_HERE="$(grep -cF 'grep -qxF "$MODEL" <<< "$VALID_MODELS"' "$BRIDGE")" || R9D_HERE=0
[[ "$R9D_PIPE" -eq 0 && "$R9D_HERE" -eq 1 ]] ...
```
A byte-identical twin (`SH15D_PIPE`/`SH15D_HERE`) exists at `tests/run-tests.sh:1575-1577` against `$SHIM`.

**Precedent B — genuine cross-file structural-equality check (`IN01`, one combined assertion spanning both files):**
```bash
# tests/run-tests.sh:1591-1599 [VERIFIED: read this session]
IN01_BRIDGE_PATTERN=$'( umask 077; printf \'%s\' "$_agy_models" > "$CACHE_FILE.tmp.$$" )'
IN01_SHIM_PATTERN=$'( umask 077; printf \'%s\' "$raw" > "$MODELS_CACHE.tmp.$$" )'
IN01_BRIDGE="$(grep -cF "$IN01_BRIDGE_PATTERN" "$BRIDGE")" || IN01_BRIDGE=0
IN01_SHIM="$(grep -cF "$IN01_SHIM_PATTERN" "$SHIM")" || IN01_SHIM=0
if [[ "$IN01_BRIDGE" -eq 1 && "$IN01_SHIM" -eq 1 ]]; then
    ok "IN01 cache-file write is umask-guarded in both scripts, closing perm window (IN-01)"
```

`R9d`/`SH15d` already guard the *form* of both `grep -qxF` sites independently (regression back to the SIGPIPE-unsafe pipe form). What's missing — and what D-05 is actually asking for — is `IN01`'s shape applied to these two sites: a **single combined assertion** that both files' `grep -qxF "$MODEL"`/`grep -qxF "$m"` sites still exist at all (count 1 each), catching drift/deletion that `R9d`/`SH15d` don't cover (they only fire if the site regresses to the *pipe* form specifically, not if it's deleted, renamed, or restructured some other way). Recommend `IN01`'s pattern, since it is the only one of the two that is genuinely "structural-equality... across both files."

### D-06 — `delegate-agy-d4t`: RB01 loop + the guard-clause conflict

**Step 1 — verified impact of the naive fix**, run against the real file this session:
```
$ (source the exact _rb_logical_lines/_rb_agy_segments/_rb_agy_scan functions from
   tests/run-tests.sh:2316-2360 verbatim, then:)
_rb_agy_scan tests/contract-check.sh
7 11
```
7 violations out of 11 occurrences — all 7 are `[[ -z "$AGY_BIN" ]]` (`[VERIFIED: ran the scan this session]`), at `tests/contract-check.sh:527, 565, 600, 644, 698, 829, 1008`.

**Step 2 — the widen itself (`tests/run-tests.sh:2372`):**
```bash
# current
for _rb01_f in "$BRIDGE" "$SHIM"; do
# fix
for _rb01_f in "$BRIDGE" "$SHIM" "$CONTRACT_CHECK"; do
```
`$CONTRACT_CHECK` is already defined at `tests/run-tests.sh:36` (`CONTRACT_CHECK="$HERE/contract-check.sh"`), so this is a one-token change — but it must not land without Step 3.

**Step 3 — required, not optional: restructure `contract-check.sh`'s 7 guards.** `RB01`'s comment (`tests/run-tests.sh:2300-2306`) states the "mentions the variable outside a bounded call = violation" behavior is deliberate, with "no allowlist, no skip list, no escape-hatch comment" permitted. The correct fix computes the "agy absent" condition once, into a variable whose name does not contain the substring `AGY_BIN`, and has the 7 guard sites test that instead:
```bash
# tests/contract-check.sh:413 area — compute once, right after AGY_BIN is resolved
AGY_BIN="$(command -v agy 2>/dev/null || true)"
_CC_NO_AGY=0; [[ -z "$AGY_BIN" ]] && _CC_NO_AGY=1

# each of the 7 sites (527, 565, 600, 644, 698, 829, 1008), was:
if [[ -z "$AGY_BIN" ]]; then
# becomes:
if [[ "$_CC_NO_AGY" -eq 1 ]]; then
```
This keeps the semantics identical (still one source of truth for "is `agy` on PATH") while making the guard clauses invisible to a textual `$AGY_BIN` scan — which is the correct outcome, since these lines never *invoke* `agy`, they only test its absence.

### D-07 — `delegate-agy-b7g`: degraded-empty-reply message, without losing stderr

Exact current code, `[VERIFIED: read this session]`, `scripts/agy_bridge.sh`:
```bash
482  if _agy_models=$(run_bounded "$AGY_MODELS_TIMEOUT" 3 -- \
483                   "$AGY_BIN" models </dev/null 2>"${_agy_err:-/dev/null}"); then
489      _agy_ids="$(printf '%s\n' "$_agy_models" | cut -f1)"
490      if grep -q '^gemini-' <<< "$_agy_ids"; then
...                                                          # normal success, cache write
503      elif [[ -s "$CACHE_FILE" ]]; then
509          echo "WARNING: 'agy models' returned a list with no 'gemini-' ids ..." >&2
510          _agy_models=""
511      fi                                                   # <-- NO else: silent no-op when no cache AND no gemini- ids
...
526      [[ -n "$_agy_err" && -s "$_agy_err" ]] && sed 's/^/       agy: /' "$_agy_err" >&2
528  fi
533  VALID_MODELS="${_agy_models:-}"
534  if [[ -z "$VALID_MODELS" ]]; then
535      VALID_MODELS=$(cat "$CACHE_FILE" 2>/dev/null) || true
536  fi
537  [[ -n "$VALID_MODELS" ]] || { echo "ERROR: failed to retrieve model list from agy" >&2; exit 2; }
```

The `b7g` scenario (rc=0, zero-byte reply, no cache) falls through the `if/elif` at 490/503 with no message (neither arm matches), reaches line 537's generic bail. **Do not** add an `exit` inside the 490-511 block — that would skip line 526's unconditional stderr passthrough (the comment there explicitly calls this "the only diagnostic when the real fault is auth or the network," and re-labels this "(D-07, criterion 3)" — that is a **different, Phase-3 D-07**, an unrelated label collision the planner should not confuse with this phase's D-07/`b7g`).

**Recommended patch** — a flag set inside the block, consumed at the existing single exit choke point:
```bash
# add a sibling `else` to the existing if/elif at line ~503-511:
        elif [[ -s "$CACHE_FILE" ]]; then
            echo "WARNING: 'agy models' returned a list with no 'gemini-' ids (agy may be unauthenticated); using the stale cached list." >&2
            _agy_models=""
        else
            # D-07 (delegate-agy-b7g): rc=0 but no gemini- ids and no cache to
            # fall back on. Not "fetch failed" -- fetch succeeded and returned
            # nothing usable. Defer the exit to line 537 so the stderr
            # passthrough two lines below still runs.
            _agy_degraded_no_cache=1
        fi

# then change line 537 from:
[[ -n "$VALID_MODELS" ]] || { echo "ERROR: failed to retrieve model list from agy" >&2; exit 2; }
# to:
if [[ -z "$VALID_MODELS" ]]; then
    if [[ "${_agy_degraded_no_cache:-0}" -eq 1 ]]; then
        echo "ERROR: agy model list contains no 'gemini-' ids; agy may be unauthenticated" >&2
        echo "       or its 'agy models' output format changed. Run 'agy models' to inspect." >&2
    else
        echo "ERROR: failed to retrieve model list from agy" >&2
    fi
    exit 2
fi
```
This reuses the exact two-line message already at `agy_bridge.sh:547-548` verbatim (same wording D-07 asks for), touches no other branch's behavior (the pre-existing nonzero-rc/no-cache path at lines 512-524 already double-prints its own accurate timeout/error message plus this generic-or-specific one — unchanged either way, since `_agy_degraded_no_cache` stays unset on that path), and keeps the stderr passthrough intact.

**`gemini_shim.sh` needs no change for D-07** — ticket text and my own reading of its `load_models()` confirm its `[[ -n "$raw" ]]` guard already skips the whole degraded-detection block on a truly-empty raw reply, falling straight to the cache read with identical external behavior to the (already-fixed) `SH15`/`SH15b` cases.

### D-08 — `delegate-agy-sup`: `run_bounded`'s trap save/restore

Full current watchdog-arm code, `[VERIFIED: read this session]`, `scripts/agy_bridge.sh:262-358` (identical in `gemini_shim.sh`, per `RB02`'s own byte-identity check):
```bash
262  # ── bash watchdog fallback: no external binary at all ────────────────────
...
330  rb_trap_term="$(trap -p TERM)"
331  rb_trap_int="$(trap -p INT)"
332  rb_trap_hup="$(trap -p HUP)"
333  trap '_rb_relay TERM 143' TERM
334  trap '_rb_relay INT 130' INT
335  trap '_rb_relay HUP 129' HUP
336
337  _rb_start_timer "$secs" TERM
338  wait "$child" 2>/dev/null || rc=$?
339  _rb_cancel_timer "$timer" "$timer_pgid"
340  trap - TERM INT HUP
341  eval "${rb_trap_term:-}"
342  eval "${rb_trap_int:-}"
343  eval "${rb_trap_hup:-}"
...
357  return "$rc"
358  }
```

The coreutils arm (`agy_bridge.sh:241-260`) never calls `trap -p`/`trap`/`eval` — it forks `timeout -k ...` directly. `[VERIFIED: read this session]` — this arm architecturally cannot be the source of a trap-preservation race; `RB24`'s own test comment (`tests/run-tests.sh:2079-2080`) treats it explicitly as the control.

**`_rb_relay`** (`agy_bridge.sh:215-221`), installed as the TERM/INT/HUP handler for the whole window between lines 333 and 340:
```bash
_rb_relay() {
    _rb_cancel_timer "$timer" "$timer_pgid"
    _rb_start_timer 0 "$1"
    wait "$child" 2>/dev/null || true
    _rb_cancel_timer "$timer" "$timer_pgid"
    exit "$2"
}
```
Note the unconditional `exit "$2"` — if `_rb_relay` fires for ANY reason during the window before line 340 clears it, the whole `bash -c` process (or the whole caller script, if `run_bounded` isn't itself in a subshell) exits immediately, **before line 341-343's restore-eval ever runs** — leaving the host's original TERM/INT/HUP handlers permanently replaced by whatever default disposition `trap -` would have set, except `trap -` itself never even executes in that scenario. This is architecturally the only mechanism by which "before" and "after" trap state could diverge for a call that otherwise completed normally (like `RB24`'s `run_bounded 5 2 -- true`).

**What I could not establish:** the exact trigger that delivers a TERM/INT/HUP to the `_rb_relay`-trapped shell during this narrow window when nothing external is sending signals and the bounded command (`true`) exits almost instantly. I attempted live reproduction this session:
- 2 full `bash tests/run-tests.sh` runs (idle system): `PASS=161 FAIL=0` both times, `RB24` green both times.
- 80 isolated iterations (40 watchdog + 40 coreutils) of `RB24`'s exact driver script, extracted verbatim from `gemini_shim.sh`'s `run_bounded` block: 0 failures.

This is honest negative evidence, not proof of absence — the ticket confirms the flake reproduced on a pre-Phase-02 commit (`a7ab6bd`), so it is real, just not triggered by the conditions in this session (idle host, low iteration count relative to whatever rate produces "roughly every other full-suite run" on the original reporting host). `[ASSUMED]` — everything below this point is a hypothesis, not a verified root cause.

**Hypothesis:** `_rb_cancel_timer` (`agy_bridge.sh:148-152`) sends a real `SIGTERM` to the timer subshell (via `_rb_signal`, `agy_bridge.sh:132-139`) while the `_rb_relay TERM ...` trap is *still installed* (line 339 runs before line 340 clears it). If that signal, or its delivery timing, ever races with bash's own asynchronous signal-delivery point (bash defers trap execution to the next "safe point" between simple commands — the gap between line 339 finishing and line 340 executing is exactly such a point) landing on the **shell itself** rather than being cleanly confined to the timer's process group — `_rb_relay` fires, `exit`s unconditionally, and the restore-eval at 341-343 never runs. `_rb_pgid_of`'s `/proc`-read-based pgid lookup (`agy_bridge.sh:94-123`) is a plausible source of an occasional stale/incorrect pgid under load, though I could not confirm this empirically.

**Recommended fix direction (untested):** reorder so trap restoration happens *before* timer cancellation, closing the window where `_rb_relay` can still be armed while a signal related to timer teardown is in flight:
```bash
_rb_start_timer "$secs" TERM
wait "$child" 2>/dev/null || rc=$?
trap - TERM INT HUP           # restore/disarm BEFORE the cancel-timer signal
eval "${rb_trap_term:-}"
eval "${rb_trap_int:-}"
eval "${rb_trap_hup:-}"
_rb_cancel_timer "$timer" "$timer_pgid"   # moved last
```
This is also arguably more correct on its own terms: by the time we reach this code, the bounded command has already completed on its own (not via signal), so the host should own signal handling again immediately, not after one more `kill` call the relay traps are still watching.

**Answering CONTEXT.md's discretion question directly:** given (a) the flake is proven real but not reliably reproducible on demand, and (b) this codebase's own established convention is "prove the check can fail before trusting it" (`RB01m`, `RB25`, `RB26`), **recommend both**: implement the reorder fix above, *and* add one new deterministic test that forces a signal into the narrow window (rather than relying on natural scheduler jitter) — e.g., have the bounded command itself send a `TERM` to its own parent's pgid at the moment it exits, synchronizing delivery to land near the cancel/restore boundary. Rerunning `RB24` N times alone is not sufficient proof: 82 clean attempts this session against a codebase where the ticket confirms the flake is real demonstrates reruns have weak power to confirm a fix actually addressed the trigger versus got lucky.

### Criterion 2 verification — exact commands and results

```bash
$ git merge-base --is-ancestor fix/agy-bridge-resilience master && echo yes
yes
```
`[VERIFIED: ran this session]` — confirms CONTEXT.md's "Scouted" claim mechanically, not by trust.

```bash
$ git log -1 --format='%H %P' a001d0e
a001d0e857c064ca8534bc6610417e6cdfcfa47e 1a0051c9f9d2c7f365b760b27c14d97fe2cd2b7f
```
Single parent — `a001d0e` is a normal revert commit, not a merge; reachable from `master` (`git merge-base --is-ancestor a001d0e master` → yes, `[VERIFIED]`).

```bash
$ git show --stat a001d0e -- scripts/ README.md
 README.md             | 36 ++++++---------------
 scripts/agy_bridge.sh | 69 ++++++---------------------------------
 scripts/install.sh    | 90 +++++++++++++++++----------------------------------
 3 files changed, 47 insertions(+), 148 deletions(-)
```
`[VERIFIED: ran this session]` — `a001d0e` touched exactly these 3 files (**not** `gemini_shim.sh` — that script's bounding was fixed independently and later, in Phase 1, per `REQUIREMENTS.md`'s R11 traceability, not by the reverted `fix/agy-bridge-resilience` branch).

**Confirmed today's `master` already carries every piece `a001d0e` removed**, re-implemented with more rigor:

| Removed by `a001d0e` | Re-present on `master` today |
|---|---|
| `AGY_MODELS_TIMEOUT` bound + validation | `scripts/agy_bridge.sh:42-44` `[VERIFIED]` |
| `-k` SIGKILL escalation on the model-fetch call | `run_bounded "$AGY_MODELS_TIMEOUT" 3 -- ...` at `agy_bridge.sh:482` `[VERIFIED]` |
| `-k` SIGKILL escalation on the delegation call | `run_bounded "$TIMEOUT" 5 -- "$AGY_BIN"` at `agy_bridge.sh:716` `[VERIFIED]` |
| Degraded-list ("no gemini- ids") message | `agy_bridge.sh:547-548` `[VERIFIED]` |
| 137-vs-124 external-kill discrimination | `agy_bridge.sh:726-748` `[VERIFIED]` |
| `install.sh` stale-pin `exit 127` registry comparison | `scripts/install.sh:138, 174` `[VERIFIED]` |
| README's two-step, registry-comparison-only install prose | present verbatim in current `README.md:81-114` region `[VERIFIED: read this session]` |

The planner's verification step for criterion 2 can therefore be exactly: `git merge-base --is-ancestor fix/agy-bridge-resilience master` (expect exit 0) plus the 6 `grep`/line-number checks in the table above — not a full-file diff against the old branch (which would show noise from unrelated `.planning/` doc divergence, confirmed via `git diff master fix/agy-bridge-resilience --stat` this session).

### D-09 — exact current `### 1.6.2` Changelog section

Verbatim, `[VERIFIED: read this session]`, `README.md:405-415`:
```markdown
## Changelog

### 1.6.2

- `agy-bridge` no longer hangs when agy does. [... 6 existing bullets, unchanged ...]
- `/agy-setup` leads with a readable two-step install (print the path, run it) instead of the 9-line resolve-and-validate pipeline; the pipeline remains as a fallback where no registry file exists.

### 1.6.1
```
Insertion point: new bullets go **between** the last existing bullet (line 414, ending "...where no registry file exists.") and the blank line before `### 1.6.1` (line 416) — i.e. append lines, do not touch 1.6.1/1.6.0 sections. Existing bullet style to match: one bullet per defect, backtick-quoted identifiers, plain language, past-tense description of the fix, no ticket IDs inline (CONTEXT.md's discretion note confirms this last point explicitly).

CONTEXT.md's D-09 text: "the six newly-fixed items (ltf, u1z, d4t, b7g, plus a line noting xfa/i43's investigation-closures)" — this literally lists 4 named fix-bullets (ltf, u1z, d4t, b7g) plus "a line" for xfa/i43 (singular "a line" for two ticket closures, or possibly one line each — ambiguous as written). Flagging verbatim rather than resolving silently: the planner should write 4 fix-bullets + 1 (or 2) closure-note bullet(s) + the mandatory "every existing installation must re-run the installer" notice (explicitly required by the phase's success criterion 4, independent of D-09's own wording).

### D-10 — fresh-install checklist components

Wrapper-writing call sites, `[VERIFIED: read this session]`:
```bash
# scripts/install.sh:206-207
write_wrapper "agy-bridge" "$BRIDGE_TARGET" "$BIN_DIR/agy-bridge"
write_wrapper "gemini" "$SHIM_TARGET" "$BIN_DIR/gemini"
```
`agy_bridge.sh` has **no `--version` arm** (`[VERIFIED: grep -n -- "--version" scripts/agy_bridge.sh` returned nothing this session]`) — so "confirm both launchers exec" cannot use a `--version` smoke-test for `agy-bridge` the way it can for `gemini` (`gemini_shim.sh:540` maps `--version` straight to `agy --version`). Concrete literal checklist for D-10, given what actually exists:
```bash
command -v agy-bridge && command -v gemini              # both resolve on PATH
gemini --version                                        # -> prints agy's version string (exit 0)
head -1 "$(command -v agy-bridge)"                        # confirm shebang + WRAPPER_MARKER present
grep -qF '# agy-delegate-wrapper' "$(command -v agy-bridge)" "$(command -v gemini)"
bash tests/run-tests.sh                                 # both suites
bash tests/hooks/run-hook-tests.sh
```
`agy-bridge` itself needs a real (or fake) `agy` plus stdin to smoke-test meaningfully (`echo test | agy-bridge --type search` would spend real quota); given D-10 is an explicitly manual, one-time pass (not automated CI), recommend the plan's checklist stop at "launcher resolves + is executable + suites pass," matching CONTEXT.md's own scope note that this is deliberately *not* a new automated E2E test.

**"Both suites" is resolved, not ambiguous** — CONTEXT.md's own "Scouted, not hypothesized" section states this explicitly: `tests/run-tests.sh` (the harness, which already contains the installer's `I`-prefixed cases — confirmed this session, section starts at `tests/run-tests.sh:3818` "== install.sh / uninstall.sh (vfn.11) ==") and `tests/hooks/run-hook-tests.sh` (28-test hook suite) — **not** a separate, undiscovered "installer suite" despite the phase description's own prose using that phrase. Use CONTEXT.md's resolution; the phase-description wording is imprecise, not a second suite.

## Runtime State Inventory

**Not applicable.** This phase is a bug-fix + release-gate phase, not a rename/refactor/migration. No stored data, live service config, OS-registered state, secrets, or build artifacts carry an identifier being renamed. (Confirmed by reading all 8 tickets' full text and CONTEXT.md's Decisions — none involve renaming anything.)

## Common Pitfalls
(See above, folded into the main Common Pitfalls section — kept together with the code they apply to rather than duplicated.)

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | D-08's root cause is a signal-delivery race in `run_bounded`'s watchdog-arm cancel-before-restore ordering (lines 339-340) | Code Examples / D-08 | If wrong, the recommended reorder fix may not eliminate the flake; the deterministic forcing-test recommendation still has value (it would simply continue failing after the fix, correctly signaling the real cause is elsewhere) |
| A2 | `_rb_pgid_of`'s `/proc`-read-based pgid lookup is a plausible (not confirmed) contributor to a stale/incorrect pgid under load | Code Examples / D-08 | Low — stated only as a secondary, unconfirmed contributing hypothesis, not load-bearing for the recommended fix |
| A3 | D-09's "six newly-fixed items... plus a line" should resolve to 4 fix-bullets + 1-or-2 closure bullets + the reinstall notice | Code Examples / D-09 | Low — cosmetic; wrong bullet count doesn't block the release, just needs a planner decision, flagged explicitly above rather than silently resolved |

## Open Questions

1. **Does the D-08 reorder fix (restore-before-cancel) actually eliminate the `RB24` flake?**
   - What we know: it closes the one architecturally-identifiable window where `_rb_relay`'s unconditional `exit` could skip the restore-eval.
   - What's unclear: whether this is *the* trigger or *a* trigger, given zero live reproductions this session.
   - Recommendation: implement the fix, add the deterministic forcing-test recommended above, and treat "the forcing test now reliably passes both before-fix-red and after-fix-green" as the actual proof — not natural-rerun counts.

2. **D-09's exact bullet count** — see A3 above; needs a planner decision, not a research answer (CONTEXT.md's own wording is internally ambiguous on this one point).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `bash` | everything | ✓ | system default | — |
| GNU coreutils `timeout` | `run_bounded`'s coreutils arm, both suites | ✓ | `/usr/bin/timeout` | bash watchdog (already the shipped fallback) |
| `python3` | JSON envelope construction | ✓ | 3.14.7 | — |
| `agy` binary | D-10's manual fresh-install check, `tests/contract-check.sh` (excluded from this phase's gate) | ✓ | 1.1.17 | — |
| `git` | criterion-2 verification | ✓ | 2.55.0 | — |
| `gh` CLI | confirming no prior GitHub Release exists | ✓ | 2.98.0 | — |
| `bd` | ticket tracking (not shipped) | ✓ | 1.2.2 | — |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none — every dependency this phase touches is present on this dev host.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Custom bash harness (`ok`/`bad` functions), no external test framework |
| Config file | none — `tests/run-tests.sh` is self-contained; `tests/hooks/run-hook-tests.sh` is a separate self-contained harness |
| Quick run command | targeted case unavailable — no `--filter` flag exists in either harness (`[VERIFIED: grep for FILTER/--filter in tests/run-tests.sh this session found nothing]`) |
| Full suite command | `bash tests/run-tests.sh` (161 cases, ~3m44s measured this session) + `bash tests/hooks/run-hook-tests.sh` |

### Phase Fixes → Test Map
| Ticket | Behavior | Test | Command | File Exists? |
|--------|----------|------|---------|-------------|
| D-04 (`ltf`) | unknown long flag never consumes the next token | needs a new case — none exists today | `bash tests/run-tests.sh` (new case to add) | ❌ new case needed |
| D-05 (`u1z`) | twin `grep -qxF` sites structurally present in both files | needs a new case (`IN01`-shaped) | `bash tests/run-tests.sh` (new case to add) | ❌ new case needed |
| D-06 (`d4t`) | `RB01` scans `contract-check.sh` too, zero violations | `RB01` (existing, extend loop) + `contract-check.sh` restructure | `bash tests/run-tests.sh` | ✅ (extend) |
| D-07 (`b7g`) | empty successful fetch, no cache → specific message | needs a new case — none exists today | `bash tests/run-tests.sh` (new case to add) | ❌ new case needed |
| D-08 (`sup`) | `RB24` deterministically green pre- and post-fix | `RB24` (existing) + new forcing test | `bash tests/run-tests.sh` | ⚠️ `RB24` exists but is non-deterministic; new forcing case needed |

### Sampling Rate
- **Per task commit:** `bash tests/run-tests.sh` (no faster targeted-run option exists in this harness)
- **Per wave merge:** `bash tests/run-tests.sh && bash tests/hooks/run-hook-tests.sh`
- **Phase gate:** both suites green, per criterion 3 (contract-check.sh explicitly excluded, per the phase's own note)

### Wave 0 Gaps
- [ ] New `tests/run-tests.sh` case for D-04 (unknown-flag-never-eats-next-token)
- [ ] New `tests/run-tests.sh` case for D-05 (twin `grep -qxF` site structural presence, `IN01`-shaped)
- [ ] New `tests/run-tests.sh` case for D-07 (empty-successful-fetch-no-cache message)
- [ ] New `tests/run-tests.sh` deterministic forcing case for D-08 (signal delivered into the exact narrow window, not relying on natural jitter)
- [ ] `tests/contract-check.sh` guard-clause restructure (7 sites) required *before* D-06's loop-widen lands, or `RB01` goes red

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | This phase touches no auth code (agy's own OAuth is out of scope) |
| V3 Session Management | No | No sessions in this codebase |
| V4 Access Control | No | No access-control logic touched |
| V5 Input Validation | Yes | D-04's flag-parsing fix is input validation on argv. Existing positive-integer regex guards (`^[1-9][0-9]*$`) for all timeout/bound values are the established pattern — do not introduce a new parsing mechanism |
| V6 Cryptography | No | No crypto in this phase |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation (already in place, verify unchanged) |
|---------|--------|---------------------------------------------------------|
| Argument injection via unrecognized flags consuming the prompt (D-04's exact bug) | Tampering / information exposure | Never `shift 2` for an unrecognized flag; require `--flag=value` inline form for any value a genuinely-unknown flag needs |
| SIGPIPE-induced false-negative on model validation (`R9d`/`SH15d`, unrelated to this phase but adjacent to D-05's twin sites) | Denial of Service (spurious rejection) | Herestring form (`<<<`), never `printf | grep -qxF` — already fixed; D-05 only adds a presence-check, does not touch this |
| Unbounded `agy` invocation outliving its caller (the whole `run_bounded` mechanism, R11) | Denial of Service | Every `$AGY_BIN` occurrence must be a `run_bounded` argument — D-06 extends this invariant's *scan coverage*, does not touch the invariant itself |

No new attack surface is introduced by this phase — all 8 tickets are corrections to existing, already-audited control paths (flag parsing, model-list caching, bounded execution, install pinning). D-06 and D-07's patches specifically must not *weaken* existing security invariants while fixing their bugs (confirmed above: D-06's fix preserves "zero exceptions" in the unbounded-call scan; D-07's fix preserves the stderr diagnostic passthrough).

## Sources

### Primary (HIGH confidence — all read directly this session)
- `scripts/gemini_shim.sh` (737 lines, full read + targeted `sed` extraction) — D-04, D-05 twin site
- `scripts/agy_bridge.sh` (813 lines, full read + targeted `sed` extraction) — D-05 twin site, D-07, D-08, criterion 2
- `scripts/install.sh` (398 lines, targeted read) — D-10, criterion 2
- `tests/run-tests.sh` (5428 lines, targeted `sed`/`grep` extraction of `RB01`, `RB01m`, `RB24`, `R9d`, `SH15d`, `IN01`, `_rb_agy_segments`/`_rb_agy_scan`/`_rb_logical_lines`) — D-05, D-06, D-08
- `tests/contract-check.sh` (targeted grep for `$AGY_BIN` sites) — D-06
- `tests/hooks/run-hook-tests.sh` (targeted read) — D-10
- `README.md` (full read) — D-09, D-10, Standard Stack version citation
- `.planning/phases/06-ship-1-6-2/06-CONTEXT.md` (full read via `sed`, clean) — all locked decisions
- `.planning/REQUIREMENTS.md`, `.planning/STATE.md`, `.planning/phases/06-ship-1-6-2/06-BEADS-RECALL.md` — traceability, project history
- `bd show` output for all 8 tickets (`delegate-agy-ltf`, `-u1z`, `-d4t`, `-b7g`, `-sup`, `-xfa`, `-i43`, `-rod`) — full ticket text
- Live tool runs this session: `git merge-base --is-ancestor` (×2), `git show --stat a001d0e`, `git show a001d0e -- <file>` (×3), `gh release list`, `bash tests/run-tests.sh` (×2 full runs), 80× isolated `RB24`-driver reproduction attempt, direct invocation of `_rb_agy_scan` against `tests/contract-check.sh`

### Secondary (MEDIUM confidence)
- None used — no web search was needed or attempted; this is a closed-codebase phase per the task's own explicit instruction ("do NOT research external domains").

### Tertiary (LOW confidence)
- D-08's root-cause hypothesis (signal-delivery race, `_rb_pgid_of` staleness under load) — static analysis only, could not be confirmed via live reproduction; explicitly tagged `[ASSUMED]` throughout.

## Metadata

**Confidence breakdown:**
- Code-location findings (D-04, D-05, D-06, D-07, D-09, D-10, criterion 2): HIGH — every line number and code excerpt was read from `master` this session, several empirically exercised (RB01's scan run directly, full test suite run twice, git ancestry commands run directly)
- D-08 root cause: LOW — grounded in a full static trace but not confirmed by reproduction; presented as `[ASSUMED]` with an explicit recommended validation path (deterministic forcing test) rather than a claimed answer

**Research date:** 2026-08-21
**Valid until:** Effectively indefinite for the code-location findings (this is a static, slow-moving bash codebase with no CI and no dependency drift) — but re-verify line numbers if any other phase/commit lands on `master` before this phase's plan executes, since several fixes are only 1-3 lines away from each other and a line-number citation could drift.
