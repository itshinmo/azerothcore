# World map pins

`patch-Z.MPQ` carries one small addon, `WorldMapPins`, that draws the pins the server actually
needs to advertise. Contract: [ADR-037](../../../decisions/ADR-037-world-map-pins.md).

## What is drawn

| Kind | Count | Source |
|------|-------|--------|
| Outdoor world bosses | 7 | `acore_world.creature` entries: Azuregos, Lethon, Taerar, Emeriss, Ysondre, Doom Lord Kazzak, Doomwalker |
| Warpweaver (transmogrifier) | 10 | `data/sql/custom/db_world/collections_npc_spawns.sql`, entry `910012` |
| Call Board | 15 | `data/sql/custom/db_world/call_boards.sql`, entry `930101` |
| Hub portals | 12 | one pin per room: Shattrath row, Quel'Danas, two Dalaran enclaves, 8 capital Blasted Lands portals; stock `Spell_Arcane_Portal*` icons |
| Ship and zeppelin stations | 29 | 15 player routes in `acore_world.transports`, one pin per station node; `INV_ShipMount` / `INV_ZeppelinMount` from `patch-I` |

Stock NPC categories are deliberately absent: no flight masters, innkeepers, battlemasters, meeting
stones or city leaders. Addons such as Questie cover those, and a wrong stock pin is worse than none.
Two closed exceptions stand beside the 7 world bosses, both approved on 2026-11-27: the hub portal
network and the player ship and zeppelin stations. A player needs them to plan travel and Questie does
not place the station pins accurately.

The portal rooms are the Shattrath City row (8 capital destinations), the Shattrath portal to the Isle
of Quel'Danas, the Dalaran Silver Enclave (5), the Dalaran Sunreaver's Sanctuary (5) and one Blasted
Lands portal per capital (8). The Blasted Lands rooms and the Quel'Danas room are named after the
destination they serve, so their tooltips read `Portal - Blasted Lands` with no `To` line. Portals draw one pin per room, at the centroid of that room's portal
objects, not per portal object: Shattrath's eight portals span about 145 by 103 yards, so per-object
pins would overlap and only the top tooltip would ever open. Each room uses a faction icon: Stormwind
for the Alliance enclave, Orgrimmar for the Horde one, its own city icon for each capital's Blasted
Lands portal, and `Spell_Arcane_PortalShattrath` for both Shattrath pins.

Transport pins come from the 15 player routes; the two Icecrown gunships, the two Northrend turtles
and Garvan's Reef stay out. There is **one pin per station node and no distance merging**: the owner
wants every node visible, so Orgrimmar shows four, Undercity three, Grom'gol two and Auberdine three.
The only collapse is the exact-duplicate node of the Westguard Keep route, whose two stops share one
coordinate; that pin is titled `Westguard Keep` and points at `Shattered Straits`.

Stacked pins are a known limitation. On a continent map a capital carries three service pins
(Warpweaver, Call Board, Blasted Lands portal) plus its station pins, all within a few pixels, so only
the top pin of each stack can be hovered there. Orgrimmar, Undercity and Grom'gol add their transport
nodes to the same stack. Zone maps separate most of them. Every tooltip title names the place and
service, so the reachable pin is still identifiable; this is the same rule the owner chose for the
Warpweaver and Call Board pairs.

Pins show on their own zone map, on their city's region zone map, and on the continent map, at the
exact spawn position. No stack fan-out, no fake offsets.

A city's own `WorldMapArea` is a micro-map: the Thunder Bluff pins store zone 1638, so opening
Mulgore (215) matched nothing and the region map was empty. Each serviced capital has one curated
parent zone, attached to its pins at generation time as a `zones` list, so the addon does no lookup.
Orgrimmar's parent is Durotar even though half its rectangle overlaps; its auction house stands on
Durotar's eastern edge. Dalaran is its own micro-map inside Crystalsong Forest and deliberately has
no parent, or its pins would draw twice.

The region rectangle is several times the city's, so each pin carries a second fraction pair
(`px`/`py`) projected on the parent's bounds, and the addon picks that pair when the parent is the
displayed zone. Reusing `mx`/`my` there drew every city pin hundreds of pixels off its region map,
in the sea. The generator rejects a fraction outside 3% of the rectangle, which is how Orgrimmar's
auction house (just past Durotar's eastern edge) stays allowed. That tolerance is a proximity
check, not a parent check: neighbouring zones contain the pins too. The curated table is
therefore verified by a coverage rule — the parent covers the most of the city's rectangle —
which decides seven of the nine uniquely. Thunder Bluff and Shattrath tie with a neighbour, and no
DBC field breaks the tie, so those two picks are editorial and recorded in `TIE_BREAKS`. The Orgrimmar Warpweaver stores `py = -0.0243`
and draws about 16 pixels above Durotar's top edge, over the frame border; moving it would mean
inventing a position the spawn does not have.

## Tooltip

Each pin is a 24x24 button parented to `WorldMapFrame`, at the frame's own strata and frame level
plus 8, with the mouse enabled. Questie uses `+7` for its own pins and HandyNotes `+6`, so one level
higher means our tooltip and click survive every addon load order. The cost is that our 24x24 button
covers a Questie pin within 24 pixels of it. A pin parented to `WorldMapButton` at
`WORLDMAP_POI_FRAMELEVEL + 50` drew correctly but never received a mouse event, which is why hover
and click both failed in the 2026-11-27 playtest.

Pin offsets come from the map's live screen rectangle, never from a scale constant. `WorldMapButton`
and `WorldMapDetailFrame` are siblings under `WorldMapFrame` in the shipped `WorldMapFrame.xml`, and
the client scales each of them independently: `1.0` full map, `0.691` quest view, `0.573` windowed.
The client's own `GetLeft`/`GetTop` already divide by the frame's own effective scale, so
subtracting a button rect from a frame rect mixes two unit spaces; `MapRect()` scales each corner to
screen pixels and divides once. Live rects also follow a third-party addon that resizes the map.

Pins are re-placed on every path that can move the map, not only on `WorldMapFrame_Update`: the
objectives checkbox goes through `WorldMapFrame_DisplayQuests` and the size toggle through
`WorldMap_ToggleSizeUp`/`Down`, and neither calls `Update`. Hooking only `Update` left the pins at
the previous view's offsets, which is the shift the owner saw. Each handler runs inside `pcall` and
reports one line per failing site, so an addon erroring on the same frames cannot kill the layer.

Hovering shows the pin's lines on `WorldMapTooltip`, the client's own map tooltip:

- boss: the boss name, then `<Classic world boss> - <zone>`;
- Warpweaver: the city, then `Warpweaver - Transmogrifier`;
- Call Board: the city or hub, then `Call Board - Custom quest board`;
- portal: the city, the room, then every destination as `To <city>`. A room named after its
  own destination reads `Portal - Blasted Lands` and lists nothing, so the destination is not said
  twice;
- station: the station name, then `To <destination>`, one line per route at that node. Ship pins use
  `INV_ShipMount`, zeppelin pins `INV_ZeppelinMount`, both from `Data/patch-I.mpq`.

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

Portal pins use the stock `Spell_Arcane_Portal*` icons, one per room. Transport pins use
`INV_ShipMount` for every boat and `INV_ZeppelinMount` for every zeppelin; both come from
`Data/patch-I.mpq`, so the same client caveat applies. A transport tooltip is the station name and
then `To <destination>`. Vessel names are not shown.

Clicking forwards to `WorldMapButton_OnClick`, so the stock map ping still works.

`/wmp` (or `/worldmappins`) prints the pin count, the open map zone index, the pin level offset, the
map's screen rectangle, the effective scale, and the frame under the cursor. Use it when a hover does
not open the tooltip: it says whether a pin, the client quest POI layer, or something else owns the
mouse. A wrong rectangle or a surprising scale is the signature of an addon resizing the map; a
"handlers that failed" line names the site that a third-party addon broke.

## Generated data

Pin rows are not edited by hand. `generate.py` reads the spawn coordinates from tracked SQL and the
map bounds from the client DBC, then writes one file per pin kind under `src/WorldMapPins/data/`:

| File | Source |
|------|--------|
| `zones.lua` | `AreaTable.dbc` names for the zones that hold a pin, including each city's parent zone |
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
| Zone and continent pin fractions | `Data/patch-M.mpq` `WorldMapArea.dbc` | `90e1ec678c8226c76f4dd9f7904f05a4cb0a58c8b4d386719b24949bd55925bb` |
| Dalaran pin fractions | `Data/patch-M.mpq` `DungeonMap.dbc` row 27 | `aa31db35a2266694d8318c410712a18540d86469e3d6134eb648a1d9694f21f5` |
| FrameXML canary | `Data/enUS/patch-enUS-3.MPQ` (source archive) | `e05b75b212cdda98f86beef35eb024aa1ff416a7164d08873c49b7ae1f3105c8` |
| Cooldown nil guard | `Data/enUS/locale-enUS.MPQ` (source archive) | `7b93af66d6f5bb0aaaed35202a376c5e2a75df0daea8e0c6c117ab2bfbde77b5` |
| Built archive | `dist/patch-Z.MPQ`, 38,131 bytes | `f86b3f25cabd11504f99cf431cd9d11d97bd1b788a4c8d982b09e91d3b00ca18` |

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
