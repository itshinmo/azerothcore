# Project SQL

Project-specific, re-applicable SQL. This tree is **tracked** (the upstream convention kept it
gitignored; this fork does not). It is applied by the startup updater with state `CUSTOM`.

## Rules

- Only re-applicable SQL:
  - `CREATE TABLE IF NOT EXISTS`
  - `DELETE` + `INSERT`
  - `REPLACE`
  - `UPDATE` with fixed values and a narrow `WHERE`
- No `DROP DATABASE`, `TRUNCATE`, or unbounded `DELETE`/`UPDATE`.
- No player data, credentials, or generated dumps.
- Follow `.agents/docs/sql-guidelines.md` for style.
- Record custom IDs in `runbook/database/id-registry.md` before use.
- Back up before applying to any shared database.
- Do not edit `base/`, `archive/`, or `updates/db_*`; those are immutable.

## Layout

- `db_auth/` — accounts, RBAC presets, realm changes.
- `db_characters/` — character-side schema or repair SQL.
- `db_world/` — content, templates, spawns, loot, SmartAI, conditions.

## Apply

The server applies this tree at startup when `updates_include` contains `custom/db_*`. For a manual
test apply, use `runbook/operation/apply-sql-update.md`.
