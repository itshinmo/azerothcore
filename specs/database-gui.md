# Database GUI

> Status: phase 3. The tool in `tools/dbadmin/` does not exist yet; this spec is the contract for
> when it lands.

## Purpose

Give humans a local, auditable way to browse and edit the game databases without raw SQL or `root`
credentials. The GUI is an internal operator tool, not a player-facing service.

## Scope

- Schema browser, row browser/editor, SQL runner, saved game queries, pending SQL import.
- Audit log and pre-write backups.
- Local and test connections, read-only production through an SSH tunnel.

## Boundary

Owns the tool UI, its local authentication, query guard, audit, and backup orchestration.

Does not own the game database schema, game logic, or production deployment. Does not replace the GM
panel; the GM panel calls the server API, not the database.

## Contract

### Stack

- Node 26 ESM, built-in `http`, `mysql2` as the only runtime dependency, server-rendered HTML, small
  vanilla JS/CSS.
- No framework, no build step, no external assets.
- Source in `tools/dbadmin/`; tests with `node:test`.

### Profiles

| Profile | Access | Default |
|---------|--------|---------|
| `local` | read/write | read-only until write mode is enabled |
| `test` | read/write | read-only until write mode is enabled |
| `prod-readonly` | read-only | always read-only; used through an SSH tunnel |

Each profile has its own database user. Never `root`.

### Authentication and transport

- Bind `127.0.0.1` only.
- Host-header allowlist: `localhost:<port>` and `127.0.0.1:<port>`.
- Random 32-byte token printed at startup; login form; HttpOnly, SameSite=Strict cookie; timing-safe
  comparison.
- CSRF token on every state-changing form; `Origin`/`Referer` check.
- Security headers: CSP `default-src 'self'`, `frame-ancestors 'none'`, `nosniff`, no inline script.
- Optional local username/password for shared Macs; not required for single-user localhost.

### Features

- Schema browser: tables, columns, types, indexes, row counts.
- Row browser/editor: pagination, primary-key edits, FK hints, null handling.
- SQL runner: one statement at a time, `EXPLAIN` for reads, row limit, dangerous-statement block list.
- Saved queries: account lookup, characters, online players, inventory, mail, quests, instance binds,
  realm list, bans, pending SQL.
- Pending SQL import: scan `pending_db_*` and `custom/db_*`, show file/DB/hash/state, apply with
  backup, stop on first error.
- Audit viewer: actor, profile, SQL, before/after, row count, duration, success, backup path.
- ERD: curated relationships plus generated table/column index; simple SVG graph.
- Backup list and restore instructions.

### Write guard

1. Write mode is off by default.
2. A write requires an explicit mode switch and a typed confirmation.
3. The SQL must be a single statement.
4. Dangerous statements are blocked unless a human enables an override:
   `DROP DATABASE`, `DROP TABLE`, `TRUNCATE`, `GRANT`, `REVOKE`, `CREATE USER`, `SET GLOBAL`,
   `LOAD_FILE`, `INTO OUTFILE`, `INTO DUMPFILE`.
5. `UPDATE`/`DELETE` previews its row count with a `SELECT` using the same `WHERE`.
6. A backup runs before the write batch and its path is recorded.
7. The audit record is written before the result is returned.
8. On error, the transaction is rolled back where MySQL supports it.

### Audit

- Stored in `var/dbadmin/audit.db` using `node:sqlite`.
- Record: timestamp, actor/session, profile, database, statement, parameters, before rows (for
  updates/deletes), after rows, affected count, duration, success, error, backup path.
- Redact values of columns named like secrets (`password`, `token`, `key`, `secret`, `session`).
- Audit is append-only from the app; no delete route.

### Backups

- `mysqldump --single-transaction --routines --triggers` per database.
- Path `var/backups/dbadmin/<timestamp>/`.
- A checksum file and a manifest with profile/database/size.
- Retention configurable; default 30 days.
- A restore is documented but never one-click in production.

## Errors and edge cases

- Token missing or wrong: 401, no detail.
- Foreign Host header: 403.
- Missing CSRF or bad Origin: 403.
- Write on a read-only profile: 403 at the route and by the database user.
- Dangerous statement without override: 403 with the statement class.
- Backup failure: abort the write.
- MySQL connection lost: no retry for writes; show the error and the backup path.
- DDL implicit commit: warn that a transaction cannot roll it back.
- Large result: cap rows and offer pagination; never stream unbounded output.

## Security

- No public binding. Remote access is an SSH tunnel.
- Least-privilege DB users.
- No secrets in logs, audit values, or error messages.
- No `root`.
- Production is read-only at both the app and the database user.

## Observability

- Structured local log with request id, route, status, duration; no secrets.
- Audit records.
- Backup manifest.
- A startup line with the bound address and token location (never the token in a log file).

## Test plan

- Unit: token auth, CSRF, host check, SQL guard, splitter, audit redaction, backup command.
- Integration: temporary MySQL schema; row edit, write preview, rollback, backup restore.
- Security: read-only profile rejects writes; dangerous SQL blocked; wrong Host/Origin rejected.
- Manual: SSH tunnel to a read-only production profile; review an audit entry; restore a backup.

## References

- [decisions/ADR-004-database-gui.md](../decisions/ADR-004-database-gui.md)
- [runbook/operation/dbadmin.md](../runbook/operation/dbadmin.md)
- [specs/security.md](security.md)
