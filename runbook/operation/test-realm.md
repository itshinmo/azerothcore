# Test realm

## When to use

Before live e2e, before a risky database change, or when testing GM tools and player-visible behavior.

## Goal

An isolated realm that cannot touch production or the normal local characters. It may share binaries
and client data, but not databases.

## Prerequisites

- MySQL running.
- A dedicated MySQL admin user with `CREATE USER`, `CREATE DATABASE`, and `GRANT` privileges. Do not
  use `root`; set `MYSQL_ADMIN_USER` and `MYSQL_ADMIN_PASSWORD`.
- Disk space for a second set of databases.
- A copy of the client data (read-only is fine).
- Ports 3824 and 8185 free, or override `TEST_AUTH_PORT` / `TEST_WORLD_PORT`.
- `screen` for the background sessions.

One-time admin user creation, run by a human with the MySQL root account:

```sql
CREATE USER IF NOT EXISTS 'acore_admin'@'127.0.0.1' IDENTIFIED BY '<admin-password>';
GRANT ALL PRIVILEGES ON *.* TO 'acore_admin'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
```

## Automation

The script creates and runs the test realm on ports 3824 (auth) and 8185 (world), with its own
configs under `env/test/etc/` and logs under `env/test/logs/`:

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

`TEST_DB_PASSWORD` and `TEST_DB_USER` may contain only letters, digits, dot, underscore, and hyphen.
The script rejects `MYSQL_ADMIN_USER=root`.

Or through `make`:

```bash
make test-realm CMD=setup
make test-realm CMD=start
make test-realm CMD=status
make test-realm CMD=stop
```

The test realm runs with `Console.Enable=0`. Detached runs have no interactive console, and a
console prompt on a closed stdin spins forever, filling `worldserver.console.log` with `AC> `
lines; see [specs/server.md](../../specs/server.md). The local stack keeps its console available
through `screen`, so it stays at `1`; both stacks rotate their console log on the next start when
it exceeds 100 MB (override with `MAX_CONSOLE_LOG_BYTES`). Use `status`, the log files, or the GM API
on the test realm instead.

Put local values in `tools/dev/config.env` (ignored); the template is
`tools/dev/config.env.example`. The script refuses to reset databases whose names do not contain
`test`. It backs up nothing by itself; `make verify-sql` backs up the test databases before an apply.

## Setup

1. Create separate databases and a test user:

   ```sql
   CREATE USER IF NOT EXISTS 'acore_test'@'127.0.0.1' IDENTIFIED BY '<test_password>';
   CREATE DATABASE acore_test_auth;
   CREATE DATABASE acore_test_characters;
   CREATE DATABASE acore_test_world;
   GRANT ALL PRIVILEGES ON acore_test_auth.* TO 'acore_test'@'127.0.0.1';
   GRANT ALL PRIVILEGES ON acore_test_characters.* TO 'acore_test'@'127.0.0.1';
   GRANT ALL PRIVILEGES ON acore_test_world.* TO 'acore_test'@'127.0.0.1';
   ```

2. Copy the server configs to a test directory and restrict them:

   ```bash
   mkdir -p env/test/etc env/test/logs
   cp env/dist/etc/authserver.conf env/test/etc/
   cp env/dist/etc/worldserver.conf env/test/etc/
   chmod 700 env/test/etc env/test/logs
   chmod 600 env/test/etc/*.conf
   ```

3. Point the test configs at the test databases, test logs, and the same `DataDir`.
4. Set `Warden.Enabled=0` and `Console.Enable=0` in the test worldserver config.
5. Set a different realm name/port if both realms run at once.
6. Start the test worldserver first, then the test authserver; the updater populates the test
   databases. Pass the test config explicitly and keep the test realm out of `tools/dev/server.sh`:

   ```bash
   cd env/dist/bin
   ./worldserver -c ../../../env/test/etc/worldserver.conf
   # in a second terminal:
   ./authserver -c ../../../env/test/etc/authserver.conf
   ```

   Adjust the relative path to your checkout. The `-c` argument also keeps the process distinct from
   the local server for `tools/dev/server.sh`.
7. Create dedicated GM accounts per role.
8. Run the smoke test.

## Reset

1. Stop the test servers.
2. Drop and recreate the test databases (only the test ones).
3. Start the servers; the updater repopulates.
4. Recreate the test accounts.
5. Verify login.

## Rules

- Never point the test config at `acore_auth`, `acore_characters`, or `acore_world`.
- Never enable the test realm on a production host.
- Keep test accounts separate from player accounts.
- Delete test characters after a run if they hold unique names.

## Verification

- The test realm appears in the realm list.
- After `start`, `realmlist.flag` for the test realm is `0`:

  ```bash
  mysql -u acore_test -p acore_test_auth -e "SELECT id, flag FROM realmlist;"
  ```

  `start` clears the offline bit that authserver sets on boot. A logged-in client can still see the
  realm as offline until authserver refreshes its cached list (`RealmsStateUpdateDelay`, default 20s).
- A test GM account logs in.
- `Warden.Enabled=0` is confirmed.
- The production databases have no new rows from the test run.

## References

- [specs/testing-and-release.md](../../specs/testing-and-release.md)
- [e2e/README.md](../../e2e/README.md)
- [.agents/docs/e2e-policy.md](../../.agents/docs/e2e-policy.md)
