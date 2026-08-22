# Testing Patterns

**Analysis Date:** 2026-08-18

Source examined: git worktree `/home/dd/Gemini/delegate-agy/.worktrees/agy-1.6.2` (branch `fix/agy-bridge-resilience`). No test framework — hand-rolled bash. This document was produced by reading the suite, not running it (the suite takes minutes by design and invokes a fake `agy`; the real `agy` binary hangs and must never be invoked).

## Test "Framework"

There is no framework, no runner dependency, no assertion library. Two independent, self-contained bash scripts implement their own PASS/FAIL bookkeeping and print a final summary line, exiting 0 iff all cases passed:

- `tests/run-tests.sh` (1598 lines) — the main suite: `agy_bridge.sh`, `gemini_shim.sh`, `install.sh`, `uninstall.sh`, and policy/doc consistency checks.
- `tests/hooks/run-hook-tests.sh` (485 lines) — SubagentStart hook tests, a separate, differently-shaped harness (`run_case name cmd stdin_json expected_exit matcher`).

**Run commands** (do not actually execute — see Rules below; documented for reference only):
```bash
bash tests/run-tests.sh          # ~88 cases, several deliberately slow (hang-detection tests)
bash tests/hooks/run-hook-tests.sh
```

## `tests/run-tests.sh` — Structure

**Sandbox setup** (`tests/run-tests.sh:37-46`):
```bash
SANDBOX="$(mktemp -d -t agy-tests.XXXXXX)"
trap cleanup EXIT   # rm -rf "$SANDBOX"
mkdir -p "$SANDBOX/bin" "$SANDBOX/home"
cp "$HERE/fake-agy.sh" "$SANDBOX/bin/agy"; chmod +x "$SANDBOX/bin/agy"
export PATH="$SANDBOX/bin:$PATH"
export HOME="$SANDBOX/home"
```
`agy` on `$PATH` for the rest of the run resolves to `fake-agy.sh`. `$HOME` is sandboxed once, globally, for the entire script — **not per-test**. This is the harness's biggest trap for a new contributor (see "Shared HOME" below).

**Bookkeeping primitives** (`tests/run-tests.sh:48-73`):
```bash
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'ok   - %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL - %s\n' "$1"; [[ $# -ge 2 ]] && printf '       %s\n' "$2"; }

_run() {  # _run OUTVAR RCVAR cmd...
    local __outvar="$1" __rcvar="$2"; shift 2
    local __out __rc
    __out="$("$@" 2>&1)"; __rc=$?
    printf -v "$__outvar" '%s' "$__out"
    printf -v "$__rcvar" '%s' "$__rc"
}
```
Each test case is a flat block: set env vars, call `_run OUT RC bash "$SCRIPT" ...`, then an `if [[ ... ]]; then ok "..."; else bad "..." "detail"; fi`. There is no setup/teardown hook, no fixture registration, no table-driven macro — every case is copy-pasted and adapted. Exit status: `PASS=$PASS FAIL=$FAIL` printed, `exit 0` iff `FAIL -eq 0` (`tests/run-tests.sh:1592-1598`).

**Test ID prefixes** (the suite's real vocabulary — use these prefixes for new cases in the same area):

| Prefix | Area | Example |
|---|---|---|
| `B*` | `agy_bridge.sh` basics (success passthrough, hidden-failure, JSON envelope) | B1-B4 |
| `S*` | `gemini_shim.sh` basics + static/config guards (also reused for ST-prefixed policy/doc checks) | S1-S8, ST1-ST6 |
| `R*` | Dynamic model resolution (bridge) | R1-R8 |
| `D*` | `--digest` output contract | D1-D4 |
| `T*` | Prompt-delivery contract + timeout/kill semantics (bridge) | T1-T5, T3b-T3e |
| `AD*` | `--add-dir` passthrough and broad-grant guards | AD1-AD8 |
| `M*` | MCP tool-preference stanza gating | M1-M3 |
| `SH*` | shim-specific: sandbox floor, unbounded-call bounding, dynamic model resolution | SH1-SH14 |
| `I*` | installer/uninstaller (`install.sh`/`uninstall.sh`) | I1-I18 |

Numeric suffixes with letters (`T3b`, `AD3`, `I8b`, `I9b`, `I13b`, `I16`/`I17` sub-cases `(a)`-`(h)`) denote a variant/edge case of the base test, not a separate area — follow this suffix convention rather than inventing a new prefix for a close variant.

**Suite-state comment** (`tests/run-tests.sh:26-27`): "SUITE STATE: fully GREEN. New cases must keep the suite green; no assertion may be weakened to pass early." Treat any existing assertion as fixed unless the underlying behavior is deliberately changing.

## `tests/fake-agy.sh` — the Vocabulary of Simulated `agy` Behaviors

`fake-agy.sh` (169 lines) is a deterministic stand-in for the real `agy` binary, driven entirely by env vars read at invocation time (never a config file). It models agy's real (>=1.1.1) prompt-delivery contract: the prompt is **not** read from stdin or passed as `--print`'s value — it is embedded by the caller in a `GEMINI.md` file's `TASK:` section, inside the directory named by the **last** `--add-dir` argument (`tests/fake-agy.sh:4-10`). This is the exact contract `agy_bridge.sh` and `gemini_shim.sh` implement; the fixture is a spec as much as a stub.

Full catalogue of env-var controls (all optional; behavior with none set: `models` → 8 canned model ids; `--version` → `agy 0.0.0-fake`; `--print` → succeeds with empty stdout unless `FAKE_AGY_STDOUT` is set):

| Env var | Effect | Applies to |
|---|---|---|
| `FAKE_AGY_EXIT` | Exit code for a `--print` run (default 0) | `--print` |
| `FAKE_AGY_STDOUT` | Bytes written to stdout | `--print` |
| `FAKE_AGY_STDERR` | Bytes written to stderr | `--print` |
| `FAKE_AGY_ECHO_PROMPT=1` | Instead of the STDOUT/STDERR/EXIT triple, echoes only the extracted `TASK:` text (including any appended digest contract) — lets a test assert exactly what the wrapper embedded | `--print` |
| `FAKE_AGY_DUMP_ARGV=<path>` | Writes the full argv (one per line) to `<path>` before any other behavior; purely observational, never changes behavior | any subcommand |
| `FAKE_AGY_MODELS_HANG=1` | `agy models` traps `SIGTERM` (`trap '' TERM`) and sleeps 300s — only `timeout -k` (SIGKILL) ends it | `models` |
| `FAKE_AGY_PRINT_HANG=1` | Same hang behavior on the `--print` path | `--print` |
| `FAKE_AGY_VERSION_HANG=1` | Same hang behavior on `--version` | `--version` |
| `FAKE_AGY_PRINT_KILL9=1` | Exits 137 immediately (well inside any `--timeout` bound) — simulates an external SIGKILL (OOM/manual `kill -9`/cgroup preemption), distinct from the wrapper's own `-k` escalation | `--print` |
| `FAKE_AGY_MODELS_FAIL=1` | `agy models` exits 1 with `FAKE-AGY-AUTH-FAILURE: not authenticated` on stderr | `models` |
| `FAKE_AGY_MODELS_GARBAGE=1` | `agy models` exits 0 but with no `gemini-` ids in output (degraded/unauthenticated agy simulation) | `models` |

Real `agy models` output format modeled at `tests/fake-agy.sh:79-87`: `id<TAB>display name` per line, e.g. `gemini-3.6-flash-high\tGemini 3.6 Flash (High)`.

Argv parsing inside the fixture (`tests/fake-agy.sh:120-140`) understands the real `agy` flag set: `--print <value>`, `--add-dir`/`--include-directories <dir>` (repeatable, last wins for `GEMINI.md` resolution), `--model <value>`, `--sandbox`, `--dangerously-skip-permissions`. `fail_empty_prompt()` (`tests/fake-agy.sh:141-144`) reproduces agy's real error message verbatim: `Error: Error: empty prompt. Usage: agy --print "your prompt here"`.

**When adding a new simulated `agy` failure mode**, add a new `FAKE_AGY_*` env var following this table's naming (`FAKE_AGY_<SUBCOMMAND>_<MODE>` or `FAKE_AGY_<MODE>` if cross-subcommand), document it in the header comment block, and keep it read-only/observational unless it's explicitly meant to change output.

## Harness Mechanics a Contributor Will Trip Over

**1. `set -u`, never `set -e`.** (`tests/run-tests.sh:28`, `tests/hooks/run-hook-tests.sh:29`) Most test bodies deliberately invoke a script expected to fail — `set -e` would abort the whole runner on the first such call. Do not add `set -e` when extending either file.

**2. Shared `$HOME` across the entire run — not per-test.** `$HOME` is exported once at `tests/run-tests.sh:46` and never re-scoped for the remainder of the script. Both `agy_bridge.sh` and `gemini_shim.sh` cache the live model list at `$HOME/.cache/agy-bridge-models` and MCP-detection state at `$HOME/.cache/agy-bridge-mcp`. A test that seeds a fake cache file and doesn't clean it up will corrupt every *later* test that expects a fresh fetch. The suite handles this explicitly and repeatedly — grep any test around R3/R3c/R6/R8/SH7-SH11 and note the `rm -f "$_*_CACHE"` immediately after the assertion, e.g.:
```bash
_R3_CACHE="$HOME/.cache/agy-bridge-models"
printf '%s\n' "gemini-3.1-pro-high" > "$_R3_CACHE"
FAKE_AGY_STDOUT="ok" _run OUT RC bash "$BRIDGE" --type search
if [[ "$RC" -eq 2 && "$OUT" == *"no gemini model"* ]]; then ok "R3 ..."; else bad "R3 ..." "..."; fi
rm -f "$_R3_CACHE"   # <-- mandatory: later tests (D1-D4/T1-T3/M1-M3) need the full model list
```
**Any new test that writes to `$HOME/.cache/*` or `$HOME/.config/*` must `rm -f`/restore it before returning**, or every test that runs after it in file order will see corrupted state. The MCP-stanza block (M1-M3/SH1) goes further and saves/restores the pre-existing hint+cache files via a trap (`tests/run-tests.sh:734-738`) because those files may legitimately pre-exist outside the test run.

**3. `_run` merges stderr into stdout.** (`tests/run-tests.sh:65-73`: `__out="$("$@" 2>&1)"`) An assertion using `_run` cannot distinguish stdout from stderr — `$OUT` is both, concatenated. Most cases don't need to (they check for a substring or an exact combined match), but any case that *must* prove something reached (or did NOT reach) stdout specifically — e.g. "a JSON envelope on stdout must never carry a WARNING string that could corrupt a machine parser" — captures the two streams **separately**, bypassing `_run` entirely:
```bash
# SH9 (tests/run-tests.sh:900-916): stdout and stderr captured to separate files
bash "$SHIM" -m zzz-unknown-model -p x > "$SH9_OUT" 2> "$SH9_ERR"
RC=$?
grep -q 'ok' "$SH9_OUT" && grep -q 'WARNING' "$SH9_ERR" && ! grep -q 'WARNING' "$SH9_OUT"
```
Follow this split-capture pattern (`cmd > out 2> err; rc=$?`) whenever a new assertion needs to tell the two streams apart — `_run` is not adequate for that class of test.

**4. Some tests take minutes by design — the defect under test IS a hang.** Cases like T4, T5, R5, SH4, SH5, SH11, SH13 deliberately drive `fake-agy.sh` into a `trap '' TERM; sleep 300` hang to prove the wrapper's `timeout -k` escalation actually fires (a plain `timeout` would leave the runner blocked for the fixture's full 300s sleep — see the SH11 comment at `tests/run-tests.sh:940-948`). These cases wrap the invocation in an outer `timeout 30 bash "$SHIM" ...` so a *regression* to unbounded fails the suite in ~30s instead of stalling ~300s, and assert `_ELAPSED -lt N` in addition to exit code/output, so a slow-but-eventually-correct escalation still fails the test. This is why the suite as a whole is documented as taking minutes; do not attempt to "speed up" these cases by removing the outer bound or shortening the sleep in the fixture — both are load-bearing for what's being proven.

**5. Installer tests execute the generated wrapper, not just the generator.** `_fresh_home()` (`tests/run-tests.sh:1035-1041`) creates an isolated `$h` with its own `bin/agy` (copy of `fake-agy.sh`) and `.local/bin`; `_install_in()` (`tests/run-tests.sh:1044-1049`) runs `install.sh` under `env -i HOME="$h" PATH="$h/bin:$h/.local/bin:/usr/bin:/bin" AGY_PLUGIN_DIR="$ROOT" ... bash "$INSTALL"` — a *fully* isolated environment (`env -i`), not merely a different `$HOME` inside the parent shell's environment. Tests then invoke the generated `~/.local/bin/agy-bridge` wrapper directly (again under a matching `env -i`) and assert on its real behavior — e.g. I1 (`tests/run-tests.sh:1051-1068`) checks the wrapper file's content (marker string, no `plugins/cache` glob, no `claude plugin list` call) **and** actually runs it (`bash "$IH/.local/bin/agy-bridge" --types`) to confirm it execs correctly. I16/I17/I18 go further, mutating the generated wrapper's `_AGY_TARGET=` line or fabricating a stale-version registry file and re-running the wrapper to prove fail-loud/silent-degrade behavior end-to-end. This is a deliberate, valuable choice over grepping the generator's source: it catches quoting bugs (I18's apostrophe-in-path case) and exec-target bugs that a static grep of `install.sh` would miss.

## `tests/hooks/run-hook-tests.sh` — Separate, Simpler Harness

Different shape from the main suite, purpose-built for hook scripts that take a JSON payload on stdin and emit either nothing or hook-protocol output:

```bash
run_case <name> <hook_cmd> <stdin_json> <expected_exit> <matcher>
```
- `<hook_cmd>` is invoked via `eval` (`tests/hooks/run-hook-tests.sh:74`: `eval "$hook_cmd"`), so it may be a bare path or a command string with args.
- `<matcher>` is one of `empty` (stdout must be exactly `""`) or `contains:SUBSTR` (`tests/hooks/run-hook-tests.sh:38-52`).
- The harness includes a self-check that verifies the harness itself can detect a failing assertion, isolated from the real suite counters (`tests/hooks/run-hook-tests.sh:27-29`) — a rubber-stamp harness (one that always reports PASS regardless of actual behavior) cannot satisfy it.

## What Is Asserted, Not Just "It Runs"

Recurring assertion shapes worth reusing for new cases:
- **Negative-space assertions**: proving a token/flag is *absent* from a log, not just that the expected value is present — e.g. T1/S8 assert a leaked prompt token is absent from both an argv-dump log and a stdin-dump log, using a `PATH`-shadowing `agy` recorder script written inline in the test (`tests/run-tests.sh:415-441`).
- **Exact-match, not substring, when a leaking diagnostic would otherwise pass**: AD2 (`tests/run-tests.sh:556-567`) asserts the *exact* error string, specifically because a substring match would not catch a `cd`'s own "No such file or directory" line leaking to stderr if the `2>/dev/null` guard were dropped.
- **Elapsed-time bounds combined with exit code and message**, for every hang/kill case (see point 4 above) — never assert exit code alone for a timeout/kill test.
- **Byte-identical passthrough** for the "should be untouched" path (D3: `"$OUT" == "$BIGREPLY"`), alongside the corresponding "should be transformed" path (D2) for the same input shape.

## `tests/hooks/run-hook-tests.sh` Test Cases (wu3-01 through wu3-15b, 28 cases)

Cases exercise `hooks/agy-subagent-policy.sh` directly, one `run_case` per guard/behavior:
- **Disabled/env-gating** (wu3-01x): `agy_hooks_enabled` false path — empty stdout, exit 0, no python3 fork observed.
- **Malformed/empty payload** (wu3-02x, wu3-03x): empty stdin, non-JSON stdin — each asserts empty stdout and the specific debug reason via `AGY_HOOKS_DEBUG=1`.
- **Allowlist gating** (wu3-05x through wu3-08x): `agent_type` present/absent/allowed/disallowed combinations against `agy_hooks_agent_allowed`, using `WU3_STUB_DIR`'s `agy-bridge` stub to isolate from the real bridge.
- **No-bridge-on-PATH** (wu3-09x): `agy-bridge` absent from `PATH` — silent skip with its own debug reason.
- **python3-absence/brokenness** (wu3-10x, wu3-14): `WU3_NOPY_DIR`/`WU3_TOUCHPY_DIR` shadow `python3` with a missing or non-functional stub to prove guard 2 fires before guard 4 (misreport-prevention regression test).
- **Guard-ordering regression** (wu3-15, wu3-15b): asserts guard 1 (bash-only enabled check) short-circuits before any python3 fork, and guard 2 before guard 4 — directly protects the ordering convention documented in CONVENTIONS.md.
- **Prompt/payload leak check** (uses a `PROMPTSENTINEL_ZZZ` marker in the injected payload): asserts the sentinel never appears in the hook's stdout, proving the advisory emission path never echoes payload content.
- **Byte-exact advisory assertion** (wu3-12): the one all-guards-pass case; re-verifies the emitted advisory against the hook source's literal string using a *separate temp-file-argument* python3 invocation rather than a second heredoc-over-stdin, specifically to avoid a heredoc-vs-stdin collision with the harness's own `eval "$hook_cmd"` invocation plumbing.

A reader changing `agy-subagent-policy.sh`'s guard order, debug-reason strings, or the advisory text will break wu3-12 (byte-exact) and wu3-15/15b (ordering) first.

---

*Testing analysis: 2026-08-18*
