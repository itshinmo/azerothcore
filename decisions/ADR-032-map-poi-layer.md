# ADR-032 — Map POI layer: baked addon, stock icons, red PvP overlay

- Status: accepted
- Date: 2026-11-23
- Related: [ADR-027](ADR-027-client-patch-pipeline.md),
  [ADR-020](ADR-020-collections-transmog-stack.md),
  [ADR-023](ADR-023-cross-faction-social-layer.md),
  [ADR-028](ADR-028-objective-engine-board-chronicle.md)

## Context

The server already publishes the Warpweaver position through gossip POIs:
`points_of_interest` plus `gossip_menu_option.ActionPoiID` sends `SMSG_GOSSIP_POI`, which the client
draws on the **minimap** for the current city. It does not appear on the world map. The ten capital
Warpweavers (entry `910012`), the PvP vendors, and future world-boss or Crow's Cache content are
therefore hard to find when a player opens the map.

Possible client-side routes:

- Add `AreaPOI.dbc` rows. This is a DBC change, needs the client and server DBC set to stay in sync,
  and is static.
- Reuse `SMSG_GOSSIP_POI`. Already minimap-only; no world-map surface.
- Ship a normal user addon. Manual install, lost on client rebuild, and not part of the supported
  bundle.
- Bake a small addon into the project client patch. This is data-only, lives in `patch-Z.MPQ`, and
  can draw on the same `WorldMapFrame` the player already uses.

## Decision

1. **Baked addon, not a user addon.** `Interface\AddOns\ServerMapPOI` ships inside
   `data/client-patches/map-poi/dist/patch-Z.MPQ` under [ADR-027](ADR-027-client-patch-pipeline.md).
   It is enabled with the client's other addons; the player does not install it separately.
2. **Static v1 data.** The first layer draws:
   - all ten capital Warpweaver spawns (creature entry `910012`);
   - PvP vendor clusters: honor quartermasters in Stormwind and Orgrimmar, battleground
     battlemasters in the capitals and Shattrath, and the Dalaran Underbelly arena vendors;
   - two stock outdoor bosses as skull examples (Doom Lord Kazzak, Doomwalker).
   Positions are a snapshot of `acore_world.creature`; the Warpweaver rows come from the live table
   and are recorded with the snapshot date. Regenerate after a spawn move.
3. **Stock icons only in v1.** Warpweaver: `INV_Misc_Map_01`. Vendors: `INV_Misc_Coin_01`. Boss:
   `UI-RaidTargetingIcon_8` (skull). Cache: `INV_Misc_Bag_10`. No custom BLP or new texture assets
   in v1. The second pass adds one MIT-licensed meeting-stone texture; see its revision below.
4. **Draw only while the map is open.** The addon hooks `WorldMapFrame_Update`,
   `WorldMapFrame_OnShow`, and `WorldMapFrame_OnHide`. It creates one button per POI and reuses it.
   It never registers an `OnUpdate` handler and never loops over the POI list per frame. Icon
   textures are set once per kind and cached.
5. **Zone-correct coordinates.** 3.3.5 zone maps are rotated: map X follows world Y and map Y
   follows world X. `WorldMapArea.dbc` stores Y bounds in LocLeft/LocRight and X bounds in
   LocTop/LocBottom. `generate_poi_data.py` applies:
   `mapX = (yMax - worldY) / (yMax - yMin)`, `mapY = (xMax - worldX) / (xMax - xMin)`.
   Dalaran's city micro-map uses `DungeonMap.dbc` floor 27 on map 571. The Warpweaver percentage is
   derived from the `collections_npc_spawns.sql` spawn (Simply Enchanting, `5842.8, 721.8`); only the
   arena-vendor pair is an imported `DALARAN_MAP_OVERRIDES` approximation.
6. **Red overlay for selected end-game PvP zones.** Wintergrasp, Strand of the Ancients, and Isle of
   Conquest get a translucent red `WHITE8X8` overlay. The list is explicit in `Data.lua`; adding a
   zone is a one-line data change and a rebuild.
7. **Dynamic hooks, no server tick work.** `ServerMapPOI:SetWorldBoss(zone, worldX, worldY, label)`,
   `ServerMapPOI:SetCrowsCache(...)`, and `ServerMapPOI:SetDynamicMapPOI(...)` accept runtime data.
   v1 does not call them. A future world-boss/Crow's Cache feature either bakes the positions and
   rebuilds the patch, or sends the positions to the addon through a server message under a new ADR.
   The server never runs per-tick work for the map layer.
8. **Outlaw dynamic marker (visual contract only).** The addon defines an `outlaw` marker type and
   the version 2 `SMPOI` addon-message protocol. The PvP server module is **not implemented** here.
   The server issues a per-session token with `AUTH`; every `OUTLAW`, `CLEAR` and `KILL` must carry
   it or the client ignores the message. Without `AUTH`, Outlaw markers stay off; static POIs are
   unaffected. The token stops casual spoofing only, not a modified client/addon, so the server must
   still validate every kill and position. The client accepts `OUTLAW` position messages only for its
   own continent: exact zone-map coordinates in the same zone, coarse continent-map coordinates in
   another zone on the same continent, and nothing on another continent. It hides all Outlaw markers
   in instances, battlegrounds, and arenas via `IsInInstance()`. The server contract is one update
   per outlaw per 5 seconds, `CLEAR` on death, zone change, or flag loss, a 15-second client TTL, and
   no per-tick broadcast. A separate `KILL` message uses the chat format
   `[OUTLAW] <killer> killed <victim> in <zone> (<subzone>).` The wire format and fixture live in
   `data/client-patches/map-poi/README.md` and `tests/fixtures/outlaw.lua`.
9. **No DBC change.** The layer uses the client's own zone maps. It does not add `AreaPOI.dbc` rows,
   does not replace `WorldMapFrameTemplates.xml`, and does not change `DungeonMap.dbc`.
10. **Verification is in the client.** The patch canary prints a login line from the overridden
   `WorldMapFrame.lua`; the addon prints a load line. The owner opens the map in each capital,
   hovers and clicks markers, checks the red zones, and reports wrong positions. Wrong static data
   is a rebuild, not a runtime edit.

## Alternatives considered

- **`AreaPOI.dbc` rows.** Rejected for v1: a DBC replacement, client/server sync work, and no dynamic
  hook. Revisit if the markers must appear without an addon.
- **Server `SMSG_GOSSIP_POI` only.** Rejected: it draws on the minimap, not the world map, and needs a
  gossip interaction.
- **A normal addon distributed separately.** Rejected: the bundle is the supported client; a user
  addon can be disabled, deleted, or lost on rebuild.
- **Server-driven marker updates now.** Deferred for world bosses and Crow's Cache. The Outlaw
  client contract exists; the server module that would send it does not.
- **Custom map textures or icons.** Rejected: v1 has no art pipeline and stock icons are enough.

## Consequences

- The static markers drift when a spawn moves: regenerate with `generate_poi_data.py`, rebuild, and
  record a new manifest hash. Outlaw markers are dynamic but need a future server module.
- Dalaran's Warpweaver follows the SQL spawn; only the arena-vendor pair is approximate. Adjust the
  one `DALARAN_MAP_OVERRIDES` vendor pair and rebuild if the owner's in-game check disagrees.
- The addon appears in the client addon list. It is enabled by default and is not a user-facing
  feature toggle.
- The red overlay is a visual annotation only; it grants nothing and changes no PvP rules.
- The first patch proves MPQ addon loading and FrameXML load order with one canary, so later UI
  features can reuse the same pipeline.

## Revision 2026-11-26 — world-wide coverage, transports, portals, meeting stones

The first layer drew 24 hand-written markers in ten capitals plus two bosses. The owner asked for
the kinds a player actually needs to find, so the layer now generates from a read-only harvest of
`acore_world` instead of a hand-written list.

- **Kinds added:** flight masters (155), innkeepers (124), battlemasters (187, one marker per
  zone and name because the same emissary stands at 20-25 spots per city), meeting stones (47) with
  their level range, and portals (43) with their destination. The ten Warpweavers and the two
  outdoor bosses stay as hand-placed markers, so the existing layer keeps them.
- **Ships and zeppelins are not drawn in this revision.** Their dock coordinates are not derivable
  from the tables, and a wrong dock marker is worse than none. Follow-up: harvest dock positions
  from the named dock gameobjects or from an in-game pass.
- **Meeting stone ranges join by name, not by map.** A stone's `data2` is the dungeon's own area;
  its name is the dungeon name, and the LFD row of the same name carries the range. Keying by map
  was wrong twice: Hellfire Citadel has four wings on map 540, and holiday rows (Coren Direbrew,
  Headless Horseman, Crown Chemical Co.) share a map with a real dungeon and were winning the name.
- **Instance maps are dropped.** Markers on maps the world map cannot open are filtered out, which
  removed six dead portal pins (Oculus, Ulduar, Icecrown Citadel, Sunwell).
- **Zone coverage:** every zone that `WorldMapArea.dbc` gives usable bounds for, not a fixed list.
  Spawns with no zone id are resolved by the smallest containing zone rectangle.
- **Meeting stone ranges:** a stone's `data2` is the dungeon's areaID; that area's map is the
  instance map; `LFGDungeons.dbc` for that map carries min and max level (fields 18 and 19). This
  replaces the earlier guess that `data2` was an LFD or map id.
- **Faction tint** replaces per-faction icon textures: one stock icon per kind, `SetVertexColor`
  alliance blue, horde red, shared gold.
- **Data pipeline:** `harvest_poi_data.py` is the only part that touches MySQL and it only reads. It
  writes `poidata/snapshot.json`, which `generate_poi_data.py` consumes, so the patch builds without
  a database.
- **Red zones:** the six contested open-world zones the owner named (Silithus, Eastern
  Plaguelands, Hellfire Peninsula, Nagrand, Wintergrasp, Zangarmarsh) plus the two stock
  battlegrounds that had the overlay before.
- **Icons:** stock client textures only in that revision. A custom BLP set was deferred until the
  owner approved concept art; the second pass adds one MIT-licensed meeting-stone texture.

## Revision 2026-11-26 (second pass) — render correctness, Questie pins, call boards, Cooldown

The 2026-11-26 build passed the offline checks but failed the owner's in-client test: zone pins
appeared in the ocean on the continent map, Elwynn showed almost nothing, and the icons were 18 px
squares. The root cause was an API mismatch, not the projection. `GetCurrentMapZone()` returns a
zone **index**, not an area id; it is `0` on the continent map. The addon compared that index to
`poi.zone` as well as to `GetCurrentMapAreaID()`, so a handful of small area ids matched by
coincidence and zone-relative pins landed on the continent texture.

- **Render rule.** Static pins draw only when a zone map is open: `GetCurrentMapZone() > 0` and
  `poi.zone == GetCurrentMapAreaID()`. The continent map, cosmic map and any map with no matching
  zone draw none. The red overlay and the Outlaw zone mode use the same guard; an outlaw on the
  continent uses the coarse continent coordinates, never zone coordinates.
- **Icons.** The 18 px ability icons are replaced by the stock tracking glyphs Questie uses
  (`Interface\Minimap\Tracking\FlightMaster`, `Innkeeper`, `Battlemaster`) at 12 px. Meeting stones
  use Questie's `Icons/mstone.blp` (MIT, from Shagu's pfQuest; SHA256
  `847bb9d2a81e4f356b87c0ae014ce7aa0e8613597b062ff07242b4021b6ec8fc`), credited in the README.
  Call boards use a stock scroll icon. Faction tint is unchanged. This is the only non-stock art.
- **Call boards.** Fifteen boards use the stock Wanted Board model: eight faction capitals,
  Shattrath, Dalaran, and the five neutral hubs (Booty Bay, Gadgetzan, Everlook, Area 52, Ratchet).
  Gameobject entry `930101`, spawn GUIDs `5714521-5714535`, tracked SQL in
  `data/sql/custom/db_world/call_boards.sql`. The positions and floor heights came from AWE's
  `area_overview` and `acore-data`'s `terrain position`, not guesses. The boards are type-2
  questgivers with no quest; the objectives engine
  ([ADR-028](ADR-028-objective-engine-board-chronicle.md)) attaches the menu in a later slice.
- **Goldshire.** 3.3.5 has no Goldshire flight point; it was added in Cataclysm (4.0.3a). The empty
  Elwynn flight-master set is authentic, not a bug. Elwynn keeps Innkeeper Farley and the arena
  battlemaster. No custom flight point is added.
- **Questie overlap.** The native layer still owns every kind. A player running upstream Questie
  sees its flight master, innkeeper and meeting-stone pins as well, because Questie draws them by
  default. Double pins are accepted; the player can disable Questie's townsfolk POIs. No suppression
  code is added. The future branded Questie build can disable its map pins and keep the full quest
  database, which is the Ascension/Epoch model.
- **Cooldown.** `patch-Z` now carries a whole-file `Interface\FrameXML\Cooldown.lua` from
  `Data/enUS/locale-enUS.MPQ` with `CooldownFrame_SetTimer` made nil-safe. `WatchFrame.lua` passes
  nil on this Ascension client and the stock comparison raised a Lua error. No other line changed.
- **Carrier.** The baked addon stays for this slice. FrameXML migration, the branded Questie build,
  and the other addon patches are a separate session. The end state is still all client work
  patched; the addon is temporary.
- **Transport and continent pins** remain deferred. Ships and zeppelins still have no reliable dock
  coordinates; continent-level pins need a second projection and are not in this slice.
- **Counts.** 583 markers: 155 flight masters, 124 innkeepers, 187 battlemasters, 47 meeting stones,
  43 portals, 10 Warpweavers, 2 bosses, 15 call boards.

## References

- [ADR-027](ADR-027-client-patch-pipeline.md)
- [specs/client-patch.md](../specs/client-patch.md)
- [data/client-patches/map-poi/README.md](../data/client-patches/map-poi/README.md)
- [runbook/tools/mcp-servers.md](../runbook/tools/mcp-servers.md)
- [runbook/audits/2026-11-26-playtest-round-2.md](../runbook/audits/2026-11-26-playtest-round-2.md)
- `data/sql/custom/db_world/collections_npc_spawns.sql`
- `data/sql/custom/db_world/collections_guard_directions.sql`
- `data/sql/custom/db_world/call_boards.sql`
