# Upstream and local divergence

- Upstream: <https://github.com/silviu20092/mod-mythic-plus>
- Pinned commit: `e2a487d358c1c1c562d686f53a3e269b2cf1b8c5` (2026-03-23)
- Licence: MIT, copyright 2023 AzerothCore, author silviu20092. See `LICENSE`.
- Upstream author for commit attribution: `silviu20092 <dobrescu.silviu92@gmail.com>`.

This directory is a fork. The first slice keeps the run state machine and the affix interface. It
does not keep the upstream standings, snapshots, random affixes, lightning sphere, spell overrides,
map damage scale or reward tokens.

Local divergence from upstream:

- One dungeon: Ragefire Chasm (map 389), key levels 1-5, final boss Taragaman the Hungerer
  (11520). The upstream row pointed at Bazzalan (11519).
- Start is NPC-only. Creature `910013` starts the run from gossip. The upstream physical keystone
  item is removed: item 5373 has no on-use spell, so the client never sends `CMSG_USE_ITEM` and the
  item script never runs. The module does not rename, rebind or otherwise use item 5373. The world
  SQL has one guarded migration that restores the previous slice's rename, and only while the row
  still carries `Mythic Keystone` or script `mythic_plus_keystone`; a stock row is a no-op.
- Progression is per character per era in `mod_mythic_plus_progress`. `highest_key` is the highest
  key completed. A start requires `K <= highest_key + 1` for every member and `K <= 20`. A timed
  completion stores `max(highest_key, K)`, capped at 20. `K + 1` is never stored.
- A member who leaves the instance is marked and is not eligible for rewards or the key unlock, even
  after rejoining.
- Creature level, health multiplier and damage multiplier are data in
  `mythic_plus_creature_scale`. No 82/80, 20x or 4x constant remains in C++.
- Run rows in `mythic_plus_dungeon` are deleted at world start and are deleted again when a run
  completes or aborts. A restart never restores a run. The pre-cleared marker is in map memory only.
- Deaths are in memory. The run row is written only for an active run, never per death and never per
  boss.
- No `OnAllCreatureUpdate` and no `OnUnitUpdate`. Scaling and static affixes are applied once at run
  start and from `OnCreatureAddWorld`. No periodic affix hook is needed after removing the explosion
  affix.
- The timer uses one clock: `GameTime::GetGameTimeMS()` for both start and elapsed checks.
- Shared module maps are guarded by `_dataMutex`; no database call is made while that lock is held.
- Runtime `ASSERT`s on saved state are replaced by null checks and log lines.
- SQL is re-applicable and lives in `data/sql/custom/db_*`, not in the module directory.
- The module owns a `ModuleDatabasePool` against `CharacterDatabaseInfo` in
  `src/mythic_plus_database.{h,cpp}`. It sizes `m_stmts` in both connection constructors, prepares
  the progress and run statements, and opens/probes/pings/closes on the `DatabaseScript` hooks. The
  core database enum and files are unchanged.

Commit plan when a human approves staging:

- Stage the module with `--author "silviu20092 <dobrescu.silviu92@gmail.com>"` for the vendored base,
  or keep the local author and add `Co-authored-by: silviu20092 <dobrescu.silviu92@gmail.com>` for
  the mirrored timer/affix/gossip skeleton. Never omit the upstream attribution.
- Stage the SQL, registry, module-owned pool and module in the same reviewed change. SQL and
  module rollback together.
