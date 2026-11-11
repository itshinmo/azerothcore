# Rollback

## When to use

A bad SQL update, a broken binary, a bad config, or a failed deploy.

## Prerequisites

- A backup taken before the change.
- The previous binary or a known-good commit.
- The previous config.
- Human approval for production.

## Database rollback

1. Stop both servers.
2. Take a safety backup of the current state.
3. Restore the pre-change dump:

   ```bash
   backup_dir="var/backups/manual/<timestamp>"
   mysql -u <admin> -p < "$backup_dir/acore.sql"
   ```

4. Start MySQL, worldserver, authserver.
5. Run the health check and verify the affected feature.

If the change was a small, reversible data edit, the inverse SQL may be faster, but only when it was
reviewed and the row set is known.

## Binary rollback

1. Stop both servers.
2. Keep the failed binary for diagnosis.
3. Restore the previous `env/dist/bin/{authserver,worldserver}` or reinstall the known-good build.
4. Start and health-check.

## Config rollback

1. Restore the previous `env/dist/etc/*.conf`.
2. Restart both servers.
3. Confirm DB strings, ports, and `DataDir`.

## Rules

- DDL causes an implicit commit; a transaction does not roll it back. Use the backup.
- Do not restore a dump from a different schema version without checking compatibility.
- Do not delete the failed build or logs before the incident is understood.
- Production rollback needs a human and a maintenance window.

## Verification

- Health check passes.
- Login works.
- The affected feature works.
- `Errors.log` is clean.
- The incident record names the restored backup and binary.

## References

- [backup-restore.md](backup-restore.md)
- [logs-and-monitoring.md](logs-and-monitoring.md)
- [gm/incident-response.md](../gm/incident-response.md)
