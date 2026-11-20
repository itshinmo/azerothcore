# mod-dungeon-xp

Dungeon XP rebalance (ADR-012 revision 2026-11-20, RFC-003 Group A; owner picked the shape from
Wow-Forever's pattern): repeatable dungeon income (mob/boss kill XP) is reduced, one-time dungeon
quest income is raised. Result: a first visit is richer than a repeat ever was, world questing
stays the fastest path, and the incentive to chain-clear dungeons for XP disappears.

| Knob | Default | Effect |
|------|---------|--------|
| `DungeonXp.KillFactor` | 0.33 | kill XP inside instance maps (mob + boss) x 0.33 |
| `DungeonXp.QuestFactor` | 2.0 | dungeon quest XP x 2, on top of the global 2x = 4x one-time |
| `DungeonXp.IncludeRaids` | 1 | raids get the same kill reduction |

Math at defaults: a repeat Northrend run drops from roughly ~260k XP/h to ~85k, versus ~300k/h
for world questing — spam is no longer the meta, while a first visit (one-time 4x quests + loot)
pays more than it used to.

Notes:

- Kill side gates on `Map::IsDungeon()` (instances + raids per MapEntry); battleground kills are
  untouched (their own per-BG rates), outdoor elites/rares keep full rate, and mod-xp-bonus's
  rare-kill bonus is also scaled inside dungeons (rare-rank mobs essentially never spawn there).
- Quest side is data-driven: a quest whose ZoneOrSort points at an area whose map is an instance
  counts as a dungeon quest (verified sample: Blackfathom quests -> area 719, "Into Utgarde!" ->
  206). Quests without a dungeon zone (some turn-in-outside quests, a few DF reward quests with
  their own DF rate) fail open and keep the world rate.
- The quest hook fires wherever quest XP is computed (reward sites and the UI preview), each with
  its own local value — scaling keeps the shown XP consistent with what is paid.
