# STATE Archive

Pruned entries from STATE.md. Recoverable but no longer loaded into agent context.

## Pruned 2026-08-21 (phases 1-1, kept recent 3)

### Decisions

- [Phase 01.5]: 01.5-01: tracer-feedback gate observed -- committed Task 1, paused for human confirmation of real-agy and absent-binary runs, then proceeded to Task 2/3 after approval
- [Phase 01.5]: 01.5-01: two literal acceptance-criteria shell commands (grep for 'set -euo pipefail' substring; PATH=/nonexistent bash invocation) could not pass/run as literally typed due to D-03's mandated verbatim comment text and bash's own command-prefix PATH lookup semantics -- verified via intent-equivalent checks instead, documented in SUMMARY, no code changed
- [Phase 01.5]: 01.5-01: CC01's sanitized PATH needed an explicit 'timeout' entry beyond the existing _PUREBIN_TOOLS whitelist -- the outer bounding wrapper itself must resolve under CC01's fully-replaced PATH, unlike every other _purebin() caller which keeps the harness's original PATH available for its own outer safety net
- [Phase 01.5]: 01.5-02: CC02 reuses _purebin()'s directory (fake agy present, no timeout/gtimeout by design per RB00a) and composes an external `timeout 30` via `env PATH=...` rather than mutating that shared directory or reusing _run_sanitized's own safety net as the bound
- [Phase 01.5]: 01.5-02: CC03's isolation scan needed a dedicated _cc_raw_segments helper (same split as _rb_agy_segments, without its noise-stripping) because that stripping erases the leading PATH= assignment CC01/CC02's own invocations rely on as their clearing signal -- found live when the scan first ran against the real, correct file
- [Phase 01.5]: 01.5-02: CC03m's mutation payloads are assembled from separator-free arguments joined inside the harness function's own code, not as a literal `;` in a probe's call-site text, because that text is itself part of the file the scan reads
- [Phase 01.5]: 01.5-03: preflight-once design -- agy --version and agy models each called exactly once per run, reused by three probes; agy models requires </dev/null or it hangs indefinitely
- [Phase 01.5]: 01.5-03: invalid-model-rejection derives its verdict from whether agy's rejection names the impossible id WE supplied, never from pinned message text
- [Phase 01.5]: 01.5-04: fake-agy.sh reads tests/fixtures/agy-models.tsv at runtime via _fake_fixture (three-tier resolution: AGY_FIXTURES_DIR, dirname $0/fixtures, $AGY_PLUGIN_DIR/tests/fixtures), loud non-zero on total failure or zero-row fixture -- never a silent empty list (D-14, D-14a)
- [Phase 01.5]: 01.5-04: R2, R4, and CC06 all derive their expected model id via _cc_expect_model (shipped grep|sort -V|tail -1 rule) instead of pinning a literal, so a fixture recapture cannot leave a stale expectation passing silently (D-15a)
- [Phase 01.5]: [Phase 01.5]: 01.5-05: gemini-md-binds (D-10) verified against real agy 1.1.13 with a competing decoy GEMINI.md present -- forbidden run_shell_command declined, cksum discriminator absent, decoy marker did not leak; delegate-agy-xfa updated with evidence, left open for 01.5-06 (D-18) to close
- [Phase 01.5]: [Phase 01.5]: 01.5-05: sigterm-ignored (D-12) contradicted -- real agy 1.1.13 died on SIGTERM alone (rc=124) under a strict 8s bound; R11's -k escalation rationale not reproduced this run; delegate-agy-i43 filed rather than changing run_bounded/R11 in this phase (phase boundary)
- [Phase 01.5]: [Phase 01.5]: 01.5-05: model-arg-accepts aggregates two observations (F6) -- a bare id harvested free from the gemini-md-binds probe's already-billed bridge call, plus a direct display-name call -- keeping the whole run's billed count at 2 (within D-13's budget of 3), both accepted against real agy
- [Phase 01.5]: S5 corrected: README states the verified --model fact (both ids and display names) with agy 1.1.13/2026-08-20; REQUIREMENTS.md moves S5 to Phase 1.5, status met, naming the one contradicted assumption (sigterm-ignored, delegate-agy-i43) plainly

### Performance Metrics

| 01 | 6 | - | - |

## Pruned 2026-08-21 (phases 1-2, kept recent 3)

### Decisions

- [Phase 02]: 02-01: D-03's write gate lives on the fetch-success branch only; the no-cache degraded path leaves `$_agy_models` untouched so the shipped criterion-3 check (now use-time, herestring form under D-08) is what reports the degraded-list message -- clearing it unconditionally would let the generic retrieval-failure fatal fire first and lose R8's distinct message
- [Phase 02]: 02-01: D-08's herestring exception is scoped to exactly two sites in `agy_bridge.sh` (the new write-gate and the existing `:515`-era use-time check) -- a narrow, user-approved carve-out of D-01/D-02's closed-criteria boundary after Codex found the `printf | grep -q` pipe form shares the same SIGPIPE hazard class it was chosen to avoid (reproduced empirically, bash 5.3.15)
- [Phase 02]: 02-01: D-07's stderr relay is relocated (one line moved to fire unconditionally after the whole fetch if/elif/else), not duplicated per branch -- folded into this plan's Task 2 rather than raised as a follow-up bd issue, closing the last open half of criterion 3 in this phase instead of a later one
- [Phase 02]: 02-01: D-06's synthetic 3-column/trailing-tab fixture lives in a scratch `AGY_FIXTURES_DIR`, never in `tests/fixtures/agy-models.tsv` (D-14/D-14a's captured-vs-synthetic separation)
- [Phase 02]: 02-01: S4 (`delegate-agy-8ph`) and S1 both stay "partial" in REQUIREMENTS.md, not "met" -- `8ph` explicitly forbids a one-sided fix, so both requirements close only after plan 02-02 mirrors the same gate/fallback into `gemini_shim.sh`
- [Phase 02]: 02-02: the shim's write gate lives entirely inside `load_models()` -- a new `ids` local (cut -f1-normalized) gates the existing tmp-then-mv write; the D-04 fallback is one `elif [[ -s "$MODELS_CACHE" ]]; then raw=""; fi` on the same if, no new branch, no second cache read
- [Phase 02]: 02-02: unlike the bridge, the shim adds no stderr line on the degraded-fallback path (D-05) -- this script shadows `gemini` on PATH, so a warning here would land in every Octopus/Metaswarm log line; the bridge's D-07 stderr-relocation gap does not apply here since `load_models()`'s fetch already redirects agy's own stderr to `2>/dev/null`
- [Phase 02]: 02-02: D-08's herestring conversion touches exactly two sites in `gemini_shim.sh` -- the new write-gate and the existing `map_model` warning-gate check (formerly a `printf | grep -q` pipe) -- mirroring plan 02-01's identical, narrow D-01/D-02 exception on `agy_bridge.sh`; `map_model`'s verbatim-id and class-resolution matchers are untouched
- [Phase 02]: 02-02: `delegate-agy-8ph` closed -- both writers of `~/.cache/agy-bridge-models` (`agy_bridge.sh` plan 02-01, `gemini_shim.sh` plan 02-02) now carry the write gate, the D-04 stale-cache fallback and atomic-write preservation; S1 and S4 both move to "met" in REQUIREMENTS.md. Suite PASS=141 FAIL=0.

### Performance Metrics

| 02 | 3 | - | - |

## Pruned 2026-08-21 (phases 1-3, kept recent 3)

### Decisions

- [Phase 03]: 03-01: EC_KILL9_TAIL holds only the fixed variable-free tail ' -- possible OOM or external kill', not the whole sentence -- both output forms keep their existing, already-differing prefixes untouched
- [Phase 03]: 03-01: _err_txt is computed once via $(cat "$STDERR_FILE" 2>/dev/null || true) immediately before the plain-text/JSON branch, guarded once via ${_err_txt:+...}, and is the single normalization point both output forms defer to -- the JSON path's open(sys.argv[5]).read() is deleted, not guarded
- [Phase 03]: 03-01: the JSON path's error string is now trailing-newline-stripped (decided behavior change, not a bug fix) -- text\n\n now yields ': text', matching the plain-text arm's pre-existing $(cat ...) behavior
- [Phase 03]: [Phase 03]: 03-02: the shim's EC_KILL9_TAIL mirrors the bridge's literal exactly (not just equivalent wording) so EC03's cross-script comparison is a meaningful byte-identity check, not two independently-written expected strings
- [Phase 03]: [Phase 03]: 03-02: EC05's mutation-red proof (T-03-08) is a manual, git-status-tracked verification of the real file during task execution, not a permanent self-mutating suite case -- matches RB03's own static-provenance shape
- [Phase 03]: [Phase 03]: 03-03: README's exit-124 row quotes both timeout literals as bridge-text-vs-bridge-JSON divergence, not bridge-vs-shim -- the two entry points' TEXT forms are byte-identical
- [Phase 03]: [Phase 03]: 03-03: D-09 exit-2 consistency pass found zero inconsistencies among 25 call sites in agy_bridge.sh; delegate-agy-b7g recorded with explicit left-for-another-phase disposition, no production change
- [Phase 03]: [Phase 03]: 03-04: EC07's cause-fragment exclusivity check is scoped to the bridge's four captured messages (137/124/3/2), not all seven runtime invocations -- the bridge is the only entry point that reaches all four codes
- [Phase 03]: [Phase 03]: 03-04: exit 127 is cited via four source assertions (not two) -- the two Codex-named -eq127 exactness pins plus two more pinning the negative half (-z OUT_STALE / -z RB29_SOUT) that must_haves separately require
- [Phase 03]: [Phase 03]: 03-04: EC07's four self-referential grep patterns use escaped ERE metacharacters so the grep invocation's own source line can never satisfy the pattern it searches for -- verified empirically via an empty detail string
- [Phase 03]: [Phase 03]: 03-04: EC07/EC08 were written in one Edit pass then split into two commits by temporarily removing and re-inserting the EC08 block, preserving per-task bd-id traceability without any destructive git operation
- [Phase 03]: [Phase 03]: 03-04: R5's REQUIREMENTS.md row is closed met but names the integer-second SECONDS-precision ceiling (edge:R5/precision) as a stated residue rather than an implied closure

### Performance Metrics

| 03 | 4 | - | - |
