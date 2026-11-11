# Server

## Purpose

Define the local and production server topology, configuration, lifecycle, and health expectations.

## Scope

`authserver`, `worldserver`, MySQL, client data, ports, logs, and startup/shutdown behavior.

## Boundary

Owns the process and configuration contract. Does not own gameplay content or the database GUI.

## Contract

### Processes

| Process | Port | Config | Log |
|---------|------|--------|-----|
| `authserver` | 3724 | `env/dist/etc/authserver.conf` | `Auth.log` |
| `worldserver` | 8085 | `env/dist/etc/worldserver.conf` | `Server.log`, `Errors.log` |
| MySQL | 3306 | server DB config | MySQL error log |

### Required configuration

- `LoginDatabaseInfo`, `WorldDatabaseInfo`, `CharacterDatabaseInfo` point at `acore_auth`,
  `acore_world`, `acore_characters`.
- `DataDir` contains `dbc/`, `maps/`, `vmaps/`, `mmaps/`.
- `LogsDir` is writable.
- `RealmID` matches the `realmlist` row.
- `Updates.EnableDatabases=7` and `Updates.AutoSetup=1` for automatic schema setup.
- `Console.Enable=1` for an interactive terminal or a screen/tmux session; `0` for a service with
  null stdin. With `1` and null stdin, the console thread spins on EOF.

### Local and test

- Local: native macOS build in `build/`, install prefix `env/dist/`.
- Test realm: separate databases or a documented reset; `Warden.Enabled=0` for AzerothGhost e2e.
- Production: Ubuntu 24.04 LTS, native binaries, MySQL on the same host, systemd, firewall.

### Lifecycle

Start order: MySQL → `worldserver` → `authserver`. The worldserver clears its realm's
version-mismatch flag; the authserver refuses to start while every realm has flag 3
(`VERSION_MISMATCH | OFFLINE`). Stop order: `authserver` → `worldserver` → MySQL. Use graceful shutdown. Confirm ports are free.

### Health

- Both processes alive and ports listening.
- Database reachable.
- `DataDir` complete.
- `Errors.log` clean at startup.
- A GM test account can log in and enter the world.
- `server info` responds.

## Errors and edge cases

- Port conflict: process exits or logs a bind error.
- Missing client data: map load errors; world may start but terrain and collision are wrong.
- Failed SQL update: startup stops; `Errors.log` records the file and error.
- Database down: connection errors and exit.

## Security

- No credentials in the repository.
- Warden on in production; off only on the test realm.
- SOAP and RA disabled unless explicitly needed and protected.
- GM accounts are named and least-privilege.

## Observability

- Startup summary in `Server.log`.
- Error appender in `Errors.log`.
- Login and realm-list failures in `Auth.log`.
- Optional InfluxDB/Grafana metrics, disabled by default.

## References

- [architecture.md](architecture.md)
- [runbook/development/build-and-install.md](../runbook/development/build-and-install.md)
- [runbook/operation/start-stop.md](../runbook/operation/start-stop.md)
- [runbook/operation/health-check.md](../runbook/operation/health-check.md)
