# Setup on macOS

## When to use

First-time local setup, or rebuilding a Mac after a clean checkout.

Read [environment-overview.md](environment-overview.md) first if you do not yet know the difference
between the local server, the test realm, and the bot rig. This page only covers the local one.

## What you are setting up

You are building two programs, `authserver` and `worldserver`, installing them into `env/dist`, and
pointing them at one MySQL instance. The local stack uses ports 3724 (login) and 8085 (world). The
game client is not part of this repository; it needs `DataDir` with `dbc/`, `maps/`, `vmaps/`, and
`mmaps/`, and its `realmlist.wtf` must point at `127.0.0.1`.

## Prerequisites

- macOS with Homebrew
- Xcode Command Line Tools
- MySQL 8.4
- CMake 3.16+
- C++20 compiler (Apple clang)
- Boost, OpenSSL 3, readline
- Optional: Go 1.26+ for live e2e, DBeaver for database browsing
- `screen` for background server sessions

## Steps

1. Install dependencies:

   ```bash
   xcode-select --install
   brew install cmake openssl@3 readline boost mysql@8.4 ccache jq screen
   brew install go node
   ```

2. Start MySQL and confirm it is reachable:

   ```bash
   brew services start mysql@8.4
   mysql -u root -e "SELECT VERSION();"
   ```

3. Create the databases:

   ```bash
   mysql -u root -p < data/sql/create/create_mysql.sql
   ```

4. Build and install:

   ```bash
   cmake -S . -B build \
     -DCMAKE_BUILD_TYPE=RelWithDebInfo \
     -DSCRIPTS=static -DMODULES=static \
     -DCMAKE_INSTALL_PREFIX="$PWD/env/dist"
   cmake --build build -j"$(sysctl -n hw.ncpu)"
   cmake --install build
   ```

5. Configure the servers:

   ```bash
   $EDITOR env/dist/etc/authserver.conf
   $EDITOR env/dist/etc/worldserver.conf
   ```

   Set:
   - `LoginDatabaseInfo`, `WorldDatabaseInfo`, `CharacterDatabaseInfo`
   - `DataDir` (must contain `dbc/`, `maps/`, `vmaps/`, `mmaps/`)
   - `LogsDir`
   - `RealmID` matching `acore_auth.realmlist`

6. Confirm client data:

   ```bash
   DATA_DIR="$(grep -E '^DataDir' env/dist/etc/worldserver.conf | cut -d'"' -f2)"
   ls "$DATA_DIR"/dbc | head
   ls "$DATA_DIR"/maps | head
   ls "$DATA_DIR"/vmaps | head
   ls "$DATA_DIR"/mmaps | head
   ```

7. Optional: copy `tools/dev/config.env.example` to `tools/dev/config.env` for test-realm and backup
   overrides. Do not commit it.

8. Start the stack and create a GM account:

   ```bash
   make start
   make console
   ```

   At the `AC>` prompt:

   ```text
   .account create ADMIN <password>
   .account set gmlevel ADMIN 3 -1
   ```

   Leave the console with `Ctrl+A` then `D`. Detaching does not stop the server.

   Use a leading dot if the console echoes a command back without running it. Write the account name
   in upper case; account names are stored upper-cased.

9. Check the result:

   ```bash
   make status
   make logs
   ```

10. Point a client at the local realm. Use a copy whose `Data/enUS/realmlist.wtf` says
    `set realmlist 127.0.0.1`; do not reuse the test-realm or bot-rig client copy. The local
    `acore_auth.realmlist` row must carry `port = 8085` and `flag = 0`.

## Verification

- `authserver` listens on 3724; `worldserver` on 8085.
- `env/dist/logs/Errors.log` has no new startup errors.
- The client can reach the realm and log in.
- A GM account can run `.server info`.

## Troubleshooting

- **OpenSSL not found:** pass `-DOPENSSL_ROOT_DIR="$(brew --prefix openssl@3)"`.
- **MySQL not found:** pass `-DMYSQL_INCLUDE_DIR` and `-DMYSQL_LIBRARY` from `brew --prefix mysql@8.4`.
- **Port in use:** `lsof -nP -iTCP:3724 -sTCP:LISTEN`. An old stack can survive a `make stop`; stop
  the process that owns the port before starting again.
- **Client returns to the realm list after selecting the realm:** the authserver told the client the
  wrong world port, or the realm is flagged offline. Read the authserver log line
  `Added realm "AzerothCore" at 127.0.0.1:<port>`; it must say 8085. Then check
  `acore_auth.realmlist` (`port = 8085`). Fixing the row needs the authserver restarted so it
  re-reads the table; its boot marks the realm offline, so clear `flag = 0` after that restart.
  `make start` already performs both steps in the right order.
- **Missing maps:** worldserver logs map-file errors; check `DataDir`.
- **DB connection refused:** MySQL is not running or the config host/user is wrong.

## References

- [environment-overview.md](environment-overview.md)
- [build-and-install.md](build-and-install.md)
- [database-bootstrap.md](database-bootstrap.md)
- [config-changes.md](config-changes.md)
- [.agents/docs/build.md](../../.agents/docs/build.md)
