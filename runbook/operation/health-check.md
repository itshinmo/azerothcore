# Health check

## When to use

After starting, before a test run, after a deploy, or when a player reports an outage.

## Steps

1. Processes and ports:

   ```bash
   pgrep -fl authserver
   pgrep -fl worldserver
   lsof -nP -iTCP:3724 -sTCP:LISTEN
   lsof -nP -iTCP:8085 -sTCP:LISTEN
   ```

2. Database:

   ```bash
   mysql -h 127.0.0.1 -u acore -p -e "SELECT 1" acore_world
   mysql -h 127.0.0.1 -u acore -p -e "SELECT name,state FROM updates ORDER BY timestamp DESC LIMIT 5" acore_world
   ```

3. Client data:

   ```bash
   DATA_DIR="$(grep -E '^DataDir' env/dist/etc/worldserver.conf | cut -d'"' -f2)"
   for d in dbc maps vmaps mmaps; do printf '%s: ' "$d"; ls "$DATA_DIR/$d" | wc -l; done
   ```

4. Logs:

   ```bash
   tail -n 100 env/dist/logs/Server.log
   tail -n 100 env/dist/logs/Errors.log
   tail -n 50 env/dist/logs/Auth.log
   ```

5. Login with a dedicated GM test account. Confirm realm list, character list, and world entry.
6. Run `.server info` in game.
7. Record the result.

## Pass criteria

- Both processes alive; ports listening.
- DB reachable; `updates` readable.
- All four client-data directories non-empty.
- No new `Errors.log` entries at startup.
- Test account reaches the world.
- `.server info` responds.

## Fail actions

- Process missing: read the log, fix the cause, restart.
- Port missing: check the config and `lsof`.
- DB error: see [database-errors.md](../troubleshooting/database-errors.md).
- Map errors: see [map-data-missing.md](../troubleshooting/map-data-missing.md).
- Login failure: see [auth-login-failures.md](../troubleshooting/auth-login-failures.md).

## References

- [start-stop.md](start-stop.md)
- [logs-and-monitoring.md](logs-and-monitoring.md)
- [.ai/skills/server-health-check/SKILL.md](../../.ai/skills/server-health-check/SKILL.md)
