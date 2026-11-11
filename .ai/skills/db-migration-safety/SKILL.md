---
name: db-migration-safety
description: Use when adding or changing schema, indexes, large data updates, or any SQL that must be re-applied safely.
---

# db-migration-safety

## Prerequisites

- A backup and a test database.
- The target table definitions and row counts.
- The SQL lint rules in `.agents/docs/sql-guidelines.md`.

## Workflow

1. Classify the change:
   - **Data only:** `DELETE` + `INSERT`, `REPLACE`, or a narrow `UPDATE`.
   - **Schema:** `CREATE TABLE IF NOT EXISTS`, `ALTER TABLE` with a guard, index creation.
   - **Large backfill:** batch by primary key; avoid one long lock.
2. Make it re-applicable:
   - `CREATE TABLE IF NOT EXISTS`
   - `DELETE` before `INSERT`
   - `REPLACE` where the row is a full replacement
   - guarded `ALTER` checks via `information_schema` when needed
3. Test on a scratch/test schema with production-like row counts.
4. Measure duration and lock time for large tables.
5. Apply to test, verify, then hand off for production approval.
6. Record a rollback: restore the backup, or the inverse SQL if it is genuinely reversible.

## Constraints

- MySQL DDL causes an implicit commit; a transaction is not a rollback for `ALTER`/`DROP`.
- Never edit merged or archived SQL.
- Never run a migration on production without a backup, a maintenance window, and a human.
- Do not add an index without checking existing indexes and query plans.
- Do not change a column type or collation without checking every consumer.

## Expected output

Re-applicable SQL, duration/lock measurements, verification queries, and a rollback plan.

## References

- [.agents/docs/sql-guidelines.md](../../../.agents/docs/sql-guidelines.md)
- [runbook/operation/apply-sql-update.md](../../../runbook/operation/apply-sql-update.md)
- [runbook/operation/rollback.md](../../../runbook/operation/rollback.md)
