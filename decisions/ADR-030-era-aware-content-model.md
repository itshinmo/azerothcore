# ADR-030 — Era-aware content model for objectives

- Status: proposed
- Date: 2026-11-23
- Implements: owner request for a Classic/TBC/WotLK aware objective model

## Context

The realm is Classic-first, but the same objective engine must serve later eras without a schema
rewrite or a second module. A task can be valid for one expansion, a level band, one faction and one
zone; a vendor offer has the same era and level constraints. The first slice seeds Classic data only,
so the engine must not assume "everything is Classic" in a way that blocks TBC and WotLK rows later.

Numbering: ADR-027 is allocated on the client-patch branch; see ADR-028's context note.

## Decision

1. **One row per era.** Every task and offer row carries `era`:
   `0` Classic, `1` The Burning Crusade, `2` Wrath of the Lich King. A row belongs to exactly one
   era; later content adds rows, it does not add columns or tables.
2. **Level bands are data.** Every task and offer row carries `min_level` and `max_level`
   (`max_level = 0` means no upper bound). The selection query filters the player's level into the
   band. Level bands are independent of era so a Classic task can cover levels 10–60 and a TBC task
   can cover 58–70.
3. **Faction and zone are filters, not hard-coded tables.** A task carries `faction` (`0` any,
   `1` Alliance, `2` Horde) and `zone_id` (`0` any). The daily pool prefers the character's focus
   zone; weekly and chronicle pools ignore zone unless the task sets one. A quest task with
   `zone_id` matches either the player's zone or the quest's `ZoneOrSort`.
4. **The active era is a config value.** `Objectives.Era` defaults to `0` (Classic). Selection
   accepts rows with `era <= Objectives.Era`. A Classic-only realm therefore sees only Classic
   rows; a future TBC realm flips one value and adds rows. It does not silently show WotLK tasks on
   a Classic realm.
5. **The schema ships all eras now.** `mod_objectives_task` and `mod_objectives_offer` have the era
   and level columns in this slice, even though only era `0` rows are seeded. This is the point of
   the ADR: the shape is stable before the data grows.
6. **Client assets do not change.** All first-slice tasks name existing creatures, quests,
   battlegrounds and items. No DBC, MPQ or map data is added. TBC and WotLK rows will reuse the same
   approach until a client-patch pipeline exists.
7. **Validation at load.** The module rejects a task with an unknown type, an empty name or a
   `required_count` of zero, and logs one line per rejected row. Offers are rejected when their
   item is missing from `item_template`. Bad data fails safe: a missing task cannot crash a login.

## Alternatives considered

- **Separate tables per expansion (`mod_objectives_task_classic`, `_tbc`, `_wotlk`).** Three copies of
  every query, index and loader. Rejected; `era` is enough.
- **Separate modules per era.** Same duplication at the module level.
- **Column-per-era values (three reward columns).** Makes a task expressible in several eras at once,
  but complicates the loader and the addon protocol for no first-slice benefit. A task that should
  exist in every era is seeded as one row per era.
- **Hard-code Classic task IDs in C++.** Rebuild for every content change. Rejected; definitions are
  world data.
- **Use the client's expansion state.** The 3.3.5 client has no reliable "current era" for a private
  realm. Config plus data is authoritative.

## Consequences / tradeoffs

- A task for a later era can be added by SQL alone, with no code change.
- Flipping `Objectives.Era` is a realm-wide decision; it does not migrate existing boards. Existing
  daily rows stay until their reset, which is acceptable and bounded.
- Level bands must be maintained per row; there is no automatic derivation from the target creature
  or quest. The first slice uses hand-picked bands.
- The addon receives the active era only indirectly (via the tasks it is sent); it does not need an
  era field in the wire protocol.

## Performance

- **Expected cost.** Era and level filtering happens once per board generation, not per event. The
  task table is small (dozens of rows) and fully cached at startup.
- **Hot path.** None. Selection is O(cached tasks) on login/request; progress events use the cached
  defs.
- **Target.** 5–7k online players. Even a few hundred task rows fit in memory; the addon payload is
  bounded by the slot count, not by the era.
- **Measurement.** Log the number of loaded tasks per era at startup. If selection time becomes
  visible, measure board generation with the MySQL slow-query log for the single task query and
  with a startup timing line.

## References

- [specs/objectives.md](../specs/objectives.md)
- [ADR-028](ADR-028-objective-engine-board-chronicle.md)
- [ADR-002](ADR-002-custom-content-isolation-and-ids.md) (client-patch boundary)
