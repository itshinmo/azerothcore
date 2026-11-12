# Development scripts

Thin wrappers for the local loop. They are safe to run repeatedly and print what they check.

| Script | Purpose |
|--------|---------|
| `common.sh` | shared paths and config helpers |
| `doctor.sh` | binaries, config, databases, client data, ports, logs |
| `server.sh` | start, stop, restart, status, logs |
| `backup.sh` | dump auth, characters, and world with checksum and manifest |
| `verify.sh` | verification tiers: docs, sql, cpp, smoke, full |
| `check-docs.mjs` | relative Markdown link check |
| `command-index.py` | regenerate or check the GM command index |
| `test-realm.sh` | create, reset, start, stop an isolated test realm |
| `backup-schedule.sh` | install/remove a daily backup schedule |
| `config.env.example` | template for local overrides |

Run them through `make` from the repository root:

```bash
make doctor
make start
make status
make logs
make console
make stop
make backup
make verify-docs
make verify-sql
make verify-cpp
make verify-smoke
make verify-full
```

`server.sh` runs the servers inside detached `screen` sessions. The servers read console input from
stdin; with `/dev/null` they spin on EOF and write `AC> ` forever. Attach with `make console`; detach
with `Ctrl-A d`. If `screen` is unavailable, set `Console.Enable = 0` for a service run and manage it
through SOAP/RA or the service manager.

`backup.sh` uses the configured `acore` user. It requires the three databases to share a host and
user; extend the script if that changes. Dumps go to `var/backups/manual/<timestamp>/`.

## Rules

- Do not put credentials in these scripts.
- Do not add a command that writes to production.
- A new script gets a row in this table and a runbook entry.
