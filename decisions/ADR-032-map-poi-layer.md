# ADR-032 — Map POI layer: baked addon, stock icons, red PvP overlay

- Status: accepted
- Date: 2026-11-23
- Related: [ADR-027](ADR-027-client-patch-pipeline.md),
  [ADR-020](ADR-020-collections-transmog-stack.md),
  [ADR-023](ADR-023-cross-faction-social-layer.md)

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
3. **Stock icons only.** Warpweaver: `INV_Misc_Map_01`. Vendors: `INV_Misc_Coin_01`. Boss:
   `UI-RaidTargetingIcon_8` (skull). Cache: `INV_Misc_Bag_10`. No custom BLP and no new texture
   assets in v1.
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

## References

- [ADR-027](ADR-027-client-patch-pipeline.md)
- [specs/client-patch.md](../specs/client-patch.md)
- [data/client-patches/map-poi/README.md](../data/client-patches/map-poi/README.md)
- `data/sql/custom/db_world/collections_npc_spawns.sql`
- `data/sql/custom/db_world/collections_guard_directions.sql`
