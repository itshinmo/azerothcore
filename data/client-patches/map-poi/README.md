# Map POI layer

Baked world-map markers for the project client. Ships in `dist/patch-Z.MPQ`; no user addon install.
Decision: [ADR-032](../../../decisions/ADR-032-map-poi-layer.md). Pipeline:
[ADR-027](../../../decisions/ADR-027-client-patch-pipeline.md),
[specs/client-patch.md](../../../specs/client-patch.md).

## What it draws

Generated from `poidata/snapshot.json` (a read-only harvest of `acore_world`) plus the client DBCs.
568 markers over the whole world:

| Kind | Count | Source | Hover text |
|---|---|---|---|
| Flight master | 155 | `creature_template.npcflag & 0x2000` | NPC name |
| Innkeeper | 124 | `npcflag & 0x10000` | NPC name |
| Battlemaster | 187 | `npcflag & 0x100000`, one per zone+name | NPC name |
| Meeting stone | 47 | `gameobject_template.type 23` | `Utgarde Keep (68-83)` |
| Portal | 43 | `gameobject_template.type 22`, name-filtered, instance maps dropped | destination |
| Warpweaver | 10 | creature entry `910012` | city |
| World boss | 2 | Doom Lord Kazzak, Doomwalker | boss name |

Ships and zeppelins are **not drawn in this slice**. Their dock coordinates cannot be derived from
the tables: `transports` stores only a route name, and `TransportAnimation.dbc` is keyed by a
different id space than `transports.entry`. A marker at a guessed dock would be worse than none.
The follow-up is to harvest dock positions from the named dock gameobjects in the world (for example
the zeppelin towers, which carry the route in their name) or from an in-game pass.

Faction tint: alliance blue, horde red, shared/neutral gold, applied with `SetVertexColor` on one
stock icon per kind.

Meeting stone level ranges come from `LFGDungeons.dbc`: a stone's `data2` is the dungeon's areaID,
that area's map is the instance map, and the LFD row for that map carries min/max level.

The addon still exposes `SetWorldBoss`, `SetCrowsCache` and `SetDynamicMapPOI` for later dynamic data.
- **Outlaw** dynamic marker (client visual contract only; no PvP server module): exact marker in the
  same zone, coarse marker on the same continent, hidden in instances/BGs/arenas, and a kill-feed
  chat line. The wire requires a server-issued session token; without `AUTH`, Outlaw markers stay
  off. Protocol below.
- **Red overlay** on selected end-game PvP zones: Wintergrasp, Strand of the Ancients, Isle of
  Conquest.
- **Canary**: a login message from the overridden `Interface\FrameXML\WorldMapFrame.lua` proves
  `Data/patch-Z.MPQ` wins the load order.

Icons are stock client textures (`INV_Misc_Map_01`, `INV_Misc_Coin_01`, `UI-RaidTargetingIcon_8`,
`INV_Misc_Bag_10`, `INV_Misc_Bandana_03` for Outlaw); no custom BLP.

License: the packed files are the stock 3.3.5a client assets from the owner's own licensed install.
The addon Lua and static data are project-authored.

## Contents

| Entry | Purpose |
|-------|---------|
| `Interface\AddOns\ServerMapPOI\ServerMapPOI.toc` | Addon manifest. |
| `Interface\AddOns\ServerMapPOI\ServerMapPOI.lua` | Map hooks, pins, tooltip, red overlay, dynamic hooks, Outlaw protocol. |
| `Interface\AddOns\ServerMapPOI\Data.lua` | Generated zone bounds, POI positions, red-zone list. |
| `Interface\FrameXML\WorldMapFrame.lua` | Whole-file copy of the highest-priority source plus the login canary. |

## Sources and hashes

Recorded in `manifest.json`; the build re-resolves them.

| Source | Value |
|--------|-------|
| Canary source archive | `Data/enUS/patch-enUS-3.MPQ` |
| Canary source file | `Interface\FrameXML\WorldMapFrame.lua` |
| Canary source SHA256 | `e05b75b212cdda98f86beef35eb024aa1ff416a7164d08873c49b7ae1f3105c8` |
| Canary output SHA256 | `8bac9f7dccf659fff5891d22b0a5fd401f3495bb70a10a0ce980f1095bda7fe1` |
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

Current output:

Current output: see `manifest.json`. The archive changes whenever the snapshot or the DBCs change.

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
   - `ServerMapPOI loaded from patch-Z.MPQ (24 static markers, Outlaw protocol v2 token required).`
   A missing first line means the patch lost the load order; a missing second line means the MPQ
   addon did not load or is disabled.
2. Open the map in Stormwind (or `/run SetMapZoom(0, 1519)`). Expect the Warpweaver marker near
   `64.7, 72.0`, PvP honor vendors near `75.0, 67.3`, and battlemasters near `82.7, 34.0`.
3. Repeat in Ironforge, Darnassus, The Exodar, Orgrimmar, Undercity, Thunder Bluff, Silvermoon, and
   Shattrath. Positions are in `Data.lua` as percentages.
4. Dalaran: the Warpweaver marker is near `39.8, 40.5` (Simply Enchanting, beside Enchanter
   Nalthanis) and the arena vendors near `58.4, 58.0`. The arena-vendor pair is still the only
   imported approximation.
5. Hellfire Peninsula: a skull at Doom Lord Kazzak. Shadowmoon Valley: a skull at Doomwalker.
6. Wintergrasp, Strand of the Ancients, and Isle of Conquest: the map gets a translucent red overlay.
7. Hover each marker: tooltip shows the label and note. Click: chat echoes the label.
8. Close the map. Markers are hidden; no map work continues. Reopen; markers are back.
9. `/reload`. No Lua error dialog; both login lines repeat.
10. Outlaw markers need a server module and are not shipped. The client contract is tested offline:
    `luajit data/client-patches/map-poi/tests/test_addon.lua` runs the fake position, same-zone
    exact marker, same-continent coarse marker, other-continent hide, instance hide, kill line, and
    clear.
11. Roll back and restart: both lines disappear and the map returns to stock.

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
- `zone`: the client's `GetCurrentMapZone()` value (AreaTable ID, for example 1519 Stormwind City).
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
