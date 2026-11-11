---
name: pending-sql-import
description: Use when applying SQL from pending_db_* or custom/db_* to a local or test database, or when checking whether an update was applied.
---

# pending-sql-import

## Prerequisites

- Backup path recorded.
- The target database is local or test, never production.
- The server is stopped or the change is a safe online update.

## Workflow

1. Inventory the files:

   ```bash
   ls -1 data/sql/updates/pending_db_world
   ls -1 data/sql/custom/db_world
   ```

2. Check whether a file was already applied:

   ```bash
   mysql -u <user> -p acore_world \
     -e "SELECT name,state,timestamp FROM updates WHERE name LIKE '%<file>%';"
   ```

3. Dry-run the server with updates enabled; it applies pending files and exits on failure:

   ```bash
   ./env/dist/bin/worldserver -d
   ```

4. Or apply the file directly after a backup, with `--show-warnings`:

   ```bash
   file="data/sql/updates/pending_db_world/rev_<timestamp>.sql"
   mysql -u <user> -p --show-warnings acore_world < "$file"
   ```

5. Verify the intended rows and row counts. Re-read the `updates` table.
6. If the file failed, restore the backup if data changed, fix the SQL, and retry on test only.

## Rules

- `pending_db_*` is one-time, upstream-shaped SQL.
- `custom/db_*` must be re-applicable and is applied by the updater with state `CUSTOM`.
- Never edit a file after it was applied and recorded; add a new file.
- Never apply production SQL from an agent session.
- Never ignore a nonzero exit code.

## Expected output

Files applied, backup path, `updates` rows, verification queries, and any errors.

## References

- [runbook/operation/apply-sql-update.md](../../../runbook/operation/apply-sql-update.md)
- [.agents/docs/sql-guidelines.md](../../../.agents/docs/sql-guidelines.md)
