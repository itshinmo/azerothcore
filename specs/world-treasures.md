# World treasures

## Purpose

Define the hand-placed world treasure framework: one chest, one unique item, a shared world spawn,
and a repeatable authoring format for the 100-item target.

## Scope

Treasure items, their gameobject containers, spawn placement, loot tables, ID ranges, era mix, and
the batch authoring format. Batch 1 is 20 items (12 Classic, 4 TBC, 4 WotLK).

## Boundary

Owns the treasure contract and the batch-1 data. Does not own the general item or gameobject
storage rules, which are [content-pipeline.md](content-pipeline.md). Does not own the client patch
pipeline, and does not add new maps, display IDs, spells, or client assets.

## Contract

### Treasure definition

A treasure is a hand-placed type-3 gameobject (chest, crate, or sack model) with a one-row
`gameobject_loot_template` entry: one item, 100% chance, `MinCount = 1`, `MaxCount = 1`. The
gameobject is a normal shared world spawn, not a per-player object.

### Unique ownership

`item_template.maxcount = 1` is the unique rule. It is enforced by the native item storage path:
`Player::CanTakeMoreSimilarItems` calls `GetItemCount(entry, true, item)`, and `inBankAlso = true`
counts the bank as well as bags and equipped slots. Consequences:

- A character who already owns the item cannot loot another copy. The loot attempt returns
  `EQUIP_ERR_CANT_CARRY_MORE_OF_THIS`.
- Dropping, destroying, or trading the item removes it from the count. The character can loot it
  again on a later spawn.
- The check is per character, never per account.
- No C++ hook is used. The behavior is native.

The loot row still appears in the chest window for a character who already owns the item. The
character cannot take it, and the chest remains for another player. Once the chest is looted, it
respawns on its timer. Hiding the row would need a core or module change and is out of scope.

### Respawn and sharing

The chest is shared. One player loots it, the chest despawns, and it returns after
`gameobject.spawntimesecs`. Batch 1 uses 1800 seconds (30 minutes) for low-level Classic treasures,
2700 seconds (45 minutes) for the rest of Classic and TBC, and 3600 seconds (60 minutes) for WotLK.
`gameobject_template.Data3 = 1` makes the chest consumable on loot. `Data2 = 0` leaves no separate
restock timer.

### Placement

- Non-instanced open-world locations only.
- Coordinates must be on valid floor. Batch 1 uses the position of a nearby anchor spawn as the
  height reference, then offsets by 1-8 yards. The CSV records the final position; the content note
  names the landmark.
- No overlap with an existing spawn: at least 1.5 yards from an existing gameobject and at least 2
  yards from an existing creature, measured in 3D.
- Iconic, era-appropriate locations. Batch 1 visits inns, towers, chapels, auction houses, expedition
  camps, and faction hubs, not capital-city auction-house crowds.
- `zoneId` and `areaId` stay `0`; the zone name is content metadata in the CSV. The server does not
  need it to spawn the object.

### Era scope and batch plan

The owner approved 100 treasures. Batch 1 proves the loop with 12 Classic, 4 TBC, and 4 WotLK items.
The remaining 80 are four more batches of 20 with the same era mix unless the owner changes it.

| Batch | Items | Era mix | Item entries | Gameobject and loot entries |
|-------|-------|---------|--------------|-----------------------------|
| 1 | 20 | 12 Classic, 4 TBC, 4 WotLK | `901001-901020` | `930001-930020` |
| 2 | 20 | TBD | `901021-901040` | `930021-930040` |
| 3 | 20 | TBD | `901041-901060` | `930041-930060` |
| 4 | 20 | TBD | `901061-901080` | `930061-930080` |
| 5 | 20 | TBD | `901081-901100` | `930081-930100` |

Batch 1 uses spawn GUIDs `5714501-5714520`. Later batches reserve the next 20 GUIDs above the
current global `gameobject` maximum and record the block in
[runbook/database/id-registry.md](../runbook/database/id-registry.md).

### Balance and no pay-for-power

- Quality is uncommon, rare, or epic.
- The stat budget stays below the best same-level dungeon or raid reward. Trinkets use plain stats
  or existing item stats; no new spells.
- Some items bind on pickup, some bind on equip.
- No vendor sale, no auction-house supply, no shop product, and no real-money value.
- `BuyPrice = 0` and `SellPrice = 0`; the item cannot be converted into gold through a vendor.
- No item has a random property or random suffix.

### IDs

Items use `901000+`. Gameobject entries and their loot tables use `930000+`. Spawn GUIDs are a
separate key space and use a reserved block above the global maximum, recorded in the ID registry.
The batch-1 SQL is
[data/sql/custom/db_world/world_treasures_batch_01.sql](../data/sql/custom/db_world/world_treasures_batch_01.sql).

### Authoring format

The machine-readable source for one treasure is a row in
[specs/world-treasures/batch_01.csv](world-treasures/batch_01.csv). The field dictionary and the
batch workflow are in [specs/world-treasures/README.md](world-treasures/README.md). The columns are:

| Column | Meaning |
|--------|---------|
| `item_entry` | Item template entry |
| `item_name` | Item and gameobject name |
| `era` | `Classic`, `TBC`, or `WotLK` |
| `zone` | Zone name |
| `location` | Named landmark |
| `map` | Map id |
| `pos_x`, `pos_y`, `pos_z` | Final spawn position |
| `gameobject_entry` | Type-3 gameobject template entry |
| `spawn_guid` | Gameobject spawn GUID |
| `go_display_id` | Container display id |
| `loot_entry` | `gameobject_loot_template.Entry` |
| `quality` | `uncommon`, `rare`, or `epic` |
| `bonding` | `1` bind on pickup, `2` bind on equip |
| `item_level`, `required_level` | Item budget and use level |
| `inventory_type`, `item_class`, `item_subclass` | Item slot and type |
| `item_display_id` | Item display id |
| `maxcount` | Always `1` for a treasure |
| `respawn_seconds` | 1800-3600 |
| `container_model`, `item_model` | Existing source of the visuals |
| `content_note` | One line used in the content table and SQL comments |

### Batch 1 content

| ID | Item | Era / zone | Container / item model | Quality / bind | Why it is there |
|----|------|------------|------------------------|----------------|-----------------|
| 901001 | Goldshire Ledger | Classic / Elwynn Forest | Crate 18 (Abercrombie's Crate) / Mystic Tome 54808 | uncommon / BoP | The first treasure a new Alliance character can find, inside the Goldshire inn. |
| 901002 | Sentinel Hill Signal Lantern | Classic / Westfall | Supply crate 336 / Nolkai's Lantern 36575 | uncommon / BoE | Westfall militia signal gear on the hill that guards the road to Stormwind. |
| 901003 | Auberdine Tidecaller's Charm | Classic / Darkshore | Basket 644 (Shimmerweed Basket) / Amulet of the Moon 9657 | uncommon / BoE | A tide charm at the Darkshore inn, on the way north from Teldrassil. |
| 901004 | Astranaar Moonguard Sigil | Classic / Ashenvale | Wooden chest 10 (Sunken Chest) / Seal of Wrynn 9845 | rare / BoE | A sentinel sigil in Astranaar, the night elf hub in Ashenvale. |
| 901005 | Booty Bay Smuggler's Coil | Classic / Stranglethorn Vale | Sack 5511 (Amadi Sack) / Ogron's Sash 28802 | rare / BoE | A smuggler belt from the Booty Bay auction house, a pirate-town landmark. |
| 901006 | Gadgetzan Sandstorm Goggles | Classic / Tanaris | Crate 335 / Green Lens 19563 | rare / BoE | Gadgetzan goggles for the Tanaris sand, at the goblin desert hub. |
| 901007 | Marshal's Refuge Field Compass | Classic / Un'Goro Crater | Battered chest 259 / Smotts' Compass 6562 | rare / BoE | A field compass at Marshal's Refuge, the Un'Goro expedition camp. |
| 901008 | Everlook Frostweave Blanket | Classic / Winterspring | Basket 644 / Mystical Cape 23136 | uncommon / BoE | A winter blanket from the Everlook inn in Winterspring. |
| 901009 | Light's Hope Prayer Beads | Classic / Eastern Plaguelands | Chest 41 (Benedict's Chest) / Scout's Medallion 32008 | rare / BoP | Prayer beads from Light's Hope Chapel, the Argent Dawn outpost. |
| 901010 | Brill Gravedigger's Spade | Classic / Tirisfal Glades | Wooden chest 10 / Battering Hammer 8585 | uncommon / BoE | A gravedigger's spade from Brill, the Forsaken starting hub. |
| 901011 | Shimmering Flats Salt Goggles | Classic / Thousand Needles | Supply crate 336 / Adventurer's Pith Helmet 18322 | uncommon / BoE | Salt goggles from the Mirage Raceway in the Shimmering Flats. |
| 901012 | Feathermoon Sentinel's Longbow | Classic / Feralas | Battered chest 259 / Harpy Needler 28543 | rare / BoE | A longbow from Feathermoon Stronghold in Feralas. |
| 901013 | Honor Hold Bulwark Fragment | TBC / Hellfire Peninsula | Adamantite chest 5744 / Emperor Shield 40781 | rare / BoE | A shield splinter from Honor Hold, the Alliance foothold in Hellfire. |
| 901014 | Cenarion Refuge Sporeling Charter | TBC / Zangarmarsh | Knapsack 7144 (Arelion's Knapsack) / Book of Many Blessings 44544 | uncommon / BoP | A sporeling charter from Cenarion Refuge in Zangarmarsh. |
| 901015 | Garadar Ancestor's Totem | TBC / Nagrand | Sack 5511 / Uniting Charm 37552 | rare / BoE | An ancestor totem from Garadar, the Mag'har town in Nagrand. |
| 901016 | Area 52 Telemetric Rod | TBC / Netherstorm | Supply crate 5531 / Wand of the Netherwing 43449 | rare / BoE | A telemetric rod from Area 52 in Netherstorm. |
| 901017 | Valiance Keep Winter Cloak | WotLK / Borean Tundra | Bundle 7224 / Riding Cloak 50050 | uncommon / BoE | A winter cloak from Valiance Keep, the Alliance landing in Borean Tundra. |
| 901018 | Amberpine Trapper's Knife | WotLK / Grizzly Hills | Knapsack 7144 / Elanor's Edge 52445 | rare / BoP | A trapper knife from Amberpine Lodge in Grizzly Hills. |
| 901019 | K3 Surveyor's Sextant | WotLK / The Storm Peaks | Adamantite chest 5744 / Badge of the Infiltrator 34188 | rare / BoE | A surveyor sextant from K3 in the Storm Peaks. |
| 901020 | Crusader's Oathband | WotLK / Icecrown | Argent tribute chest 9069 / Ring of the Fated 35313 | epic / BoP | An Argent oathband from the Argent Tournament grounds in Icecrown. |

### Validation

1. SQL lint: `python apps/codestyle/codestyle-sql.py` passes.
2. ID check: item entries, gameobject entries, loot entries, and spawn GUIDs are free in the local
   world database before the batch is applied.
3. Spawn overlap check: for every CSV row, select creatures and gameobjects on the same map within
   6 yards in 3D. Batch 1 minimums are 1.89 yards to an existing gameobject (Goldshire food crate)
   and 2.86 yards to an existing creature (Goldshire Barkeep Dobbins). No spawn is coincident.
4. Unique check: all 20 item rows have `maxcount = 1`; all 20 loot rows have one item, 100% chance,
   `MinCount = 1`, `MaxCount = 1`; item and loot entries are one-to-one.
5. Model check: every item display id and gameobject display id belongs to an existing template of
   the same slot or container type. No new client asset is required.

A static check cannot prove floor height after terrain changes. The anchor positions come from live
world spawns, so a chest that follows an anchor is safe unless the zone geometry is later patched.
Re-run the overlap check when a zone is changed or when a new batch is authored.

## Errors and edge cases

- **Player already owns the item.** Looting fails with the native unique error. The chest remains
  for another player. This is intended.
- **Item is in the bank or equipped.** Both count. The character cannot loot a second copy.
- **Item is dropped, destroyed, or traded.** The count falls, and a later spawn can be looted again.
- **Two players at one chest.** The object is shared. Only the first looter gets the item; the
  second sees the empty or despawned chest.
- **Spawn block collision.** The spawn GUIDs are reserved above the global maximum. If a future
  upstream update fills the block, move the block, update the registry, and re-apply.
- **Item template changed by a later batch.** `REPLACE` rewrites the custom row and keeps the entry
  present. `DELETE` on `item_template` is forbidden. Do not edit the row in another file.
- **Missing model or display.** The client shows a fallback or an error. The source display ids are
  from existing templates, so this should not happen.
- **Chest never looted.** A chest left by a character who already owns the item stays until another
  player loots it or the world reloads. It does not block the item for anyone else.

## Security

- No secrets, credentials, player data, or production values in the SQL, CSV, or spec.
- No executable content in SQL.
- No real-money value and no pay-for-power. The items are not shop products.
- The treasure is ordinary world content. It does not bypass RBAC, audit, or the GM API.

## Observability

- `Errors.log` reports an unknown item, gameobject, display, or loot entry at load time.
- `updates` records the custom SQL apply.
- In game: `.gobject near`, `.lookup object <entry>`, `.lookup item <entry>`, and the chest tooltip
  confirm the spawn and item.
- The loot window shows the item and the unique error on a character who already owns it.

## References

- [ADR-031](../decisions/ADR-031-world-treasures.md)
- [content-pipeline.md](content-pipeline.md)
- [specs/world-treasures/README.md](world-treasures/README.md)
- [specs/world-treasures/batch_01.csv](world-treasures/batch_01.csv)
- [runbook/database/id-registry.md](../runbook/database/id-registry.md)
- [.agents/docs/sql-guidelines.md](../.agents/docs/sql-guidelines.md)
- `src/server/game/Entities/Player/PlayerStorage.cpp` — `CanTakeMoreSimilarItems`, `GetItemCount`
- `src/server/game/Entities/Player/Player.cpp` — `StoreLootItem`
- `src/server/game/Handlers/LootHandler.cpp` — gameobject loot path
