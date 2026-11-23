# World treasures: batch authoring

This directory holds the machine-readable batch data for
[the world treasure contract](../world-treasures.md). Batch 1 is `batch_01.csv`; the SQL is
[data/sql/custom/db_world/world_treasures_batch_01.sql](../../data/sql/custom/db_world/world_treasures_batch_01.sql).

## Batch workflow

1. Read the contract in [specs/world-treasures.md](../world-treasures.md).
2. Take the next 20 item entries and the next 20 gameobject/loot entries from the table below.
3. Reserve the next 20 spawn GUIDs above the current global maximum:

   ```sql
   SELECT MAX(guid) FROM gameobject;
   ```

   Record the block in [runbook/database/id-registry.md](../../runbook/database/id-registry.md).
4. Copy `batch_01.csv` to `batch_NN.csv` and fill one row per treasure.
5. Write the SQL from the CSV. Keep the same five statements: items, gameobject templates, template
   addons, loot, spawns. Item and gameobject template rows use `REPLACE`; spawns and loot use
   `DELETE` + `INSERT` over the reserved block.
6. Validate:

   ```bash
   python apps/codestyle/codestyle-sql.py
   ```

   Then run the overlap query for every CSV row (see below) and check that the item rows have
   `maxcount = 1` and the loot rows have one item at 100%.
7. Add the batch table to [specs/world-treasures.md](../world-treasures.md) and the ID rows to the
   registry.

## ID blocks

| Batch | Item entries | Gameobject and loot entries |
|-------|--------------|-----------------------------|
| 1 | `901001-901020` | `930001-930020` |
| 2 | `901021-901040` | `930021-930040` |
| 3 | `901041-901060` | `930041-930060` |
| 4 | `901061-901080` | `930061-930080` |
| 5 | `901081-901100` | `930081-930100` |

Spawn GUIDs are not in the 930000 range. They are a separate key space and must be above the
current `gameobject` maximum. Batch 1 uses `5714501-5714520`.

## CSV columns

| Column | Type | Rule |
|--------|------|------|
| `item_entry` | integer | One per row, from the batch block |
| `item_name` | text | Unique item and gameobject name |
| `era` | text | `Classic`, `TBC`, or `WotLK` |
| `zone` | text | Zone name |
| `location` | text | Named landmark |
| `map` | integer | Map id |
| `pos_x`, `pos_y`, `pos_z` | float | Final spawn position, valid floor |
| `gameobject_entry` | integer | Type-3 template, same number as the batch block |
| `spawn_guid` | integer | From the reserved spawn block |
| `go_display_id` | integer | Existing chest, crate, sack, basket, or bundle display |
| `loot_entry` | integer | `gameobject_loot_template.Entry`, normally the gameobject entry |
| `quality` | text | `uncommon`, `rare`, or `epic` |
| `bonding` | integer | `1` bind on pickup, `2` bind on equip |
| `item_level` | integer | Era-appropriate, below the best same-level dungeon reward |
| `required_level` | integer | Use level |
| `inventory_type` | integer | 3.3.5 inventory type |
| `item_class` | integer | `2` weapon, `4` armor |
| `item_subclass` | integer | Weapon or armor subclass |
| `item_display_id` | integer | Existing item display of the same slot |
| `maxcount` | integer | Always `1` |
| `respawn_seconds` | integer | `1800` to `3600` |
| `container_model` | text | Container display id and source name |
| `item_model` | text | Item display id and source name |
| `content_note` | text | One line for the spec table |

## Placement check

For each CSV row, run this query with the row's map and coordinates. It returns every creature and
gameobject within 6 yards in 3D. The contract requires no creature within 2 yards and no gameobject
within 1.5 yards.

```sql
SELECT 'creature' AS kind, c.guid, ct.name,
       SQRT(POW(c.position_x - :x, 2) + POW(c.position_y - :y, 2) + POW(c.position_z - :z, 2)) AS dist
FROM creature c
JOIN creature_template ct ON ct.entry = c.id
WHERE c.map = :map
  AND ABS(c.position_x - :x) < 6
  AND ABS(c.position_y - :y) < 6
  AND SQRT(POW(c.position_x - :x, 2) + POW(c.position_y - :y, 2) + POW(c.position_z - :z, 2)) < 6
UNION ALL
SELECT 'gameobject', g.guid, gt.name,
       SQRT(POW(g.position_x - :x, 2) + POW(g.position_y - :y, 2) + POW(g.position_z - :z, 2))
FROM gameobject g
JOIN gameobject_template gt ON gt.entry = g.id
WHERE g.map = :map
  AND ABS(g.position_x - :x) < 6
  AND ABS(g.position_y - :y) < 6
  AND SQRT(POW(g.position_x - :x, 2) + POW(g.position_y - :y, 2) + POW(g.position_z - :z, 2)) < 6
ORDER BY dist;
```

The query uses `creature.id`, the spawn entry column in this repository's world schema. The check
is read-only.

## What the next batch must not do

- Do not add a new map, zone, display id, spell, or client asset.
- Do not place a chest in an instance or a capital-city auction-house crowd.
- Do not use a random loot table or a second item in the chest.
- Do not add a vendor, shop, or real-money path.
- Do not delete `item_template` rows. Use `REPLACE`.
- Do not reuse a spawn GUID or an item entry from another batch.
