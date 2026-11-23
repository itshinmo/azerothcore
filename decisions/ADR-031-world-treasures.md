# ADR-031: Hand-placed world treasures with unique items

- Status: proposed
- Date: 2026-11-23
- Deciders: repo owner (100-item target and batch contract), implementation agent (batch 1)
- Related: [ADR-002](ADR-002-custom-content-isolation-and-ids.md),
  [ADR-006](ADR-006-shop-policy.md), [ADR-011](ADR-011-world-data-and-content-verification.md),
  [ADR-013](ADR-013-server-and-client-before-website.md)

## Context

The server needs a long-tail exploration reward that is not another daily quest, a vendor, or a
random drop. A hand-placed chest gives the world a reason to be walked through, and an item that a
character can own only once makes the find personal without adding power that competes with the
shop or with raid progression.

The owner approved a target of 100 treasures. Batch 1 proves the loop with 20 items: 12 Classic, 4
TBC, and 4 WotLK. The remaining 80 are authored in four more batches of 20 with the same contract.

The native game already has every mechanism the feature needs. `item_template.maxcount` is the
unique-ownership check: `Player::CanTakeMoreSimilarItems` counts the item in bags, bank, and
equipped slots through `GetItemCount(entry, true, item)`. A type-3 gameobject with a loot table and
`spawntimesecs` already provides a shared object that respawns. One core gap surfaced in testing:
unlocked chests (`lockId = 0`) were not opened by `GameObject::Use`; locked chests worked only through
`Spell::EffectOpenLock`. Batch 1 adds the missing direct-use branch, and a GM-only `.treasure`
placement tool (module, RBAC `950152`) previews and records chest coordinates.

## Decision

1. **One hand-placed chest per treasure.** Each treasure is a type-3 gameobject (chest, crate, or
   sack model) with a one-row loot table. The loot table has a 100% chance for exactly one item.
2. **Unique per character, not per account.** The item template sets `maxcount = 1`. Bags, bank,
   and equipped slots all count. If the character already owns the item, looting fails with the
   native "can only carry one" error. If the item is dropped, destroyed, or traded away, the
   character can loot it again on a later spawn.
3. **Shared object, 30-60 minute respawn.** The chest is a normal world spawn, not a per-player
   object. One player loots it, it despawns, and it returns after `spawntimesecs` (1800-3600
   seconds, set per spawn). Other players see the same chest.
4. **Hand-placed in iconic, non-instanced locations.** Every coordinate is checked against the
   local world database. A new treasure must be at least 1.5 yards from an existing gameobject spawn
   and at least 2 yards from an existing creature spawn (3D distance). The chest is placed on a
   floor coordinate taken from a nearby anchor spawn, never in an instance, and never in a capital
   city's auction house crowd.
5. **Era scope.** Batch 1 is 12 Classic, 4 TBC, and 4 WotLK items. Later batches keep the same
   era mix unless the owner changes the target. No new maps, zones, display IDs, spells, or client
   assets are introduced.
6. **No pay-for-power and no real-money value.** Items are uncommon to epic, but their stat budget
   stays below the best same-level dungeon or raid reward. They are not sold by a vendor and have a
   zero sell price. They are not part of the shop, a real-money product, or a power promise.
7. **Mixed binding.** Some items bind on pickup, some bind on equip. Binding does not change the
   unique rule; the item still counts while owned.
8. **Reserved IDs.** Items use the `901000+` block, gameobject entries and loot tables use the
   `930000+` block. Each batch takes 20 consecutive slots. Spawn GUIDs use a block reserved against
   the current global `gameobject` maximum, not the 930000 range, because spawn GUIDs are a
   separate key space. Batch 1 uses item entries `901001-901020`, gameobject and loot entries
   `930001-930020`, and spawn GUIDs `5714501-5714520`.
9. **Authoring format.** A CSV row is the source of truth for one treasure: item entry, name, era,
   zone, map and coordinates, gameobject entry, spawn GUID, display IDs, quality, binding, level,
   slot, respawn, model sources, and a content note. The SQL is written from the CSV. The format and
   batch workflow are in [specs/world-treasures.md](../specs/world-treasures.md).
10. **Storage.** Re-applicable project SQL in `data/sql/custom/db_world/`. Item and gameobject
    template rows use `REPLACE` because the SQL linter forbids `DELETE` on those tables. Spawns and
    loot rows use `DELETE` + `INSERT` over the reserved block.

## Consequences

- A player who already owns the treasure sees the item in the chest but cannot loot it. That is the
  intended unique rule; the chest remains for another player until it is looted and respawns.
- A character who destroys the item can find it again. This is deliberate: the treasure is a
  keepsake, not a one-time account flag.
- The object is shared, so two players cannot both loot the same spawn. The unique check is still
  per character, and the respawn gives the second player another chance.
- `maxcount = 1` also blocks receiving a second copy by trade or mail. That matches the unique
  promise and is a native behavior, not a new rule.
- The core now has one chest direct-use branch for unlocked chests; locked chests keep the
  `EffectOpenLock` path. The `.treasure` preview/save/export tool is a GM-only module and never
  appears to players. If a future requirement needs per-player loot visibility or a hidden loot row
  when the player owns the item, that is a new decision and a core or module change.
- The 100-item target needs four more batches. The CSV format, the ID formula, and the overlap
  check make each batch mechanical.

## Rejected alternatives

- **C++ per-character gating.** The native `maxcount` check already covers bags, bank, and equipped
  slots. A script hook would add code, a reload surface, and a second source of truth.
- **Random loot tables.** A random table hides the unique item behind a second dice roll and makes
  the content note inaccurate. The chest exists because of the item, so the drop is guaranteed.
- **Account-wide unique.** The owner chose per-character ownership. Account-wide flags would make
  alts unable to find the same keepsake and would need a new account table.
- **A vendor or shop delivery.** That turns exploration into a purchase and conflicts with the
  no-pay-for-power rule and the shop policy in [ADR-006](ADR-006-shop-policy.md).
- **New item icons, models, or maps.** The client-patch pipeline is not ready. Batch 1 reuses
  existing displays and the existing world.
- **Instanced placement.** Instances are not shareable world traffic and would turn the treasure
  into a dungeon drop. Batch 1 uses only open-world locations.

## References

- [specs/world-treasures.md](../specs/world-treasures.md)
- [specs/content-pipeline.md](../specs/content-pipeline.md)
- [runbook/database/id-registry.md](../runbook/database/id-registry.md)
- [data/sql/custom/db_world/world_treasures_batch_01.sql](../data/sql/custom/db_world/world_treasures_batch_01.sql)
- [specs/world-treasures/batch_01.csv](../specs/world-treasures/batch_01.csv)
