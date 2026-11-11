---
name: build-and-run-server
description: Use when building, installing, starting, stopping, or restarting authserver and worldserver locally or on the test realm.
---

# build-and-run-server

## Prerequisites

- macOS with CMake, C++20 compiler, MySQL 8.4, Boost, OpenSSL, readline.
- `DataDir` points at a directory with `dbc/`, `maps/`, `vmaps/`, `mmaps/`.
- Local config exists under `env/dist/etc/`.

## Workflow

1. Check the environment:

   ```bash
   make doctor
   ```

2. Build and install:

   ```bash
   make build
   ```

   Equivalent manual commands:

   ```bash
   cmake -S . -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo \
     -DSCRIPTS=static -DMODULES=static \
     -DCMAKE_INSTALL_PREFIX="$PWD/env/dist"
   cmake --build build -j"$(sysctl -n hw.ncpu)"
   cmake --install build
   ```

3. Start:

   ```bash
   make start
   make status
   ```

4. Confirm readiness: both ports listening, `Errors.log` clean, worldserver prints
   `World Initialized`, and a GM account can log in.
5. Stop:

   ```bash
   make stop
   ```

## Constraints

- Do not run `worldserver` and `authserver` from two checkouts against the same databases at once.
- Do not point a test or production run at the local databases by accident; check the config.
- Do not use `kill -9` unless the process is unresponsive and a human approves.
- Do not commit `env/dist/etc/*.conf`, logs, or data.
- Do not build unless the task needs it; builds are slow.

## Troubleshooting

- Missing maps/vmaps: worldserver logs map-file errors; check `DataDir`.
- DB connection refused: MySQL is not running or the config points at the wrong host/port.
- Port in use: `lsof -nP -iTCP:3724 -sTCP:LISTEN` or `:8085`.
- Schema update failure: read `Errors.log`; restore the backup before retrying.

## Expected output

A running local or test stack with a readiness report and the exact commands used.

## References

- [runbook/development/build-and-install.md](../../../runbook/development/build-and-install.md)
- [runbook/operation/start-stop.md](../../../runbook/operation/start-stop.md)
- [.agents/docs/build.md](../../../.agents/docs/build.md)
