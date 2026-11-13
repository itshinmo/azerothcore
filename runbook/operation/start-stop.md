# Start and stop

## When to use

Starting the local or test stack, restarting after a config change, or shutting down cleanly.

## Prerequisites

- Binaries installed under `env/dist/bin/`.
- MySQL running.
- Config and client data present.

## Start

1. Start MySQL if it is not running:

   ```bash
   brew services start mysql@8.4
   ```

2. Start worldserver in one terminal:

   ```bash
   cd env/dist/bin
   ./worldserver
   ```

3. Start authserver in another terminal:

   ```bash
   cd env/dist/bin
   ./authserver
   ```

   Start worldserver first: it clears the realm's version-mismatch flag, and authserver refuses to
   start while every realm has flag 3 (`VERSION_MISMATCH | OFFLINE`). `make start` runs both in the
   background inside detached `screen` sessions.

   authserver marks every realm offline on boot, after the worldserver has already cleared that bit.
   `make start` and `make test-realm CMD=start` clear the offline bit for this realm after authserver
   starts and check the database row. authserver caches the realm list and refreshes it every
   `RealmsStateUpdateDelay` seconds (default 20), so a client can still see the realm as offline for
   up to that long. For a manual start, run:

   ```sql
   UPDATE acore_auth.realmlist SET flag = flag & ~2 WHERE id = <realm id>;
   ```

   `screen` is required: the servers read console input from stdin, and with `/dev/null` they spin on
   EOF and write `AC> ` forever. Attach to the worldserver console with `make console`; detach with
   `Ctrl-A d`.

## Stop

Graceful, in this order:

1. Stop authserver first so no new logins arrive: `Ctrl-C` or SIGTERM.
2. Stop worldserver from its console with `server shutdown 0`.

Then confirm ports are free:

```bash
lsof -nP -iTCP:3724 -sTCP:LISTEN
lsof -nP -iTCP:8085 -sTCP:LISTEN
```

`make stop` sends SIGTERM and waits 30 seconds per server. If a process ignores SIGTERM, it sends
SIGKILL, which skips the normal shutdown path: online character state may not be saved and the
session-end row is not written. Use SIGKILL only as a last resort and check the logs afterwards.

## Restart

Stop gracefully, then start again. Do not restart only one process if the config change affects the
other.

## Console commands

```text
server info
server shutdown 0
server restart 10
server set loglevel 3
server set motd <text>
account create <user> <password>
account set gmlevel <user> <level> -1
```

## Rules

- Do not use `kill -9` unless the process is unresponsive and a human approves.
- Do not run two worldservers against the same databases.
- Do not start production with a test config.
- Stop before restoring a database backup.

## Verification

- Both ports listening after start.
- `World Initialized` in `Server.log`.
- No new errors in `Errors.log`.
- Both ports free after stop.

## References

- [health-check.md](health-check.md)
- [logs-and-monitoring.md](logs-and-monitoring.md)
- [specs/server.md](../../specs/server.md)
