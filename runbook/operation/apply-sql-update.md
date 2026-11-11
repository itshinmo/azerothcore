# Apply SQL update

## When to use

Applying a pending or custom SQL file to a local or test database, or checking whether an update was
applied.

## Safety

- Local and test are different targets. Do not use a local command against a test database, or a test
  command against a local database.
- Back up the target database before any write.
- Never apply production SQL from an agent session.
- `worldserver -d` applies pending and custom SQL; it is not a read-only dry run. It also changes
  `realmlist.flag`, so run it only against the intended config.

## Identify the file type

| Path | Type | Re-applicable |
|------|------|---------------|
| `data/sql/updates/pending_db_*` | one-time, upstream-shaped | no |
| `data/sql/custom/db_*` | project SQL | yes |
| `data/sql/updates/db_*` | merged | never edit |
| `data/sql/base/` | schema seed | never edit |

## Local procedure

1. Back up the local databases:

   ```bash
   make backup
   ```

2. Check whether the file was already applied:

   ```bash
   mysql -u acore -p acore_world \
     -e "SELECT name,state,timestamp FROM updates WHERE name LIKE '%<file>%';"
   ```

3. Apply with the local config:

   ```bash
   ./env/dist/bin/worldserver -d
   ```

4. Verify:
   - intended rows exist;
   - unintended rows were not changed;
   - `updates` has the expected row;
   - `Errors.log` has no new error.

5. Reload the affected cache if the server is running:

   ```text
   .reload creature_template
   .reload quest_template
   .reload item_template
   .reload npc_vendor
   ```

## Test-realm procedure

The verifier owns this path. It checks that all three test database names are distinct from the local
names, backs up the test databases, applies with the test config, and runs row checks:

```bash
make verify-sql
```

- Auto-applies when `env/test/etc/worldserver.conf` exists.
- `VERIFY_SQL_APPLY=0 make verify-sql` runs lint only.
- `VERIFY_SQL_APPLY=1 make verify-sql` fails if the test config is missing.
- The local `acore_*` databases are never used by this path.

Manual test apply, only when the verifier path cannot be used:

```bash
# Inspect the test config first; all three names must contain "test".
grep -E 'DatabaseInfo' env/test/etc/worldserver.conf

# Set these from the test config. Do not use the local acore_* names.
TEST_HOST="127.0.0.1"
TEST_USER="acore_test"
TEST_AUTH="acore_test_auth"
TEST_CHAR="acore_test_characters"
TEST_WORLD="acore_test_world"

# Back up the test databases with the test credentials.
TEST_BACKUP="var/backups/manual/test-$(date +%Y%m%d-%H%M%S)"
umask 077
mkdir -p "$TEST_BACKUP"
chmod 700 "$TEST_BACKUP"
mysqldump -h "$TEST_HOST" -u "$TEST_USER" -p \
  --single-transaction --routines --triggers --no-tablespaces \
  --databases "$TEST_AUTH" "$TEST_CHAR" "$TEST_WORLD" \
  > "$TEST_BACKUP/test.sql"

# Apply with the test config.
./env/dist/bin/worldserver -d -c env/test/etc/worldserver.conf
```

Direct apply to one test database:

```bash
file="data/sql/updates/pending_db_world/rev_<timestamp>.sql"
mysql -h "$TEST_HOST" -u "$TEST_USER" -p --show-warnings "$TEST_WORLD" < "$file"
```

Never substitute `acore_world` here.

## Failure

- Stop. Do not retry blindly.
- Read `Errors.log` and the MySQL error.
- Restore the target backup if data changed.
- Fix on the test realm first.
- Never edit an applied file; add a new one.

## Rules

- Never apply production SQL from an agent session.
- Never ignore a nonzero exit code.
- Never use `--force`.
- Keep the backup until verification passes.
- A test-realm result does not prove production; production needs its own backup and approval.

## References

- [.agents/docs/sql-guidelines.md](../../.agents/docs/sql-guidelines.md)
- [.ai/skills/pending-sql-import/SKILL.md](../../.ai/skills/pending-sql-import/SKILL.md)
- [backup-restore.md](backup-restore.md)
- [rollback.md](rollback.md)
- [test-realm.md](test-realm.md)
