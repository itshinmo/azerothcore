# Custom ID registry

## When to use

Before creating any custom item, creature, quest, gameobject, spell, or map. Record the new ID here in
the same change.

## Reserved ranges

| Kind | Range | Notes |
|------|-------|-------|
| Items | `900000–909999` | includes mounts, cosmetics, tokens |
| Items | `1100000–1899999` | Mythic+ obtainable scaled copies (generated); proposed, see ADR-034 |
| Items | `1900000–1999999` | Mythic+ QA/non-obtainable copies; never in loot, vendor or vault; proposed, see ADR-034 |
| Preview items | `2000000–2999999` | generated, non-obtainable transmog preview copies, id = `2000000 + source_entry`; never use for content |
| Preview items | `3000000–3999999` | preview copies of seven-digit source entries (same formula); reserved, unused today |
| Creatures | `910000–919999` | templates and spawns use different keys |
| Quests | `920000–929999` | includes chain addon rows |
| GameObjects | `930000–939999` | templates; spawn GUIDs use their own reserved block |
| Spells | `940000–949999` | server-side `spell_dbc` only until a client patch |
| Misc | `950000–959999` | text, conditions, other IDs; auth RBAC role groups also use this range |
| Maps | `1000+` | requires a client patch and extracted map data |

## Rules

- Never use an ID below the reserved range for project content.
- Never reuse an ID after deletion.
- Record the ID, kind, name, feature, and owner below before use.
- A new spell or item visual also needs a client patch; a server-only ID does not make the client
  render it.
- Keep `creature.guid`, `gameobject.guid`, and item GUIDs separate from entry IDs; use the map/global
  GUID generators.

## Registry

| ID | Kind | Name | Feature | Owner | Date |
|----|------|------|---------|-------|------|
| 950100 | Auth RBAC role | support | GM role preset | repo owner | 2026-11-12 |
| 950101 | Auth RBAC role | content-tester | GM role preset | repo owner | 2026-11-12 |
| 950102 | Auth RBAC role | economy | GM role preset | repo owner | 2026-11-12 |
| 950103 | Auth RBAC role | admin | GM role preset | repo owner | 2026-11-12 |
| 950104 | Auth RBAC role | superadmin | GM role preset | repo owner | 2026-11-12 |
| 1000003 | Creature entry | Arena 3v3 Solo | solo-queue NPC template (vendored mod-arena-3v3-solo-queue data; spawned nowhere by default) | ADR-024 | 2026-11-20 |
| 1000004 | npc_text | Arena 3v3 Solo greeting | solo-queue NPC text (vendored module SQL) | ADR-024 | 2026-11-20 |
| 950150 | Auth RBAC permission | Command: queue bg (project) | queue-from-anywhere player command | ADR-024 | 2026-11-20 |
| 910020 | Creature entry | Adventure Quartermaster | objective reward vendor template, Stormwind spawn GUID 5400011 (`objectives_engine.sql`) | ADR-029 | 2026-11-23 |
| 910021 | Creature entry | Chronicle Quartermaster | objective reward vendor template, Orgrimmar spawn GUID 5400012 (`objectives_engine.sql`) | ADR-029 | 2026-11-23 |
| 950151 | Auth RBAC permission | Command: pledge (project) | PvP rulesets `.pledge` player command (`pvp_rulesets_command.sql`) | ADR-033 | 2026-11-23 |
| 950200 | Misc (npc_text) | Objective vendor greeting | reward vendor gossip text | ADR-029 | 2026-11-23 |
| 950300–950324 | Misc (task rows) | `mod_objectives_task` launch tasks | 25 Classic objective definitions | ADR-028 | 2026-11-23 |
| 950340–950348 | Misc (offer rows) | `mod_objectives_offer` launch offers | reward vendor items | ADR-029 | 2026-11-23 |
| 910012 | Creature entry | Warpweaver | transmogrifier template + 10 capital spawns (`collections_npc_spawns.sql`, spawn GUID block 5400001–5400010) | collections (ADR-020) | 2026-11-20 |
| 910013 | Creature entry | Mythic Quartermaster | vendor/vault/pending-reward NPC template; spawn placed at implementation; **proposed, not yet allocated** (ADR-034, RFC-004) | repo owner | 2026-11-23 |
| 950160 | Auth RBAC permission | Command: mythic info | player permission for `.mythic info`; **proposed, not yet allocated** (ADR-034, RFC-004) | repo owner | 2026-11-23 |
| 950161 | Auth RBAC permission | Command: mythic start | player permission for `.mythic start`; **proposed, not yet allocated** (ADR-034, RFC-004) | repo owner | 2026-11-23 |
| 950162 | Auth RBAC permission | Command: mythic abandon | player permission for `.mythic abandon`; **proposed, not yet allocated** (ADR-034, RFC-004) | repo owner | 2026-11-23 |
| 950163 | Auth RBAC permission | Command: mythic status/reload | admin permission for `.mythic status` and `.mythic reload`; **proposed, not yet allocated** (ADR-034, RFC-004) | repo owner | 2026-11-23 |
| 950110–950119 | Misc (POI) | city Warpweaver markers | `points_of_interest` rows behind the guard gossip options (`collections_guard_directions.sql`) | collections (ADR-020) | 2026-11-20 |
| 950120 | Misc (npc_text) | guard answer | shared gossip answer text in `collections_guard_directions.sql` | collections (ADR-020) | 2026-11-20 |
| 1100000–1899999 | Items | Mythic+ obtainable scaled copies | generated `item_template`, server `item_dbc` and client `Item.dbc` rows for old-content Mythic+; **proposed, not yet allocated** (ADR-034, RFC-004) | repo owner | 2026-11-23 |
| 1900000–1999999 | Items | Mythic+ non-obtainable/QA copies | QA and GM-only copies; never in loot, vendor or vault; **proposed, not yet allocated** (ADR-034, RFC-004) | repo owner | 2026-11-23 |
| 2000000–2999999 | Items (generated) | transmog preview copies | off-hand copies of one-hand weapons (`InventoryType 22`) and main-hand copies of thrown weapons (`InventoryType 21`) in `zz_transmog_preview_items.sql`; non-obtainable | mod-transmog-plus (ADR-026) | 2026-11-23 |
| 901001–901020 | Item entries | world treasures batch 1 | 20 unique hand-placed chest items (`world_treasures_batch_01.sql`); 12 Classic, 4 TBC, 4 WotLK | ADR-031 | 2026-11-23 |
| 901021–901100 | Item entries | world treasures batches 2–5 | reserved 80-item block | ADR-031 | 2026-11-23 |
| 930001–930020 | Gameobject entries + loot tables | world treasures batch 1 | 20 type-3 chest templates and their one-row loot tables | ADR-031 | 2026-11-23 |
| 930021–930100 | Gameobject entries + loot tables | world treasures batches 2–5 | reserved 80-chest block | ADR-031 | 2026-11-23 |
| 5714501–5714520 | Gameobject spawn GUIDs | world treasures batch 1 | spawn block above the global `gameobject` maximum at authoring time | ADR-031 | 2026-11-23 |
| 950400–950407 | Misc (DBC rows) | combo starting outfits | `CharStartOutfit.dbc` rows for the batch-1 pairs (4 pairs × 2 genders), shipped in the client patch and the server `DataDir`; reserved, not yet used | ADR-035 | 2026-11-23 |
| 950410–950413 | Misc (DBC rows) | combo weapon skills | `skillraceclassinfo_dbc` rows for Blood Elf Warrior swords/axes/2H axes/daggers; reserved, not yet used | ADR-035 | 2026-11-23 |
| 910013 | Creature entry | Mythic Plus | start/guidance NPC template; two spawns: 5400020 Orgrimmar and 5400021 Ragefire Chasm entrance (`zz_mythic_plus.sql`) | mod-mythic-plus (RFC-004) | 2026-11-23 |
| 5400020 | Creature spawn GUID | Mythic Plus guidance | Orgrimmar spawn outside the Ragefire Chasm entrance | mod-mythic-plus (RFC-004) | 2026-11-23 |
| 5400021 | Creature spawn GUID | Mythic Plus start | Ragefire Chasm entrance spawn; starts the run inside the instance | mod-mythic-plus (RFC-004) | 2026-11-23 |
| 950160 | Auth RBAC permission | Command: mythic info | player command permission in `mythic_plus_rbac.sql` | mod-mythic-plus (RFC-004) | 2026-11-23 |
| 950163 | Auth RBAC permission | Command: mythic status/reload | admin command permission in `mythic_plus_rbac.sql` | mod-mythic-plus (RFC-004) | 2026-11-23 |

`mod_mythic_plus_progress` and `mythic_plus_dungeon` are characters-database tables created by this
slice; they allocate no entry IDs. `mythic_plus_capable_dungeon`, `mythic_plus_boss`,
`mythic_plus_level`, `mythic_plus_affix`, `mythic_plus_level_rewards` and
`mythic_plus_creature_scale` are world tables; they allocate no entry IDs.


World content IDs for the objective slice are listed above; the RBAC rows live in `acore_auth`, not
`acore_world`. Gameobject spawn GUIDs are a separate key space from the 930000 entry range; each
feature reserves its own block above the current global maximum. Preview ids are
`2000000 + source_entry`; a seven-digit source lands in `3000000–3999999`, and the generator must
refuse any id outside the two preview blocks.

## References

- [decisions/ADR-002-custom-content-isolation-and-ids.md](../../decisions/ADR-002-custom-content-isolation-and-ids.md)
- [specs/content-pipeline.md](../../specs/content-pipeline.md)
