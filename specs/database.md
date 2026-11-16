# Database

## Purpose

Define the three databases, the SQL tree, the updater contract, and the safety rules for data changes.

## Scope

`acore_auth`, `acore_characters`, `acore_world`, `data/sql/`, the startup updater, and direct client
access.

## Boundary

Owns schema and data lifecycle. Does not own gameplay rules; those are encoded in data and scripts.
Direct client access is in [runbook/database/dbeaver.md](../runbook/database/dbeaver.md).

## Contract

### Databases

- `acore_auth` — accounts, `account_access`, `realmlist`, bans, session keys, logs, `gm_audit_log`.
- `acore_characters` — characters, inventory, quests, mail, guilds, arena teams, achievements.
- `acore_world` — static content: creature/item/quest/gameobject templates, spawns, loot, SmartAI,
  conditions, instance templates.

### SQL tree

| Path | Purpose | Mutability |
|------|---------|------------|
| `data/sql/base/db_*` | full schema and seed for an empty database | immutable |
| `data/sql/updates/db_*` | merged release updates | immutable |
| `data/sql/updates/pending_db_*` | in-flight upstream-shaped changes | writable |
| `data/sql/custom/db_*` | project-specific re-applicable SQL | writable |
| `data/sql/archive/db_*` | historical updates | immutable |

### Updater

- When a database is empty, base SQL is applied in filename order.
- Then files from `updates_include` are applied in filename order.
- Applied files are recorded in `updates` with name, SHA-1, state, timestamp, and speed.
- A changed file is re-applied unless `Updates.AllowRehash` permits it; a renamed file is detected by
  hash.
- A failed update stops startup by default.
- `updates_include` states: `RELEASED`, `PENDING`, `CUSTOM`, `ARCHIVED`, `MODULE`.

### Schema conventions

- InnoDB, utf8mb4, explicit primary keys, indexes on foreign-key-like columns.
- No destructive `DROP`/`TRUNCATE` in project SQL.
- Re-applicable project SQL: `CREATE TABLE IF NOT EXISTS`, `DELETE` + `INSERT`, `REPLACE`, guarded
  `UPDATE`.
- `smart_scripts` rows are rewritten as a full `(entryorguid, source_type)` block.

### Key relationships

- `creature_template.entry` ← `creature.id1`; `creature.guid` ← `creature_addon.guid`.
- `creature_queststarter/ender` link NPCs to quests; `npcflag & 2` is required.
- `quest_template` + `quest_template_addon`; objectives reference creatures, gameobjects, or items.
- `item_template`; mounts are class 15, subclass 5, with a mount spell.
- `gameobject_template` + `gameobject`.
- `smart_scripts` keyed by `(entryorguid, source_type)`.
- `conditions` is polymorphic; source type 19 gates quest availability, 23 vendor items, 22 SmartAI.
- `instance_template` + `instance_encounters`.
- `spell_script_names` binds a C++ script to a spell.
- `*_dbc` tables overlay client DBC data.

## Errors and edge cases

- Duplicate filename across included directories is fatal.
- A failed update leaves the previous state; restore the backup if partial data was written.
- DDL implicit commits mean a transaction is not a rollback for `ALTER`/`DROP`.
- Missing indexes cause slow queries and map/login stalls.

## Security

- Least-privilege users; never `root` for tools or agents.
- Back up before a write batch.
- Production writes are human-only.
- No player data in docs or logs.

## Observability

- `Errors.log` for SQL errors.
- `updates` table for applied files.
- Slow query log and `EXPLAIN` for performance work.

## References

- [.agents/docs/sql-guidelines.md](../.agents/docs/sql-guidelines.md)
- [runbook/database/schema-guide.md](../runbook/database/schema-guide.md)
- [runbook/operation/backup-restore.md](../runbook/operation/backup-restore.md)
- [runbook/operation/apply-sql-update.md](../runbook/operation/apply-sql-update.md)
