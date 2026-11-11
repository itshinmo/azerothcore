# Setup on macOS

## When to use

First-time local setup, or rebuilding a Mac after a clean checkout.

## Prerequisites

- macOS with Homebrew
- Xcode Command Line Tools
- MySQL 8.4
- CMake 3.16+
- C++20 compiler (Apple clang)
- Boost, OpenSSL 3, readline
- Optional: Go 1.26+ for live e2e, Node 26 for the database GUI
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

7. Create a GM account:

   ```bash
   cd env/dist/bin
   ./worldserver
   # console:
   account create ADMIN <password>
   account set gmlevel ADMIN 3 -1
   ```

8. Start both servers:

   ```bash
   make start
   make status
   make logs
   ```

## Verification

- `authserver` listens on 3724; `worldserver` on 8085.
- `env/dist/logs/Errors.log` has no new startup errors.
- The client can reach the realm and log in.
- A GM account can run `.server info`.

## Troubleshooting

- **OpenSSL not found:** pass `-DOPENSSL_ROOT_DIR="$(brew --prefix openssl@3)"`.
- **MySQL not found:** pass `-DMYSQL_INCLUDE_DIR` and `-DMYSQL_LIBRARY` from `brew --prefix mysql@8.4`.
- **Port in use:** `lsof -nP -iTCP:3724 -sTCP:LISTEN`.
- **Missing maps:** worldserver logs map-file errors; check `DataDir`.
- **DB connection refused:** MySQL is not running or the config host/user is wrong.

## References

- [build-and-install.md](build-and-install.md)
- [database-bootstrap.md](database-bootstrap.md)
- [config-changes.md](config-changes.md)
- [.agents/docs/build.md](../../.agents/docs/build.md)
