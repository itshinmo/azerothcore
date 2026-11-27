# World map pins

`patch-Z.MPQ` carries one small addon, `WorldMapPins`, that draws the pins the server actually
needs to advertise. Contract: [ADR-037](../../../decisions/ADR-037-world-map-pins.md).

## What is drawn

| Kind | Count | Source |
|------|-------|--------|
| Outdoor world bosses | 7 | `acore_world.creature` entries: Azuregos, Lethon, Taerar, Emeriss, Ysondre, Doom Lord Kazzak, Doomwalker |
| Warpweaver (transmogrifier) | 10 | `data/sql/custom/db_world/collections_npc_spawns.sql`, entry `910012` |
| Call Board | 15 | `data/sql/custom/db_world/call_boards.sql`, entry `930101` |

Stock NPC categories are deliberately absent: no flight masters, innkeepers, battlemasters,
meeting stones, portals or city leaders. Addons such as Questie cover those, and a wrong stock pin
is worse than none. The 7 world bosses are the one stock exception, approved on 2026-11-27.

Pins show on their own zone map and on the continent map, at the exact spawn position. No stack
fan-out, no fake offsets.

## Tooltip

Each pin is a 24x24 button parented to `WorldMapFrame`, at the frame's own strata and frame level
plus 7, with the mouse enabled. That is the arrangement Questie uses in this client; HandyNotes
uses `+6`. A pin parented to `WorldMapButton` at `WORLDMAP_POI_FRAMELEVEL + 50` drew correctly but
never received a mouse event, which is why hover and click both failed in the 2026-11-27 playtest.

Level 94 is deliberately below the client quest POI frame at 100. That frame is not mouse-enabled,
so it does not block the pin; only its child quest icons do, and a pin that lands exactly on a quest
icon is the rare case where the quest icon wins the mouse.

Hovering uses `WorldMapTooltip`, the client's own map tooltip. The first line is the subject, the
second names the service:

- boss: the boss name, then `<Classic world boss> - <zone>`;
- Warpweaver: the city, then `Warpweaver - Transmogrifier`;
- Call Board: the city or hub, then `Call Board - Custom quest board`.

The city goes in the title because of a known limitation. Every capital has a Warpweaver and a Call
Board 1 to 7 pixels apart on the continent map (Undercity 1.0 px, Stormwind 1.3 px, Thunder Bluff
2.1 px), and pins are 24 px, so only the top pin of a pair can be hovered there. The owner chose to
keep all 20 pins and make the reachable one self-describing rather than merge or offset them. Zone
maps show both pins apart.

Hover also sets `WorldMapPOIFrame.allowBlobTooltip = false`, because otherwise
`WorldMapBlobFrame_OnUpdate` replaces the pin tooltip with the quest-blob tooltip under the cursor.
Leaving restores it.

Warpweaver uses `Interface\Icons\INV_NetherPortal`, a dark void portal that matches the ethereal
transmogrifier; the stock chest icon read as generic loot. The texture comes from
`Data/patch-I.mpq` (Reforged icon set), not a stock 3.3.5 archive; a client without `patch-I` shows
a placeholder for that one icon.

Clicking forwards to `WorldMapButton_OnClick`, so the stock map ping still works.

`/wmp` (or `/worldmappins`) prints the pin count, the open map zone index and the name of the frame
under the cursor. Use it when a hover does not open the tooltip: it says whether a pin, the client
quest POI layer, or something else owns the mouse.

## Generated data

Pin rows are not edited by hand. `generate.py` reads the spawn coordinates from tracked SQL and the
map bounds from the client DBC, then writes one file per pin kind under `src/WorldMapPins/data/`:

| File | Source |
|------|--------|
| `zones.lua` | `AreaTable.dbc` names for the zones that hold a pin |
| `bosses.lua` | the seven outdoor world boss spawns |
| `services.lua` | `collections_npc_spawns.sql` and `call_boards.sql` |

`build.py --check` runs `generate.py --check` and fails when a committed data file is stale, so a
moved spawn cannot ship with an old position. A spawn move is: edit the tracked SQL, run
`generate.py`, rebuild.

## Build

```bash
python3 data/client-patches/map-pins/generate.py
python3 data/client-patches/map-pins/build.py
python3 data/client-patches/map-pins/build.py --check
luajit data/client-patches/map-pins/tests/test_addon.lua
python3 -m unittest discover -s data/client-patches/map-pins/tests -v
```

The build generates the pin data, copies the addon, appends the FrameXML canary, applies the
`Cooldown.lua` nil guard, packs `patch-Z.MPQ`, verifies every entry, and writes `manifest.json`.

Map fractions use the 3.3.5 rotated axes:

```text
mx = (yMax - worldY) / (yMax - yMin)
my = (xMax - worldX) / (xMax - xMin)
```

Zone bounds come from `WorldMapArea.dbc`. Two exceptions are handled by the generator:

- **Dalaran** has a `WorldMapArea` row with zero bounds, so its pins come from the `DungeonMap.dbc`
  row whose id matches the zone's floor (27, map 571), the city micro-map.
- **Silvermoon and the Exodar** show on the Eastern Kingdoms and Kalimdor maps but stand on map
  530, so their continent fraction applies the additive `WorldMapTransforms.dbc` offset before
  projecting: `(-2400, +2400)` for Eastern Kingdoms, `(+10133.333, +17600)` for Kalimdor. Zone
  fractions never take it. Skipping it is the ocean-pin bug the owner reported on 2026-11-27.

The generator finds a Call Board's zone by the `zoneId` column of the tracked SQL, not by the
coordinate: `WorldMapArea` bounds overlap, so a point alone is ambiguous (Feralas and Mulgore both
contain Emeriss). The ten Warpweaver rows carry `zoneId` 0, so their zones come from the reserved
GUID block in `WARPWEAVER_ZONES`; a Warpweaver GUID missing from that map fails the generator
instead of falling back to a neighbouring zone.

A boxed spawn row that cannot be parsed, or a row count that does not match, is an error. A
silently dropped pin would look fine on the map and still pass `--check`.

Continent index order is the client's, not the map id order: **1 Kalimdor, 2 Eastern Kingdoms,
3 Outland, 4 Northrend**, the `WorldMapArea` area-id-0 file order. Pins store that index. Mapping
1=Eastern Kingdoms draws both continents on the wrong map and puts pins in the ocean.

## Sources and hashes

| Input | Source | SHA256 |
|-------|--------|--------|
| Zone and continent pin fractions | `Data/patch-M.mpq` `WorldMapArea.dbc` | `c7361fae70d2f3136e98b8d19f86a594b3592a6ec3351e184eafb350db7d6503` |
| Dalaran pin fractions | `Data/patch-M.mpq` `DungeonMap.dbc` row 27 | `34beae04678c69cf536946217106d3e935d65d833dc86c59d120e8f335e756e9` |
| FrameXML canary | `Data/enUS/patch-enUS-3.MPQ` (source archive) | `e05b75b212cdda98f86beef35eb024aa1ff416a7164d08873c49b7ae1f3105c8` |
| Cooldown nil guard | `Data/enUS/locale-enUS.MPQ` (source archive) | `7b93af66d6f5bb0aaaed35202a376c5e2a75df0daea8e0c6c117ab2bfbde77b5` |
| Built archive | `dist/patch-Z.MPQ`, 31,148 bytes | `4c630fda4d373e91b58bcbdae0534dc444677026c103dab02e7ea3a31f2dbbeb` |

`manifest.json` carries the per-entry hashes and is the audit record; this table names the DBC
sources the fractions were computed from.

## Install and rollback

The owner installs; agents do not write to the live client.

```bash
# client closed
cp data/client-patches/map-pins/dist/patch-Z.MPQ ~/Games/wotlk-clean/Data/patch-Z.MPQ

# rollback
rm ~/Games/wotlk-clean/Data/patch-Z.MPQ
```

The archive also carries the `Interface\FrameXML\WorldMapFrame.lua` canary and the
`Cooldown.lua` nil guard. Removing `patch-Z` removes both.

## Test in the client

1. Login chat shows the patch-Z canary and `WorldMapPins loaded ... (32 pins)`.
2. Stormwind zone map: Warpweaver and Call Board pins on their exact spots.
3. Hover each pin: three-line tooltip. Click: map ping.
4. Duskwood: Taerar. Westfall: no pins.
5. Dalaran city micro-map: Warpweaver and Call Board on their spots.
6. Continent maps: Eastern Kingdoms 11, Kalimdor 14, Outland 5, Northrend 2.
