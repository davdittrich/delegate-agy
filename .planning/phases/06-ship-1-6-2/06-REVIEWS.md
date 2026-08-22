---
phase: 06
reviewers: [codex, antigravity]
reviewed_at: 2026-08-21T21:49:42Z
plans_reviewed: [06-01-PLAN.md, 06-02-PLAN.md, 06-03-PLAN.md, 06-04-PLAN.md, 06-05-PLAN.md, 06-06-PLAN.md]
models:
  codex: "gpt-5.6-sol (reasoning=low)"
  antigravity: "unknown"
model_sources:
  codex: "banner"
  antigravity: "unknown"
---

# Cross-AI Plan Review — Phase 06

## Consensus Summary

Both reviewers independently verified the plans' cited file:line claims against the live repository and agree the phase is unusually well-grounded: dependencies are explicit, fixes are narrow same-file patches, TDD RED gates are required before each fix, and the release gate checks installed artifacts rather than trusting `git log`. Neither reviewer found the phase over-engineered or scope-creeping. Both flag that Beads (`bd`) state could not be independently verified in their read-only review environments.

The two reviewers diverge sharply on **risk level** (Codex: HIGH pre-fix / MEDIUM-LOW if concerns addressed; Antigravity: LOW throughout) because Codex traced three specific mechanisms end-to-end and found each one doesn't yet prove what its plan claims, while Antigravity's concerns are narrower correctness nits that don't touch the same claims. Codex's three HIGH findings are independently plausible against the cited line numbers and are treated as consensus-worthy despite only one reviewer raising them, because each cites a concrete mechanism mismatch rather than a stylistic preference.

### Agreed Strengths
- Root-cause reasoning for D-08 (trap-restore-before-timer-teardown) is correctly grounded in `agy_bridge.sh:330-343` and `_rb_relay`'s unconditional exit at `agy_bridge.sh:215`.
- D-04's single-`shift` fix is provably safe: every value-taking flag has an earlier explicit `case` arm (`gemini_shim.sh:509-538`), confirmed independently by both reviewers.
- D-07's deferred-exit-to-existing-choke-point design correctly avoids bypassing the unconditional stderr passthrough at `agy_bridge.sh:526-530`.
- D-06's `_CC_NO_AGY` guard-restructure in `contract-check.sh` (7 sites) is the right fix — extending `RB01`'s scanner without adding allowlist exceptions.
- Plan 06-06's `HOME` sandbox + `CLAUDE_CONFIG_DIR` unset is necessary and correctly targets `install.sh:157`'s registry-path precedence bug class.
- Byte-identity discipline across all three `run_bounded` copies (`agy_bridge.sh`, `gemini_shim.sh`, `tests/contract-check.sh`), protected by `RB02`, is correctly maintained by every plan touching that block.

### Agreed Concerns
None raised as HIGH by both reviewers on the same mechanism — see Divergent Views below for the three HIGH findings raised by Codex alone, which are still weighted heavily due to specific, checkable mechanism citations.

Both reviewers separately note the same category of gap: **Beads ticket-state assertions are unverifiable from a static repo review** (Codex on 06-02's "six remain" count; Antigravity implicitly, by not attempting to verify `bd` state at all). Recommendation: verify ticket identity by set comparison, not just count, when 06-02/06-06 execute.

### Divergent Views

**1. Plan 06-01 (D-08 trap fix) — does `RB30` prove the actual production root cause?**
- **Codex (HIGH):** `RB30`'s shadowed `_rb_cancel_timer` sends `TERM` to `$$` (the host shell). Production `_rb_cancel_timer` sends `TERM` to the timer PID or its process group (`agy_bridge.sh:127`, `:148`), not to the host shell directly. `RB30` proves the reorder closes *an* ordering hazard, not that this specific hazard caused the historical `RB24` flake. Suggests recasting `RB30` as an ordering-invariant regression test rather than root-cause proof, or requiring a production-shaped reproduction.
- **Antigravity:** Did not flag this distinction; treated `RB30`'s deterministic signal injection as sufficient given RESEARCH.md's `[ASSUMED]` framing and the plan's own halt condition.
- **Assessment:** This is a real, checkable claim (mechanism citations on both sides of the argument), not a stylistic disagreement. Worth resolving before 06-01 executes — either strengthen `RB30` to inject via the timer-PID path or adjust the plan's closure language to not overclaim root-cause proof.

**2. Plan 06-03 (D-07 degraded-message fix) — can `R9f` actually assert what it claims?**
- **Codex (HIGH):** `FAKE_AGY_STDERR` in `tests/fake-agy.sh` is only emitted on delegation paths (`fake-agy.sh:230`, `:238`). The bridge's empty-successful-fetch case exits during *model discovery*, before any delegation occurs — so `R9f`'s stderr-passthrough assertion has no fixture path to actually drive it, and will likely stay red (or vacuously pass) after the production fix lands.
- **Antigravity:** Did not independently trace `fake-agy.sh`'s stderr-emission conditional against `R9f`'s specific assertion; flagged only a `set -u` scoping nit on `_agy_degraded_no_cache` (LOW, and the plan already guards it with `:-0`).
- **Assessment:** This is the most concrete and actionable finding in either review — if correct, `R9f` as currently specified cannot pass, which would either block 06-03 or silently produce a non-verifying test. Recommend the executor add a model-discovery-path stderr mode to the fake fixture (e.g. `FAKE_AGY_MODELS_EMPTY_STDERR`) before writing `R9f`, and verify the RED gate is driven by the right code path.

**3. Plan 06-06 (release gate) — what exactly does "clone the repository" clone?**
- **Codex (HIGH):** The plan doesn't pin whether the fresh-install proof clones the local working tree (proves committed local state, not what's push-able) or the configured GitHub remote (proves remote state, which may lag local commits from earlier plans in this same phase). Either interpretation can produce a misleading pass if the two diverge at execution time.
- **Antigravity:** Confirmed the sandbox isolation mechanism (`HOME` + `CLAUDE_CONFIG_DIR`) is correct and sufficient to prevent contamination of the operator's real launchers; did not address which ref gets cloned.
- **Assessment:** Straightforward to close — pin the exact SHA cloned (local `master` at time of gate execution) and record it, so a later ship-time check can confirm the pushed remote matches.

### Additional Antigravity-only findings (not raised by Codex, all LOW)
- `README.md:143` cites `agy 1.1.13` for validation while current dev hosts report `agy 1.1.17` — cosmetic, may confuse manual verifiers, worth a drive-by fix in 06-05.
- `_CC_NO_AGY`'s snapshot-at-resolution-time nature in `contract-check.sh` is safe today (traced: `AGY_BIN` never reassigned) but should get a comment noting the invariant, matching Codex's independent LOW finding on the same variable.

### Additional Codex-only findings (not raised by Antigravity, MEDIUM/LOW)
- 06-01: test shadow for `_rb_cancel_timer` must set its one-shot re-entrancy guard *before* calling `kill -TERM $$`, or `_rb_relay` can recurse into it (MEDIUM) — Antigravity independently suggested the same re-entrancy guard as a **Suggestion**, so this is closer to agreed than divergent; listed here because Codex rated it a blocking-adjacent concern and Antigravity rated it a nice-to-have.
- 06-03: `SH16` should test `--model pro` (a genuine long-form value-taking flag) rather than `-m`, to actually exercise the regression it's meant to guard (MEDIUM).
- 06-04: `IN02` is a presence/form guard, not true structural-equality — plan should describe it accurately rather than overclaim (MEDIUM). Also: line-number-anchored acceptance checks for the `RB01` loop location will drift once earlier plans edit `tests/run-tests.sh` — prefer an anchored search (LOW).
- 06-05: Criterion-2 item 5's `"$EXIT_CODE" -eq 137` search proves a branch exists, not that it discriminates elapsed-time-vs-bound correctly or preserves arm ordering — strengthen to assert all load-bearing pieces (MEDIUM).
- 06-06: real-`~/.local/bin` mtime assertion is overbroad (any unrelated file touch in that dir fails it) — narrow to the two specific launcher paths (MEDIUM). Cleanup-before-dossier ordering risks losing diagnostic output on failure — emit/copy logs before deleting scratch state (MEDIUM). Ticket closure currently precedes human sign-off with no specified reopen path if a criterion is rejected (MEDIUM).

---

## Codex Review

{see full review at .planning/phases/06-ship-1-6-2/06-REVIEWS.md generation time — reproduced in full below}

### Overall assessment

The phase is unusually well grounded: dependencies are explicit, fixes are narrow, test-first evidence is required, and the final gate checks installed artifacts rather than trusting source history. Two issues should be corrected before execution:

1. Plan 06-01 proves that the proposed statement ordering is safer, but does not establish that this ordering caused the reported intermittent `RB24` failure.
2. Plan 06-03's `R9f` stderr assertion cannot work with the fake's current behavior because `FAKE_AGY_STDERR` is emitted only during delegation, while the bridge exits during model discovery.

I verified the cited mechanisms against the repository. Beads state itself could not be verified because its embedded database requires writes and this review environment is read-only.

### Plan 06-01 — Trap-restoration tracer

**Summary:** The statement reorder is defensible and the three-copy synchronization is correctly covered. However, `RB30` models a constructed self-signal, not the unknown production signal source behind the intermittent `RB24` failure. It proves an ordering hazard exists but does not root-cause the reported flake. As written, the plan could close `delegate-agy-sup` while the original failure remains unexplained.

**Strengths:**
- The vulnerable ordering is real: normal completion currently cancels the timer while `_rb_relay` is still installed, then restores the host traps afterward (`scripts/agy_bridge.sh:330`, `:339`).
- `_rb_relay` unconditionally exits, so a signal handled during that interval bypasses the restoration statements (`scripts/agy_bridge.sh:215`).
- The plan correctly includes all three copies. `RB02` already compares bridge, shim, and contract-check blocks byte-for-byte (`tests/run-tests.sh:2443`).
- The mandatory RED gate and halt condition are appropriate for a low-confidence hypothesis.
- Restricting `RB30` to the watchdog arm is correct; the coreutils arm returns before any trap manipulation (`scripts/agy_bridge.sh:241`).

**Concerns:**
- HIGH — The proposed test does not identify the source of the actual flake. `RB30` deliberately overrides `_rb_cancel_timer` and sends `TERM` to `$$`. Production `_rb_cancel_timer` sends TERM to the timer PID or its confirmed process group, not to the host shell (`scripts/agy_bridge.sh:127`, `:148`). Passing `RB30` proves "restore before a hypothetical host signal," but not that timer cancellation caused `RB24`.
- MEDIUM — The test shadow must set its one-shot guard before calling `kill -TERM $$`. Otherwise `_rb_relay` immediately calls the shadow again and can recurse. The plan requires a guard but does not lock the sequencing.
- MEDIUM — The plan overstates the post-fix result. A restored host trap may itself exit or perform destructive cleanup during `run_bounded`; "execution continues" is true only for the selected echo-only test handler.
- LOW — The claimed "costly" reversibility is overstated. The production change is a small synchronized reorder protected by `RB02`; the uncertainty is evidentiary, not rollback complexity.

**Suggestions:**
- Recast `RB30` as an ordering-invariant regression, not proof of the original flake's root cause.
- Require either a production-shaped reproduction showing `_rb_cancel_timer` can misdirect TERM to the host shell, or closure text explicitly saying the ordering hazard was fixed while the precise source of the historical intermittent signal remains unverified.
- Specify that the shadow sets its fired flag before sending the signal.
- Preserve the halt condition if the constructed pre-fix RED cannot be demonstrated.

**Risk assessment:** HIGH. The code change is small and likely beneficial, but the plan's evidence does not justify its root-cause and ticket-closure claims.

### Plan 06-02 — Investigation closures

**Summary:** This is a sound documentation-and-tracker plan. It keeps investigation results durable and avoids turning one real-agy observation into a risky code change.

**Strengths:**
- The `i43` disposition is appropriately conservative: the current source still documents the models-subcommand hang as the escalation rationale (`scripts/agy_bridge.sh:478`).
- Recording the differing subcommands — `agy models` versus a delegation — is materially important and prevents a false contradiction.
- The plan preserves the `-k` defense rather than weakening R11 based on one observation.
- Closure comments pointing back to `PROJECT.md` provide an auditable chain after the tickets disappear from the open list.
- It has no overlap with the code-owning plans.

**Concerns:**
- LOW — The requested table rows will be extremely long; embedding the full ledger line, caveat, rationale, and source citation in a single Markdown table cell reduces maintainability.
- LOW — Exact open-ticket count assertions are brittle. A new legitimate ticket opened during concurrent Plan 06-01 work would make the "six remain" assertion fail even though this plan correctly closed only its own two. Failing closed is acceptable, but the error should identify unexpected additions separately from accidental closures.
- OPEN QUESTION — Current Beads state was not independently verified; `bd` could not open its database in the read-only review environment.

**Suggestions:**
- Keep the rows concise and link to the detailed phase summary or ticket comment for full evidence.
- Verify ticket identity by set comparison, not only a count of six.
- Retain the requirement that no shipped code changes occur in this plan.

**Risk assessment:** LOW. The scope and dispositions align with the phase decisions.

### Plan 06-03 — Shim parsing and degraded empty models

**Summary:** The two source fixes are minimal and correctly targeted. The `R9f` design nevertheless contains a blocking fixture mismatch: its planned stderr-passthrough assertion cannot be driven by `FAKE_AGY_STDERR` on the model-discovery path.

**Strengths:**
- The unknown-flag defect is exactly where the plan says: the catch-all can consume two tokens (`scripts/gemini_shim.sh:568`).
- Every currently recognized separate-value flag has an earlier explicit arm (`scripts/gemini_shim.sh:510`, `:524`). A single `shift` is therefore sufficient today.
- The D-07 control-flow analysis is correct: an early exit inside the fetch branch would bypass the unconditional stderr passthrough (`scripts/agy_bridge.sh:526`).
- Deferring the diagnostic choice to the existing empty-list choke point preserves cache fallback and exit-code behavior (`scripts/agy_bridge.sh:533`).
- The `:-0` default is necessary under `set -u`.

**Concerns:**
- HIGH — `R9f` cannot currently prove the promised stderr passthrough. `FAKE_AGY_STDERR` is emitted only on delegation paths (`tests/fake-agy.sh:230`, `:238`). The bridge exits during model discovery, so delegation never occurs. The new empty-model arm is specified to write nothing and exit zero; unless it explicitly emits model-path stderr, the assertion will stay red after the production fix.
- MEDIUM — `SH16`'s "known value-taking flag" regression uses `-m`, not the long-form condition under discussion. It should at least test `--model pro`; ideally it should cover each recognized long separate-value arm.
- LOW — The unknown-flag policy remains compatibility-sensitive. `--unknown value` will now treat `value` as prompt text. That is the locked decision, but the release notes should make clear that unknown option values require `--flag=value`.
- LOW — Exact string-count assertions couple the test to duplicate diagnostic literals. They prove reuse only textually and discourage later safe centralization.

**Suggestions:**
- Add a model-specific stderr mode, such as `FAKE_AGY_MODELS_EMPTY_STDERR`, or make `FAKE_AGY_MODELS_EMPTY` emit a fixed stderr sentinel while keeping stdout zero bytes.
- Assert zero-byte stdout separately from the stderr sentinel.
- Extend `SH16` to exercise `--model`, `--output-format`, `--approval-mode`, and `--include-directories` in separate-value form.
- Keep the production changes exactly as narrow as planned.

**Risk assessment:** HIGH until the fake/stderr mismatch is corrected; MEDIUM afterward.

### Plan 06-04 — Structural guards

**Summary:** This plan correctly addresses two test-coverage holes without changing shipped behavior. The measured `7_unbounded_of_11` prediction matches the live source: seven guards mention `$AGY_BIN`, and four actual invocations are already bounded.

**Strengths:**
- `RB01` deliberately treats any non-bounded `$AGY_BIN` expansion as a violation and expressly forbids exceptions (`tests/run-tests.sh:2293`, `:2357`).
- The loop currently covers only bridge and shim (`tests/run-tests.sh:2372`).
- `contract-check.sh` contains exactly the predicted seven guard references beginning at `tests/contract-check.sh:527`, while its actual invocations are bounded, e.g. `tests/contract-check.sh:535`.
- Computing `_CC_NO_AGY` once next to resolution preserves one source of truth (`tests/contract-check.sh:410`).
- `IN02` follows the established `IN01` combined-count pattern (`tests/run-tests.sh:1591`).
- The plan correctly protects the marker-delimited `run_bounded` block from incidental edits.

**Concerns:**
- MEDIUM — `IN02` is not truly a structural-equality test. The bridge and shim expressions necessarily use different variables, so the case only asserts one exact occurrence in each file. It will not detect semantic divergence around those expressions.
- LOW — `_CC_NO_AGY` is a snapshot. This is safe in the current script because `AGY_BIN` is resolved once, but the invariant should be documented so future re-resolution does not leave the flag stale.
- LOW — Line-number-based acceptance checks will drift after earlier plans modify `tests/run-tests.sh`. The action itself is semantic, but `sed -n '2372p'` is brittle.

**Suggestions:**
- Describe `IN02` accurately as a joint presence/form guard.
- Use an anchored search for the `RB01` loop rather than asserting a fixed line number.
- Add a comment that `AGY_BIN` must not be reassigned after `_CC_NO_AGY` is computed.
- Retain the pre-rewrite RED checkpoint; it is strong evidence the expanded scan is active.

**Risk assessment:** LOW. The changes are mechanical and well constrained.

### Plan 06-05 — Content proof and release notes

**Summary:** The plan properly separates content verification from history and delays release-note writing until fixes are green. Its content script should strengthen the external-kill check, which currently proves only the existence of a 137 branch rather than the promised elapsed-versus-bound discrimination.

**Strengths:**
- The content check targets exactly the files the revert affected and explicitly avoids using history as proof of contents.
- Fixed-string searches are appropriate because Plan 06-03 will shift source line numbers.
- The expected model-diagnostic count accounts for the warning plus two error sites.
- Release-note placement and formatting match the existing changelog (`README.md:405`).
- The reinstall notice is consistent with the existing documented stale-pin behavior (`README.md:100`).
- The five-fix-plus-one-investigation resolution is coherent.

**Concerns:**
- MEDIUM — Criterion-2 item 5 is underverified. Searching for `"$EXIT_CODE" -eq 137` proves a branch exists, not that it compares elapsed time against the configured bound or preserves the intended arm ordering.
- LOW — An emphasized notice plus twelve long bullets may make the section difficult to scan. This is editorial rather than functional.
- LOW — The ancestry precondition depends on a local branch that may be pruned. The mandated halt is safe but can block an otherwise verifiable release.

**Suggestions:**
- Make item 5 assert all load-bearing pieces: the 137 arm; the elapsed-duration comparison; the comparison against the bound; its ordering relative to timeout normalization.
- Prefer a content comparison against the revert's removed hunks where practical, then add targeted checks for later hardened replacements.
- Keep each new release bullet focused on one user-visible change.

**Risk assessment:** MEDIUM. The documentation work is safe, but one release-gate proof is weaker than the behavior it claims to certify.

### Plan 06-06 — Release gate

**Summary:** The final gate has strong isolation and evidence requirements. The principal weakness is that the clean-clone source is underspecified: cloning the remote `master` may omit locally committed but unpushed phase work, while cloning the current repository proves local committed state but not the remote release candidate. The plan must name which is authoritative.

**Strengths:**
- Sandboxing `HOME` is necessary because the installer hardcodes `$HOME/.local/bin` (`scripts/install.sh:59`).
- Unsetting `CLAUDE_CONFIG_DIR` is also necessary because it takes precedence in the generated registry path (`scripts/install.sh:157`).
- Wrapper existence, executable bits, and marker checks directly exercise `write_wrapper` (`scripts/install.sh:126`, `:206`).
- `--help` is the right network-free execution smoke test; both scripts still require `agy` to resolve before parsing arguments (`scripts/agy_bridge.sh:20`, `scripts/gemini_shim.sh:548`).
- Excluding `contract-check.sh` from the release gate matches the roadmap's explicit third-party-outage policy.
- Ticket closures are delayed until fix evidence and the fresh-install gate exist.
- The human checkpoint appropriately leaves tagging and publishing out of scope.

**Concerns:**
- HIGH — "Clone the repository" does not define the release candidate. The configured remote is GitHub, while earlier plans create local commits. If those commits have not been pushed, `git clone https://…` tests stale remote master. If the executor clones the local path, it tests committed local master but not what is remotely available for shipping. Either interpretation can produce a misleading pass.
- MEDIUM — The real `~/.local/bin` mtime assertion is overbroad. Requiring no file in the entire directory to have an mtime during the task can fail because of unrelated activity and does not directly compare the two launchers at risk.
- MEDIUM — Cleanup before dossier creation can lose diagnostic artifacts. The task says to paste full output and then delete the scratch tree. The script must copy logs or emit them before deletion even on failure.
- MEDIUM — The plan closes tickets before the human sign-off. If the reviewer rejects a criterion, the tickets remain closed unless the workflow explicitly reopens affected tickets.
- LOW — Requiring real `agy` merely for `--help` is inherited behavior, not evidence of live integration. The plan explains this correctly, but the dossier should avoid describing it as a real-agy execution proof.
- OPEN QUESTION — Beads verification could not be checked live in this read-only environment.

**Suggestions:**
- Define the clone source explicitly: clone the local repository at the exact reviewed `master` SHA for the pre-push release gate, record that SHA, then after push have the ship workflow verify remote `master` resolves to that same SHA.
- Snapshot only `~/.local/bin/agy-bridge` and `~/.local/bin/gemini` before and after, including absence, inode/size/hash, and mtime.
- Use a cleanup trap that preserves or emits logs before deleting scratch state.
- Either defer ticket closure until human sign-off or require reopening affected tickets automatically if any criterion is rejected.
- Record suite exit codes as well as summary strings.

**Risk assessment:** MEDIUM-HIGH. The isolation is excellent, but the unspecified clone authority can invalidate the central "test what will ship" claim.

### Phase-level recommendations (Codex)

Before approving execution:
1. Revise 06-01 so `RB30` is explicitly an ordering proof, not sufficient evidence of the historical flake's production root cause.
2. Fix 06-03's empty-model fixture so model-path stderr can actually be asserted.
3. Define the exact source and SHA cloned by 06-06.
4. Strengthen 06-05's external-kill content check.
5. Decide whether ticket closure occurs before or after human sign-off, and specify rollback/reopen behavior.

With those changes, the overall phase risk drops from HIGH to MEDIUM-LOW. The implementation changes themselves are small; most remaining risk lies in whether the proposed evidence proves the claims used to authorize release.

---

## Antigravity Review

### 1. Summary

Phase 06 is an exceptionally well-specified, rigorous bug-fix and release-gate phase that resolves all 8 outstanding issues (`delegate-agy-ltf`, `-u1z`, `-d4t`, `-b7g`, `-sup`, `-rod`, `-xfa`, `-i43`) across 6 plans (06-01 through 06-06) organized into 5 serial execution waves. Every proposed change directly targets a verified defect or structural gap in the pure-Bash wrapper codebase without introducing unnecessary abstractions or external dependencies. All code modifications have been verified against the physical repository files, confirming that the cited line numbers, AST patterns, variable names, and control flows match ground truth. The testing discipline (task-level TDD, deterministic signal injection in `RB30`, and structural cross-file guards in `IN02` and `RB01`) ensures verifiable verification before and after each change.

### 2. Strengths

- **Surgical, Zero-Abstraction Bug Fixes Grounded in Concrete Code**:
  - D-04 / `delegate-agy-ltf` (`scripts/gemini_shim.sh:568-574`): Changing the catch-all shift logic to a single `shift` correctly prevents token-stealing for prompts following unknown long options. The plan verified that all legitimately value-taking options are already handled by explicit branches earlier in the `case` statement (`scripts/gemini_shim.sh:509-538`), making an allowlist redundant.
  - D-07 / `delegate-agy-b7g` (`scripts/agy_bridge.sh:480-550`): Correctly identifies that exiting directly within the fetch `if/elif` block would bypass the unconditional `agy` stderr passthrough at `scripts/agy_bridge.sh:530`. Deferring the exit via `_agy_degraded_no_cache=1` to the single choke point at line 537 preserves diagnostic stderr while emitting the actionable degraded message and maintaining exit code 2.
- **Robust Root-Cause Resolution for Intermittent Flakes**:
  - D-08 / `delegate-agy-sup`: Moving `trap - TERM INT HUP` and the `eval "${rb_trap_*:-}"` restores *before* `_rb_cancel_timer` eliminates the window where an asynchronous signal or timer-teardown signal lands on `_rb_relay`'s `exit "$2"` handler (`scripts/agy_bridge.sh:215-221`) after the child has already exited. Plan 06-01 mandates `RB30` as a deterministic forcing test rather than relying on non-deterministic test repetitions.
- **Byte-Identity and Multi-File Synchronization Discipline**: The plan accounts for all three locations where the `# --- BEGIN run_bounded ---` block is maintained (`agy_bridge.sh:103-359`, `gemini_shim.sh:122-378`, `tests/contract-check.sh:152-408`), preserving compliance with `RB02`'s cross-file byte-equality assertion.
- **Scanner Integrity Preservation**: D-06 / `delegate-agy-d4t` — instead of adding allowlists or bypass comments to `RB01`'s AST scanner, the plan correctly restructures the 7 preflight guards in `tests/contract-check.sh` (lines 527, 565, 600, 644, 698, 829, 1008) to use `_CC_NO_AGY`, allowing `contract-check.sh`'s 4 actual invocation sites (535, 548, 742, 1059) to be strictly validated without false positives.
- **Defensive Release Gate & Isolation Sandbox**: Plan 06-06 uses a disposable clone and an isolated sandbox (`env -u CLAUDE_CONFIG_DIR HOME=<throwaway>`), preventing contamination of the operator's real `~/.local/bin` and avoiding spurious `exit 127` errors caused by registry mismatches against `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json` (`scripts/install.sh:157`).

### 3. Concerns

- **[LOW] `_agy_degraded_no_cache` Flag Scope Under `set -u`** (`scripts/agy_bridge.sh:481-537`): In plan 06-03, `_agy_degraded_no_cache=1` is set in the `else` branch of the fetch block under `set -euo pipefail`. If the cache hit path is taken, or the model fetch branch is skipped/fails, the flag is unset. The plan specifies `[[ "${_agy_degraded_no_cache:-0}" -eq 1 ]]` at line 537, which is safe under `set -u`. However, any other evaluation of the variable without the `:-0` default would abort execution. Severity LOW — the plan specifies the safe syntax explicitly.
- **[LOW] Scope of `_CC_NO_AGY` in `tests/contract-check.sh:413`**: Computed once immediately after `AGY_BIN` resolution. If any future subshell or function were to modify `PATH` or re-detect `AGY_BIN`, the flag would go stale. Tracing confirms `AGY_BIN` is never modified or shadowed today, so the assumption is sound for all existing check functions.
- **[LOW] Stale `agy` Version Citation in README prose** (`README.md:143`): Documentation refers to validation against `agy 1.1.13`, whereas current development host environments report `agy 1.1.17`. Does not block functionality or test passes, but may cause cosmetic confusion during manual verification.

### 4. Suggestions

1. **Verify `_agy_degraded_no_cache` Initialization**: In `scripts/agy_bridge.sh:481`, initialize `_agy_degraded_no_cache=0` alongside `_agy_err` before the fetch block, guarding against any future unquoted/undefaulted reference under `set -u`.
2. **Deterministic Process Group Signaling in `RB30`**: When authoring `RB30`, ensure the mock shadow for `_rb_cancel_timer` explicitly targets `kill -TERM "$$"` (or `$timer_pgid` where applicable) with a re-entrancy guard variable (`_RB30_TRIGGERED=1`) so subsequent calls to `_rb_cancel_timer` from inside `_rb_relay` do not enter an infinite loop.
3. **Explicit Version Notation in Release Notes**: When appending the `### 1.6.2` release notes (`README.md:408`, plan 06-05 Task 2), ensure the re-run requirement prominently highlights that `~/.local/bin/agy-bridge` and `~/.local/bin/gemini` must be repinned because the wrappers execute an absolute immutable path pinned at install time (`scripts/install.sh:206-207`).

### 5. Risk Assessment

- **Overall Risk Level: LOW**
- **Justification**: All 6 plans address bounded, well-understood defect mechanisms. No external packages or framework rewrites are introduced. The test harness is executed at each task boundary, maintaining `FAIL=0` and verifying both `watchdog` and `coreutils` execution paths. The plan sequence strictly respects inter-task dependencies and enforces thorough human validation prior to tag generation.
