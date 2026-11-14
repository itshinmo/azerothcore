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

### Verification

Static content checks run against the database, not against a running world. They are read-only,
deterministic, and fast enough to run before every release. The extractor and the public catalog
share one query layer; see [world-data.md](world-data.md).

**Check catalog**

| ID | Check | Severity |
|----|-------|----------|
| C-01 | Quest starter or ender references a missing creature or gameobject | blocker |
| C-02 | Quest objective target has no template (blocker), or no spawn (minor; may be summoned) | blocker / minor |
| C-03 | Quest chain broken: prerequisite cycle or missing prerequisite (blocker); MinLevel above QuestLevel (minor) | blocker / minor |
| C-04 | Required item missing (blocker), or no known loot, vendor, or quest source (minor) | blocker / minor |
| C-05 | SmartAI row with an invalid event, action, or target type, `event_chance` above 100, or a phase mask beyond the supported bits | major |
| C-06 | SmartAI `link` chain broken, or a phase no event can reach | major |
| C-07 | `AIName='SmartAI'` with zero rows, or rows present without `AIName` | major |
| C-08 | Database `ScriptName` not registered in `src/server/scripts` | blocker |
| C-09 | Instance without a registered `InstanceScript` | blocker |
| C-10 | Spawn of a missing template (blocker); `spawnMask` of 0 (major) | blocker / major |
| C-11 | Vendor/trainer flag without stock or assignment (minor; cosmetic, needs content review); vendor sells a missing item (blocker); trainer spell missing (major) | blocker / major / minor |
| C-12 | Loot referencing a missing item (blocker) or a missing reference loot table (major) | blocker / major |
| C-13 | Conditions: gossip menu/option and quest-available source rows referencing missing rows | major |

v1 limits: map-bounds validation is skipped because `map_dbc` is empty; trainer spells are checked
against `Spell.dbc` from `DataDir`, never the `spell_dbc` override table; conditions are audited only
for the three source types with verified semantics (14 gossip menu, 15 gossip menu option, 19 quest
available), and C-06 phase reachability is not checked.

Severity meaning:

- **blocker** — content cannot be reached or completed, or a scripted encounter cannot run.
- **major** — content is playable but visibly wrong.
- **minor** — data hygiene only.

**Report**

- Markdown for humans, JSON for the tool and CI.
- Each finding carries: check id, severity, entity kind, entity id, location, and one line of cause.
- The findings are ordered by severity, then entity id, so their order is stable across runs.
- A clean run prints zero findings and exits zero. Any unwaived blocker exits non-zero.

**Waivers**

- Tracked file `tools/dev/content-audit-waivers.json`.
- Each waiver carries the check id, entity id, a non-empty reason, and the person who accepted it.
- Duplicate waivers for the same finding are rejected.
- A waiver for a removed entity is itself reported, so the file cannot rot silently.

**Coverage metric**

- Coverage is the share of quests in a level band that have a starter row and all objectives
  resolvable from database data, divided by the quests defined for that band.
- Reported per band (1-20, 21-40, 41-60, 61-70, 71-80, 81-255) and overall.
- The number is published. It is the QA scoreboard, not an internal vanity metric.

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
