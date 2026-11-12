---
name: db-query-and-edit
description: Use when reading or changing rows in acore_auth, acore_characters, or acore_world. Enforces backup, least privilege, scoped writes, and before/after evidence.
---

# db-query-and-edit

## Prerequisites

- Know the target database and table.
- Read [runbook/database/schema-guide.md](../../../runbook/database/schema-guide.md) for the table.
- A backup exists if the operation writes.

## Workflow

1. Identify the environment. Local and test are writable after a backup. Production is read-only for
   agents.
2. Backup before a write batch:

   ```bash
   make backup
   ```

3. Read first. Use the primary key or a narrow indexed filter:

   ```sql
   SELECT * FROM creature WHERE guid = ? AND id1 = ?;
   ```

4. Preview the write as a `SELECT` with the same `WHERE` clause. Count rows.
5. Write inside a transaction where the engine supports it. Keep the `WHERE` narrow; never `OR`.
6. Verify with a before/after row count and a sample row.
7. Record the backup path, SQL, affected rows, and verification.

## Rules

- Never `UPDATE`/`DELETE` without a `WHERE` that matches only the intended rows.
- Never `DROP DATABASE`, `TRUNCATE`, or mass-delete without a human and a backup.
- Use `DELETE` + `INSERT` for idempotent data changes.
- `smart_scripts` edits rewrite the full `(entryorguid, source_type)` block.
- Do not edit `data/sql/base/`, `archive/`, or `updates/db_*/`.
- Project SQL goes in `data/sql/custom/db_*/`; upstream-shaped fixes in `pending_db_*/`.
- Never use `root`.
- Use DBeaver saved queries for common GM operations; always back up first and keep production
  read-only.

## Expected output

The SQL, backup path, affected row counts, before/after sample, and any rollback note.

## References

- [specs/database.md](../../../specs/database.md)
- [.ai/memories/database.md](../../memories/database.md)
- [.agents/docs/sql-guidelines.md](../../../.agents/docs/sql-guidelines.md)
