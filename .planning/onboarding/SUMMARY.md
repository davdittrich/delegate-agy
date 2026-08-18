# Onboarding Summary

## Project State
- PROJECT.md: present
- REQUIREMENTS.md: present
- ROADMAP.md: present
- STATE.md: present

## Codebase Context
- Brownfield repo: **yes** — GSD's own detector reports `is_brownfield: false`, which is wrong. It looks for a package manifest (`package.json`, `pyproject.toml`); this is a pure-bash project with 32 tracked files, 9 shell scripts, and an ~89-test harness. The codebase map was run by forcing it, not because the projection asked for it.
- Map readiness: complete
- Codebase map: complete (7 documents, committed at `67e9a24`)
- Fast map available: no

## Docs Context
- Existing ADR/PRD/SPEC/RFC candidates: 6 — all classified SPEC, all synthesized. 0 blockers, 0 warnings, 4 INFO resolutions, each verified against live code rather than settled by precedence alone.

## What onboarding established

**Scope.** Finish 1.6.2, then close the structural coupling underneath it. Seven phases, 9 requirements, 7 open tickets absorbed.

**Core value.** Delegation must never break the caller. The `gemini` shim shadows the real binary for every process on PATH, so a defect here is not scoped to this plugin.

**The state trap, worth repeating.** `master`'s commit graph contains the 1.6.2 commits; `master`'s files do not. The merge was content-reverted at `a001d0e` rather than history-rewritten. Judge state by reading files, never by `git log` — this misled two subagents and produced three wrong commit counts before it was pinned down.

## Known-imperfect artifacts

Recorded so the next reader knows what to re-check rather than trusting these documents flat:

- **The codebase map was taken against a dirty tree.** Mappers ran while an implementer was mid-edit on `scripts/install.sh`, which produced one wrong attribution (a fix credited to four unrelated commits) that was corrected. `CONCERNS.md` carries a caveat naming the exact commit it describes.
- **`ROADMAP.md` Phase 1, criterion 4 says "four `agy` call sites". There are five.** That count has been wrong three times in three ways — 2, then 4, then 5 — the last because this project's own Task 2 added a site. Any fixed number decays. The durable form is the invariant: no `"$AGY_BIN"` occurrence outside a `$TIMEOUT_BIN` wrapper or a documented fallback, enforced by a test.
- **S5 rests on an unverified hypothesis.** `delegate-agy-62x` raised the id-vs-display-name question and was closed when its remedy shipped, but the question itself was never answered — `agy` is unresponsive and returns 124 on every call. Phase 7 exists to answer it and cannot run today.

## Recommended Next Step
- `/gsd-manager`
