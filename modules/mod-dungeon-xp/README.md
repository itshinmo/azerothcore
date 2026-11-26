# mod-dungeon-xp

Dungeon XP rebalance (ADR-012 revisions 2026-11-20 and 2026-11-26, RFC-003 Group A; owner picked
the shape from Wow-Forever's pattern): repeatable dungeon income (trash and boss kill XP) is
reduced, one-time dungeon quest income is raised. Result: a first visit is richer than a repeat
ever was, world questing stays the fastest path, and the incentive to chain-clear dungeons for XP
disappears.

| Knob | Default | Effect |
|------|---------|--------|
| `DungeonXp.TrashKillFactor` | 0.10 | trash kill XP inside instance maps x 0.10 |
| `DungeonXp.BossKillFactor` | 0.33 | boss kill XP inside instance maps x 0.33 |
| `DungeonXp.QuestFactor` | 3.0 | dungeon quest XP x 3, on top of the global 2x = 6x base, one-time |
| `DungeonXp.IncludeRaids` | 1 | raids get the same trash/boss split |

Math at defaults: a repeat run is trash-dominated, so its income drops from roughly ~260k XP/h to
well under the old ~85k, versus ~300k/h for world questing — spam is no longer the meta. A first
visit pays 6x base on its dungeon quests plus loot, more than a repeat ever did.

Notes:

- Boss or trash? The module reuses mod-objectives' definition so the two agree: a kill is a boss
  when the map is an instance and `Creature::IsDungeonBoss()` (the core sets
  `CREATURE_FLAG_EXTRA_DUNGEON_BOSS` from `instance_encounters`) or `Creature::isWorldBoss()`
  (`CREATURE_TYPE_FLAG_BOSS_MOB`) is true. Everything else in the instance is trash. A null victim
  in the hook counts as trash.
- Kill side gates on `Map::IsDungeon()` (instances + raids per MapEntry); battleground kills are
  untouched (their own per-BG rates), outdoor elites/rares keep full rate, and mod-xp-bonus's
  rare-kill bonus is also scaled inside dungeons (rare-rank mobs essentially never spawn there).
- Quest side is data-driven: a quest whose ZoneOrSort points at an area whose map is an instance
  counts as a dungeon quest (verified sample: Blackfathom quests -> area 719, "Into Utgarde!" ->
  206). Quests without a dungeon zone (some turn-in-outside quests, a few DF reward quests with
  their own DF rate) fail open and keep the world rate.
- The quest hook fires wherever quest XP is computed (reward sites and the UI preview), each with
  its own local value — scaling keeps the shown XP consistent with what is paid.
