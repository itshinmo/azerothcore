# GM audit

## When to use

Reviewing privileged actions, investigating a player report, or checking that a GM command ran.

## What is recorded

`modules/mod-gm-audit` writes to `acore_auth.gm_audit_log`:

- realm, account id, account name
- player name and GUID
- command and arguments
- timestamp
- `result`: `NULL` for command-hook rows; reserved for website outcomes

Console commands, accounts with security above player, and accounts with any direct RBAC grant
beyond the default permission set are audited.

Password-bearing commands are redacted: `account create`, `account password`,
`account set password`, `account set 2fa`, `account set email`, and `account 2fa`. Stored arguments
for those commands are `<redacted>`.

## Apply

Table SQL: `data/sql/custom/db_auth/gm_audit.sql`.

```bash
make verify-sql
```

or:

```bash
./env/dist/bin/worldserver -d -c env/test/etc/worldserver.conf
```

## Query

Recent actions:

```sql
SELECT created_at, realm_id, account_name, player_name, command, arguments, result
FROM acore_auth.gm_audit_log
ORDER BY id DESC
LIMIT 50;
```

One account:

```sql
SELECT created_at, command, arguments
FROM acore_auth.gm_audit_log
WHERE account_name = 'ADMIN'
ORDER BY id DESC;
```

One command family:

```sql
SELECT created_at, account_name, arguments
FROM acore_auth.gm_audit_log
WHERE command = 'ban'
ORDER BY id DESC;
```

## Failure behavior

If the audit insert returns a non-fatal error, the command is aborted. A missing table, missing column,
or parse error is a schema error: the core treats it as fatal and shuts the server down. Apply
`data/sql/custom/db_auth/gm_audit.sql` before enabling the module.

The server log gets a `module.gm-audit` error when the insert fails.

## Limits

- The hook runs before command execution. It records the attempt, not whether the handler succeeded.
- `result` stays `NULL` until the website or a future post-execute hook writes it.
- The table contains account names, player names, and command arguments. Treat it as sensitive; do
  not paste rows into chat, issues, or commits without redaction.
- Redaction covers known password-bearing commands. Do not add new secret-bearing command forms
  without extending `HasSensitiveArguments`.
- No automatic retention or purge. Archive or delete old rows only with a backup and a written
  reason.

## Verify

1. Apply the SQL.
2. Run `.server info` from the console.
3. Query `gm_audit_log`; expect `command = 'server'`, `arguments = 'info'`.
4. Run `.account create auditprobe Secret123`; expect `arguments = '<redacted>'`.
5. Do not test failure by renaming or dropping the table. A missing table or column is a schema error
   and shuts the server down. Non-fatal insert failures abort the command only.

## References

- [command-handbook.md](command-handbook.md)
- [rbac-roles.md](rbac-roles.md)
- [specs/gm-tools.md](../../specs/gm-tools.md)
- [modules/mod-gm-audit/README.md](../../modules/mod-gm-audit/README.md)
