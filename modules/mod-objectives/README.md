# mod-objectives

First vertical slice of the era-aware objective system: a shared task engine, the character
Adventure Board, the account Chronicle and the three objective currencies. Design and contracts:
[specs/objectives.md](../../specs/objectives.md), [specs/rewards.md](../../specs/rewards.md),
[ADR-028](../../decisions/ADR-028-objective-engine-board-chronicle.md),
[ADR-029](../../decisions/ADR-029-objective-reward-currencies.md),
[ADR-030](../../decisions/ADR-030-era-aware-content-model.md).

## What is in the slice

- One task table (`mod_objectives_task`) with era, level band, faction, zone and target filters.
- Four task types: kill creature, complete quest, kill dungeon/raid boss, win battleground.
- Twenty-five Classic seed tasks: 20 daily (5+ at level 1-9 and 7+ per faction per later band),
  2 weekly and 3 chronicle.
- Character daily board (up to 7 slots, default 5), character weekly board (1 slot) and account
  chronicle (3 slots).
- Zone focus and a server-side gold reroll.
- Adventure Marks (account), Mythic Coins (character) and Raider's Commendations (character).
- Two reward vendors, gossip menus, existing items only. No item, spell or map IDs.
- A standalone `/objectives` addon with Board and Chronicle tabs. It does not depend on the Journal
  addon.

## Install

1. Copy this directory to `modules/mod-objectives` of the target checkout.
2. Let the worldserver apply the custom SQL on restart:
   - `data/sql/custom/db_world/objectives_engine.sql`
   - `data/sql/custom/db_characters/objectives_engine.sql`
3. Restart. The module copies `conf/Objectives.conf.dist` to the server config directory on a CMake
   run; if it does not exist yet, copy it to `env/dist/etc/modules/Objectives.conf`.
4. Enable the module build (`MODULES=static` includes every `modules/mod-*` by default) and rebuild.
5. Copy `addon/Objectives/` to `Interface/AddOns/Objectives/` in the client.

## Config

See `conf/Objectives.conf.dist`. The values that matter for a first test are `Objectives.Era` (0),
`Objectives.DailySlots` (5), `Objectives.RerollCostCopper` (2000, provisional) and
`Objectives.Enable` (1).

## Tests

- Pure math: `make test` builds the unit test registered by `mod-objectives.cmake`
  (`ObjectivesMathTest`).
- Addon syntax: `luac -p modules/mod-objectives/addon/Objectives/*.lua`.
- Addon smoke: `lua modules/mod-objectives/tools/addon-smoke.lua` (loads the `.toc` against a small
  WoW API mock, opens the window, feeds a synthetic board answer and clicks Reroll).
- Task data: `python3 modules/mod-objectives/tools/check_task_data.py` (5+ daily tasks per faction
  at level 1-9, 7+ in 15-30 and 31-80, and 2+ focus zones).
- SQL lint: `python3 apps/codestyle/codestyle-sql.py`.
- C++ lint: `python apps/codestyle/codestyle-cpp.py` covers `src/` only; module formatting is
  reviewed by hand against `.agents/docs/cpp-guidelines.md`.

## Owner test checklist

1. `/objectives` opens the window; Board and Chronicle tabs both render.
2. Talk to the Adventure Quartermaster in Stormwind or the Chronicle Quartermaster in Orgrimmar;
   the gossip menu lists level-appropriate offers.
3. Kill a task creature and complete a task quest; the row progress changes and completing a row
   prints the currency line.
4. Buy a cheap material with Adventure Marks; the balance drops and the item appears in the bags.
5. `/objectives` → Focus changes the zone once; a second change says it is already used today.
6. Reroll one daily slot; the gold cost is shown and the task changes.
7. Relog: progress, focus and currency are still there.
8. Wait for a daily reset (or set `Objectives.Era`/data for a test) and confirm the board refreshes
   on the next request.

## Known limits of the slice

- Only four task types. Profession and gather types are the next event sources.
- The seed has 25 tasks: 20 daily, 2 weekly, 3 chronicle. Level 1-9 has at least 5 daily tasks per
  faction; 15-30 and 31-80 have at least 7, and each faction has 2+ focus zones. Add data, not code,
  to grow the pools.
- The addon has no shop tab; vendors are gossip menus.
- Rewards are existing Classic items. Era 1 and 2 tables are present but empty.
- The addon asks for state; the server never pushes progress. Reopen the window to refresh.
- No per-character telemetry; the debug log is ids only.

## Layout

```text
conf/Objectives.conf.dist       module config
src/Objectives.h                public module API
src/ObjectivesMath.h            pure progress/reset/reroll math (unit tested)
src/Objectives.cpp              definitions, state, persistence, addon protocol, vendors
src/ObjectivesScripts.cpp       script hooks and the vendor gossip script
test/ObjectivesMathTest.cpp     gtest cases
addon/Objectives/               standalone addon
tools/addon-smoke.lua           offline addon smoke test
```
