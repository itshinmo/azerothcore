# Objectives

## Purpose

Define the shared objective engine, the character Adventure Board and the account Chronicle: what a
task is, how progress is earned, when it resets, how the board is generated and how the addon talks
to the server.

## Scope

Task definitions in `acore_world`; progress, focus, chronicle and currency rows in
`acore_characters`; the event hooks that advance progress; the addon-message protocol; the
`/objectives` window. Reward currencies and the vendor spend path are in
[rewards.md](rewards.md).

## Boundary (owns / does not own / consumes)

- Owns: task selection, progress, reset periods, zone focus, reroll cost, board/chronicle layout
  data and the wire protocol.
- Does not own: reward item balance or vendor stock data (world rows in `mod_objectives_offer`),
  the future shop ([ADR-006](../decisions/ADR-006-shop-policy.md)), or the Journal addon.
- Consumes: `sWorld` reset times, `OnPlayerRewardKillRewarder`, `OnPlayerCompleteQuest`,
  `OnBattlegroundEndReward`, `sObjectMgr` item/quest data and the character database.

## Contract

### Task types

| Value | Type | Event | Target |
|-------|------|-------|--------|
| 1 | Kill creature | `OnPlayerRewardKillRewarder` | `target_id` = creature entry, `0` = any |
| 2 | Complete quest | `OnPlayerCompleteQuest` | `target_id` = quest id, `0` = any |
| 3 | Kill dungeon/raid boss | `OnPlayerRewardKillRewarder` | `target_id` = creature entry, `0` = any boss |
| 4 | Win battleground | `OnBattlegroundEndReward` | `target_id` = `BattlegroundTypeId`, `0` = any |

Profession and gather types are not implemented. The task table already carries the type column, so a
future type is a new value and a new event source.

### Scopes and slots

| Scope | Table value | Owner | Slots |
|-------|-------------|-------|-------|
| Board daily | 1 | character | `Objectives.DailySlots`, default 5, maximum 7 |
| Board weekly | 2 | character | `Objectives.WeeklySlots`, default 1, maximum 1 |
| Chronicle weekly | 3 | account | `Objectives.ChronicleSlots`, default 3, maximum 6 |

A slot holds one task and its progress. Empty slots are allowed when the eligible pool is smaller
than the configured count. "7-stack" means seven daily slots; a task is not duplicated to fill a
slot.

### Selection

- The pool is filtered by `scope`, `enabled`, `era <= Objectives.Era`, `min_level <= level <=
  max_level`, and `faction` (`0`, or the character's faction).
- The daily pool additionally prefers `zone_id = focus_zone`; when that pool is exhausted the
  remaining slots are filled from tasks with `zone_id = 0` and then other zones. A task with
  `zone_id = 0` matches any zone.
- Weekly and chronicle pools ignore the focus zone. Chronicle selection also ignores level and
  faction: it is account-wide, so a level-1 alt cannot seed a weaker weekly pool. Only era and scope
  filter it.
- Selection is weighted by `weight` (default 1) without replacement inside one board generation.
- The board is generated on login and on the first request of a period. It is not regenerated on
  every request.

### Zone focus

- Focus is per character and per daily period, stored in `mod_objectives_focus`.
- Default: the character's current zone when at least one eligible daily task names it; otherwise
  the eligible zone with the most tasks, ties broken by zone id.
- Changing focus is free once per day (`focus_changed = 1` after the first change). It cycles to the
  next eligible zone and replaces every **incomplete** daily task with a task from the new focus.
  Completed daily tasks keep their row.
- A second change in the same daily period is refused with `focus_used`.

### Reroll

- One daily slot per request, server-side.
- Refused when the slot is empty, the task is completed, the player lacks the gold, or no replacement
  task exists.
- Cost = `Objectives.RerollCostCopper * (rerolls_bought_today + 1)`. The counter is stored in
  `mod_objectives_focus` and resets with the daily period.
- The replacement is drawn from the focus pool and must not duplicate another task on the board.
- Gold is removed by the server with `Player::ModifyMoney`; the client never sends a price.

### Resets

- Daily rows use `sWorld->GetNextDailyQuestsResetTime()`; weekly rows use
  `GetNextWeeklyQuestsResetTime()`.
- Each row stores `period_key` = the reset time it belongs to. `period_key <= now` means stale.
- A stale daily row does not invalidate the weekly board: daily and weekly rows are validated and
  replaced separately.
- Stale rows are replaced lazily on the next load, event or board request. There is no timer that
  scans all players.
- A player who stays online across the reset sees the new board on the first event or request after
  the reset.

### Progress and completion

- Progress is in memory and is clamped to `required_count`.
- A task completes once; further events do nothing.
- Completion awards the task's currencies immediately (see [rewards.md](rewards.md)) and sends a chat
  line to the completing character.
- `OnPlayerRewardKillRewarder` is per credited player, so group members at reward distance and pet
  owners receive kill progress without a custom group scan.
- Boss progress requires `killed->GetMap()->IsDungeon()` and `IsDungeonBoss() || isWorldBoss()`.
- Quest zone matching accepts the player's current zone or `quest->GetZoneOrSort()` when positive.
- Battleground progress requires `bg->isBattleground()`, `winnerTeamId != TEAM_NEUTRAL` and the
  player's battleground team equal to the winner. Arenas do not count.

### Persistence

| Table | Key | Purpose |
|-------|-----|---------|
| `mod_objectives_board` | `(guid, scope, slot)` | character daily/weekly rows |
| `mod_objectives_focus` | `(guid)` | focus zone, rerolls, focus-changed flag for the current daily period |
| `mod_objectives_chronicle` | `(account_id, slot)` | account weekly rows |
| `mod_objectives_character_currency` | `(guid)` | Mythic Coins, Raider's Commendations |
| `mod_objectives_account_currency` | `(account_id)` | Adventure Marks |

Every table is keyed by the character or account. No secondary index is used yet: every read is by
the primary key, and the task table is cached at startup.

All SQL values are server-generated numeric ids, counters and timestamps; no client string ever
reaches a query. Module-local prepared statements are not available without adding entries to the
core `CharacterDatabase` enum, which would break the module isolation rule, so the module uses the
same formatted-query path as the other project modules and escapes nothing because it never
interpolates text.

- Definitions are cached at startup from `mod_objectives_task`.
- Board and chronicle progress stays in memory. Dirty character and account sets are flushed every
  `Objectives.FlushIntervalMs` (default 20000), on logout and on shutdown.
- Currency is a balance, not a progress row. It is written through immediately on award and on
  vendor purchase, so a crash cannot grant an item without the deduction. The write copies the
  balance under the state lock, then executes the SQL outside it.
- A flush tick drains up to 100 batches. Each batch covers at most 100 characters and 100 accounts
  and is one transaction: delete the current board/chronicle rows for those keys, then one multi-row
  insert. A 7k login burst is about 70 batches, so the dirty set drains in one 20 s tick; shutdown
  drains until the dirty sets are empty.

### Addon protocol

Prefix `OBJ`, protocol 1. The addon whispers itself; the server intercepts `LANG_ADDON` private chat
and answers with addon whispers. Fields are colon-separated, rows are `;`-separated and row values
are `,`-separated. Names are sanitized to remove the delimiters.

Requests:

| Request | Meaning |
|---------|---------|
| `B:<req>` | board |
| `C:<req>` | chronicle |
| `F:<req>` | cycle focus and reroll incomplete dailies |
| `R:<req>:<slot>` | gold reroll of one daily slot |

Answers:

| Answer | Meaning |
|--------|---------|
| `BR:<req>:<focusId>:<focusName>:<marks>:<coins>:<commendations>:<nextRerollCost>:<dailySlots>` | board header |
| `BD:<slot>,<scope>,<taskId>,<type>,<required>,<progress>,<completed>,<rewardMarks>,<rewardCoins>,<rewardCommendations>,<zoneId>,<name>` | board row |
| `BE` | board end |
| `CR:<req>:<marks>:<coins>:<commendations>` | chronicle header |
| `CD:<slot>,<taskId>,<type>,<required>,<progress>,<completed>,<rewardMarks>,<rewardCoins>,<rewardCommendations>,<zoneId>,<name>` | chronicle row |
| `CE` | chronicle end |
| `RR:<req>:<ok\|err>:<message>` | reroll result |
| `FR:<req>:<ok\|err>:<message>` | focus result |
| `ERR:<req>:<reason>` | request refused (disabled, unknown, bad) |

A successful `F` or `R` is followed by a fresh `BR`/`BD`/`BE` sequence. `marks` is the account
balance; `coins` and `commendations` are the character balance.

### Config

| Option | Default | Meaning |
|--------|---------|---------|
| `Objectives.Enable` | 1 | master switch |
| `Objectives.Era` | 0 | 0 Classic, 1 TBC, 2 WotLK |
| `Objectives.DailySlots` | 5 | daily slots, clamped 1–7 |
| `Objectives.WeeklySlots` | 1 | weekly slots, clamped 0–1 |
| `Objectives.ChronicleSlots` | 3 | chronicle slots, clamped 0–6 |
| `Objectives.RerollCostCopper` | 2000 | first reroll price in copper (provisional; owner confirms) |
| `Objectives.FlushIntervalMs` | 20000 | dirty-write interval |

## Errors and edge cases

- Missing module tables: the module logs one warning at startup and disables the objective feature
  (no board, progress, chronicle or purchases) until the SQL is applied. It never queries a missing
  table, because MySQL errno 1146 aborts the worldserver.
- Missing `item_template` row for an offer: the offer is skipped at load with one error line.
- Empty pool: the slot stays empty; the addon shows an empty row, not a fake task.
- A task row with `required_count = 0` or an unknown type is rejected at load.
- A completed task is never rerolled; the slot is kept until the period ends.
- A second character of the same account sees the same chronicle progress and marks; the character
  currencies are separate.
- A full inventory at a vendor refuses the purchase before any currency is deducted.
- A crash can lose at most one flush interval of progress; a vendor purchase is written through.

## Security

- The client never sends progress, prices, currency balances, task ids or character/account ids.
  It sends only a request id, a slot number and a focus request. Requests are rate-limited per
  character (8 burst, 4 per second) so a modified client cannot flood the world thread.
- Every request is answered from the server's own state. Slot numbers are range-checked.
- Currency and item grants are server-side; the addon has no grant path.
- Definition and offer data are world data, not player input.
- No account names, player names or balances are written to logs. Debug logs carry ids only.

## Observability

- Startup: one line with the number of loaded tasks and offers, and one warning if the feature is
  disabled because the module tables are missing.
- Completion: one debug line with task id and character id; no names or balances.
- Flush: one debug line per flushed batch (at most 100 characters and 100 accounts), with that
  batch's counts; a tick may run several batches.
- No per-kill log line at normal verbosity.

## Performance

- **Expected cost.** Startup: one world query for tasks, one for offers. Login: five indexed
  character/account queries (board, focus, character currency, chronicle, account currency), fewer
  for a sibling character of an already-loaded account. Event: hash lookup plus at most 10 cached
  task checks. Flush: batched deletes and inserts for dirty keys only. Refresh: in-memory.
- **Hot path.** `OnPlayerRewardKillRewarder` and `OnPlayerCompleteQuest`; no SQL, no per-kill write,
  no loop over online players.
- **Target.** 5–7k online players. The engine's per-event work is independent of the online count.
  The 20 s flush is bounded by dirty characters, not by the population.
- **Measurement.** Slow-query log and `performance_schema` for the `mod_objectives_*` statements;
  startup count lines; a playtest with several characters online and a kill/quest loop. Measure
  flush wall time and rows written before changing the interval.

## References

- [ADR-028](../decisions/ADR-028-objective-engine-board-chronicle.md)
- [ADR-029](../decisions/ADR-029-objective-reward-currencies.md)
- [ADR-030](../decisions/ADR-030-era-aware-content-model.md)
- [specs/rewards.md](rewards.md)
- `modules/mod-objectives/`
