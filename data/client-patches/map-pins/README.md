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

Each pin is a 24x24 button at `WORLDMAP_POI_FRAMELEVEL + 50`, above the client landmark buttons
(level 91) and the quest POI layer (level 100), with the mouse enabled. Hovering shows three lines:

- boss: name, `Classic world boss` or `The Burning Crusade world boss`, zone;
- Warpweaver: `Warpweaver`, `Transmogrifier`, city;
- Call Board: `Call Board`, `Custom quest board`, city or hub.

Warpweaver uses `Interface\Icons\INV_NetherPortal`, a dark void portal that matches the ethereal
transmogrifier; the stock chest icon read as generic loot. The texture comes from
`Data/patch-I.mpq` (Reforged icon set), not a stock 3.3.5 archive; a client without `patch-I` shows
a placeholder for that one icon.

Clicking forwards to `WorldMapButton_OnClick`, so the stock map ping still works.

## Build

```bash
python3 data/client-patches/map-pins/build.py
python3 data/client-patches/map-pins/build.py --check
luajit data/client-patches/map-pins/tests/test_addon.lua
```

The build copies the addon, appends the FrameXML canary, applies the `Cooldown.lua` nil guard,
packs `patch-Z.MPQ`, verifies every entry, and writes `manifest.json`. Pin data is static and lives
in `src/WorldMapPins/WorldMapPins.lua`; recompute it if a spawn moves.

Map fractions use the 3.3.5 rotated axes:

```text
mx = (yMax - worldY) / (yMax - yMin)
my = (xMax - worldX) / (xMax - xMin)
```

Zone bounds come from `WorldMapArea.dbc`. Dalaran is the exception: its `WorldMapArea` row has zero
bounds, so both Dalaran pins come from `DungeonMap.dbc` floor 27 (map 571), the city micro-map.
Silvermoon and the Exodar use `DisplayMapID` (Eastern Kingdoms and Kalimdor), not their `MapID`
(530).

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
| Built archive | `dist/patch-Z.MPQ`, 27,923 bytes | `c4088d412e9722cafec75d0ec79ed56fe2c5f581a017f34b2f3ff2c8b1c3c643` |

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
