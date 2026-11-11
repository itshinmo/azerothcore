# Testing and release

## Purpose

Define how changes are verified and how they reach the test and production environments.

## Scope

Unit, integration, live e2e, SQL/data checks, static checks, the test realm, fork CI, and release.

## Boundary

Owns the verification contract. Does not own individual feature test plans; those belong in the
feature spec.

## Contract

### Levels

| Level | Location | Use |
|-------|----------|-----|
| Unit | `src/test/` | pure logic, parsers, flags, helpers, extracted behavior |
| Integration | `src/test/` | multiple components, no client login |
| Live e2e | `e2e/` | protocol/client-observed behavior on a running stack |
| SQL/data | test database | row counts, constraints, sample rows |
| Manual | test realm | player-visible behavior the harness cannot express |

### Tiers

| Tier | Applies to | Must pass |
|------|------------|-----------|
| T0 docs | Markdown, ADRs, runbooks | link check, reviewer |
| T1 SQL/tooling | SQL, RBAC, GUI schema | SQL lint; auto test-realm apply, row checks, backup when configured; `VERIFY_SQL_APPLY=0` disables |
| T2 C++/scripts | core, modules, scripts | codestyle, cppcheck, `-Werror` build, unit tests |
| T3 player-visible | GM tools, GUI writes, behavior | T2 + startup smoke + manual checklist + clean errors; live e2e when the change needs it and the user asked |
| T4 production | deploy, config, DB | T3 + backup + staging + rollback plan + human approval |

### Test realm

- Separate databases or a documented reset.
- `Warden.Enabled=0` for AzerothGhost.
- Dedicated GM accounts per role.
- Unique character prefixes; cleanup after each e2e test.
- Never point at production.

### Fork CI

- Planned for phase 1: `.github/workflows/fork-ci.yml` runs on this fork.
- On push/PR: docs check, SQL lint, C++ lint, build, unit tests, dry-run.
- E2E smoke on label or manual dispatch.
- No upstream-repository guard.
- Actions pinned by full SHA with version comments.

### Release

- Local build and install.
- Test realm verification.
- Production: Ubuntu 24.04, native binaries, systemd, MySQL on the same host.
- Backup before deploy; rollback plan; health check after.
- Production writes are human-only.

## Errors and edge cases

- A flaky test is classified before retry: product, test, environment, or prerequisite.
- A failed SQL update stops startup; restore the backup before retrying.
- A failed deploy rolls back to the previous binary and config; the database rollback uses the
  pre-deploy backup.
- A test that needs missing client data is an environment failure, not a product pass.

## Security

- No production data in tests.
- No secrets in CI logs.
- CI tokens are least-privilege.
- E2E accounts are test-only.

## Observability

- CI job logs.
- Test realm `Errors.log`.
- Deploy log with commit, backup path, and health result.

## References

- [.ai/memories/testing.md](../.ai/memories/testing.md)
- [.agents/docs/e2e-policy.md](../.agents/docs/e2e-policy.md)
- [runbook/operation/test-realm.md](../runbook/operation/test-realm.md)
- [runbook/operation/production-deploy.md](../runbook/operation/production-deploy.md)
- [decisions/ADR-007-verification-gates-and-fork-ci.md](../decisions/ADR-007-verification-gates-and-fork-ci.md)
