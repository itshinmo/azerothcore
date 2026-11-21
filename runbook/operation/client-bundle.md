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
| Transmog addon | `modules/mod-transmog-plus/addon/Transmog` | active — in-game transmog UI + collections |
| Journal addon | `modules/mod-forever-journal/addon/Journal` | active — the Collections journal (Mounts, Pets, Toys, Appearances) |
| GM Helper | `tools/gm-addon/` | active — testing addon |

Paths: client `~/Games/wotlk-clean` (WoWSilicon launcher, realmlist `127.0.0.1`); vanilla reference
exe kept at `~/Downloads/wow-related/Wow-clean.exe` (build-12340, unmodified).

## Screens and glue ownership

The **Ascension patch-A MPQ owns the glue screens** (login, character select, character creation —
its modern creation layout carries the 500+ options). No other mod may redefine those screens:
ForeverUI's loose `Interface/GlueXML` conflicted with them (duplicate widgets, overlapping text,
Lua errors) and was removed — and later the owner removed **mod-forever-ui entirely** (addon, art,
saved variables). Two mods both shipping GlueXML for the same screens do not compose.

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
3. Copy the 11 custom MPQs into `Data/`: Ascension `patch-A.MPQ` + Reforged
   `patch-B/C/D/E/G/I/M/N/P/U.MPQ` (never Reforged patch-A — the Ascension pack replaces it;
   patch-S removed 2026-11-21, see the table above).
4. Copy the Ascension pack's 8 DBCs into the **server** `DataDir/dbc/`
   (BarberShopStyle, CharSections, CreatureDisplayInfoExtra, EmotesTextSound, CharHairGeosets,
   CharHairTextures, CharacterFacialHairStyles, HelmetGeosetVisData) and restart the worldserver.
5. Install addons into `Interface/AddOns/` from this repository: `Transmog` and `Journal` from the
   module trees (`modules/mod-transmog-plus/addon/`, `modules/mod-forever-journal/addon/`) and
   `GMHelper` from `tools/gm-addon/`. Do NOT install ForeverUI or any other mod's loose
   `Interface/GlueXML` files — they conflict with the Ascension glue.
6. Point `Data/enUS/realmlist.wtf` at the realm; play.

## Rebuild kit (generated client artifacts)

Any client artifact this project generates (patch MPQs, modified DBCs, bundled addons) is stored in
this repository so a deleted client can be rebuilt without re-downloading anything: addons ship
from the module trees and `tools/gm-addon/` above; server DBC swaps ship from the feature's own
data (see the feature's module or `data/sql/custom/`). When a feature generates a client MPQ, it
lands in `data/client-patches/<feature>/` with its own README, and this runbook links it. Nothing
is generated today — the Warpweaver guard directions are pure server data (`points_of_interest` +
`SMSG_GOSSIP_POI`, see `data/sql/custom/db_world/collections_guard_directions.sql`).

## Verification checklist (per client rebuild)

- Client starts; no addon dependency errors.
- Creation screen: modern layout, 500+ options cycle, HD models; no Lua errors (glue dialogs).
- Login/character select render cleanly; no overlapping widgets.
- In-world: HD models and gear, Reforged spell VFX, GM Helper tabs, Transmog/Journal windows, FPS
  in the expected range; capital guards offer "The transmogrifier" with a minimap marker — in
  Dalaran, ask the Violet Citadel teleport-service NPCs (the city has no guards).

## References

- [RFC-001](../../rfcs/active/RFC-001-client-modernization.md)
- [ADR-020](../../decisions/ADR-020-collections-transmog-stack.md)
- [ADR-018](../../decisions/ADR-018-realm-strategy.md) (realm layout)
- [environment-overview.md](../development/environment-overview.md)
