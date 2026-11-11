# Server won't start

## Symptoms

`authserver` or `worldserver` exits immediately, hangs at startup, or never listens on its port.

## Triage order

1. **Run in the foreground** and read the last lines:

   ```bash
   cd env/dist/bin
   ./worldserver
   ./authserver
   ```

2. **Config:** confirm the config path and the database strings. Check `DataDir`, `LogsDir`,
   `RealmID`, and the ports.
3. **Database:** confirm MySQL is running and the user can connect over the configured host:

   ```bash
   mysql -h 127.0.0.1 -u acore -p -e "SELECT 1"
   ```

4. **Schema update:** a failed update stops startup. Read `Errors.log` and fix or restore.
5. **Port:** check for a process already listening:

   ```bash
   lsof -nP -iTCP:8085 -sTCP:LISTEN
   lsof -nP -iTCP:3724 -sTCP:LISTEN
   ```

6. **Client data:** missing `dbc/` is fatal; missing `maps/`/`vmaps/`/`mmaps/` causes map errors.
7. **Permissions:** the install directory and `LogsDir` must be writable by the running user.
8. **Binary mismatch:** a module built for a different config or a stale `build/`. Reconfigure and
   rebuild.

## Common causes

| Symptom | Likely cause |
|---------|--------------|
| `Access denied for user` | DB user/host mismatch or wrong password |
| `Unknown database` | database not created |
| `Table ... doesn't exist` | base SQL not applied or wrong DB |
| `Could not find ... dbc` | `DataDir` wrong or missing `dbc/` |
| `bind: Address already in use` | another server is running |
| `Failed to open ... map` | missing maps/vmaps/mmaps |
| Exits after an update | failed SQL; read `Errors.log` |
| `No valid realms specified` | authserver started before worldserver, or every realm has flag 3 |

## `No valid realms specified`

The authserver marks every realm offline on startup, then refuses to start if every realm has flag 3
(`VERSION_MISMATCH | OFFLINE`). A normal offline realm (flag 2) is accepted. The worldserver clears its
realm's version-mismatch flag after it finishes loading. Start the worldserver first.

If no worldserver is running, back up and reset the flag for the intended realm:

```bash
make backup
```

```sql
SELECT id, name, flag FROM acore_auth.realmlist;
UPDATE acore_auth.realmlist SET flag = 0 WHERE id = <realm_id>;
```

Then start worldserver, wait for `World Initialized`, and start authserver.

## Verification

- The process stays in the foreground.
- The port listens.
- `World Initialized` appears.
- `Errors.log` is clean.

## References

- [health-check.md](../operation/health-check.md)
- [database-errors.md](database-errors.md)
- [map-data-missing.md](map-data-missing.md)
- [logs-and-monitoring.md](../operation/logs-and-monitoring.md)
