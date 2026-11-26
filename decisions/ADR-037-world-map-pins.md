# ADR-037 — World map pins: world bosses and custom services only

- Status: accepted
- Date: 2026-11-27
- Supersedes: [ADR-032](ADR-032-map-poi-layer.md) (withdrawn)
- Related: [ADR-027](ADR-027-client-patch-pipeline.md),
  [ADR-028](ADR-028-objective-engine-board-chronicle.md)

## Context

ADR-032 shipped a general map POI layer. It grew from 24 hand-written markers to 1,128 stock NPC
markers (flight masters, innkeepers, battlemasters, meeting stones, portals). The owner rejected it
on 2026-11-27: many positions were wrong, the map was noisy, hover tooltips did not open, and the
layer duplicated what Questie already does correctly.

The project still needs to advertise content it adds itself: the ten capital Warpweavers
(transmogrifier, entry `910012`) and the fifteen Call Boards (entry `930101`). Those are custom
spawns no third-party addon knows about. The seven outdoor world bosses are the one stock exception
the owner asked to keep.

## Decision

1. **Scope is custom content plus world bosses.** The layer draws:
   - the 7 outdoor world bosses: Azuregos, Lethon, Taerar, Emeriss, Ysondre (Classic), Doom Lord
     Kazzak and Doomwalker (The Burning Crusade);
   - the 10 Warpweaver spawns from `data/sql/custom/db_world/collections_npc_spawns.sql`;
   - the 15 Call Board spawns from `data/sql/custom/db_world/call_boards.sql`.
2. **No stock NPC categories, ever.** Flight masters, innkeepers, battlemasters, meeting stones,
   portals and city leaders stay out. Questie and similar addons own that data. A new pin is added
   only when the project adds the spawn it points at.
3. **No WotLK boss pin.** All four Wrath world bosses (Archavon, Emalon, Koralon, Toravon) are
   inside Vault of Archavon. An instance pin would point at an entrance, not a world spawn; the
   owner excluded it on 2026-11-27.
4. **Exact static positions.** Zone and continent fractions are baked in
   `src/WorldMapPins/WorldMapPins.lua`, computed from the spawn coordinates with the 3.3.5 rotated
   axes. There is no generator, no runtime projection and no stack fan-out.
5. **Hover must work.** Each pin is a 24x24 button at `WORLDMAP_POI_FRAMELEVEL + 50`, above the
   client landmark buttons (91) and the quest POI layer (100), with the mouse enabled. `OnEnter`
   opens one `GameTooltip` with name, kind and place. `OnClick` forwards to
   `WorldMapButton_OnClick`, so the stock map ping still works. Warpweaver uses the
   `INV_NetherPortal` icon: a dark void portal, matching the ethereal transmogrifier.
6. **Same archive, no DBC.** `patch-Z.MPQ` carries `Interface\AddOns\WorldMapPins`, the
   `WorldMapFrame.lua` load-order canary and the `Cooldown.lua` nil guard. Zero DBC files.
7. **Zone detection by displayed map.** `GetCurrentMapContinent` plus the `GetCurrentMapZone`
   index into `GetMapZones` resolves the open zone; `0` is the continent map. Names are normalized
   (`The` prefix, `City` suffix). Silvermoon and the Exodar use `WorldMapArea.DisplayMapID`
   (Eastern Kingdoms and Kalimdor), not their `MapID` (530).
8. **Continent index order is the client's, not geographic.** `GetCurrentMapContinent` follows
   `WorldMapArea`'s area-id-0 file order: **1 Kalimdor, 2 Eastern Kingdoms, 3 Outland,
   4 Northrend**. Assuming 1=Eastern Kingdoms draws every EK pin on the Kalimdor map and every
   Kalimdor pin on the EK map, which is the ocean-pin bug fixed on 2026-11-27.

## Alternatives considered

- **Keep the generated stock layer (ADR-032).** Rejected: wrong data, noise, duplicated Questie,
  and the owner explicitly withdrew it.
- **Add only bosses and drop custom services.** Rejected: Warpweavers and Call Boards are our
  content and no addon can find them.
- **`AreaPOI.dbc` rows.** Rejected: DBC replacement, client/server sync, and the pins are static
  custom spawns that fit in a small addon.
- **Server `SMSG_GOSSIP_POI`.** Rejected: minimap-only and needs a gossip interaction.
- **Instance pin for Vault of Archavon.** Rejected by the owner; it would advertise an entrance,
  not a world boss location.

## Consequences

- Pins drift only when a custom spawn moves. Edit the one row and rebuild; there is no generator to
  rerun.
- Questie remains the reference for stock NPCs; the project layer does not compete with it.
- The map addon still appears in the client addon list and is enabled with the bundle.
- Adding a new custom service to the map is a data-row change plus `build.py`, not a new subsystem.
