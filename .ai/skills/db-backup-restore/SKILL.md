---
name: db-backup-restore
description: Use before a write batch, before a schema change, on a schedule, or when recovering from a bad update. Dumps, verifies, and restores the three databases.
---

# db-backup-restore

## Prerequisites

- `mysqldump` and `mysql` on PATH.
- Credentials for a user with the required privileges, stored outside the repository.
- Enough disk space for the dump plus a restore copy.

## Workflow

1. Dump each database with a consistent snapshot:

   ```bash
   BACKUP_DIR="var/backups/manual/$(date +%Y%m%d-%H%M%S)"
   umask 077
   mkdir -p "$BACKUP_DIR"
   chmod 700 "$BACKUP_DIR"
   mysqldump --single-transaction --routines --triggers --no-tablespaces \
     --databases acore_auth acore_characters acore_world \
     > "$BACKUP_DIR/acore.sql"
   shasum -a 256 "$BACKUP_DIR/acore.sql" > "$BACKUP_DIR/acore.sql.sha256"
   # Linux without shasum: sha256sum "$BACKUP_DIR/acore.sql" > "$BACKUP_DIR/acore.sql.sha256"
   ```

   `make backup` wraps this and records the path.

2. Verify the dump is non-empty and contains the expected databases:

   ```bash
   grep -m1 'CREATE DATABASE' "$BACKUP_DIR/acore.sql"
   ```

3. Restore into a scratch schema first when testing a restore:

   ```bash
   mysql -u <user> -p < "$BACKUP_DIR/acore.sql"
   ```

4. For a real restore, stop the servers first, restore, then start worldserver and authserver.
5. Record the backup path, size, checksum, restore result, and row counts.

## Constraints

- Never commit a dump; it may contain player data and credentials.
- Never overwrite the only backup.
- Do not restore production without human approval and a maintenance window.
- Test the restore path before trusting a backup.
- Keep retention long enough to cover the slowest bad-update discovery.
- Dumps are private: mode 700 on the directory, mode 600 on the file.

## Expected output

A verified backup path with checksum, and a restore result with row counts.

## References

- [runbook/operation/backup-restore.md](../../../runbook/operation/backup-restore.md)
- [runbook/operation/rollback.md](../../../runbook/operation/rollback.md)
