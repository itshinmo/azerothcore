---
name: server-health-check
description: Use after starting the server, before a test run, or when diagnosing a suspected outage. Checks ports, processes, database, data files, logs, and login readiness.
---

# server-health-check

## Prerequisites

- Server binaries installed under `env/dist/bin/`.
- MySQL running and the three databases reachable.

## Workflow

1. Processes and ports:

   ```bash
   make status
   lsof -nP -iTCP:3724 -sTCP:LISTEN
   lsof -nP -iTCP:8085 -sTCP:LISTEN
   ```

2. Database connectivity with the configured server user:

   ```bash
   mysql -h 127.0.0.1 -u acore -p -e "SELECT 1" acore_world
   ```

3. Schema state:

   ```bash
   mysql -u acore -p acore_world -e "SELECT name,state,timestamp FROM updates ORDER BY timestamp DESC LIMIT 5;"
   ```

4. Client data:

   ```bash
   grep '^DataDir' env/dist/etc/worldserver.conf
   ls "$DATA_DIR"/dbc | head
   ls "$DATA_DIR"/maps | head
   ls "$DATA_DIR"/vmaps | head
   ls "$DATA_DIR"/mmaps | head
   ```

5. Logs:

   ```bash
   tail -n 100 env/dist/logs/Server.log
   tail -n 100 env/dist/logs/Errors.log
   tail -n 50 env/dist/logs/Auth.log
   ```

6. Login test with a dedicated GM account. Confirm realm list, character list, and world entry.
7. Record the result.

## Pass criteria

- Both ports listening.
- Both processes alive.
- No new `Errors.log` entries at startup.
- `DataDir` has all four data sets.
- A test account can log in.

## Constraints

- Do not use a player account for tests.
- Do not restart production to run this check.
- Do not paste credentials or player data into the report.

## Expected output

A pass/fail table with PIDs, ports, DB result, data-dir result, log status, and login result.

## References

- [runbook/operation/health-check.md](../../../runbook/operation/health-check.md)
- [runbook/operation/logs-and-monitoring.md](../../../runbook/operation/logs-and-monitoring.md)
