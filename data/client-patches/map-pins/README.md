# World map pins

`patch-Z.MPQ` carries one small addon, `WorldMapPins`, that draws the pins the server actually
needs to advertise. Contract: [ADR-037](../../../decisions/ADR-037-world-map-pins.md).

## What is drawn

| Kind | Count | Source |
|------|-------|--------|
| Outdoor world bosses | 7 | `acore_world.creature` entries: Azuregos, Lethon, Taerar, Emeriss, Ysondre, Doom Lord Kazzak, Doomwalker |
| Warpweaver (transmogrifier) | 10 | `data/sql/custom/db_world/collections_npc_spawns.sql`, entry `910012` |
| Call Board | 15 | `data/sql/custom/db_world/call_boards.sql`, entry `930101` |
| Hub portals | one per room | `Spell_Arcane_Portal*` icons; Shattrath, Quel'Danas, Dalaran, Blasted Lands |
| Ship and zeppelin stations | one per cluster | 15 player routes in `acore_world.transports`; icons from `patch-I` |

Stock NPC categories are deliberately absent: no flight masters, innkeepers, battlemasters, meeting
stones or city leaders. Addons such as Questie cover those, and a wrong stock pin is worse than none.
Two closed exceptions stand beside the 7 world bosses, both approved on 2026-11-27: the hub portal
network and the player ship and zeppelin stations. A player needs them to plan travel and Questie does
not place the station pins accurately.

The portal rooms are the Shattrath City row (8 capital destinations), the Shattrath portal to the Isle
of Quel'Danas, the Dalaran Alliance enclave (5), the Dalaran Horde enclave (5) and one Blasted Lands
portal per capital (8). Portals draw one pin per room, not per portal object, so the tooltip lists
every destination once. Transport pins come from the 15 player routes; the two Icecrown gunships, the
Northrend turtles and Garvan's Reef stay out. Stations within about 120 yards on one map merge into
one pin listing every destination from that spot, and `Westguard Keep`/`Shattered Straits` share a
coordinate, so that route is one pin.

Pins show on their own zone map and on the continent map, at the exact spawn position. No stack
fan-out, no fake offsets.

## Tooltip

Each pin is a 24x24 button parented to `WorldMapFrame`, at the frame's own strata and frame level
plus 7, with the mouse enabled. That is the arrangement Questie uses in this client; HandyNotes uses
`+6`. A pin parented to `WorldMapButton` at `WORLDMAP_POI_FRAMELEVEL + 50` drew correctly but never
received a mouse event, which is why hover and click both failed in the 2026-11-27 playtest.

Hovering shows the pin's lines on `WorldMapTooltip`, the client's own map tooltip:

- boss: the boss name, then `<Classic world boss> - <zone>`;
- Warpweaver: the city, then `Warpweaver - Transmogrifier`;
- Call Board: the city or hub, then `Call Board - Custom quest board`;
- portal: the room name and every destination, one per line;
- station: the station name and `To <destination>`.

The city is the title because every capital has a Warpweaver and a Call Board 1 to 7 pixels apart on
the continent map, and only the top pin of a pair can be hovered there. The owner chose to keep all
20 pins self-describing rather than merge or offset them. Zone maps show both pins apart.

Hover also sets `WorldMapPOIFrame.allowBlobTooltip = false`, because otherwise
`WorldMapBlobFrame_OnUpdate` replaces the pin tooltip with the quest-blob tooltip under the cursor.
`OnLeave` and `HideAll` restore it, so closing the map while hovered does not leave it off.

Warpweaver uses `Interface\Icons\INV_NetherPortal`, a dark void portal that matches the ethereal
transmogrifier; the stock chest icon read as generic loot. The texture comes from
`Data/patch-I.mpq` (Reforged icon set), not a stock 3.3.5 archive; a client without `patch-I` shows
a placeholder for that one icon.

Portal pins use the stock `Spell_Arcane_Portal*` icons. Transport pins use
`INV_AllianceShipMount`/`INV_ShipMount` for boats and
`INV_HordeZeppelinMount`/`INV_ZeppelinMount` for zeppelins; those four come from `Data/patch-I.mpq`
too, so the same client caveat applies. A transport tooltip is always two lines: the station name,
then `To <destination>`. Vessel names are not shown.

Clicking forwards to `WorldMapButton_OnClick`, so the stock map ping still works.

`/wmp` (or `/worldmappins`) prints the pin count, the open map zone index and the name of the frame
under the cursor. Use it when a hover does not open the tooltip: it says whether a pin, the client
quest POI layer, or something else owns the mouse.

## Build

```bash
python3 data/client-patches/map-pins/build.py
python3 data/client-patches/map-pins/build.py --check
luajit data/client-patches/map-pins/tests/test_addon.lua
```

The build copies the addon, appends the FrameXML canary, applies the `Cooldown.lua` nil guard,
packs `patch-Z.MPQ`, verifies every entry, and writes `manifest.json`. Pin rows are currently static
in `src/WorldMapPins/WorldMapPins.lua`; the generator that replaces that table lands in its own
change, and ADR-037 rule 4 records why it exists.

Map fractions use the 3.3.5 rotated axes:

```text
mx = (yMax - worldY) / (yMax - yMin)
my = (xMax - worldX) / (xMax - xMin)
```

Zone bounds come from `WorldMapArea.dbc`. Dalaran is the exception: its `WorldMapArea` row has zero
bounds, so both Dalaran pins come from `DungeonMap.dbc` floor 27 (map 571), the city micro-map.

Silvermoon and the Exodar are the second exception. They sit on map 530 but display on the Eastern
Kingdoms and Kalimdor maps, so their **continent** fractions need the additive offset from
`WorldMapTransforms.dbc` before projection:

| Map 530 region | Offset X | Offset Y |
|----------------|----------|----------|
| `0` Eastern Kingdoms | `-2400` | `+2400` |
| `1` Kalimdor | `+10133.333` | `+17600` |

Their zone fractions never take the offset. Skipping it put the Silvermoon pair in the ocean north of
the Eastern Kingdoms and the Exodar pair under the `THE GREAT SEA` label, which is the bug the owner
reported on 2026-11-27.

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
| Built archive | `dist/patch-Z.MPQ`, 29,254 bytes | `a68263d4d7130d8bf5cc54ace894beae65ab2d987108baaba42de743633cccef` |

`manifest.json` carries the per-entry hashes and is the audit record; this table names the DBC
sources the fractions were computed from. The built archive row is the current checked-in pair;
a regeneration and rebuild rewrites both numbers, and `manifest.json` is then authoritative.

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

1. Login chat shows the patch-Z canary and the `WorldMapPins loaded ... (<n> pins)` line.
2. Stormwind zone map: Warpweaver and Call Board pins on their exact spots.
3. Hover each pin: the tooltip for its kind. Click: map ping.
4. Duskwood: Taerar. Westfall: no pins.
5. Dalaran city micro-map: Warpweaver and Call Board on their spots.
6. Continent maps: the pins for the kinds that belong there, including the Silvermoon and Exodar
   pairs on Eastern Kingdoms and Kalimdor, and the ship and zeppelin stations on the coast.
