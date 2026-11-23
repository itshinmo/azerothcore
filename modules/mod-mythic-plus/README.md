# mod-mythic-plus

First playable Mythic+ slice: Ragefire Chasm (map 389), key levels 1-5.

**This slice has not been tested in-game.** The SQL has been applied twice to scratch databases and the
module is built and linked, but no worldserver has been started for a playtest.

- Creature `910013` has two spawns: `5400020` in Orgrimmar gives guidance and status; `5400021`
  inside Ragefire Chasm, beside the instance entrance, starts the run at key 1-5. Group leader only;
  a solo player is accepted. A GM-mode character cannot start.
- Every member's next key is `highest completed key + 1` (default 1). A start is refused when any
  member's next key is below the selected key.

## Progression contract

```text
Highest-key rule: `highest_key` is the highest key completed per era. A run at key K may start only
when `K <= highest_key + 1` for every member and `K <= 20`. On a timed completion
`highest_key = max(highest_key, K)`, capped at 20. Never store `K + 1`: `highest_key + 1` is
derived, so a repeat or a lower-key run cannot advance the ceiling by more than one key.
```

- The timer is 30 minutes and starts on the first damage to a hostile creature. A 15-minute prestart
  timeout aborts a run that never starts.
- A death after the timer starts adds 5 seconds.
- Four affixes: trash health, boss health, additional trash copies, and more creature damage.
- Creature level, health multiplier and damage multiplier come from `mythic_plus_creature_scale`.
- A timed completion pays 1-5 gold (10000-50000 copper) per eligible member and unlocks the next key.
  A missed timer pays nothing and does not unlock a key.
- A member who leaves the instance is marked ineligible for rewards and the key unlock, including on
  rejoin.
- Active runs are deleted at world start. A restart never restores a run or blocks a new one.
- Loot is the existing dungeon loot. This slice does not generate scaled item copies.

## Test steps

1. Apply `data/sql/custom/db_world/zz_mythic_plus.sql`,
   `data/sql/custom/db_characters/zz_mythic_plus.sql` and
   `data/sql/custom/db_auth/mythic_plus_rbac.sql` (or restart the local worldserver so the custom
   updater applies them). Apply each file twice; both applies must succeed.
2. Start the worldserver. Check the log for `Loaded 1 dungeon(s), 4 boss(es), 10 scale(s), 5 key level(s)`.
3. Log in a level-80 character. `.mythic status` as an admin: `database ready: yes`, module enabled,
   with 1 dungeon, 4 bosses, 10 scales and 5 key levels.
4. Talk to Mythic Plus `5400020` outside the Ragefire Chasm entrance in Orgrimmar. It shows guidance
   and status. Enter the normal Ragefire Chasm instance.
5. Talk to the inside NPC `5400021` beside the instance entrance. Gossip -> Start a Mythic+ run ->
   Key 1. Solo or group leader only. The start message appears; the timer must not move until the
   first damage to a hostile creature. `.mythic info` shows key, timer and affixes.
6. Die once after the timer starts. The penalty must be 5 seconds. Kill Taragaman the Hungerer
   `11520` before the limit. Verify the completion message, the gold, and that the character's next
   key is 2.
7. Reset the instance. Key 2 starts. Key 3 is refused until key 2 is completed. A group member whose
   next key is lower than the selected key refuses the whole start with a clear message.
8. Group test: start a run, let one member leave the instance and re-enter, then complete. The member
   must be listed ineligible and receive no gold or key unlock.
9. Restart the worldserver with an active run. The run row must be gone (`SELECT * FROM
   mythic_plus_dungeon` is empty) and a new run must start in a fresh instance.
10. `.mythic reload` during an active run must be refused. After the run, it must reload key levels,
    scales, affixes and configuration.

## Migration from the previous slice

- `mythic_plus_capable_dungeon`, `mythic_plus_boss`, `mythic_plus_level`, `mythic_plus_affix`,
  `mythic_plus_level_rewards` and `mythic_plus_creature_scale` are dropped and recreated. This
  replaces the old capable-dungeon table without `era` and removes the old explosion affix type 4.
- `item_template` entry `5373` is restored to `Lucky Charm`, quality 1, no bind, stackable 5,
  maxcount 0, buy 290, sell 72, no description and no script, in case the previous slice renamed it.
- `mythic_plus_dungeon` rows are deleted. Runs never survive a restart.
- `mod_mythic_plus_progress` and `mythic_plus_dungeon` remain `CREATE TABLE IF NOT EXISTS`.

SQL lives at `data/sql/custom/db_world/zz_mythic_plus.sql`,
`data/sql/custom/db_characters/zz_mythic_plus.sql` and
`data/sql/custom/db_auth/mythic_plus_rbac.sql`.

This is a fork of <https://github.com/silviu20092/mod-mythic-plus> at commit `e2a487d` (MIT). See
`UPSTREAM.md` for local divergence and `LICENSE` for the licence.
