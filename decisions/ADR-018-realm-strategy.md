# ADR-018 — Realm strategy: test realm deleted; local realm becomes live at launch

- Status: accepted
- Date: 2026-11-20
- Decided by: the owner
- Supersedes (in part): [ADR-007](ADR-007-verification-gates-and-fork-ci.md) — its "dedicated test
  realm" element. The tiered verification gate and fork CI elements remain in force.

## Context

The test realm (ports 3824/8185, `acore_test_*` databases, `tools/dev/test-realm.sh`,
`make test-realm`, `verify-sql` apply) was built on 2026-11-12 for e2e and risky-change verification.
Since 2026-11-19 development targets the local realm only and the test realm went unused. The owner
decided on 2026-11-20 to remove it entirely rather than keep it dormant: no trace of it should
remain until the launch realm topology exists.

## Decision

1. The test realm is deleted: the `acore_test_auth/characters/world` databases, the `acore_test` and
   `acore_admin` MySQL users, `tools/dev/test-realm.sh`, the `make test-realm` target, the
   `verify-sql` apply step, `cleanup.sh --test-db`, `env/test/`, and the test-realm runbooks.
2. Development runs against the local realm only (ports 3724/8085, `acore_auth/characters/world`).
   SQL is verified by lint (`python apps/codestyle/codestyle-sql.py`); the local worldserver applies
   pending and custom updates on restart. A backup is taken before any write batch.
3. At launch, the local realm is fully reset (fresh databases, fresh accounts) and renamed **live**,
   so every player starts clean.
4. A **dev** realm and a **ptr** realm are created at launch when public testing is needed. They are
   separate stacks with separate databases, distinct GM API ports, and `Warden.Enabled=0`.
5. Live e2e (`e2e/`) stays in the repository but is dormant until the `dev`/`ptr` realms exist. Its
   tests are not deleted; documentation now points at the future e2e realm requirements.

## Consequences

- `make verify-sql` is lint-only; the apply path and its backup/row checks are gone. Isolated
  pre-apply validation is lost until the launch realms exist; a local backup before writes is the
  compensating control.
- The e2e harness has no target realm today; it is exercised again when `dev`/`ptr` are created.
- Any future isolated realm is a new build following the launch topology, not a revival of the old
  test-realm tooling.
- Historical audit records that mention the test realm stay as written; they describe the past.

## References

- [ADR-007](ADR-007-verification-gates-and-fork-ci.md)
- [ADR-013](ADR-013-server-and-client-before-website.md)
- [runbook/operation/cleanup.md](../runbook/operation/cleanup.md)
- [runbook/development/commands.md](../runbook/development/commands.md)
