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
| Items | `2000000–2999999` | transmog preview copies, id = `2000000 + source_entry`; real on `local-server-setup`, not yet on this branch |
| Items | `3000000–3999999` | preview copies of seven-digit source entries (same formula); reserved, unused today |
| Creatures | `910000–919999` | templates and spawns use different keys |
| Quests | `920000–929999` | includes chain addon rows |
| GameObjects | `930000–939999` | templates and spawns |
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

World content IDs are otherwise unallocated. The RBAC rows live in `acore_auth`, not `acore_world`.
The Mythic+ block starts at `1100000` so it does not overlap registered creature `1000003` or
npc_text `1000004`. Preview items at `2000000–2999999` are real on `local-server-setup` (ADR-026
revision, `transmog_preview_items.sql`); this branch base predates that merge, so the registry does
not allocate that range. Preview ids are `2000000 + source_entry`, so a source at `1000000` or above
would land in `3000000–3999999`; that block is reserved for seven-digit sources and the generator
must refuse any id outside the two preview blocks.

## References

- [decisions/ADR-002-custom-content-isolation-and-ids.md](../../decisions/ADR-002-custom-content-isolation-and-ids.md)
- [specs/content-pipeline.md](../../specs/content-pipeline.md)
