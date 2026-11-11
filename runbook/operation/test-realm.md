# Test realm

## When to use

Before live e2e, before a risky database change, or when testing GM tools and player-visible behavior.

## Goal

An isolated realm that cannot touch production or the normal local characters. It may share binaries
and client data, but not databases.

## Prerequisites

- MySQL running.
- Disk space for a second set of databases.
- A copy of the client data (read-only is fine).
- Ports 3724 and 8085 free, or a second pair of ports.

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
4. Set `Warden.Enabled=0` in the test worldserver config.
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
- A test GM account logs in.
- `Warden.Enabled=0` is confirmed.
- The production databases have no new rows from the test run.

## References

- [specs/testing-and-release.md](../../specs/testing-and-release.md)
- [e2e/README.md](../../e2e/README.md)
- [.agents/docs/e2e-policy.md](../../.agents/docs/e2e-policy.md)
