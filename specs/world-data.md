# World data

## Purpose

Define the public catalog of world data served to the website: entities, spawn locations, freshness,
and the optional live spawn overlay. The decision is
[ADR-011](../decisions/ADR-011-world-data-and-content-verification.md).

## Scope

Exported JSON for items, NPCs, quests, gameobjects, spawn sets, coordinate inputs, freshness, and
the search index. Vendor, trainer, loot, condition, and SmartAI data stay in the content audit for
v1.

## Boundary

Owns the export artifact format and the public read contract. Does not own the extractor
implementation, the website markup, or the GM API transport contract. The site consumes this
contract; the audit consumes the same extractor but its report is owned by
[content-pipeline.md](content-pipeline.md).

## Contract

### Sources

Read-only, from `acore_world`:

- `creature_template`, `creature` — NPC definitions and spawns.
- `quest_template`, `quest_template_addon` — quests.
- `item_template` — items.
- `gameobject_template`, `gameobject` — objects and spawns.
- `creature_queststarter` / `creature_questender` — NPC quest links, with names.
- `gameobject_queststarter` / `gameobject_questender` — object quest links, with names.

The content audit additionally reads `npc_vendor`, `npc_trainer`, `trainer_spell`,
`creature_default_trainer`, `*_loot_template`, `conditions`, and `smart_scripts`. Those are not part
of the public catalog in v1.

The export runs with a read-only database user. It never writes to any database.
`acore_characters` is not read. Player data never leaves the server.

### Artifacts

One artifact per entity type, plus one spawn artifact per type:

```text
export/
  meta.json
  npc/{id}.json
  item/{id}.json
  quest/{id}.json
  object/{id}.json
  spawns/npc/{id}.json
  spawns/object/{id}.json
  search/{bucket}.json
```

v1 exports `npc`, `item`, `quest`, `object`, and spawn sets. Spell entities and item icons are v2:
both need DBC field maps that are not part of this contract yet. `object` has no `flags` column in
this schema, so the document carries `type`, `aiName`, and `scriptName` only.

`meta.json`:

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-11-14T10:00:00Z",
  "sourceDatabaseVersion": "<acore_world.version.db_version>",
  "counts": { "npc": 0, "item": 0, "quest": 0, "object": 0, "spell": 0, "spawns": 0, "parts": 0 },
  "buckets": 0,
  "durationSeconds": 0
}
```

Entity documents carry `schemaVersion` and `generatedAt`. Output is deterministic: stable key order,
stable array order, no volatile fields.

### Entity shape

Minimum fields per type. Additional fields may be added; removing or renaming one is a schema
version bump.

| Type | Required fields |
|------|-----------------|
| `npc` | `id`, `name`, `subname`, `level`, `maxLevel`, `rank`, `faction`, `npcFlags`, `questStarter`, `questEnder`, `vendor`, `trainer`, `aiName`, `scriptName` |
| `item` | `id`, `name`, `quality`, `itemLevel`, `requiredLevel`, `class`, `subclass`, `displayId`, `sellPrice` |
| `quest` | `id`, `title`, `level`, `minLevel`, `zone`, `sortCategory`, `type`, `objectives`, `starters`, `enders`, `prerequisites`, `startItem` |
| `object` | `id`, `name`, `type`, `aiName`, `scriptName` |

`starters` and `enders` reference `{ "kind": "creature" | "object", "id": 0, "name": "" }` so the site
can link without a second lookup.

### Spawn set

```json
{
  "entry": 1234,
  "kind": "npc",
  "schemaVersion": 1,
  "generatedAt": "2026-11-14T10:00:00Z",
  "points": [
    { "map": 0, "x": -8949.95, "y": -132.49, "z": 83.53,
      "orientation": 0.0, "spawnId": 0, "respawnSeconds": 300 }
  ]
}
```

- `points` is ordered by `map`, then `spawnId`.
- A set larger than 500 points is split by map into `spawns/{type}/{id}-{map}.json`. The canonical
  `spawns/{type}/{id}.json` then carries `{ "parts": ["spawns/npc/1234-0.json", ...] }` instead of
  `points`. A client follows `parts` when it is present.
- "In the database" is the only claim a spawn set makes. It is not a claim that the spawn is alive.

### Coordinate conversion

World coordinates to normalized map coordinates use per-map bounds, not zone boundaries. `Map.dbc`
does not carry bounds: `MapEntry` in `src/server/shared/DataStores/DBCStructure.h` has no bound
fields. The bounds come from a generated sidecar table produced from world map data, settled with the
exporter.

```text
u = (x - minX) / (maxX - minX)
v = (maxY - y) / (maxY - minY)
```

<!-- TODO: choose the bounds sidecar source and pin the exception list for maps with unusual bounds.
     Blocked for the public map page, not for the exported data. -->

`u` and `v` are in `[0, 1]`, origin top-left of the map image. The website applies the conversion;
the export provides raw world coordinates only.

<!-- TODO: choose the map imagery source. Options are client-derived minimap tiles, a licensed asset
     set, or a non-asset schematic. Blocked for the public map page, not for the exported data. -->

### Endpoints

Served by the website BFF, read-only, public zone:

| Endpoint | Returns |
|----------|---------|
| `GET /api/world/{type}/{id}` | entity document |
| `GET /api/world/{type}/{id}/spawns` | spawn set, or a map-keyed index when split |
| `GET /api/world/search?q=` | id, name, type; paged |
| `GET /api/world/spawn-state?map=&entry=` | live spawn state (deferred, see below) |

- `type` is one of `npc`, `item`, `quest`, `object`, `spell`. The literal routes `search` and
  `spawn-state` are reserved and take precedence over `{type}`.
- `limit` defaults to 20, maximum 100. The response carries a cursor when more results exist.
- Entity and spawn-set responses are cacheable: `ETag` from `schemaVersion`, `generatedAt`, and the
  request path.
- `spawn-state` is never cached and never blocks the page. If it fails, the page still renders the
  static spawn set and says the live state is unavailable.

### Live spawn state (deferred)

Not in the first public version; see ADR-011. The public site must not hold the GM API secret, so a
public overlay needs its own secretless read surface. Until then, live state is available only
through the private GM API path. When a public surface exists, `spawn-state` answers one question: is
this spawn alive right now on this map.

```json
{ "map": 0, "entry": 1234, "generatedAt": "2026-11-14T10:00:03Z", "state": "alive" | "dead" | "unknown" }
```

- `alive` means a living creature of that entry exists on that map.
- `dead` means at least one spawn exists and none is alive, typically a respawn timer.
- `unknown` means the worldserver could not answer, for example during startup or restart.
- The browser never calls the GM API. The admin BFF calls it with the shared secret over loopback,
  a private network, or TLS.

## Errors and edge cases

- Unknown id: `404` with the entity type and id, no stack trace, no SQL.
- Export older than the configured freshness threshold: serve it, and mark the page stale with the
  export timestamp.
- Worldserver unavailable, once the overlay exists: `spawn-state` returns `unknown`; static content
  is unaffected.
- A quest with no starter in the database is still a valid entity. Its page shows that no starter
  exists; that is an audit finding, not a page failure.
- An entity added by a database update appears only after the next export. Freshness metadata makes
  that visible.

## Security

- Public read only. No write endpoints.
- No player data, account data, GM data, audit data, or IP addresses in any artifact.
- No database credentials in artifacts or in page source. The public BFF never holds the GM API
  secret.
- The catalog is free and requires no login, per
  [ADR-011](../decisions/ADR-011-world-data-and-content-verification.md).
- Rate limiting applies to `search` and `spawn-state`; the export artifacts are static.

## Observability

- `generatedAt` and `sourceDatabaseVersion` in `meta.json` and on every page footer.
- Export duration and artifact counts logged by the export tool.
- Staleness tracked as a page state, not an error.

## References

- [ADR-011](../decisions/ADR-011-world-data-and-content-verification.md)
- [ADR-010](../decisions/ADR-010-website-as-visual-interface.md)
- [content-pipeline.md](content-pipeline.md)
- [architecture.md](architecture.md)
