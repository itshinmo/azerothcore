# DBeaver

## When to use

Browse or edit the local, test, or production databases; run ad-hoc SQL; inspect schema and
relationships; troubleshoot player or content data.

## Prerequisites

- MySQL 8.4 running.
- DBeaver Community installed.
- The database password for the target environment.
- For production: an SSH tunnel and a read-only MySQL user.

## Install

```bash
brew install --cask dbeaver-community
```

Sequel Ace is a lighter native alternative:

```bash
brew install --cask sequel-ace
```

## Local connection

1. Open DBeaver → **New Database Connection** → **MySQL**.
2. Set:
    - Host: `127.0.0.1`
    - Port: `3306`
    - Database: `acore_world` (or leave blank)
    - Username: `acore`
    - Password: the value in `env/dist/etc/worldserver.conf` (`WorldDatabaseInfo`)
3. Test the connection.
    - If MySQL rejects with **Public Key Retrieval is not allowed**, add the driver property
      `allowPublicKeyRetrieval=true`. If the server requires TLS, enable SSL instead.
4. Finish, then open the database. Repeat for `acore_auth` and `acore_characters`, or switch the
   current database in the SQL editor with `USE acore_auth;`.

## Test realm connection

Use the same host and port, but:

- User: `acore_test`
- Password: the value in the test config (`env/test/etc/worldserver.conf`) or `tools/dev/config.env`
- Databases: `acore_test_auth`, `acore_test_characters`, `acore_test_world`

Never point the test connection at the live `acore_*` databases.

## Production connection

Production is read-only.

1. Create an SSH tunnel on your Mac:

    ```bash
    ssh -L 3307:127.0.0.1:3306 <user>@<host>
    ```

2. In DBeaver, use:
    - Host: `127.0.0.1`
    - Port: `3307`
    - User: the read-only production user
    - Password: from the human operator, never committed
3. Enable the connection's read-only option and use a database user that only has `SELECT`.
4. Verify the grant without attempting a write:

   ```sql
   SHOW GRANTS FOR CURRENT_USER();
   ```

   The result must not include `INSERT`, `UPDATE`, `DELETE`, or `ALL PRIVILEGES` on the game
   databases.

Do not expose MySQL to the internet. Do not use `root`. Do not store production credentials in the
repository or in chat.

## Browse

- **Databases** → expand `acore_world`, `acore_characters`, or `acore_auth`.
- **Tables** → double-click a table to open its data.
- **Data** tab: filter, sort, paginate. Add `LIMIT` for large tables; `creature`, `item_template`, and
  `quest_template` are large.
- **Properties/DDL** tab: columns, indexes, keys.
- **ER Diagram** tab: relationships DBeaver can infer. AzerothCore has very few real foreign keys, so
  use [schema-guide.md](schema-guide.md) and [erd.md](erd.md) for the curated map.

## Query

1. Open **SQL Editor** from the toolbar or the table's SQL button.
2. Run with `Cmd+Enter` (macOS) or the execute button.
3. Use `EXPLAIN` before a slow query.
4. Keep autocommit off for edits and commit only after verifying the rows.
5. Use `LIMIT` on exploratory queries.

Common read-only queries are in [common-queries.md](common-queries.md).

## Edit

1. Back up first:

    ```bash
    make backup
    ```

2. Prefer the SQL editor with a scoped `WHERE`:

    ```sql
    UPDATE acore_world.creature_template
    SET name = 'New name'
    WHERE entry = 12345;
    ```

3. Or edit a cell in the **Data** tab and save. DBeaver prompts to commit.
4. Verify with a `SELECT` using the same key.
5. For schema changes or content additions, write a repo SQL file instead:
    - `data/sql/custom/db_*` for re-applicable project SQL.
    - `data/sql/updates/pending_db_*` for one-time updates.
    - Run `python3 apps/codestyle/codestyle-sql.py` and `make verify-sql`.

## Safety rules

- Never use `root` for DBeaver.
- Never write to production.
- Back up before a write batch.
- Use a narrow `WHERE`; never `UPDATE`/`DELETE` without one.
- Do not edit `data/sql/base/`, `data/sql/archive/`, or `data/sql/updates/db_*`.
- Do not commit DBeaver workspace files, query history, or connection profiles.
- Do not paste player data or credentials into chat, issues, or docs.
- DBeaver does not audit edits or take pre-write backups; the backup and SQL review are the record.

## Troubleshooting

- **Public Key Retrieval is not allowed:** add `allowPublicKeyRetrieval=true`, or use SSL.
- **Access denied:** user/host grant mismatch; check the user's `@host` (bootstrap creates
  `acore`@`localhost`; a TCP connection may match `acore`@`127.0.0.1`) and the password.
- **Unknown database:** wrong database name; use `acore_*` or `acore_test_*`.
- **Communications link failure:** MySQL down, wrong port, or tunnel closed.
- **Read-only error:** expected on production; use the local/test connection.
- **Lock wait timeout:** another transaction holds rows; roll back and retry with a narrower scope.

## Verification

- `SELECT 1` works.
- The table list shows the expected three databases.
- `SHOW GRANTS FOR CURRENT_USER();` shows only `SELECT` on production.
- A local backup exists before any edit.

## References

- [schema-guide.md](schema-guide.md)
- [common-queries.md](common-queries.md)
- [runbook/operation/backup-restore.md](../operation/backup-restore.md)
- [decisions/ADR-008-database-access-with-dbeaver.md](../../decisions/ADR-008-database-access-with-dbeaver.md)
