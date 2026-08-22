---
task: 260822-m01-remove-tokensave-from-the-plugin-complet
verified: 2026-08-22T14:52:01Z
status: passed
score: 7/7 must-haves verified
behavior_unverified: 0
overrides_applied: 0
---

# Quick Task 260822-m01: Remove tokensave from the plugin, completely — Verification Report

**Task Goal:** Remove tokensave plugin completely, including FORBIDDEN-catch-all mentions — user explicitly overturned the plan's original D-02 tradeoff proposal to keep those; confirmed instruction: "catch-all mentions gone too."
**Verified:** 2026-08-22T14:52:01Z
**Status:** passed

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `install.sh` never writes to `~/.gemini/antigravity-cli/mcp_config.json`; it only READS it to detect lean-ctx | ✓ VERIFIED | `scripts/install.sh:263-283` — `AGY_MCP_CFG` used only inside `python3 - "$AGY_MCP_CFG"` read (`json.load(open(p))`), never opened for write. Confirmed by test `I9` (fixture pre-seeds the file, runs install with the retired opt-in env var set, asserts `_ORIG == $_NOW`, no `.bak-agy-*`, no `.mcp_config.*` temp file) — `ok`. |
| 2 | `AGY_SETUP_REGISTER_TOKENSAVE=1` / `AGY_UNINSTALL_TOKENSAVE=1` are inert — setting them changes nothing | ✓ VERIFIED | Neither string appears anywhere in `scripts/install.sh`, `scripts/uninstall.sh`, or `scripts/agy_bridge.sh` (`grep -c -i tokensave` = 0 in all three) — the vars are simply unreferenced, so `set -u` bash cannot even see them. Test `I9` sets `AGY_SETUP_REGISTER_TOKENSAVE=1` in the install env and asserts no config mutation — `ok`. |
| 3 | `install.sh` still writes the availability hint `~/.config/agy-delegate/config.json`, now with exactly one key: `lean_ctx` | ✓ VERIFIED | `scripts/install.sh:287-294` — `json.dump({"lean_ctx": lc}, ...)`, single key. Test `I11 "availability hint carries exactly the lean_ctx key"` — `ok`. |
| 4 | `uninstall.sh` removes that hint unconditionally (no env flag) and never touches the agy MCP config | ✓ VERIFIED | `scripts/uninstall.sh:59-65` — unconditional `if [[ -f "$HINT" ]]; then rm -f "$HINT"; ...`, no `AGY_UNINSTALL_TOKENSAVE` check, no reference to any MCP config path anywhere in the file. Test `I13b "uninstall removes the availability hint"` — `ok`. |
| 5 | `agy_bridge.sh` still appends the TOOL PREFERENCE stanza for code/review/analysis/implement when lean-ctx is available, and omits it when it is not | ✓ VERIFIED | `scripts/agy_bridge.sh:707-711` — gated on `[[ "$TYPE" ... && "$_MCP_LEANCTX" == "1" ]]`, appends `TOOL PREFERENCE: lean-ctx (ctx_read/ctx_search)...` text only, no tokensave alternative branch. Test `SH1 "shim never appends TOOL PREFERENCE stanza"` and the bridge-side positive-path tests pass — `ok`. |
| 6 | FORBIDDEN-catch-all lines in all 4 gated policy files name no retired server (`tokensave`) and are byte-identical across files | ✓ VERIFIED | `grep -h "allowlist catch-all" config/policies/*.md` returns 4 byte-identical lines reading `...This includes every lean-ctx ctx_* tool (...), the ctx_call gateway (...), and any mcp__* tool...` — zero mention of tokensave. Tests `ST1` (byte-identical across search+shim policies), `ST2` (catch-all covers ctx_call+mcp__, names no retired server), `ST3` (PERMITTED lists in code/review-analysis/implement never mention tokensave) — all `ok`. |
| 7 | `bash tests/run-tests.sh` exits 0 with FAIL=0 | ✓ VERIFIED | Full suite run in this verification session: `PASS=164 FAIL=0`, script exit code `0`. |

**Score:** 7/7 truths verified (0 present-but-behavior-unverified)

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `scripts/install.sh` | No tokensave registration path; read-only MCP-config detection; single-key hint writer | ✓ VERIFIED | Confirmed by direct read + grep (0 tokensave hits) + passing `I9`/`I11` tests |
| `scripts/uninstall.sh` | No tokensave de-registration path; unconditional hint removal | ✓ VERIFIED | Full file read; unconditional `rm -f "$HINT"`; 0 tokensave hits |
| `scripts/agy_bridge.sh` | TOOL PREFERENCE stanza references only lean-ctx | ✓ VERIFIED | 0 tokensave hits; gating logic reads only `_MCP_LEANCTX` |
| `config/policies/*.md` (7 files) | FORBIDDEN catch-all mentions no `tokensave`/`mcp__tokensave__*` names | ✓ VERIFIED | `grep -rn tokensave config/` → empty; catch-all line text confirmed generic (`ctx_*`, `ctx_call`, `mcp__*` only) |
| `agents/agy-delegate-code.md` | `tools:` frontmatter list drops `mcp__tokensave__tokensave_context` | ✓ VERIFIED | Diff shows exact removal, remaining tools list intact (`Bash, Read, Grep, Glob, Edit, Write, mcp__lean-ctx__ctx_shell, mcp__lean-ctx__ctx_read, mcp__lean-ctx__ctx_search`) |
| `README.md`, `config/provider.md`, `.claude/commands/agy-setup.md` | Prose no longer documents tokensave opt-in flags/registration | ✓ VERIFIED | Diffs show `AGY_SETUP_REGISTER_TOKENSAVE`/`AGY_UNINSTALL_TOKENSAVE` doc lines and the `tokensave_*`/mcp__tokensave catch-all mention removed |
| `.gitignore` | Stray `.tokensave/` ignore rule removed | ✓ VERIFIED | Diff: `-.tokensave/` line removed, no other change to file |
| `.claude/settings.local.json` | Local MCP-server entry for tokensave removed (gitignored, untracked) | ✓ VERIFIED | File exists, valid JSON, 0 tokensave references, confirmed untracked (`git ls-files` empty) and gitignored (`git check-ignore` matches `.gitignore:24`) |
| `tests/run-tests.sh` | New/retargeted tests (ST1-3, I9, I11, I13b, SH1, etc.) enforce absence; retired-name test fixture vars kept only as literals to check against | ✓ VERIFIED | All named tests present and passing; retired-name vars (`_ST2_RETIRED_TOOL`, `_ST3_RETIRED_TOOL`, `_I9_RETIRED_BIN`, `_I9_RETIRED_ENV`) are documented fixture-only residuals per task exemption list |
| `.claude/commands/agy-uninstall.md` | Breadcrumb sentence pointing users who previously opted into tokensave to manual cleanup | ✓ VERIFIED (documented residual) | Line 20: "If you previously registered `tokensave`..." — this is the explicitly exempted D-05 breadcrumb, not a leftover artifact |

### Full-Repo Residual Scan

`grep -rniE 'tokensave' --include='*.md' --include='*.sh' --include='*.json' .` (excluding `.planning/`, `.wolf/`, `.git/`, `docs/superpowers/specs/`) returns exactly 5 lines, all in the documented-exemption list:

```
.claude/commands/agy-uninstall.md:20   (D-05 breadcrumb sentence)
tests/run-tests.sh:1119  _ST2_RETIRED_TOOL="tokensave_"     (RETIRED-named test fixture var)
tests/run-tests.sh:1129  _ST3_RETIRED_TOOL="tokensave"      (RETIRED-named test fixture var)
tests/run-tests.sh:4206  _I9_RETIRED_BIN="tokensave"        (RETIRED-named test fixture var)
tests/run-tests.sh:4207  _I9_RETIRED_ENV="AGY_SETUP_REGISTER_TOKENSAVE=1"  (RETIRED-named test fixture var)
```

No other match anywhere in tracked source, docs, config, or `.json` files. `find . -iname '*tokensave*'` (excluding `.git`) finds no stray files/directories.

### Requirements Coverage

Not applicable — this is a quick task (no `requirements:` frontmatter linkage to `.planning/REQUIREMENTS.md`).

### Anti-Patterns Found

None. No `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/`PLACEHOLDER` markers introduced in the modified files. No empty stub implementations.

### Behavioral Spot-Checks / Test Execution

| Check | Command | Result | Status |
|---|---|---|---|
| Full test suite | `bash tests/run-tests.sh` | `PASS=164 FAIL=0`, exit 0 | ✓ PASS |
| Tokensave-specific tests (ST1-3, I9, I11, I13b, SH1) | grep of suite output | all lines prefixed `ok` | ✓ PASS |
| No tracked file contains tokensave outside exemptions | `git grep -niI tokensave` minus exemptions | empty | ✓ PASS |
| `.claude/settings.local.json` clean, untracked, gitignored | `git check-ignore` / `git ls-files` / grep | confirmed | ✓ PASS |

### Human Verification Required

None — every must-have was verifiable by direct file inspection, grep, and a full deterministic test-suite run.

### Gaps Summary

No gaps. The task's own must-haves (full removal including FORBIDDEN-catch-all mentions, per the user's override of the plan's original D-02 tradeoff) are satisfied everywhere except the two explicitly pre-approved residual classes (D-05 breadcrumb sentence, RETIRED-named test fixture variables), both of which exist solely to assert the absence of tokensave, not to reintroduce it.

---

_Verified: 2026-08-22T14:52:01Z_
_Verifier: Claude (gsd-verifier)_
