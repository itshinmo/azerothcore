# 2026-11-14 — content audit baseline

## Summary

Baseline (pre-triage) for `acore_world` (`ACDB 335.17-dev`) on 2026-11-14, after the audit tool
review fixes. An earlier run with the pre-review build reported 2,032 findings. That build was
replaced during review, so the exact per-check delta is not reproducible; no data changed. The
current post-triage state is at the end of the report.

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

After the blocker fix, the triage in the next section resolved these.

| Check | Count | Meaning | Next step |
|-------|-------|---------|-----------|
| C-11 | 135 | 113 vendors with no stock, 22 trainers with no trainer assignment | Reviewed in part 1; reclassified |
| C-07 | 9 | `AIName` without rows, or rows without `AIName` | Fixed in part 1 |
| C-10 | 5 | `spawnMask = 0` | Fixed in part 1 |
| C-06 | 3 | Broken SmartAI `link` targets | Fixed in part 1 |
| C-05 | 1 | `event_chance = 101` | Fixed in part 1 |

## Part 1 triage

Rule: change data only when the outcome is understood. Activation is allowed when the rows are
clearly authored and currently dead; deletion is allowed only for rows the core never loads.

| Check | Action | Reasoning |
|-------|--------|-----------|
| C-05 | Rewrite block `2202:0`, `event_chance` 101 → 100 | SmartScript skips the roll when chance >= 100; 101 and 100 behave the same |
| C-06 | Rewrite blocks `21231:0`, `24043:0`, `30956:0`, `link` → 0 | The link target does not exist, so the chain already failed; the actions still run |
| C-07 | Set `AIName='SmartAI'` for 10182, 14690, 18703, 21271 and `SmartGameObjectAI` for 201937 | Rows are authored and meaningful (gossip reward, combat timers, summon chain); they never ran because `AIName` was empty |
| C-07 | Delete inert rows for 25367, 25744, 190635, 190636 and the `-guid` rows of 25367 | 25367 and 25744 are driven by C++ scripts, and the two gameobjects have no `AIName`, so SmartAI rows never load. Deletion is behaviour-neutral |
| C-10 | Delete four `spawnMask = 0` spawns; restore guid 131066 disabled and waive it | The four never load. 131066 is the Ruby Sanctum firewall, disabled on purpose by `2026_07_11_00.sql`; deleting it would erase that decision |
| C-11 | Reclassify flag-without-stock/assignment from major to minor; no data edit | A vendor with no stock opens an empty window; a trainer with no assignment opens nothing. Mass flag edits without sniffs risk breaking scripted vendors; data hygiene, not breakage |

Files:

- `data/sql/updates/pending_db_world/rev_1794652958956865000.sql` — part 1.
- `data/sql/updates/pending_db_world/rev_1794653085328495000.sql` — C-07 per-spawn follow-up.
- `data/sql/updates/pending_db_world/rev_1794653993556354000.sql` — C-10 correction and orphan
  cleanup.
- `tools/dev/content-audit-waivers.json` — one waiver for guid 131066, with the reason above.

Result after all three files, including a forced re-apply of part 1 after its hash changed:
**0 blocker, 0 major, 1,972 minor, 1 waived**; coverage unchanged at 78.89% overall. Latest
verification backups: `var/backups/manual/20261114-143634/acore.sql` (local) and
`var/backups/verify/20261114-143621/test.sql` (test realm).

The 1,972 minors are four classes: 809 objective targets without a spawn, 935 required items with
no known source, 135 vendor or trainer flags, and 93 quests whose `MinLevel` exceeds `QuestLevel`.
They stay visible.

## Part 2 — audit v2

- Added C-13: conditions for gossip menus (source 14), gossip menu options (15), and quest-available
  (19) must reference existing rows. Semantics verified in `ConditionMgr::LoadConditions`; the check
  is deliberately limited to those three source types.
- Result on `acore_world`: 0 C-13 findings. The table is consistent for those sources.
- Still open by design:
  - Map-bounds validation: `map_dbc` is empty and `Map.dbc` carries no bounds, so there is no
    reference data to validate against yet.
  - C-06 phase reachability: requires modeling which SmartAI events can switch phases; only link
    chains and cycles are checked.

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
