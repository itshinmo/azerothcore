# Database bootstrap

## When to use

First-time setup, a clean test realm, or rebuilding a database from the SQL tree.

## Prerequisites

- MySQL 8.4 running.
- A MySQL administrative account.
- `data/sql/` present.

## Steps

1. Create the databases and the `acore` user:

   ```bash
   mysql -u root -p < data/sql/create/create_mysql.sql
   ```

   This creates `acore_auth`, `acore_characters`, `acore_world`, and grants the `acore` user.

2. If the server connects over TCP `127.0.0.1`, confirm the user can connect:

   ```bash
   mysql -h 127.0.0.1 -u acore -p -e "SELECT 1"
   ```

   If it fails, add the matching host grant:

   ```sql
   CREATE USER IF NOT EXISTS 'acore'@'127.0.0.1' IDENTIFIED BY '<password>';
   GRANT ALL PRIVILEGES ON acore_auth.* TO 'acore'@'127.0.0.1';
   GRANT ALL PRIVILEGES ON acore_characters.* TO 'acore'@'127.0.0.1';
   GRANT ALL PRIVILEGES ON acore_world.* TO 'acore'@'127.0.0.1';
   FLUSH PRIVILEGES;
   ```

3. Configure the database strings in `env/dist/etc/{authserver,worldserver}.conf`.

4. Let the servers populate the schema. Start `worldserver` first, then `authserver`; worldserver
   clears the realm's version-mismatch flag, and authserver refuses to start while every realm has
   flag 3 (`VERSION_MISMATCH | OFFLINE`). With `Updates.AutoSetup=1`, base SQL runs when the database
   is empty, then updates from `updates_include`.

5. Confirm the applied updates:

   ```bash
   mysql -u acore -p acore_world \
     -e "SELECT name,state,timestamp FROM updates ORDER BY timestamp DESC LIMIT 10;"
   ```

6. Check `env/dist/logs/Errors.log` for failed SQL.

## What the updater applies

| Directory | State | Purpose |
|-----------|-------|---------|
| `base/db_*` | — | schema and seed for an empty database |
| `updates/db_*` | `RELEASED` | merged release updates |
| `updates/pending_db_*` | `PENDING` | in-flight changes |
| `custom/db_*` | `CUSTOM` | project-specific re-applicable SQL |
| `archive/db_*` | `ARCHIVED` | historical updates |

## Verification

- Three databases exist.
- `updates` is populated.
- `Errors.log` has no SQL failures.
- A GM account can log in.

## Troubleshooting

- **Access denied:** the user/host grant does not match the config string.
- **Duplicate filename:** two included directories contain a file with the same name; rename one.
- **Failed update:** read `Errors.log`, restore the backup, fix the file, retry on test.
- **Charset/collation errors:** use MySQL 8.4 and the provided schema.

## References

- [specs/database.md](../../specs/database.md)
- [apply-sql-update.md](../operation/apply-sql-update.md)
- [backup-restore.md](../operation/backup-restore.md)
- [data/sql/create/create_mysql.sql](../../data/sql/create/create_mysql.sql)
