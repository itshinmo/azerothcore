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
| Misc | `950000–959999` | text, conditions, other IDs |
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
| — | — | — | — | — | — |

No custom IDs are allocated yet.

## References

- [decisions/ADR-002-custom-content-isolation-and-ids.md](../../decisions/ADR-002-custom-content-isolation-and-ids.md)
- [specs/content-pipeline.md](../../specs/content-pipeline.md)
