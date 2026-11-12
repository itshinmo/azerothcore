# Backup and restore

## When to use

Before any database write batch, before a schema change, on a schedule, and during recovery.

## Prerequisites

- `mysqldump` and `mysql` on PATH.
- Credentials for a user with the required privileges.
- Disk space outside the repository for dumps.

## Backup

1. Create a timestamped directory with restricted permissions:

   ```bash
   BACKUP_DIR="var/backups/manual/$(date +%Y%m%d-%H%M%S)"
   umask 077
   mkdir -p "$BACKUP_DIR"
   chmod 700 "$BACKUP_DIR"
   ```

2. Dump all three databases in one consistent snapshot:

   ```bash
   mysqldump --single-transaction --routines --triggers --no-tablespaces \
     --databases acore_auth acore_characters acore_world \
     > "$BACKUP_DIR/acore.sql"
   ```

3. Checksum and manifest:

   ```bash
   shasum -a 256 "$BACKUP_DIR/acore.sql" > "$BACKUP_DIR/acore.sql.sha256"
   # Linux without shasum: sha256sum "$BACKUP_DIR/acore.sql" > "$BACKUP_DIR/acore.sql.sha256"
   ```

4. Verify the dump contains the expected databases:

   ```bash
   grep -m1 'CREATE DATABASE' "$BACKUP_DIR/acore.sql"
   ```

5. Store a copy outside the repository. Never commit a dump.

## Restore

1. Stop both servers.
2. Take a safety backup of the current state.
3. Restore:

   ```bash
   mysql -u <admin> -p < "$BACKUP_DIR/acore.sql"
   ```

4. Start MySQL, then worldserver, then authserver.
5. Run [health-check.md](health-check.md).
6. Verify the affected feature and row counts.

### Restore drill

Before trusting a backup, restore it into a scratch MySQL instance or scratch schema and check:

- the three databases exist;
- `updates` is populated;
- `creature`, `quest_template`, and `item_template` have expected counts;
- a known account and character exist.

## Schedule

- Pre-change: every write batch.
- Daily: one full dump, retained according to policy.
- Keep enough history to cover the slowest bad-update discovery.
- On macOS use launchd; on Linux use cron or a systemd timer. The wrapper is
  `tools/dev/backup-schedule.sh`.

```bash
bash tools/dev/backup-schedule.sh install   # daily 04:00
bash tools/dev/backup-schedule.sh status
bash tools/dev/backup-schedule.sh remove
```

`tools/dev/backup.sh` keeps `BACKUP_RETENTION_DAYS` (default 14) of daily dumps under
`var/backups/manual/` and prunes older ones. `make backup-schedule CMD=install` is the wrapper.

## Rules

- Never overwrite the only backup.
- Never restore production without human approval and a maintenance window.
- Do not restore a dump into a database version it was not taken from without checking the schema.
- Encrypt or restrict access to dumps; they contain player data.

## References

- [.ai/skills/db-backup-restore/SKILL.md](../../.ai/skills/db-backup-restore/SKILL.md)
- [rollback.md](rollback.md)
- [specs/database.md](../../specs/database.md)
