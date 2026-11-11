---
description: Start/stop, health, logs, backups, monitoring, and incident basics. Read before operating the server.
last-verified: 2026-11-12
---

# Operations

Procedures: [runbook/operation/](../../runbook/operation/).

## Start and stop

```bash
make start
make status
make logs
make stop
```

- authserver: port 3724, `Auth.log`.
- worldserver: port 8085, `Server.log` and `Errors.log`.
- Logs live under `env/dist/logs/` by default.
- Stop gracefully: worldserver console `server shutdown 0` or SIGTERM. Confirm ports are free.

## Health

- Both processes running, ports listening.
- Database reachable with the configured users.
- `DataDir` contains `dbc/`, `maps/`, `vmaps/`, `mmaps/`.
- `Errors.log` has no new errors at startup.
- A GM test account can log in and enter the world.
- `server info` shows uptime and players.

## Backups

- `make backup` dumps auth, characters, and world.
- Before any write batch; daily scheduled; retain enough history to cover a bad update.
- Restore drill: restore into a scratch schema and verify row counts before trusting the backup.
- Store backups outside the repository; never commit them.

## Monitoring

- `Server.log` for lifecycle and update-time summaries.
- `Errors.log` for SQL and application errors; it should be empty in CI and clean after startup.
- `Auth.log` for login and realm-list failures.
- Metrics/InfluxDB/Grafana are optional; keep them disabled unless configured.
- Watch disk space, MySQL slow queries, and map update time.

## Incident order

1. Contain: stop writes, stop the server if data is at risk.
2. Preserve: copy logs and the current DB state.
3. Diagnose: identify the last change and the first error.
4. Restore: DB backup, binary rollback, or config rollback.
5. Verify: health check, login, affected feature.
6. Record: timeline, root cause, fix, prevention.
