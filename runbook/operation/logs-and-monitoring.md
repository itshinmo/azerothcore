# Logs and monitoring

## When to use

Debugging a startup, login, query, or in-game failure; checking server health; setting up monitoring.

## Log files

| File | Contents |
|------|----------|
| `env/dist/logs/Server.log` | lifecycle, world init, update-time summary |
| `env/dist/logs/Errors.log` | SQL and application errors; should be clean after startup |
| `env/dist/logs/Auth.log` | login and realm-list events |
| MySQL error log | database engine errors |

The exact paths come from `LogsDir` and the appender config.

## Triage

1. Find the first decisive error:

   ```bash
   tail -n 300 env/dist/logs/Errors.log
   grep -nE 'ERROR|FATAL|SQL|failed|Could not' env/dist/logs/Server.log | tail -n 80
   tail -n 80 env/dist/logs/Auth.log
   ```

2. Classify: SQL/schema, config, client data, code, or environment.
3. Reproduce with the smallest command.
4. Preserve the log before restarting.
5. Report the shortest decisive line. Do not paste secrets or player data.

## Log levels

Server log levels are set in `worldserver.conf`:

```text
Logger.root=3,Console Server Errors
Logger.sql.sql=2,Console Errors
Logger.sql.updates=4,Console Server Errors
```

Higher number means more verbose. Change a category, not the global root, when possible. Restart or
`server set loglevel <n>` for the console.

## Monitoring

- Watch disk space for `LogsDir` and MySQL.
- Watch `Errors.log` growth.
- Watch map update time in the `Server.log` update summary.
- Optional InfluxDB/Grafana: `Metric.Enable=1` and the `Metric.InfluxDB.*` settings. Keep it disabled
  unless configured.
- A health check can be a cron/launchd job that runs the checks in [health-check.md](health-check.md).

## Retention

- Rotate or compress logs so they do not fill the disk.
- Keep enough history to investigate an incident after it is reported.
- Do not commit logs.

## Rules

- Never log credentials, tokens, or full connection strings.
- Do not delete a log before the incident is understood.
- Do not restart production just to clear a log.

## References

- [specs/server.md](../../specs/server.md)
- [health-check.md](health-check.md)
- [troubleshooting/](../troubleshooting/)
