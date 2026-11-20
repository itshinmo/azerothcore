# Custom ID registry

## When to use

Before creating any custom item, creature, quest, gameobject, spell, or map. Record the new ID here in
the same change.

## Reserved ranges

| Kind | Range | Notes |
|------|-------|-------|
| Items | `900000–909999` | includes mounts, cosmetics, tokens |
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
| 950110–950119 | Misc (POI) | city Warpweaver markers | `points_of_interest` rows behind the guard gossip options (`collections_guard_directions.sql`) | collections (ADR-020) | 2026-11-20 |
| 950120 | Misc (npc_text) | guard answer | shared gossip answer text in `collections_guard_directions.sql` | collections (ADR-020) | 2026-11-20 |

World content IDs are still unallocated. The RBAC rows live in `acore_auth`, not `acore_world`.

## References

- [decisions/ADR-002-custom-content-isolation-and-ids.md](../../decisions/ADR-002-custom-content-isolation-and-ids.md)
- [specs/content-pipeline.md](../../specs/content-pipeline.md)
