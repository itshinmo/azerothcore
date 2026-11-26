# Map POI layer

Baked world-map markers for the project client. Ships in `dist/patch-Z.MPQ`; no user addon install.
Decision: [ADR-032](../../../decisions/ADR-032-map-poi-layer.md). Pipeline:
[ADR-027](../../../decisions/ADR-027-client-patch-pipeline.md),
[specs/client-patch.md](../../../specs/client-patch.md).

## What it draws

Generated from `poidata/snapshot.json` (a read-only harvest of `acore_world`), the client DBCs, and a
short static list for the hand-placed content. 583 markers over the whole world:

| Kind | Count | Source | Hover text |
|---|---|---|---|
| Flight master | 155 | `creature_template.npcflag & 0x2000` | NPC name |
| Innkeeper | 124 | `npcflag & 0x10000` | NPC name |
| Battlemaster | 187 | `npcflag & 0x100000`, one per zone+name | NPC name |
| Meeting stone | 47 | `gameobject_template.type 23` | `Utgarde Keep (68-83)` |
| Portal | 43 | `gameobject_template.type 22`, name-filtered, instance maps dropped | destination |
| Warpweaver | 10 | creature entry `910012` | city |
| World boss | 2 | Doom Lord Kazzak, Doomwalker | boss name |
| Call board | 15 | `data/sql/custom/db_world/call_boards.sql`; AWE/acore-data placement | faction call board |

The 15 call boards are world-database rows, not client rows: the patch only draws their markers. They
are stock Wanted Board objects (entry `930101`, spawn GUIDs `5714521-5714535`) near the innkeepers;
the objectives engine attaches their menu in a later slice.

Ships and zeppelins are **not drawn in this slice**. Their dock coordinates cannot be derived from
the tables: `transports` stores only a route name, and `TransportAnimation.dbc` is keyed by a
different id space than `transports.entry`. A marker at a guessed dock would be worse than none.
The follow-up is to harvest dock positions from the named dock gameobjects in the world (for example
the zeppelin towers, which carry the route in their name) or from an in-game pass.

Faction tint: alliance blue, horde red, shared/neutral gold, applied with `SetVertexColor` on one
stock icon per kind.

Meeting stone level ranges come from `LFGDungeons.dbc`, keyed by the dungeon's own area name: a
stone's `data2` is the dungeon areaID and the area's name is the dungeon name. Keying by map
collapsed the four Hellfire Citadel wings and let holiday bosses (Coren Direbrew, Headless Horseman,
Crown Chemical Co.) win the name.

The map layer draws only on zone maps. On the continent map `GetCurrentMapZone()` is 0, and every
static pin is hidden; a zone-relative coordinate drawn over the continent texture is the
"markers in the ocean" bug. The red overlay and the Outlaw exact-zone mode use the same guard.

Goldshire has no flight master in 3.3.5: the flight point was added in Cataclysm (4.0.3a). Elwynn
shows Innkeeper Farley and the arena battlemaster; that is authentic, not a missing marker.

A player running upstream Questie sees its flight master, innkeeper and meeting-stone pins as well,
because Questie draws them by default. Double pins are accepted; the player can disable Questie's
townfolk POIs. The native layer adds no suppression code. The future branded Questie build is where
the overlap is resolved.

The addon still exposes `SetWorldBoss`, `SetCrowsCache` and `SetDynamicMapPOI` for later dynamic data.
- **Outlaw** dynamic marker (client visual contract only; no PvP server module): exact marker in the
  same zone, coarse marker on the same continent, hidden in instances/BGs/arenas, and a kill-feed
  chat line. The wire requires a server-issued session token; without `AUTH`, Outlaw markers stay
  off. Protocol below.
- **Red overlay** on selected end-game PvP zones: Wintergrasp, Strand of the Ancients, Isle of
  Conquest.
- **Canary**: a login message from the overridden `Interface\FrameXML\WorldMapFrame.lua` proves
  `Data/patch-Z.MPQ` wins the load order.

Icons are the stock tracking glyphs Questie uses (`Interface\Minimap\Tracking\FlightMaster`,
`Innkeeper`, `Battlemaster`) at 12 px. Meeting stones use Questie's `Icons/mstone.blp` (MIT, from
Shagu's pfQuest; SHA256 `847bb9d2a81e4f356b87c0ae014ce7aa0e8613597b062ff07242b4021b6ec8fc`); call
boards use a stock scroll icon. No other custom BLP.

License: the packed files are the stock 3.3.5a client assets from the owner's own licensed install,
except `mstone.blp`, which is Questie's MIT-licensed icon (see above). The addon Lua and static data
are project-authored.

## Contents

| Entry | Purpose |
|-------|---------|
| `Interface\AddOns\ServerMapPOI\ServerMapPOI.toc` | Addon manifest. |
| `Interface\AddOns\ServerMapPOI\ServerMapPOI.lua` | Map hooks, pins, tooltip, red overlay, dynamic hooks, Outlaw protocol. |
| `Interface\AddOns\ServerMapPOI\Data.lua` | Generated zone bounds, POI positions, red-zone list. |
| `Interface\AddOns\ServerMapPOI\mstone.blp` | Questie MIT meeting-stone icon. |
| `Interface\FrameXML\WorldMapFrame.lua` | Whole-file copy of the highest-priority source plus the login canary. |
| `Interface\FrameXML\Cooldown.lua` | Whole-file copy with the nil-safe `CooldownFrame_SetTimer`. |

## Sources and hashes

Recorded in `manifest.json`; the build re-resolves them.

| Source | Value |
|--------|-------|
| Canary source archive | `Data/enUS/patch-enUS-3.MPQ` |
| Canary source file | `Interface\FrameXML\WorldMapFrame.lua` |
| Canary source SHA256 | `e05b75b212cdda98f86beef35eb024aa1ff416a7164d08873c49b7ae1f3105c8` |
| Canary output SHA256 | `8bac9f7dccf659fff5891d22b0a5fd401f3495bb70a10a0ce980f1095bda7fe1` |
| Cooldown source archive | `Data/enUS/locale-enUS.MPQ` |
| Cooldown source file | `Interface\FrameXML\Cooldown.lua` |
| Cooldown source SHA256 | `7b93af66d6f5bb0aaaed35202a376c5e2a75df0daea8e0c6c117ab2bfbde77b5` |
| Cooldown output SHA256 | `c118ae3225f735e18b07191beb73d432359cfd63b7e2637e83daac5a98724a52` |
| Archive SHA256 | `a3ffc8d6c22f5bc29b5e4e4e9dee8189b31a0727b244692d4cb5ca4de7c2f7d5` (63,175 bytes, 6 files) |
| `WorldMapArea.dbc` source | `Data/patch-M.mpq` |
| `WorldMapArea.dbc` SHA256 | `c7361fae70d2f3136e98b8d19f86a594b3592a6ec3351e184eafb350db7d6503` |
| `DungeonMap.dbc` source | `Data/patch-M.mpq` |
| `DungeonMap.dbc` SHA256 | `34beae04678c69cf536946217106d3e935d65d833dc86c59d120e8f335e756e9` |
| Spawn snapshot | `acore_world` creatures, gameobjects and transports, 2026-11-26 |

The Warpweaver snapshot uses the live `creature` table. The Dalaran row and
`data/sql/custom/db_world/collections_npc_spawns.sql` now agree on `5842.8, 721.8` in Simply
Enchanting. The Dalaran micro-map coordinate is derived from that spawn
(`DungeonMap.dbc` floor 27), so the marker follows a future spawn move after regeneration.

## Build

```bash
export STORMLIB=/opt/homebrew/lib/libstorm.dylib   # only when needed
python3 data/client-patches/map-poi/build.py
python3 data/client-patches/map-poi/build.py --check
```

The build regenerates `src/ServerMapPOI/Data.lua` from the snapshot and the client DBCs, copies the
addon, appends the canary to the highest-priority `WorldMapFrame.lua` below `patch-Z`, packs MPQ v1
with listfile/attributes/zlib, verifies every entry, and writes `manifest.json`.

Refresh the spawn data after a move (the only step that needs MySQL; it never writes):

```bash
export POI_DB_PASSWORD='...'   # never on the command line: ps and shell history expose it
python3 data/client-patches/map-poi/harvest_poi_data.py --user acore
```

Offline addon smoke test (map API mock, no client):

```bash
luajit data/client-patches/map-poi/tests/test_addon.lua
```

Current output: 583 markers; the archive hash and every source hash are in `manifest.json`. The
archive changes whenever the snapshot, the DBCs, the addon, or the Cooldown source changes.

A content change changes the archive hash. Unchanged sources rebuild byte-identically because the
build pins entry times; regenerate the manifest and commit both when the content changes.

## Install

Client closed. Back up nothing; rollback is deleting the file.

```bash
cp data/client-patches/map-poi/dist/patch-Z.MPQ ~/Games/wotlk-clean/Data/patch-Z.MPQ
```

Prove the load order before or after install:

```bash
python3 tools/client-patch/client_patch.py which \
  ~/Games/wotlk-clean/Data 'Interface\FrameXML\WorldMapFrame.lua'
```

The winner must be `Data/patch-Z.MPQ` after install.

## In-client test steps

1. Start the client and log in. Expect two chat lines:
   - `[client-patch] patch-Z.MPQ canary active: WorldMapFrame.lua loaded from patch-Z.`
   - `ServerMapPOI loaded from patch-Z.MPQ (583 static markers, Outlaw protocol v2 token required).`
   A missing first line means the patch lost the load order; a missing second line means the MPQ
   addon did not load or is disabled.
2. Stormwind zone map: 23 pins (flight master, innkeeper, battlemasters, meeting stone, two portals,
   Warpweaver, call board). The icons are 12 px tracking glyphs, not squares.
3. Check the other capitals and Shattrath. Alliance pins tint blue, horde red, shared gold; no marker
   from another zone.
4. Dalaran shows its innkeepers, flight master, portals, Warpweaver and call board.
5. Hellfire Peninsula: a skull at Doom Lord Kazzak. Shadowmoon Valley: Doomwalker.
6. Call boards: one in each faction capital, Shattrath, Dalaran, Booty Bay, Gadgetzan, Everlook,
   Area 52 and Ratchet. Hover the board and the POI; the board is inert until the objectives slice.
7. Red overlay on Wintergrasp, Strand of the Ancients and Isle of Conquest.
8. Continent map: no static pins anywhere on the continent texture.
9. Elwynn: Innkeeper Farley and the arena battlemaster; no flight master (3.3.5 has none).
10. Hover and click a pin; close and reopen the map; `/reload`; no Lua error.
11. Cooldown: track a quest item or trigger the Call of Water path; no `Cooldown.lua` error.
12. Outlaw markers need a server module and are not shipped. The offline test covers the contract.
13. Roll back and restart: both chat lines disappear and the map returns to stock.

Full checklist: [2026-11-26-playtest-round-2.md](../../../runbook/audits/2026-11-26-playtest-round-2.md).

## Outlaw marker protocol

This is the client-patch visual contract. The PvP module that would send these messages is **not
implemented**; no server code, SQL, or tick work is added.

Transport: server-sent `CHAT_MSG_ADDON` (`SMSG_MESSAGECHAT` type ADDON), prefix `SMPOI`,
tab-separated, version `2`. The server sets the channel (for example `ZONE`); the addon ignores it.
Keep each payload under the 255-byte addon-message limit.

| Action | Payload |
|--------|---------|
| `AUTH` | `2<TAB>AUTH<TAB>token` |
| `OUTLAW` | `2<TAB>OUTLAW<TAB>token<TAB>killer<TAB>victim<TAB>continent<TAB>zone<TAB>zoneName<TAB>subzone<TAB>mapX<TAB>mapY<TAB>continentX<TAB>continentY<TAB>ttl` |
| `CLEAR` | `2<TAB>CLEAR<TAB>token<TAB>killer` |
| `KILL` | `2<TAB>KILL<TAB>token<TAB>killer<TAB>victim<TAB>zone<TAB>subzone` |

Fields:

- `token`: server-issued per-session token, 8-128 characters, no tabs. `AUTH` sets it; every
  `OUTLAW`, `CLEAR` and `KILL` must carry the same value or the addon ignores the message.
- `killer`, `victim`: character names, no tabs.
- `continent`: the client's `GetCurrentMapContinent()` value (1 Eastern Kingdoms, 2 Kalimdor,
  3 Outland, 4 Northrend).
- `zone`: the AreaTable zone id (for example 1519 Stormwind City). The client matches it against
  `GetCurrentMapAreaID()`; `GetCurrentMapZone()` returns an index, not this id.
- `zoneName`, `subzone`: display strings for the tooltip; `subzone` is the finer location.
- `mapX`, `mapY`: exact zone-map coordinates, 0..1, top-left origin. Sent only to players in the
  same zone.
- `continentX`, `continentY`: coarse continent-map coordinates, 0..1. Sent only to players on the
  same continent in a different zone.
- `ttl`: seconds before the client treats the marker as stale; default 15.

Server rules (future module):

- Send `AUTH` once per session, before any `OUTLAW`. Rotate the token on relogin or reconnect; the
  client clears old markers when the token changes.
- Send at most one position per outlaw every **5 seconds** (`ns.Outlaw.updateSeconds`), on change or
  as a heartbeat. Never broadcast per tick.
- Same zone: exact `mapX`/`mapY`. Same continent, other zone: coarse `continentX`/`continentY` only.
  Other continent: send nothing and never send exact coordinates.
- Send `CLEAR` on death, zone change, or flag loss. The client also expires stale markers after
  `ttl` seconds on the next map refresh.
- Instances, battlegrounds, and arenas: send nothing; the client hides Outlaw markers whenever
  `IsInInstance()` is true.
- v1 limitation: no PvP module issues `AUTH` yet, so Outlaw markers are off. Until it does, the
  client-side token stops casual spoofed `SMPOI` messages only. It is **not** a security boundary:
  a modified client or addon can call the Lua API directly. The server must still validate every
  kill and position; never trust a client-supplied outlaw marker for gameplay.
- `KILL` is an announcement, not a position. Chat format:
  `[OUTLAW] <killer> killed <victim> in <zone> (<subzone>).` The addon prints the line and exposes
  `FormatOutlawKill`/`ParseOutlawKill`.

Client API: `SetOutlaw(id, data)`, `ClearOutlaw(id)`, `ClearOutlaws()`, `GetOutlaw(id)`,
`HandleAddonMessage(prefix, message, channel, sender)`. `SetOutlaw` also requires
`data.token == ns.Frame.outlawToken`; direct API callers must authenticate first. The client stores
messages on `CHAT_MSG_ADDON` and redraws only on map update/show; there is no `OnUpdate` loop.

Fixture: `tests/fixtures/outlaw.lua` contains a fake position, the `OUTLAW`/`CLEAR`/`KILL` payloads,
and the expected chat line, plus `AUTH` and a wrong-token spoof. `tests/test_addon.lua` asserts the
pre-AUTH rejection, wrong-token rejection, exact marker, coarse marker, other-continent and instance
hides, kill line, clear, and stale-pin release.

## Rollback

```bash
rm ~/Games/wotlk-clean/Data/patch-Z.MPQ
```

No server data changes, no DBC change, no cache purge.

## Known limits

- Static positions drift after a spawn move. Regenerate `Data.lua` and rebuild.
- Dalaran uses a `DungeonMap` micro-map; the Warpweaver follows the SQL spawn, and only the
  arena-vendor pair is an imported approximation until verified.
- English client only. The root `patch-Z.MPQ` does not outrank locale patches on Russian/Chinese
  clients.
- The addon is visible in the client addon list; it is not a user-facing feature toggle.
- World-boss/Crow's Cache data is baked or set by a future server message; v1 has hooks only.
- Outlaw markers need a future PvP server module; the client contract and fixture ship now.

## Performance

The addon runs on map update/show, not per frame. Pins and icon textures are created once and reused;
the overlay is a single texture. The server does no work for this layer.
