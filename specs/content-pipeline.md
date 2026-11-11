# Content pipeline

## Purpose

Define how game content is authored, stored, loaded, and verified. New content is currently out of
scope; this contract exists so future work starts correctly.

## Scope

Creatures, NPCs, quests, items, mounts, vendors, loot, gameobjects, SmartAI, conditions, instances, and
the split between SQL, C++ scripts, modules, and client data.

## Boundary

Owns content storage and loading. Does not own individual content design; that belongs in a content
spec. Does not own the client patch pipeline, which is documented but not implemented.

## Contract

### Storage

| Kind | Location | Rules |
|------|----------|-------|
| Project data | `data/sql/custom/db_world/` | re-applicable; `DELETE` + `INSERT`; reserved IDs |
| Upstream-shaped fix | `data/sql/updates/pending_db_world/` | one-time; follows SQL lint |
| C++ behavior | `modules/mod-*` | preferred over core edits or `scripts/Custom/` |
| Core script | `src/server/scripts/` | only for upstream behavior; not project content |
| Client assets | external client patch | DBC/MPQ plus map/vmap/mmap extraction |

### Reserved IDs

- Items `900000–909999`
- Creatures `910000–919999`
- Quests `920000–929999`
- GameObjects `930000–939999`
- Spells `940000–949999`
- Misc `950000–959999`
- Maps `1000+`

The registry is [runbook/database/id-registry.md](../runbook/database/id-registry.md). Every new ID is
recorded there before use.

### Minimum rows

**Quest chain**

- `quest_template` one row per quest, plus `quest_template_addon`.
- `creature_template` + `creature_template_model` + `creature` spawn for the questgiver.
- `creature_queststarter` / `creature_questender`; `npcflag & 2`.
- Objective targets: creature template and spawn, gameobject, or item.
- Loot rows with `QuestRequired=1` where the objective is a drop.
- Optional: `quest_details`, `quest_offer_reward`, `quest_request_items`, `quest_poi`,
  `quest_poi_points`, `conditions` source 19.

**NPC vendor**

- `creature_template` with `npcflag & 128`, template model, spawn.
- `npc_vendor` rows; optional `conditions` source 23 for gating.

**Item or mount**

- `item_template` and, where the client needs it, `item_dbc`.
- Mount: class 15, subclass 5, `spellid_1` = mount spell, `spelltrigger_1=0`.
- A genuinely new spell or visual needs a client patch; reuse an existing client spell ID otherwise.

**Instance**

- `instance_template` row with a registered `InstanceScript` name.
- Spawns on the map, `instance_encounters`, loot, bosses.
- Client Map.dbc/MapDifficulty.dbc/AreaTrigger.dbc rows if the map is new.
- Server `maps/`, `vmaps/`, `mmaps/` files extracted from the patched client.

### SmartAI

- Prefer SmartAI for data-driven creature behavior.
- `creature_template.AIName='SmartAI'`; `gameobject_template.AIName='SmartGameObjectAI'`.
- Full-block rewrite of `(entryorguid, source_type)`.
- Timed action lists use positive `entryorguid = base * 100 + listId` and `source_type=9`.
- Use named enums in C++ wrappers, not raw event/action numbers.

### Client data boundary

- The server can change gameplay data without a client patch through `*_dbc` tables.
- New maps, zones, item icons/models, spell visuals, creature displays, and area triggers need a
  client MPQ/DBC patch.
- After a client patch, run the extractors for `maps/`, `vmaps/`, `mmaps/`, and update `DataDir`.
- Reuse existing assets until the client-patch pipeline is documented and approved.

## Errors and edge cases

- A `SpellScript` without `spell_script_names` is inert.
- A creature with `AIName='SmartAI'` and no rows is inert.
- A questgiver without `npcflag & 2` does not offer the quest.
- A spawn with an unknown map or missing map files is unplayable.
- A summon of an entry in an `InstanceScript` `ObjectData` table steals the data slot.

## Security

- No player data in content files.
- No client assets from unlicensed sources.
- No executable content in SQL.

## Observability

- `Errors.log` for unknown IDs, missing models, and invalid loot.
- `updates` table for applied SQL.
- In-game GM checks: `.lookup`, `.npc info`, `.quest status`, `.reload`.

## References

- [.agents/docs/sql-guidelines.md](../.agents/docs/sql-guidelines.md)
- [.agents/docs/cpp-scripts.md](../.agents/docs/cpp-scripts.md)
- [runbook/database/id-registry.md](../runbook/database/id-registry.md)
- [decisions/ADR-002-custom-content-isolation-and-ids.md](../decisions/ADR-002-custom-content-isolation-and-ids.md)
