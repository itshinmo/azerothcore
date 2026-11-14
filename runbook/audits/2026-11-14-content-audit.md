# 2026-11-14 — content audit baseline

## Summary

Content audit baseline for `acore_world` (`ACDB 335.17-dev`) on 2026-11-14, after the audit tool
review fixes. An earlier run with the pre-review build reported 2,032 findings. That build was
replaced during review, so the exact per-check delta is not reproducible; no data changed.

- P0: 0
- P1: 0
- P2: 1
- P3: 0

Audit counts: 3 blocker findings, 153 major, 1,837 minor. Coverage 78.89% overall, per band
73.78-84.70%. The three blockers share one cause.

Audit severity maps to this format as follows: blocker is P1 here only when it can stop content;
this one could not, so it is recorded as P2. Major is P2-P3, minor is P3.

## Findings

### P2 — Baron Longshore spawns carry a numeric `ScriptName`

- Evidence:
  - `data/sql/updates/db_world/2026_05_18_01.sql:6-8` inserts `'67511'` into `ScriptName`.
  - `data/sql/base/db_world/creature.sql:15015`, `:15164`, `:15166` carry the same rows.
  - `ObjectMgr::GetScriptId` (`src/server/game/Globals/ObjectMgr.cpp:10567`) returns `0` for an
    unknown name and does not fail.
  - No script named `67511` exists in `src/server/scripts`; `67511` is not a quest id, and the
    creature has no quest, vendor, or trainer rows.
- Impact: none at runtime. The three spawns behave as if `ScriptName` were empty. The value is still
  wrong data and fails audit check C-08.
- Fix: `data/sql/updates/pending_db_world/rev_1794650159541821000.sql` clears the column for those
  three guids only, filtered on `id`, `guid`, and the old value.
- Status: fixed in the commit that adds this report; applied to the test realm and the local
  database. Audit after the fix: 0 blockers, exit code 0.

### Remaining majors

| Check | Count | Meaning | Next step |
|-------|-------|---------|-----------|
| C-11 | 135 | 113 vendors with no stock, 22 trainers with no trainer assignment | Review in batches, fix the flag or add the data |
| C-07 | 9 | `AIName` without rows, or rows without `AIName` | Set the AI name or remove orphan rows |
| C-10 | 5 | `spawnMask = 0` | Set the mask or delete the spawn |
| C-06 | 3 | Broken SmartAI `link` targets | Repair the chains |
| C-05 | 1 | `event_chance = 101` | Set to 100 |

Minors are 809 objective targets with no spawn (mostly summons), 935 required items with no known
source (mostly crafted), and 93 quests whose `MinLevel` exceeds `QuestLevel`.

## What was checked

- `make verify-sql`: SQL lint passed, test-realm apply passed, backup written
  (`var/backups/verify/20261114-132609/test.sql`).
- Local apply through `env/dist/bin/worldserver -d -c env/dist/etc/worldserver.conf` after
  `make backup` (`var/backups/manual/20261114-132640/acore.sql`).
- Row check in both databases: `SELECT guid,id,ScriptName FROM creature WHERE id=3467` returns three
  rows with empty `ScriptName`.
- `make content-audit` before and after; `python3 -m unittest discover -s tools/dev/tests`.

## What was not checked

- C-10 map-bounds validation (`map_dbc` is empty).
- C-06 phase reachability: only link chains and cycles are checked, not whether an event can reach
  a phase.
- Conditions auditing (not implemented in audit v1).
- Whether upstream has an open issue for the `ScriptName` column; the same statement is a candidate
  for an upstream pull request.
