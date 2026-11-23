# ADR-028 — Shared Objective Engine, Adventure Board and Chronicle

- Status: proposed
- Date: 2026-11-23
- Implements: owner request for the first vertical slice of the era-aware objective system

## Context

The server has no repeatable objective layer. Daily and weekly content, zone-directed play and a
long-term progression currency all need one engine: one definition of a task, one progress path, one
reset rule and one place to add future task types. Building the board and the chronicle as separate
systems would duplicate task selection, progress accounting and persistence.

Numbering: ADR-027 is allocated on the client-patch branch
(`feat-map-poi`, `ADR-027-client-patch-pipeline.md`) and will be merged; do not create a duplicate
027 row. This slice uses ADR-028 through ADR-030.

The first slice must be small enough to review and test with the owner, not a full feature slate.
It must not add per-tick work over players and must not write to the database on every kill.

## Decision

1. **One module, two views.** `modules/mod-objectives` owns the engine. The Adventure Board and the
   Chronicle are views over the same task definitions and the same progress path. The module has no
   dependency on the Journal addon.
2. **Task types in this slice:** kill creature, complete quest, kill dungeon or raid boss, win a
   battleground. Each task row carries a `task_type`; adding profession or gather types later is a
   new enum value and a new event source, not a new engine.
3. **Scopes:**
   - character board daily: up to 7 slots (`Objectives.DailySlots`, default 5, hard maximum 7);
   - character board weekly: 1 slot (`Objectives.WeeklySlots`);
   - account chronicle weekly: 3 slots (`Objectives.ChronicleSlots`).
   "7-stack" means seven daily slots, not seven copies of one task. A slot is a task row for the
   character's current daily period.
4. **Resets use the server's own reset clock**, not a cron job:
   `sWorld->GetNextDailyQuestsResetTime()` and `GetNextWeeklyQuestsResetTime()`. Each stored row
   carries the reset time it belongs to. A row whose reset time has passed is stale and is replaced
   lazily on the next load, event or board request. The board is generated on login or on the first
   request, never by a timer that scans every player.
5. **Zone focus.** The daily pool prefers tasks whose `zone_id` matches the character's focus zone.
   The focus defaults to the character's current zone when that zone has eligible tasks, otherwise to
   the eligible zone with the most tasks. Changing the focus cycles the eligible zones and replaces
   all **incomplete** daily tasks with tasks from the new focus; it is free once per day and is
   refused a second time. Completed daily tasks are kept. The focus is per character and per daily
   period.
6. **Gold reroll.** Reroll is server-side and per daily slot. It refuses completed tasks and a full
   bag of gold. Cost is `Objectives.RerollCostCopper` times the number of rerolls already bought
   that day plus one, so the first reroll costs the base price and each later reroll costs more.
   The first-slice base is 2000 copper (20 silver); the owner confirms or lowers it at playtest.
   Reroll is the only gold sink in the slice; it never buys currency.
7. **Character vs account scope.**
   - Board tasks and progress are per character.
   - Chronicle tasks and progress are per account. Any character of the account contributes
     progress; the character that completes a chronicle task receives its character-currency reward,
     and the account receives its Adventure Marks. Chronicle selection ignores level and faction;
     only era and scope are enforced, so a low-level alt cannot seed a weaker weekly pool for the
     account.
   - Adventure Marks are account-wide. Mythic Coins and Raider's Commendations are per character.
8. **Progress and storage.**
   - Task definitions are cached at startup from `mod_objectives_task`; no per-event world query.
   - Board and chronicle progress is kept in memory. Events update it directly; nothing reads the
     database on a kill.
   - Dirty rows are written in batches on a ~20 s timer, on logout and on shutdown. A progress,
     focus or reroll change marks the character or account dirty.
   - Currency is a balance, not batched progress. It is written through immediately on award and
     on vendor purchase, so a crash cannot grant an item without the deduction.
   - Board, focus, chronicle and currency rows are keyed by character or account, as specified in
     `specs/objectives.md`.
9. **Credit.** Kill progress uses `OnPlayerRewardKillRewarder`, which the core already calls per
   credited player (killer, group members at reward distance, pet owners). The module does not
   implement its own group scan. Quest progress uses `OnPlayerCompleteQuest`; battleground progress
   uses the winner reward hook; boss detection uses the core's `IsDungeonBoss` / `isWorldBoss`.
10. **Transport.** A small standalone addon (`/objectives`) speaks an addon-message protocol to the
    server. The server answers board, chronicle, focus and reroll requests. The addon has no write
    path other than those requests; the server validates every one.
11. **Not in this slice.** Profession and gather task types, more than one weekly board slot,
    per-expansion boards, task claiming, cross-character board sharing, and reward vendors opened
    from the addon. Vendors use a server gossip menu and are recorded in ADR-029.

## Alternatives considered

- **Two modules, one for the board and one for the chronicle.** Duplicates selection, reset and
  persistence; the chronicle is the same engine with an account key.
- **Database progress on every event.** A 5–7k player server would pay an indexed write per kill.
  Rejected; batched writes keep the hot path in memory.
- **A per-tick scan that resets boards.** Rejected; resets are lazy and event-driven.
- **Task tokens as items.** Items can be traded, mailed and sold, and account-wide marks cannot be
  expressed as an item without a custom client DBC. Rejected in favour of server-side currency rows.
- **Seven copies of one task ("stack").** The owner asked for up to seven daily stacks; reading it
  as seven slots gives the board variety and keeps the UI simple. Recorded here so the wording does
  not drift.

## Consequences / tradeoffs

- A player who stays online across reset keeps the old board until the next event or request; the
  first event after the reset replaces the stale rows. This is deliberate and bounded.
- A crash can lose at most the last ~20 s of board or chronicle progress. Currency is written
  through immediately, so it is durable.
- Shutdown drains flush batches until the dirty sets are empty, one bounded transaction per batch;
  it does not walk every online character in one transaction.
- The board's daily pool must contain enough tasks for the configured slots and faction/level band.
  Empty slots are allowed and shown as empty, not fake tasks.
- Zone focus changes are limited to once per day; a player cannot fish for a perfect board.
- The account-wide chronicle means two characters of the same account share progress, so a player
  cannot double-count the same weekly on two alts.

## Performance

- **Expected cost.** Task definitions: one world query at startup. Login: three indexed character
  queries (board, focus, currency) plus two account queries (chronicle, marks). Event: a hash lookup
  and at most 10 in-memory task checks per credited player. Flush: up to 100 batches of 100
  characters and 100 accounts per 20 s tick; a 7k login burst is about 70 batches.
- **Hot path.** `OnPlayerRewardKillRewarder` and `OnPlayerCompleteQuest`. No SQL, no allocation
  beyond small vectors, no full player scan.
- **Target.** 5–7k online players. At 7k online and 100 events/s the engine does ~1k in-memory task
  comparisons per second, which is noise next to combat. The flush is bounded by dirty characters,
  not by online characters.
- **Measurement.** Enable the MySQL slow-query log for `mod_objectives_*`, watch
  `performance_schema.events_statements_summary_by_digest` for the board statements, and add a
  playtest with N characters online while running `/objectives` and a kill loop. Record flush
  duration and query counts before changing the 20 s interval.

## References

- [specs/objectives.md](../specs/objectives.md)
- [specs/rewards.md](../specs/rewards.md)
- [ADR-029](ADR-029-objective-reward-currencies.md), [ADR-030](ADR-030-era-aware-content-model.md)
- [ADR-002](ADR-002-custom-content-isolation-and-ids.md) (tracked modules and IDs)
