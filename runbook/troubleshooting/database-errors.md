# Database errors

## Symptoms

Startup stops on a SQL update, a query fails, the server loses its MySQL connection, or `Errors.log`
shows SQL errors.

## First checks

```bash
tail -n 300 env/dist/logs/Errors.log
mysql -h 127.0.0.1 -u acore -p -e "SELECT 1"
mysql -h 127.0.0.1 -u acore -p acore_world -e "SELECT name,state FROM updates ORDER BY timestamp DESC LIMIT 5"
```

## Common errors

| Error | Cause | Fix |
|-------|-------|-----|
| `Access denied for user` | user/host/password mismatch | fix the config or grant the host |
| `Unknown database` | DB not created | run `create_mysql.sql` |
| `Table ... doesn't exist` | base SQL not applied or wrong DB | apply base/update; check the DB string |
| `Duplicate entry` | non-idempotent insert | add `DELETE` before `INSERT` |
| `Unknown column` | schema older than the code | apply pending updates or rebuild the DB |
| `Cannot add or update a child row` | FK mismatch (rare) | fix the referenced row |
| `Lock wait timeout` / `Deadlock` | long transaction or bad order | shorten the transaction, retry once, inspect |
| `Lost connection` | MySQL restart, timeout, network | check MySQL, `wait_timeout`, max connections |
| `Data too long` | column too small | change the schema or truncate input |

## Failed update

1. Stop the server if it is still running.
2. Read the exact file and statement from `Errors.log`.
3. Restore the pre-update backup if partial data was written.
4. Fix the SQL on the test realm.
5. Reapply. Never edit an applied file; add a new one.

## Connection loss

- Confirm MySQL is running: `brew services list` or `systemctl status mysql`.
- Check `max_connections`, `wait_timeout`, and the DB pool config.
- Check disk space; a full disk can crash MySQL.
- Check the MySQL error log.

## Rules

- Do not retry a write blindly after an unknown outcome.
- Do not run `--force`.
- Do not edit merged or archived SQL.
- Always back up before a repair.

## References

- [apply-sql-update.md](../operation/apply-sql-update.md)
- [backup-restore.md](../operation/backup-restore.md)
- [schema-guide.md](../database/schema-guide.md)
