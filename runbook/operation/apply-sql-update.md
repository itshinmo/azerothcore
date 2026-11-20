# Apply SQL update

## When to use

Applying a pending or custom SQL file, or checking whether an update was
applied.

## Safety

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

## Apply procedure

The local worldserver owns the apply path ([ADR-018](../../decisions/ADR-018-realm-strategy.md)):

```bash
python3 apps/codestyle/codestyle-sql.py   # lint first
make stop
make start                                # worldserver applies pending/custom updates on startup
grep -i 'applying' env/dist/logs/Server.log | tail
```

Manual apply to the local databases is reserved for the human; agents lint and restart instead.
Isolated apply validation returns with the launch `dev`/`ptr` realms.

## Failure

- Stop. Do not retry blindly.
- Read `Errors.log` and the MySQL error.
- Restore the target backup if data changed.
- Fix the SQL file, lint again, restart.
- Never edit an applied file; add a new one.

## Rules

- Never apply production SQL from an agent session.
- Never ignore a nonzero exit code.
- Never use `--force`.
- Keep the backup until verification passes.
- A local apply result does not prove production; production needs its own backup and approval.

## References

- [.agents/docs/sql-guidelines.md](../../.agents/docs/sql-guidelines.md)
- [.ai/skills/pending-sql-import/SKILL.md](../../.ai/skills/pending-sql-import/SKILL.md)
- [backup-restore.md](backup-restore.md)
- [rollback.md](rollback.md)
