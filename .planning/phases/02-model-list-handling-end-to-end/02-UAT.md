---
status: testing
phase: 02-model-list-handling-end-to-end
source: [02-VERIFICATION.md]
started: 2026-08-20T15:11:01Z
updated: 2026-08-20T15:11:01Z
---

## Current Test

number: 1
name: Zero-byte `agy models` reply is gated identically to a non-empty degraded reply
expected: |
  Add a `fake-agy.sh` mode (or a one-off harness) where the `models` subcommand exits 0 with truly
  empty stdout (no lines at all, not even the two-line `FAKE_AGY_MODELS_GARBAGE` text), then run it
  through both `scripts/agy_bridge.sh` and `scripts/gemini_shim.sh` with a stale cache present and
  then absent. Expected: same outcome as R9b/SH15b (degraded-with-cache: falls back
  silently/with-warning, cache untouched) and R9/SH15 (degraded-without-cache: nothing written).
awaiting: user response

## Tests

### 1. Zero-byte `agy models` reply is gated identically to a non-empty degraded reply
expected: Same outcome as R9b/SH15b (degraded-with-cache fallback, cache untouched) and R9/SH15
  (degraded-without-cache, nothing written) — both plans tag this must-have `verification: backstop`
  since no existing fixture produces a genuinely zero-byte, rc=0 `agy models` reply. The gate logic
  (`cut -f1` of an empty string, then `grep -q '^gemini-'`) is the same code path R9/R9b/SH15/SH15b
  already exercise with non-empty degraded input — strong inference, not a behavioral pass.
result: [pending]

## Summary

total: 1
passed: 0
issues: 0
pending: 1
skipped: 0
blocked: 0

## Gaps
