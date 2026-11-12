---
name: verify-change
description: Use before handing a change to review. Picks the right verification tier and runs the documented checks, with evidence.
---

# verify-change

## Prerequisites

- The change and its acceptance criteria.
- The test realm for anything player-visible.
- A backup for any database write.

## Tiers

| Tier | Applies to | Commands |
|------|------------|----------|
| T0 docs | Markdown, ADRs, runbooks | `make verify-docs` |
| T1 SQL/tooling | SQL, RBAC, schema | `make verify-sql` (auto test-realm apply for pending/custom SQL when configured; `VERIFY_SQL_APPLY=0` lint only) |
| T2 C++/scripts | core, modules, scripts | `make verify-cpp` |
| T3 player-visible | GM tools, DB writes, behavior | `make verify-smoke`, then `make verify-full`; live e2e when asked |
| T4 production | deploy, config, DB | T3 + backup + staging + rollback plan |

## Workflow

1. Pick the highest tier the change touches. A change that touches code and SQL gets both.
2. Run the commands and capture exit codes and the decisive output.
3. For T3, follow the manual checklist in the relevant runbook. Record observations, not "works".
4. Confirm `Errors.log` has no new errors.
5. For SQL, record the backup path, affected rows, and verification query.
6. For database clients or GM tools, confirm least privilege, read-only production, backup, and audit
   where applicable.
7. Report failures with the exact step, expected, actual, and log excerpt.

## Constraints

- Do not weaken a test or skip a check to go green.
- Do not run e2e against production.
- Do not claim a manual check you did not perform.
- Do not invent a new suite unless the user asked.
- A flaky result needs a classified cause, not a retry loop.

## Expected output

A pass/fail table per check, exact commands, results, backup paths, and untested paths.

## References

- [specs/testing-and-release.md](../../../specs/testing-and-release.md)
- [.ai/memories/testing.md](../../memories/testing.md)
- [runbook/operation/test-realm.md](../../../runbook/operation/test-realm.md)
