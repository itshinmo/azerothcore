# mod-treasure-placer

GM-only in-game placement tool for the hand-placed world treasures
([ADR-031](../../decisions/ADR-031-world-treasures.md), [specs/world-treasures.md](../../specs/world-treasures.md)).

## Commands

| Command | Effect |
|---|---|
| `.treasure list` | List items `901001-901100` with their chest entry and spawn GUID. |
| `.treasure preview <item>` | Spawn a temporary chest 1.5 yards in front of the GM for 10 minutes. No database write. |
| `.treasure save <item>` | Record the active preview chest's position and orientation for that item. |
| `.treasure export` | Print SQL-ready `UPDATE gameobject ... WHERE guid = ...` lines for every saved item. |
| `.treasure clear` | Remove the current preview chest. |

Only saved items are exported; previews live in memory. The export includes the map, position,
orientation and rotation quaternion. Copy the values into the spawn `INSERT` tuple in
`world_treasures_batch_01.sql` and into the matching `specs/world-treasures/batch_01.csv` row (the CSV
is the source of truth), then restart to apply the SQL.

## Install

1. Rebuild (the normal module build picks `modules/mod-treasure-placer` up).
2. Apply `data/sql/custom/db_auth/treasure_placer_command.sql`; permission `950152` is linked to the
   content-tester and admin RBAC roles (superadmin inherits admin). Never grant it to players.
3. Restart the worldserver; `.treasure list` is available to the GM role.

## Placement loop

1. Stand where the chest should sit and face the direction it should face. The preview lands
   1.5 yards in front of you.
2. `.treasure preview 901001`; look at the chest and confirm it is reachable.
3. Move one step and preview again until the position is right.
4. `.treasure save 901001` at the final spot.
5. Repeat for the other items.
6. `.treasure export`; copy the values into the matching spawn `INSERT` tuple in
   `data/sql/custom/db_world/world_treasures_batch_01.sql` and into the matching
   `specs/world-treasures/batch_01.csv` row. The CSV is the source of truth.

`save` uses the active preview chest's position and orientation when the item matches, so the spot
you inspected is the spot exported. Without a preview it uses the player's position. Instance and
battleground saves are refused.

## Notes

- The chest name and item come from `gameobject_template` and `item_template`; the tool never creates
  templates or items.
- Batch 1 is items `901001-901020`. The command accepts the reserved block up to `901100` so later
  batches work without a code change.
- Permission is GM-only; there is no player-facing command.
