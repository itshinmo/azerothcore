# Developer commands

## When to use

Day-to-day development, building, testing, running the server, applying SQL, and verifying a change.
Each command has a one-line purpose so a human can choose the right one without guessing.

## Conventions

- Run from the repository root unless a step says otherwise.
- The current checkout uses `build/` for the normal build and `build-verify/` for the test and
  `-Werror` build. The upstream `acore.sh` default is `var/build/obj`; this checkout does not use it.
- Install prefix: `env/dist/`.
- Local config: `env/dist/etc/*.conf` (ignored).
- Logs: whatever `LogsDir` says; the local config uses `env/dist/logs/`.

## Quick map

| Command | What it does |
|---------|--------------|
| `make doctor` | Checks binaries, config, databases, client data, ports, pending SQL, logs, disk. |
| `make configure` | Configures `build/` only. |
| `make configure-verify` | Configures `build-verify/` with tests and `-Werror`. |
| `make build` | Configures if needed, builds, and installs into `env/dist`. |
| `make install` | Alias of `make build`: builds and installs into `env/dist`. |
| `make test` | Configures `build-verify`, builds it, runs the unit tests. |
| `make test-tools` | Runs the Python tool unit tests (`tools/dev/tests`). |
| `make command-index` | Regenerates the GM command index from `cs_*.cpp`. |
| `make content-audit` | Read-only content audit of the world database; see [content-audit.md](../operation/content-audit.md). |
| `make world-export` | Export world data artifacts; see [world-export.md](../operation/world-export.md). |
| `make world-api` | Serve the exported catalog on loopback; see [world-api.md](../operation/world-api.md). |
| `make verify-docs` | Checks knowledge-layer Markdown links and the generated command index. |
| `make verify-sql` | Runs the SQL linter; applies pending/custom SQL to the test realm when configured. |
| `make verify-cpp` | C++ codestyle, cppcheck (2.22.x), `-Werror` build, unit tests. |
| `make verify-smoke` | Starts the local stack, health-checks it, stops it. |
| `make verify-full` | Runs docs, C++, SQL, and smoke in order. |
| `make start` | Starts worldserver then authserver inside `screen`. |
| `make stop` | Stops authserver then worldserver. |
| `make restart` | Stops then starts both servers. |
| `make status` | Shows process and port state. |
| `make logs` | Tails the main server logs. |
| `make console` | Attaches to the worldserver `screen` console. |
| `make backup` | Dumps auth, characters, and world with a checksum and manifest. |
| `make test-realm CMD=...` | Runs `setup`, `reset`, `start`, `stop`, or `status` for the test realm. |
| `make backup-schedule CMD=...` | Installs, removes, or checks the daily backup schedule. |
| `make clean` | Deletes `build/` and `build-verify/`. |

## Build

### Normal build

```bash
make build
```

Equivalent manual commands:

```bash
cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DSCRIPTS=static -DMODULES=static \
  -DCMAKE_INSTALL_PREFIX="$PWD/env/dist"
cmake --build build -j"$(sysctl -n hw.ncpu)"
cmake --install build
```

- `-S . -B build` configures out-of-source. In-source builds are blocked.
- `-DCMAKE_BUILD_TYPE=RelWithDebInfo` gives optimized binaries with symbols.
- `-DSCRIPTS=static -DMODULES=static` links scripts and modules into the server.
- `-DCMAKE_INSTALL_PREFIX` controls where `bin/` and `etc/` land.
- `--build ... -j` compiles in parallel.
- `--install` copies binaries and `.conf.dist` templates to `env/dist`.

### Reconfigure

```bash
cmake -S . -B build
```

Run only after changing `CMakeLists.txt`, a module list, or a CMake option. A normal build reuses the
cache.

### CMake options

| Option | Purpose |
|--------|---------|
| `-DCMAKE_BUILD_TYPE=Debug` | Debug symbols, no optimization. |
| `-DCMAKE_BUILD_TYPE=Release` | Optimized, no debug symbols. |
| `-DCMAKE_BUILD_TYPE=RelWithDebInfo` | Optimized with symbols; default for this checkout. |
| `-DBUILD_TESTING=ON` | Builds Google Test and `src/test/unit_tests`. |
| `-DNOPCH=1` | Disables precompiled headers; use for a clean toolchain check. |
| `-DSCRIPTS=static|dynamic|none` | How content scripts are linked. |
| `-DMODULES=static|dynamic|none` | How modules are linked. |
| `-DDISABLED_AC_MODULES="mod1;mod2"` | Skips specific modules. |
| `-DAPPS_BUILD=all|auth-only|world-only|none` | Which server binaries to build. |
| `-DTOOLS_BUILD=all|db-only|maps-only|none` | Builds extractors and `dbimport`. |
| `-DCMAKE_CXX_FLAGS=-Werror` | Treats warnings as errors. |
| `-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY` | Workaround for a macOS SDK try-link failure with `-Werror`; does not change the output. |
| `-DCMAKE_OSX_SYSROOT=...` | Select a working macOS SDK when the linker rejects the newest one. |
| `-DCMAKE_INSTALL_PREFIX=...` | Install location. |

The `make` targets pass the macOS sysroot/zlib/readline flags automatically when they exist.

### Clean

```bash
rm -rf build build-verify
```

Do not delete `env/dist/etc/*.conf`, `env/dist/logs`, or `DataDir` unless you intend to.

## Tests and verification

### Unit tests

```bash
make test
```

This configures `build-verify` with `BUILD_TESTING=ON`, `-Werror`, and the local macOS flags, builds
the test target, and runs `build-verify/src/test/unit_tests`.

Manual equivalent:

```bash
cmake -S . -B build-verify \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DSCRIPTS=static -DMODULES=static \
  -DBUILD_TESTING=ON \
  -DCMAKE_CXX_FLAGS=-Werror \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DCMAKE_INSTALL_PREFIX="$PWD/env/dist"
cmake --build build-verify -j"$(sysctl -n hw.ncpu)"
./build-verify/src/test/unit_tests
```

`ctest` also works after a test build:

```bash
ctest --test-dir build-verify -R unit --output-on-failure
```

### C++ gate

```bash
make verify-cpp
```

Runs:
- `python3 apps/codestyle/codestyle-cpp.py`
- `cppcheck --force --inline-suppr --suppressions-list=.suppress.cppcheck src/`
- `make configure-verify`, build, unit tests, then `cmake --install build-verify` into `env/dist`

`cppcheck` is required. Install it with `brew install cppcheck` or `apt install cppcheck`.

### Docs gate

```bash
make verify-docs
```

Scans the project knowledge layer for broken relative Markdown links and checks that
`runbook/gm/command-index.md` is current. It skips `node_modules` and symlinked directories.

### SQL gate

```bash
make verify-sql
```

- Runs `python3 apps/codestyle/codestyle-sql.py`.
- If `env/test/etc/worldserver.conf` exists and pending/custom SQL files exist, backs up the test
  databases, applies the SQL with `worldserver -d -c env/test/etc/worldserver.conf`, and checks
  `updates` and `creature` rows.
- `VERIFY_SQL_APPLY=0` forces lint only.
- `VERIFY_SQL_APPLY=1` forces an apply and fails if the test config is missing.

### Smoke gate

```bash
make verify-smoke
```

Requires a stopped stack. Starts worldserver then authserver, runs `doctor --expect-running`, then
stops both. It refuses if any server is already running or the stack is partial.

### Full gate

```bash
make verify-full
```

Runs docs, C++, SQL, then smoke.

### Live e2e

Only when the user asked or an existing test broke.

```bash
cd e2e
go test -tags=e2e ./smoke -count=1 -v -timeout 30m -parallel 1
```

Requires a running test realm or local stack with `Warden.Enabled=0`. See `e2e/README.md` and
[runbook/operation/test-realm.md](../operation/test-realm.md).

## Server lifecycle

### Normal

```bash
make start
make status
make logs
make console
make stop
```

- `make start` starts **worldserver first** because it clears the realm's version-mismatch flag, then
  authserver.
- Both run inside detached `screen` sessions because the console reads stdin. With `/dev/null` the
  console spins on EOF.
- `make console` attaches to worldserver; detach with `Ctrl-A d`.
- `make stop` sends SIGTERM to authserver, then worldserver.

### Manual

```bash
cd env/dist/bin
./worldserver --help
./worldserver --version
./worldserver -d                 # apply updates and exit
./worldserver -c /path/to/worldserver.conf
./authserver -c /path/to/authserver.conf
```

- `-d` / `--dry-run` applies database updates and exits. It is not a read-only SQL check.
- `-c` selects a config; use it for the test realm.
- `--config-policy` overrides config severity.

Start order is MySQL → worldserver → authserver. Stop order is authserver → worldserver.

### Console commands

```text
server info
server shutdown 0
server restart 10
server set loglevel 3
server set motd <text>
account create <user> <password>
account set gmlevel <user> <level> -1
```

## Database

### MySQL shell

```bash
mysql -h 127.0.0.1 -u acore -p -e "SELECT 1" acore_world
```

Use the password in `env/dist/etc/worldserver.conf`. Never use `root` for scripts or tools.

### Create databases

```bash
mysql -u root -p < data/sql/create/create_mysql.sql
```

This is a human one-time bootstrap. It creates `acore_auth`, `acore_characters`, `acore_world`, and
the `acore` user.

### SQL updates

- Project, re-applicable SQL: `data/sql/custom/db_auth|db_characters|db_world/`.
- One-time, upstream-shaped SQL: `data/sql/updates/pending_db_auth|characters|world/`.
- Do not edit `data/sql/base/`, `data/sql/archive/`, or `data/sql/updates/db_*`.

Apply with the server updater:

```bash
./env/dist/bin/worldserver -d
```

Apply the same file directly after a backup:

```bash
file="data/sql/updates/pending_db_world/rev_<timestamp>.sql"
mysql -u acore -p --show-warnings acore_world < "$file"
```

Run the SQL linter first:

```bash
python3 apps/codestyle/codestyle-sql.py
```

### DBeaver

Use DBeaver for browsing, queries, and small edits. See
[runbook/database/dbeaver.md](../database/dbeaver.md).

### Test realm

```bash
export TEST_DB_PASSWORD='<test-password>'
export MYSQL_ADMIN_USER='acore_admin'
export MYSQL_ADMIN_PASSWORD='<admin-password>'
bash tools/dev/test-realm.sh setup
bash tools/dev/test-realm.sh start
bash tools/dev/test-realm.sh status
bash tools/dev/test-realm.sh stop
bash tools/dev/test-realm.sh reset
```

Ports 3824 (auth) and 8185 (world). Uses `env/test/etc` and `env/test/logs`. The script refuses
`root` and refuses setup/reset while the test stack is running.

## Backups

```bash
make backup
```

Dumps `acore_auth`, `acore_characters`, and `acore_world` to
`var/backups/manual/<timestamp>/acore.sql` with a SHA-256 file. Directory mode 700, file mode 600.

Daily schedule:

```bash
make backup-schedule CMD=install
make backup-schedule CMD=status
make backup-schedule CMD=remove
```

Restore procedure: [runbook/operation/backup-restore.md](../operation/backup-restore.md).

## Client data

`DataDir` must contain `dbc/`, `maps/`, `vmaps/`, and `mmaps/`.

Download the prepared data (CI-style, no client extraction):

```bash
./acore.sh client-data
```

Extract from a client copy:

```bash
# Build extractors first: -DTOOLS_BUILD=all
apps/extractor/extractor.sh
```

Then point `DataDir` in `worldserver.conf` at the extracted data root.

## `acore.sh` dashboard

```bash
./acore.sh --help
```

Useful commands:

| Command | Purpose |
|---------|---------|
| `./acore.sh install-deps` | Installs OS packages and starts MySQL in CI-style setups. |
| `./acore.sh setup-db` | Creates the databases from `create_mysql.sql`. |
| `./acore.sh compiler configure` | Configures the upstream-style build. |
| `./acore.sh compiler build` | Builds. |
| `./acore.sh compiler clean` | Cleans the build. |
| `./acore.sh client-data` | Downloads prepared client data. |
| `./acore.sh run-worldserver` | Starts worldserver through the simple restarter. |
| `./acore.sh run-authserver` | Starts authserver. |
| `./acore.sh module install|remove|list` | Manages modules. |
| `./acore.sh docker prod:up` | Starts the Docker stack. |
| `./acore.sh test` | Runs the dashboard/CI test suite. |

This checkout currently uses `make` and `build/`; `acore.sh compiler` uses `var/build/obj`. Pick one
workflow and do not mix build directories.

## Code style

```bash
python3 apps/codestyle/codestyle-cpp.py
python3 apps/codestyle/codestyle-sql.py
cppcheck --force --inline-suppr --suppressions-list=.suppress.cppcheck src/ --output-file=report.txt
```

- The C++ linter checks blank lines, trailing whitespace, flag helpers, `GetTypeId`, qualifiers.
- The SQL linter checks idempotency, semicolon/backtick/blank-line rules, spawn delete/update filters.
- `cppcheck` must produce an empty report.

## Git and worktrees

```bash
git worktree list
git worktree add -b feat/<slug> ../azerothcore-worktrees/feat-<slug> local-server-setup
```

One task, one branch, one worktree. Branch from `local-server-setup`. `master` mirrors upstream and
fast-forwards only; never commit project work on it. Never edit another worktree. Never commit, push,
or deploy without human and reviewer approval. Topology and upstream sync:
[worktrees-and-branches.md](worktrees-and-branches.md).

## CI

`.github/workflows/fork-ci.yml` runs on this fork:
- docs link and command index check
- SQL lint
- C++ lint and cppcheck
- `-Werror` build and unit tests

The upstream workflows are guarded to `azerothcore/azerothcore-wotlk`; they do not run here.

## Logs and diagnosis

```bash
tail -n 100 env/dist/logs/Server.log
tail -n 100 env/dist/logs/Errors.log
tail -n 50 env/dist/logs/Auth.log
```

Useful in-game checks:

```text
.server info
.reload config
.reload creature_template
.reload quest_template
.reload item_template
.reload npc_vendor
.quest status <quest>
.npc info
```

## References

- [build-and-install.md](build-and-install.md)
- [setup-macos.md](setup-macos.md)
- [database-bootstrap.md](database-bootstrap.md)
- [.agents/docs/build.md](../../.agents/docs/build.md)
- [.agents/docs/cpp-guidelines.md](../../.agents/docs/cpp-guidelines.md)
- [.agents/docs/sql-guidelines.md](../../.agents/docs/sql-guidelines.md)
- [e2e/README.md](../../e2e/README.md)
