# Client bundle — the supported play client

The owner plays on the **modernized bundle client**; at launch this becomes the shipped player
client (with a launcher). Verified working on 2026-11-20 with the owner in-game: 120 FPS, all
screens functional. Owner decisions recorded in [RFC-001](../../rfcs/active/RFC-001-client-modernization.md)
and [ADR-020](../../decisions/ADR-020-collections-transmog-stack.md).

## The verified bundle

| Component | Source | State |
|---|---|---|
| `Wow.exe` | WoWSilicon build (SSE2-optimized for Apple Silicon) | active — the fast path; the St0ny-patched vanilla exe measured 14 FPS (x87 emulation) and was reverted |
| d3d9.dll | WoWSilicon's own (installed by its Game Patch) | active — WoWSilicon re-offers the patch whenever its hash check fails; click Patch |
| patch-A.MPQ | "Ascension Character Customization" v6 (Nexus mod 907) | active — WoD HD models + 500+ creation options |
| 8 server DBCs | same mod | active — copied into server `DataDir/dbc/`; worldserver restart applies them |
| patch-B/C/D/E/G/I/M/N/P/U.MPQ | Project Reforged v1.5.8 (skip patch-A) | active — VFX, environment, gear, interface, sounds |
| patch-S.MPQ | Project Reforged v1.5.8 | **removed 2026-11-21 (owner)** — caused client performance issues in Orgrimmar; all other Reforged parts stay |
| patch-X.MPQ | project item data (client-patch branch) | active — the only `DBFilesClient\Item.dbc` carrier; SHA256 `9ddd80c9fda95647c393a00fb2c0d2db706185b59c05364ce00d3899e95c1d50` |
| patch-Y.MPQ | project white-model restore (client-patch branch) | active — stock goblin male model, skins and 32 animations; SHA256 `b236c1c35d2714a0e6423e87a934256fbace13168951d2c5144b0ca30016f524` |
| patch-Z.MPQ | project map/UI (client-patch branch) | active — `WorldMapPins` addon, `WorldMapFrame.lua` canary and `Cooldown.lua` nil guard; SHA256 `8d119e9591fae47e191ee9740ec6dabc36541f566679e43b3337b7a5ac8e1925` |
| Transmog addon | `modules/mod-transmog-plus/addon/Transmog` | active — in-game transmog UI + collections |
| Journal addon | `modules/mod-forever-journal/addon/Journal` | active — the Collections journal (Mounts, Pets, Toys, Appearances) |
| GM Helper | `tools/gm-addon/` | active — testing addon |
| Chat Notice Guard | `tools/client-addons/ChatNoticeGuard/` | active workaround — supplies the `CHAT_<token>_NOTICE` strings the Ascension client omits, otherwise a LookingForGroup notice throws `format(nil)` |

Project patch family, separate from the vendor bundle:

| Archive | Owner | State | SHA256 |
|---------|-------|-------|--------|
| `patch-X.MPQ` | `data/client-patches/item-data/` | installed in `~/Games/wotlk-clean/Data` | `9ddd80c9fda95647c393a00fb2c0d2db706185b59c05364ce00d3899e95c1d50` |
| `patch-Y.MPQ` | `data/client-patches/white-boss-models/` | installed in `~/Games/wotlk-clean/Data` | `b236c1c35d2714a0e6423e87a934256fbace13168951d2c5144b0ca30016f524` |
| `patch-Z.MPQ` | `data/client-patches/map-pins/` | installed in `~/Games/wotlk-clean/Data` | `8d119e9591fae47e191ee9740ec6dabc36541f566679e43b3337b7a5ac8e1925` |
| `patch-V.MPQ` | `data/client-patches/race-class-combos/` | **proposal, not installed** | `50e4477b93678272ad35089bfbbd6c8fa7f884c98d1d3171491b29da49d4731c` |

X = item data, Y = white models, Z = map/UI; X < Y < Z, all after Reforged `patch-U`. `patch-V`,
if approved, loads before X. Each feature's manifest is its source of truth; rebuild only through
that feature's `build.py`. Verify an archive with `git hash-object --path=<path> <file>` equal to
`git hash-object --no-filters <file>`.

Paths: client `~/Games/wotlk-clean` (WoWSilicon launcher, realmlist `127.0.0.1`); vanilla reference
exe kept at `~/Downloads/wow-related/Wow-clean.exe` (build-12340, unmodified).

## Screens and glue ownership

The **winning glue archive** owns the glue screens (login, character select, character creation). On
the verified bundle the measured winner for `Interface\GlueXML\CharacterCreate.lua` is
`patch-I.mpq` (Reforged interface); `patch-A.MPQ` supplies customization DBCs and models but has no
`Interface\GlueXML` entries. The creation screen carries the 500+ options. No other mod may redefine
those screens: ForeverUI's loose `Interface/GlueXML` conflicted with them (duplicate widgets,
overlapping text, Lua errors) and was removed — and later the owner removed **mod-forever-ui
entirely** (addon, art, saved variables). Two mods both shipping GlueXML for the same screens do not
compose. Verify the winner with the client-patch tool (`client_patch.py which`) after any bundle
change.

## Proven incompatible or dropped (do not re-add without a new decision)

- **St0ny AIO EXE Patcher (46 patches)**: patches vanilla `Wow.exe` fine, but that exe runs x87
  through software emulation on Apple Silicon → 14 FPS measured; reverted. Its patcher also
  corrupts the exe when run after any foreign byte patch (verified both orders).
- **ForeverUIPatcher (named creation choices)**: needs vanilla-byte offsets; incompatible with
  St0ny in either order (verified; the merged exe failed St0ny's own integrity scan). Creation and
  barber choices show numbers instead of names.
- **mod-forever-ui** (all components: addon, art, loose `GlueXML`, `Minimap` art, exe patch):
  glue screens conflicted with the Ascension glue; the owner removed it entirely on 2026-11-20.
- **LuxVelum**: needs St0ny's loader hook; inert on the WoWSilicon exe. Removed.
- **DXVK 3.1.1**: blocked by WoWSilicon's Game Patch gate (it re-installs its own d3d9). Removed;
  a DXVK version matters little for the bundle's look.

## Install order (step by step — how the bundle was built)

The verified path, in the order actually performed (recorded so any client copy can be rebuilt):

1. Start from a clean 3.3.5a build 12340 client copy (`Wow.exe` unmodified, stock `Data/`).
2. Open it once in the **WoWSilicon launcher**: apply its **CrossOver Patch**, then its
   **Game Patch** (installs WoWSilicon's `d3d9.dll`, `libDllLdr.dll`, `winerosetta.dll` chain).
   WoWSilicon re-offers the Game Patch whenever its hash check fails — click Patch.
3. Copy the 14 custom MPQs into `Data/`: Ascension `patch-A.MPQ`, Reforged
   `patch-B/C/D/E/G/I/M/N/P/U.MPQ`, and the project `patch-X.MPQ` (item data), `patch-Y.MPQ`
   (goblin models) and `patch-Z.MPQ` (map/UI). Never copy Reforged patch-A — the Ascension pack
   replaces it. `patch-S` was removed 2026-11-21. The project patch ledger is
   [data/client-patches/README.md](../../data/client-patches/README.md); keep X, Y and Z when
   rebuilding or the item data, white-model fix and map layer are lost.
4. Copy the Ascension pack's 8 DBCs into the **server** `DataDir/dbc/`
   (BarberShopStyle, CharSections, CreatureDisplayInfoExtra, EmotesTextSound, CharHairGeosets,
   CharHairTextures, CharacterFacialHairStyles, HelmetGeosetVisData) and restart the worldserver.
5. Install addons into `Interface/AddOns/` from this repository: `Transmog`, `Journal` and
   `Objectives` from the module trees (`modules/mod-transmog-plus/addon/`,
   `modules/mod-forever-journal/addon/`, `modules/mod-objectives/addon/`),
   `GMHelper` from `tools/gm-addon/`, and `ChatNoticeGuard` from `tools/client-addons/`. Do NOT
   install ForeverUI or any other mod's loose `Interface/GlueXML` files — they conflict with the
   Ascension glue.
6. Point `Data/enUS/realmlist.wtf` at the realm; play.

## Rebuild kit (generated client artifacts)

Any client artifact this project generates (patch MPQs, modified DBCs, bundled addons) is stored in
this repository so a deleted client can be rebuilt without re-downloading anything: addons ship
from the module trees and `tools/gm-addon/` above; server DBC swaps ship from the feature's own
data (see the feature's module or `data/sql/custom/`). A generated client MPQ lands in
`data/client-patches/<feature>/` with its own README and manifest, and this runbook links it. The
Warpweaver guard directions are pure server data (`points_of_interest` + `SMSG_GOSSIP_POI`, see
`data/sql/custom/db_world/collections_guard_directions.sql`).

Current project patches:

- [item-data](../../data/client-patches/item-data/README.md) — `patch-X.MPQ`: whole
  `DBFilesClient\Item.dbc` with custom item rows for the world treasures. Only X carries Item.dbc.
- [white-boss-models](../../data/client-patches/white-boss-models/README.md) — `patch-Y.MPQ`: stock
  goblin male model over the Ascension HD replacement, fixing white Journal previews.
- [map-pins](../../data/client-patches/map-pins/README.md) — `patch-Z.MPQ`: `WorldMapPins`
  world-map layer (7 world bosses, 10 Warpweavers, 15 Call Boards) plus a FrameXML load-order
  canary. No DBC change.
- [race-class-combos](../../data/client-patches/race-class-combos/README.md) — `patch-V.MPQ`
  **proposal only**: whole-file `CharBaseInfo.dbc` and `CharStartOutfit.dbc`. Do not install until
  the owner approves the target list and the carrier.

Procedure: [client-patch.md](client-patch.md).

## Verification checklist (per client rebuild)

- Client starts; no addon dependency errors.
- Creation screen: modern layout, 500+ options cycle, HD models; no Lua errors (glue dialogs).
- Login/character select render cleanly; no overlapping widgets.
- In-world: HD models and gear, Reforged spell VFX, GM Helper tabs, Transmog/Journal windows, FPS
  in the expected range; capital guards offer "The transmogrifier" with a minimap marker — in
  Dalaran, ask the Violet Citadel teleport-service NPCs (the city has no guards).
- Project patches (when installed): `patch-Z.MPQ` canary line at login and `WorldMapPins` pins on
  the world map; `patch-X.MPQ` makes custom item IDs render an icon instead of the red question mark.
  Test steps: [map-pins README](../../data/client-patches/map-pins/README.md),
  [item-data README](../../data/client-patches/item-data/README.md).

## References

- [RFC-001](../../rfcs/active/RFC-001-client-modernization.md)
- [ADR-020](../../decisions/ADR-020-collections-transmog-stack.md)
- [ADR-018](../../decisions/ADR-018-realm-strategy.md) (realm layout)
- [environment-overview.md](../development/environment-overview.md)
