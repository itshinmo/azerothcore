---
description: The three databases, SQL tree, updater, key tables, and safety rules. Read before querying or changing data.
last-verified: 2026-11-12
---

# Database

The contract is [specs/database.md](../../specs/database.md). Schema guide:
[runbook/database/schema-guide.md](../../runbook/database/schema-guide.md).

## Three databases

- `acore_auth` — accounts, account access, realm list, bans, session keys, logs, GM audit log.
- `acore_characters` — characters, inventory, quests, mail, guilds, arena teams, achievements.
- `acore_world` — static content: creature/item/quest/gameobject templates, spawns, loot, SmartAI,
  conditions, instance templates.

## SQL tree

| Path | Purpose | State |
|------|---------|-------|
| `data/sql/base/db_*` | full schema and seed for an empty database | immutable |
| `data/sql/updates/db_*` | merged release updates | immutable |
| `data/sql/updates/pending_db_*` | in-flight upstream-shaped changes | writable |
| `data/sql/custom/db_*` | project-specific re-applicable SQL | writable |
| `data/sql/archive/db_*` | historical updates | immutable |

The server applies base SQL when a database is empty, then files from `updates_include` at startup.
`Updates.AutoSetup=1` and `Updates.EnableDatabases=7` are the local defaults. A failed update stops
startup and writes to `Errors.log`.

## Key world tables

- `creature_template` ← `creature_template_model`; `creature.id1` is the spawn template.
- `creature_queststarter` / `creature_questender` link NPCs to quests.
- `quest_template` + `quest_template_addon`; objectives reference creatures, gameobjects, or items.
- `item_template`; mounts are class 15, subclass 5, with a mount spell in `spellid_1`.
- `gameobject_template` + `gameobject`; chests use `Data1` as loot ID, questgivers type 2.
- `smart_scripts` keyed by `(entryorguid, source_type)`; full-block rewrites only.
- `conditions` is polymorphic; source type 19 gates quest availability, 23 vendor items, 22 SmartAI.
- `instance_template` maps a map ID to an `InstanceScript`; `instance_encounters` drives boss credit.
- `spell_script_names` binds a C++ spell/aura script to a spell.
- `*_dbc` tables overlay client DBC data on the server.

## Safety

- Back up before any write batch: `make backup`.
- Test on the test realm first.
- Never use `root` for tools or agents.
- Never run an unbounded `UPDATE`/`DELETE`; require a primary key or a narrow, reviewed `WHERE`.
- `DELETE` + `INSERT` for idempotency; `SQLTransaction` for multi-statement writes.
- Verify with before/after row counts and a sample query.
- Production writes are human-only, with a backup and a rollback plan.
