---
schema_version: 1
open_count: 5
waived_count: 0
fixed_count: 0
total_count: 5
last_updated: 2026-08-19T14:44:45.227Z
---

# Broken Windows Ledger

> Cross-phase defect register. With `workflow.windows_enforce` enabled, `/gsd-ship` blocks while `open_count > 0`.
> Waive with `gsd-tools windows waive <id> "<reason>"` (reason required).
> Mark fixed with `gsd-tools windows fixed <id>`.

| id | phase | kind | file | line | description | status | reason | recorded_at | resolved_at |
|----|-------|------|------|------|-------------|--------|--------|-------------|-------------|
| 1 | 01 | unrun-verify | .planning/phases/01-the-missing-timeout-decision/01-06-PLAN.md |  | macOS job-control notice under a coreutils-less PATH cannot be reproduced or asserted on this project's hosts (plan 01-06 task 3 human-check, SUMMARY coverage D7) | open |  | 2026-08-19T14:44:38.984Z |  |
| 2 | 01 | unrun-verify | .planning/phases/01-the-missing-timeout-decision/01-06-PLAN.md |  | README's environment-variable prose (phase criterion 3) is a property of prose and is unverified by the suite (plan 01-06 task 3 human-check, SUMMARY coverage D8) | open |  | 2026-08-19T14:44:39.048Z |  |
| 3 | 01 | unrun-verify | .planning/phases/01-the-missing-timeout-decision/01-06-PLAN.md |  | PROJECT.md's Key Decisions always-bounded row (phase criterion 1) is unverified by the suite (plan 01-06 task 3 human-check, SUMMARY coverage D8) | open |  | 2026-08-19T14:44:39.110Z |  |
| 4 | 01 | deviation | .worktrees/agy-1.6.2/tests/fake-agy.sh |  | FAKE_AGY_FORK_HANG made SIGHUP-immune outside plan 01-06's files_modified, because the pty hangup made RB06c a vacuous pass (Rule 2) | open |  | 2026-08-19T14:44:39.172Z |  |
| 5 | 01 | deviation | .planning/REQUIREMENTS.md |  | R11's Evidence line still cites pre-phase case ids (delegate-agy-8k0); left untouched by plan 01-06 as REQUIREMENTS.md is outside its files_modified, case ids posted to the ticket for a single later edit | open |  | 2026-08-19T14:44:39.235Z |  |

````json
[
  {
    "id": 1,
    "kind": "unrun-verify",
    "phase": "01",
    "file": ".planning/phases/01-the-missing-timeout-decision/01-06-PLAN.md",
    "line": null,
    "description": "macOS job-control notice under a coreutils-less PATH cannot be reproduced or asserted on this project's hosts (plan 01-06 task 3 human-check, SUMMARY coverage D7)",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-19T14:44:38.984Z",
    "resolved_at": null
  },
  {
    "id": 2,
    "kind": "unrun-verify",
    "phase": "01",
    "file": ".planning/phases/01-the-missing-timeout-decision/01-06-PLAN.md",
    "line": null,
    "description": "README's environment-variable prose (phase criterion 3) is a property of prose and is unverified by the suite (plan 01-06 task 3 human-check, SUMMARY coverage D8)",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-19T14:44:39.048Z",
    "resolved_at": null
  },
  {
    "id": 3,
    "kind": "unrun-verify",
    "phase": "01",
    "file": ".planning/phases/01-the-missing-timeout-decision/01-06-PLAN.md",
    "line": null,
    "description": "PROJECT.md's Key Decisions always-bounded row (phase criterion 1) is unverified by the suite (plan 01-06 task 3 human-check, SUMMARY coverage D8)",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-19T14:44:39.110Z",
    "resolved_at": null
  },
  {
    "id": 4,
    "kind": "deviation",
    "phase": "01",
    "file": ".worktrees/agy-1.6.2/tests/fake-agy.sh",
    "line": null,
    "description": "FAKE_AGY_FORK_HANG made SIGHUP-immune outside plan 01-06's files_modified, because the pty hangup made RB06c a vacuous pass (Rule 2)",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-19T14:44:39.172Z",
    "resolved_at": null
  },
  {
    "id": 5,
    "kind": "deviation",
    "phase": "01",
    "file": ".planning/REQUIREMENTS.md",
    "line": null,
    "description": "R11's Evidence line still cites pre-phase case ids (delegate-agy-8k0); left untouched by plan 01-06 as REQUIREMENTS.md is outside its files_modified, case ids posted to the ticket for a single later edit",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-19T14:44:39.235Z",
    "resolved_at": null
  }
]
````
