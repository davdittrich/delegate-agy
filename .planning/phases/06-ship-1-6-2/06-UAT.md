---
phase: 06-ship-1-6-2
verified: 2026-08-22T16:02:37Z
status: human_needed
must_haves_verified: 4/4
---

# Phase 06: Ship 1.6.2 — UAT

Automated verification (`06-VERIFICATION.md`) independently re-checked all four ROADMAP.md Success Criteria against the live codebase — not SUMMARY.md claims, not the old dossier's numbers. All 4/4 passed on re-check, including a fresh sandboxed install and a fresh full-suite run performed by the verifier itself (`PASS=165 FAIL=0`, hooks `28/0`).

Two items need your judgment before shipping — neither is a failed truth, both are things a grep can't settle.

## 1. Real-terminal stale-pin check (pre-existing, not new)

The sandboxed install proof (throwaway `HOME`, no plugin registry) structurally cannot exercise `scripts/install.sh`'s stale-pin comparison against your real `~/.claude/plugins/installed_plugins.json`. This was already flagged as open in `06-06-SUMMARY.md`'s "Open for human verification" section — unchanged status, just re-surfaced here since it's still outstanding.

**Action:** In your own terminal, run the installer from the plugin directory per README's `### 1.6.2` re-run notice, then run `agy-bridge --help` and `gemini --help`. Both should exit 0. A `stale <version>` refusal is the check working correctly, not a failure — the fix is to re-run the installer.

## 2. Sign-off timing gap

You signed off on all four release-gate criteria (recorded on `delegate-agy-tmm`, 13:14) at `GATE_SHA=37c9926`. `06-REVIEW.md` — run as part of this `/gsd:ship` attempt — found a real blocker (CR-01) in code that commit still carried, committed at 17:13. You said "fix it"; it landed at 17:46 (`delegate-agy-3bw`, RED `c3bfea3` / GREEN `f02d6ae`, suite green).

The verifier independently re-ran all 4 criteria against the *current* tree (post-fix) and they hold. But the formal sign-off on `delegate-agy-tmm` still names the pre-fix SHA. Whether that record needs a refresh, or your "fix it" instruction already counts as re-authorization for shipping past this point, is your call.

## Recommendation

Given the independent re-verification, I'd read your "fix it" as sufficient — but I'm not deciding this for you.

**Please confirm:** ship as-is, or do you want anything else addressed first (the stale-pin terminal check, a refreshed sign-off note, or something else)?
