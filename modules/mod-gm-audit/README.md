# mod-gm-audit

Records GM command attempts in `acore_auth.gm_audit_log`.

## Apply

The table is created by `data/sql/custom/db_auth/gm_audit.sql`. Apply it with the startup updater or:

```bash
./env/dist/bin/worldserver -d -c env/test/etc/worldserver.conf
```

If the insert returns a non-fatal error, the command is aborted. A missing table or column is a schema
error: the core treats it as fatal and shuts the server down. Apply the SQL before enabling the module.

## Records

- realm, account id and name, player name and GUID
- command and arguments
- timestamp
- `result` is `NULL` for command-hook rows; website actions can write an outcome later

Console commands, accounts with security above player, and accounts with any direct RBAC grant
beyond the default permission set are audited.

Password-bearing commands are redacted: `account create`, `account password`,
`account set password`, `account set 2fa`, `account set email`, and `account 2fa`.

## Known limit

`AllCommandScript::OnTryExecuteCommand` runs before the command executes, so the module records
attempts, not success or failure. The result column is reserved for the website and a future
post-execute hook.

## Query

```sql
SELECT created_at, account_name, command, arguments, result
FROM acore_auth.gm_audit_log
ORDER BY id DESC
LIMIT 50;
```

Filter one actor:

```sql
SELECT created_at, command, arguments
FROM acore_auth.gm_audit_log
WHERE account_name = 'ADMIN'
ORDER BY id DESC;
```
