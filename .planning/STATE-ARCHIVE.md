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
