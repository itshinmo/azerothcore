# Database GUI

> Status: phase 3. The tool in `tools/dbadmin/` does not exist yet. This runbook is the contract and
> procedure for when it lands.

## When to use

Browsing or editing the game databases, running a saved support query, applying pending SQL, reviewing
audit entries, or taking a pre-write backup.

## Prerequisites

- Node 26.
- `tools/dbadmin/` dependencies installed.
- A `.env` profile with a least-privilege database user.
- For production, an SSH tunnel.

## Start

```bash
cd tools/dbadmin
npm install
npm start
```

The app prints the local URL and a one-time token. Open `http://127.0.0.1:<port>`, enter the token,
and choose a profile.

## Profiles

| Profile | Access |
|---------|--------|
| `local` | read/write, read-only default |
| `test` | read/write, read-only default |
| `prod-readonly` | read-only |

Production is never edited directly. Use a read-only user and the SSH tunnel:

```bash
ssh -L 8787:127.0.0.1:8787 <user>@<host>
```

Then open `http://127.0.0.1:8787` locally. The token and cookie still apply.

## Read

- Schema browser: tables, columns, indexes, row counts.
- Row browser: filter by primary key or a narrow indexed column.
- Saved queries: account, character, inventory, mail, quests, instances, bans.
- SQL runner: one statement, `EXPLAIN`, row limit.

## Write

1. Switch to write mode.
2. Select a saved query or write a single statement.
3. Preview the affected rows.
4. Type the confirmation.
5. The GUI takes a backup, runs the write, and records the audit entry.
6. Verify the result with a read query.

## Pending SQL

- The import view lists `pending_db_*` and `custom/db_*` files.
- It shows the target DB, hash, and applied state.
- Applying takes a backup and stops on the first error.
- DDL cannot be rolled back by a transaction; restore the backup if it fails.

## Audit

Every write records actor, profile, database, statement, before/after rows, affected count, duration,
success, and backup path. The audit is append-only. Review it after a batch and during an incident.

## Backup

- Pre-write backups are stored under `var/backups/dbadmin/<timestamp>/`.
- The manifest lists profile, database, size, and checksum.
- Restore uses the normal MySQL procedure; see [backup-restore.md](backup-restore.md).

## Security rules

- Never bind `0.0.0.0`.
- Never use `root`.
- Never share the token or cookie.
- Never write to production.
- Report a wrong Host/Origin rejection as expected behavior, not a bug.

## Troubleshooting

- **401:** token missing or expired; restart and re-enter.
- **403 Host:** use `127.0.0.1` or `localhost`, not a LAN IP.
- **403 CSRF:** reload the page; the session token is stale.
- **Read-only:** the profile or the database user denies writes.
- **Backup failed:** the write is aborted; fix disk/permissions and retry.

## References

- [specs/database-gui.md](../../specs/database-gui.md)
- [decisions/ADR-004-database-gui.md](../../decisions/ADR-004-database-gui.md)
- [backup-restore.md](backup-restore.md)
